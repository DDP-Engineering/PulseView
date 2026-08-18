<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# DSO3062L command catalogue

Derived 2026-08-16 by static analysis of `HTHardDLL.dll` (32-bit, image base
`0x10000000`, `.text` 26 048 bytes) using
`05_Software/protocol_probe/map_commands.py`. The DLL was parsed and
disassembled only; it was never loaded or executed.

Everything here is **inferred from code, not yet confirmed on the wire**.
Only the two rows marked *device-confirmed* have been observed against the
physical instrument. Treat the rest as a hypothesis to test.

## Transport

USB descriptors read from the device over WinUSB:

| Property | Value |
|---|---|
| VID:PID | `04b5:3062` |
| bcdUSB | `0x0200`, high speed |
| Manufacturer / Product | `"ODM   "` / `"DSO-3062L"` |
| Serial | none |
| Configuration / Interface | 1 / 0, class `0xff` vendor specific |
| Bulk OUT | `0x02`, wMaxPacketSize 512 |
| Bulk IN | `0x86`, wMaxPacketSize 512 |

These match libsigrok `hantek-dso`'s `USB_CONFIGURATION 1`, `USB_INTERFACE 0`,
`DSO_EP_OUT 0x02`, `DSO_EP_IN 0x86` exactly.

Vendor control requests, confirmed answered by the device:

| bRequest | Name | Observed |
|---|---|---|
| `0xb2` | `CTRL_GETSPEED` | returns `0x01` = high speed |
| `0xb3` | `CTRL_BEGINCOMMAND` | accepts the fixed 10-byte payload `0f 03 03 03 68 ac fe 00 01 00` |

## Vendor driver path

The Windows SDK does not speak USB directly. It opens the vendor kernel driver
with `CreateFileA` and issues **two** IOCTLs, a write/read pair:

```
0x222051   FILE_DEVICE_UNKNOWN (0x22), function 0x814, METHOD_IN_DIRECT   - send command
0x22204e   FILE_DEVICE_UNKNOWN (0x22), function 0x813, METHOD_OUT_DIRECT  - read reply
```

These correspond directly to bulk OUT `0x02` and bulk IN `0x86`. A query is
therefore: write the request buffer to `0x02`, then read from `0x86`.

The opcode travels in the request buffer, not the IOCTL code. `HTHardDLL`
marshals through a generic wrapper at `0x10001000`:

```
[+0x04] hDevice        [+0x14] lpOutBuffer
[+0x08] dwIoControlCode[+0x18] nOutBufferSize
[+0x0c] lpInBuffer     [+0x1c] bytesReturned
[+0x10] nInBufferSize
```

Byte 0 of the input buffer is the device opcode. This is why the driver is only
a transport detail: the same opcodes can be written straight to bulk endpoint
`0x02`, which is what the libsigrok driver will do.

## Core acquisition opcodes

These five are **identical to libsigrok `hantek-dso`**, both in value and
meaning. That is the single most important finding in this document.

| Opcode | SDK export | libsigrok `hantek-dso` equivalent |
|---|---|---|
| `0x02` | `dsoHTForceTrigger` | `CMD_FORCE_TRIGGER` |
| `0x03` | `dsoHTStartCollectData` | `CMD_CAPTURE_START` |
| `0x04` | `dsoHTStartTrigger` | `CMD_ENABLE_TRIGGER` |
| `0x05` | `dsoHTGetData` | `CMD_GET_CHANNELDATA` |
| `0x06` | `dsoHTGetState` | `CMD_GET_CAPTURESTATE` *(device-confirmed)* |

### Status byte layout

`dsoHTGetState` and `dsoHTGetPackState` share the worker at `0x10003550` and
differ only in how they mask its result:

```
dsoHTGetState     -> and eax, 7        ; bits 0-2 = capture state
dsoHTGetPackState -> shr al,3; and 1   ; bit 3    = pack state
```

*Device-confirmed:* sending `[06 00]` to EP `0x02` and reading EP `0x86`
returned `10 00 02 00 04 00 ...`. Applying the SDK's own mask,
`0x10 & 7 == 0` — `CAPTURE_EMPTY`, which is correct for an idle instrument.
Bit 4 is set and is not part of the `hantek-dso` state field; it is a
DSO3062L extension of unknown meaning.

## Device-confirmed opcodes

Sent to the physical instrument over WinUSB on 2026-08-16 by
`05_Software/protocol_probe/validate_opcodes.py`, with nothing connected to the
inputs and the instrument idle. Each request is `[opcode, 0x00]` on EP `0x02`
after the `0xb3` handshake, reply read from EP `0x86`. All four returned
distinct, structured data — no echo, no constant filler.

| Opcode | SDK export | First bytes of reply | Reading |
|---|---|---|---|
| `0x06` | `dsoHTGetState` | `10 00 02 00 04 00 04 00` | `0x10 & 7 = 0` → `CAPTURE_EMPTY`, pack bit 0. Correct for an idle scope. |
| `0x09` | `dsoGetHardVersion` | `03 01 20 08 00 00 …` | LE words `0x0103`, `0x0820`. Reads as hardware version 1.03. |
| `0x2b` | `dsoGetFPGAVersion` | `18 02` repeated | LE word `0x0218` repeated across the buffer — FPGA version register. |
| `0x0a` | `dsoHTGetHardFC` | `00 00 00 00 ff ff ff ff` | Zero count with nothing connected, then an all-ones field. Plausible for no input. |

This validates the static-analysis method end to end: opcodes recovered from
the DLL produce meaningful answers when written straight to the bulk endpoint,
with no vendor driver and no vendor DLL in the path.

Field-level meaning beyond byte 0 is still unconfirmed for every one of these.

### Acquisition state machine — confirmed on hardware

`05_Software/protocol_probe/try_capture.py`, nothing connected to the probes,
using only the instrument's existing front-panel configuration:

```
0x06 -> 10   state 0  CAPTURE_EMPTY        idle
0x03         StartCollectData   (no reply)
0x04         StartTrigger       (no reply)
0x06 -> 11   state 1  CAPTURE_FILLING      armed, awaiting trigger
0x02         ForceTrigger       (no reply)
0x06 -> 17   state 7  CAPTURE_READY_9BIT   capture complete
```

Every transition matches libsigrok `hantek-dso`'s model, including the value
`7` for a 9-bit-ready capture. `0x02`, `0x03` and `0x04` return no reply; they
are write-only commands.

**A capture can be armed and completed with no configuration commands at all**,
inheriting the instrument's front-panel timebase, volts/div and trigger. That
makes this the safest possible acquisition test.

Bit 4 of the status byte is set in all three states (`0x10`, `0x11`, `0x17`)
and is still unexplained.

### Data readout — working

A bare `[05 00]` returns zero bytes because `dsoHTGetData` is a four-step
sequence and `0x05` is only the last step. All four are decoded and confirmed
on hardware.

| Step | Opcode | Request | Meaning |
|---|---|---|---|
| 1 | `0x17` | 2 bytes | read the **trigger** address in the ring buffer |
| 2 | `0x13` | 8 bytes | set the read start address, 512-aligned |
| 3 | `0x1b` | 8 bytes | set the read length in words — **advisory** |
| 4 | `0x05` | 2 bytes | stream the samples off the bulk IN endpoint |

`0x17` returns a 24-bit little-endian address in the first three bytes. The
ring buffer is 2^24 samples — the constant `16777216.0` at `0x10008098`.

**The transfer model, corrected 2026-08-18.** Four findings from live
experiments (`diag_wrap.py`, `diag_single_stream.py`), each overturning an
earlier belief:

1. `0x17` is the **trigger address**, not the capture end. The record
   physically ends at `trigger + post` (post from the `0x0f` split). Both
   interpretations produce phase-locked windows, which is why the trigger
   experiments never caught this.
2. `0x1b` is **advisory**: a read requesting 202 k words streamed 28.8 MB.
   Once started, the stream runs from the read start to the record's
   physical end and stops there on its own. The old "device returns
   length + 2048 bytes" observation was an artifact of never draining.
3. **One read session per armed capture.** A second `0x13`/`0x1b`/`0x05`
   setup after a drain or stall delivers nothing until the next arm.
   `CONTROLDATA.nAlreadyReadLen` tracks progress through one continuous
   stream, not independent reads; re-issuing the setup mid-record produced
   irreproducible seams of tens to hundreds of samples.
4. A read starting **past the record end** delivers exactly the 2048-byte
   preamble and stalls, wedging the endpoint until re-arm. This is the
   signature that was long mistaken for a ~40 k memory-depth limit.
5. The **write pointer resets on arm** — end addresses repeat to within a
   few hundred points across identical runs. A record therefore only wraps
   the ring when the trigger waits long enough for the writer to pass
   2^24, or when the record simply doesn't fit: at 16 M points the trigger
   must land within a window under a million points wide, which is
   presumably what `0x0d`'s buffer-size codes exist to manage. Untested.

`0x13` and `0x1b` share one 8-byte layout:

```
[0] opcode        [1] 0x00
[2..5] value, little-endian 32-bit
[6] value & 0xff  [7] 0x80 for 0x13, 0x00 for 0x1b
```

Byte 6 duplicating the low byte is not a typo. The DLL computes it with
`shr eax, 0x20`, which x86-32 masks to a shift of zero, so a 40-bit field was
intended and the low byte lands there instead. The firmware tolerates it.
Reproduce it verbatim rather than "fixing" it.

`0x13`'s value is the start address **minus one**; `0x1b`'s length is used
as-is. The device then returns `length + 2048` bytes.

Start address selection, from `dsoHTGetData`:

```
back    = int(nHTriggerPos * nReadDataLen * 0.01)   # const 0.01 at 0x10008070
start   = (end_address - back) mod 2^24
rem     = start & 0x1ff
aligned = start - rem                                # what 0x13 receives
words   = 2 * nReadDataLen + 0x800                   # what 0x1b receives
```

The first `rem + 512` sample points are preamble and must be discarded.

#### That length formula counts analog samples, not groups

`nReadDataLen` is a count of **analog** samples, and an analog channel owns
two of the four slots in every group. Logic owns one. So asking for `n` and
reading the result as logic yields about `n/2 + 512 - rem` logic samples, not
`n`.

Measured with the libsigrok driver before this was understood: 1000 requested
gave 906, 4096 gave 2237, 10240 gave 5475 - all matching that expression to
the sample. `probe_logic.py` and `read_capture.py` inherit the same halving;
it goes unnoticed there because neither checks the returned count against the
requested one.

Working in logic samples instead, for `n` of them:

```
start   = (end_address - n) mod 2^24
rem     = start & 0x1ff
words   = 4 * n + 4 * rem + 0x800
```

Confirmed exact: 1000, 4096 and 10240 requested each return precisely that
many logic samples.

### Sample stream format

`sub_10003330` de-interleaves the bulk stream with a stride of four, widening
each byte to a `WORD`. One group of four bytes is:

```
[CH1 core A] [CH1 core B] [CH2 core A] [CH2 core B]
```

Each channel's ADC is **time-interleaved across two cores**, so a four-byte
group carries two consecutive samples per channel, not one sample of four
channels. The two cores show a constant offset mismatch of about 1 LSB, which
a naive midpoint edge detector will trip over — correct the offset or use
hysteresis.

Measured against the probe-compensation output: a 1 kHz square wave gives a
median half-period of 100007 samples per core, so **200.014 MS/s** per
channel — 0.007% from nominal 200 MS/s.

### Confirmed capture, end to end

`05_Software/protocol_probe/read_capture.py` drives the whole path over WinUSB
with no vendor driver, DLL or SDK loaded:

```
0x16  centre the offset DAC
0x03  StartCollectData
0x04  StartTrigger
0x02  ForceTrigger
0x06  poll to CAPTURE_READY_9BIT
0x17 -> 0x13 -> 0x1b -> 0x05
```

Reading 500000 (`nReadDataLen`) yields 250279 four-byte points, CH1 swinging
113..128 counts, a clean square wave at the reference frequency. Gate G2
step 5 is met.

## The SDK manual is an authoritative source, and was under-used

`01_Documentation/SDK_3062L/Manual/SDK_HTHardDLL-EN.pdf` documents every
exported function's parameters and their legal values. It gives semantics that
disassembly can only guess at. The headers under `HeadFiles/` give the struct
layouts, and `Code Demo/VCDSO/Hard.cpp` shows the vendor's own calling
sequence. Where the manual and the demo disagree, the demo wins: it presumably
runs.

What that settles for trigger support, which had looked like it needed `0x0c`
reverse-engineered from scratch:

```c
dsoHTSetTriggerAndSyncOutput(WORD nDeviceIndex, WORD nSynMode,
    WORD nlaTriggerMode, WORD nTriggerMode, WORD nTriggerSlope,
    WORD nPWCondition, ULONG nPW, USHORT nVideoStandard,
    USHORT nVedioSyncSelect, USHORT nVideoHsyncNumOption, WORD nSync);
```

| Parameter | Values |
|---|---|
| `nSynMode` | 0 for CH1/CH2/EXT as source, 5 for D0-D15 |
| `nlaTriggerMode` | logic trigger: 0 edge, 1 pulse |
| `nTriggerMode` | analog trigger: 0 edge, 1 pulse |
| `nTriggerSlope` | 0 rising, 1 falling |
| `nPWCondition` | 0 +Less, 1 +Equal, 2 +More, 3 -Less, 4 -Equal, 5 -More |
| `nPW` | pulse width in units of 5 ns, range 2 to 2e9 |
| `nSync` | sync output, 1 enable, 0 disable |

Trigger source indexing comes from `Hard.cpp`, which branches on it:

```
CH1 = 0, CH2 = 1, D0..D15 = 2..17, EXT = 18
```

with `laSetTrigSource(nTrigSource - 2)` called for the logic sources.

Also pinned down: coupling is `DC=0, AC=1, GND=2`; `nHTriggerPos` is a
percentage 0-100; `nVTriggerPos` is 0-255; `nYTFormat` is 0 normal, 1 scan,
2 roll.

**What the SDK cannot give is the wire format.** The DLL marshals these
parameters into the bulk buffer, and only disassembly or experiment reveals
the byte layout. But knowing every field, its order in the signature and its
legal range turns that from open-ended reverse engineering into a hypothesis
that can be tested against hardware in minutes.

The Chinese editions of the manuals, and the `HTSoftDll` and `HTDisplayDll`
manuals, have not been read.

## Configuration opcodes

| Opcode | SDK export | Notes |
|---|---|---|
| `0x09` | `dsoGetHardVersion` | |
| `0x0a` | `dsoHTGetHardFC` | hardware frequency counter read |
| `0x0c` | `dsoHTSetTriggerAndSyncOutput` | trigger mode, slope, pulse width, video sync |
| `0x0d` | `dsoHTSetBufferSize` | also stores `[+1] = 0x0f` |
| `0x0e` | `dsoHTSetSampleRate` | |
| `0x0f` | `dsoHTSetHTriggerLength` | buffer length, trigger position, timebase |
| `0x10` | `dsoHTResetCnter`, `dsoHTSetHardFC` | shared opcode, discriminated in later bytes |
| `0x15` | `dsoHTSetCHAndTrigger`, `…VB` | the `RELAYCONTROL` struct: enable, V/div, coupling, BW limit |
| `0x16` | `dsoHTSetCHPos`, `dsoHTSetVTriggerLevel` | shared DAC-level opcode; `[+2] = 1` selects trigger level rather than channel position |
| `0x18` | `dsoHTInitSDRam` | |
| `0x19` | `dsoHTOpenRollMode`, `dsoHTCloseRollMode` | |
| `0x1a` | `dsoHTSetPeakDetect`, `dsoHTClosePeakDetect` | |
| `0x2b` | `dsoGetFPGAVersion`, `ReadFPGAVersion` | |

Note `0x15` is a **read**, not a write: it returns the current 16-bit relay
word. The relay write is `0x12`, below.

### Vendor init order

`Code Demo/VCDSO/Hard.cpp` in the SDK spells out the order the vendor uses in
`CHard::Init()`, which is worth following in a driver:

```
dsoSetUSBBus
dsoHTReadCalibrationData         -> feeds the 0x16 DAC values
dsoHTSetSampleRate               0x0e
dsoHTSetCHAndTrigger             0x15 read + 0x12 writes
dsoHTSetTriggerAndSyncOutput     0x0c
dsoHTSetCHPos        per channel 0x16 selector 0
dsoHTSetVTriggerLevel            0x16 selector 1
dsoHTSetHTriggerLength           0x0f
laSetVoltDiv
```

`dsoHTSetBufferSize` (`0x0d`) is **never called** — it is not part of normal
setup. The demo's defaults are `nTimeDIV = 12`, `nYTFormat = 0`,
`nHTriggerPos = 50`, `nCHSet = 0x0f`, and buffer/read lengths all
`BUF_10K_LEN`.

### Decoded configuration buffers

`0x0d` SetBufferSize, 4 bytes:

```
[0] 0x0d  [1] 0x0f  [2] size code & 7  [3] 0x00
```

`0x0e` SetSampleRate, 12 bytes:

```
[0] 0x0e  [1] 0x00  [2] mode bits  [3] 0x00
[4..7] divider, little-endian signed 32-bit
[8..11] 0x00
```

`nTimeDIV` selects the divider through a 38-entry jump table at `0x10002284`.
The wire value is negative: `divider = -(ticks)`, and

```
sample_rate = 200 MHz / (ticks + 1)      per channel
```

**Byte 2 is not cosmetic.** It packs two flags the same jump table arms set,
as `(flagA & 1) << 1 | (flagB & 1)`. With byte 2 = 0 the divider is ignored
outright and the scope stays at full rate — this cost a full debugging cycle.
Every arm from index 13 down sets both flags, so **any dividing rate needs
byte 2 = 3**.

| `nTimeDIV` | byte 2 | ticks | rate per channel |
|---|---|---|---|
| 0–10 | `0b00` | 1 | 100 MS/s |
| 11 | `0b01` | 1 | 100 MS/s |
| 12 | `0b10` | 4 | 40 MS/s |
| 13 | `0b11` | 9 | 20 MS/s |
| 14 | `0b11` | 19 | 10 MS/s |
| 15 | `0b11` | 49 | 4 MS/s |
| 16 | `0b11` | 99 | 2 MS/s |
| 17 | `0b11` | 199 | 1 MS/s |
| 18 | `0b11` | 499 | 400 kS/s |
| 19 | `0b11` | 999 | 200 kS/s |
| 20 | `0b11` | 1999 | 100 kS/s |
| 21 | `0b11` | 4999 | 40 kS/s |
| 22 | `0b11` | 9999 | 20 kS/s |
| 23 | `0b11` | 19999 | 10 kS/s |

Indices 24–33 derive their divider from `nYTFormat` rather than loading a
constant: `ebx = BASE` when `nYTFormat` is 0, else `BASE + MASK`. 34–37 are
the roll-mode rates. `05_Software/protocol_probe/dump_timebase.py`
regenerates the table.

The 200 MHz base clock is **measured, not assumed**. Against the 1 kHz
probe-compensation reference the median half-period per interleaved core
follows `50000 / (ticks + 1)` samples exactly across ticks 99, 199, 499, 999
and 1999 — a 20× span with no drift, which fixes the per-channel base at
200 MHz. The DLL's own naming suggests 250 MHz; the hardware disagrees.

`0x0c` SetTriggerAndSyncOutput, 10 bytes — decoded from `sub_10003fa0`, which
`dsoHTSetTriggerAndSyncOutput` is a thin wrapper around. It mallocs ten bytes,
packs them as below and hands them straight to `DeviceIoControl(0x222051)`:

```
[0] 0x0c
[1] 0x00
[2] ((((nPWCondition & 3) | (nSync << 2)) << 2 | (nTriggerMode & 3)) << 2
      | (nTriggerSlope & 3)) << 1
[3] (((nSynMode << 3) | (nVedioSyncSelect & 7)) << 1) | (nVideoStandard & 1)
[4..6] nPW, little-endian
[7] (nPW >> 24) & 7                      the pulse width is 27 bits, not 32
[8] nVideoHsyncNumOption & 0xff
[9] ((nVideoHsyncNumOption >> 8) & 3) | (nlaTriggerMode << 3)
```

Note the trailing shift on byte 2: every field there sits one bit higher than
its own width suggests, so bit 0 is always clear.

The parameter meanings come from the SDK manual, above. Checked against the
demo's own call `(idx, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0)`, which yields

```
0c 00 00 00 00 00 00 00 01 00      rising-edge trigger on an analog source
0c 00 02 00 00 00 00 00 01 00      the same, falling edge
0c 00 00 50 00 00 00 00 01 00      edge trigger on a logic source (nSynMode 5)
```

#### Arming a trigger takes three commands, in order

`0x0c` alone does nothing. Nor does `0x0c` plus a level. The trigger only
arms once the **source** is set, and the source is not in `0x0c` at all - it
rides at bit 13 of the 24-bit word in the second `0x12` form, from
`nTrigSource` via `esp+0x19` in `sub_10002320`.

So the full chain is:

1. the source, in the `0x12` enable word - **after** the bit-serial relay
   writes, or they undo it
2. the level, `0x16` with byte 2 = 1
3. the mode and slope, `0x0c`

Confirmed working through the libsigrok driver against the 1 kHz reference.
Before the ordering was right, the first rising edge landed at samples 135,
167, 155, 71, 9 and 172 across six captures - the auto-trigger timeout firing
at a random phase. After:

| Slope | first rise | first fall | trace starts |
|---|---|---|---|
| rising | **145, 146, 146, 146, 145, 146** | 44-46 | high |
| falling | 46 | **146, 146, 147** | low |

Locked to a sample, and the two slopes are exact phase inversions of each
other: the triggered edge sits at ~146 in both, only its direction changes.

`0x0f` SetHTriggerLength, 12 bytes — two 24-bit ring-buffer pointers:

```
[0] 0x0f  [1] 0x00
[2..4] fieldA, little-endian 24-bit    [5] 0x00
[6..8] fieldB, little-endian 24-bit    [9] 0x00
[10..11] uninitialised in the DLL
```

```
buflen = min(nBufferLen, 0xfffbff)          # 2^24 - 1025
pre    = HTriggerPos * buflen / 100
post   = (100 - HTriggerPos) * buflen / 100
fieldA = max(0, 0xfffbff - pre)
fieldB = max(0, 0xfffbff - post)
```

`HTriggerPos == 100` is special-cased to `fieldA = 0xfffbff - buflen`,
`fieldB = 0xfffbff`. When `nYTFormat == 1` and `nTimeDIV >= 0x18` the length
is pre-multiplied by 4; when `nYTFormat == 2` the trigger position is forced
to 0.

Note this command carries **no timebase** despite taking `nTimeDIV` — that
argument only selects the ×4 branch above. The sample rate comes from `0x0e`
alone.

`0x16` SetCHPos / SetVTriggerLevel, 8 bytes:

```
[0] 0x16  [1] 0x00  [2] selector  [3] 0x00
[4] dac & 0xff  [5] ((dac >> 8) & 0x0f) | 0x10  [6] 0x00  [7] 0x00
```

Selector 0 is the channel offset, 1 the trigger level. The DAC is 12-bit and
the `0x10` bit in the high nibble is always set.

Confirmed on hardware: CH1 rails at `0x00` for DAC 0 and at `0xff` for DAC
1024 and above, and tracks linearly between — 256 → 45, 512 → 126, 768 → 197
counts. **The offset DAC must be set before any capture**, or the channel
reads a constant and looks like a dead datapath. DAC 512 centres it.

### Relay control — `0x12`

`dsoHTSetCHAndTrigger` builds a 16-bit relay word from the `RELAYCONTROL`
struct, reads the current word with `0x15`, then clocks out **only the
differing bits, one at a time**, with `Sleep(20 ms)` between writes. This is a
serial relay driver, not a parallel register.

Each write is 10 bytes:

```
[0] 0x12  [1] 0x00
[2..3] mask, little-endian 16-bit
[4..6] mask, little-endian 24-bit
[7] 0x00
[8..9] full target relay word, little-endian 16-bit
```

Bit *n* is addressed as `mask = 1 << (n + 3)` to set and `~(1 << (n + 3))` to
clear.

**Relay state carries across writes and must be fully reset before each
measurement.** Clearing only the previously-set bit contaminates the next
reading — that mistake produced a first table where 11 of 16 bits looked
identical, and made a set/clear pair appear to contradict itself. With a full
16-bit clear before each set, results repeat exactly (`set bit 3` gave span
176, dc 169 on four consecutive trials).

The mask's exact semantics are **still open**. It is not a plain accumulate:
clearing bit 10 after setting bit 3 wipes bit 3's effect, which fits a
whole-word overwrite. But a bare overwrite does not explain why `1 << 6`
applied directly after `1 << 13` leaves the `1 << 13` gain in place. Bytes
8–9, the "full target word", were swept across `0x0000`, `0x0040`, `0x2000`
and `0xffff` with no measurable effect, so the mask is what drives the
hardware.

Measured with CH1 on the 1 kHz 2 Vpp probe-compensation output, at 200 kS/s,
offset DAC 512, each bit set from a fully cleared state:

| Bit | CH1 span | CH1 DC | Effect |
|---|---|---|---|
| all clear | 1 | 59 | no signal |
| 3 | 196 | 169 | gain up |
| 4 | 163 | 183 | gain up, less |
| 10 | 255 | 127 | **maximum gain — clips — and centres the signal** |
| 11, 12 | 130 | 184 | gain down |
| 0,1,2,5–9,13–15 | 135–140 | 188 | no distinct effect at this setting |

So bits 3, 4, 10, 11 and 12 form the attenuator/gain ladder. The eleven
remaining bits do nothing measurable here; they are presumably coupling,
bandwidth limit and CH2 controls that this single-channel DC test cannot
distinguish.

**No bit brought CH2 alive** — it stayed railed at 255 throughout, which
suggests CH2 needs its own offset DAC write rather than a relay change.

**Superseded 2026-08-18: CH2's relay bits found.** The sweep above was
structurally blind - CH2's default gain puts any 2 Vpp signal past the
rail, so every bit looked identical. Re-swept in dual-channel mode with
the compensation output on CH2 and the offset DAC pulled down:

| bit | function |
|---|---|
| 8, 9 | CH2 gain pair, byte-identical, 2 V = 130 counts (15.385 mV/count) |
| 7 | CH2 AC coupling - comp square's mean fell count 193 -> 129, span kept |

The chain is mirror-symmetric with CH1 (gain pair 11/12, coupling 10).
CH2's zero is count 128 at offset DAC 512.

**CH2's full ladder, closed 2026-08-18 with a small source on CH2.** The
obvious symmetry hypothesis - CH1 has fine gain relays, so CH2 must too -
was tested and refuted twice over:

- Chain positions 16-20, which no sweep had ever written (the 16-bit
  chain was an assumption; the wire format holds a 24-bit shift), are
  empty: clearing or setting them changes nothing.
- With a 100 mVpp square on CH2, no chain bit besides 7/8/9 moves its
  gain at all.

CH2's fine range is the chain's **default path**: no relay engages it.
Measured against a 300 mVpp offset-zero square: 1.62 mV/count
(52 mV/div), zero at count 130 with the offset DAC at 200 - at the
driver's generic DAC 512 this range's zero sits at count 214, against the
top rail, which is why it always looked clipped and why the original
sweep concluded no relay touched CH2. So CH2 has two ranges to CH1's
three; the missing middle step presumably lives in the settings word's
volts/div group, like CH1's other six nominal steps.

One interaction matters for offsets: under AC coupling the signal centres
on the coupling network's bias, which lands at count ~129 at DAC 512 on
both ranges - the fine range's lowered DAC applies to DC only, or an AC
signal is dragged into the bottom rail.

Two ordering traps bit this measurement before it worked: the bit-serial
relay writes undo the enable word (write the enable word after every relay
change, per the vendor's own ordering), and only then does slot 1 carry
CH2 at all.

**Reproduced through the libsigrok driver, 2026-08-17.** Implementing the
clear-all-then-set sequence in C and selecting bit 12 gives min 119, max 249 -
span 130, midpoint 184 - against the 1 kHz probe-compensation reference. That
matches the table above exactly, independently of the Python probe path, which
is good evidence that both the relay encoding and the "fully clear first"
requirement are correctly understood.

It is also the first usable analog capture: at this setting the waveform fits
inside the converter's range instead of railing at 255.

### Gain ladder swept through the driver

Each bit set from a fully cleared baseline, 1x probes on the 1 kHz 2 Vpp
compensation output, offset DAC 512:

| Bit | min | max | span | midpoint | |
|---|---|---|---|---|---|
| 3 | 79 | 255 | 176 | 167.0 | clips |
| 4 | 109 | 255 | 146 | 182.0 | clips |
| 10 | 0 | 255 | 255 | 127.5 | clips hard, maximum gain |
| 11 | 119 | 249 | 130 | 184.0 | fits |
| 12 | 119 | 249 | 130 | 184.0 | fits |
| 0 | 120 | 255 | 135 | 187.5 | clips |

Bits 11 and 12 produce byte-identical results, which suggests they drive the
same relay or a redundant pair rather than two distinct attenuator steps.

Only these two keep a 2 Vpp input inside the converter, so bit 12 is the
driver's default. The clipping settings **cannot be calibrated from this
reference** - their spans above are truncated by saturation, not measured.
Characterising them needs a smaller adjustable source.

### The gain ladder, measured against a variable source

An external generator at 1 kHz square, 1x probes, offset DAC 512, each bit
applied from a fully cleared relay state. Each step measured at an amplitude
that fills a useful part of the converter - a span of five counts carries a
20 percent quantisation error and is worthless.

| Bit | mV/count | Full scale | Measured at | Confidence |
|---|---|---|---|---|
| 3 | 0.565 | 0.145 V | span 177 @ 100 mV | good |
| 4 | 1.117 | 0.286 V | span 89.5 @ 100 mV | good |
| 10 | 1.65 | 0.42 V | span 182 @ 300 mV | **suspect, see below** |
| 11, 12 | ~15.8 | ~4.0 V | span 30.5 @ 500 mV, 130 @ 2 V | good |

Bits 11 and 12 produce byte-identical amplitudes at every input level tested.
Neither is the bandwidth limit - that lives at bits 8 to 11 of the settings
word, not in the relay chain - so both act on the gain path. Whether they are
one relay, a redundant pair, or two coincident steps is still open.

The 11/12 figure is the trustworthy one: 16.4 mV/count from the generator at
500 mV and 15.4 from the instrument's own 2 Vpp compensation output agree
within 6 percent, and those are independent sources.

Note the ordering is the reverse of the earlier reading. Bit 3 is the
**highest** gain, not bit 10; the original table was taken at 2 Vpp where
every step except 11 and 12 saturated, so their spans were the converter's
limit rather than the instrument's response.

### Bits 11 and 12 are not the bandwidth limit

The bandwidth limit is not in the relay chain. `bCHBWLimit[0..3]` occupies
**bits 8 to 11 of the 24-bit settings word**, as the decoded bit map above
already shows, and reaches the wire through the second `0x12` form. Nothing
in the bit-serial relay writes carries it.

Measurement agrees. Sampling both ADC cores interleaved at 200 MS/s with a
10 MHz sine, where a 20 MHz limit would pass 89 percent:

| Bit | Span at 100 kHz | Span at 10 MHz | Three runs |
|---|---|---|---|
| 11 | 134 | 27 | 27, 27, 28 |
| 12 | 134 | 27 | 27, 28, 27 |

One bit limited to 20 MHz would read about 24 against the other's 27. The
spread is +/-1 and no such gap appears.

Both bits therefore act on the gain path. Whether they are one relay, a
redundant pair, or two steps that happen to coincide is still unknown, but
neither is the bandwidth control.

#### The 1x probe rolls off around 10 MHz

Incidental but worth knowing: the span falls from 134 at 100 kHz to 27 at
10 MHz, an 80 percent loss identical on both bits. That is not the
instrument - a 60 MHz front end loses nothing at 10 MHz. It is the probe,
and not by inference: the manual's Appendix B specifies the shipped passive
probes as **6 MHz bandwidth in the X1 position**, full bandwidth only at X10.
The generator may also be down at its maximum rated frequency.

Consequence for calibration: every volts-per-count figure in this document
was measured at 1 kHz and holds only at low frequency. They say nothing about
amplitude accuracy in the MHz range, and with a 1x probe the probe itself is
the limit long before the instrument is.

### Bit 10 is AC coupling - confirmed

Not a gain bit at all. Measured with a generator's full-wave rectified output,
which is all-positive and so carries a large DC component, against a symmetric
sine as the zero reference: a sine has zero mean, so its midpoint marks 0 V
under either coupling.

| | 0 V reference | full-wave min | full-wave mean |
|---|---|---|---|
| bit 10 | 122.5 | 64 | **120.5** |
| bit 12 | 129.5 | **129** | 134.4 |

Bit 10 places the signal's **mean** at zero - the DC component has been
removed. Bit 12 places its **minimum** at zero - the DC passes through. The
matching figures are within 2.0 and 0.5 counts; the alternatives miss by 58
and 5.

`RELAYCONTROL.nCHCoupling[]` takes DC 0, AC 1, GND 2, so a coupling relay is
expected to exist. This is it, for CH1.

That explains every oddity recorded below: why bit 10 "centres the signal",
and why its apparent span never scaled with input amplitude the way a real
attenuator step does.

**Composition confirmed on hardware, 2026-08-18.** Relay word bit 12 + bit 10
together - a gain step with AC coupling on top, the way RELAYCONTROL's
independent nCHCoupling and nCHVoltDIV fields imply - behaves exactly as the
two bits do alone: a 10 MHz sine riding a ~+1.25 V DC offset clipped the top
rail under DC coupling (mean +1.29 V) and came back centred on zero
(mean +31 mV) with the full waveform inside the converter under AC. Measured
through the libsigrok driver's SR_CONF_COUPLING path, not a probe script.

### The evidence that pointed there

It does not scale:

| Input | Span | Implied full scale |
|---|---|---|
| 100 mV | 36.5 | 0.70 V |
| 200 mV | 42 | 1.22 V |
| 300 mV | 182 | 0.42 V |
| 500 mV | railed 0-255 | under 0.5 V |

Generator drift is ruled out: bit 3 and bit 10 were measured in the *same*
sweep at 100 mV, and bit 3 scaled correctly while bit 10 did not.

Two properties pointed away from gain: it is the only bit that centres the
trace, which is what removing a DC component does rather than what an
attenuator does, and `RELAYCONTROL` carries a coupling field that nothing in
the decoded word had been matched to.

A generator with no DC-offset control can still run the test. A full-wave
rectified output is all-positive and therefore carries a large DC component,
and a symmetric sine supplies the zero reference. No offset knob needed.

### One calibrated point

At bit 12 with 1x probes: 2 V spans 130 counts, and the waveform's low level -
ground, for a ground-referenced compensation output - sits at count 119.

```
volts = (count - 119) * 2.0 / 130        ~15.4 mV per count
```

The driver emits volts on this basis. Two honest limits: it holds only for
this exact gain and offset-DAC combination, and reading 2.000 V back from the
same signal that produced the constants confirms the arithmetic rather than
the calibration. The independent check is timing - 1000.0 Hz - which played no
part in deriving the vertical scale.

`0x15` returned `0x0000` in early runs but `0x8584` on a later entry, so it is
a real readback, not a stub. The DLL guards against a zero result with
`test edi, edi; je` — if bit 0 of the readback is clear it writes every bit
unconditionally instead of diffing.

`RELAYCONTROL` offsets, confirmed against the disassembly:

| Offset | Field |
|---|---|
| `0x00` | `bCHEnable[4]`, 4 bytes each |
| `0x10` | `nCHVoltDIV[4]`, WORD |
| `0x18` | `nCHCoupling[4]`, WORD |
| `0x20` | `bCHBWLimit[4]`, 4 bytes each |
| `0x30` | `nTrigSource`, WORD |
| `0x34` | `bTrigFilt` |
| `0x38` | `nALT`, WORD |

`bTrigFilt` is the manual's "HF Rejection" (trigger setup, section under
3.4): it suppresses trigger frequencies above roughly 20 MHz. A trigger-path
filter, not a signal-path one — distinct from `bCHBWLimit`, which is the
per-channel 20 MHz limit on the displayed signal and gets a "B" badge in the
vendor UI.

## Data transfer opcodes

`0x13`, `0x17` and `0x1b` appear together with `0x05` across
`dsoHTGetData`, `dsoHTGetScanData`, `dsoHTGetRollData`, `dsoHTStartRoll` and the
`dsoSD*` variants. They are most likely a mode/bank selector around the same
transfer, not four independent reads. **Unresolved — needs wire evidence.**

## Logic analyzer opcodes

Not present in `hantek-dso` at all. This block is the MSO half of the
instrument and covers the complex triggers the project plan rated only
"Medium" confidence.

| Opcode | SDK export | Purpose |
|---|---|---|
| `0x3c` | `laSetTrigSource` | logic trigger source |
| `0x3d` | `laSetTriEdge` | edge trigger |
| `0x3e` | `laSetTriDataRange` | value-range trigger |
| `0x3f` | `laSetTriDataTime` | duration trigger |
| `0x40` | `laSetTriDataEqu` | bus-value equality trigger |
| `0x41` | `laSetTriIntr`, `laSetVolt`, `laSetVoltDiv` | shared; includes the 16-entry logic threshold array |
| `0x42` | `laSetTrigNow` | immediate trigger |
| `0x43` | `SetTrigRelease` | trigger release/re-arm |

### Where the logic samples live — solved

**Bytes 2 and 3 of every four-byte group in the `dsoHTGetData` stream are the
16 logic channels**, D0–D7 and D8–D15, one byte each. There is no separate
`laGetData` export because logic rides in the same stream as analog.

This corrects the earlier reading of those slots as "CH2's two interleaved ADC
cores". Three independent lines of evidence:

1. They never respond to any of the four `0x16` offset DACs, swept 0–768.
2. They never respond to any of the 16 relay bits — including with CH2
   physically driven from the same 1 kHz source.
3. They flip together exactly as the `0x41` comparator threshold crosses 0 V,
   which is where 16 unconnected inputs sitting at ground switch.

### Stream layout depends on the enabled-channel set — solved

| Slot | CH1 only | CH1 + CH2 |
|---|---|---|
| 0 | CH1, ADC core A | CH1 |
| 1 | CH1, ADC core B | **CH2** |
| 2 | logic D0–D7 | logic D0–D7 |
| 3 | logic D8–D15 | logic D8–D15 |

With one analog channel enabled the two slots carry it from two
time-interleaved ADC cores, so CH1 gets the full rate. Enabling CH2 reassigns
slot 1, and **each channel then runs at half the single-channel rate**. The
per-slot rate is unchanged at `100 MHz / (ticks + 1)` in both modes; the
200 MS/s figure is a shared budget, which is consistent with the instrument's
published 200 MS/s spec.

So the effective per-channel rate is:

```
one analog channel   200 MHz / (ticks + 1)
two analog channels  100 MHz / (ticks + 1)
logic (always)       100 MHz / (ticks + 1)
```

The manual's LA spec corroborates the logic line independently: "Max Sample
Rate 100MHz", alongside 10 MHz LA bandwidth, 200 kΩ / 10 pF inputs, ±60 V
absolute range, and 10K–68M/CH storage depth (deeper than the analog
10K–16M — the logic bytes evidently pack more samples into the same ring).

#### Logic rate confirmed, and probe_logic.py corrected

`probe_logic.py` computes `200e6 / (ticks + 1)` for logic and prints the
"200 kS/s" figure quoted elsewhere in this document. **That is wrong by a
factor of two.** Logic occupies one slot per four-byte group, so it advances
at the per-slot rate, never the two-slot analog rate.

Measured 2026-08-17 through the libsigrok driver, against the instrument's own
1 kHz probe-compensation output on CH1 - which rides the same groups, so its
timing is the logic timing:

| Rate set | Median period | Implied frequency |
|---|---|---|
| 200 kHz | 200 samples | 1000.0 Hz |
| 500 kHz | 500 samples | 1000.0 Hz |
| 1 MHz | 1000 samples | 1000.0 Hz |

Exact at all three. Had the 200 MHz figure been right, the 1 kHz reference
would have measured 500 Hz.

The analog side is the opposite case, and confirms the two-core reading of
slots 0 and 1. Emitting both slots as consecutive samples makes the same
1 kHz reference span **400** samples instead of 200 at a reported 200 kHz. So
with one analog channel enabled CH1 really does sample at
`200 MHz / (ticks + 1)` - the instrument's full 200 MS/s budget - while the
group, and therefore logic, advances at half that.

That measurement also reveals the current hardware state: slot 1 is CH1's
second core, **not CH2**, so the instrument is in single-analog-channel mode
even with both probes physically connected. Consistent with the finding above
that no relay bit brought CH2 alive.

Still open, and only a logic pod can close it: whether slots 2 and 3 are two
banks of eight channels (D0-D7, D8-D15) or two time points of the same eight.
The evidence favours banks - the instrument is specified as 16 channels,
`laSetVoltDiv` reads a 16-entry array using entries 0 and 8, and the two bytes
respond to different threshold DACs - but every test so far ran on unconnected
inputs, where all sixteen read alike. Drive D0 and check whether the same
signal appears on D8.

### The enable word — a second `0x12` form

`dsoHTSetCHAndTrigger` builds **two** words, not one. The bit-serial loop
described above clocks only the second (coupling and attenuator). The first is
written once at the very end by a `0x12` with a different shape:

```
[0] 0x12  [1] 0x00  [2] 0x00  [3] 0x00
[4..6] the 24-bit enable word, little-endian
[7] 0x00
[8..9] the coupling/attenuator word, little-endian 16-bit
```

**Bytes 2–3 being zero is what distinguishes the two forms.** A bit-serial
pulse carries a mask there; this direct register write does not. Channel
enable lives only in this word, which is why no amount of single-bit poking
ever turned CH2 on — the earlier sweeps were driving the wrong register
entirely.

Bit order in the 24-bit word, recovered from the packing chain at
`0x100029b2` (MSB first):

```
bit23 branch flag   bit22 [0x1c]        bit21 [0x10]        bit20 [0x11]
bit19 [0x15]        bit18 [0x16]        bit17 [0x12]        bit16 [0x13]
bit15 [0x17]        bit14 [0x18]        bit13 [0x19]        bit12 TrigFilt
bit11 BWLimit[0]    bit10 BWLimit[1]    bit9  BWLimit[2]    bit8  BWLimit[3]
bit7..bit0          volts/div group
```

#### Those bracketed numbers are stack locals, not struct offsets

Worth stating explicitly, because reading them as `RELAYCONTROL` offsets
leads to the confident and wrong conclusion that this word carries no
channel-enable bits.

`[0x10]` and friends are `esp+0x10` inside `sub_10002320`, a scratch buffer
the function fills before packing. The packing chain at `0x100029b2` reads
them in exactly the order listed above: `esp+0x1c`, `0x10`, `0x11`, `0x15`,
`0x16`, `0x12`, `0x13`, `0x17`, `0x18`, `0x19`.

Where those locals come from is the answer to two open questions:

| Local | Filled from |
|---|---|
| `esp+0x10` .. `esp+0x16` | the `bCHEnable[4]` decision tree at `0x10002422` |
| `esp+0x19` | `nTrigSource`, `mov cx, word ptr [eax + 0x30]` |

So **the 24-bit word does carry channel enable, and it carries the trigger
source too**. `sub_10002320` branches on the combination of enabled channels -
`[eax]`, `[eax+4]`, `[eax+8]`, `[eax+0xc]` - and each combination writes its
own seven-byte pattern into `esp+0x10..0x16`. It is a lookup, not a bitmask,
which is why poking individual bits never turned CH2 on.

Decoding the branch for "CH1 and CH2 both enabled" is what enabling CH2 needs.
The same word, via `esp+0x19`, is what arming a trigger needs.

Polarity is not involved: `Hard.cpp` sets `bCHEnable[i] = 1` to enable and the
manual's own example passes `pCHEnable[4] = {1,1,1,1}`. The manual's separate
remark that `nCHSet` uses "0 is enable, 1 is disable" contradicts both, and
contradicts the demo's own `((nCHSet >> i) & 1) == 1` test for an active
channel. Treat that line as an error in the manual.

**Decoded further 2026-08-18: the word is two independent fields.** Fresh
disassembly of `sub_10002320` shows the trigger source set as a two-flag
field (`esp+0x17/0x18`: 1,1 for CH1; 0,0 for CH2; 1,0 and 0,1 for sources
2 and 3), separate from the channel flags. Empirically, clearing bits 14
and 15 from the dual word phase-locks the record to CH2's edge within one
sample on every repeat:

| Field | Bits | Values |
|---|---|---|
| channels | 16-18, 21 | `0x270000` dual, `0` CH1 alone |
| trigger source | 14-15 | `0x00c000` CH1, `0` CH2 |

So `0x00c000`, long recorded as "the CH1-only enable word", contains **no
channel bits at all** - it is the source-CH1 field, and single-channel
mode is simply the channel field at zero. The trigger-level DAC (`0x16`
selector 1) is source-agnostic. EXT and the logic sources presumably use
the remaining source-field values; untested.

Values for `nTrigSource = 0` with coupling and bandwidth bits clear, derived
from the `bCHEnable[]` branch tree at `0x10002513`:

| Channels | Word | Status |
|---|---|---|
| CH1 only | `0x00C000` | **confirmed on hardware** |
| CH1 + CH2 | `0x27C000` | **confirmed on hardware, and now proven to make CH2 independent** |
| CH2 only | `0x2AC000` | derived, untested |
| CH3 only | `0x15C000` | derived, untested |

Confirmed by writing `0x27C000` with CH1 and CH2 held at different offset DACs
(400 and 850): slot 1 jumped from tracking CH1 within 0.5 counts to a 66-count
offset, and reverting to `0x00C000` put it straight back.

### The 0x16 channel selectors, and proof that CH2 is real

`05_Software/protocol_probe/probe_dacsel.py` drives one selector at a time to
a distinct offset and measures both analog slots. The result settles two
questions at once:

| Selector driven | CH1 only (`0x00C000`) | CH1 + CH2 (`0x27C000`) |
|---|---|---|
| ch1 `0x10` | **both** slots move | slot 0 only |
| ch2 `0x50` | nothing | **slot 1 only** |
| ch3 `0x90`, ch4 `0xd0` | nothing | nothing |

With one channel enabled the two slots follow the same DAC, because they are
CH1's two interleaved cores. Write `0x27C000` and they separate: `0x10` moves
slot 0 and `0x50` moves slot 1, independently. **CH2 is a real second channel,
and the enable word is what turns it on.**

Selectors `0x90` and `0xd0` do nothing on this two-channel instrument, as
expected - the DAC block is shared with four-channel models.

### The enable word must be written last

It is a `0x12`, and so are the bit-serial relay writes. Sent before them it is
simply undone, which looks exactly like an enable word that has no effect. The
vendor writes it once at the end of `dsoHTSetCHAndTrigger`, after the serial
bits, and a driver has to do the same.

Together with the `0x41` ordering below, that makes three separate failures in
this project traced to command order rather than command content. The vendor's
`CHard::Init()` sequence is worth following exactly.

### `0x41` after `0x16` destroys the offset DACs

Ordering, not payload. Sending the logic-threshold write after the
channel-position writes leaves the offset DACs at whatever they were before,
so a `0x16` that is byte-for-byte identical to the one the probe scripts use
appears to do nothing at all.

Found by elimination: through the libsigrok driver, DAC 300 produced counts
119-249 (the DAC-512 result) with `0x41` last, and 54-184 - the expected DAC
300 result - with `0x41` moved ahead of the DAC loop. Nothing else changed.

`0x41` is a shared opcode (`laSetTriIntr`, `laSetVolt`, `laSetVoltDiv`), so
this is plausible rather than surprising: some other arm of it reaches the
analog position DACs. Follow the vendor's `CHard::Init()` order and the
problem does not arise - it ends with `laSetVoltDiv`, and its `0x16` writes
come before that.

### Gain and offset are coupled, and the SDK says so

`dsoHTSetCHPos(WORD nDeviceIndex, WORD* CHLevel, WORD nVoltDIV, WORD nPos,
WORD nCH)` takes **`nVoltDIV`** alongside the position, and indexes a
calibration array with it. The offset DAC is therefore a function of the gain
setting, not an independent control: change the relay attenuator and the DAC
must be recomputed or the trace walks off screen.

The gain sweep shows the same thing from the other side - each relay bit moves
the midpoint as well as the span, from 128 counts at bit 10 to 188 at bit 0.

So a real volts/div control needs both halves together: the relay word for the
attenuator, and a matching DAC value for the position. A fixed DAC of 512 is
correct only at the gain it was measured against.

### `0x41` — logic threshold

Four bytes:

```
[0] 0x41  [1] 0x00  [2] DAC, even channels  [3] DAC, odd channels
```

The two DACs do **not** split by byte. One drives the even-numbered logic
channels and the other the odd, across both bytes:

| byte 2 | byte 3 | every logic byte reads |
|---|---|---|
| 0 | 240 | `0b01010101` |
| 240 | 0 | `0b10101010` |
| 0 | 0 | `0b11111111` |
| 240 | 240 | `0b00000000` |

That matches `laSetVoltDiv` reading array entries 0 and 8 of its 16-entry
`WORD*` — two banks, not sixteen independent thresholds.

The user manual (section 4.6) labels the two banks differently: "Level A:
Logic threshold range of D0-D7", "Level B: D8-D15", adjustable −6 V to +6 V.
That is a **byte split**, and it contradicts the measured even/odd split
above — under a byte split, byte 2 at 0 and byte 3 at 240 would read
`0x00`/`0xff` per byte, not `0b01010101` on every byte. Either the vendor UI's
labelling doesn't match the hardware, or the channel-to-bit mapping between
the pod connector and the stream is itself interleaved, which would make both
descriptions true at once. Only a pod on known pins can separate those. Until
then the measured behaviour stands: the two DACs land on alternating bits of
the captured stream. (The spec page claims −8 V to +8 V threshold range; the
panel says −6 to +6; the DLL clamps to 0–6 V. Three sources, three ranges.)

From the constants at `0x100080d0`, `0x100080d8` and `0x100080e0`:

```
dac = 121.848 - 10.8696 * threshold_volts
```

so DAC 122 is 0 V and the usable range is roughly −12 V to +11 V.
`laSetVoltDiv` clamps its own input to 0–6 V before conversion.

Confirmed end to end: `05_Software/protocol_probe/probe_logic.py` reads all
16 channels at 200 kS/s with a 1.4 V threshold. With nothing attached all 16
read high, and the threshold sweep drives them low as expected.

`laSetVoltDiv` first calls `laReadEEROM` for per-instrument calibration, which
this implementation skips — thresholds are therefore uncalibrated.

**Not yet tested with a logic pod attached**, so edge capture on a real
digital signal is unproven.

## Acquisition memory depth

`nBufferLen`, passed to `dsoHTSetHTriggerLength` (`0x0f`), is the record
length. The SDK demo defines exactly two: `BUF_10K_LEN` 10240 and
`BUF_40K_LEN` 40960, and uses 10240 as its "factory setup".

Measured through the libsigrok driver, requesting logic samples:

| Requested | Returned |
|---|---|
| 10240 | 10240 |
| 40960 | 40960 |
| 200000 | nothing |
| 1000000 | nothing |

That is a limit of **this driver**, not of the instrument. The vendor software
advertises 10K to 16M per channel, matching the 2^24 ring, and
`read_capture.py` reaches it: with the record length raised alongside the read
length it returns 100522 and 500534 sample points, state 3, clean data.

```
uv run read_capture.py --samples 500000 --buflen 500000 --ticks 999 --force
```

Two things are needed together. The record length in `0x0f` must match, or
the capture never leaves state 0. And the bulk read must be issued **one
512-byte packet at a time**, which is what the DLL's own loop does - asking
for a larger block returns `LIBUSB_ERROR_TIMEOUT`, because the device
streams a packet at a time and never fills a bigger request.

**Resolved 2026-08-18.** The "deep capture returns 2048 bytes and times out"
failure was the record-geometry stall described under the transfer opcodes:
the read start landed past the record's physical end, because the driver
treated the `0x17` address as the capture end when it is the trigger. With
the single-stream read model the driver reaches every depth whose record
fits the ring:

| Depth | Result |
|---|---|
| 10 k / 40 k | exact, regression |
| 500 k / 1 M / 4 M | exact |
| 6 M @ 2 MHz | exact, 2999 comp-square periods, zero anomalies |
| 8 M @ 10 MHz | exact, 799 periods, zero anomalies |
| **16 M @ 10 MHz** | **exact, 1599 periods, zero anomalies** |

A segmented reader (fresh `0x13`/`0x1b`/`0x05` per 4 M) got the counts right
but left variable seams of -54 to +356 samples at every boundary; the
single-stream reader has no boundaries and no seams.

Deep records need the trigger steered into the readable window
`[samples/2, ring - samples/2]` (mod the ring). Two facts make that
possible, both measured 2026-08-18: the **write pointer wraps the ring
indefinitely** while armed (a 50 MHz capture triggered at
elapsed × rate mod 2^24 exactly), so where the trigger lands is decided by
*when* arming happens; and a live trigger source fires the instant 0x04
arms it. The driver estimates the pointer from the monotonic clock -
timer ticks drift 30 percent and are useless for this - waits out the
laps, closes the final stretch with a precise sleep, and re-arms up to
three times if a sparse real trigger still lands badly. Verified live:
16 M at 10 MHz and even 16 M at 20 MHz, whose window is 17 ms wide. Only
16 M at 50 MHz stays out of reach (window under 6 ms); the driver refuses
it up front with a clear error.

Verification artifact of note: the sigrok-cli **CSV output module displaces
samples by hundreds of positions** when analog data arrives as multiple
packets (it warns "untested configuration" and means it). Two of the three
"seams" first blamed on the driver were this. Deep-capture validation must
read the `.sr` payloads directly.

`dsoHTSetBufferSize` (`0x0d`) takes a three-bit size code and **the demo
never calls it**. Tested 2026-08-18 (`diag_wrap_halt.py`): all eight codes
were swept at 1 MHz and at 50 MHz, and none changed the trigger address,
the capture state, or any other observable - the suspected write-region
sizing role did not materialise. Function still unknown, and it was not
needed: window steering reaches 16 M without it.

## Function generator opcodes

**The generator exists only on the DSO3062AL.** The user manual is explicit
three times over: chapter 4.7 opens with "Caution: This part is only used for
DSO3062AL", the connector list marks both "OUTPUT: Signal output" and the
E-TRIG/S sync output as "(DSO3062AL)", and the spec page heads the generator
table "Arbitrary Waveform Generator Mode (DSO3062AL)". A plain DSO3062L has
no OUTPUT terminal at all — the DDS exports below are in the shared DLL, but
on this instrument there is nothing wired to them. That closes the earlier
PWM question for good: no generator, no PWM output, on the L.

For the record, the AL's generator spec: DC–25 MHz, one channel, 4 KSa
waveform depth, 12-bit vertical, ±3.5 V max into 50 Ω, plus a square sync
output at the generated frequency. Declared in `HeadFiles/HTHardDll.h` under
its own `-----------DDS--------------` banner:

```c
ddsSetOnOff(WORD DeviceIndex, short nOnOff);
ddsSetFrequency(WORD DeviceIndex, double dbFre, WORD* pWaveNum, WORD* pPeriodNum);
ddsDownload(WORD DeviceIndex, WORD iWaveNum, WORD* pData);
ddsSetSyncOut(WORD DeviceIndex, BOOL bEnable);
ddsSetCmd(WORD DeviceIndex, USHORT nSingle);
```

It is an arbitrary-waveform generator - `ddsDownload` sends a sample table -
rather than a dedicated PWM peripheral, though a downloaded table can of
course be a pulse train of any duty cycle. `ddsSetSyncOut` drives a separate
sync output.

**The English SDK manual documents none of these**, and the demo calls none of
them. Only the export names and signatures are known. That leaves two possible
sources: the Chinese manual editions, which are unread, and the DLL itself -
the opcodes below came from disassembly.

There is a second, unrelated output: `nSync`, the last parameter of
`dsoHTSetTriggerAndSyncOutput` (`0x0c`), documented as "the synchro output is
enable or disable". The driver packs it at its correct position and leaves it
at 0. That one is a trigger-synchronous output, not the generator.

Out of scope for the PulseView integration, recorded for completeness.

| Opcode | SDK export |
|---|---|
| `0x30`, `0x31` | `ddsSetOnOff` |
| `0x33` | `ddsSetCmd` |
| `0x34` | `ddsSetFrequency` |
| `0x35`, `0x37` | `ddsDownload` |
| `0x39`, `0x3a` | `ddsSetSyncOut` |

## Network opcodes

| Opcode | SDK export |
|---|---|
| `0x29` | `dsoOpenWIFIPower` |
| `0x2a` | `dsoResetWIFI` |

## Undocumented exports

The public `HTHardDll.h` declares roughly 20 functions. The DLL exports **68**.
Notable additions: `dsoHTWriteCalibrationData`, `dsoHTDeviceConnect`,
`dsoReadFlash`, `dsoWriteFlash`, `laReadEEROM`, `laWriteEEROM`,
`dsoGetDeviceSN`, and the whole `laSetTri*` trigger family.

**`dsoHTWriteCalibrationData`, `dsoWriteFlash` and `laWriteEEROM` write
persistent device state.** Never issue their opcodes during exploratory
probing. This is the concrete reason blind opcode sweeps are unsafe.

## Open questions

1. The exact write semantics of the `0x12` mask — neither plain accumulate nor
   plain overwrite explains every observed sequence.
2. What the eleven relay bits with no measured effect do. Distinguishing them
   needs an AC-coupled test, a signal on CH2, and a bandwidth sweep rather
   than the single DC test used so far.
3. Whether CH2 needs its own offset DAC write, and what selector value
   addresses it — selector 0 appears to move CH1 only, and CH2 sits railed at
   `0xff` regardless of relay state.
4. Volts/div to ADC-counts scaling, needed to report real voltages.
5. How `nTimeDIV` indices 24–33 combine `BASE` and `MASK` in practice, and
   what `nYTFormat` selects there.
6. Which opcodes the `0xb3` `CTRL_BEGINCOMMAND` handshake must precede.
7. Whether the logic channels capture real edges. Verified only against
   unconnected inputs and a threshold sweep so far - no pod attached.
8. The volts/div group, bits 0-7 of the enable word, and how it maps to the
   instrument's 10 mV/div .. 5 V/div range — nine steps in a 1-2-5 sequence
   per the spec page, so `nCHVoltDIV` runs 0..8. Three of the nine gains are
   measured (relay bits 3, 4, 11/12); the remaining six presumably combine
   those relays with the settings-word group.
9. Bit 4 of the status byte.
10. Opcodes for calibration read, and their buffer format. `dsoHTReadCalibrationData`
   is the first call in the SDK demo's `Init()` and its result feeds the
   `0x16` DAC values, so real voltage accuracy depends on it.

## Reproducing

```bash
cd 05_Software/protocol_probe
uv run map_commands.py <path to HTHardDLL.dll>
```

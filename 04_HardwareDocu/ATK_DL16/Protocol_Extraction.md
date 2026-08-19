# ALIENTEK ATK DL16 — protocol extraction (phase 1)

Feasibility study for adding an ALIENTEK DL16-family logic analyzer as a
second device in the same libsigrok/PulseView build that carries the Hantek
DSO-3062L driver.

**Status: analysis only.** No code written, nothing built, no hardware
touched (the device was not connected during this work). Sources are the
vendor's GPL-3.0 repositories and the installed Windows application at
`D:\Programms\ATK-Logic`.

Date: 2026-08-19.

---

## 1. The premise, corrected

ATK-Logic **is not PulseView and does not use libsigrok.**

| Component | Reality |
|---|---|
| `atk-logic` | Custom Qt/QML application. Own libusb device layer in `pv/usb/` (`usb_base`, `usb_control`, `usb_hotplug`, `usb_loop_thread`, `usb_server`). `usb_base.h` includes `libusb.h`; **no sigrok headers anywhere**. |
| `atk_libsigrokdecode` | A copy of sigrok's protocol-decoder library (2 commits, stock README). |

The `pv/` prefix and some naming echo PulseView, but the subdirectories
(`controller`, `draw`, `model`, `thread`, `usb`) do not match PulseView's
real layout (`view`, `binding`, `dialogs`, `popups`, `prop`). It is a
separate application that reuses **only the decoders**.

Consequence: **there is no DL16 libsigrok driver to merge.** A single
unified build means *writing* one - the same shape of work as the Hantek
driver, but with the protocol readable from source instead of recovered
from a DLL.

## 2. Device identity — CONFIRMED

From `driver/ATK-Logic-Analyzer/ATK-Logic-Analyzer.inf` (UTF-16):

```
DeviceID  = "VID_1A86&PID_FFCC"
Class     = "USBDevice"
Provider  = "libwdi"
Service   = WinUSB (WinUSB.sys)
```

- **VID 0x1A86 / PID 0xFFCC** (1A86 = WCH / Nanjing Qinheng).
- Bound to **WinUSB through libwdi** - the same driver model as the Hantek
  (Zadig is libwdi's UI). No proprietary kernel driver, so a libsigrok
  driver can claim it exactly as it claims the DSO-3062L.

A separate bundled product, **ATK-PTDL32**, uses `cyusb3.inf`
(Cypress FX3, VID 0x04B4) - a different, higher-end device. Do not confuse
the two.

**No FPGA bitstream ships as a loose file** (searched `.bit .rbf .sof .jic
.svf .bin .hex .rpd` across the install tree - none). The FPGA is
presumably configured from onboard flash, with the separate
`ATK-PTDL32_Bootloader` / `EnterBootloader` path used only for firmware
updates. **This removes the single biggest scope risk** - the driver
should not need to upload a bitstream at connect.

## 3. USB transport — CONFIRMED from `pv/usb/usb_control.cpp`

| Property | Value |
|---|---|
| Bulk OUT (to device) | `0x02` |
| Bulk IN (to host) | `0x81` |
| Write frame | `[0x0A][cmd][len][data...][0x0B][CRC32]` |
| Padding | transfers padded to a multiple of **2048 bytes** |
| Read | async queued transfers, or sync bulk with a 50 ms timeout |

Note the endpoints are nearly identical to the Hantek's (OUT `0x02`,
IN `0x86`), and the framing is simpler - a header/footer with a CRC32
rather than the Hantek's fixed control-transfer preamble.

### Command set

| Code | Name | Payload |
|---|---|---|
| `0x10` | GetDeviceData | none |
| `0x11` | **ParameterSetting** | sample rate / channels / depth — encoding not yet extracted |
| `0x12` | **SimpleTrigger** | trigger config — encoding not yet extracted |
| `0x15` | Stop | none |
| `0x17` | PWM | PWM generator output |
| `0x18` | Exit | none |
| `0x80` | EnterBootloader | key |
| `0x81` | GetMCUVersion | none |
| `0x87` | SetResetState | state |
| `0x88` | GetResetState | none |

Identity strings present in `usb_control.h`:
`ATK-LOGIC-ANALYZER`, `ATK-LOGIC-ANALYZER-MCU-V1`,
`ATK-LOGIC-ANALYZER-FPGA-V1`, `ATK-LOGIC-ANALYZER-CONFIG`.
Also `MCU_ENTER_KEY`, `FPGA_ENTER_KEY`, `BOOTLOADER_ENTER_KEY`,
`SET_VERSION_ENTER_KEY`.

Note `0x17` PWM: the device has a **PWM output generator** - a feature the
DSO-3062L lacks.

## 4. Sample data format — CONFIRMED from `usb_base.cpp`

`logic_analyzer_convert_to_pc()` / `..._to_device()` transpose between the
wire layout and a flat sample array:

- Samples are **16-bit** (`uint16_t`) - one bit per channel, 16 channels.
- The wire moves **2048-byte frames**.
- Within a frame the data sits in **four parallel 512-byte segments** at
  offsets `0`, `512`, `1024`, `1536`.
- Conversion runs **256 iterations per frame**, taking 4 samples per
  iteration - one from each segment - and interleaving them.

This is a de-interleave of exactly the same kind the Hantek driver already
does with its four-byte groups, so the unpacking code is familiar
territory. A 16-bit sample maps **directly onto libsigrok's little-endian
2-byte logic unit** with no bit shuffling - the same happy accident the
DSO-3062L had.

## 5. Device capability — from the bundled manual (`ATK-Logic_en_US.pdf`)

| Property | Value |
|---|---|
| Channels | 16 |
| Interface | USB 2.0, Type-C |
| Max rate, **buffer** mode | 1 GHz (8 ch), 500 MHz (16 ch), 250 MHz (16 ch) — text extraction ambiguous, verify |
| Max rate, **stream** mode | 100 MHz (3 ch), 50 MHz (6 ch), 20 MHz (16 ch) |
| Max depth, buffer | 1 Gbit, 3.5 Gbit with RLE |
| Max depth, stream | limited by PC memory |
| Compression | RLE, optional |
| Threshold | configurable trigger threshold |

Two acquisition modes, matching what we already built for the Hantek:
**buffer** = one-shot into device memory, **stream** = continuous to the
host. Far more capable than the DSO-3062L's logic side (16 ch @ 100 MHz).

**Caution:** the bundled sample captures identify as **"DL16 Plus"**, while
the target hardware is the **DL16 Pro**. Same family, but per-model rate
and depth limits must be confirmed against the actual unit.

## 6. Configuration model — from `.atkdl` capture files

`.atkdl` is a **ZIP archive** (structurally the same idea as sigrok's
`.sr`/srzip): per-channel `channel.ini`, a global `set.ini`, decoder JSON,
and the raw samples in `0/0-0.bin`.

`set.ini` exposes the complete device configuration:

```ini
[DL16 Plus]
isSimpleTrigger=true
channelsSet=[{"enable":true,"id":0,"triggerType":1}, ... 16 entries]
settingData={"RLE":false,"isBuffer":true,"model":0,
             "selectHzIndex":10,"selectThresholdLevelIndex":2,
             "setHz":200000000, ...}
```

```ini
SamplingFrequency=200000
SamplingDepth=200000
TriggerSamplingDepth=100000
```

### This maps almost one-to-one onto libsigrok

| ATK concept | libsigrok key |
|---|---|
| `setHz` / `SamplingFrequency` | `SR_CONF_SAMPLERATE` |
| `SamplingDepth` | `SR_CONF_LIMIT_SAMPLES` |
| `TriggerSamplingDepth` | `SR_CONF_CAPTURE_RATIO` (100000/200000 = 50 %) |
| per-channel `triggerType` | `SR_CONF_TRIGGER_MATCH` (PulseView's native per-channel trigger UI) |
| `selectThresholdLevelIndex` | `SR_CONF_VOLTAGE_THRESHOLD` |
| `isBuffer` false → stream | `SR_CONF_CONTINUOUS` |
| `RLE` | `SR_CONF_RLE` |
| channel `enable` | standard channel enable |

Every significant ATK setting has a native sigrok equivalent. The driver
would need **no custom config keys** - which is precisely what makes a
single unified PulseView build clean rather than bolted-on.

## 7. Command payload encodings — EXTRACTED (phase 2)

`ParameterSetting`/`SimpleTrigger` are thin wrappers
(`Write(0x11, data, len)` / `Write(0x12, data, len)`); the buffers are
built in `pv/controller/session_controller.cpp::start()` and handed to
`session.cpp::OrderStart()`. Both encodings below come from that builder.

### `0x11` ParameterSetting — 13 bytes

| Byte(s) | Field | Encoding |
|---|---|---|
| 0 | mode flags | bit7 `0x80` = **buffer** mode; bit6 `0x40` = **RLE** |
| 1 | threshold | bit7 = sign (negative); bits 0-6 = `abs(round(volts * 10))` — **tenths of a volt** |
| 2 | sample-rate index | `selectHzIndex + 1` (wire values 1-14) |
| 3-7 | sampling depth | **5 bytes, little-endian** (up to 2^40) |
| 8-12 | trigger position depth | **5 bytes, little-endian** |

Threshold is refreshingly simple compared with the Hantek's DAC formula:
1.6 V becomes `16`, -1.4 V becomes `0x80 | 14`.

### Sample-rate table (`selectHzIndex`, 0-based)

| idx | rate | idx | rate |
|---|---|---|---|
| 0 | 1 MHz | 7 | 40 MHz |
| 1 | 2 MHz | 8 | 50 MHz |
| 2 | 4 MHz | 9 | 100 MHz |
| 3 | 5 MHz | **10** | **200 MHz** |
| 4 | 10 MHz | 11 | 250 MHz |
| 5 | 20 MHz | 12 | 500 MHz |
| 6 | 25 MHz | 13 | 1 GHz |

**Cross-checked:** the bundled `pwm_10M_30_25.atkdl` records
`selectHzIndex=10` with `setHz=200000000` — index 10 is 200 MHz, exactly
as the table predicts. The wire byte for that capture is therefore `11`.

### Threshold presets (volts, from the UI model)

`custom (-1)`, 5.0 V CMOS → **2.5**, 3.3 V CMOS → **1.6**,
3.0 V → **1.5**, 2.5 V → **1.2**, 1.8 V → **0.9**, 1.5 V → **0.7**,
1.2 V → **0.6**. Arbitrary values are allowed (custom), so the driver can
expose either a preset list or a continuous float.

Depth limits seen in the UI: **320 000 000** in one mode, and
`2^40 * 1000 - 1` in the other — consistent with the 5-byte depth field.

### `0x12` SimpleTrigger — 9 bytes

**Two channels packed per byte**, 16 channels → 8 bytes, plus one trailing
flag byte. Even channel in the **high** nibble, odd channel in the **low**:

| Nibble bit | High nibble (even ch) | Low nibble (odd ch) | Meaning |
|---|---|---|---|
| 3 | `0x80` | `0x08` | channel **enabled** |
| 2 | `0x40` | `0x04` | **high level** |
| 1 | `0x20` | `0x02` | **falling edge** |
| 0 | `0x10` | `0x01` | **rising edge** |

Condition encoding is a mask of "states that satisfy the trigger":

| UI trigger type | Condition bits | Note |
|---|---|---|
| RisingEdge | rising | |
| FallingEdge | falling | |
| DoubleEdge | rising + falling | any edge |
| HighLevel | high | |
| LowLevel | *(none)* | enable only |
| default / don't-care | rising + falling + high | always true |

Byte 8: `isInstantly` — **1 = trigger immediately** (the analogue of the
Hantek's force-trigger).

This maps **1:1 onto libsigrok's trigger matches** with no impedance
mismatch at all:

| libsigrok | ATK condition bits |
|---|---|
| `SR_TRIGGER_ONE` | high |
| `SR_TRIGGER_ZERO` | none |
| `SR_TRIGGER_RISING` | rising |
| `SR_TRIGGER_FALLING` | falling |
| `SR_TRIGGER_EDGE` | rising + falling |

That is a better fit than the DSO-3062L, whose hardware pattern trigger we
could never fully arm and had to serve with a host-side matcher.

### Capture start sequence (from `session.cpp`)

```
fpgaActive()            -> SetResetState(1)   wake the FPGA
ParameterSetting(0x11)  -> setArray           mode/threshold/rate/depth
SimpleTrigger(0x12)     -> dataBytes          per-channel trigger config
... acquisition ...
Stop(0x15) / fpgaDormancy() -> SetResetState(0)
```

`fpgaActive`/`fpgaDormancy` toggling a reset line - rather than uploading a
bitstream - is further evidence the FPGA image is resident.

## 7a. HARDWARE VERIFICATION (phase 3) — device connected

Everything in this section was confirmed against the real DL16 Pro, not
inferred. Only read-only / reversible commands were issued; `0x80`
EnterBootloader was never sent and no flash, EEPROM or calibration was
written.

### Enumeration — matches the source constants exactly

```
1a86:ffcc  Manufacturer "ATK"  Product "ATK-Logic-Analyzer"  Serial "ATK22"
USB 2.0, high speed, 250 mA
Configuration 1, Interface 0, class 0xFF (vendor specific)
  EP 0x02  OUT  BULK  maxpacket 512     (= TO_MCU_EP)
  EP 0x81  IN   BULK  maxpacket 512     (= TO_PC_EP)
```

Windows shows it as `USB\VID_1A86&PID_FFCC\ATK22`, bound to the WinUSB
class - so libusb claims it directly, exactly like the DSO-3062L.

### There are TWO command channels, and they are framed differently

This is the single most important structural finding, and it is not
obvious from the command table alone.

**MCU channel** (`SendToMCU`) - sent **raw**:

```
[0x0A][code][args...]   zero-padded to 512 bytes
```

**FPGA channel** (`SendToDevice`) - framed, then **word-interleaved**:

```
8 zero bytes | 0x0A | code | len+1 | payload | 0x0B | CRC32 (LE) | 0x00
padded to a multiple of 2048, then passed through
logic_analyzer_convert_to_device()
```

`SendToDevice` calls `logic_analyzer_convert_to_device()` on the finished
frame before submitting it. **Commands are scrambled on the wire the same
way sample data is.** A correctly framed but un-interleaved command is
ignored - that cost one debugging round and is the reason the FPGA channel
looked dead at first. `SendToMCU` does *not* transform, which is why the
MCU channel worked immediately: a clean cross-check that this reading is
right.

The transform, per 2048-byte block, in 16-bit words:

```
for i in 0..255:
    dst[  0 + i] = src[4i + 0]
    dst[256 + i] = src[4i + 1]
    dst[512 + i] = src[4i + 2]
    dst[768 + i] = src[4i + 3]
```

Replies are interleaved the same way and must be inverted.

### CRC32 — confirmed variant

`gCRC32` uses the standard reflected CRC-32 table (poly `0xEDB88320`) but
with **init 0** and final XOR `0xFFFFFFFF` - *not* the usual zlib init.
In Python that is exactly:

```python
crc = zlib.crc32(data, 0xFFFFFFFF) & 0xFFFFFFFF
```

computed over `[code][len+1][payload]` only - not the header, footer or
the 8-byte offset region.

### MCU reply format — confirmed on hardware

```
[0x0A][code echo][0x01 = ACK][payload...] then filler to 512 bytes
```

The filler byte is a **rolling transaction counter**: successive replies
filled with `04, 05, 06, 07, 08, 09, 0a...`. Useful as a liveness/sequence
check.

| Command | Sent | Reply | Meaning |
|---|---|---|---|
| GetMCUVersion `0x81` | `0a 81` | `0a 81 01 61 01 09 02 00 01` | ACK + 6 version bytes |
| GetResetState `0x88` | `0a 88` | `0a 88 01 **00**` | FPGA dormant |
| SetResetState `0x87` | `0a 87 01` | `0a 87 01` | ACK |
| GetResetState `0x88` | `0a 88` | `0a 88 01 **01**` | FPGA awake |

**The reset state round-trips 0 → 1 → 0 exactly as commanded**, which
confirms both the MCU framing and that `fpgaActive`/`fpgaDormancy` are a
simple reset-line toggle - no bitstream upload anywhere.

### FPGA channel — working, and the device names itself

With the FPGA woken and the frame interleaved, `GetDeviceData` (`0x10`)
replies. De-interleaved:

```
0000  0a 02 0d 00 ff 00 01 02 10 02 16 0b 08 44 4c 31  .............DL1
0010  36 00 0b 00 00 00 00 00 00 00 00 00 00 00 00 00  6...............
```

- framed `0x0A` ... `0x0B` as expected;
- the command byte `0x10` echoes at offset 8;
- **offset 13 holds the ASCII string `"DL16"`**, NUL-terminated, preceded
  by `08` (a length).

So `GetDeviceData` is a **device identification / hello** record, not
sample data as its name suggests. The ASCII model string is decisive proof
that the frame construction, the CRC, the interleave transform and the
reply de-interleave are all correct.

### Confirmed working sequence

```
SetResetState(1)          MCU, wake the FPGA        -> ACK
GetDeviceData(0x10)       FPGA, interleaved         -> "DL16" identity
SetResetState(0)          MCU, back to dormant      -> ACK
```

## 8. What is still unknown

1. **RLE format**, if enabled. (Avoidable: clear bit6 to disable.)
2. **Stream-mode data flow** — how continuous capture is paced and
   flow-controlled (the analogue of the Hantek's roll mode).
3. **The read path in detail** — `GetDeviceData` (`0x10`) framing and how
   end-of-capture is signalled.
4. **Per-model limits** for the DL16 **Pro** specifically; the rate table
   above is the UI's full list and some entries are presumably rejected on
   lower models or above a channel-count threshold.
5. **Channel-count vs rate coupling** — the manual quotes rate limits that
   depend on how many channels are enabled; where that constraint is
   enforced (host or device) is not yet established.

**Verification status.** Transport, both channel framings, the CRC
variant, the interleave transform, the MCU reply format and the
wake/identify sequence are now **confirmed on hardware** (section 7a).
Still transcribed-from-source and *not* yet exercised on the device: the
`0x11` ParameterSetting and `0x12` SimpleTrigger payload layouts in
section 7. Those are the next thing to test - configure a slow capture on
a known signal and check that the returned samples match.

No USB sniffer is installed on this machine (no Wireshark/USBPcap), so all
verification so far came from talking to the device directly. Installing
USBPcap would still be worthwhile before trusting the acquisition path,
since it shows exactly what the vendor app does rather than what we think
it does.

## 8. Assessment

**Feasible, and materially easier than the Hantek driver was.**

Favourable:
- Source is GPL-3.0 and readable — no DLL disassembly. GPL-3.0 into
  libsigrok's GPL-3.0-or-later is licence-compatible for a derived driver.
- WinUSB/libwdi binding, same as the Hantek — no driver-model surprises.
- No FPGA bitstream upload appears necessary.
- 16-bit samples map straight onto libsigrok's logic unit.
- Configuration maps onto standard config keys with no custom extensions.
- PulseView itself needs **zero changes**: drivers are independent modules
  under `src/hardware/<name>/` registered by `SR_REGISTER_DEV_DRIVER`, and
  our build already compiles 83 of them. The DL16 would be the 84th, and
  both devices would appear in the same device list of one binary.

Remaining effort is a normal driver build-out: extract the two payload
encodings, implement scan/open/config/acquisition, unpack the four-segment
interleave, and verify against hardware.

Risks:
- Stream mode at high rates may exceed sustained USB throughput, exactly as
  the Hantek's roll mode does (~1 M points/s there).
- The Pro/Plus model difference must be pinned down.
- RLE, if it cannot be disabled, would need decoding before any capture
  works.

---

## 10. WIRE VERIFICATION (phase 3) — captured on real hardware

USBPcap capture of ATK-Logic driving the **DL16 Pro**, 2026-08-19. The
device enumerated as **USB address 7** (`VID_1A86&PID_FFCC`, FriendlyName
`ATK-Logic-Analyzer`, instance `ATK22`), analysed with `tshark`. Four
complete acquisition cycles were captured.

**The section-7 encodings are confirmed on the wire.**

### Command sequence — exactly as predicted from source

```
0a 87 01 0b     SetResetState(1)    fpgaActive
0a 11 ...       ParameterSetting
0a 12 ...       SimpleTrigger
  ... 16 KB bulk IN transfers carry the samples ...
0a 15 ...       Stop
0a 87 00 0b     SetResetState(0)    fpgaDormancy
```

### Frame format — corrected

```
[0x0A] [cmd] [len] [data ...] [0x0B] [CRC32]
```

`len` counts **data + the 0x0B footer**: Stop carries `len=0x01` with no
data; ParameterSetting `len=0x0E` with 13 data bytes.

### Two transport classes — not visible in the source

| Class | Commands | On the wire |
|---|---|---|
| **MCU** | `0x87` (presumably all `0x8x`) | short frame (~510 B), **not interleaved** |
| **FPGA** | `0x11`, `0x12`, `0x15` | **word-interleaved, padded to 2048 B** |

Even *command* frames pass through the sample interleaver. Mapping
confirmed by inspection: four 512-byte segments at 0/512/1024/1536, with
**PC word i at device offset `(i%4)*512 + (i//4)*2`**, after an 8-byte
zero lead.

### `0x11` ParameterSetting — CONFIRMED

Captured frame, de-interleaved:

```
0a 11 0e 00 10 06 80 96 98 00 00 a0 86 01 00 00 0b d0 48 68 37
```

| Field | Bytes | Value | Meaning |
|---|---|---|---|
| flags | `00` | 0 | buffer bit clear, RLE off |
| threshold | `10` | 16 | **1.6 V** — exactly the "3.3 V CMOS" preset |
| rate index+1 | `06` | 6 | index 5 = **20 MHz** |
| depth | `80 96 98 00 00` | 10 000 000 | 5-byte LE ✓ |
| trigger depth | `a0 86 01 00 00` | 100 000 | 5-byte LE ✓ |

Every field lands where section 7 predicted, and the values are
self-consistent (a threshold matching a named preset, round depths). The
5-byte little-endian depths and the tenths-of-a-volt threshold are now
**facts, not inferences**.

### `0x12` SimpleTrigger — CONFIRMED, with one correction

```
0a 12 0b ff ff ff ff ff ff ff ff 00 00 0b 0d c2 b5 6e
```

Eight channel bytes as predicted — but the payload is **10 bytes, not 9**:
`isInstantly` is followed by one further byte (`00`), purpose unknown.

All eight channel bytes are `0xFF`: every nibble = enable + high + falling
+ rising — all 16 channels enabled with the **don't-care** condition,
precisely the `default:` branch of the vendor's switch. The nibble layout
is confirmed by real capture.

### Data return path

| Transfer size | Count | Role |
|---|---|---|
| **16384 B** | 3999 | sample data — matches `READ_TRANSFER_BUFFER_SIZE 16384` |
| 512 B | 3285 | status / short responses |

67 MB total across four acquisitions (~17 MB each, consistent with
10 M samples × 2 bytes). Samples arrive as 16 KB bulk IN reads on endpoint
`0x81`, carrying the same 2048-byte interleave.

### Still open after wire verification

- **CRC32 is a custom variant.** Standard zlib CRC-32 over the whole frame,
  over the frame minus header, and over the data alone all fail to match
  the trailing four bytes. The vendor's CRC routine must be read to
  recover polynomial/init/reflection. **This is the one blocker for
  *writing* commands**; reading is unaffected.
- The second trailing byte of `0x12`.
- Stream-vs-buffer flag semantics (this capture used flags `0x00`).

**Provenance note:** this capture recorded whatever configuration the
operator had previously exercised, so the settings were recovered *from*
the bytes rather than dictated to them. See §11 for the controlled test.

## 11. CONTROLLED A/B TEST — predictions made first, then verified

Second capture, 2026-08-19, with settings **chosen in advance** and the
expected bytes **predicted before capturing**:

- ATK-Logic: **10 MHz**, **2.5 V CMOS** threshold, **100 MSa/ch** depth,
  **1 %** trigger position, **Stream** mode.
- Signal: 1 MHz 3 V square into the pod.
- The app's own status bar independently displayed `Vth:1.2 V` for the
  "2.5 V CMOS" preset - confirming the preset table in §7 straight from
  the UI.

Captured frame, de-interleaved:

```
0a 11 0e 00 0c 05 00 e1 f5 05 00 40 42 0f 00 00 0b f8 20 ec 17
```

| Field | Predicted | On the wire | |
|---|---|---|---|
| flags (stream) | bit7 clear | `00` | ✓ |
| threshold | `0x0C` (1.2 V x 10) | `0c` = 12 → 1.2 V | ✓ |
| rate index + 1 | `0x05` (10 MHz = index 4) | `05` → index 4 | ✓ |
| depth | 100 000 000 | `00 e1 f5 05 00` = 100 000 000 | ✓ |
| trigger depth | 1 000 000 (1 % of depth) | `40 42 0f 00 00` = 1 000 000 | ✓ |

**Every field predicted correctly.** The `0x11` encoding is no longer an
inference - it has predictive power over a configuration it was not
derived from. This also establishes that **trigger depth is an absolute
sample count** equal to `capture_ratio % x depth`, which maps directly
onto `SR_CONF_CAPTURE_RATIO`.

`0x12` was byte-identical to the earlier capture
(`ff` x8 + `00 00`) - consistent, since all 16 channels were enabled with
no trigger condition set, i.e. the `default:` branch.

### Consequences

- The **sample-rate index table** (§7) is confirmed at two independent
  points: index 5 → 20 MHz (first capture) and index 4 → 10 MHz (this one).
- The **threshold law** `round(volts x 10)` is confirmed at 1.6 V and
  1.2 V, and cross-checked against the vendor UI's own readout.
- The **5-byte little-endian depth fields** are confirmed at four distinct
  values (10 M, 100 k, 100 M, 1 M).
- `flags = 0x00` for Stream is consistent with bit7 = buffer; a
  buffer-mode capture (expecting `0x80`) would close that last bit.

## 15. CRC32 — SOLVED (the last blocker)

Recovered by brute-forcing CRC parameters against nine known frame/CRC
pairs harvested from the captures. **Exactly one parameter set matches all
nine**, across MCU commands, PWM, and interleaved FPGA commands alike.

| Parameter | Value |
|---|---|
| Polynomial | `0x04C11DB7` (standard CRC-32 poly) |
| **Init** | **`0x00000000`** |
| RefIn / RefOut | true / true |
| XorOut | `0xFFFFFFFF` |
| **Covered bytes** | **`frame[1:-1]`** — command byte through last data byte, **excluding** the `0x0A` header and `0x0B` footer |
| Stored as | little-endian, immediately after the `0x0B` footer |

**Why standard CRC-32 failed earlier:** the only deviation is the initial
value. Standard CRC-32/ISO-HDLC uses init `0xFFFFFFFF`; this uses
`0x00000000`. Everything else is stock.

That makes it a one-liner with any stock CRC-32 implementation:

```python
crc = zlib.crc32(frame[1:-1], 0xFFFFFFFF) & 0xFFFFFFFF   # init = 0
frame += crc.to_bytes(4, "little")
```

(Passing `0xFFFFFFFF` as zlib's seed cancels its internal complement,
yielding a register init of zero.)

### Verification

| Frame | CRC | |
|---|---|---|
| `0a 17 02 10 0b` (PWM0 stop) | `ec 38 17 c9` | ✓ |
| `0a 17 0a 11 c8…32… 0b` (PWM 1 MHz 25 %) | `e4 84 ca 27` | ✓ |
| `0a 17 0a 11 c8…64… 0b` (PWM 1 MHz 50 %) | `9a d4 ac c9` | ✓ |
| `0a 17 0a 11 0a…05… 0b` (PWM 20 MHz) | `b6 04 b5 72` | ✓ |
| `0a 17 0a 11 64…32… 0b` (PWM 2 MHz) | `27 76 28 da` | ✓ |
| `0a 15 01 0b` (Stop) | `7d 29 4d bf` | ✓ |
| `0a 12 0b ff×8 00 00 0b` (trigger, Normal) | `0d c2 b5 6e` | ✓ |
| `0a 12 0b ff×8 00 01 0b` (trigger, Roll) | `9b f2 b2 19` | ✓ |
| `0a 11 0e 00 0c 05 …0b` (ParameterSetting) | `f8 20 ec 17` | ✓ |

Nine for nine. Note the CRC is computed over the **logical frame**, before
interleaving and padding — the same rule holds for `0x11`/`0x12` (which
are interleaved on the wire) as for `0x17`/`0x15` (which are not).

**Consequence: the driver can now construct and sign valid commands.**
The last blocker to *writing* to the device is removed.

## 14. PWM output (`0x17`) — DECODED AND VERIFIED

The DL16 has **two PWM generator outputs** (PWM0/PWM1) - a feature the
DSO-3062L lacks entirely. Encoding from
`session_controller.cpp::pwmStart/pwmStop`, then confirmed on the wire.

```cpp
maxHz = round(200000000 / hz)               // period, in 200 MHz ticks
data  = [index ? 0x21 : 0x11]               // start
      + intToBytes(maxHz)                   // period
      + intToBytes(round(maxHz*duty/100))   // high time
// stop: [index ? 0x20 : 0x10]  - sub-command only
```

### Frame layout

```
[0x0A] [0x17] [len] [sub] [period LE32] [high LE32] [0x0B] [CRC32]
```

| Sub-command | Meaning |
|---|---|
| `0x11` | PWM0 start |
| `0x21` | PWM1 start |
| `0x10` | PWM0 stop |
| `0x20` | PWM1 stop |

### Verification — predicted then captured

Set PWM0 = **1 MHz, 25 % duty**. Prediction was written before capture:

```
predicted: 0a 17 0a 11 c8 00 00 00 32 00 00 00 0b <crc>
captured:  0a 17 0a 11 c8 00 00 00 32 00 00 00 0b e4 84 ca 27
```

Stop, also as predicted:

```
predicted: 0a 17 02 10 0b <crc>
captured:  0a 17 02 10 0b ec 38 17 c9
```

Confirmed by this test:

- **Base clock = 200 MHz.** Period `0xC8` = 200 for a 1 MHz request. (Had
  the clock been 20 MHz the field would read 20.)
- **`intToBytes` default width = 4 bytes, little-endian** - previously the
  only unverified assumption in the PWM encoding. (The depth fields in
  `0x11` pass an explicit width of 5; the default is 4.)
- **`len` = data + 1 footer**, consistent with every other command
  (start: 9 data → `0x0A`; stop: 1 data → `0x02`).
- **Duty is an absolute high-time in ticks**, not a percentage.

### Observed sweep (the app re-sends on every parameter change)

| period | high | meaning |
|---|---|---|
| 200 | 100 | 1 MHz, 50 % |
| 100 | 50 | 2 MHz, 50 % |
| 10 | 5 | 20 MHz, 50 % |
| 200 | 4 | 1 MHz, 2 % |
| 200 | 50 | 1 MHz, 25 % |

The UI's 20 MHz ceiling is a **resolution floor, not a clock limit**: at
20 MHz the period is only 10 ticks, so duty is quantised to 10 % steps.
The protocol itself would accept smaller periods.

### Transport-class correction

`0x17` frames go out **short and un-interleaved**, like `0x87` - not
padded to 2048 and word-interleaved the way `0x11`/`0x12`/`0x15` are. So
the split recorded in §10 is not simply "`0x1x` = FPGA": it is the
**acquisition** commands that are interleaved, while PWM and reset control
are not. PWM is an MCU-side peripheral.

## 13. Per-channel trigger + buffer flag — VERIFIED ON THE WIRE

Controlled test: **Mode = Buffer**, **Method = Normal**, **only Channel 1
set to rising edge**, everything else left alone. Predicted in advance:
"the first channel byte changes from `ff` to `X9`". Captured:

```
0a 11 0e 80 0c 05 00 e1 f5 05 00 40 42 0f 00 00 0b ...
0a 12 0b f9 ff ff ff ff ff ff ff 00 00 0b ...
```

**Two results at once:**

**1. `flags = 0x80`** — with Mode = Buffer. Bit 7 = buffer mode is now
confirmed (previously only ever observed as `0x00` in Stream). The flags
byte is fully mapped: bit7 = buffer, bit6 = RLE.

**2. Channel byte 0 = `0xF9`** — exactly as predicted:

| Nibble | Channel | Bits | Meaning |
|---|---|---|---|
| high `F` | D0 | enable+high+fall+rise | don't care (untriggered) |
| low `9` | D1 | `1001` = enable + rising | **rising-edge trigger** |

The nibble layout of §7 is therefore confirmed against a real, deliberately
configured trigger - not just inferred from source.

### Implementation detail that matters

An **enabled channel with no trigger condition is `0xF`, not `0x0`** - all
three condition bits set means "any state satisfies", i.e. don't care. A
driver that leaves those bits clear would instead be requesting **low
level** on every channel and would never trigger. Concretely:

| Intent | Nibble |
|---|---|
| don't care (enabled, no condition) | `1111` |
| rising | `1001` |
| falling | `1010` |
| either edge | `1011` |
| high level | `1100` |
| low level | `1000` |
| channel disabled | `0000` |

### Verified state of the protocol

Everything in `0x11` and `0x12` is now confirmed on hardware:

| Field | Status |
|---|---|
| flags: buffer (bit7) / RLE (bit6) | ✓ both states observed |
| threshold (tenths of a volt) | ✓ at 1.6 V and 1.2 V |
| sample-rate index | ✓ at 10 MHz and 20 MHz |
| depth / trigger depth (5-byte LE) | ✓ at four values |
| per-channel trigger nibbles | ✓ rising vs don't-care |
| isInstantly / roll flags | ✓ all three methods |

## 12. Capture "Method" (Normal / Auto / Instant / Roll) — RESOLVED

The vendor UI's **Method** selector maps onto the last two payload bytes of
`0x12` SimpleTrigger. Captured by switching Method and re-running:

```
Method = Roll     0a 12 0b ffffffffffffffff 00 01 0b 9b f2 b2 19
Method = Instant  0a 12 0b ffffffffffffffff 01 00 0b ...
Method = Normal   0a 12 0b ffffffffffffffff 00 00 0b 0d c2 b5 6e
```

They are **two independent flag bytes, not an enum**:

| Payload byte | Flag | Set by |
|---|---|---|
| data[8] (frame idx 11) | **isInstantly** — trigger immediately | Method = Instant |
| data[9] (frame idx 12) | **roll** — continuous rolling acquisition | Method = Roll |

This also identifies the byte listed as "unknown" in §10: it is the **roll
flag**. The source snippet read in §7 showed only `isInstantly` being
appended, so the wire is the better authority here.

| Method | isInstantly | roll |
|---|---|---|
| Normal | 0 | 0 |
| Instant | 1 | 0 |
| Roll | 0 | 1 |
| **Auto** | **not yet captured** | — |

**Auto is untested.** It is most likely a *host-side* policy rather than a
device flag: `set.ini` carries `intervalTime` as an application setting,
and the very first capture showed the host simply re-issuing the whole
`0x11`/`0x12`/`0x15` sequence four times - which is what an auto-repeat
loop looks like from the wire. Expect Auto to send `0 0` and differ only
in the host re-arming.

### libsigrok mapping

| ATK Method | libsigrok equivalent |
|---|---|
| Normal | wait for the configured trigger (default) |
| Instant | force/immediate trigger - the Hantek driver's forced-capture path |
| Roll | `SR_CONF_CONTINUOUS` - same role as the Hantek's roll mode |
| Auto | frontend re-arm loop; no device support needed |

### Device identity note

The application's status bar reports the attached unit as **"DL16 Plus"**,
not "DL16 Pro". Either the Pro shares the Plus's device profile, or the
family naming differs between marketing and firmware. Worth resolving
before publishing per-model limits, but it does not affect the protocol.

---

## 16. Return path — SOLVED, and four earlier claims corrected

This section supersedes anything above that conflicts with it. It is the
result of reading the vendor's own GPL sources
(`github.com/alientek-openedv/atk-logic`, an app-specific fork with the USB
layer in `pv/usb/`, not upstream PulseView) and re-verifying every claim on
the device.

### The device does not send packed samples

The single most costly wrong assumption in this document was that the bulk-IN
stream is the same 16-bit-per-sample word format libsigrok wants. It is not.
The device sends **one channel at a time**, each frame carrying a slice of
that channel's own bitstream, dealt out round-robin over the 16 channels
(`pv/thread/thread_work.cpp`, `channelID = *analysisData.pData`). A host that
treats the stream as packed words gets every channel smeared into every
other one — which is exactly the symptom that exposed this.

The driver therefore has to transpose: accumulate per-channel bytes, then
emit whatever length all 16 channels have in common.

### Response framing

Every bulk-IN block carries **exactly one** logical frame, at block offset 0
once de-interleaved, with the remainder padded using `0b 00` filler words. No
frame ever straddles a block boundary. This matters more than it sounds:
sample payloads are opaque bytes, so scanning for the `0x0a` header is
actively harmful — real data contains `0x0a`, and a scanning parser resyncs
onto garbage and silently drops every data frame. Decode block by block.

```
[0x0a] [order] [len16 LE] [chanID] [??] [data ...] [0x00] [0x0b] [padding]
                └─────────── len16 counts from chanID ───────────┘
```

`data` is `len - 2` bytes. `chanID` is `0xff` on every frame that is not
sample data. The second byte is never read anywhere in the vendor codebase.

| order | meaning |
|---|---|
| 1 | per-channel bitstream, `[chanID][??][bits]` |
| 2 | device/FPGA info — reply to `0x10`, connect time only |
| 3 | trigger position, then per-channel byte counts |
| 4 | command acknowledge: `data[0]` = opcode, `data[1]` = status |
| 5 | progress, 5-byte LE sample counter |
| 6 | **capture/transfer finished** |

Bit order within a channel byte is **LSB first**: bit *k* of byte *b* is
sample `8b + k`. Verified against a 1 MHz square sampled at 10 MHz — LSB
first yields a period of exactly 10 samples with 100 % consistency, MSB
first yields an incoherent 6/6/8.

### Four corrections

1. **`0x12` SimpleTrigger is 9 bytes, not 10.** There is no roll/stream byte.
   Buffer versus stream is bit 7 of the ParameterSetting flags and nowhere
   else. Sending 10 bytes is not harmless: the device intermittently accepts
   the frame and then never delivers a single data frame.
2. **Order 6 is end-of-capture, not a status heartbeat.** The vendor app
   tears down on the first one. The device keeps repeating it afterwards,
   which is what made it look like a keepalive.
3. **`0x87` SetReset is not a frame.** It is a plain 512-byte MCU write whose
   only meaningful bytes are `0x0a`, `0x87`, state — no length, no `0x0b`,
   no CRC, never interleaved. The device is lenient enough to accept the
   framed form, so this was invisible on the wire.
4. **Waking the FPGA is mandatory per capture.** The vendor app leaves the
   FPGA asleep whenever it is idle and sends `0x87 01` before every
   acquisition. A dormant FPGA answers order 6 forever and never captures.

### Arming sequence, as the vendor app performs it

`pv/data/session.cpp` (`Session::OrderStart` and `fpgaActive`):

1. `0x87` with state 1 — wake the FPGA.
2. **Drain the IN endpoint until empty.** Skipping this leaves the tail of the
   previous capture in the pipe, which shows up as a few channels running
   ahead of the rest.
3. `0x11` ParameterSetting.
4. Sleep ~30 ms. The vendor comment says this is required for the FPGA's
   threshold voltage to settle.
5. `0x12` SimpleTrigger.
6. Read; the device streams unprompted.

`0x10 GetDeviceData` is **not** part of arming — it is enumeration only.

An order-4 frame with opcode `0x12` and status `3` means the parameters were
accepted; any other status means they were rejected and nothing will ever be
captured. That is the cheapest possible arming self-test.

### Teardown

`0x15` Stop is always sent when a capture ends, however it ended, followed by
a full drain of the IN endpoint.

### Verified end to end

`sigrok-cli --driver atk-dl16 --config samplerate=10m --samples 100000`
returns exactly 100000 samples in ~0.5 s, reports the trigger position, and
terminates on the device's own end-of-capture rather than on a sample count.

### Trigger — verified end to end against a live signal

With a 1 MHz square on physical **D8**, sampled at 10 MHz:

- **Channel-to-nibble mapping confirmed through the whole stack.** `D8=r`
  produces `ff ff ff ff 9f ff ff ff` — byte 4 high nibble, enable+rising —
  and `D3=r` produces `ff f9 ...`, byte 1 low nibble. Even channel in the
  high nibble, as the vendor source says.
- **Physical D8 arrives as protocol channel 8.** The header is labelled
  0-based and the numbering needs no adjustment; an earlier capture that
  appeared to show an off-by-one was simply probing D0.
- **The trigger gates acquisition.** An impossible condition (`D3=1` on a
  channel sitting constantly low) returns 0 samples and no file, rather than
  free-running.
- **Polarity and position are correct.** At 25 % capture ratio over 20000
  samples the edge adjacent to sample 5000 is rising for `=r` and falling for
  `=f`, every time, within 2-3 samples of the mark. That residual offset is
  FPGA trigger-path latency, well under one 10-sample period.

**Trigger position is reported from the END of the record.** The order-3
value is `limit - position`, so the position libsigrok wants is
`limit - reported`. Confirmed at several capture ratios.

**Edge triggers on unconnected channels fire spuriously.** A floating input
sits near the comparator threshold and produces occasional edges - rare
enough not to appear in a 2 ms record, frequent enough to satisfy an edge
trigger during arming. Level conditions do not have this problem. This is
analog behaviour of an open input, not a protocol issue, and the vendor
application is subject to the same thing.

### Real device limits — measured, not assumed

All figures with 16 channels enabled on a DL16 Pro, against a 1 MHz
reference on D8.

**Sample rates.** Every rate from 1 MHz to 500 MHz is genuine: the reference
came back at 1.000-1.008 MHz throughout, so better than 1 % across a
500-fold range. (At 1 MHz sampling the reference aliases to 0.5 MHz, which is
Nyquist, not a defect.)

**1 GHz does not work and has been removed from the driver's list.** It
returns a truncated 32768-sample record and reports the reference as
4.36 MHz. This matches the vendor UI, which only offers 1 GHz with eight
channels or fewer.

**Capture depth tops out near 266.3 Msamples.** Requests beyond that return
a short record *without any error*: 500 M gave 266,336,384 and 1 G gave
266,334,336 - agreeing to within one 2048-byte block. The driver therefore
advertises 256 Msamples, a round number safely below the cliff, and rejects
larger requests up front rather than handing back a silently truncated
capture. Verified: 256 M returns exactly 256,000,000 samples.

### Throughput — one read per poll is a trap

The session source is a timed poll. Reading a single 16 KiB chunk per
callback at a 10 ms interval caps the driver at ~1.6 MB/s no matter what USB
can sustain; a 50 Msample capture took 102 s. Reading a bounded batch per
callback (48 x 64 KiB, stopping on a short transfer) took the same capture to
9 s, and 100 Msamples runs at roughly 12 MB/s.

Fixing that exposed a latent correctness bug worth recording, because it only
appears once the host is fast enough to keep up:

- **End-of-capture arrives before the data behind it.** Order 6 is
  interleaved with sample frames still queued in the pipe, so stopping the
  moment it appears truncates the record. Wait until the endpoint actually
  runs dry.
- **Stale data carries a stale end-of-capture.** Residue from a previous run
  is not just unwanted samples - its order-6 frame terminates the *next*
  capture early. A 10 Msample request came back with 4.6 Msamples. The drain
  before arming must be thorough, and is now preceded by an explicit `0x15`
  so the device stops refilling the pipe behind it.

## 17. RLE and continuous mode

### RLE is byte-level, not sample-level

Param flag bit 6. The payload stops being a raw bitstream and becomes
`[count][value]` pairs: `value` is one byte of that channel's bitstream,
repeated `count` times. The count is a single byte, so runs cap at 255, and
counts of zero occur as end padding and expand to nothing.

Measured at 10 MHz, 200 ksamples, 1 MHz reference on D8:

| channel | raw | RLE |
|---|---|---|
| idle (D0, D3) | 25002 B | **224 B** |
| active (D8) | 25002 B | 50032 B |

Both directions are inherent to the format. An idle channel compresses about
100:1; a 1 MHz square sampled at 10 MHz has a five-byte period, so no two
adjacent bytes match, every count is 1 and the payload **doubles**. Summing
the counts reproduces the requested depth exactly on every channel, which is
the check that confirms the encoding.

### Continuous (stream) mode is bandwidth-limited, and that is physical

Buffer versus stream is param bit 7 - nothing in the trigger payload selects
it. Both modes deliver order-1 frames; the difference is that stream mode has
no depth target and runs until stopped.

Reliability over five runs each, 16 channels:

| rate | bytes/s on the wire | result |
|---|---|---|
| 1-10 MHz | up to ~20 MB/s | 5/5 exact |
| 20 MHz | ~40 MB/s | 4/5 |
| 25 MHz | ~50 MB/s | 4/5 |

16 channels at 20 MHz is 320 Mbit/s, which is past what USB 2.0 bulk
sustains, so the device gives up part-way. **Continuous is dependable to
about 10 MHz on this link; above that, use buffered acquisition.** Note the
device does not always set the stream-overflow flag in its end-of-capture
frame when this happens, so an overrun can look like a clean short capture.

### Three timing traps in the read loop

All three produce *intermittent* truncation, which is why they took so long
to pin down. None are visible until the host is fast enough to keep up.

1. **A short bulk transfer does not mean "finished".** It only means the next
   chunk is not ready. Treating it as end-of-stream truncated captures at
   exact multiples of the frame size.
2. **One read timeout does not mean "finished" either.** While streaming, the
   device pauses for longer than the 500 ms bulk timeout. Requiring four
   consecutive fully-empty polls before acting on end-of-capture took
   continuous mode from roughly half the runs succeeding to 5/5 at 10 MHz.
3. **Do not send `0x15` while arming.** The vendor sequence is wake, drain,
   param, trigger. Slipping a stop in front of it makes the device cut
   captures short after a handful of frames. Stopping belongs in teardown -
   where it must be followed by a drain, or the backlog wedges the endpoint
   and the *next* run fails its first write with `LIBUSB_ERROR_IO`.

Stale data is not just unwanted samples: it carries the previous run's `0x12`
ack and its end-of-capture frame, which together can end a new run instantly.
The drain must therefore require several consecutive empty reads, not stop at
the first one. As a backstop the driver ignores frames until the run is
armed, where either the `0x12` ack or the first data frame arms it - keying
on the ack alone loses the entire capture whenever that ack is missed.

## 18. Order 3 decoded — and what it proves about the short captures

In **buffer mode** order 3 carries, after the two `[chanID][??]` header bytes:

```
[trigger position : 5] [byte count : 5] x 16 [flags : 1]
```

all little-endian; 86 data bytes, so `len` = 88. `flags` bit0 = capacity
exceeded, bit1 = bandwidth exceeded.

**In stream mode the per-channel counts are not present.** The frame is the
same length, but parsing them anyway yields values around 2^40, which then
looks like a capture that can never complete. Gate the parse on buffer mode,
exactly as the vendor does.

### The per-channel byte count is the only reliable completion signal

The device states up front precisely how many bytes each channel will send -
25001 per channel for a 200 ksample request, identical across all 16. That
turns completion from a heuristic into an exact test, and it is immune to the
early end-of-capture frame and the mid-transfer pauses that made every
timing-based rule truncate captures.

### The intermittent short captures are a device fault, and unrecoverable

Roughly one capture in three to ten stops early. Measured against the
promised counts, with the endpoint held open:

- The device promises 25001 bytes/channel, then delivers e.g. 14848 or 20944.
- **`flags` is 0x00 on the short runs.** The device does not report the
  failure; there is no capacity or bandwidth complaint.
- **The missing data never arrives.** Held open for 17.6 s across 41
  consecutive read timeouts, nothing more came. It is lost, not late.
- It is not a settle-time problem. A 0.3 s gap between captures gave 6/6
  while a 0.6 s gap gave 3/6 - the failures are random, not timing-dependent.

So no host-side change can recover a short capture. What the driver can do,
and now does, is know exactly when it happened and say so:

    Short capture: device sent 14848 of 25001 bytes per channel
    (118784 samples of 200000). The data is not recoverable; retry.

That is the important correctness win. Before this, a short capture was
indistinguishable from a successful one and silently produced a truncated
record.

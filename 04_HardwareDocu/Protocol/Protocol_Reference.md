# Hantek DSO-3062L — Protocol Reference

The decoded USB protocol of the Hantek DSO-3062L mixed-signal
oscilloscope, as established by reverse engineering and live-hardware
verification. This is the **authoritative final state**: every claim here
is either verified on hardware or explicitly marked otherwise.

For the discovery history, dead ends and measurement details, see
[Command_Catalogue.md](Command_Catalogue.md) — the working document this
reference distils.

Status date: 2026-08-18.

---

## 1. USB transport

| Property | Value |
|---|---|
| VID:PID | `04b5:3062` (device carries its own firmware; no upload step) |
| Configuration / interface | 1 / 0 |
| Bulk OUT / IN | `0x02` / `0x86`, both 512-byte endpoints |
| Windows driver | WinUSB binding required |

**Every bulk command must be preceded by a vendor control transfer**
(`bmRequestType` OUT|VENDOR|DEVICE, request `0xb3` "BEGINCOMMAND") carrying
this fixed 10-byte payload; without it the following bulk write is
silently ignored:

```
0f 03 03 03 68 ac fe 00 01 00
```

Control request `0xb2` (IN) returns one byte: `0x01` = USB high speed.

Bulk IN data is streamed **one 512-byte packet per transfer request**;
larger requests time out.

## 2. Command set

Commands are small buffers on bulk OUT, opcode in byte 0.

| Opcode | Function | Layout section |
|---|---|---|
| `0x02` | force trigger | §4 |
| `0x03` | start collect (starts the writer) | §4 |
| `0x04` | start trigger (arms triggering) | §4 |
| `0x05` | begin sample stream | §5 |
| `0x06` | read capture state | §4 |
| `0x0c` | trigger configuration | §7 |
| `0x0d` | buffer-size code — **inert in all tests**, function unknown | — |
| `0x0e` | sample rate | §3 |
| `0x0f` | record length and trigger position | §3 |
| `0x12` | two forms: relay chain write / enable word | §6 |
| `0x13` | read start address | §5 |
| `0x15` | relay readback (semantics unreliable; returned 0 in later tests) | — |
| `0x16` | offset DACs and trigger level | §8 |
| `0x17` | read trigger address | §5 |
| `0x1b` | read length (advisory) | §5 |
| `0x41` | logic thresholds | §9 |

**Never send opcodes belonging to `dsoHTWriteCalibrationData`,
`dsoWriteFlash` or `laWriteEEROM`** — they write persistent device state.
This is the concrete reason blind opcode sweeps are unsafe on this device.

## 3. Rates and record geometry

**Sample rate** (`0x0e`, 12 bytes): a tick divider, sent negated.

```
[0] 0x0e  [1] 0        [2] mode  [3] 0
[4..7] (-ticks) as 32-bit LE     [8..11] 0
```

- Point (group) rate = `100 MHz / (ticks + 1)`; ticks follow the 1-2-5
  sequence (1, 4, 9, 19, 49, 99, ...).
- `mode` byte 2 must be 3 for dividing rates; with mode 0 the divider is
  ignored and the device stays at full rate.
- A single enabled analog channel samples at **twice** the point rate
  (two interleaved ADC cores); logic always advances at the point rate.

**Record** (`0x0f`, 12 bytes): two 24-bit values derived from record
length `L` (in points) and trigger position `pos` (percent pre-trigger):

```
pre  = pos * L / 100        post = L - pre
a = 0xfffbff - pre          b = 0xfffbff - post     (clamped at 0)
[0] 0x0f [1] 0  [2..4] a LE24  [5] 0  [6..8] b LE24  [9..11] 0
```

`0xfffbff` = 2^24 − 1025, the ring limit.

## 4. Acquisition model

The sample memory is a 2^24-point ring. The essential, hard-won facts:

1. **The write pointer resets to ~0 at `0x03` and then wraps the ring
   indefinitely** while armed. Where the trigger lands in the ring is
   therefore decided by *when* arming/triggering happens.
2. A record is readable only if it lies entirely below the ring limit:
   `trigger + post ≤ 0xfffbff` and `trigger ≥ pre`. The usable trigger
   window is `[pre, ring − post]`; at full 16 M depth it is under a
   million points wide, so deep captures require steering the arm time
   (wall-clock based — timer callbacks run ~65 ms, not their nominal
   50 ms, and drift-based estimates fail).
3. A **forced trigger sent before pre-fill completes is silently
   dropped**. Repeating the force is free; the first accepted one wins.
4. State (`0x06`, reply byte 0 & 7): 0 during fill, ready = 2, 3 or 7.
   `0x17` reads **zero until the trigger fires** — fill progress is not
   observable.

Arming sequence: `0x03` → settle ≈ 0.3 s → `0x04` → trigger (real or
forced) → poll `0x06` until ready.

Verified depths: 10 k … 16 M points, zero sample anomalies, at 100 kHz to
50 MHz (16 M at 50 MHz is geometrically impossible — window < 6 ms).

### Roll mode — continuous acquisition (VERIFIED on hardware 2026-08-18)

The normal path is one-shot: it reads a completed record once per arm.
Roll mode reads the **live** ring while the writer free-runs, giving
unbounded-duration capture — the vendor's `dsoHT*RollMode` /
`dsoHTStartRoll` / `dsoHTGetRollData` exports, none in the public header.

```
0x19 00 01 00     dsoHTOpenRollMode  (byte 2 = 1 on / 0 off)
0x03 ...          start collect
0x04 ...          start trigger - REQUIRED: the writer does not run
                  without it, even though roll never waits for a trigger
0x17              read the live write pointer (tracks the writer;
                  unlike one-shot mode it does NOT stay zero)
0x13 / 0x1b       point the read window near the pointer, length 0x800 words
0x05              read a 0x1000-point (4 KB) chunk of live data
  ... repeat 0x17 + read, following the writer, indefinitely ...
0x19 00 00 00     dsoHTCloseRollMode
```

Stream layout is the SAME four-byte groups as §5 (slot 0 CH1, 1 CH2/core B,
2 = D0-D7, 3 = D8-D15).

**Implemented in the libsigrok driver** as `SR_CONF_CONTINUOUS` (PulseView
renders a checkbox; Run/Stop streams). The driver chases the live pointer,
reading each ring region once and advancing gap-free, with two safeguards
learned in testing:

- **Guard band**: read only up to ~16 k points behind the live pointer.
  Reading right up to it catches points the writer has not finished,
  which stalls the read and wedges the bulk endpoint.
- **Resilience**: a transient stall must not end the stream. A short read
  is drained (bounded) to resync, and a failed `0x17` skips the tick
  rather than stopping. Without this, one stall ended the whole capture.
- **Overrun**: if the writer runs more than half the ring ahead of the
  read cursor, the host has fallen behind (rate above the throughput
  ceiling); the driver resyncs to the live pointer, logs the gap, and
  continues (true roll semantics).

Verified live gap-free at 200 kHz and 500 kHz (D9 square, 209/209 periods
within 5 %, no gaps, zero overruns), and mixed logic+analog. Sustained
throughput is bulk-IN bound (~1 M points/s), so continuous mode suits
rates up to ~1 MHz; faster rates stay on the one-shot 16 M path and the
driver warns when a continuous rate exceeds 1 MHz.

## 5. Reading samples

**One continuous stream per armed capture.**

```
0x17            -> 24-bit LE TRIGGER address (bytes 0-2 of reply)
record end      =  trigger + post
start           =  record end - wanted points
0x13            -> value = (start aligned down to 512) - 1, byte 7 = 0x80
0x1b            -> advisory length in 16-bit words, byte 7 = 0x00
0x05            -> stream begins on bulk IN
```

- `0x13`/`0x1b` share one layout: `[0] op [1] 0 [2..5] value LE32
  [6] value&0xff [7] flag`. Byte 6 duplicating the low byte reproduces a
  vendor bug (`shr eax, 0x20` on x86-32); the firmware tolerates it.
- The stream runs from the aligned start to the record's physical end
  **regardless of the `0x1b` value** and stops there (plus a ~1-2 k point
  tail). The first `(start & 0x1ff) + 512` points are preamble; discard.
- A read starting past the record end delivers exactly the 2048-byte
  preamble and stalls, wedging bulk IN until the next arm.
- A second `0x13`/`0x1b`/`0x05` setup after a drain or stall delivers
  nothing until re-armed. Mid-record re-setup produces data seams — never
  segment; stream once and consume in chunks.

**Stream format**: four-byte point groups.

| Slot | Single-analog mode | Dual mode |
|---|---|---|
| 0 | CH1, ADC core A | CH1 |
| 1 | CH1, ADC core B | CH2 |
| 2 | logic D0–D7 | logic D0–D7 |
| 3 | logic D8–D15 | logic D8–D15 |

## 6. The `0x12` command — relay chain and enable word

Two forms share the opcode, distinguished by bytes 2-3.

**Bit-serial relay write** (bytes 2-3 carry a mask): sets or clears ONE
relay of the front-end chain per command, with ≥ 20 ms settle after each.
Chain position `n` (0–15) is addressed as a 32-bit value `1 << (n+3)`
(set) or its complement (clear), packed:

```
[0] 0x12 [1] 0 [2..3] v LE16 [4..6] v LE24 [7] 0 [8..9] target word
```

Relay state persists across writes — always clear the full chain before
applying a new configuration. Positions 16–20 are empty.

| Chain bit | Function |
|---|---|
| 7 | CH2 AC-coupling relay |
| 8 | CH2 attenuator stage 1 (/10) |
| 9 | CH2 attenuator stage 2 (with 8: /100) |
| 10 | CH1 AC-coupling relay |
| 11 | CH1 attenuator stage 2 (with 12: /100) |
| 12 | CH1 attenuator stage 1 (/10) |
| 3, 4 | CH1 extra gain taps (real, superseded by the range model) |
| 0,1,2,5,6,13,14,15 | no data-path effect; candidates: trigger path, spares |

**IMPORTANT ORDERING**: the bit-serial writes destroy the enable word.
Write the enable word after every relay change, never before.

**Enable word** (bytes 2-3 zero): a direct register write.

```
[0] 0x12 [1..3] 0 [4..6] word LE24 [7] 0 [8..9] 0
```

| Bits | Field | Values |
|---|---|---|
| 16-18, 21 | channel mode | all set (`0x270000`) = dual CH1+CH2; clear = CH1 alone |
| 14-15 | trigger source | `11` = CH1, `00` = CH2 |
| 13 | EXT trigger | set (with 14-15 clear) = EXT as source |
| 12 | trigger HF reject | 20 MHz trigger-path filter |
| 8-11 | bandwidth limits (`bCHBWLimit`) | untested |
| 7-6 | CH1 PGA | see §7 front end |
| 5-4 | CH2 PGA | see §7 front end |
| 3-0 | inert | — |

Enabling dual mode halves each analog channel's rate (slot reassignment,
§5) — the 200 MS/s budget splits.

## 7. The analog front end

Per channel:

```
gain = attenuator (relay chain) x PGA (enable word)
```

- Attenuator: none = ×1, one stage = /10, both = /100.
- PGA field: `00` = ×1, `10` = ×2.544, `01` = ×5.033,
  `11` = **input disconnected — this is GND coupling**.
- 3 × 3 = the nine advertised 1-2-5 ranges, 10 mV/div … 5 V/div.
- AC coupling is a separate chain relay per channel (bits 10 / 7). Under
  AC (or GND), the signal centres on the coupling bias ≈ ADC count 129 at
  offset DAC 512, regardless of range.
- The PGA also scales the offset path: each PGA step needs its own offset
  DAC to stay centred (≈512 / 400 / 300).

Measured anchors (1 kHz, ×1 probes — the shipped probe is 6 MHz in the
X1 position, so all figures are low-frequency):

| Range family | volts/count | source |
|---|---|---|
| fine (×1) | 1.62 mV | 300 mVpp generator |
| /10 | 15.385 mV (2 V = 130 counts) | compensation output |
| /100 | 133 mV | compensation output |

Zero counts per range and channel are tabulated in the driver
(`src/hardware/hantek-dso3062l/protocol.c`, `dso3062l_ranges_ch1/ch2`);
CH1's are measured from compensation-output minima, several CH2 PGA-range
zeros are derived and may err by up to half a division. The /100 PGA
factors carry ~10 % uncertainty.

**Trigger configuration** (`0x0c`, 10 bytes), decoded from
`sub_10003fa0`:

```
[0] 0x0c  [1] 0
[2] ((((PWCondition&3)|(sync<<2))<<2 | (mode&3))<<2 | (slope&3)) << 1
[3] (((synmode<<3)|(videoSyncSel&7))<<1) | (videoStd&1)
[4..6] pulse width LE      [7] (pw>>24)&7      27-bit, 5 ns units
[8] hsyncNum & 0xff        [9] ((hsyncNum>>8)&3)|(laTrigMode<<3)
```

`synmode` 0 = analog sources (CH1/CH2/EXT), 5 = logic sources. `mode`
0 = edge, 1 = pulse. `slope` 0 = rising, 1 = falling. Pulse-width and
video fields are decoded but unexercised. Logic-source triggering
additionally uses `laSetTrigSource` (source − 2); undecoded on the wire,
untested.

## 8. Offset DACs and trigger level (`0x16`)

```
[0] 0x16 [1] 0 [2] sel [3] 0 [4] v&0xff [5] ((v>>8)&0x0f) | nibble [6..7] 0
```

12-bit value `v`. `sel` 0 = channel position, 1 = trigger level. Byte 5's
high nibble picks the DAC: `0x10`/`0x50`/`0x90`/`0xd0` for channels 1–4.
Wrong nibble writes land on CH1 silently. Offset slope ≈ 0.27 ADC
counts per DAC step (post-gain — gain-independent).

Trigger level (sel 1, nibble 0x10) is **source-agnostic** (works for CH1,
CH2 and EXT). Measured count↔DAC line: DAC 256/512/768 → counts
45/126/197. EXT's input scaling is unmeasured; levels for EXT are
approximate.

## 9. Logic side

- 16 channels, in stream slots 2 (D0–D7) and 3 (D8–D15) — libsigrok's
  little-endian 2-byte logic unit directly.
- Rate = point rate = `100 MHz / (ticks+1)`, verified against a 1 kHz
  reference at three settings.
- **Thresholds** (`0x41`, 4 bytes): `[0] 0x41 [1] 0 [2] DAC-A [3] DAC-B`.
  Measured calibration (this pod, grounded scope-verified square):
  `dac = 95.2 + 12.47 × volts` — 0.080 V per count, 0 V at DAC 95.
  The DLL's formula (`121.848 − 10.8696 × volts`) has the wrong sign and
  scale; the vendor corrects it with per-pod EEPROM calibration.
  **The two DACs split the channels even/odd — CONFIRMED on driven pins**:
  byte 2 gates the even channels, byte 3 the odd ones (D0 stops toggling
  exactly as byte 2 crosses the scope-measured signal top; byte 3 has no
  effect on D0 anywhere in the legal range). The vendor UI's labeling
  (Level A = D0–D7, Level B = D8–D15) does not match its own hardware.
  DAC values outside the ±6 V spec (above ~DAC 170) cause cross-channel
  anomalies; the driver clamps to ±6 V. Floating pod inputs bias to
  roughly +1.5 V.
- **The pod needs a real ground return.** Signal fed to a hook without a
  shared ground reads as mush (99 % duty artifacts); with a ground the
  same signal captures perfectly.
- Storage depth spec: 10 K–68 M/CH (vs 16 M analog); LA bandwidth 10 MHz,
  max rate 100 MHz per the manual.

### Logic (bus) trigger commands — decoded from disassembly 2026-08-18

The instrument's own bus/pattern trigger engine, from the DLL's `laSetTri*`
exports. Selected by putting `0x0c` in logic mode (`synmode = 5`); the
`la*` commands below then define the condition. All are little-endian.

| Opcode | Export | Layout | Meaning |
|---|---|---|---|
| `0x3c` | `laSetTrigSource` | `[3c 00 src 00]` | which channel/bus drives the trigger |
| `0x3d` | `laSetTriEdge` | `[3d 00 edge 00]` | edge trigger on the source |
| `0x3e` | `laSetTriDataRange` | 10 bytes, 6 data + 1 | value-range (relative) trigger |
| `0x3f` | `laSetTriDataTime` | `[3f 00 b2 b3 b4 b5 qual 00]` | pattern + duration |
| **`0x40`** | **`laSetTriDataEqu`** | **`[40 00 val_lo val_hi mask_lo mask_hi qual&3 00]`** | **bus equals a 16-bit pattern under a 16-bit mask** |
| `0x41` | `laSetTriIntr` | 8 bytes (shared opcode) | arm the logic trigger |
| `0x42` | `laSetTrigNow` | `[42 00 arg 00]` | force the logic trigger |

`0x40` is the headline: the manual's "bus value" / advanced "data" trigger
is `(bus & mask) == value`. `qual` fields (2 bits) are the equal/not-equal
or edge qualifier, values not yet mapped.

**Live status, 2026-08-18.** Hardware logic triggering *engages and works
at the source level*: with `0x0c` in logic mode (byte 3 = `0x50` for
synmode 5) and `laSetTrigSource(9)`, the capture phase-locks to a **D9
rising edge** — 10/10 captures, a consistent ~150-sample offset, versus a
random phase without it. So logic-source triggering is real and verified.

Two pieces of fine control are **not yet mapped**:
- **Polarity**: `laSetTriEdge` args 0-3 all still lock to a rising edge -
  the polarity must live elsewhere (a channel-mask form, or the source
  command), not this single byte.
- **Pattern value/mask** (`0x40`) and **arm** (`0x41` `laSetTriIntr`): the
  `==0` vs `==1` request does not change the result because the pattern
  needs arming, and `0x41` is **multiplexed with the threshold command**
  — its bytes 2-3 overwrite the logic-threshold DACs, so a naive arm
  destroys the thresholds and the pod reads all-high. Coexisting the two
  (thresholds in bytes 2-3, arm flag in bytes 4/6) is the next step.

So: **opcodes decoded, source triggering verified live; polarity and
pattern control await decoding the arm/threshold multiplexing.**

### Software pattern trigger (implemented, verified 2026-08-18)

Independent of the hardware bus trigger above, the driver provides
`SR_CONF_TRIGGER_MATCH` - PulseView's native per-channel logic trigger.
The instrument captures a full-rate record; the driver holds it, finds the
first sample matching the pattern (level 0/1, rising, falling, or edge,
ANDed across channels), emits `SR_DF_TRIGGER` there and forwards the data
aligned to it. Runs at the full logic rate (the hardware did the
sampling); the only limit is that the pattern must occur within the
captured window. Verified live: `D9=rising` matched a D9 edge and aligned
the record to it. (Note: sigrok-cli's CSV output module crashes on the
trigger packet - an upstream tool bug; PulseView and `.sr` output are
unaffected.)

## 10. What is NOT in this device

- **No waveform generator, no PWM output** — the DDS opcodes
  (`0x30`–`0x3a`) exist in the shared DLL, but the OUTPUT and sync
  connectors exist only on the DSO3062**AL**.
- The serial-in/serial-out pins on the LA connector are undocumented
  everywhere; plausibly the pod EEPROM interface. Do not drive them.
- `0x0d` (buffer-size code): all eight values tested, no observable
  effect.
- Roll/scan modes, ETS, and the WIFI opcodes (`0x29`/`0x2a`) are known to
  exist and are undecoded.

## 11. Verification summary

| Subsystem | Evidence |
|---|---|
| Deep capture | 16 M points, every comp-square period exact, multiple rates |
| Trigger CH1/CH2 | phase-locked to ±2 samples at 10/50/90 % positions |
| Trigger EXT | fires without force; captured phase random vs unrelated signal |
| Front end | nine ranges live; comp reads 0→2.015 V; GND flatlines |
| AC coupling | mean 1.29 V → 31 mV (CH1); ±152 mV symmetric (CH2) |
| Logic rate | 1000.0 Hz measured at three reported rates |
| Logic edges | D0 vs CH1 on the same node: identical duty, edges, 9985-sample periods |
| Logic banks | D0 -> bit 0, D9 -> bit 9; low and high banks both verified driven |
| Threshold split | even/odd confirmed on driven D0, D1 and D9 across both banks |

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

### Data readout — not yet working

Sending a bare `[05 00]` in the ready state returns **zero bytes**. The DLL
shows why: `dsoHTGetData` is a four-step sequence, and `0x05` is only the last
step.

| Step | Opcode | Request | Notes |
|---|---|---|---|
| 1 | `0x17` | 2 bytes | issues both IOCTLs, so it reads a value back |
| 2 | `0x13` | 8 bytes | sets `[+7] = 0x80` |
| 3 | `0x1b` | 8 bytes | |
| 4 | `0x05` | 2 bytes | reads the sample payload |

`0x13` and `0x1b` almost certainly carry the transfer length, memory bank or
channel selection. Their 8-byte layouts are the next thing to decode; until
then `0x05` has nothing to transfer. The same `0x17`/`0x13`/`0x1b`/`0x05`
grouping appears in `dsoHTGetScanData`, `dsoHTGetRollData`, `dsoHTStartRoll`
and the `dsoSD*` variants.

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

`laSetVoltDiv` taking `WORD*` for 16 entries remains the evidence for
per-channel thresholds. Whether all 16 are independent is still unproven.

## Function generator opcodes

The DSO3062L carries a DDS arbitrary waveform generator. Out of scope for the
PulseView integration, recorded for completeness.

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

1. Full request-buffer layout beyond byte 0 for each opcode.
2. Meaning of `0x13` / `0x17` / `0x1b` versus `0x05`.
3. Which opcodes the `0xb3` `CTRL_BEGINCOMMAND` handshake must precede.
4. Whether logic samples arrive through the `pCH3Data`/`pCH4Data` arguments of
   `dsoHTGetData`, as the header's shape suggests.
5. Bit 4 of the status byte.
6. Opcodes for calibration read, and their buffer format.

## Reproducing

```bash
cd 05_Software/protocol_probe
uv run map_commands.py <path to HTHardDLL.dll>
```

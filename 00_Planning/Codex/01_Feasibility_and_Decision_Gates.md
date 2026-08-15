<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Feasibility and decision gates

## Decision

Proceed with the integration as a native libsigrok driver. The core mixed
signal integration is feasible with high confidence. Complete complex-trigger
support and Linux operation remain conditional until native USB communication
is proven with a connected DSO3062L.

PulseView is a frontend around libsigrok sessions and dynamically exposes many
`sr_config` device properties. Existing libsigrok Hantek drivers demonstrate
both analog oscilloscope configuration and logic-analyzer thresholds. The
DSO3062L is not present in the surveyed driver profiles, so a new driver is
required.

Primary upstream references:

- [PulseView architecture](https://www.sigrok.org/wiki/PulseView/Architecture)
- [libsigrok hardware driver API](https://sigrok.org/wiki/Hardware_driver_API)
- [libsigrok source](https://github.com/sigrokproject/libsigrok)
- [PulseView source](https://github.com/sigrokproject/pulseview)
- [sigrok Windows guidance](https://sigrok.org/wiki/Windows)
- [sigrok Linux guidance](https://sigrok.org/wiki/Linux)

## Capability assessment

| Capability | Evidence | Confidence | Completion gate |
|---|---|---:|---|
| Find and open `04b5:3062` | Hantek INF and SDK discovery API | High | Native libusb scan and open succeed. |
| CH1/CH2 acquisition | SDK functions and manual | High | Known waveform is captured with correct scale and timing. |
| D0-D15 acquisition | SDK returns packed D0-D7 and D8-D15 streams | High | Known 16-bit pattern is decoded without bit swaps. |
| Channel enable/disable | SDK channel configuration API | High | Every channel is independently exercised. |
| Volts/div and coupling | SDK plus existing `hantek-dso` patterns | High | All documented ranges round-trip and measure correctly. |
| Timebase, sample rate, depth | SDK and device manual | High | Device-backed configuration table is recorded. |
| Logic thresholds | `laSetVoltDiv()` accepts a 16-entry SDK array | High | D0-D15 granularity, encoding, and actual voltage limits are measured. |
| Simple triggers | Existing libsigrok trigger model matches device functions | High | Low/high/rise/fall/edge tests pass. |
| Pulse/video/alternate triggers | Documented SDK call | Medium | USB commands and device behavior are characterized. |
| Bus/data/duration/relative triggers | Device UI and related Hantek structures | Medium | Protocol is decoded and a generic frontend representation is accepted. |
| Windows x64 | libusb with WinUSB; official MXE build route | High | Installer works on a clean Windows x64 system. |
| Linux x86_64 | Native libusb avoids the Windows `.sys` stack | Medium | Discovery and the full hardware matrix pass on native Linux. |

## Facts that constrain the design

- `HTHardDLL.dll`, `HTSoftDll.dll`, and `HTDisplayDll.dll` are 32-bit PE
  binaries. A 64-bit PulseView process cannot load them in-process.
- The Hantek driver archive includes x86 and AMD64 Windows kernel drivers, but
  neither driver is usable on Linux.
- `HTHardDLL.dll` uses Windows device I/O calls and the proprietary kernel
  driver. It is not a libusb wrapper.
- The device is identified by `USB\VID_04B5&PID_3062` in the supplied INF.
- The SDK exposes calibration, channel configuration, sampling, triggering,
  acquisition, state, unpacking, and a 16-entry logic-threshold array. This is
  evidence for per-channel thresholds, but USB traffic and device behavior
  must prove whether all entries are independent.
- The manual and SDK disagree on some values, including the logic-threshold
  range and at least one timebase example. Hardware measurements override
  documentation when they conflict.
- Current PulseView exposes low, high, rising, falling, and any-edge triggers.
  Its current UI cannot fully express the DSO3062L complex trigger set.
- Current libsigrok's generic trigger match contains a channel, match type, and
  one floating-point value. Bus masks, ranges, pulse widths, and relational
  expressions need a public API design before they can be generic UI features.

## Mandatory gates

### G0 — Governance and licensing

Pass when:

- the root repository and upstream fork strategy are approved;
- the GPL/PolyForm source boundary is documented;
- Hantek redistribution rights are reviewed;
- deliverables default to excluding vendor binaries and firmware.

Failure means research may continue, but no distributable bundle is produced.

### G1 - Reproducible baseline

Pass when pinned, unmodified libsigrok, sigrok-cli, libsigrokdecode, and
PulseView build and run on the selected Linux builder. Record commands,
versions, hashes, test results, and output paths.

### G1A - Optional vendor-reference characterization

Use this gate only when official-application captures do not provide a clear
enough oracle. Pass when a minimal 32-bit Windows program dynamically loads
the locally supplied `HTHardDLL.dll`, performs only documented volatile
operations, and produces a versioned result record plus correlated USB
capture. The harness must not be linked into libsigrok, exposed to PulseView,
or included with release artifacts. `HTSoftDll.dll` and undocumented exports
remain out of scope unless static call-site evidence proves they are required.

### G2 - Native USB proof

Pass when a program using libusb, without the Hantek SDK, can:

1. discover and open the DSO3062L;
2. read or reproduce required initialization state;
3. configure one safe setting;
4. arm a capture; and
5. retrieve and recognize at least one analog and one logic sample stream.

Failure triggers more protocol research; it does not justify linking the
vendor SDK into production.

### G3 — Core driver

Pass when sigrok-cli can discover the device, configure basic analog and logic
settings, perform a mixed capture, stop cleanly, and repeat without reconnecting.

### G4 — PulseView core acceptance

Pass when PulseView displays synchronized analog and logic traces, exposes the
supported standard settings, and performs a simple hardware-triggered capture.

### G5 — Advanced triggers

Pass when the generic libsigrok trigger representation, C++ bindings, PulseView
editor, driver translation, persistence, and hardware behavior all agree for
the approved complex trigger types.

### G6 — Platform delivery

Pass independently for Windows x64 and Linux x86_64. A platform is supported
only after clean-system installation, USB access, acquisition, removal, and
artifact verification succeed on that platform.

## Stop and reassess conditions

- USB traffic is encrypted, authenticated, or dependent on opaque kernel-only
  behavior that cannot be observed or reproduced.
- Required firmware cannot legally be redistributed and cannot be obtained by
  the end user through a documented extraction process.
- Calibration data cannot be read safely and no bounded fallback produces
  acceptable measurement accuracy.
- The hardware becomes unstable, overheats, disconnects repeatedly, or reports
  calibration failure during normal research operations.
- An upstream trigger API change would break compatibility without a viable
  versioned migration path.

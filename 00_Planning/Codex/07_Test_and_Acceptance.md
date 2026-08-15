<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Test and acceptance

## Evidence classes

Every result is labelled as one of:

- **offline fixture** — recorded bytes or injected transport; no device used;
- **hardware Windows/vendor** — official stack used as reference;
- **hardware Windows/WinUSB** — native libusb driver on Windows;
- **hardware Linux** — native libusb driver on Linux;
- **build-only** — compilation/link/package evidence;
- **manual inspection** — UI, physical setup, or clean-install observation.

An offline test never satisfies a hardware acceptance requirement. A build on
one platform never proves operation on another.

## Test layers

### L1 — pure unit tests

Test without USB access:

- endian and bitfield encoding/decoding;
- command lengths, markers, checksums, and reserved fields;
- threshold voltage/index/PWM conversion and bounds;
- timebase, sample-rate, memory-depth, volts/div, and coupling tables;
- trigger expression validation and wire translation;
- analog sample conversion and calibration coefficients;
- D0-D15 packed bit order;
- packet length, overflow, truncation, marker, and sequence failures;
- state transitions and invalid transition rejection;
- partial transfer accumulation and cancellation cleanup;
- configuration list/get/set consistency.

Prefer minimized binary fixtures with manifest hashes. Each parser test includes
a normal case, lower and upper boundaries, truncated input, oversized length,
invalid marker, and unexpected enum value.

### L2 — simulated transport integration

Provide a fake or replay transport at the narrow protocol/USB boundary. Test:

- scan/open/initialize/close;
- configuration command ordering;
- busy-to-armed-to-triggered polling;
- finite capture with multiple transfer chunks;
- no-trigger timeout and force trigger;
- cancellation while waiting and reading;
- unplug and short-transfer cleanup;
- repeated acquisition without stale state;
- concurrent configuration rejection.

Do not introduce a generalized abstraction solely for tests; use the smallest
callback or fixture seam accepted by upstream style.

### L3 — upstream project suites

- libsigrok: `make check` including new driver-focused tests where integrated;
- libsigrokdecode: `make check` when built;
- sigrok-cli: build and smoke commands;
- PulseView: `ctest --output-on-failure` with trigger-model tests;
- strict compiler warnings on supported development toolchains;
- sanitizer build on Linux for parser and simulated-transport tests.

Run focused tests while iterating. Run complete affected suites at phase gates
and on the final clean candidate.

### L4 — hardware characterization

Use a known signal generator, logic pattern generator, or verified loopback
source. Record instrument model, calibration status, connections, probe factors,
frequency, voltage, duty cycle, and tolerance.

Analog matrix:

- CH1, CH2, and both enabled;
- each volts/div setting with representative in-range signal;
- AC and DC coupling;
- every reported timebase or a justified boundary/equivalence partition;
- representative sample rates and every memory depth;
- DC offset/scale accuracy and frequency/time accuracy;
- clipping and near-zero signals;
- analog trigger source, slope, level, pre-trigger ratio, force, and timeout.

Logic matrix:

- each D0-D15 input using walking-one and walking-zero;
- all channels enabled and sparse combinations;
- every D0-D15 threshold entry at minimum, zero, common logic levels, and
  maximum while holding the other entries constant;
- measured switching around each threshold plus an aliasing map when changing
  one SDK entry affects more than one physical input;
- representative sample rates, depths, and pattern frequencies;
- low, high, rising, falling, and any-edge triggers across every input and each
  distinct hardware threshold group discovered.

Mixed-signal matrix:

- CH1/CH2 and D0-D15 captured from a common edge source;
- analog and digital trigger sources;
- sample alignment and trigger-index tolerance;
- disabled-channel changes between repeated captures;
- minimum and maximum practical data sizes;
- 100 repeated arm/capture/stop cycles;
- cancel, timeout, unplug, reconnect, and application restart.

Advanced trigger matrix covers every shipped mode and operator, including
boundary durations, masks with disabled bits, invalid ranges, and expressions
the hardware cannot support. Unsupported expressions must be rejected before
arming, not silently simplified.

### L5 — frontend acceptance

In PulseView verify:

- device discovery and unambiguous name;
- 2 analog and 16 logic channels with correct groups;
- enable/disable state and standard settings;
- synchronized rendering and correct units;
- acquisition start, stop, repeat, force, and trigger marker;
- simple and advanced trigger editing as applicable;
- saving and reopening captures and settings;
- clear error on disconnect or invalid configuration;
- no need to run as administrator/root after correct USB provisioning.

Use sigrok-cli first for every driver fault. PulseView acceptance begins only
after the same configuration works through sigrok-cli, which isolates frontend
issues from transport and protocol issues.

### Device-backed result matrix

Maintain this matrix as structured records as well as a human-readable table.
`Not run` is the initial state and may never be silently converted to pass.

| Test family | Windows/vendor oracle | Windows/WinUSB | Linux/libusb | Required evidence |
|---|---|---|---|---|
| Enumerate, open, close | Not run | Not run | Not run | descriptor/driver record and 100-cycle result |
| Initialization and calibration read | Not run | Not run | Not run | command trace, bounded values, no write |
| CH1/CH2 enable combinations | Not run | Not run | Not run | case manifest and waveform hashes |
| Volts/div and coupling | Not run | Not run | Not run | all advertised values and measured scale |
| Timebase/sample rate/depth | Not run | Not run | Not run | complete advertised table and timing error |
| D0-D15 enable combinations | Not run | Not run | Not run | walking-bit and sparse-enable results |
| D0-D15 thresholds | Not run | Not run | Not run | per-entry variation, switching voltage, alias map |
| Analog acquisition | Not run | Not run | Not run | known waveform, units, sample count, trigger index |
| Logic acquisition | Not run | Not run | Not run | known 16-bit pattern and bit-order proof |
| Synchronized mixed capture | Not run | Not run | Not run | common-edge alignment measurement |
| Simple analog triggers | Not run | Not run | Not run | sources, slopes, levels, force, timeout |
| Simple digital triggers | Not run | Not run | Not run | low/high/rise/fall/any-edge cases |
| Pulse/video/alternate triggers | Not run | Not run | Not run | parameter boundaries and observed behavior |
| Bus/data/range triggers | Not run | Not run | Not run | masks, relations, invalid-expression rejection |
| Duration/relative triggers | Not run | Not run | Not run | min/max/range boundaries and timing tolerance |
| Cancel, unplug, reconnect | Not run | Not run | Not run | cleanup log and reusable-device proof |
| Maximum capture and partial transfers | Not run | Not run | Not run | size, throughput, chunking, memory, no truncation |
| PulseView settings persistence | N/A | Not run | Not run | saved/reopened session and UI screenshots |
| Clean install/uninstall | N/A | Not run | Not run | artifact hashes, binding/access, rollback/removal |

### L6 — clean-platform delivery acceptance

Windows x64:

- clean supported Windows installation or snapshot;
- installer and portable ZIP hash verification;
- install without Hantek DLLs;
- manual WinUSB binding and read-only verification;
- sigrok-cli scan/capture and PulseView capture;
- upgrade, uninstall, and vendor-driver restoration;
- no leftover service, kernel driver, or writable global directory.

Linux x86_64:

- clean supported distribution or snapshot;
- portable bundle and AppImage hash verification;
- udev installation, reload, normal-user access, and removal;
- sigrok-cli scan/capture and PulseView capture;
- run without root and without unintended system libsigrok;
- uninstall/removal leaves only explicitly documented user settings.

## Performance and reliability

Record, do not merely observe:

- configuration-to-arm latency;
- trigger-to-first-data and full-transfer latency;
- sustained USB throughput and transfer chunk size;
- peak resident memory for maximum capture;
- UI responsiveness while receiving and rendering;
- timeout/cancel completion time;
- repeated-capture success rate;
- data loss, short transfer, retry, and reset counts.

Set final numeric acceptance tolerances only after the protocol and device
behavior are characterized. Until then, record measured distributions rather
than inventing guarantees.

## Traceability record

Each hardware test result records:

- requirement ID and test case ID;
- driver, PulseView, and root revisions;
- build ID and artifact hash;
- device identity, firmware/FPGA/calibration information available;
- OS, USB backend, driver binding, and physical port;
- signal setup and expected tolerance;
- exact command or UI procedure;
- log and capture evidence hashes;
- result: pass, fail, blocked, or not run;
- deviations and follow-up task.

## Product acceptance

The project is complete only when:

1. the native driver has no runtime dependency on Hantek binaries;
2. PulseView and sigrok-cli discover and operate the device on every declared
   supported platform;
3. analog, logic, mixed capture, standard settings, and required triggers have
   device-backed evidence;
4. the required complex triggers are implemented and verified through the
   generic libsigrok/PulseView architecture;
5. failure, cancellation, unplug, and repeated-capture paths are reliable;
6. delivery artifacts reproduce from locked sources and verify by checksum;
7. licences, provenance, udev/WinUSB guidance, limitations, and rollback are
   documented;
8. the exact final artifacts pass clean-system acceptance.

An owner-approved partial release may explicitly exclude capabilities, but it
does not satisfy completion of the full project goal.

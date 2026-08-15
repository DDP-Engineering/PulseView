<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# USB protocol and hardware research

## Purpose

Convert Hantek's documented high-level SDK behavior into a verified,
cross-platform USB protocol description without making the SDK a runtime
dependency.

## Safety and preservation rules

- Use the supplied USB cable directly, avoiding a hub during timing and
  throughput tests.
- Connect instrument and signal-source grounds correctly before applying a
  signal.
- Keep analog and digital inputs within the manual's limits, using conservative
  levels during discovery.
- Never invoke calibration-write, EEPROM/flash-write, FPGA-update, serial-number
  write, or firmware-update functions during protocol discovery.
- Record commands that might be nonvolatile and do not replay them until their
  effect is understood.
- Do not switch away from the Hantek driver until vendor-reference captures are
  complete and the rollback procedure is recorded.
- Treat raw USB data and device calibration values as project data; publish only
  minimized fixtures that are necessary and safe to disclose.

## Stage A — read-only Windows inventory

With the device powered and the Hantek application closed:

1. Record Windows edition, architecture, USB controller, physical port, and
   power state.
2. Record PnP instance ID, VID/PID, descriptors available through Windows,
   driver service, provider, version, date, signature, and installed INF.
3. Hash the installed driver binaries and compare them with the supplied ZIP.
4. Check whether the device has a serial number and whether identity changes by
   USB port.
5. Reopen the official application and confirm a normal acquisition before any
   capture tooling or driver change.

Planned tool: `02_Tools/research/inventory_windows_usb.ps1`. It performs only
read operations and writes a JSON report to an explicitly supplied output path.

## Stage B — capture the vendor protocol

Use USBPcap plus Wireshark or another approved URB capture path on Windows.
Capture the smallest possible session for each test:

1. start capture;
2. launch the vendor application or SDK probe;
3. change exactly one setting or perform one acquisition;
4. return the setting to baseline where appropriate;
5. close the application;
6. stop capture;
7. record test metadata and SHA-256.

Capture a baseline session twice before changing variables. Repeated identical
actions reveal sequence numbers, timestamps, polling, and nondeterministic
fields.

### Capture matrix

| Area | Controlled experiments |
|---|---|
| Enumeration | cold plug, warm plug, application open/close, reconnect |
| Initialization | device search, bus selection, calibration read, FPGA/version read |
| Analog channels | CH1 only, CH2 only, both, neither if accepted |
| Analog ranges | every volts/div value, AC/DC coupling, filter/bandwidth |
| Timing | every timebase index; every memory depth; boundary and representative sample rates |
| Thresholds | each D0-D15 entry independently at minimum, three distinguishing values, common logic levels, and maximum; test aliasing |
| Simple triggers | each source, slope, level, digital match, force trigger |
| Pulse/video | each mode with one parameter varied at a time |
| Complex triggers | bus mask/value, range, duration, edge combination, relative/data forms |
| Acquisition | normal trigger, no-trigger timeout, force, cancel, repeat, maximum depth |
| Errors | invalid SDK input where safe, unplug while idle, unplug while waiting/reading |

Never infer numeric encodings from one capture. Use at least three values that
make byte order, scale, signedness, and field location distinguishable.

### Optional SDK reference harness

Prefer the official Hantek application as the oracle. If it cannot isolate a
documented behavior, create `02_Tools/research/sdk_reference/` with its own
README and an x86 MSVC build script. The tool dynamically loads only the
operator-supplied `HTHardDLL.dll` by default and offers narrow commands such as
`inventory`, `open-close`, `configure --case <id>`, and
`acquire --case <id> --output <path>`.

Each case changes one semantic variable, waits a bounded stabilization period,
restores the baseline where safe, and writes deterministic JSON containing
input values, return codes, durations, library hashes, and output hashes. The
harness must cap device count, allocation size, sample count, and runtime. It
must not call calibration/firmware/nonvolatile setters, guess undocumented
signatures, load arbitrary DLLs, or accept arbitrary export names. Vendor DLLs
are supplied from an ignored local path and never copied to delivery.

## Stage C — organize evidence

Create this project-owned structure during implementation:

```text
04_HardwareDocu/Protocol/
├── README.md
├── USB_Descriptors.md
├── Acquisition_State_Machine.md
├── Command_Catalogue.md
├── Data_Formats.md
├── Calibration.md
├── Documentation_Discrepancies.md
└── captures/
    ├── README.md
    ├── manifest.json
    └── fixtures/
```

Large raw captures stay in an ignored local directory such as
`.work/captures/raw`. The tracked manifest contains:

- capture ID and schema;
- timestamp and operator;
- device identity and driver version;
- application/SDK version;
- physical setup and signal description;
- single variable changed;
- expected observation;
- raw file SHA-256 and local archive reference;
- minimized fixture path and SHA-256;
- confidentiality/licence classification;
- interpretation status: raw, hypothesized, confirmed, contradicted.

Every newly created directory includes a README as required by the project.

## Stage D — decode commands and data

For each transfer, determine:

- endpoint, direction, transfer type, request fields, length, and timeout;
- command marker, identifier, payload length, checksum, and sequence field;
- configuration field offsets, byte order, scale, valid range, and persistence;
- acknowledgement, error, busy, armed, triggered, complete, and retry states;
- acquisition block markers, channel interleave, sample packing, trigger index,
  padding, and termination;
- whether calibration, firmware, or FPGA state is read during initialization.

Compare with existing Hantek drivers as hypotheses only. The related 4032L
logic driver has two threshold banks and rich trigger fields that resemble the
DSO3062L UI, but the DSO3062L SDK instead supplies 16 threshold entries and
common naming does not prove an identical wire protocol.

Use small parsers with explicit bounds checks. A parser accepts raw bytes and
returns a typed record or a structured error; it does not communicate with the
device. This creates the offline unit-test seam.

## Stage E — build the native protocol probe

Create a project research tool before the production driver. Its command set is
deliberately narrow:

```text
dso3062l_probe inventory
dso3062l_probe initialize
dso3062l_probe read-calibration
dso3062l_probe configure --profile <safe-profile.json>
dso3062l_probe acquire --profile <safe-profile.json> --output <capture.bin>
```

Requirements:

- libusb only; no Hantek DLL calls;
- explicit device selection and refusal when multiple devices match;
- no firmware or nonvolatile writes;
- bounded timeout and allocation size;
- deterministic JSON metadata plus raw sample output;
- dry-run command encoding for offline tests;
- logs contain command IDs and sizes but not full sample payloads by default;
- cleanup drains transfers after success, cancel, timeout, or unplug.

The probe is a characterization tool, not an alternative end-user driver. Code
may move into the libsigrok driver only after its behavior is tested and its
licensing is compatible.

## Stage F — switch transport deliberately

### Windows

After reference captures are complete:

1. record the vendor-driver restoration procedure and driver-store identity;
2. create a restore point or equivalent rollback record where appropriate;
3. use Zadig manually to bind `04b5:3062` to WinUSB;
4. verify the selected PnP instance and USB port before applying the change;
5. run the native probe;
6. restore the Hantek driver when additional vendor-reference captures are
   needed.

Project automation may inventory and verify the bound driver but must not
silently replace it.

### Linux

1. boot a native Linux environment or VM with reliable USB passthrough;
2. record `lsusb` and verbose descriptors;
3. check kernel logs for enumeration/reset errors;
4. add a temporary least-privilege udev rule for `04b5:3062`;
5. verify access as a normal user;
6. run inventory, initialization, and capture with the same native probe.

If Linux and Windows libusb exchanges differ, first investigate driver binding,
timeouts, reset behavior, and endpoint scheduling. Do not introduce platform
protocol forks without packet evidence.

## Protocol proof acceptance

The G2 proof is complete only when:

- no Hantek SDK DLL or `.sys` driver is used by the probe process;
- device discovery and initialization are repeatable after cold and warm plug;
- at least one harmless setting produces the expected observable device state;
- a known analog waveform and a known digital pattern are present in the
  retrieved buffer with understood packing;
- all transfers and buffers clean up after normal completion and cancellation;
- the command catalogue identifies every byte used in the proof or marks it as
  an explicit unknown with repeatability evidence;
- the evidence bundle contains hashes, environment, commands, and results.

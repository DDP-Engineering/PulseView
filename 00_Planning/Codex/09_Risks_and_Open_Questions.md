<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Risks and open questions

## Purpose

This is the decision register for uncertainties that can alter architecture,
scope, schedule, safety, licensing, or platform claims. Update it whenever an
experiment changes likelihood, impact, mitigation, or a gate. A risk is not
closed by code alone; cite the requirement, capture, test, build, or legal
record that closes it.

## Risk register

| ID | Risk | Likelihood | Impact | Mitigation and evidence gate |
|---|---|---:|---:|---|
| R-01 | Supplied Hantek driver is blocked or unstable on current Windows/Secure Boot | Medium | High | Perform read-only driver/signature inventory first; prefer the official app for captures; document rollback; never weaken OS security automatically. |
| R-02 | 32-bit SDK DLL requires missing legacy runtime or behaves differently from the official application | Medium | Medium | Make the x86 harness optional; verify imports and hashes statically; load only documented exports; keep official-application captures as the primary oracle. |
| R-03 | Protocol initialization depends on undocumented state in the kernel driver | Medium | Critical | Correlate cold/warm/open traces, repeat native initialization, and stop at G2 if required exchanges cannot be reproduced safely. |
| R-04 | Undocumented SDK exports tempt unsafe signature guessing | Medium | High | Require header/import/disassembly/call-site evidence; no crash probing or arbitrary-export harness. |
| R-05 | Device requires a firmware/FPGA blob that cannot be redistributed | Medium | Critical | Identify initialization downloads and licence terms before packaging; support documented user-side extraction only if legal and repeatable; otherwise reassess delivery. |
| R-06 | Calibration is device-specific, unreadable, or unsafe to apply | Medium | High | Capture read-only initialization, bound and validate values, retain raw-versus-scaled fixture pairs, and never write calibration during research. |
| R-07 | Fast timebases use segmented/interleaved acquisition or reconstruction | High | High | Characterize every timebase index, channel combination, length, and sample ordering; do not advertise unproven modes. |
| R-08 | Memory-depth and sample-rate combinations exceed host memory or USB stability | Medium | High | Build a measured capability table, enforce integer/size caps, use chunked partial-transfer handling, and test maximum cases separately. |
| R-09 | The 16 SDK threshold values alias to fewer hardware comparators | Medium | Medium | Change one entry at a time for D0-D15 and measure switching; expose only the observed grouping in libsigrok. |
| R-10 | Generic advanced-trigger API is rejected or diverges upstream | Medium | High | Design capability-driven, backward-compatible C/C++ structures and UI independently of Hantek; seek upstream feedback before broad implementation. |
| R-11 | Device complex-trigger modes cannot all be represented without semantic loss | Medium | High | Catalogue operator, width, range, mask, source, and stage limits; reject unsupported expressions before arming; do not silently simplify. |
| R-12 | MXE/Qt/Python packaging changes break Windows x64 release builds | Medium | High | Lock toolchain inputs, prove an unmodified baseline early, record patches, and treat Wine tests as supplemental to native Windows acceptance. |
| R-13 | Linux USB behavior differs from WinUSB due to reset, claim, or scheduling semantics | Medium | High | Run the same probe and profiles on both platforms; compare packet evidence before adding platform-specific protocol logic. |
| R-14 | Driver binding changes make the vendor application unavailable or strand the device | Medium | High | Capture vendor behavior first, inventory exact PnP instance, require `[HUMAN]` binding changes, and verify vendor-driver restoration. |
| R-15 | Vendor binaries, SDK material, captures, or calibration data cannot be redistributed | High | High | Keep them in restricted/ignored locations, ship none by default, minimize fixtures, and require a recorded legal basis before inclusion. |
| R-16 | Upstream revisions drift while the project spans multiple repositories | Medium | Medium | Use immutable locks and separate fork/submodule histories; refresh deliberately and rerun affected baselines before accepting updates. |
| R-17 | USB parser defects cause overreads, oversized allocations, hangs, or corrupt frames | Medium | Critical | Length-first parsing, allocation caps, bounded timeouts, fuzz/boundary fixtures, sanitizer tests, cancellation drains, and no output on protocol violation. |
| R-18 | Hardware damage or nonvolatile state change occurs during research | Low | Critical | Use conservative input levels; exclude firmware, EEPROM, serial, and calibration writes; identify every possibly persistent command before replay. |
| R-19 | A build succeeds but silently ships a reduced driver or decoder set, for example with libsigrokdecode disabled because no cross-built Windows Python was available | Medium | High | Assert the pinned counts (87 drivers, 132 decoders) in `verify_delivery.py`; treat any shortfall as a build failure, not a warning. |
| R-20 | Upstream `sigrok-util` cross-compile scripts have bit-rotted and cannot run unmodified | High | Medium | Confirmed for the MSYS2 script, which clones a deleted libusb branch over the retired `git://` protocol; build only in a container so a failed script costs an image rebuild, and record every required patch alongside the MXE pin. |

Likelihood and impact are planning estimates until measured. Record changes in
the active AEGIS journal and link the evidence that justified them.

## Open questions and closure evidence

| ID | Question | Owner/phase | Evidence required to close |
|---|---|---|---|
| Q-01 | Does the supplied vendor driver load on the target Windows version with current security settings? | P2A `[DEVICE]` | driver inventory, signature state, successful official capture |
| Q-02 | Which exact DLLs and runtimes are required for documented SDK calls? | P2A | PE imports, controlled x86 harness load, recorded hashes |
| Q-03 | What are the complete timebase, sample-rate, and depth combinations? | P2A/P2B | exhaustive enumeration plus native replay and measured timing |
| Q-04 | How are volts/div, probe factor, offset, ADC counts, and calibration combined? | P4 | known DC/AC signals across both channels and ranges |
| Q-05 | Are all 16 threshold entries independent, and what voltage encoding/range is real? | P2A/P5 | one-entry-at-a-time captures and measured switching on D0-D15 |
| Q-06 | How are analog and logic buffers packed at each channel/timebase combination? | P2B/P4/P5 | walking patterns, known waveforms, length equations, minimized fixtures |
| Q-07 | Do fast modes interleave, segment, decimate, or reconstruct samples? | P2B/P4 | repeated captures with phase/frequency-controlled input and ordering proof |
| Q-08 | What do device search/open return values mean, and are indices stable across ports? | P2A/P2B | zero/one/multiple-device observations and cold/warm/replug records |
| Q-09 | Can the device repeatedly close/reopen and rearm without reset or process restart? | P3/P6 | 100 open/close and 100 capture cycles per supported backend |
| Q-10 | Is firmware/FPGA data uploaded, read, or selected during initialization? | P2A/P2B | initialization transfer catalogue and artifact/licence classification |
| Q-11 | What are the documented and wire-level signatures of advanced trigger functions? | P2A/P7 | header/static call-site evidence plus controlled captures; never guessed calls |
| Q-12 | Which pulse, video, alternate, data, duration, and relative modes really work? | P7 | capability catalogue and device-backed boundary tests |
| Q-13 | What generic libsigrok/PulseView API will upstream accept for complex triggers? | P7 `[HUMAN]` | written proposal, compatibility tests, upstream review decision |
| Q-14 | Can a prebuilt distribution mingw package set replace MXE's from-source Qt and Python build? | build | confirm a `mingw64-*` set (Fedora is the candidate) provides both glibmm and an embeddable Python 3; libsigrokdecode links a Windows CPython, so absence of that one package decides it |
| Q-15 | Is the pinned MXE revision still buildable now that `git://` is retired and its Qt 5.7 freeze is obsolete? | build | one clean container build of unmodified upstream sigrok before any project driver is added |
| Q-14 | Which Windows and Linux versions will be declared supported? | P8 `[HUMAN]` | clean-system matrix on exact release artifacts |
| Q-15 | May any Hantek file or derived fixture be redistributed? | P0 `[HUMAN]` | recorded licence review and explicit scope per artifact |

## Stop, narrow, or pivot criteria

Stop device experiments immediately for repeated disconnects, abnormal heat,
calibration errors, unexpected nonvolatile changes, electrical-limit concerns,
or an unbounded/hung vendor call. Preserve logs and require owner review before
continuing.

Return to protocol research rather than production implementation when G2 is
not repeatable, unexplained bytes affect acquisition, or native capture differs
from the oracle without a bounded explanation.

Narrow a platform claim when its complete clean-system and hardware matrix is
not green. A Linux build is not Linux device support; a Windows cross-build is
not WinUSB device support.

Declare a partial release only through an explicit owner scope decision. A
partial release must name omitted triggers, timebases, depths, threshold
granularity, and platforms. It must not be described as completion of the full
project goal.

Reassess the architecture if the device requires legally unavailable firmware,
irreproducible kernel-only behavior, unsafe calibration writes, or protocol
authentication that cannot be implemented lawfully and reliably. The optional
SDK harness may remain a research oracle but must not silently become a shipped
32-bit bridge.

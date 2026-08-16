<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Governance and licensing boundaries

## Status and rule of interpretation

This is an engineering classification, not legal advice. It records the most
conservative handling rule supported by the material currently available.
Specific file headers and verified licence terms override a repository-level
summary. Unclear vendor rights mean no redistribution, not implied permission.

## Material classes

| Class | Project location | Ownership/licence basis | Development use | Delivery rule |
|---|---|---|---|---|
| First-party project material | Root except upstream and vendor boundaries | PolyForm Noncommercial 1.0.0; commercial use separately licensed | Create and modify under project style | Include licence and required notice |
| Modified libsigrok/PulseView work | `05_Software/upstream/` submodules | Respective GPL upstream terms and per-file headers | Modify in independent fork histories using upstream style | Distribute only under applicable GPL terms and notices |
| Build-only open-source inputs | Ignored `.work/upstreams/` | Licence recorded in immutable lock; per-file terms govern | Build at locked commits | Include only components selected by reviewed package inventory and their notices |
| Hantek manuals, SDK, DLLs, LIBs, demo code, and drivers | `01_Documentation/` | Vendor-supplied; redistribution permission not identified | Local reference and controlled characterization only | Excluded unless written rights are established for each artifact |
| Raw USB captures and calibration evidence | Ignored `.work/captures/raw/` | Project research evidence that may include vendor/private device data | Restricted local analysis | Never delivered by default |
| Minimized protocol fixtures | `04_HardwareDocu/Protocol/captures/fixtures/` | Derived research evidence, individually reviewed | Tests after minimization and provenance review | Include only when necessary, safe, and licence-reviewed |
| Generated delivery candidates | `07_Delivery/` | Composition of approved components | Verify from locked inputs | No vendor component by default; manifest every included licence |

Copying GPL source into a PolyForm root-owned file is prohibited. First-party
scripts may orchestrate upstream builds without incorporating upstream source.
Files contributed inside an upstream fork retain that upstream project's style
and licence headers, not the project PolyForm header.

## Vendor-material review

Reviewed on 2026-08-15:

- `DSO3062_Manual.pdf`, 89 pages, SHA-256
  `9393ac5de3a6c120801dff77162585b07defe851c6f3ce4a4b7a7f5b6beb357a`;
- English SDK manuals for `HTHardDLL`, `HTSoftDLL`, and `HTDisplayDll`, with
  SHA-256 values `c0681104aa4889613095d2b07da957ac159dcead4adeab6261388b78cee31cee`,
  `b05aef0ad384358d1c9a52802bf0d7299f9de6695d3f0ab7df5c92c3ab88b13a`,
  and `84fab5c744615ec52d78f61818a993180741fab8f5ec79a6ff89b1365ad7a582`;
- SDK headers, demos, and text files;
- `DSO3062L_Driver.zip`, SHA-256
  `1d002ccdf640065f515120342f7baef162be33a8f2ea8a617f9d7017209e3c9d`,
  containing only a catalogue, INF, and x86/AMD64/IA64 driver binaries.

No licence, redistribution grant, confidentiality statement, warranty text, or
permission notice was identified in the reviewed English PDFs, SDK text/source
headers, or driver archive inventory. The manuals describe interfaces and use;
they do not establish a right to redistribute the supplied binaries or code.
Chinese manuals were not used for the initial legal classification because
parallel English editions exist; review them if an English/Chinese discrepancy
becomes material.

Consequences:

- do not copy Hantek DLLs, LIBs, SYS/CAT/INF files, manuals, or demo sources
  into upstream repositories or delivery packages;
- accept their paths only as explicit local research inputs;
- record hashes rather than embedding vendor contents in logs;
- obtain written rights before any exception;
- treat firmware, FPGA images, EEPROM, and calibration contents as separately
  restricted even if later discovered inside traffic or binaries.

Vendor material under `01_Documentation/` is tracked in this private
repository as local research input. It stays out of upstream forks and out of
`07_Delivery/` output.

## Open-source upstream review

`02_Tools/upstream/upstreams.lock.toml` records official repository licence
observations and immutable commits. At review time, the official repositories
reported GPL-3.0 for libsigrok, PulseView, libsigrokdecode, and sigrok-cli;
LGPL-3.0 for libserialport; GPL-2.0 at the sigrok-util top level; LGPL-2.1 for
libusb; and MIT for MXE core, whose downloaded packages retain their own terms.

The owner has not supplied libsigrok or PulseView fork URLs. Those two lock
entries therefore remain disabled and explicitly pending; canonical upstream
URLs are evidence sources, not authorized push destinations.

## G0 licensing exit conditions

This boundary is ready for development when:

- owner fork URLs are recorded for modified upstream work;
- each delivery component has a reviewed licence and notice path;
- vendor components remain absent or have written, artifact-specific rights;
- capture/fixture classification is recorded before tracking or publication;
- the delivery manifest can state an empty vendor-component list by default.

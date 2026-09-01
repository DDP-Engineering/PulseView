<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Licensing

This repository is **GPL-3.0-or-later by default**. Three paths are exceptions.
This file is the authoritative map; where a stray file header disagrees with the
table below, the table governs.

## The default: GPL-3.0-or-later

```
LICENSE.txt          the GNU General Public License, version 3
```

| Path | Why |
|---|---|
| `05_Software/libsigrok/` | Upstream GPL-3.0. Includes this project's own `src/hardware/hantek-dso3062l/` and `src/hardware/atk-dl16/` drivers, which compile into libsigrok and are therefore part of that work. |
| `05_Software/libsigrokdecode/` | Upstream GPL-3.0. Includes this project's added decoders, which run inside it. |
| `05_Software/pulseview/` | Upstream GPL-3.0. |
| `05_Software/sigrok-cli/` | Upstream GPL-3.0. |
| `05_Software/sigrok-util/` | Upstream GPL-2.0/GPL-3.0; see its own `COPYING.v2` and `COPYING.v3`. |
| `05_Software/libserialport/` | Upstream **LGPL-3.0**; see its own `COPYING`. |
| `05_Software/libusb/` | Upstream **LGPL-2.1**; see its own `COPYING`. |
| `01_Documentation/`, `06_SoftwareDocu/` | Documentation of the GPL software. |
| `02_Tools/` | Build, packaging, test and delivery tooling for the GPL software. |
| `04_HardwareDocu/` | This project's own protocol analysis — **except** the vendor-supplied material, which is neither ours nor GPL. See `04_HardwareDocu/README.md`. |
| `07_Delivery/` | Built packages. Each is a GPL-3.0 combined work; the corresponding source is this repository at the revision named in the package. |

Each vendored upstream keeps its own `COPYING` file, and per-file headers govern
within those trees. Nothing in this repository relicenses upstream code.
Provenance — upstream URLs, pinned commits and licenses — is recorded in
[`02_Tools/upstream/upstreams.lock.toml`](02_Tools/upstream/upstreams.lock.toml).

## The exceptions: PolyForm Noncommercial 1.0.0

```
LICENSE-PolyForm.txt   the PolyForm Noncommercial License, version 1.0.0
```

| Path | What it is |
|---|---|
| `.agentic/` | The AEGIS workflow: its contract, step files, tooling, requirements, specifications, knowledge pages and task journals. |
| `00_Planning/` | Planning material. |
| `05_Software/protocol_probe/` | Standalone USB protocol-probing scripts. They talk to devices over PyUSB and do not import, link against, or derive from any sigrok component. |

These three are independent works, not derivatives of and not combined with any
GPL component, so they may carry their own terms. Commercial use of this material
requires a separate license from DDP Engineering — contact
pasaredan1979@gmail.com.

If any of this material is ever linked into or distributed as part of the GPL
software, it becomes part of that combined work and this exception stops
applying to it.

## Third-party material that is neither

`04_HardwareDocu/Hantek_DSO3062L/` contains manufacturer-supplied reference
material — an SDK, a driver package and a product manual — redistributed under
its originator's terms, not under either license above. It is not ours to
license and is not part of the GPL work. See
[`04_HardwareDocu/README.md`](04_HardwareDocu/README.md).

## Trademarks

*sigrok* and *PulseView* are the names of the upstream project. This repository
is an unaffiliated fork and is not endorsed by, or associated with, the sigrok
project or its contributors. Package names are retained for recognisability
only.

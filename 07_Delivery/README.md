<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Delivery

Release candidates, package records, and delivery documentation. A supported
release contains exactly these five package targets from one source revision:

| Target | Artifact |
|---|---|
| Windows x86_64 | `pulseview-*-windows-x64.zip` |
| Linux x86_64, portable | `PulseView-x86_64.AppImage` |
| Linux x86_64, thin | `pulseview-*-linux-x64.tar.gz` |
| Raspberry Pi 4/5 aarch64, portable | `PulseView-aarch64.AppImage` |
| Raspberry Pi 4/5 arm64, installed | `pulseview-ddp_*_arm64.deb` |

`SHA256SUMS` is the release-completeness record. It covers exactly those five
files and is written only by `02_Tools/build/verify_delivery_set.sh` after it
rejects missing, duplicate, mixed-revision, empty, or hash-invalid packages.
The package-specific READMEs, individual `.sha256` files, and shared
`60-sigrok-instruments.rules` are supporting records, not additional targets.

Use `02_Tools/build/build_delivery_set.ps1` from Windows PowerShell to build and
verify the complete matrix. A directory without a valid five-row `SHA256SUMS`
is a candidate collection, not a completed release.

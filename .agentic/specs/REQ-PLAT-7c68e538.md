<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# REQ-PLAT-7c68e538 - Install the Raspberry Pi delivery as a Debian package

## Behavior

`build_deb.sh` packages the already-verified aarch64 AppImage payload as a
native Debian package. Installation does not execute or mount the AppImage:
the extracted AppDir is stored under `/opt/pulseview-ddp`, so FUSE is not a
runtime dependency. Removal deletes every package-owned path.

The package owns the standard `pulseview` and `sigrok-cli` commands and
therefore conflicts with and replaces Raspberry Pi OS packages that own those
same commands. Its package name is `pulseview-ddp`, keeping the custom build
distinguishable in `apt` and `dpkg` output.

## Data / interface

- Build command: `02_Tools/build/build_deb.sh [--appimage FILE] [--out DIR]`
- Test seam: `--appdir DIR --stage-only DIR` assembles but does not archive a
  supplied AppDir, allowing payload tests without an arm64 runtime or dpkg.
- Artifact: `pulseview-ddp_<version+revision>_arm64.deb`, with the source
  revision embedded as Debian local-version metadata and all characters
  normalized according to Debian policy.
- Control: package `pulseview-ddp`, architecture `arm64`, section
  `electronics`, `Depends: libc6 (>= 2.35), libstdc++6, libgl1, libegl1`,
  and conflicts/replaces/provides for `pulseview` and `sigrok-cli`.
- Payload: `/opt/pulseview-ddp`, `/usr/bin/pulseview`,
  `/usr/bin/sigrok-cli`, `/usr/share/applications/pulseview-ddp.desktop`,
  `/usr/share/icons/hicolor/48x48/apps/pulseview-ddp.png`,
  `/lib/udev/rules.d/60-sigrok-instruments.rules`, and package documentation
  under `/usr/share/doc/pulseview-ddp`.
- The desktop entry uses `Exec=pulseview`, `Icon=pulseview-ddp`, and the
  `Development;Electronics;` categories.
- `postinst` and `postrm` reload udev rules when `udevadm` is available; no
  connected device is reset or triggered automatically.
- A sibling `.sha256` file is emitted only after `dpkg-deb --info` and
  `dpkg-deb --contents` both accept the artifact.

## Examples

Normal build:

`bash 02_Tools/build/build_deb.sh`

Normal install and start:

`sudo apt install ./pulseview-ddp_0.5.0+git5aa2f17.dirty_arm64.deb`

`pulseview`

CLI dispatch:

`sigrok-cli --version`

## Acceptance

The package builds from the published aarch64 AppImage, reports `arm64` in
Debian metadata, contains every specified path, installs on 64-bit Raspberry
Pi OS, launches both commands and the desktop entry, exposes both project
drivers and decoders, and cleanly removes its owned paths.

<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Saved builder images

This directory holds `docker save` archives of the builder toolchains, tracked
through Git LFS. They are the reason a clone of this repository can be built
without the network.

## Why this exists

Building the Windows toolchain from source takes hours, and while it runs, MXE
downloads upstream source tarballs. Across MXE's package set those come from
**117 distinct hosts** - ftp.gnu.org, download.gnome.org, download.qt.io,
GitHub and a long tail of project servers. MXE checksum-verifies every one, so
corruption is not the concern; disappearance is. A single retired download URL
turns a reproducible build into an unbuildable one, and nothing about that
failure would be this project's fault or within its power to fix.

The archive removes that exposure permanently. Once it exists, no build ever
reaches those hosts again.

## Using it

```sh
02_Tools/build/load_image.sh --image mingw
```

That verifies the checksum and loads the image. About a minute, no network.

Only build the image from source when the toolchain itself must change:

```sh
02_Tools/build/build_image.sh --image mingw --skip-patch mxe_fixes.patch \
    --save 07_Delivery/toolchain/hantek-builder-mingw.tar
```

## Contents

| File | Holds |
|---|---|
| `hantek-builder-mingw.tar` | MXE cross-toolchain for Windows x86_64: gcc 11.5.0, Qt 5.15.19, glib 2.89.1 (held), glibmm 2.66.2, libusb 1.0.27 with the RAW_IO patch, plus host doxygen and NSIS |
| `*.tar.sha256` | Checksum, verified by `load_image.sh` before loading |

## Notes

**Not compressed, deliberately.** Container layers are already compressed
inside the archive; a sample gzips to 99% of its original size. Compressing
again would cost time and save nothing.

**Each revision costs its full size in LFS storage.** Git LFS does not
deduplicate between versions, so a regenerated archive adds another ~2.2 GB
that never goes away. Regenerate when the toolchain genuinely changes - a new
MXE pin, a new package, a new patch - and not merely because the image was
rebuilt.

**A clone without Git LFS gets a pointer file**, roughly 130 bytes, in place of
the archive. `load_image.sh` detects that and says so. The fix is
`git lfs install && git lfs pull`.

**The image is not a substitute for provenance.** What went into it is recorded
in `.work/logs/<build-id>/record.txt` at build time and in the image's own
OCI labels (`io.ddp.mxe.commit`, `.target`, `.patches`). Read those rather than
trusting the tag.

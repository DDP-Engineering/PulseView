<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Saved builder images

This directory holds multipart `docker save` archives of the builder
toolchains, tracked through Git LFS. The small TOML manifests remain ordinary
Git content and bind every part, the reconstructed archive, and the exact
container image ID by SHA-256.

## Why this exists

Building the Windows toolchain from source takes hours, and while it runs, MXE
downloads upstream source tarballs. Across MXE's package set those come from
**117 distinct hosts** - ftp.gnu.org, download.gnome.org, download.qt.io,
GitHub and a long tail of project servers. MXE checksum-verifies every one, so
corruption is not the concern; disappearance is. A single retired download URL
turns a reproducible build into an unbuildable one, and nothing about that
failure would be this project's fault or within its power to fix.

The archived image removes that exposure from normal application builds.

## Using it

```sh
bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform x86_64
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform aarch64
```

That validates an installed image or verifies and joins the local parts under
`.work/bootstrap/`, verifies the whole archive, loads it, deletes the temporary
whole archive, and runs an offline health check. It performs no LFS download
and publishes nothing.

Only build the image from source when the toolchain itself must change:

```sh
bash 02_Tools/build/build_image.sh --image mingw --skip-patch mxe_fixes.patch
```

If restoration is impossible, `ensure_build_environment.sh` offers that local
online rebuild itself. The rebuilt image remains only in the developer's local
container engine. To replace an archived generation deliberately, remove that
image's existing manifest and parts and run:

```sh
bash 02_Tools/build/save_image_parts.sh --image mingw
```

## Contents

| Stem | Holds |
|---|---|
| `pulseview-builder-mingw` | Windows x86_64 MXE cross-toolchain and embedded CPython |
| `pulseview-builder-appimage` | Linux x86_64 AppImage build environment |
| `pulseview-builder-appimage-arm64` | Linux arm64 AppImage build environment |

Each stem has one `*.manifest.toml` and one or more `*.tar.part-NNN` files.

## Notes

**One GiB parts, not one huge LFS object.** This keeps every object below common
free-hosting per-file limits while preserving the exact uncompressed Docker
archive. Container layers are already compressed; compressing the archive
again saves effectively nothing.

**Each changed generation costs its new content in LFS storage.** Regenerate
only when the toolchain genuinely changes - a new MXE pin, package, patch, or
other baked input - and not merely because the image was loaded again.

Regenerated once so far, on 2026-08-23, when the embedded CPython moved from
3.4.4 to 3.13.15. That is the shape of change that requires it: the archive
carries the pinned Python artifacts, so an archive older than the Dockerfile
hands a fresh clone an image that cannot build offline.

**MXE itself is not in this repository, and does not need to be.** This archive
is the toolchain; MXE is only the recipe for building it, and building from
that recipe downloads 2-3 GB of upstream source from hundreds of hosts anyway.
Vendoring the recipe without the ingredients would buy nothing. If MXE ever
disappears, this archive is what keeps the Windows build alive.

**A clone without Git LFS gets pointer files** in place of the archive parts.
The bootstrap detects the exact affected part and says so. The fix is
`git lfs install && git lfs pull`.

**The image is not a substitute for provenance.** What went into it is recorded
in `.work/logs/<build-id>/record.txt` at build time and in the image's own
OCI labels (`io.ddp.mxe.commit`, `.target`, `.patches`, `.builder.spec`). Read
those rather than trusting the tag. `io.ddp.builder.spec` is the SHA-256 of the
recipe that produced the image: the lock, the Dockerfile and its helpers, the
host-side build driver, the effective build options, and the bytes of every
patch applied. Two images with
the same label were built from the same recipe in this repository.

The three manifests currently in this directory record `builder_spec = ""`,
because the images they describe predate that label. It costs nothing:
`ensure_build_environment.sh` validates a restored image against the manifest's
exact `image_id`, which is a stronger check than recipe equivalence. The label
exists for the other case - a locally rebuilt image, whose ID necessarily
differs and which can only be recognised by its recipe.

**What the licence label does and does not say.** Both Dockerfiles set
`org.opencontainers.image.licenses="GPL-3.0-or-later"`. That is this project's
own contribution - the Dockerfiles, the helper scripts and the build recipe.
The image itself is an aggregate: a Debian or Ubuntu base, an MXE-built
cross-toolchain, GCC, Qt, boost, glib, CPython and a long tail of libraries,
each under its own upstream terms. One SPDX identifier cannot describe that
set, and no attempt is made here to do so.

There is no SBOM and no third-party licence inventory for these images. That is
a recorded gap, not a claim that none is needed: the builders are development
tooling and are not themselves redistributed as part of a release, but anyone
who does redistribute one needs an inventory this repository does not currently
provide. Producing one - and any judgement about what the aggregate requires -
is separate work outside the scope of the build tooling. The per-artifact
licence data that does exist is in `02_Tools/upstream/upstreams.lock.toml`, and
the delivered binaries (not these builders) carry their own notices under
`LICENSING.md`.

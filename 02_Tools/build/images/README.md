<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Builder images

| File | Produces | Base |
|---|---|---|
| `Dockerfile.mingw` | Windows x86_64 executables and NSIS installer, via MXE | `debian:bookworm-slim` |
| `Dockerfile.appimage` | Linux x86_64 AppImage | `ubuntu:22.04` |

Do not run `docker build` on these directly. Use `../build_image.sh`, which
stages the context, resolves pins from `upstreams.lock.toml`, and records
provenance. The mingw image in particular expects MXE to already be present in
the context, checked out at the pinned commit - it will not clone it, because
the container holds no credentials and no route to github.com.

## Base image pinning

Both files default to a tag, not a digest. `build_image.sh` pulls the tag,
resolves it to a digest, and builds against the digest, recording it in
`.work/logs/<build-id>/record.txt`.

Once a build has succeeded, copy that digest into the `ARG BASE_IMAGE` default
so the file is self-pinning. Placeholder digests are not used here: a
fabricated digest that happens to be syntactically valid is worse than an
honest tag, because it fails at pull time with a confusing error instead of
being visibly unfinished.

## What lives in an image

The toolchain only. No sigrok source, no project code. Sources are mounted at
build time, so editing the driver never rebuilds the image.

That split is what makes the second and every later build take minutes.

## Build arguments worth knowing

`Dockerfile.mingw`:

| Argument | Default | Effect |
|---|---|---|
| `MXE_QT5_FREEZE` | `0` | `1` reproduces upstream's Qt 5.7 freeze for Windows XP. This project does not claim XP support. |
| `MXE_APPLY_SIGROK_PATCHES` | `1` | `0` builds a plain MXE, to isolate a patch that will not apply. |
| `PKG_JOBS` x `SUB_JOBS` | `6` x `4` | MXE parallelism. The product is the real load; keep it at or under the core count. |
| `MXE_COMMIT` | `unrecorded` | Verified against the staged clone's `HEAD`. A mismatch fails the build. |

`Dockerfile.appimage`:

| Argument | Default | Effect |
|---|---|---|
| `APPIMAGETOOL_VERSION` | none | Required. From the lock's artifact table. |
| `APPIMAGETOOL_SHA256` | none | Required. An unverified download is not accepted into a release toolchain. |

## The Ubuntu 22.04 choice

An AppImage runs on any glibc newer than the one it was built against, and
none older. So the base image is the compatibility floor of the Linux
delivery.

Upstream's script targets Ubuntu 16.04 for maximum reach, but 16.04 is long
EOL and its archive has moved. 22.04 gives glibc 2.35 and is supported into
2027. Lowering the floor later means changing this base and rebuilding - it is
not something that can be patched into an existing AppImage.

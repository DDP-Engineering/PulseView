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
| `Dockerfile.appimage` | Linux AppImage, x86_64 and aarch64 | `ubuntu:22.04` |

Do not run `docker build` on these directly. Use `../build_image.sh`, which
stages the context, resolves pins from `upstreams.lock.toml`, and records
provenance. The mingw image in particular expects MXE to already be present in
the context, checked out at the pinned commit - it will not clone it, because
the container holds no credentials and no route to github.com.

## Base image pinning

The Dockerfiles retain readable tag defaults for direct inspection, but the
supported `build_image.sh` path reads immutable digest references from
`upstreams.lock.toml`, selects the requested platform, verifies that the base
can be pulled, and records the exact reference in `.work/logs/<build-id>/`.

## What lives in an image

The toolchain only. No sigrok source, no project code. Sources are mounted at
build time, so editing the driver never rebuilds the image.

That split is what makes the second and every later build take minutes.

## Build arguments worth knowing

`Dockerfile.mingw`:

| Argument | Default | Effect |
|---|---|---|
| `MXE_QT5_FREEZE` | `0` | `1` reproduces upstream's Qt 5.7 freeze for Windows XP. This project does not claim XP support. |
| `MXE_PATCHES` | empty | Space-separated patch filenames to apply, in order. `build_image.sh` computes it from `--skip-patch` / `--no-sigrok-patches` and verifies each one applies before the build starts. |
| `MXE_GLIB_VERSION` | `2.89.1` | Holds glib at this version; the newest that builds glibmm. `--glib-version` overrides it. |
| `PKG_JOBS` x `SUB_JOBS` | `6` x `4` in the Dockerfile | MXE parallelism. `build_image.sh` passes `nproc/4` x `4` unless told otherwise. The product is the real load; keep it at or under the core count. |
| `MXE_COMMIT` | `unrecorded` | Verified against the staged clone's `HEAD`. A mismatch fails the build. |

`Dockerfile.appimage`:

| Argument | Default | Effect |
|---|---|---|
| `APPIMAGETOOL_VERSION` | none | Required. From the lock's artifact table. |
| `APPIMAGETOOL_SHA256` | none | Required. An unverified download is not accepted into a release toolchain. |

Both are inputs to the builder recipe identity: `builder_spec.sh` hashes the
Dockerfile, the lock, `build_image.sh`, the helper scripts, the effective
options and the bytes of every patch selected, so two images that differ in any of them
carry different `io.ddp.builder.spec` labels.

## The aarch64 AppImage builder

`Dockerfile.appimage` builds for `linux/arm64` as well, selected with
`build_image.sh --image appimage --platform aarch64`. Only the lock entry
names differ by architecture; appimagetool, linuxdeployqt and the type-2
runtime all ship aarch64 assets. On an x86_64 host this needs qemu binfmt -
`check_host.sh` reports whether it is registered.

## The Ubuntu 22.04 choice

An AppImage runs on any glibc newer than the one it was built against, and
none older. So the base image is the compatibility floor of the Linux
delivery.

Upstream's script targets Ubuntu 16.04 for maximum reach, but 16.04 is long
EOL and its archive has moved. 22.04 gives glibc 2.35 and is supported into
2027. Lowering the floor later means changing this base and rebuilding - it is
not something that can be patched into an existing AppImage.

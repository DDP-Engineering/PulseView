<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Build

Container definitions and build drivers for the sigrok stack. This page is
how to run it; `STATUS.md` beside it records what is verified and the
findings behind each choice.

## Why a container at all

libsigrok has no runtime plugin ABI. Drivers are collected at link time, so
adding the DSO3062L means recompiling libsigrok, and on Windows PulseView is
statically linked against it, so that means recompiling PulseView too.

That rebuild needs a large cross-toolchain. Putting it in a container keeps it
off the Windows host, makes it reproducible, and lets the complete environment
be preserved as checksum-verified `docker save` parts.

## Two stages

The distinction matters more than anything else here.

**Stage 1 - build the toolbox. Hours, once.**
`build_image.sh` produces an image containing MXE with every sigrok dependency
already cross-compiled for Windows. It contains none of this project. Changing
our driver never invalidates it.

**Stage 2 - build the app. Minutes, every change.**
`run_in_builder.sh` mounts the repository into that image and compiles
libserialport, libsigrok, libsigrokdecode, sigrok-cli and PulseView.

## Where things go

| Location | Contents |
|---|---|
| `.work/build-context/<image>/` | staged Docker context: MXE clone, patches |
| `.work/logs/<build-id>/` | build log and provenance record |
| container volume `pulseview-build-<image>` | out-of-tree build trees |
| `07_Delivery/staging/<build-id>/` | candidate artifacts |
| `07_Delivery/releases/<version>/` | verified releases |

Only finished, verified artifacts belong in `07_Delivery`. Everything
intermediate stays in `.work/`, which is ignored and safe to delete.

## Running it

Run these **inside WSL** (`wsl -d Ubuntu-24.04`), not Git Bash - the container
engine lives there. The repository is visible under `/mnt/<drive letter>/`;
this project's own checkout is `/mnt/f/2026_PulseView`, and every script
derives its own root, so nothing depends on that path.

Scripts are run as `bash <path>` rather than `./<path>`: all of them are
tracked with Git mode `100644`, so a fresh clone gets them
non-executable.

For a release, the Windows host has one owner command instead of a handwritten
mixture of WSL and Git Bash steps:

```powershell
.\02_Tools\build\build_delivery_set.ps1 -Plan
.\02_Tools\build\build_delivery_set.ps1
```

It produces the required Windows x86_64 ZIP, Linux x86_64 AppImage and thin
tarball, Raspberry Pi aarch64 AppImage and arm64 Debian package. The final
`verify_delivery_set.sh` gate writes `SHA256SUMS` only when exactly one of each
exists at the same source revision. Builder images and arm64 binfmt remain
one-time/per-boot prerequisites; see `01_Documentation/Environment_Setup.md`.

### Which builds need the network

| Path | Network | Why |
|---|---|---|
| Windows ZIP (`build_windows_mxe.sh`) | none | Cross-compiles inside the archived MXE builder; every input is baked in. |
| AppImage, x86_64 and aarch64 (`build_appimage.sh`) | none | Same: the archived AppImage builder carries the packaging tools and runtime. |
| Raspberry Pi `.deb` (`build_deb.sh`) | none | Repackages the verified AppImage inside the same builder. |
| Linux thin tarball (`build_linux.sh`) | **required, every run** | It links against Ubuntu's own runtime libraries, so it installs them with `apt` at build time. The base image is digest-pinned in the lock; the apt transaction resolves against the live Ubuntu archive. |
| Builder image rebuild (`build_image.sh`) | required | The deliberate fallback when an archive cannot be restored. |

So "normal builds need no network" holds for the three archived-builder
paths and not for the thin tarball. Making that one offline too would mean
a dedicated archived Linux builder, which fixes the distribution the
tarball links against at archive time - a delivery decision, not a
cleanup, and one nobody has taken yet.

### Online rebuild source

A builder-image rebuild needs the network. If the developer
accepts a local image rebuild, `build_image.sh` clones MXE from the canonical
HTTPS URL in `upstreams.lock.toml`, verifies the full commit pin, and stages it
into the container context. `--mxe-src PATH` uses an existing local clone
instead.

Stage the context and print the command without building:

```bash
bash build_image.sh --image mingw --dry-run
```

Build the Windows toolchain:

```bash
bash build_image.sh --image mingw
```

Get a shell in it:

```bash
bash run_in_builder.sh --image mingw
```

Write checksum-verified 1 GiB Git LFS parts from the local image:

```bash
bash save_image_parts.sh --image mingw
```

This creates local files only. Committing and publishing them is a deliberate
developer operation, not something any repository script performs.

## Two images, not one

`Dockerfile.mingw` and `Dockerfile.appimage` are separate because they want
opposite things from their base. MXE prefers a current Debian. An AppImage
wants the oldest base still worth supporting, because it runs on any glibc
newer than the one it was built against and none older - so the base choice
*is* the Linux compatibility floor. Merging them would silently raise that
floor.

## The offline story, honestly

The **first** build of the mingw image downloads upstream source tarballs;
MXE fetches Qt, Python, boost and the rest. That step needs the internet.

After that, `save_image_parts.sh` writes the complete built environment as a
manifest plus Git LFS-sized parts, and no later build **from an archived
builder** reaches the network - that is the Windows ZIP, both AppImages and
the `.deb`. The thin Linux tarball is the exception and always has been: see
the table above. The sigrok sources themselves
cannot expire at all: `05_Software/` holds them as plain files in this
repository, so a clone carries every source the build needs.

So the accurate claim is "offline after the first toolchain build", not
"offline from a cold start". Getting to a cold-start-offline build would mean
also archiving MXE's tarball cache, which the current design deliberately
deletes to halve the image size.

## Container engines

Every entry point takes `--engine` and honours `BUILDER_ENGINE`, defaulting
to `docker`. Docker is the only engine this project's builds are verified
on - `STATUS.md` records every verification against it. Podman is accepted
because the scripts use no Docker-only command on the build path, but no
delivery has been produced with it, so treat it as untested rather than
supported.

## Known sharp edges

- Building from a Windows drive is slow: it reaches WSL over 9p.
  `run_in_builder.sh` puts build trees in a container volume for this reason.
  Do not move them back to the mount for convenience.
- `mxe_fixes.patch` no longer applies to the pinned MXE and is expected to be
  skipped; `libusb1_upgrade.patch` applies and should be kept, because it
  enables WinUSB RAW_IO for 512-byte-aligned transfers, which is this device's
  endpoint size. So the working invocation is:

  ```bash
  bash build_image.sh --image mingw --skip-patch mxe_fixes.patch
  ```

  `build_image.sh` checks each patch before building and refuses to start if
  one will not apply, so this cannot silently regress. See `STATUS.md`.
- The upstream README freezes Qt at 5.7 for Windows XP. This project does not
  claim XP, so the freeze is off by default. `--qt5-freeze` restores it.
- `sigrok-util`'s own MSYS2 script is broken and is not used here; see
  planning doc 06.

Everything in this directory that is marked verified has been run. The five
required package formats share one release coordinator; the Raspberry Pi
Debian package has also been installed, GUI-launched, removed, and reinstalled
on the physical Pi. `STATUS.md` is the ledger: which script, on which host,
with which command, and what each one's known limitation is.

For the operator's route from a fresh clone through to a build, see
`01_Documentation/Environment_Setup.md`.

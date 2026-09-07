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

## Lifecycle contracts and identities

`images/dependencies.mingw.toml` and `images/dependencies.appimage.toml` are the
source of truth for direct packages and required probes. `dependency_contract.py`
strictly selects one architecture, writes canonical JSON, and generates the
package list consumed by each Dockerfile. The same normalized contract is
embedded for later verification.

The lifecycle keeps three identities separate:

- `builder_recipe_spec` covers only selected image-content inputs;
- `dependency_contract_spec` covers the normalized selected declaration; and
- `validation_policy_spec` covers verifier code and mandatory tests.

A verifier-policy change therefore requires new validation evidence, not a
multi-gigabyte image rebuild. A resolved package inventory records transitive
packages. The promoted manifest binds that inventory and its derived SPDX 2.3
JSON SBOM to the exact image generation.

### Adding or changing a builder dependency

Edit the selected contract first:

- `images/dependencies.mingw.toml` for the Windows cross-builder;
- `images/dependencies.appimage.toml` for either AppImage architecture; and
- `upstreams.lock.toml` only when the dependency is a checksum-pinned external
  artifact or another selected upstream input.

Do not add a second package list to a Dockerfile. `build_image.sh` derives the
installation list from the contract, embeds the same normalized declaration,
and records the complete resolved distribution-package inventory. Standard
verification checks every declared package, command, file, module, header,
library, and target output that applies to the selected architecture. Full
verification then performs the clean offline product build and its mandatory
functional checks. AppImage promotion runs against the exact clean Ubuntu base
pinned in `upstreams.lock.toml`; an ambient `APPIMAGE_RUNTIME_IMAGE` override
is ignored so promotion evidence cannot vary between developer hosts.

Review the identity and affected generation before the expensive operation:

```bash
bash 02_Tools/build/update_builder_environment.sh \
  --image appimage --platform amd64 --plan
```

After review, `--replace` performs the build, checks, archive round trip, and
transactional local replacement. Git staging, commit, LFS transfer, and
publication remain separate developer actions.

### Lightweight verification for lifecycle changes

The repository suite exercises contracts, identities, bootstrap selection,
manifest validation, and transaction failure points without creating a real
multi-gigabyte image:

```bash
bash 02_Tools/test/run_tests.sh
```

The new Python tools are also checked with:

```bash
ruff format --check 02_Tools/build/*.py
ruff check --select F 02_Tools/build/*.py
python3 -m py_compile 02_Tools/build/*.py
```

For changed lifecycle shell scripts, run ShellCheck at warning severity; its
informational `SC1091` messages for repository-relative sourced helpers are
expected:

```bash
shellcheck --severity=warning -x <changed-script> ...
```

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
bash 02_Tools/build/build_image.sh --image mingw --dry-run
```

Build the Windows toolchain:

```bash
bash 02_Tools/build/build_image.sh --image mingw
```

Get a shell in it:

```bash
bash run_in_builder.sh --image mingw
```

Plan, then explicitly build, qualify, archive, audit, and promote a canonical
builder generation:

```bash
bash update_builder_environment.sh --image mingw --plan
bash update_builder_environment.sh --image mingw --replace
```

Use `--image appimage --platform amd64` or `arm64` for the other variants.
Plan mode has no output effects. Replacement requires Docker and serializes
updates per variant. The coordinator uses a content-derived candidate tag,
unique volume, and `.work/` output. It runs the mandatory product matrix,
rejects exit 77, proves an exact archive load, writes schema-2 provenance,
commits the stable manifest last, and only then applies the stable local tag.
It creates local files only. Repository
staging, commits, pushes, LFS uploads, registry pushes, and publication remain
explicit maintainer operations.

`save_image_parts.sh` remains the lower-level export primitive. Do not use it
as a substitute for candidate qualification.

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

After that, `update_builder_environment.sh` writes the complete qualified
environment as a schema-2 manifest, provenance sidecars, and Git LFS-sized
parts. No later build **from an archived builder** reaches the network - that is the Windows ZIP, both AppImages and
the `.deb`. The thin Linux tarball is the exception and always has been: see
the table above. The sigrok sources themselves
cannot expire at all: `05_Software/` holds them as plain files in this
repository, so a clone carries every source the build needs.

So the accurate claim is "offline after the first toolchain build", not
"offline from a cold start". Exact archive restore is reproducible. Exact
online reconstruction is deferred: it would require dated distribution
snapshots or preserved package payloads as well as MXE's source cache.

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
- The repository-owned `builder_profile.mingw.toml` is automatic.
  `mxe_fixes.patch` is excluded because it no longer applies to pinned MXE;
  `libusb1_upgrade.patch` remains selected because it enables WinUSB RAW_IO
  for transfers aligned to this device's 512-byte endpoint size. A normal
  `build_image.sh --image mingw` needs no remembered exception. Experimental
  command-line overrides produce distinct recipe identities.
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

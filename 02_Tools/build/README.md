<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
off the Windows host, makes it reproducible, and reduces the offline archive to
a single `docker save` tarball.

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
| container volume `hantek-build-<image>` | out-of-tree build trees |
| `07_Delivery/staging/<build-id>/` | candidate artifacts |
| `07_Delivery/releases/<version>/` | verified releases |

Only finished, verified artifacts belong in `07_Delivery`. Everything
intermediate stays in `.work/`, which is ignored and safe to delete.

## Running it

Run these **inside WSL** (`wsl -d Ubuntu-24.04`), not Git Bash - the container
engine lives there. The repository is visible at `/mnt/f/2026_PulseView`.

### One-time prerequisite: SSH access from WSL

WSL has its own home directory, so SSH keys set up under Windows are not
visible to it. `build_image.sh` clones MXE from the Gitea mirror and will stop
with a readable error until this is done:

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname) hantek build"
cat ~/.ssh/id_ed25519.pub
```

Add that public key to Gitea under Settings -> SSH Keys. If you would rather
not, clone MXE somewhere you already have access and pass `--mxe-src PATH`.
Copying a private key from the Windows home directory is not recommended and
the script does not suggest it.

Stage the context and print the command without building:

```bash
./build_image.sh --image mingw --dry-run
```

Build the Windows toolchain:

```bash
./build_image.sh --image mingw
```

Get a shell in it:

```bash
./run_in_builder.sh --image mingw
```

Write the offline archive:

```bash
./build_image.sh --image mingw --save 07_Delivery/toolchain/mingw-builder.tar
```

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

After that, `docker save` writes the complete built environment to one
tarball, and no later build reaches the network. The sigrok sources themselves
are already offline: `05_Software/` points at the Gitea mirrors, never GitHub.

So the accurate claim is "offline after the first toolchain build", not
"offline from a cold start". Getting to a cold-start-offline build would mean
also archiving MXE's tarball cache, which the current design deliberately
deletes to halve the image size.

## Known sharp edges

- Building from `/mnt/f` is slow: the Windows drive reaches WSL over 9p.
  `run_in_builder.sh` puts build trees in a container volume for this reason.
  Do not move them back to the mount for convenience.
- `mxe_fixes.patch` no longer applies to the pinned MXE and is expected to be
  skipped; `libusb1_upgrade.patch` applies and should be kept, because it
  enables WinUSB RAW_IO for 512-byte-aligned transfers, which is this device's
  endpoint size. So the working invocation is:

  ```bash
  ./build_image.sh --image mingw --skip-patch mxe_fixes.patch
  ```

  `build_image.sh` checks each patch before building and refuses to start if
  one will not apply, so this cannot silently regress. See `STATUS.md`.
- The upstream README freezes Qt at 5.7 for Windows XP. This project does not
  claim XP, so the freeze is off by default. `--qt5-freeze` restores it.
- `sigrok-util`'s own MSYS2 script is broken and is not used here; see
  planning doc 06.

Nothing in this directory has been executed yet. See `STATUS.md` for what is
implemented versus verified.

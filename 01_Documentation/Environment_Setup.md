<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Environment setup

How to get from a fresh clone to a build. If you only read one section, read
[Two host roles](#two-host-roles) - getting that backwards is the most common
way to lose an afternoon here.

This page is the operator's route. `02_Tools/build/STATUS.md` is the ledger
behind it: what has actually been verified, on which host, and every finding
that shaped a choice. Where this page says "see STATUS.md", the detail there is
worth reading before you work around a problem.

## Two host roles

Work in this repository happens in two different places, and they are not
interchangeable.

| Role | Where | Used for |
|---|---|---|
| **Build host** | WSL Ubuntu 24.04, or a native Linux machine | Everything that touches Docker: the toolchain image, all three build scripts. |
| **Test host** | Windows directly, via Git Bash | Running the built `sigrok-cli.exe` and `pulseview.exe`, and the host-side smoke tests. |

The build scripts refuse to be useful from Git Bash - the container engine is
not there. The smoke tests cannot run inside the MXE build image - it has no
Wine, so it cannot execute the `.exe` it just produced. On Linux the two roles
collapse into one machine, with `wine64` standing in for the Windows side.

From WSL the repository is visible at `/mnt/f/2026_PulseView`.

## Prerequisites

| Need | Build host | Test host | Notes |
|---|---|---|---|
| `git` | yes | yes | |
| `git-lfs` | when the checkout is on the Linux filesystem | yes on Windows | Whoever owns the checkout needs it. With the repo on a Windows drive, Windows git owns it and the WSL side only reads. |
| Docker, daemon reachable | yes | no | Docker Desktop with WSL integration enabled for the distro is fine. |
| ≥ 30 GB free | yes | no | The image is ~7.3 GB unpacked; a build tree adds several more. |
| ≥ 4 CPU cores | yes | no | Fewer works; the toolchain build gets slow. |
| Git Bash | no | yes (Windows) | The smoke tests need a real POSIX toolset - `mktemp`, `comm`, `awk`. `cmd.exe` cannot run them. |
| `python3` | no | yes | Only to generate synthetic captures for the decode smoke test. Standard library only; nothing to `pip install`. |
| `wine64` | no | yes (Linux, optional) | Lets a Linux machine run the Windows smoke tests. Without it they exit 77. |

Nothing needs administrator or root privileges.

### SSH identity inside WSL

WSL has its own home directory, so keys set up under Windows are invisible to
it. This only matters if you clone or push from the WSL side, or rebuild the
toolchain image from source (which clones MXE):

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

Add the public half to the Git host. Copying the private key across from the
Windows home directory is not recommended and no script here offers it.

## First run

### 1. Clone, with LFS

```bash
git clone <origin-url> 2026_PulseView
cd 2026_PulseView
git lfs pull
```

`git lfs pull` is not optional. The saved toolchain image is a 2.2 GB LFS
object; without LFS you get a ~130-byte pointer file in its place. The failure
does not appear at clone time - it appears later, as an archive that will not
load. `load_image.sh` detects the pointer and says so explicitly, which is the
only reason it is a five-second diagnosis rather than an hour.

There is no `git submodule update` step. The sigrok stack was folded into this
repository as plain files in August 2026, so the clone carries every source it
builds.

### 2. Check the host

On Windows, from a PowerShell prompt:

```powershell
.\02_Tools\bootstrap\check_host.ps1
```

On Linux, or in WSL:

```bash
02_Tools/bootstrap/check_host.sh
```

Both are read-only by default: they report what is missing and the exact
command to fix it, and change nothing. Exit status is 1 if any check FAILED;
a WARN does not fail.

`check_host.ps1` additionally accepts `-Install`, which offers per-item `winget`
remediation with a y/N prompt for each. It never elevates silently and never
touches Docker Desktop or WSL distro installation - for those it prints the
command and leaves it to you. Use `-WhatIf` to see what it would propose:

```powershell
.\02_Tools\bootstrap\check_host.ps1 -Install -WhatIf
```

Useful flags on both: `-Tag` / `--tag` names the builder image to look for
(default `hantek-builder-mingw:latest`), and `-ResultPath` / `--result` writes a
JSON record of the run.

### 3. Load the toolchain image

Run this in WSL:

```bash
02_Tools/build/load_image.sh --image mingw
```

About a minute, no network. It verifies the `.sha256` beside the archive and
`docker load`s it. This is the normal route and the one to use.

Building the image from source instead takes hours and needs 117 distinct
upstream hosts reachable. Only do it when the toolchain itself changes:

```bash
02_Tools/build/build_image.sh --image mingw --skip-patch mxe_fixes.patch
```

`--skip-patch mxe_fixes.patch` is required, not optional - see
[Known sharp edges](#known-sharp-edges). To also write a fresh offline archive,
add `--save 07_Delivery/toolchain/hantek-builder-mingw.tar`. Regenerate that
archive only on a real toolchain change: Git LFS does not deduplicate between
revisions, so each one costs another ~2.2 GB permanently.

## Building

All three scripts re-exec themselves into the right container, so you invoke
them from WSL and they handle the rest. They take explicit paths and do not
care about your working directory.

### Windows x86_64

```bash
02_Tools/build/build_windows_mxe.sh --stage
```

Cross-builds `libserialport`, `libsigrok`, `libsigrokdecode`, `sigrok-cli` and
`pulseview` for `x86_64-w64-mingw32.static.posix`, embeds CPython 3.13.15 from
`/opt/sigrok-deps` inside the image, and stages the result to
`07_Delivery/staging/pulseview-windows-x86_64/` with a `build-record.txt` and
`SHA256SUMS`.

| Flag | Effect |
|---|---|
| *(component names)* | Build only those components. |
| `--clean` | Discard the out-of-tree build trees first. |
| `--stage` | Stage the result under `07_Delivery/staging/`. |
| `--offline` | Run the container with `--network none`. |

At staging it runs two self-checks: an `abi-check` probe asserting `MS_WIN64`,
64-bit `Py_ssize_t` and `PY_VERSION_HEX >= 0x030900F0`, and an `imports` walk of
the PE import table. The second is what keeps the "only non-system import is
`python313.dll`" claim honest.

The offline claim was tested rather than assumed:
`./build_windows_mxe.sh --offline --clean --stage` completes with no network
interface at all.

### Linux x86_64, thin tarball

```bash
02_Tools/build/build_linux.sh
```

Native build inside a plain `ubuntu:24.04` container. Output goes to
`07_Delivery/staging/pulseview-linux-x86_64/` plus a `.tar.gz`. It bundles only
the sigrok libraries - Qt5, boost, glib and the rest are an `apt install` on the
target, listed in the README it emits. Use the AppImage where that is not
acceptable.

### Linux AppImage

```bash
02_Tools/build/build_image.sh --image appimage    # first time only
02_Tools/build/build_appimage.sh
```

Produces `07_Delivery/PulseView-x86_64.AppImage`, self-contained and verified on
a bare `ubuntu:22.04` with zero packages installed. One `AppRun` dispatches both
binaries; `--cli` selects `sigrok-cli`.

The base is Ubuntu 22.04 deliberately: an AppImage runs on any glibc newer than
the one it was built against and none older, so the base image *is* the Linux
compatibility floor. That is why there are two builder images rather than one -
MXE wants a current Debian, the AppImage wants the oldest base still worth
supporting, and merging them would silently raise the floor.

## Installing the Linux udev rules

Without these, both instruments need root:

```bash
sudo cp 07_Delivery/60-sigrok-instruments.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Known sharp edges

Each of these cost real time to diagnose. The full findings are in
`02_Tools/build/STATUS.md`; this is the short form.

**A Git LFS pointer instead of the toolchain archive.** ~130 bytes where 2.2 GB
should be. `load_image.sh` detects it and names it. Fix: `git lfs pull`.

**`mxe_fixes.patch` fails every hunk.** It is dead against the pinned MXE - the
file it deletes was already removed upstream by MXE's binutils 2.46.0 update.
`build_image.sh` pre-checks every patch and refuses to start rather than
half-applying one, so this cannot silently regress. Pass
`--skip-patch mxe_fixes.patch`. Do *not* skip `libusb1_upgrade.patch`: it
enables WinUSB RAW_IO for 512-byte-aligned transfers, which is exactly these
devices' endpoint size.

**A root-owned `/build` volume.** The build cannot write to it. Fixed in the
image, which pre-creates the directory - if you see it, you are on an old image.

**Doxygen silently disables PulseView.** A missing host doxygen makes the
configure step drop PulseView without an error. The image bakes it in.

**glib 2.89.2 does not build glibmm 2.66.2.** glib is held at 2.89.1 by
`mxe-glib-hold.sh`, which swaps in the older `glib.mk` and its patches. Three
bisections were spent finding this. Do not "update" it casually.

**`wsl -d Ubuntu-24.04 -- /mnt/f/...` from Git Bash mangles the path.** MSYS
rewrites the leading `/mnt/...` into a Windows path before `wsl.exe` ever sees
it, and the error names a path that looks nothing like what you typed. Run it
from PowerShell or `cmd`, from inside a WSL shell, or prefix the command with
`MSYS_NO_PATHCONV=1`.

**Building from `/mnt/f` is slow.** The Windows drive reaches WSL over 9p.
`run_in_builder.sh` puts build trees in a container volume for exactly this
reason; do not move them back to the mount for convenience.

**MXE leaves stale logs.** A failure message may belong to a previous run.
`mxe-build.sh` parses `Failed to build package <name>` and dumps that package's
current log, which is the one to trust.

## What is not solved

Stated plainly so nobody discovers it the hard way:

- **The build is repeatable, not bit-reproducible.** Two builds from the same
  inputs produce working binaries, not identical ones. Nothing sets
  `SOURCE_DATE_EPOCH` or normalizes build paths.
- **apt package versions are not pinned.** A from-source image rebuild in a year
  gets whatever Bookworm serves then. The image archive is what makes this
  tolerable - the rebuild is rare.
- **libsigrok's unit tests cannot be cross-built for Windows.** `check` is
  excluded from the MXE package set because libcheck and winpthreads clash over
  `clock_gettime`.
- **Two artifacts still come from GitHub**, `appimagetool` and `linuxdeployqt`,
  when the *appimage builder image* is built. Both are pinned by SHA-256 so they
  cannot change underneath us, but they could disappear. Nothing in the Windows
  path depends on a third-party host any more.

## Next

- [Testing.md](Testing.md) - running and writing the test suite.
- [`02_Tools/build/STATUS.md`](../02_Tools/build/STATUS.md) - the verification
  ledger and the full findings.
- [`00_Planning/Overview.md`](../00_Planning/Overview.md) - what the project is
  and what is in it.

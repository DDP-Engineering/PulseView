<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
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
| **Build host** | WSL2 Ubuntu 24.04, or a native Linux machine | Everything that touches the container engine: builder images, the four target build scripts, and the release coordinator. |
| **Test host** | Windows directly, via Git Bash | Running the built `sigrok-cli.exe` and `pulseview.exe`, and the host-side smoke tests. |

The build scripts refuse to be useful from Git Bash - the container engine is
not there. Normal smoke tests can run directly on the Windows test host. Builder candidate
qualification also provisions Wine in the canonical MXE image and runs the
Windows binary checks there against isolated staged output.

From WSL the repository is visible under `/mnt/`, at the drive letter it
sits on: a checkout at `F:\2026_PulseView` appears as
`/mnt/f/2026_PulseView`. Examples on this page use that path because it is
the one this project is developed on; substitute your own. Inside WSL,
`wslpath -a -u "$(pwd)"` prints it, and every script derives its own
repository root, so none of them care where the checkout lives.

## Prerequisites

| Need | Build host | Test host | Notes |
|---|---|---|---|
| `git` | yes | yes | |
| `git-lfs` | when the checkout is on the Linux filesystem | yes on Windows | Whoever owns the checkout needs it. With the repo on a Windows drive, Windows git owns it and the WSL side only reads. |
| Container engine, daemon reachable | yes | no | Docker Engine installed **inside** the WSL distribution is the preferred route - see [Docker Engine inside WSL2](#docker-engine-inside-wsl2). Docker Desktop with WSL integration is an accepted alternative. Podman is accepted by the scripts but is not a verified configuration. |
| ≥ 30 GB free | yes | no | The image is ~7.3 GB unpacked; a build tree adds several more. |
| ≥ 4 CPU cores | yes | no | Fewer works; the toolchain build gets slow. |
| Git Bash | no | yes (Windows) | The smoke tests need a real POSIX toolset - `mktemp`, `comm`, `awk`. `cmd.exe` cannot run them. |
| `python3` >= 3.11 | yes | yes | The build host reads the upstream lock and the archive manifests with `tomllib`, which is standard library only from 3.11; Ubuntu 24.04 ships 3.12. On the test host it generates synthetic captures for the decode smoke test. Standard library only; nothing to `pip install`. |
| `wine64` | no | yes (Linux, optional) | Lets a Linux machine run the Windows smoke tests. Without it they exit 77. |

Once WSL and the container engine are installed, nothing in the ordinary
build cycle needs administrator or root privileges: no build script
elevates, and none installs anything on the host. Getting to that point
does. Installing WSL, installing the engine inside the distribution, and
adding yourself to the `docker` group are one-time administrative steps,
and registering arm64 emulation needs a privileged container once per boot
(`check_host.sh` prints that command when it is missing).

### Docker Engine inside WSL2

This is the preferred Windows route: the engine runs in the same Linux
distribution the builds run in, so there is no second product to keep in
step and no WSL-integration setting to get wrong. Run these once, inside
`wsl -d Ubuntu-24.04`:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo usermod -aG docker "$USER"
```

If this WSL2 distribution does not run systemd, start the daemon per session.
Otherwise enable the Docker service and let systemd start it:

```bash
sudo service docker start
```

Log out of the distribution and back in (`wsl --terminate Ubuntu-24.04`
from Windows) so the `docker` group membership takes effect, then confirm:

```bash
docker run --rm hello-world
```

`check_host.sh` reports the same thing as part of a full check. If you use
Docker Desktop instead, skip all of the above and enable WSL integration
for the distribution in its settings; everything downstream is identical,
because the scripts only ever talk to a `docker` on `PATH`.

### SSH identity inside WSL

WSL has its own home directory, so keys set up under Windows are invisible to
it. This matters only if you clone or push the main Gitea repository from the
WSL side. The optional MXE image rebuild uses its canonical HTTPS URL and does
not need a Gitea identity:

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

`git lfs pull` is not optional. The saved builder images are carried as 1 GiB
LFS parts; without LFS you get small pointer files in their place. The failure
does not appear at clone time - it appears later, when the archive cannot be
reconstructed. `ensure_build_environment.sh` detects and names the affected
part directly.

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
bash 02_Tools/bootstrap/check_host.sh
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
(default `pulseview-builder-mingw:latest`), and `-ResultPath` / `--result` writes a
JSON record of the run.

### 3. Ensure the build environment

Run this in WSL:

```bash
bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw
```

The command checks the installed image first. A current image is selected only
when its type, architecture, recipe identity, dependency-contract identity,
quick offline probes, and current validation evidence all match. This path does
not read a manifest or archive part.

If no current image is usable, the command verifies schema-2 metadata, every
part, the reconstructed archive, and exact image identity before load. It then
runs standard contract checks and records validation evidence under `.work/`.

Prepare the two AppImage builders the same way when those packages are needed:

```bash
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform x86_64
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform aarch64
```

The checked-in archives currently use legacy schema 1. They remain available
through the temporary explicit migration option
`--allow-legacy-restore`; they are not accepted as current verified builders.
A stale schema-2 archive also needs an explicit
`--allow-historical-builder --force-restore`. Historical mode verifies its
embedded contract and inventory and prints a prominent warning that it is not
the current recipe.

If local parts are missing, still contain Git LFS pointers, or fail a checksum,
the command tells the developer to run `git lfs pull` and offers an online
local rebuild from the pinned inputs. It never downloads LFS files and never
publishes an image.

Building the image from source instead takes hours and needs many upstream
hosts reachable. Only update it when the toolchain itself changes. Use the
transactional owner command, not a manual sequence:

```bash
bash 02_Tools/build/update_builder_environment.sh --image mingw --plan
bash 02_Tools/build/update_builder_environment.sh --image mingw --replace
```

Replacement is explicit and Docker-only. Plan mode is read-only and reports
selected inputs, identities, candidate resources, promotion paths, and the
superseded generation before the expensive operation starts.

The automatic MinGW profile excludes the obsolete `mxe_fixes.patch`; no
remembered command-line exception is required. The updater builds under an
isolated candidate tag and volume, builds representative output under `.work/`,
runs the complete mandatory matrix, creates inventory and SPDX records, audits
an exact archive round trip, and replaces the stable manifest last.

Run the same plan-then-replace sequence with
`--image appimage --platform amd64` or `arm64` for the AppImage builders. Exit 77 is a hard failure during candidate promotion,
not a passing skip. Regenerate only for a real toolchain change because Git LFS
does not deduplicate different content generations.

## Building

The target build scripts re-exec themselves into the right container, so you
invoke them from WSL and they handle the rest. They take explicit paths and do
not care about your working directory.

### Windows x86_64

```bash
bash 02_Tools/build/build_windows_mxe.sh --stage
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
`bash 02_Tools/build/build_windows_mxe.sh --offline --clean --stage` completes
with no network interface at all.

### Linux x86_64, thin tarball

```bash
bash 02_Tools/build/build_linux.sh
```

Native build inside the digest-pinned Ubuntu 24.04 container recorded in
`upstreams.lock.toml`. Output goes to
`07_Delivery/staging/pulseview-linux-x86_64/` plus a `.tar.gz`. It bundles only
the sigrok libraries - Qt5, boost, glib and the rest are an `apt install` on the
target, listed in the README it emits. Use the AppImage where that is not
acceptable.

### Linux AppImage

```bash
bash 02_Tools/bootstrap/ensure_build_environment.sh \
  --image appimage --platform amd64
bash 02_Tools/build/build_appimage.sh
```

Produces `07_Delivery/PulseView-x86_64.AppImage`, self-contained and verified on
a bare `ubuntu:22.04` with zero packages installed. One `AppRun` dispatches both
binaries; `--cli` selects `sigrok-cli`.

The base is Ubuntu 22.04 deliberately: an AppImage runs on any glibc newer than
the one it was built against and none older, so the base image *is* the Linux
compatibility floor. That is why there are two builder images rather than one -
MXE wants a current Debian, the AppImage wants the oldest base still worth
supporting, and merging them would silently raise the floor.

### Raspberry Pi 4/5 (aarch64)

The same two Linux builds take `--arch aarch64` and run in an arm64 container.
On the x86_64 build host that container is emulated; enable the qemu binfmt
handlers once per boot (`check_host.sh` reports whether they are present):

```bash
docker run --privileged --rm tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0 --install arm64
bash 02_Tools/bootstrap/ensure_build_environment.sh \
  --image appimage --platform arm64
bash 02_Tools/build/build_appimage.sh --arch aarch64
bash 02_Tools/build/build_deb.sh                                         # recommended installer
bash 02_Tools/build/build_linux.sh --arch aarch64                        # optional
```

Produces `07_Delivery/PulseView-aarch64.AppImage` for a Pi 4 or 5 running a
64-bit OS: Raspberry Pi OS Trixie (the current release) or Bookworm (the
legacy floor), or Ubuntu 22.04 or newer. The glibc floor is the same
ubuntu:22.04 base as x86_64 (2.35), which is what lets one binary cover
Bookworm (2.36) and everything after it. 32-bit Raspberry Pi OS cannot run
it. The thin aarch64 tarball, by contrast, builds against ubuntu:24.04 and
therefore does NOT run on Bookworm - it is for arm64 Ubuntu. The AppImage and
the Debian package are the two Raspberry Pi deliveries; the tarball README says
why it is not one of them.

Expect the emulated build to run several times longer than the native one.
Building directly on a Pi 4/5 (8 GB recommended) with Docker installed works
with the same commands minus the binfmt step; the scripts detect the native
architecture. Both architectures use the same packaging tools - linuxdeployqt
release 11 ships an aarch64 asset alongside the x86_64 one - and the type-2
AppImage runtime is pinned and baked into the builder too, because
appimagetool would otherwise download it from GitHub at packaging time.
One runtime note for the Pi itself: a normal `./PulseView-aarch64.AppImage`
launch needs the host's FUSE stack; where FUSE is unavailable, run with
`APPIMAGE_EXTRACT_AND_RUN=1` set. The udev rules and instrument
capabilities are identical to x86_64.

### Raspberry Pi Debian installer

`build_deb.sh` verifies and extracts `PulseView-aarch64.AppImage` inside the
arm64 builder, installs that tested payload under `/opt/pulseview-ddp`, and
creates `07_Delivery/pulseview-ddp_<version>_arm64.deb`. It does not compile a
second copy of PulseView and the installed application does not need FUSE.

On the Pi, copy the `.deb` there and run:

```bash
sudo apt install ./pulseview-ddp_0.5.0+gitREV_arm64.deb
pulseview                    # or choose PulseView from the application menu
sigrok-cli --version
```

The package installs both project drivers, all protocol decoders, the desktop
entry/icon, and the udev rules. It owns the standard `pulseview` and
`sigrok-cli` commands, so `apt` replaces/conflicts with Raspberry Pi OS's stock
packages of those names. Remove it cleanly with `sudo apt remove
pulseview-ddp`. Use the aarch64 AppImage instead when no installation or
package replacement is wanted.

### Complete delivery set

Every release consists of exactly five packages: Windows x86_64 ZIP, Linux
x86_64 AppImage, Linux x86_64 thin tarball, Raspberry Pi aarch64 AppImage, and
Raspberry Pi arm64 Debian package. From Windows PowerShell, the owner command
is:

```powershell
.\02_Tools\build\build_delivery_set.ps1 -Plan
.\02_Tools\build\build_delivery_set.ps1
```

The builder images and per-boot arm64 binfmt handler must already be ready.
The script uses WSL for all container builds and native Git Bash for the
Windows runtime gate. Its final `verify_delivery_set.sh` step refuses mixed,
missing, or duplicate package rows and atomically writes `07_Delivery/
SHA256SUMS` only after all five hashes verify. Judge the cross-environment run
by the `DELIVERY_SET_COMPLETE` sentinel and the manifest, not an intermediate
bridge exit code.

## Installing the Linux udev rules

Without these, both instruments need root:

```bash
sudo cp 07_Delivery/60-sigrok-instruments.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Known sharp edges

Each of these cost real time to diagnose. The full findings are in
`02_Tools/build/STATUS.md`; this is the short form.

**Git LFS pointers instead of toolchain archive parts.** A few hundred bytes
where a large part should be. `ensure_build_environment.sh` detects the exact
part and names it. Fix: `git lfs pull`.

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

**Scripts are invoked as `bash <path>`, not `./<path>`.** Every shell
script here is tracked with Git mode `100644`, so a fresh clone on Linux
gets them non-executable and `./02_Tools/...` fails with `Permission
denied`. Running them through `bash` works from any checkout and is the
form used throughout this page and by `build_delivery_set.ps1`. If you
prefer executables, `chmod +x` them locally, or a maintainer can record
the mode with `git update-index --chmod=+x`.

**Building from a Windows drive is slow.** The drive reaches WSL over 9p.
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
- **apt package versions are not individually pinned.** The Debian and Ubuntu
  base images are digest-pinned, but `apt` still gets whatever those release
  repositories serve when a local rebuild runs. The archived image remains the
  exact-restoration path.
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

<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# 2026 PulseView

**PulseView and the sigrok stack, restructured as an agent-developed project.**

This is a fork of the whole sigrok stack - libsigrok, libsigrokdecode,
PulseView, sigrok-cli and their dependencies - carried as ordinary files in one
repository and developed almost entirely by AI agents working under an explicit,
file-based workflow. The interesting claim is not that agents wrote some code.
It is that a twenty-year-old C/C++ codebase, a USB wire protocol nobody
documented, and a multi-hour offline cross-build can all be driven this way and
leave a record a human can audit afterwards.

The engineering output is real and is the evidence: two hardware drivers written
from protocols recovered by this project and verified on a bench, a first-party
decoder set, and three reproducible offline builds. None of it is the point on
its own. The point is the method that produced it, and that the method is
legible in the repository rather than in a chat log that has since scrolled
away.

## How the project is developed

Work follows **AEGIS**, an advisory workflow whose full contract is
[`.agentic/AGENTS.md`](.agentic/AGENTS.md). Its design principle is that nothing
blocks mid-flight: git is the state store and the undo, `aegis.py check` is a
report you read and self-correct against, and every artifact is a plain file
committed on the branch.

| Artifact | Where | What it is |
|---|---|---|
| Requirements | `.agentic/requirements/<category>/` | One behaviour per file, in EARS form, with its verification method and linked tests. |
| Task journals | `.agentic/tasks/` | One per task: stage, branch, scope, and a dated log of every decision and what it cost. |
| Specs, knowledge | `.agentic/specs/`, `.agentic/knowledge/` | Written when they earn their place, not by default. |

Six stages - `frame`, `specify`, `design`, `build`, `validate`, `deliver` - with
a quick path for small changes. `build` means a failing test first. `validate`
means the full suite and a strict check. A **deviation** - an accepted warning, a
skipped verification, a manual method standing in for an automatable test - is
written down as one line in the journal rather than quietly absorbed.

Three consequences shape everything else in this repository:

- **Documentation is written to be read cold**, by a human or an agent with no
  session history. That is why `02_Tools/build/STATUS.md` records what was tried
  and failed, not just what works.
- **Claims carry their evidence.** "137 decoders" is a number a test asserts. The
  offline build was proved with the network interface removed, not assumed. A
  decoder that loads but decodes nothing is written down as a failure.
- **Being honest about the gaps is part of the output.** What is *not* solved
  gets its own sections, here and in the build status.

To see what is in flight and resume it:

```bash
python .agentic/aegis.py status
```

Then read [`AGENTS.md`](AGENTS.md), which carries the rules AEGIS does not: the
repository layout contract, the code style and licence header every new
first-party file needs, and the changelog convention.

## Why a fork, and not a plugin

libsigrok has no runtime plugin ABI. Drivers are collected at link time, so
supporting a new instrument means recompiling libsigrok - and on Windows
PulseView is statically linked against it, so it means recompiling PulseView
too. A plugin was never available. A fork was the only shape this could take,
which is also what makes it a fair test of the method: there is no small
sanctioned extension point to hide inside.

The stack lives in `05_Software/` as **plain files, not submodules**. A clone
carries every source it builds. Provenance, upstream commits and licences are in
[`02_Tools/upstream/upstreams.lock.toml`](02_Tools/upstream/upstreams.lock.toml).

## What has been built

Everything below builds today and has been run against real hardware. The
details, including what is not solved, are in
[`02_Tools/build/STATUS.md`](02_Tools/build/STATUS.md).

| | |
|---|---|
| Drivers | 84 - 82 upstream, plus `hantek-dso3062l` and `atk-dl16` |
| Decoders | 137, including a first-party 100BASE-FX networking stack |
| Python | CPython 3.13.15, embedded in the Windows build |
| Deliverables | Windows x86_64 zip, Linux x86_64 tarball, Linux AppImage |

The two drivers are for the **Hantek DSO-3062L** mixed-signal oscilloscope and
the **ALIENTEK ATK-DL16** logic analyzer, both written here from protocols
recovered by this project - the Hantek's from its vendor SDK using the
`protocol_probe` harness, the ATK's from vendor GPL sources - and both confirmed
against the instrument. Both build into a single PulseView, which is why the
packages are named `pulseview-*` rather than after either device.

The Windows build is statically linked; its only non-system DLL import is
`python313.dll`, which ships beside it.

For the full current-state description, see
[`00_Planning/Overview.md`](00_Planning/Overview.md).

## Get the binaries

Ready-made packages are in [`07_Delivery/`](07_Delivery/):

| File | For |
|---|---|
| `pulseview-*-windows-x64.zip` | Windows 10/11 x86_64. Unzip and run `pulseview.exe`. |
| `PulseView-x86_64.AppImage` | Any Linux with glibc 2.35 or newer. `chmod +x` and run. Pass `--cli` to get `sigrok-cli` instead. See `README-AppImage.txt`. |
| `pulseview-*-linux-x64.tar.gz` | Linux, thin - needs Qt5, glib and boost from the distro. |
| `60-sigrok-instruments.rules` | Linux udev rules. Install to `/etc/udev/rules.d/` so both instruments are usable without root. |

> **Clone with Git LFS.** The toolchain archive and the delivery packages are
> LFS objects. A clone without LFS gets ~130-byte pointer files instead, and the
> failure surfaces much later as a corrupt archive. Run `git lfs pull` after
> cloning.

## Build it yourself

The Windows build is a cross-build: a Docker image containing an MXE
cross-toolchain, driven from WSL. The image is shipped as a `docker save`
tarball so no build needs to reach the network.

```bash
02_Tools/build/load_image.sh --image mingw
02_Tools/build/build_windows_mxe.sh --stage
```

The Linux builds also target the **Raspberry Pi 4/5** (aarch64): pass
`--arch aarch64` to `build_appimage.sh` or `build_linux.sh`, after building
the arm64 builder image with `build_image.sh --image appimage --platform
aarch64`. On an x86_64 host the arm64 container runs emulated - a one-time
qemu binfmt install that `check_host.sh` explains. Details, including the
glibc floor that makes the AppImage the right delivery for Raspberry Pi OS:
[01_Documentation/Environment_Setup.md](01_Documentation/Environment_Setup.md).

Full prerequisites, both host roles, every build script and the known sharp
edges: **[01_Documentation/Environment_Setup.md](01_Documentation/Environment_Setup.md)**.

Check your machine before you start:

```bash
02_Tools/bootstrap/check_host.ps1     # Windows, from PowerShell
02_Tools/bootstrap/check_host.sh      # Linux or WSL
```

## Test it

```bash
bash 02_Tools/test/run_tests.sh
```

on Linux or in Git Bash, or from PowerShell:

```powershell
.\02_Tools\test\run_tests.ps1
```

Exit code **77 means skipped, not passed** - the tests drive built artifacts and
say so honestly when they cannot. What each test asserts, and how to add one:
**[01_Documentation/Testing.md](01_Documentation/Testing.md)**.

## Repository layout

The numbered directories are a fixed contract, described in
[`AGENTS.md`](AGENTS.md). Do not create a parallel tree somewhere more
convenient.

| Directory | Holds |
|---|---|
| [`00_Planning/`](00_Planning/) | Scope and current-state description. Start with [Overview.md](00_Planning/Overview.md). |
| [`01_Documentation/`](01_Documentation/) | Code style, environment setup, testing. |
| [`02_Tools/`](02_Tools/) | Every project-owned script: bootstrap, container definitions, build drivers, tests, upstream locks. |
| [`03_Hardware/`](03_Hardware/) | Hardware design files. Empty today. |
| [`04_HardwareDocu/`](04_HardwareDocu/) | Per-device: the recovered wire protocols, and the vendor SDK and manuals they came from. Authoritative for device behaviour. |
| [`05_Software/`](05_Software/) | The vendored sigrok stack plus `protocol_probe/`, the reverse-engineering harness. |
| [`06_SoftwareDocu/`](06_SoftwareDocu/) | Software documentation. |
| [`07_Delivery/`](07_Delivery/) | Finished, verified packages and the saved toolchain image. Nothing unverified. |
| [`09_Others/`](09_Others/) | Anything belonging to no primary area. Empty today. |
| `.agentic/` | The AEGIS payload: workflow contract, step files, requirements, task journals. |
| `.work/` | Scratch: build contexts, build trees, logs. Git-ignored, safe to delete at any time. |

## Licensing

Project-authored code and documentation are under the **PolyForm Noncommercial
License 1.0.0** ([`LICENSE.txt`](LICENSE.txt)); commercial use requires a
separate licence. The vendored sigrok components under `05_Software/` keep their
own licences - GPL - and nothing here relicenses them. The distributed binaries
are therefore GPL builds; `upstreams.lock.toml` is the provenance record.

<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Bootstrap automation contract

Implemented host inspection and local builder restoration live here. The
remaining tools in the table are still plans and must not be reported as
available commands.

`clone_upstreams.py` was withdrawn from the plan on 2026-09-06. It existed to
materialize submodules at locked commits, and the sigrok stack stopped being
submodules in August 2026 - `05_Software/` is plain files that a normal clone
already carries, and `check_host.sh` verifies the vendored trees are present
rather than checking submodule drift. Nothing is left for it to do. Where the
prose below still describes submodule materialization it describes a design
that no longer applies to this repository.

## Tools

| Tool | Purpose | Mutating behavior |
|---|---|---|
| `check_host.sh` | **Implemented 2026-08-17.** Inspect Linux/build-host prerequisites and versions | None |
| `check_host.ps1` | **Implemented 2026-08-24.** Inspect Windows prerequisites and versions | None by default; `-Install` offers winget remediation per item |
| `ensure_build_environment.sh` | **Updated 2026-09-07.** Select current, restore exact, verify historical, or rebuild one builder image | Installed selection needs no archive; restore loads audited local bytes; accepted recovery rebuilds online |
| `ensure_build_environment.ps1` | **Updated 2026-09-07.** Windows/WSL entry point for the same workflow | Same as the shell implementation |
| `verify_upstreams.py` | **Planned.** Verify URLs, commits, roles, and dirty states | None |
| `create_build_workspace.py` | **Planned.** Create bounded ignored build directories | Explicit target only |

Each implemented script gets the project legal header, follows
`01_Documentation/Code_Style.md`, has focused tests, and is recorded in
`02_Tools/build/STATUS.md`.

### ensure_build_environment

This is the normal builder-selection command. It first validates the installed
image's current recipe and dependency contract, runs quick offline probes, and
requires validation evidence for the current policy. This path does not read a
manifest or archive part.

If no installed image is usable, it strictly audits the local manifest,
metadata, SBOM, every archive part, the reconstructed archive, and the exact
image ID before load. Standard offline probes then create current validation
evidence under `.work/`.

```sh
bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform x86_64
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform aarch64
```

On Windows, PowerShell maps the checkout into WSL and invokes the same code:

```powershell
.\02_Tools\bootstrap\ensure_build_environment.ps1 -Image mingw
```

The command never runs `git lfs pull` and never publishes anything. Missing,
pointer-only, truncated, or corrupt parts cause an actionable error. Existing
schema-1 archives require temporary explicit `--allow-legacy-restore` migration
mode. A stale schema-2 generation requires
`--allow-historical-builder --force-restore`; this checks its embedded contract
and inventory and reports that it is not current.

In an interactive terminal, failed local recovery offers `build_image.sh` with
online pinned inputs. Use `--rebuild`/`-Rebuild` to accept that path or
`--no-rebuild`/`-NoRebuild` to forbid it. Live package resolution means this is
recovery, not an exact reconstruction. A rebuilt image stays local.

### check_host.sh

Reports whether a Linux build host can build the project, and exits non-zero
if anything failed. It changes nothing, needs no privileges, and prints the
exact operator command for each missing prerequisite rather than running it.

```sh
bash 02_Tools/bootstrap/check_host.sh [--result PATH] [--tag IMAGE]
```

It covers: WSL detection and repository location, git, docker and the
reachability of its daemon, Git LFS, presence of the builder image, the lock
file, submodule initialization and drift, an SSH identity, reachability of the
LAN mirror, free disk against the ~30 GB the image and a build tree need, and
core count.

Two behaviours are deliberate and easy to mistake for bugs. A submodule that
has drifted from its locked commit is a **warning**, not a failure - driver
development happens inside `libsigrok`, so drift there is the normal working
state. And Git LFS missing on a Linux host is only a failure when the checkout
lives on the Linux filesystem: with the repository on a Windows drive, Windows
git owns the checkout and its LFS is the one that matters.

### check_host.ps1

The Windows counterpart, and deliberately a mirror of the above: same
PASS/WARN/FAIL vocabulary, same exit-status rule, same "print the command,
do not run it" default.

```powershell
.\02_Tools\bootstrap\check_host.ps1 [-ResultPath PATH] [-Tag IMAGE] [-Distro NAME] [-Install] [-WhatIf]
```

It covers both roles Windows plays here. As the **test host**: PowerShell
version and architecture, git, Git LFS, Git Bash, and `python3`. As the gateway
to the **build host**: `wsl.exe`, whether the expected distribution is
registered, and whether Docker and the builder image are reachable *from inside
that distribution* - not from Windows, because Docker Desktop can be running
happily while WSL integration is off for the distro, and it is the distro's view
the build scripts get. Then repository state, the toolchain archive, free disk
and core count.

Three behaviours are deliberate. **Git Bash is located by rejecting
`C:\Windows\System32\bash.exe`**, which is the WSL launcher that PATH resolves
first on any machine with WSL enabled; using it would run the host-side tests
inside the distro, where the Windows `.exe` cannot execute. **The toolchain
archive is checked by size, not presence** - Git LFS pointers are a few hundred
bytes where large parts should be, and left undetected they surface much later
as a corrupt archive. And the script **avoids constructs that PowerShell
ConstrainedLanguage mode blocks**, so it still runs on a managed host; a
readiness check that cannot run on a locked-down machine is not much of a
readiness check.

**`-Install` is a documented exception to the no-installer rule below.** It was
added at the project owner's request. It is opt-in, never the default, asks
before each package individually, never elevates silently, and refuses to touch
Docker Desktop or WSL distro installation - for those it prints the command and
stops. `-WhatIf` lists what it would offer and installs nothing. Everything the
script does without `-Install` remains read-only.

## Inputs

All inputs are named arguments or versioned files; no CI prompt is allowed:

```text
--lock 02_Tools/upstream/upstreams.lock.toml
--root <absolute repository root>
--workspace <absolute ignored workspace>
--libsigrok-fork <approved URL>
--pulseview-fork <approved URL>
--dry-run | --apply
--result <absolute JSON output>
```

Fork arguments may fill lock entries only through a separately reviewed lock
update. They may not silently override provenance for a release build.

## Preflight and fail-closed rules

Before mutation, automation must:

1. resolve every target and confirm it is inside the supplied repository or
   workspace root;
2. parse schema 1 and reject unknown required fields or duplicate names;
3. require full 40-character Git commits and HTTPS URLs from the lock;
4. require approved non-empty fork URLs for every modified-submodule role;
5. verify the expected repository identity and that the locked commit exists;
6. refuse an existing dirty, mismatched, nested, symlink-redirected, or
   non-repository target;
7. print the exact planned changes and result path;
8. perform no mutation in dry-run mode.

Any failed validation stops the operation before the first mutation. A partial
operation records completed actions and leaves existing repositories intact;
it never deletes or resets a target to recover automatically.

## Git and system authority

The tools must never infer authority to:

- initialize Git, create or change branches, stage, commit, push, merge, create
  a fork, or open a pull request;
- add or change a submodule without the explicit `--apply` invocation approved
  for that exact root, path, URL, and commit;
- install packages, USB capture software, udev rules, Windows drivers, or use
  administrator/root privileges;
- change WinUSB/vendor-driver binding or perform a device operation;
- publish an artifact or vendor material.

Host checks report missing prerequisites and exact operator commands but do not
run installers, with one exception, recorded here rather than left implicit:
`check_host.ps1 -Install` may install host tooling via `winget`, opt-in and one
prompt per package. It still may not install device drivers, USB capture
software, or udev rules, and it still may not elevate. The rule driver and hardware work follows is simply that
nothing writes persistent device state - no calibration, flash or EEPROM
opcodes - which the protocol references in `04_HardwareDocu/<device>/` record
per opcode.

## Idempotence and result record

Rerunning against an already-correct clean checkout succeeds without changing
it. Each run writes schema-versioned JSON containing tool version, host,
arguments with secrets removed, lock hash, source URL and requested/actual
commit, fork status, dirty state, planned/performed actions, timestamps, exit
code, and errors.

No log may contain credentials, raw USB payloads, private calibration contents,
or vendor binary contents.

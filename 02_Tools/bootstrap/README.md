<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Bootstrap automation contract

This is the P0 contract for P1 bootstrap tools. Only `check_host.sh` is
implemented; everything else in the table below is still a plan and must not
be reported as an available command.

## Tools

| Tool | Purpose | Mutating behavior |
|---|---|---|
| `check_host.sh` | **Implemented 2026-08-17.** Inspect Linux/build-host prerequisites and versions | None |
| `check_host.ps1` | Inspect Windows prerequisites and versions | None |
| `clone_upstreams.py` | Materialize approved submodules and build-only clones at locked commits | Explicit `--apply` only |
| `verify_upstreams.py` | Verify URLs, commits, roles, forks, and dirty states | None |
| `create_build_workspace.py` | Create bounded ignored build directories | Explicit target only |

Each implemented script gets the project legal header, follows
`01_Documentation/Code_Style.md`, has focused tests, and is recorded in the
folder's future `STATUS.md` ledger.

### check_host.sh

Reports whether a Linux build host can build the project, and exits non-zero
if anything failed. It changes nothing, needs no privileges, and prints the
exact operator command for each missing prerequisite rather than running it.

```sh
02_Tools/bootstrap/check_host.sh [--result PATH] [--tag IMAGE]
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
run installers. The rule driver and hardware work follows is simply that
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

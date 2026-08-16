<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Bootstrap automation contract

This is the P0 contract for P1 bootstrap tools. No executable bootstrap script
exists yet, and this document must not be reported as an implemented command.

## Planned tools

| Tool | Purpose | Mutating behavior |
|---|---|---|
| `check_host.ps1` | Inspect Windows prerequisites and versions | None |
| `check_host.sh` | Inspect Linux/build-host prerequisites and versions | None |
| `clone_upstreams.py` | Materialize approved submodules and build-only clones at locked commits | Explicit `--apply` only |
| `verify_upstreams.py` | Verify URLs, commits, roles, forks, and dirty states | None |
| `create_build_workspace.py` | Create bounded ignored build directories | Explicit target only |

Each implemented script gets the project legal header, follows
`01_Documentation/Code_Style.md`, has focused tests, and is recorded in the
folder's future `STATUS.md` ledger.

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
run installers. Driver and hardware work follows
`06_SoftwareDocu/Research_Security.md`.

## Idempotence and result record

Rerunning against an already-correct clean checkout succeeds without changing
it. Each run writes schema-versioned JSON containing tool version, host,
arguments with secrets removed, lock hash, source URL and requested/actual
commit, fork status, dirty state, planned/performed actions, timestamps, exit
code, and errors.

No log may contain credentials, raw USB payloads, private calibration contents,
or vendor binary contents.

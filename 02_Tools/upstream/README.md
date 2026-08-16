<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Upstream source locks

This folder owns the immutable input catalogue used by bootstrap, build, and
delivery automation. The lock is data, not authorization to clone, add a
submodule, change a remote, commit, push, or publish.

## Lock contract

`upstreams.lock.toml` uses schema 1. Each `[[source]]` entry records:

- stable component name and canonical HTTPS Git URL;
- full 40-character commit selected for reproducible work;
- role: modified submodule, build dependency, diagnostic frontend, build
  reference, transport dependency, or cross toolchain;
- repository-level licence observation and direct licence URL;
- review date and the observed remote HEAD at that time;
- fork URL/status and whether production-path cloning is currently enabled.

The selected commit is deliberate even when it equals the observed HEAD. A
branch, tag, release name, or remote HEAD alone is never an immutable lock.

For `libsigrok` and `pulseview`, `fork_status = "pending-owner-input"` and
`clone_enabled = false` remain mandatory until the owner supplies approved fork
URLs. Bootstrap automation must fail closed rather than cloning canonical
repositories into modified-submodule paths.

## Review and update

An update is a reviewed change, not an automatic refresh:

1. fetch remote metadata without changing a checkout;
2. compare the candidate commit with the locked commit;
3. inspect upstream changes, licence files, build requirements, and known
   security or compatibility effects;
4. run the applicable unmodified baseline build and tests;
5. update the commit, observation, review date, and evidence together;
6. record the change in the active AEGIS journal and changelog.

Per-file licence headers and dependency licences govern when they are more
specific than the repository-level observation stored here.

<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Project workflow

Use the repository-local AEGIS workflow for substantive work. Read `.agentic/AGENTS.md` before starting or resuming a task. AEGIS records and guides work; it is advisory and does not replace explicit user approval for Git or publication actions.

Planning-only work under `00_Planning/` does not use the AEGIS workflow. Do
not create or update AEGIS task journals, requirements, specifications,
knowledge pages, anchors, or evolution records for planning-only changes
unless the user explicitly requests AEGIS for that work. This exception does
not apply when the same task also changes implementation, tests, build tools,
packaging, or delivery artifacts.

## Code style, legal notices, and changelog

- Read and follow `01_Documentation/Code_Style.md` before creating or editing
  source code or tests.
- Use the copyright and license header exactly as it appears at the top of
  `01_Documentation/Code_Style.md` for every new first-party source, test, and
  project documentation file, unless a file format cannot support it.
- Maintain the root `CHANGELOG.md` for notable project changes. Add entries
  under `## [Unreleased]` by default, using the `Added`, `Changed`, `Fixed`,
  and `Removed` sections as applicable; follow its existing release format.

## Repository layout contract

These locations are fixed. Do not create a parallel tree somewhere more
convenient.

| Path | Holds |
|---|---|
| `02_Tools/` | Every project-owned script, without exception: container definitions, environment setup, build drivers, packaging, delivery, research harnesses, release tooling. |
| `05_Software/` | Software trees. Upstream projects are submodules pinned to the Gitea mirrors; project-owned software sits alongside them. |
| `07_Delivery/` | The final PulseView packages and their release records. Nothing unverified. |
| `.work/` | Scratch: build contexts, build trees, staging, logs. Git-ignored and safe to delete at any time. |

Consequences worth stating explicitly, because they are easy to get wrong:

- A build or packaging script belongs in `02_Tools/`, even when it only ever
  runs inside a container and even when it is three lines long.
- Intermediate output goes to `.work/`. Only finished, verified artifacts are
  written to `07_Delivery/`.
- Scripts take explicit paths and never assume a working directory. Anything
  that must locate the repository derives it from its own location.

`02_Tools/build/STATUS.md` holds the detailed layout inside each of these,
along with the output-root and manifest conventions, and records which build
scripts are verified.

<!-- AEGIS:BEGIN (managed by .agentic/aegis.py init) -->

## AEGIS workflow

This repository uses AEGIS for changes that add or change a durable product
rule: logic, data, security, performance, integrations, or a product-wide UI
rule such as a theme, layout system, accessibility or interaction
convention. For those, read `.agentic/AGENTS.md` first; it routes you to one
step file per stage.

Make other changes directly, with no journal or requirement: a bug fix that
restores intended behavior, a local UI adjustment (one element's position,
spacing, wording or style), a refactor with no behavior change, or a test,
docs or tooling fix. A fix that contradicts an active requirement, adds
behavior, or touches security or data handling uses AEGIS. The user's
explicit choice wins; otherwise start with one line,
`LANE: direct|aegis - <why>`.

- New AEGIS work: run `python .agentic/aegis.py status` (an open task may
  cover it), then follow `.agentic/steps/1_frame.md`.
- An existing task: run `python .agentic/aegis.py brief TASK-<id>` and read
  what its `Read next` line names.

Stages: frame -> specify -> design -> build -> validate -> done; specify and
design have skip rules for work that does not need them. The CLI writes the
journal state:
`advance` finishes a stage, `pause` stops for the user, `log` and `ruling`
record events and decisions. End every session with `advance` or `pause`.

AEGIS guides and never blocks; `python .agentic/aegis.py check` is advisory.
Commits, pushes, merges, tickets, releases and packaging follow the
repository's own procedures, not AEGIS.

Say a deviation when you record one, as one line -
`DEVIATION <stage>: <what> - <why accepted, or what it costs>` - then carry on.

<!-- AEGIS:END -->

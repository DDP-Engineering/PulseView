<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

The full contract is `.agentic/AGENTS.md` - read it before starting work.
This digest is enough to act on if you read nothing else.

Stages, one step file each in `.agentic/steps/`: **frame** (agree scope,
open the task journal) -> **specify** (write the requirement, and a spec
when useful) -> **design** (a short note for non-trivial work) -> **build**
(failing test first, then the implementation, until green) -> **validate**
(review, knowledge, full suite and strict check) -> **deliver** (approval,
report, commit/PR). A small fix or change may take the quick path,
frame -> build -> validate -> deliver.

To resume: `python .agentic/aegis.py status` lists the task journals; open
`.agentic/tasks/TASK-<id>.md`, read its `stage:` line and `## Log`, open
that stage's step file, and continue at the first unticked item of
`## Done checklist`.

Artifacts: requirements in `.agentic/requirements/<category>/`, specs in
`.agentic/specs/`, journals in `.agentic/tasks/`, component pages in
`.agentic/knowledge/`. `python .agentic/aegis.py check` is advisory - read
its findings and self-correct; nothing here blocks you mid-flight.

<!-- AEGIS:END -->

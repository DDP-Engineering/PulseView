<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Project workflow

Use the repository-local AEGIS workflow for substantive work. Read `.agentic/AGENTS.md` before starting or resuming a task. AEGIS records and guides work; it is advisory and does not replace explicit user approval for Git or publication actions.

## Code style, legal notices, and changelog

- Read and follow `01_Documentation/Code_Style.md` before creating or editing
  source code or tests.
- Use the copyright and license header exactly as it appears at the top of
  `01_Documentation/Code_Style.md` for every new first-party source, test, and
  project documentation file, unless a file format cannot support it.
- Maintain the root `CHANGELOG.md` for notable project changes. Add entries
  under `## [Unreleased]` by default, using the `Added`, `Changed`, `Fixed`,
  and `Removed` sections as applicable; follow its existing release format.

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

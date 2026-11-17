<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

<!-- AEGIS:TEMPLATE
Task journal: one per task at .agentic/tasks/TASK-<id>.md, kept as the task's
record after it closes. `python .agentic/aegis.py task "<title>"` creates it.
For an existing task, pass its bare TASK-<id> to the commands below and use its
path with file tools; never open a second journal for the same task.

Who writes what:
- The CLI writes the header stage, the Done checklist, Log lines, Rulings and
  State. `advance` moves to the next stage (or `--to` a named one),
  `pause` records a stop or a blocker, `log` adds one durable event, `ruling`
  adds one decision and `verdict` records explicit review results. `advance`,
  `pause` and `verdict` print the summary.
- You edit Frame, Requirement coverage and Design directly, tick Done checklist
  items as they are met, and edit the header lines type, interaction,
  requirements and parent in place: one `key: value` per line, no blank lines
  or comments inside the header block.

Header values:
  stage         frame | specify | design | build | validate | done
                (adoption: survey | components | close | done; deliver is a
                legacy stage that closes to done)
  type          feature | fix | change | adopt
  interaction   checkpoint | autopilot
  requirements  comma-separated requirement IDs; frame records the existing
                requirements that cover the work, specify adds the rest
  parent        optional top-level TASK-<id>; blank for an ordinary task
  branch, base, opened   written at creation; leave them unchanged

Log only durable events: decisions, verification results, discoveries,
blockers, approvals and deviations - not routine reads, edits or retries.

State fields, written by the CLI and read by `brief` and `summary`:
  status        working | waiting | blocked | ready | done
  reported      <stage> - in_progress | completed | paused | blocked | skipped
  next          one action or one question
  must_read     the journal, the stage's step file and any --read paths
  changed, evidence, issues    one line each, from --changed, --evidence, --issues
  spec_compliance, implementation_quality    approved | changes_required | disabled
  review_round  1 through 1 + max_fix_cycles; blank while review is disabled
-->

# TASK-0000 — <one-line title>

stage: frame
type: feature
interaction: checkpoint
requirements:
parent:
branch: <branch>
base:
opened: 2026-01-01

Edit Frame, Requirement coverage and Design directly. Write State, Log and
Rulings with `python .agentic/aegis.py` (advance, pause, log, ruling, verdict);
end each session with `advance` or `pause`.

## Done checklist (current stage)

- [ ] copy the "Done when" list from the current step file here

## Frame

Problem:
Desired outcome:
Actors:
Primary scenario:
Examples:
Counterexamples:
In scope:
Out of scope:
Constraints:
Success signals:
Evidence:
Assumptions:
Unknowns:
Decision-blocking questions:
Proposed behaviors:

## Requirement coverage

<!-- AEGIS:TEMPLATE
One row per atomic behavior: one trigger or state, one observable response.
Each atomic behavior maps to exactly one requirement. Specify fills the
first four columns; design fills the last.
| Frame outcome | Atomic behavior | Requirement | Verification | Design decision or no impact |
|---|---|---|---|---|
-->

## Design

<!-- AEGIS:TEMPLATE
Filled at design when the task is non-trivial; otherwise record why skipped.
-->

## Log

- 2026-01-01 frame: journal opened

## Rulings

<!-- AEGIS:TEMPLATE
`aegis.py ruling` appends one line per decision; earlier lines are never
edited. A changed decision is a new ruling with --supersedes RULING-<old-id>.
- RULING-001 | date=YYYY-MM-DD | decision=<decision> | reason=<reason> | source=user | supersedes=none
-->

## State

status:
reported:
next:
must_read:
changed:
evidence:
issues:
spec_compliance:
implementation_quality:
review_round:

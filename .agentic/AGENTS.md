<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# AEGIS — agent workflow

AEGIS guides you through implementing one feature, fix or change at a time,
stage by stage. It guides and never blocks: `check` is an advisory report,
Git is the store, and every artifact is a plain file on the task's branch.
Each task leaves the requirements and component knowledge accurate, so the
next task — in a later session or on another developer's branch — starts
from a current map.

## Scope

AEGIS governs changes that add or change a durable product rule: logic,
data, security, performance, integrations, or a product-wide UI rule such as
a theme, layout system, accessibility or interaction convention. A rule
applies to a class of things, and a later change could break it; a test
should catch that.

Make other changes directly, with no journal or requirement: a bug fix that
restores intended behavior, a local UI adjustment (one element's position,
spacing, wording or style), a refactor with no behavior change, or a test,
docs or tooling fix. Follow the repository's own practice, and add a
regression test for a logic bug. A fix that contradicts an active
requirement, adds behavior, or touches security or data handling is a
change: use AEGIS. The user's explicit choice wins; otherwise start with one
line, `LANE: direct|aegis - <why>`, and carry on.

Commits, pushes, pull requests, merges, tickets, releases and packaging are
outside it; follow the repository's own procedures and the user's
instructions for those.

## Stages

| Stage | Step file | Result |
|---|---|---|
| frame | `.agentic/steps/1_frame.md` | Agreed scope, in a new task journal |
| specify | `.agentic/steps/2_specify.md` | One requirement per behavior; a spec where needed |
| design | `.agentic/steps/3_design.md` | A short design note, or the reason to skip it |
| build | `.agentic/steps/4_build.md` | Failing tests first, then the implementation, until green |
| validate | `.agentic/steps/5_validate.md` | Reviewed candidate, current knowledge, final proof; the task closes |

Path: frame → specify → design → build → validate → done. Specify and design
each have a skip rule for work that does not need them; frame, build and
validate are never skipped.
Read a stage's step file when you enter that stage. Adopting an existing
repository is a one-time task described in `.agentic/steps/adopt.md`.

## Start or resume

- New work: run `python .agentic/aegis.py status` (an open task may already
  cover it), then follow `.agentic/steps/1_frame.md`.
- An existing task: run `python .agentic/aegis.py brief TASK-<id>` and read
  what its `Read next` line names. If `git branch --show-current` differs from
  the journal's `branch:`, stop and say so before changing anything.
- Read `.agentic/context/project.md` at frame and on resume, and the relevant
  sections of `.agentic/context/environment.md` before setup, build or
  verification. Load the requirements, knowledge pages
  (`python .agentic/aegis.py components` lists them), source and tests the
  stage needs, not the whole repository. Reuse files already read in this
  session unless they changed.

## The task journal

One journal per task, `.agentic/tasks/TASK-<id>.md`, created by `task`.
You edit Frame, Requirement coverage and Design, and tick Done checklist
items as they are met. The CLI writes the rest — the header stage, the Done
checklist, Log, Rulings and State:

| When | Command |
|---|---|
| A stage is finished | `advance TASK-<id>` (`--skipped` for a skipped stage) |
| Work must go back | `advance TASK-<id> --to <stage> --reason "<why>"` |
| You stop, or need the user | `pause TASK-<id> --next "<one action or question>"` (`--blocked` when a decision blocks) |
| A durable event happens | `log TASK-<id> "<decision, verification result, discovery or deviation>"` |
| A question is settled | `ruling TASK-<id> --decision "..." --reason "..." --source user` |
| Explicit review returns | `verdict TASK-<id> --spec <verdict> --quality <verdict>` |

End every session with one of them: `advance` when the stage is finished,
otherwise `pause` — also after a record-only update, a reconciliation or an
explicit stop. Never edit the `## State` block by hand; these commands rewrite
it. `advance` and `pause` take `--changed`, `--evidence` and `--issues`, one
line each, from what you observed. Evidence names the commands you actually ran and
their exit codes; reading code or test definitions is not a test run. Open
problems, failures and limitations go in `--issues`. Both
commands print a summary block: start your reply with that printed block in a
text fence, then explain; never write the block yourself. The Log holds
durable events only, not routine reads, edits or
retries. Rulings are append-only: a changed decision is a new ruling with
`--supersedes`, and that link is what marks the old one superseded, so never
edit or annotate an earlier line. A ruling records a decision someone with
authority made; it cannot grant authority or override newer user
instructions, repository rules or Git permissions.

## Evidence

In frame, specify and design, label each material claim:

| Label | Source |
|---|---|
| STATED | The user's own words, or an authoritative clause you cite |
| OBSERVED | A file, test or command result you inspected, with its path or command |
| INFERRED | A conclusion from stated or observed premises; name them |
| UNKNOWN | Not established by the available sources |

Never turn an inference or an unknown into product behavior. Ask when the
answer changes the outcome, scope, observable behavior, compatibility,
security, data handling or verification; otherwise keep it in Unknowns.

## Checkpoint or autopilot

The journal's `interaction:` header, copied from `[interaction] autopilot` in
`.agentic/aegis.toml` (default `false`), decides what happens when a stage is
finished:

- **checkpoint** (default): `pause` with the decision you need, show the
  summary and the choices — continue, revise, go back, or stop — and wait.
  When the user continues, `advance`.
- **autopilot**: `advance` and go on. A decision-blocking question still
  stops the work with `pause --blocked`.

Stopping before a stage is finished — for a question, a blocker or an
explicit instruction — is a `pause` too: record it first, then ask. An
explicit user instruction, such as stop after a stage or do not run
something, always wins. Record a mode the user changes in the journal header.

## Deviations

When the candidate, the agreed scope or design, or the strength of required
verification departs from plan, say it in one line and `log` it:

```text
DEVIATION <stage>: <what> — <why accepted, or what it costs>
```

Then carry on: it never waits for a reply, and autopilot never suppresses it.
Examples: skipped or weakened verification, an accepted relevant warning, a
manual check standing in for an automatable test, a retired requirement,
unrequested work kept. Corrected tool errors, expected red tests and
unrelated findings are not deviations.

## Feature by feature, branch by branch

- One task per feature, fix or change, each on its own branch. Branches,
  like commits, are the developer's: the journal records the current branch,
  and you create or switch one only when the user asks. IDs are random, so
  records from parallel branches do not collide.
- Edit only your own task's journal. Change requirements, specs and knowledge
  pages only within your task's scope, section by section, so parallel
  branches merge cleanly.
- Current-state records — `.agentic/context/`, `.agentic/knowledge/` and
  active requirements — describe what the code does now: one current,
  positive statement per fact, including its errors and limits, such as "The
  service returns 403 for callers without the role." Proposals, history and
  removed behavior stay in the journal.
- A conflict between code and an established requirement is a finding, not
  permission to rewrite the requirement: preserve the contract unless the
  user changes it.
- After another branch is integrated, re-check current-state claims against
  this checkout; another branch's plans are not facts here.
- Large work may split into child tasks, one level deep:
  `task "<title>" --parent TASK-<id>`. Each child is an ordinary task, and
  the parent validates the integrated result.

## Where things live

| Artifact | Location |
|---|---|
| Requirements | `.agentic/requirements/<category>/REQ-<CAT>-<hex>.toml`, one behavior each |
| Specs | `.agentic/specs/REQ-<CAT>-<hex>.md`, only where a requirement needs one |
| Task journals | `.agentic/tasks/TASK-<hex>.md`, kept after the task closes |
| Component knowledge | `.agentic/knowledge/<component>.md`; `components` lists them |
| Project and environment | `.agentic/context/project.md`, `.agentic/context/environment.md` |
| Templates | `.agentic/templates/` |
| Configuration | `.agentic/aegis.toml`: commands, layout, interaction, review, diagrams |

Source and tests stay where the repository keeps them. Frame, specify and
design write only under `.agentic/`; `check` reports a source or test edit
made in those stages as `stage-zone`. Do not edit the payload — `.agentic/AGENTS.md`, `CLI.md`,
`steps/`, `templates/`, `aegis.py` and `LICENSE.txt` are replaced on upgrade;
tell the user what needs to change instead.

## Commands

Run `python .agentic/aegis.py <command>`, or `python3` where `python` is not
Python 3. `<command> --help` shows one command's options and
`.agentic/CLI.md` is the full reference; you never need to read `aegis.py`.

```text
status                          open tasks, or one task's state
brief TASK-<id>                 resume view: state, decisions, what to read next
task "<title>" --type T         new journal: feature, fix, change or adopt
advance | pause | log | ruling | verdict TASK-<id>    journal writers
summary TASK-<id>               the recorded state, read-only
components                      component knowledge pages
explain <path>                  requirements and tasks that govern a path
req <category> "<title>"        new requirement file
check                           advisory report; always exits 0
test --impacted --base HEAD --no-fallback    focused tests during build
anchor | evolution --task TASK-<id>          fingerprints around build
check --task TASK-<id> --strict --run        the final proof in validate
report TASK-<id>                closing summary, appended to the journal
```

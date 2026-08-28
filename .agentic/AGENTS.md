<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# AEGIS — agent workflow

## Philosophy

This workflow is guidance, not enforcement. Nothing blocks you mid-flight:
the lifecycle lives in these instructions, git is the state store and the
undo, and `python .agentic/aegis.py check` is an advisory report you read
and self-correct against — it always exits 0 outside CI. Work is durable
because every artifact is a plain file committed on the branch: one
requirement per file, one journal per task, one page per component. You
can skip a step; the journal is what a reviewer reads to see that you
did. Do the steps honestly and keep the journal true.

## Scope

AEGIS applies only to software development operations: work that changes,
tests, or documents the software product. Do not use the workflow for
repository operations or package and delivery operations, including version
assignment, release-package construction, publication, and repository
maintenance. Those operations follow the repository's own procedures; the
software implementation they carry remains subject to AEGIS.

## Stages

| # | Stage | Step file | Purpose |
|---|---|---|---|
| 1 | frame | `.agentic/steps/1_frame.md` | Understand the ask, agree scope, open the task journal. |
| 2 | specify | `.agentic/steps/2_specify.md` | Write or update the requirement(s), and a spec when useful. |
| 3 | design | `.agentic/steps/3_design.md` | A short design note for non-trivial work; cite requirement IDs. |
| 4 | build | `.agentic/steps/4_build.md` | Failing test first, then implementation, until green. |
| 5 | validate | `.agentic/steps/5_validate.md` | Review and reconcile the candidate, then prove it as the final action. |
| 6 | deliver | `.agentic/steps/6_deliver.md` | Present the validated candidate, report, commit, and publish. |

**Quick path.** For a small fix or change: `frame → build → validate → deliver`.
Decide this in `frame`, record `path: quick` in the journal header, and
say why in the log. Everything else uses the full path.

**Write zones.** Every stage may write under `.agentic/`. Beyond that,
`frame`, `specify` and `design` write nothing else — they come before the
code is agreed — while `build`, `validate`, and `deliver` have no mechanical
zone. `deliver` is still publish-only by instruction: if the validated
candidate changes, return to `validate`. It has no configured zone because
the merge-base diff cannot tell which stage introduced an edit. Advisory
like the rest: `check` reports an edit outside the current stage's zone
as `stage-zone`, it never blocks one, and a hit usually means the
journal's `stage:` is stale rather than that the edit was wrong. Change
the zones in `[zones]` in `aegis.toml`.

**Adopting an existing repo** into this workflow is not a stage — follow
`.agentic/steps/adopt.md` once, then work normally. Adoption journals use
their own stage values (`survey → components → close → done`), all
defined in that one file; `status` points them back at it.

## Where everything lives

| Artifact | Location |
|---|---|
| Requirements | `.agentic/requirements/<category>/REQ-<CAT>-<hex>.toml`, one file each |
| Category folders | `functional/ ux/ nfr/ security/ data/ platform/ reliability/ test/` for `REQ-FUNC/UX/NFR/SEC/DATA/PLAT/REL/TEST` |
| Specs (optional) | `.agentic/specs/REQ-<CAT>-<hex>.md` |
| Task journals | `.agentic/tasks/TASK-<hex>.md`, one per task, kept after delivery |
| Component knowledge | `.agentic/knowledge/<component>.md`, one page per component |
| Templates | `.agentic/templates/` — `requirement.toml`, `spec.md`, `task.md`, `component.md` |
| Step files | `.agentic/steps/` |
| CLI reference | `.agentic/CLI.md` |
| Config | `.agentic/aegis.toml` — test/lint commands, source and test globs |

Source code and tests stay where the repo already keeps them. Never write
work products anywhere else; `check` flags strays.

**Do not edit the payload.** `AGENTS.md`, `CLI.md`, `steps/`, `templates/`,
`aegis.py` and `LICENSE.txt` are replaced wholesale when this workflow is
upgraded, so any change you make there is silently lost. Found a bug in
`aegis.py`, or need a rule the steps do not cover? Say so and let the
human decide — a project-specific rule belongs in a file this repository
owns, not in the payload. Everything else under `.agentic/` —
`requirements/`, `specs/`, `tasks/`, `knowledge/`, `aegis.toml` — is
yours to write.

## Resume a task

1. Run `python .agentic/aegis.py summary TASK-<id>` for the named task
   (use `status` to find its ID when needed), then open the journal header
   and current checklist in `.agentic/tasks/TASK-<id>.md`.
2. Compare `git branch --show-current` with the journal's `branch:` line.
   On a mismatch, stop and reconcile first — check out the recorded
   branch, or say so if it does not exist here — before touching anything.
3. Read its `stage:` line and relevant log entries: agreed scope, user/Git
   limits, unresolved issues, decisions, and latest evidence; open the step
   file for that stage from the table above. Follow references to complete
   evidence, not just the last few lines of a long log. A missing, stale,
   or shortened summary requires journal review before continuing.
4. Continue at the first unticked item of `## Done checklist`. The
   checklist always belongs to the **current** stage: advancing a stage
   replaces it with the next stage's "Done when" list (each step file's
   last step says so).

Load linked requirements, specs, knowledge, source, and tests as the current
stage needs them; do not preload the whole repository or requirement register.
Full journal reads required by validate and deliver still apply. The summary
is an entry point, never a substitute for required review or fresh proof.

The journal is a committed file, so this works across sessions, machines,
and models. End every session by updating the journal. A journal travels
only with its branch: to continue on another computer, commit and push
the branch first (ask before pushing), then pull there — uncommitted work
never crosses machines.

## Interaction modes

- **Checkpoint (default).** Stop and ask twice, not once per stage: at
  the end of `frame` (scope, chosen path, proposed requirements — the
  cheap moment to course-correct) and before the `deliver` commit/PR
  (the validated candidate, check, and suite results, presented for a yes).
  The stages
  in between flow through without asking.
- **Autopilot.** When the prompt says "autopilot to deliver", suppress
  the frame stop. The pre-PR stop always remains, because publishing is
  the outward-facing act.

These pauses are conversational and sit on top of whatever permission or
sandbox prompts your host already applies. Autopilot loses no
auditability: the journal still shows the scope decision, the red-test
line, the check findings, and the ticked checklists after the fact.

**Deviation notices.** A third thing, and not a stop. The moment you record
a deviation, say it in the conversation too, as one line:

```
DEVIATION <stage>: <what> — <why accepted, or what it costs>
```

Then carry on: stating one never pauses the work and never waits for a
reply. Autopilot does not suppress them either — the mode that removes the
frame stop is exactly the one where silence costs most. Say one when you
accept a `check` warning, when a command exits non-zero or you skip or
cannot run a verification you owed, when `anchor` or `evolution` reports
something other than what you expected, when a `Manual:`/`Inspection:`
method stands in for a test that could have been automated, when you retire
a requirement, and when diff review turns up work nobody asked for.

The journal line you would have written anyway is still written. The notice
is its twin, not its replacement — a journal is read afterwards, and by then
the human has already paid for not knowing. `DEVIATION` is deliberately not
`WARNING`: `check` prints `WARN` and `NOTE` for its own findings, and your
judgement should not be mistaken for the tool's.

## Stage reporting

At each stage completion or pause, present one compact report **before any
detailed explanation**. Reporting does not introduce approval stops: the two
ordinary checkpoints, adoption approvals, and explicit user limits still
apply. Immediate `DEVIATION` notices remain immediate; do not defer them to
the report. Do not report after every command.

After recording evidence and decisions in `## Log`, update the journal's
single `## Stage report` section using the plain fields in `templates/task.md`:
`stage`, `result`, `current`, `changed`, `evidence`, `issues`, `next`,
`needs_user`. It is a replaceable latest snapshot; the log stays append-only.
Record the completed stage in `stage`, and the actual header stage in
`current` after any transition. Use `result: paused` when waiting or ending a
session; other outcomes are `in_progress`, `completed`, `blocked`, `skipped`.
Stage names stay canonical (`specify` means requirements); reporting must not
rename stages or claim the next stage has been completed.

Run `python .agentic/aegis.py summary TASK-<id>` and copy its output into one
plain text code block. The fields are always Stage, Task, Current,
Requirements, Changed, Evidence, Issues, Next, Needs user, Details.
The command only reads the journal; it does not run tests or grant approval.
Write observed command results and their scope, never an inferred "passed";
blank values remain `not recorded`. Name all unresolved issues and carry
required decisions forward; `needs_user: no` requires an explicit reason to
continue under the existing interaction mode, not a guess from silence.

A missing or stale record must be reconstructed from the journal before
continuing. A shortened field is visibly marked: read the full journal before
acting, especially unresolved issues, deviations, evidence, and user requests.
Do not replace omitted content with "none". The snapshot is agent-authored,
not fresh proof; refresh it after work, new results, or decisions even when
the stage has not changed. Full delivery presentation remains required.

## Prompt cheatsheet

Starting work is one line:

```
using aegis workflow, implement feature X
```

That means: read this file, start at `1_frame.md`, and continue through
the stages, stopping where the interaction mode says to. Add `autopilot
to deliver` to suppress the frame stop. `fix X` or `change X` work the
same way — `frame` decides whether they take the quick path.

For a small local model, give one stage per session:

Each prompt below explicitly ends the session after that stage. Advance the
header/checklist when appropriate, record the report, then stop before work
on the next stage. This session limit does not add an approval gate to normal
checkpoint or autopilot runs. The workflow is model-independent: compact
output reduces context use but does not prove compliance by a particular
model or guarantee a tokenizer-specific 64K budget.

| Stage | One-line prompt |
|---|---|
| frame | `Read .agentic/AGENTS.md. Start task "<title>": follow .agentic/steps/1_frame.md, then record and show the stage report. Stop after this stage.` |
| specify | `Read .agentic/AGENTS.md. Continue TASK-<id> (stage specify): follow .agentic/steps/2_specify.md, then record and show the stage report. Stop after this stage.` |
| design | `Read .agentic/AGENTS.md. Continue TASK-<id> (stage design): follow .agentic/steps/3_design.md, then record and show the stage report. Stop after this stage.` |
| build | `Read .agentic/AGENTS.md. Continue TASK-<id> (stage build): follow .agentic/steps/4_build.md, then record and show the stage report. Stop after this stage.` |
| validate | `Read .agentic/AGENTS.md. Continue TASK-<id> (stage validate): follow .agentic/steps/5_validate.md, then record and show the stage report. Stop after this stage.` |
| deliver | `Read .agentic/AGENTS.md. Continue TASK-<id> (stage deliver): follow .agentic/steps/6_deliver.md, then record and show the stage report. Stop after this stage.` |
| adopt | `Read .agentic/AGENTS.md. Adopt this repo: follow .agentic/steps/adopt.md, one component per session.` |

## Commands you will use

The complete syntax, options, examples, exit behavior, and guidance on when
to use each command are in `.agentic/CLI.md`.

```
# "python" throughout - use "python3" on Linux distributions without it
python .agentic/aegis.py status                 # open tasks, or one task's state
python .agentic/aegis.py summary TASK-<id>       # compact recorded stage report
python .agentic/aegis.py task "<title>"         # new task journal
python .agentic/aegis.py req <cat> "<title>"    # new requirement file
python .agentic/aegis.py check                  # advisory report, always exits 0
python .agentic/aegis.py test --impacted --base HEAD   # fast loop in build
python .agentic/aegis.py test                   # full suite, used at validate
python .agentic/aegis.py report TASK-<id>       # delivery summary into the journal
python .agentic/aegis.py diagram --component <name>    # coverage map, for a human
python .agentic/aegis.py explain <path>         # what governs this file
```

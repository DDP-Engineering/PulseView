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

## Semantic analysis protocol

Frame, specify and design use the same compact analysis cycle before their
workflow administration. The stage files define the artifact each cycle
produces:

1. **Analyze** the request and selected repository evidence. Read the smallest
   sufficient set of linked sources rather than filling the context window.
2. **Challenge** the emerging account for contradictions, missing actors or
   triggers, boundary and failure cases, hidden constraints, and unsupported
   assumptions. Ask only decision-blocking questions; preserve other gaps as
   explicit unknowns.
3. **Write** the durable stage artifact using its named structure. Classify
   material claims as `STATED` by the user, `OBSERVED` in repository evidence,
   `INFERRED` from those facts, or `UNKNOWN`. Cite paths for observed facts.
4. **Audit** the artifact for completeness, internal consistency, traceability,
   invented behavior, and unresolved decisions before advancing the stage.

This is an evidence and output protocol, not a request to expose private model
reasoning. Never silently turn an inference or unknown into product behavior.
Record the decision or ask the human when it would materially change scope,
observable behavior, compatibility, security, data handling, or verification.
Use the journal and linked artifacts as the durable result; conversational
reasoning and a large context window are not durable evidence.

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
| Project profile | `.agentic/context/project.md`, current purpose, responsibilities, constraints, and entry points |
| Environment guide | `.agentic/context/environment.md`, current toolchain, setup, readiness, and verification routes |
| Templates | `.agentic/templates/` - `requirement.toml`, `spec.md`, `task.md`, `component.md`, `project.md`, `environment.md` |
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
`requirements/`, `specs/`, `tasks/`, `knowledge/`, `context/`, `aegis.toml` - is
yours to write.

## Current project context

`init` creates each missing context file from its template and preserves every
existing file. The files are project-owned Markdown with stable headings, not
an event log or a generated copy of the repository. Empty sections are valid;
initialization supplies structure, not project facts. Older projects can use
the workflow with either file absent. Discover the relevant facts directly
and populate context incrementally within the agreed scope.

Read the project profile at frame and resume; read the relevant environment
sections before setup, build, or verification, especially on a new computer.
Follow links to the selected component, requirements, exact source, and tests.
`brief` lists context paths and file presence only; presence is not proof that
a file is populated or accurate. Load selected references, not every page.

Populate context from repository evidence during frame or adoption. For a new
project, record its confirmed purpose and actual setup, then add responsibilities
as they are implemented. Keep planned capabilities in the task and draft
requirements/specs until realized. Update affected sections when implementation
or setup changes; validate reconciles them before final proof. Leave unchanged
sections untouched. On resume or after branch integration, recheck relevant
claims against this checkout; another branch's plans are not current facts.

### Current-state documentation rule

Project documents, component pages, and active requirements/specs describe
current responsibilities and observable behavior directly and positively.
For example: "The admin page displays the project logo in its top-right
corner." Keep one current statement, not alternatives, removed features,
before/after accounts, task IDs, or a running change history. State adjacent
components' actual responsibilities when explaining boundaries.

Positive wording preserves the complete contract, including errors, security,
privacy, and compatibility. For example: "The service returns 403 for callers
without the required role" and "Exports contain authorized records only."
Keep the trigger, response, and testable boundary; a word-level ban on negative
phrases would lose meaning. Review semantics instead.

Keep proposals and open decisions in task records and explicitly draft
requirements/specs; keep past decisions and investigation findings in journals,
Git, and the changelog. Retired requirements remain available for traceability
but are not current behavior or a reason to list removed features in summaries.
When touching an existing page, reconcile relevant stale statements rather
than appending a correction history. Preserve established requirements unless
the user authorizes a behavior change: a code/document conflict is a finding,
not permission to rewrite the contract to fit the easiest implementation.

Link authoritative setup docs and `[commands]`/`[layout]` in `aegis.toml` rather
than maintaining duplicate values. Keep secrets in their approved stores and
machine-specific paths and run outcomes in task evidence. Context adds guidance,
not a new gate, approval, or automatic setup authority.

## Resume a task

1. Run `python .agentic/aegis.py brief TASK-<id>` for the named task
   (use `status` to find its ID when needed), then open the journal header,
   current checklist, current step file, and the Handoff `must_read` paths.
2. Compare `git branch --show-current` with the journal's `branch:` line.
   On a mismatch, stop and reconcile first — check out the recorded
   branch, or say so if it does not exist here — before touching anything.
3. Read its `stage:` line, dedicated Frame/Design/Rulings/Handoff sections as
   applicable, and relevant log entries: stage outcomes, blockers, material
   changes, and consolidated evidence; open the step file for that stage from
   the table above. Follow references to complete
   evidence, not just the last few lines of a long log. A missing, stale,
   or shortened summary requires journal review before continuing.
4. Continue at the first unticked item of `## Done checklist`. The
   checklist always belongs to the **current** stage: advancing a stage
   replaces it with the next stage's "Done when" list (each step file's
   last step says so).

Load linked requirements, specs, knowledge, source, and tests as the current
stage needs them; do not preload the whole repository or requirement register.
Full journal reads required by validate and deliver still apply. Brief and
summary are entry points, never substitutes for required review or fresh proof.

The journal is a committed file, so this works across sessions, machines,
and models. End every session by updating the journal. A journal travels
only with its branch: to continue on another computer, commit and push
the branch first (ask before pushing), then pull there — uncommitted work
never crosses machines.

## Optional child tasks

Large work may use opt-in child tasks, limited to one level, with
`task "<title>" --parent TASK-<id>`. The relationship is stored only in the
child; creation never edits the parent. A child cannot be a parent, and every
child keeps its own branch, base, requirements, journal, evidence, and
approvals. Visible-child views scan only journals in the current checkout and
must never claim state hidden on another branch or machine.

Frame decides whether the work is large enough to split. Design assigns
non-overlapping scopes and requirement links. Children are governed and
validated independently. After their work is reconciled, the parent owns
validation of the integrated candidate and the status of children visible in
this checkout. AEGIS does not dispatch, branch, merge, or create worktrees.

## Interaction modes

- **Checkpoint (default).** With autopilot off, stop after every completed stage,
  show its report and the applicable Stage-boundary choices below, and wait for
  the user before advancing. This keeps scope, requirements, design, code and
  proof separately reviewable.
- **Autopilot.** With autopilot on, flow between stages without presenting the
  intermediate choice menus. The pre-publication approval always remains,
  because publishing is the outward-facing act.

The repository default is project-owned configuration:

```toml
[interaction]
autopilot = false
```

Missing table or key means `false`. An invalid value also fails safe to off and
`check` reports it. `aegis task` records the resolved mode as `interaction:` in
the new journal. A legacy journal without that header resolves from the current
configuration. An explicit user instruction for the task overrides the
configured default; update the journal header so the choice survives resume.

At a checkpoint boundary, finish and audit the stage artifacts but do not
advance the header or replace the checklist yet. Refresh Handoff with the
current stage and `status: waiting`; record the Stage report with
`result: paused`, `current:` equal to the header, and `needs_user: yes`; show
the summary and the applicable choices; then stop. When the user chooses to
continue, record the decision, tick the completed checklist, advance the header
and checklist, refresh Handoff and the Stage report, and begin the next stage.
When the user chooses a revision or return, keep or restore the named stage and
its checklist before changing artifacts. A pause leaves the current stage and
waiting Handoff intact.

### Stage-boundary choices

Use concrete stage names and artifacts rather than generic wording. Render
each choice as its own numbered or bulleted line:

| Completed work | Present these choices |
|---|---|
| `frame` | Continue to `specify` (or `build` on the quick path); revise scope, assumptions or path; pause current workflow. |
| `specify` | Continue to `design`; revise requirements or specs; return to `frame`; pause current workflow. |
| `design` | Continue to `build`; revise the design; return to `specify`; pause current workflow. |
| `build` | Continue to `validate`; change implementation or tests; return to `design` or `specify`; pause current workflow. |
| `validate` | Continue to `deliver`; return to `build` for corrections; reconsider scope or requirements; pause current workflow. |
| `deliver`, before publication | Approve the stated delivery action; change the delivery outcome; return to `validate`; pause current workflow. |

After successful delivery and transition to `done`, report the outcome without
another continuation menu.

These pauses are conversational and sit on top of whatever permission or
sandbox prompts your host already applies. Autopilot loses no
auditability: the journal still shows the scope decision, the red-test
line, the check findings, and the ticked checklists after the fact.

Children, Rulings, Handoff, brief and optional explicit review do not create
additional stops beyond the configured stage boundaries.

**Deviation notices.** A third thing, and not a stop. The moment you record
a deviation, say it in the conversation too, as one line:

```
DEVIATION <stage>: <what> — <why accepted, or what it costs>
```

Then carry on: stating one never pauses the work and never waits for a
reply. Autopilot does not suppress them either - the mode that flows between
stage boundaries is exactly the one where silence costs most.

A deviation exists only when the candidate, agreed scope, design or contract,
or confidence in required verification materially differs from what was
planned or required. Say one when you accept a current-task finding that
affects the candidate or its evidence, skip or replace required verification,
weaken or remove a test, accept an implementation that departs from the agreed
design, retire a requirement, accept unexpected candidate files, or retain
unrequested work found in review.

Do not use `DEVIATION` for recoverable internal tool-use errors — bad shell
quoting, a failed search, a rejected atomic patch, a mistyped path, or a
transient command failure — when they are corrected or rerun without changing
the candidate, scope, or verification evidence. An expected failing test in
the red phase is ordinary test-first evidence, not a deviation. Pre-existing
or unrelated findings are reported with validation evidence, not promoted to
current-task deviations.

Record the material deviation in the journal Log as durable history. The notice
is its twin, not its replacement — a journal is read afterwards, and by then
the human has already paid for not knowing. `DEVIATION` is deliberately not
`WARNING`: `check` prints `WARN` and `NOTE` for its own findings, and your
judgement should not be mistaken for the tool's.

## Journal log

The append-only `## Log` is a progress-and-evidence ledger, not a session or
tool transcript. Record only durable events that change the task's stage,
scope, engineering outcome, verification status, authority, or ability to
proceed: stage transitions; material scope or implementation decisions not
already captured in Rulings, Design, or a spec; consolidated automated or
manual verification results; material discoveries; blockers; approvals;
deviations; and delivery outcomes.

Do not log routine reads, searches, edits, tool mechanics, corrected command
retries, or repeated content already held by another journal section or linked
artifact. A failed command belongs only when it exposes a candidate problem,
changes the implementation or tests, or remains an accepted verification
limitation. Consolidate related test results by meaningful behavior increment;
do not append every inner-loop retry. Keep entries concise and link to the
durable detail instead of copying it. Existing entries are never rewritten.

## Verification efficiency

Use the project's documented readiness checks before testing in a new checkout.
Build uses focused native tests or configured impacted selection that actually
honors the selected references. `test --impacted --dry-run` previews the command;
`--no-fallback` refuses to start the full command when selection is unavailable.
A successful preview proves nothing. Runner syntax, toolchains and environment
setup belong to the project; AEGIS never installs them or guesses test adapters.
Run the configured full verification at the end of validate, after edits and
review. Repeat it for a failure or a changed final candidate, not merely because
a stage changed. Do not run a separate full suite immediately before strict
validation. Inspect existing jobs and logs before starting or polling another.

Read shared instructions once per intact session. Reuse documents already read
when they have not changed; inspect changed sections and relevant earlier
rulings/evidence. After compaction or lost context, follow the resume procedure
and required full reads. Keep Handoff fields short and update changed fields
instead of restating Frame, Design, or Log. Generated records omit marked
authoring notes; full guidance stays in `templates/` for reference.

## Rulings and handoffs

Rulings are append-only durable decisions. Use the exact `RULING-` format in
the task template for approved scope changes, authority constraints, durable
technical choices, and accepted deviations with future impact. Never edit or
delete an old ruling; append a later ruling whose `supersedes` value names it.
Rulings cannot grant authority or override newer user instructions,
repository rules, or Git authority.

Handoff is one replaceable minimal resume snapshot. Handoff current must match
the journal header stage; `next` names exactly one action and `must_read` names
only the repository-relative files needed for that action. Refresh it at every
stage transition, pause, blocker, and session end. The log remains the history,
the Stage report remains the user-facing result, and neither Rulings nor
Handoff adds an approval stop.

## Stage reporting

At each stage completion, pause or session end, or blocker, present one compact
report **before any detailed explanation**. Reporting does not introduce
stops by itself: checkpoint mode, the publication boundary, adoption approvals
and explicit user limits determine when a response is required. Immediate
`DEVIATION` notices remain immediate; do not defer them to the report. Do not
report after every command.

At that boundary, record any durable event that belongs in `## Log`, then
update the journal's single `## Stage report` section using the plain fields in
`templates/task.md`:
`stage`, `result`, `current`, `changed`, `evidence`, `issues`, `next`,
`needs_user`, `spec_compliance`, `implementation_quality`, and `review_round`.
It is a replaceable latest snapshot; the log stays append-only. Review fields
are `disabled`/blank when optional review is off and current-candidate verdicts
when it is on.
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
required decisions forward. At every checkpoint boundary use `needs_user: yes`;
`needs_user: no` requires autopilot or an explicit reason to continue, not a
guess from silence.

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

That means: read this file, start at `1_frame.md`, and follow the interaction
mode recorded for the task. With the default configuration, stop after each
stage and show the Stage-boundary choices. An explicit `autopilot to deliver`
instruction selects autopilot for that task, while preserving pre-publication
approval. `fix X` or `change X` work the same way - `frame` decides whether
they take the quick path.

For a small local model, give one stage per session:

For a resumed task, start with `brief TASK-<id>`, then read the current step
file and only the Handoff `must_read` paths before following the stage prompt.

Each prompt below explicitly ends the session after that stage. In checkpoint
mode this is the normal stage boundary; in autopilot it is an explicit
single-session limit. Record the report and stop before work on the next stage.
The workflow is model-independent: compact
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
python .agentic/aegis.py brief TASK-<id>         # bounded durable resume view
python .agentic/aegis.py summary TASK-<id>       # compact recorded stage report
python .agentic/aegis.py components              # component titles and page paths
python .agentic/aegis.py task "<title>"         # new task journal
python .agentic/aegis.py req <cat> "<title>"    # new requirement file
python .agentic/aegis.py check                  # advisory report, always exits 0
python .agentic/aegis.py test --impacted --base HEAD --no-fallback  # optional focused build check
python .agentic/aegis.py check --task TASK-<id> --strict --run  # final full proof
python .agentic/aegis.py report TASK-<id>       # delivery summary into the journal
python .agentic/aegis.py diagram --component <name>    # coverage map, for a human
python .agentic/aegis.py explain <path>         # what governs this file
```

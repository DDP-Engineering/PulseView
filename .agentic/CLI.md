<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# AEGIS CLI reference

AEGIS uses one standard-library Python script. Run it from the
repository root:

```text
python .agentic/aegis.py <command>
```

Use `python3` instead of `python` on systems where that is the available
Python 3.11-or-newer command. Paths and examples below are relative to the
repository root.

The CLI scaffolds artifacts, writes task-journal state, runs configured
project commands, and reports advisory findings. It does not replace the
workflow in `.agentic/AGENTS.md`: it never decides whether a stage's work is
done, and it does not commit, push, merge or read tickets. The CLI itself makes
no network requests; configured project commands may do so.

## Command summary

| Command | Description | When to use |
|---|---|---|
| `init` | Complete installation after copying the payload. | Once during installation, and safely after a payload upgrade. |
| `task` | Create a task journal with a unique ID. | At the start of governed feature, fix, change, or adoption work. |
| `advance` | Move a task to its next stage and record the State. | When a stage's work is finished, skipped, or must return to an earlier stage. |
| `pause` | Record a stop or a blocker in the State. | At a checkpoint, a blocking question, or the end of a session. |
| `log` | Append one dated line to the journal Log. | When a durable event happens: a decision, a verification result, a discovery, a deviation. |
| `ruling` | Append one decision to the journal Rulings. | When the user, a requirement, the repository, or a technical constraint settles a question. |
| `verdict` | Record explicit review verdicts and the review round. | In validate, when explicit review is enabled. |
| `req` | Create a requirement TOML file with a unique ID. | When work needs a new durable requirement. |
| `anchor` | Fingerprint Git-visible repository files for a task. | After the expected red failure and before implementation. |
| `evolution` | Compare the repository with its active task anchor. | After implementation and after any later validation edit. |
| `status` | List open tasks or inspect one journal. | Before starting or resuming work, and whenever the next step is unclear. |
| `brief` | Print a deterministic bounded resume view from durable files. | First when resuming, especially with a small-context model. |
| `components` | List component knowledge titles and page paths. | Before choosing which component page to read. |
| `check` | Run the heuristic governance catalog. | During work for feedback; with `--strict --run` at the validation or CI boundary. |
| `test` | Run a command configured in `.agentic/aegis.toml`. | During build and validation, optionally recording the result in a journal. |
| `summary` | Print a compact recorded stage snapshot without writes. | Before resuming and after recording a stage completion or pause. |
| `report` | Append a delivery summary to a task journal. | At the end of validate, once the evidence is final. |
| `diagram` | Draw the requirement register as a Mermaid coverage map. | In review or handover, when the question is where verification is thin. |
| `trace` | Export the requirement register as a traceability matrix. | In audit, review or handover, when the whole register has to leave the repository. |
| `explain` | Show which requirements and tasks govern one path. | Reading unfamiliar code, or before changing a file you did not write. |

## General help and version

### `--help`

**Description:** Show the top-level commands. Every command and subcommand
also accepts `--help`.

**When to use:** When checking syntax against the installed payload, which is
the authority if another document has drifted.

**Examples:**

```text
python .agentic/aegis.py --help
python .agentic/aegis.py check --help
python .agentic/aegis.py task --help
```

### `--version`

**Description:** Print the installed AEGIS version.

**When to use:** After installation or upgrade, or when reporting an issue.

**Example:**

```text
python .agentic/aegis.py --version
```

## `init`

```text
python .agentic/aegis.py init [--git]
```

**Description:** Finish installing a copied AEGIS payload. It:

- creates `.agentic/requirements/`, `specs/`, `tasks/`, `knowledge/`, and `context/`
  when absent;
- scaffolds `.agentic/context/project.md` and
  `.agentic/context/environment.md` independently when absent, stripping
  marked authoring notes and preserving existing bytes;
- creates a default `.agentic/aegis.toml` only when absent;
- adds or refreshes the managed AEGIS digest in root
  `AGENTS.md`, `assistant.md`, and `QWEN.md`;
- adds or removes the managed anchor/evolution block in the root `.gitignore`
  according to `[records] commit_fingerprints`, and reports how many sidecars
  are still tracked so a human can untrack them (it never runs `git rm`);
- reports whether Git is installed and whether the directory is a repository;
- preserves project-owned data and an existing `.agentic/aegis.toml`.

The command is idempotent: running it again does not replace the repository's
configuration or governance records. Context scaffolds contain headings, not
project claims. Populate current positive facts during frame or adoption and
reconcile affected sections when implementation or setup changes. Keep history
in task records. Missing context in an older project adds no workflow gate.

When Git is installed but the directory is not a repository, plain `init`
prints the next command and changes no Git state. `init --git` explicitly runs
`git init`. When Git is unavailable, initialization still succeeds but reports
that diff checks, impacted selection, anchor, and evolution evidence are
unavailable.

**When to use:** Immediately after copying `.agentic/` into a repository.
Run it again after copying a newer payload so the root digests match the
installed workflow.

**Example:**

```text
python .agentic/aegis.py init
python .agentic/aegis.py init --git
```

Afterward, edit `.agentic/aegis.toml` so `[commands]`, `[layout]`, optional
`[interaction]`, `[diagrams]`, `[records]`, `[context]`, and `[check]` settings
describe the repository.

## `task`

```text
python .agentic/aegis.py task "<title>" [--type {feature,fix,change,adopt}] [--parent TASK-<id>]
```

**Description:** Create `.agentic/tasks/TASK-<id>.md` from the task
template. The journal receives a collision-resistant ID, the current date,
the current Git branch and commit when available, `stage: frame` (`survey` for
`adopt`), the interaction mode resolved from `.agentic/aegis.toml`, the
stage's "Done when" list as its Done checklist, and an initial `## State`. The
new path is printed on stdout.

The default type is `feature`. Accepted types are:

| Type | Use for |
|---|---|
| `feature` | New user-visible or system capability. |
| `fix` | Correction of confirmed faulty behavior. |
| `change` | Maintenance or behavior change that is not best described as a feature or fix. |
| `adopt` | Bringing an existing repository under AEGIS. |

**When to use:** At the beginning of a new governed unit of work, after first
using `status` to ensure an existing open journal does not already cover it.
A bare task ID as the title, such as `task TASK-8b12`, is refused with a
pointer to `brief`: resuming a task never opens a second journal.

**Examples:**

```text
python .agentic/aegis.py task "Export audit report" --type feature
python .agentic/aegis.py task "Handle empty configuration" --type fix
python .agentic/aegis.py task "Adopt inventory service" --type adopt
```

Then follow the step file the journal names; `advance` moves the stage when
its work is finished.

`--parent` is optional and creates only the child-side `parent:` link. The
named parent must exist and must itself be top-level; nested children are
rejected. The parent journal is never edited. Each child keeps its own branch,
base, requirements, stages and validation. Reverse
lookup scans journals visible in the current checkout only, so it cannot claim
knowledge of children that exist solely on another branch. The parent owns
validation of the integrated candidate.

New project records - journals, requirements and context pages - omit the
payload license block and the template-only authoring notes, retaining their
data fields; they belong to the project. Existing records are never rewritten.
Inspect the templates when their full field guidance is needed.

## Journal state commands

`advance`, `pause`, `log`, `ruling` and `verdict` write the parts of a journal
that must stay machine-readable: the header stage, the Done checklist, the
Log, the Rulings and the `## State` block. Frame, Requirement coverage and
Design stay ordinary edits. The commands record what the agent decided; none
of them checks whether a stage's work is done, and none of them blocks.
Free-text values are stored on one line; `pause` and `advance` keep a
previously recorded `changed`, `evidence` or `issues` value unless a new one is
given, and both print the `summary` block.

The State block, one `key: value` per line:

```text
status: ready
reported: design - completed
next: start build: read .agentic/steps/4_build.md
must_read: .agentic/tasks/TASK-8b12.md, .agentic/steps/4_build.md
changed: design section written
evidence: check exit 0
issues:
spec_compliance: disabled
implementation_quality: disabled
review_round:
```

`status` is `working`, `waiting`, `blocked`, `ready` or `done`; `waiting` and
`blocked` mean the user is needed. `reported` names the last reported stage and
its result: `in_progress`, `completed`, `paused`, `blocked` or `skipped`. The
current stage is always the header's `stage:` line. Journals written before
this block keep their `## Handoff` and `## Stage report`; `brief`, `summary`,
`check` and `report` read either format, and the first State write replaces
the two old sections.

A header key written twice keeps its first written value: an empty template
line never hides a value written on another line, and the writers update the
first line. `pause` and `advance` print a note, never a refusal, when frame,
specify or design stops with its own section still empty, and for a record an
edit put out of shape: a repeated header key, or Rulings lines that `ruling`
did not write.

## `advance`

```text
python .agentic/aegis.py advance <TASK-id|id> [--to STAGE] [--skipped]
                                 [--reason TEXT] [--next TEXT] [--read PATH]
                                 [--changed TEXT] [--evidence TEXT] [--issues TEXT]
```

**Description:** Record a stage transition. Without `--to`, the next stage is
the one after the current stage in frame, specify, design, build, validate,
done. The header stage changes, the Done checklist becomes the destination
step's "Done when" list, one Log line records the transition, and the State
says what to do next. A `path:` header line in an older journal is kept and
no longer changes the order. `--to` an earlier stage records a return: the State waits for the
user and enabled review verdicts are cleared while the consumed round is kept.
`--skipped` records a skipped stage. Reaching `done` closes the implementation
guidance; commit, push and integration belong to the developer.

Unticked Done checklist items and, with explicit review enabled, verdicts
that are not both approved at `done` are noted in the Log line and on
stdout. They never stop the transition.

**When to use:** When the current stage's work is finished, when the user
accepts a stage boundary in checkpoint mode, or when a later stage finds that
an earlier one must change.

**Examples:**

```text
python .agentic/aegis.py advance TASK-8b12
python .agentic/aegis.py advance TASK-8b12 --skipped --reason "REQ-FUNC-1a2b3c4d covers it"
python .agentic/aegis.py advance TASK-8b12 --to specify --reason "a missing error case"
python .agentic/aegis.py advance TASK-8b12 --evidence "check --strict --run exit 0"
```

## `pause`

```text
python .agentic/aegis.py pause <TASK-id|id> --next TEXT [--blocked] [--read PATH]
                               [--changed TEXT] [--evidence TEXT] [--issues TEXT]
```

**Description:** Record that the work stops here, with the one action or
question that resumes it. The State becomes `waiting` (or `blocked` with
`--blocked`), the header stage stays, and `must_read` lists the journal, the
current step file and any `--read` paths.

**When to use:** At a checkpoint stop, when a decision-blocking question goes
to the user, and at the end of a session.

**Examples:**

```text
python .agentic/aegis.py pause TASK-8b12 --next "Accept the framed scope?"
python .agentic/aegis.py pause TASK-8b12 --blocked --next "Which retention period applies?"
```

## `log`

```text
python .agentic/aegis.py log <TASK-id|id> <text>
```

**Description:** Append one dated line, prefixed with the current stage, to
the end of the journal Log. Earlier lines are never changed. The words after
the task ID are joined, so quoting is optional. A line that records a later
stage's work - a `red:` or `green:` label before build, `final:` before
validate, or a later stage's name - prints a note to `advance` first; it is
logged either way.

**When to use:** For durable events only: decisions, verification results,
discoveries, blockers, approvals and deviations. `advance` already logs
transitions and `test --task` logs test results.

**Example:**

```text
python .agentic/aegis.py log TASK-8b12 "red: tests/test_export.py fails on the missing field"
```

## `ruling`

```text
python .agentic/aegis.py ruling <TASK-id|id> --decision TEXT --reason TEXT
                                --source {user,repository,requirement,technical}
                                [--supersedes RULING-NNN]
```

**Description:** Append the next numbered Ruling, dated today. Decision and
reason are single lines without `|`. A changed decision is a new ruling that
names the one it supersedes; earlier lines stay as written.

**When to use:** When a scope, behavior or technical question is settled and
later sessions must not reopen it.

**Example:**

```text
python .agentic/aegis.py ruling TASK-8b12 --decision "keep 30 days of history" --reason "user answer" --source user
```

## `verdict`

```text
python .agentic/aegis.py verdict <TASK-id|id> [--spec {approved,changes_required}]
                                 [--quality {approved,changes_required}] [--round N]
```

**Description:** Record the independent reviewers' verdicts and the review
round in the State. It refuses while `[review] enabled` is not `true`, where
both verdicts stay `disabled`. The round must lie within
`1 + max_fix_cycles`; without `--round` the recorded round is kept, or 1.

**When to use:** In validate with explicit review enabled, after each review
round.

**Example:**

```text
python .agentic/aegis.py verdict TASK-8b12 --spec approved --quality changes_required --round 1
```

## `anchor`

```text
python .agentic/aegis.py anchor --task TASK-<id> [--json]
```

**Description:** Record a timestamped SHA-256 fingerprint of every tracked or
untracked, non-ignored repository file except `.agentic/**`. The record stores
the current task stage, HEAD, configured source/test globs, file kinds, paths,
and hashes in `.agentic/tasks/TASK-<id>.anchor.json`. Generated Python bytecode
under `__pycache__/`, plus `.pyc` and `.pyo` files, is always excluded.

Run this after confirming the expected red test and before implementation. For
work without an automated red test, run it immediately before the first
implementation edit. Re-running replaces the active anchor and says whether
the prior anchor already had a completed evolution report.

The record describes a starting point; it is not tamper-proof and does not
prove that a test or implementation was honest. Both sidecars stay out of git
by default; see `[records] commit_fingerprints` under Coordinated workflow
records.

## `evolution`

```text
python .agentic/aegis.py evolution --task TASK-<id> [--json] [--compact]
```

**Description:** Compare the current Git-visible repository with the active
anchor. Added, modified, and removed paths are printed with their `source`,
`tests`, or `other` category. Changes never make this command fail.

The compact result is saved in
`.agentic/tasks/TASK-<id>.evolution.json`. Completed anchor/evolution pairs are
retained; rerunning evolution for the active anchor refreshes that pair so a
later validation edit can be reflected without duplicate history.

Both commands use UTC ISO 8601 timestamps. `--json` emits one complete machine
envelope on stdout.

For evolution, `--compact --json` emits paths, statuses and areas without the
before/after hashes. The saved evolution file remains complete; ordinary `--json`
output retains its existing schema and detail.

## `req`

```text
python .agentic/aegis.py req <category> "<title>"
```

**Description:** Create a requirement TOML file from the requirement template.
The file receives a collision-resistant requirement ID and the current
creation/update date. Its path is printed on stdout.

Accepted categories and aliases:

The abbreviation printed inside a requirement ID is always accepted as its
own category name, so `func` and `functional` do the same thing.

| Input | Stored category and ID prefix |
|---|---|
| `functional`, `func` | `functional`, `REQ-FUNC` |
| `ux` | `ux`, `REQ-UX` |
| `nfr`, `non_functional` | `nfr`, `REQ-NFR` |
| `security`, `sec` | `security`, `REQ-SEC` |
| `data`, `data_privacy` | `data`, `REQ-DATA` |
| `platform`, `plat` | `platform`, `REQ-PLAT` |
| `reliability`, `rel`, `release` | `reliability`, `REQ-REL` |
| `test`, `testing` | `test`, `REQ-TEST` |

**When to use:** During specification when no existing requirement expresses
the intended behavior. Update or reuse an existing requirement instead when
it already owns the behavior.

**Examples:**

```text
python .agentic/aegis.py req functional "Export reports as JSON"
python .agentic/aegis.py req security "Reject unsigned packages"
python .agentic/aegis.py req reliability "Restore interrupted uploads"
```

The generated file is a scaffold. Complete its statement, rationale,
acceptance criteria, affected paths, and verification links before treating it
as active.

## `status`

```text
python .agentic/aegis.py status [TASK-<id>|<id>] [--all] [--json]
```

**Description:** Without a task ID, list task journals that are not
`stage: done`. With an ID, show that journal's header, checklist progress,
recent log entries, and the step file to open next. The short hexadecimal ID
is accepted with or without the `TASK-` prefix.

Options:

| Option | Effect |
|---|---|
| `--all` | Include journals whose stage is `done`. |
| `--json` | Emit one complete schema-versioned JSON document on stdout. |

**When to use:** Before opening new work, when resuming after an interruption,
or when handing work to another developer or agent.

**Examples:**

```text
python .agentic/aegis.py status
python .agentic/aegis.py status --all
python .agentic/aegis.py status TASK-8b12
python .agentic/aegis.py status 8b12 --json
```

## `summary`

```text
python .agentic/aegis.py summary <TASK-id|id>
```

**Description:** Print a compact recorded stage snapshot without writing files,
running checks/tests, consulting Git, or changing workflow state. Existing
`status` JSON is unchanged; `report` remains the journal-writing delivery
summary. `advance`, `pause` and `verdict` print this block after writing; use
`brief` first when resuming.

The snapshot comes from the journal's `## State` block (see
[Journal state commands](#journal-state-commands)), or from the legacy
`## Stage report` and `## Handoff` sections of a journal written before it.
Needs user is derived: yes while the State is `waiting` or `blocked`. The
fields contain the agent's recorded observations and decisions; blank values
print `not recorded`.

Output fields, in order: **Stage, Task, Current, Requirements, Changed,
Evidence, Issues, Next, Needs user, Specification compliance, Implementation
quality,
Review round, Details**. Stage combines the reported
stage and result; Current and Requirements come from the journal header.
Details points to the full journal. Each value is at most 240 characters,
including a visible `[truncated; read journal]` marker for omitted detail.
If any value is shortened, Needs user directs full-journal review before
proceeding, even if the record said no. This is a character bound, not a
model-specific token guarantee.

A missing or incomplete State, or one that reports another stage while still
`working`, `waiting` or `blocked`, suppresses recorded outcomes and
next-action claims and directs journal review. Unknown stages, statuses or
results, duplicate sections/fields, unknown keys, and malformed record lines
exit 1 with an error and no partial stdout. Old journals need no migration.
Commented and fenced examples outside the live section do not supply report
facts; literal comment markers in inline code and fence info stay literal.

The output is an agent-authored snapshot, **not fresh proof or an approval**.
A matching stage cannot detect subsequent source edits: refresh the record
after new work, evidence, deviations, or decisions even within one stage.
Read omitted details and unresolved issues before acting. Normal checkpoints,
full validation/delivery reads, and immediate deviation notices still apply.

## `brief`

```text
python .agentic/aegis.py brief <TASK-id|id>
```

**Description:** Print a read-only, deterministic resume view derived only
from the task journal, visible task journals, `.agentic/aegis.toml`, and the
presence of the two project context files. It
does not call Git, run commands, write files, advance stages, or infer approval.
Two calls against unchanged files are byte-identical.

The fixed output order is: `AEGIS brief`, Task, Stage, Branch/base,
Parent, Requirements, Context, Checklist, State, Outcome, Interaction, Review,
Diagrams, Active rulings, Visible children, Read next, and Details. Scalar
values are limited to 240 characters; at most eight active rulings and twenty
visible children are printed, followed by a visible omission marker. Missing
fields print `not recorded` or `none`; a stale State is labelled stale. Read
the full journal whenever detail is omitted or the current stage requires it.

Diagrams is computed from `[diagrams]` as `.agentic/steps/diagrams.md` defines
it, so design needs no configuration reading of its own: `none (disabled)`,
`none (no known types configured)`, or the types to draw for a substantive
design. Read next names the current step file, then the State `must_read`
paths. While the State waits on the user, it also names the `advance` that
moves the journal on when they continue to the next stage, or that closes the
task from validate; it names the step and infers no approval.

Context lists `.agentic/context/project.md` and `.agentic/context/environment.md`
as `present` or `not recorded`. It reads no context bodies and creates nothing.
Presence establishes neither completeness nor accuracy: open the project profile
and relevant environment sections, then follow the selected authoritative links.

Use `brief` first for re-entry, then read what Read next names. Use `summary`
when you need the latest recorded snapshot; use the full journal for durable
history and evidence.

## `components`

```text
python .agentic/aegis.py components
```

**Description:** Read `.agentic/knowledge/*.md` titles and print one
tab-separated bounded printable title and lexical repository-relative page
path per component, ordered by path. The first level-one heading is the title;
a headingless page uses its filename stem so it remains discoverable. Body
sections are not parsed. A link that resolves outside the knowledge directory,
a resolution loop, or a non-printable catalogue path is rejected without
partial output. An empty catalogue prints
`no component knowledge pages`. The command writes nothing and accepts no
arguments.

**When to use:** Before selecting component knowledge during frame, specify,
or design; when build or validation reveals an additional component; and when
adoption needs an inventory of pages already present. The list helps choose a
page but does not infer ownership or replace its Routing section, exact source,
or focused tests.

**Example:**

```text
python .agentic/aegis.py components
```

## Coordinated workflow records

Journals carry append-only Rulings, written by `ruling`, and one replaceable
`## State` block, written by `advance`, `pause` and `verdict`. Older journals
and configs remain valid without migration.

```text
- RULING-001 | date=2026-08-31 | decision=<decision> | reason=<reason> | source=user | supersedes=none
```

`source` is `user`, `repository`, `requirement`, or `technical`; a later
record supersedes an earlier one by ID instead of rewriting history. A ruling
records authority already granted and cannot expand user or Git authority.

Stage interaction defaults are configured independently of publication
authority:

```toml
[interaction]
autopilot = false
```

`autopilot` must be a TOML Boolean. Missing or invalid values mean `false`:
checkpoint mode stops after every stage and presents the next choices.
`true` flows between stages through validate; decision-blocking questions
still stop it, and AEGIS never commits or publishes in either mode. New tasks
copy the resolved value into their `interaction: checkpoint|autopilot` header
so the mode survives resume. An explicit user instruction may override the
configured default for that task.

Explicit review is configured independently of mandatory validation:

```toml
[review]
enabled = false
max_fix_cycles = 2
```

`enabled` must be a TOML Boolean. `max_fix_cycles` must be an integer from 0
through 255, not a Boolean. Invalid values warn and fail safe: an invalid
`enabled` disables review, and an invalid `max_fix_cycles` allows no fix cycle.
When enabled, `verdict` records `spec_compliance` and
`implementation_quality` independently as `approved` or `changes_required`,
plus `review_round`, in the State. Both verdicts cover the same candidate; any
candidate edit invalidates both. The maximum total rounds are
`1 + max_fix_cycles`; at exhaustion the task pauses as `blocked` for the user.
Review disabled skips only these optional verdicts and their fix loop; semantic
review, full validation, the strict check and evidence stay part of validate.

Design diagrams are optional and off by default:

```toml
[diagrams]
enabled = false
types = ["structure"]
```

`enabled` must be a TOML Boolean; missing or invalid values mean `false`, and no
stage draws a diagram. With `true`, design ends by drawing Mermaid diagrams of
the proposed implementation into `.agentic/tasks/diagram_TASK-<id>.md`, as
described in `.agentic/steps/diagrams.md`. `types` lists any of `structure`,
`sequence` and `state`; a missing or non-list value means `["structure"]`, and a
list with no known name draws nothing. `check` warns when
`enabled` is not a Boolean, `types` is not a list, or a type name is unknown.
No stage, review or check finding depends on a diagram.

Fingerprint sidecars are local evidence by default:

```toml
[records]
commit_fingerprints = false
```

`commit_fingerprints` must be a TOML Boolean; missing or invalid values mean
`false`. With `false`, `init` maintains a marked block in the root
`.gitignore` that excludes `.agentic/tasks/*.anchor.json` and
`*.evolution.json`, so anchor and evolution records stay on the machine that
recorded them while the journal log line remains the durable record. With
`true`, `init` removes that block and the sidecars are committed with the
journal. `check` reports `fingerprints-tracked` when the repository disagrees
with the setting: sidecars still tracked while it is `false`, or the block
still present while it is `true`. AEGIS never untracks a file; `init` prints
the `git rm --cached` command for a human to run.

Current-state pages have a size budget:

```toml
[context]
page_kb = 24
```

`page_kb` applies to `.agentic/context/project.md`, `environment.md` and each
knowledge page. These pages are read at every frame, so a page that grows by a
section per task costs every later task. `check` reports a page above the
budget as `context-size` and a level-two heading written twice in one page as
`duplicate-heading`; both are warnings, never refusals. `init` writes 24. A
missing value or `0` means no budget; a negative or non-integer value warns
and also means no budget.

## `check`

```text
python .agentic/aegis.py check [--task TASK-<id>] [--strict] [--run] [--dry-run]
                               [--full] [--json]
```

**Description:** Run the advisory check catalog over requirements, journals,
configuration, and the Git diff against the resolved default branch. Findings
are `ERROR`, `WARN`, or `NOTE`.

Without `--strict`, findings do not block work and the command exits zero.
Read them and correct real issues or record why a finding does not apply.

Set optional `[layout] docs` globs for documentation outside source/tests,
for example `docs = ["docs/", "README.md", "CHANGELOG.md"]`. These paths
remain in secret scanning and the diff; they do not count as source, tests,
or stage write zones. Existing source/tests matches still apply if globs
overlap. The default empty list preserves existing layout checks.
A legacy journal held at `deliver` with unticked checklist items still warns;
a pause is not evidence that its items are complete.

Options:

| Option | Effect |
|---|---|
| `--task TASK-<id>` | Scope diff-based checks to the named task. |
| `--strict` | Exit 1 for errors, failed `--run` commands, and warnings promoted in `.agentic/aegis.toml`; also implies `--full`. |
| `--run` | Also execute eligible `[commands]` entries from `.agentic/aegis.toml`. |
| `--dry-run` | List what `--run` would execute, with each command's limit, and run none of it. |
| `--full` | Print every finding instead of capping human-readable output at 40. |
| `--json` | Emit one complete schema-versioned JSON document on stdout; `--run` progress goes to stderr. |

**When to use:**

- use plain `check` during specification, design, and build for inexpensive
  feedback;
- use `--task` when a shared branch contains unrelated changes;
- use `--dry-run` before committing to `--run` when you need to know what
  the proof costs - it reports the commands and their limits without
  starting any of them, and is never itself evidence;
- use `--strict --run` after the final candidate is stable or in CI;
- `uncovered-source` runs only with `--task`: changes made outside AEGIS need
  no requirement, so the whole-branch diff says nothing about coverage;
- use `--json` only when a script needs structured results.

**Examples:**

```text
python .agentic/aegis.py check
python .agentic/aegis.py check --task TASK-8b12
python .agentic/aegis.py check --dry-run
python .agentic/aegis.py check --task TASK-8b12 --strict --run
python .agentic/aegis.py check --strict --full
python .agentic/aegis.py check --json
```

`--run` proves only the commands it actually executes. Read the printed
`run:` lines, especially when `[check] run` restricts the configured
command set.

## `test`

```text
python .agentic/aegis.py test [name] [--impacted] [--no-fallback] [--dry-run] [--base <rev>] [--task TASK-<id>]
```

**Description:** Run a command from the `[commands]` table in
`.agentic/aegis.toml`. The default command name is `test`. Output streams
live, and the AEGIS process returns the executed command's exit code.

Options:

| Argument or option | Effect |
|---|---|
| `name` | Run that configured command, for example `test` or `lint`. |
| `--impacted` | For the default `test` command, substitute linked impacted tests into the configured `test_impacted` template. |
| `--no-fallback` | With `--impacted`, exit 1 without running or recording test evidence when selection is unavailable. |
| `--dry-run` | Preview the command and working directory without execution or journal writes; exit zero is not test proof. |
| `--base <rev>` | Take the diff against that revision instead of the merge base. `--base HEAD` selects only uncommitted work. |
| `--task TASK-<id>` | Validate the task ID before running and append the result and duration to its journal. |

If impact selection cannot produce a focused set, AEGIS explains why
and falls back to the full `test` command unless `--no-fallback` was requested.
`--no-fallback` requires `--impacted`. `--impacted` cannot be combined
with a command name other than `test`.

Without `--base`, the diff runs from the merge base with the default branch,
so everything the branch has changed since it forked counts. That is the
right basis for reviewing a branch and the wrong one for an edit-run loop on
a long-lived branch, where it can select most of the suite. Use `--base HEAD`
during build to select only what you have not committed yet.

Unsupported selector suffixes, including test names containing spaces or quotes,
are discarded in favor of their validated test file. Unsafe or repository-escaping
file paths are never interpolated. Multiple references to a broadened file become
one file argument. AEGIS supplies references; the configured runner must honor
both file and exact-selector input. It does not translate between test frameworks.
Paths with spaces still require a project-native command rather than interpolation.

A focused set that would make the command longer than the platform can launch
is not an error: AEGIS reduces it to one entry per distinct test file,
says so, and only falls back to the full suite if even that is too long.

**When to use:**

- use a focused project-native command, or `test --impacted --base HEAD --no-fallback`, during build;
- use `check --task TASK-<id> --strict --run` once after final edits and review; do not precede it with another full `test`;
- use `test <name>` for other configured read-only checks such as linting.

**Examples:**

```text
python .agentic/aegis.py test
python .agentic/aegis.py test --impacted
python .agentic/aegis.py test --impacted --base HEAD
python .agentic/aegis.py test --impacted --task TASK-8b12
python .agentic/aegis.py test lint
```

Example configuration:

```toml
[commands]
test = "python -m pytest -q"
test_impacted = "python -m pytest -q {tests}"
lint = "python -m ruff check ."
```

When the application lives below the repository root, set `workdir` rather
than putting a directory change inside the commands:

```toml
[commands]
workdir = "app"
test = "python -m pytest -q"
test_impacted = "python -m pytest -q {tests}"
```

Every configured command then runs in `app/`, and the repository-relative
paths stored in `linked_tests` are rewritten to match before substitution. A
command that changes directory itself would instead resolve those paths a
second time, against the directory it just moved into, and find nothing.
`workdir` and `timeout` configure how commands run and are never executed as
commands themselves.

### Time limits

Nothing is limited by default. A limit low enough to stop a suite the
repository considers healthy would report a failure that never happened, so a
command runs until it finishes unless you ask for a limit:

```toml
[commands]
test = "python -m pytest -q"
lint = "python -m ruff check ."
timeout = 0          # the shared default; 0 or absent means no limit

[timeouts]
test = 5400          # this command only, overriding the shared default
lint = 120
```

`[timeouts] <name>` wins over `[commands] timeout`, so a suite measured in
tens of minutes and a linter measured in seconds no longer have to share one
number. Zero, negative, and unreadable values all mean no limit.

A command stopped by its limit is reported as `command-timeout`, separately
from `command-failed`, and its message says that nothing was proven. Both are
errors, because an unfinished proof is not a proof — but a report must never
suggest that a suite ran and was judged when it was cut off instead.

Command strings are executed by the platform shell. Keep them repository-owned
and review configuration changes like code.

## `report`

```text
python .agentic/aegis.py report <TASK-id|id>
```

**Description:** Append a dated delivery report to a task journal. The report
records the journal state, linked requirement titles, diff size, check counts,
checklist completion, configured review policy, and bound current verdicts.
Missing, malformed, or stale verdict evidence is never converted to approval.
Repeated runs append new reports; they do not replace
history.

**When to use:** At the end of validate, once the evidence is final and before
`advance` to `done`. The developer reads it before committing; it is a
snapshot, so rerun it if the candidate or checklist changes.

The diff is measured from the commit the journal's `base:` header records —
the commit that was checked out when the task was created — and the report
names that basis, for example `diff vs task base 41e9f55`. A journal without
that header falls back to the merge base with the default branch and says
`diff vs merge base`, which on a branch carrying earlier work counts that work
as this task's own. `check --task` uses the same basis, so the two agree.
Leave `base:` alone once it is written; changing it changes what every later
report claims the task did.

**Examples:**

```text
python .agentic/aegis.py report TASK-8b12
python .agentic/aegis.py report 8b12
```

## `diagram`

```text
python .agentic/aegis.py diagram [--component NAME] [--task TASK-id] [--out PATH]
```

**Description:** Draw the requirement register as a Mermaid flowchart. Each
requirement becomes a node grouped under the component whose knowledge page
lists it in `## Key behaviors`, colored by the outcome `check` reaches for
that same record:

| Class | An active requirement where | `check` reports |
|---|---|---|
| `tested` | every entry in `linked_tests` resolves to a file | nothing |
| `manual` | nothing is linked and `verification` names a `Manual:` or `Inspection:` method | NOTE `manual-verification` |
| `broken` | something is linked but at least one entry does not resolve | WARN `no-linked-tests` |
| `uncovered` | nothing is linked and no method is named | WARN `no-linked-tests` |
| `draft` | — the requirement is still `status = "draft"` | nothing |
| `retired` | — the behavior was withdrawn | nothing |

`broken` outranks `manual`: a record that claims a test which is not there is
making a claim, and the claim is the finding. `draft` and `retired` are the
two `check` is deliberately silent about, and they are drawn apart from
`uncovered` so a behavior nobody has written yet is not read as one nobody
verifies. Requirements no page claims are grouped last under
`(no knowledge page)` rather than dropped.

Everything in the drawing is read from files already in the repository, so
the command needs no model, no network, and no renderer — the output is text
that Git diffs and that Markdown viewers draw for themselves. It writes no
repository state.

**When to use:** In review, when handing a component to someone else, or
whenever the question is where verification is thin rather than what one
requirement says. `check` remains the authority on findings; this is the same
data arranged to be looked at, and every class above maps onto one of its
outcomes rather than reaching a second opinion.

**Options:**

| Option | Effect |
|---|---|
| `--component NAME` | Restrict to one knowledge page, named by file stem or by heading. |
| `--task TASK-id` | Restrict to the requirements listed in that journal's header. |
| `--out PATH` | Write the diagram to a file as UTF-8, creating parent folders, instead of printing it. |

A whole-register diagram stops being readable somewhere past a few dozen
requirements. Narrow it before that point rather than after. An unknown
component or task is an error, not an empty diagram.

`--out` exists because printing is not portable: a console under a legacy
code page mangles the characters on the way out, and a diagram that renders
differently per platform is not a durable artifact. Redirecting stdout to a
file inherits the same problem; `--out` does not.

**Examples:**

```text
python .agentic/aegis.py diagram
python .agentic/aegis.py diagram --component core-cli-lifecycle
python .agentic/aegis.py diagram --task TASK-8b12
python .agentic/aegis.py diagram --out docs/coverage.mmd
```

## `trace`

```text
python .agentic/aegis.py trace [--format {md,csv}] [--out PATH]
```

**Description:** Export the whole requirement register as a flat traceability
matrix — one row per requirement, whatever its status. Each row carries the
identifier, category, status, coverage class, claiming component, title,
statement, verification method, spec reference, and the complete linked-test
and affected-path lists with their counts.

The coverage class is the same verdict `check` and `diagram` reach for that
record, read from the one shared classifier rather than derived again.

Rows are ordered by category — in the order the `req` table above lists them —
and then by identifier, so two runs over unchanged files produce identical
bytes. Nothing is truncated in either format: `summary` and `brief` bound
their output because they are resume views for a context-limited reader, while
this is a durable artifact whose point is completeness.

A requirement file that does not parse is named on stderr and left out of the
table rather than dropped in silence, and the Markdown summary counts it. The
exit status stays 0; `check` is the authority on findings and already reports
that file as a `req-parse` error.

Readable files with validation errors remain listed; their warnings are
separate from omitted-file counts. Category is the first folder below
`requirements/`, including for nested files; a file directly in that root is
marked `(no category)`. An unreadable knowledge page is warned about without
discarding requirement rows, and otherwise unclaimed rows are marked
`(knowledge incomplete)` because ownership could not be fully determined.

| Option | Effect |
|---|---|
| `--format md` | A Markdown table under separate coverage and category summary paragraphs. Escapes literal text, including pipes and markup; flattens whitespace within each list entry, then joins entries with `<br>`. Files use UTF-8. |
| `--format csv` | Header row and data only. Standard CSV quoting; joins list columns with `; `. Files use UTF-8 with a byte-order mark. |
| `--out PATH` | Write to a file, creating parent folders, instead of printing. The suffix does not select the format; use `--format csv` for CSV. |

The CSV header names are the requirement TOML keys, so the file is
self-describing against the records it came from. The Markdown headers are
human labels, because that is the copy a reviewer or an assessor reads.

CSV preserves field values without formula neutralization. A spreadsheet may
interpret text beginning with `=`, `+`, `-` or `@` as a formula; import the CSV
with columns treated as text when reviewing untrusted records. The BOM controls
encoding, not cell interpretation. Joined lists are display values, not a
reversible list encoding: an entry containing `; ` is indistinguishable from
that separator. Counts describe the source entries, not a split on `; `.

`--format csv --out` writes a byte-order mark because that is what stops a
spreadsheet application guessing the system code page; the register already
holds characters that guess wrongly. As with `diagram`, `--out` exists because
printing is not portable — a console under a legacy code page mangles the
characters on the way out, and redirecting stdout to a file inherits the same
problem.

**When to use:** In an audit, a review, or a handover, when someone needs the
whole register outside the repository — the third reader of the same data.
`diagram` groups it into a picture that stops being legible past a few dozen
requirements, `explain` answers about one path, and this narrows nothing.

**Examples:**

```text
python .agentic/aegis.py trace
python .agentic/aegis.py trace --format csv
python .agentic/aegis.py trace --out docs/traceability-matrix.md
python .agentic/aegis.py trace --format csv --out docs/traceability-matrix.csv
```

## `explain`

```text
python .agentic/aegis.py explain <path>
```

**Description:** Report what governs one repository path. Lists every
requirement whose `affected_paths` cover it — a directory entry covers the
files beneath it, and a glob is matched case-sensitively so Windows and Linux
agree — grouped under the component whose knowledge page claims each
requirement, with its status, how it is verified, and its spec where it has
one. Then the task journals whose `requirements:` header lists any of them.

The path may be repo-relative or absolute, with native or forward separators.
A path no requirement covers is reported plainly. Code that only direct
changes touched, outside AEGIS, has no requirement, and that is not a defect.

**When to use:** Reading unfamiliar code and asking "why is this here, and
what am I allowed to change?". It is the register read backwards: `req` and
`check` write the traceability, this is how a human spends it.

**Examples:**

```text
python .agentic/aegis.py explain src/export/m3u.py
python .agentic/aegis.py explain src/export/
python .agentic/aegis.py explain C:\repo\src\export\m3u.py
```

## Exit behavior and machine-readable output

| Situation | Exit behavior |
|---|---|
| `init`, `task`, `advance`, `pause`, `log`, `ruling`, `verdict`, `req`, `anchor`, `evolution`, `status`, `summary`, `brief`, `components`, `report`, `diagram`, `trace`, or `explain` succeeds | Exit 0. |
| Missing task, invalid configuration, or another expected CLI error | One error line on stderr and exit 1. |
| Unknown command, option or argument value | The usage text on stderr and exit 2. |
| Plain `check` finds errors or warnings | Exit 0; it remains advisory. |
| `check --strict` finds a strict failure | Exit 1. |
| `test` runs a configured command | Return that command's exit code. |
| A configured command is stopped by its time limit | Exit 124, reported as proving nothing. |

For `anchor --json`, `evolution --json`, `check --json`, and `status --json`,
successful stdout contains exactly one JSON document with a `schema` integer.
On a usage or configuration error, stdout is empty and the error is written to
stderr; consumers must treat empty stdout as failure, not as an empty result.

## Commands intentionally not provided

AEGIS has no command for approvals, waivers, evidence forms, commits, pushes,
merges, tickets, upgrades, or uninstalling. `advance` records a transition the
agent decided on; it does not approve it. The other actions remain visible
plain-file or Git operations:

- upgrade by copying the newer payload, running `init`, and reviewing the
  diff;
- uninstall by removing the payload and its managed root pointer blocks;
- commit, push, merge and publish only through the repository's normal Git
  workflow, outside AEGIS.

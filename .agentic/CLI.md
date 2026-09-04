<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details.
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

The CLI scaffolds artifacts, runs configured project commands, and reports
advisory findings. It does not replace the workflow in
`.agentic/AGENTS.md`, edit task stages for you, commit, push, or access the
network.

## Command summary

| Command | Description | When to use |
|---|---|---|
| `init` | Complete installation after copying the payload. | Once during installation, and safely after a payload upgrade. |
| `task` | Create a task journal with a unique ID. | At the start of governed feature, fix, change, or adoption work. |
| `req` | Create a requirement TOML file with a unique ID. | When work needs a new durable requirement. |
| `anchor` | Fingerprint Git-visible repository files for a task. | After the expected red failure and before implementation. |
| `evolution` | Compare the repository with its active task anchor. | After implementation and after any later validation edit. |
| `status` | List open tasks or inspect one journal. | Before starting or resuming work, and whenever the next step is unclear. |
| `brief` | Print a deterministic bounded resume view from durable files. | First when resuming, especially with a small-context model. |
| `components` | List component knowledge titles and page paths. | Before choosing which component page to read. |
| `check` | Run the heuristic governance catalog. | During work for feedback; with `--strict --run` at the validation or CI boundary. |
| `test` | Run a command configured in `.agentic/aegis.toml`. | During build and validation, optionally recording the result in a journal. |
| `summary` | Print a compact recorded stage snapshot without writes. | Before resuming and after recording a stage completion or pause. |
| `report` | Append a delivery summary to a task journal. | After validation and before the delivery commit or pull request. |
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

- creates `.agentic/requirements/`, `specs/`, `tasks/`, and `knowledge/`
  when absent;
- creates a default `.agentic/aegis.toml` only when absent;
- adds or refreshes the managed AEGIS digest in root
  `AGENTS.md`, `assistant.md`, and `QWEN.md`;
- reports whether Git is installed and whether the directory is a repository;
- preserves project-owned data and an existing `aegis.toml`.

The command is idempotent: running it again does not replace the repository's
configuration or governance records.

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

Afterward, edit `.agentic/aegis.toml` so `[commands]`, `[layout]`, and
optional `[check]` settings describe the repository.

## `task`

```text
python .agentic/aegis.py task "<title>" [--type {feature,fix,change,adopt}] [--parent TASK-<id>]
```

**Description:** Create `.agentic/tasks/TASK-<id>.md` from the task
template. The journal receives a collision-resistant ID, the current date,
the current Git branch when available, and `stage: frame`. The new path is
printed on stdout.

The default type is `feature`. Accepted types are:

| Type | Use for |
|---|---|
| `feature` | New user-visible or system capability. |
| `fix` | Correction of confirmed faulty behavior. |
| `change` | Maintenance or behavior change that is not best described as a feature or fix. |
| `adopt` | Bringing an existing repository under AEGIS. |

**When to use:** At the beginning of a new governed unit of work, after first
using `status` to ensure an existing open journal does not already cover it.

**Examples:**

```text
python .agentic/aegis.py task "Export audit report" --type feature
python .agentic/aegis.py task "Handle empty configuration" --type fix
python .agentic/aegis.py task "Adopt inventory service" --type adopt
```

The CLI creates the journal but does not advance its stage. Follow the
relevant step file and edit the journal as instructed.

`--parent` is optional and creates only the child-side `parent:` link. The
named parent must exist and must itself be top-level; nested children are
rejected. The parent journal is never edited. Each child keeps its own branch,
base, requirements, stages, validation, and delivery checkpoint. Reverse
lookup scans journals visible in the current checkout only, so it cannot claim
knowledge of children that exist solely on another branch. The parent owns
validation of the integrated candidate.

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
prove that a test or implementation was honest.

## `evolution`

```text
python .agentic/aegis.py evolution --task TASK-<id> [--json]
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
`status` output and JSON are unchanged; `report` remains the journal-writing
delivery command. Use `summary` after updating a stage report; use `brief` first
when resuming.

The journal may contain one optional `## Stage report` section with plain
one-line fields (no bullets or code fences inside the actual section):

```text
stage: specify
result: completed
current: design
changed: requirements created; IDs are on the journal header
evidence: check exit 0; tests not run at this stage
issues: none recorded
next: follow 3_design.md
needs_user: no
```

`stage` is the reported stage; `current` must equal the journal header after
any transition. Use canonical ordinary/adoption stages, not display aliases.
`result` accepts `in_progress`, `completed`, `paused`, `blocked`, or `skipped`.
The other fields contain the agent's recorded observations and decisions;
blank values print `not recorded`. Keep evidence and decisions in the
append-only log as well; replace only this latest-view section.

Output fields, in order: **Stage, Task, Current, Requirements, Changed,
Evidence, Issues, Next, Needs user, Spec compliance, Implementation quality,
Review round, Details**. Stage combines the reported
stage and result; Current and Requirements come from the journal header.
Details points to the full journal. Each value is at most 240 characters,
including a visible `[truncated; read journal]` marker for omitted detail.
If any value is shortened, Needs user directs full-journal review before
proceeding, even if the record said no. This is a character bound, not a
model-specific token guarantee.

Missing records and incomplete or mismatched stage bindings suppress recorded
outcomes and next-action claims and direct journal review. Unknown stages or
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
from the task journal, visible task journals, and `.agentic/aegis.toml`. It
does not call Git, run commands, write files, advance stages, or infer approval.
Two calls against unchanged files are byte-identical.

The fixed output order is: `AEGIS brief`, Task, Stage, Branch/base, Parent,
Requirements, Checklist, Stage report, Review, Active rulings, Handoff,
Visible children, and Details. Scalar values are limited to 240 characters;
at most eight active rulings and twenty visible children are printed, followed
by a visible omission marker. Missing legacy fields print `not recorded` or
`none`; stale stage-report or handoff bindings are labelled stale. Read the
full journal whenever detail is omitted or the current stage requires it.

Use `brief` first for re-entry, then read the current step file and the
handoff's `must_read` paths. Use `summary` when you need the latest bound stage
report projection; use the full journal for durable history and evidence.

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

New journals include these compatible optional records. Older journals and
configs remain valid without migration.

```text
- RULING-001 | date=2026-08-31 | decision=<decision> | reason=<reason> | source=user | supersedes=none

current: validate
next: run the final candidate proof
must_read: .agentic/steps/5_validate.md; tests/latest.txt
blockers: none
status: ready
```

Rulings are append-only. `source` is `user`, `repository`, `requirement`, or
`technical`; a later record supersedes an earlier one by ID instead of rewriting history. A ruling
records authority already granted and cannot expand user or Git authority.
The single `## Handoff` block is replaceable, stage-bound resume state;
`status` is `ready`, `waiting`, or `blocked` and must be refreshed at every
transition, pause, blocker, or session end.

Explicit review is configured independently of mandatory validation:

```toml
[review]
enabled = false
max_fix_cycles = 2
```

`enabled` must be a TOML Boolean. `max_fix_cycles` must be an integer from 0
through 5, not a Boolean. Invalid values warn and fail safe to disabled review
with the default bound. When enabled, the bound stage report records
`spec_compliance` and `implementation_quality` independently as `approved` or
`changes_required`, plus `review_round`. Both verdicts cover the same
candidate; any candidate edit invalidates both. The maximum total rounds are
`1 + max_fix_cycles`. Exhaustion blocks delivery with `needs_user: yes`.
Review disabled skips only these optional verdicts and their fix loop; semantic
review, full validation, the strict check, evidence, and delivery approval stay
mandatory.

## `check`

```text
python .agentic/aegis.py check [--task TASK-<id>] [--strict] [--run] [--full] [--json]
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
An unticked delivery checklist remains a warning even when delivery is
intentionally on hold; a pause is not evidence that its items are complete.

Options:

| Option | Effect |
|---|---|
| `--task TASK-<id>` | Scope diff-based checks to the named task. |
| `--strict` | Exit 1 for errors, failed `--run` commands, and warnings promoted in `aegis.toml`; also implies `--full`. |
| `--run` | Also execute eligible `[commands]` entries from `aegis.toml`. |
| `--full` | Print every finding instead of capping human-readable output at 40. |
| `--json` | Emit one complete schema-versioned JSON document on stdout; `--run` progress goes to stderr. |

**When to use:**

- use plain `check` during specification, design, and build for inexpensive
  feedback;
- use `--task` when a shared branch contains unrelated changes;
- use `--strict --run` after the final candidate is stable or in CI;
- use `--json` only when a script needs structured results.

**Examples:**

```text
python .agentic/aegis.py check
python .agentic/aegis.py check --task TASK-8b12
python .agentic/aegis.py check --task TASK-8b12 --strict --run
python .agentic/aegis.py check --strict --full
python .agentic/aegis.py check --json
```

`--run` proves only the commands it actually executes. Read the printed
`run:` lines, especially when `[check] run` restricts the configured
command set.

## `test`

```text
python .agentic/aegis.py test [name] [--impacted] [--base <rev>] [--task TASK-<id>]
```

**Description:** Run a command from the `[commands]` table in
`.agentic/aegis.toml`. The default command name is `test`. Output streams
live, and the AEGIS process returns the executed command's exit code.

Options:

| Argument or option | Effect |
|---|---|
| `name` | Run that configured command, for example `test` or `lint`. |
| `--impacted` | For the default `test` command, substitute linked impacted tests into the configured `test_impacted` template. |
| `--base <rev>` | Take the diff against that revision instead of the merge base. `--base HEAD` selects only uncommitted work. |
| `--task TASK-<id>` | Validate the task ID before running and append the result and duration to its journal. |

If impact selection cannot produce a focused set, AEGIS explains why
and falls back to the full `test` command. `--impacted` cannot be combined
with a command name other than `test`.

Without `--base`, the diff runs from the merge base with the default branch,
so everything the branch has changed since it forked counts. That is the
right basis for reviewing a branch and the wrong one for an edit-run loop on
a long-lived branch, where it can select most of the suite. Use `--base HEAD`
during build to select only what you have not committed yet.

A focused set that would make the command longer than the platform can launch
is not an error: AEGIS reduces it to one entry per distinct test file,
says so, and only falls back to the full suite if even that is too long.

**When to use:**

- use `test --impacted --base HEAD --task ...` for a fast build-loop regression;
- use `test --task ...` for the configured full suite during validation;
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

**When to use:** In the delivery stage after validation evidence is final and
before committing or opening the pull request. Read the appended report before
delivery; it is a snapshot, so rerun it if the candidate or checklist changes.

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
A path no requirement covers is reported plainly, and said to be a finding
when it sits inside the configured `source` or `tests` globs — ungoverned
code in a governed area is worth knowing about.

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
| `init`, `task`, `req`, `anchor`, `evolution`, `status`, `summary`, `brief`, `components`, `report`, `diagram`, `trace`, or `explain` succeeds | Exit 0. |
| Usage, missing task, invalid configuration, or another expected CLI error | One error line on stderr and exit 1. |
| Plain `check` finds errors or warnings | Exit 0; it remains advisory. |
| `check --strict` finds a strict failure | Exit 1. |
| `test` runs a configured command | Return that command's exit code. |
| A configured command is stopped by its time limit | Exit 124, reported as proving nothing. |

For `anchor --json`, `evolution --json`, `check --json`, and `status --json`,
successful stdout contains exactly one JSON document with a `schema` integer.
On a usage or configuration error, stdout is empty and the error is written to
stderr; consumers must treat empty stdout as failure, not as an empty result.

## Commands intentionally not provided

AEGIS has no command for stage transitions, approvals, waivers, evidence
forms, commits, pushes, upgrades, or uninstalling. Those actions remain visible
plain-file or Git operations:

- edit the task journal to advance a stage according to its step file;
- upgrade by copying the newer payload, running `init`, and reviewing the
  diff;
- uninstall by removing the payload and its managed root pointer blocks;
- commit and publish only through the repository's normal Git workflow.

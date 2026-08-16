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
| `check` | Run the heuristic governance catalog. | During work for feedback; with `--strict --run` at the validation or CI boundary. |
| `test` | Run a command configured in `.agentic/aegis.toml`. | During build and validation, optionally recording the result in a journal. |
| `report` | Append a delivery summary to a task journal. | After validation and before the delivery commit or pull request. |

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
python .agentic/aegis.py task "<title>" [--type {feature,fix,change,adopt}]
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

## `check`

```text
python .agentic/aegis.py check [--task TASK-<id>] [--strict] [--run] [--full] [--json]
```

**Description:** Run the advisory check catalog over requirements, journals,
configuration, and the Git diff against the resolved default branch. Findings
are `ERROR`, `WARN`, or `NOTE`.

Without `--strict`, findings do not block work and the command exits zero.
Read them and correct real issues or record why a finding does not apply.

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
and checklist completion. Repeated runs append new reports; they do not replace
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

## Exit behavior and machine-readable output

| Situation | Exit behavior |
|---|---|
| `init`, `task`, `req`, `anchor`, `evolution`, `status`, or `report` succeeds | Exit 0. |
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

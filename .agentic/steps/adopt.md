<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Adopt an existing repository

**Purpose:** Bring a repository that already has code under this workflow,
component by component, by describing what is there — not by rewriting it.
Three phases: survey, one component per session, close.

**Read first:**

- The repo's own README and any existing design or architecture docs.
- The top-level directory tree, the entry points, and the test layout.
- `.agentic/templates/component.md` and `.agentic/templates/requirement.toml`.
- The adoption journal, if a previous session already created one.

**Stage report (completion or pause):** After updating the log, header and
checklist, refresh the single `## Stage report` section in this task journal:
`stage`, `result`, `current`, `changed`, `evidence`, `issues`, `next`,
`needs_user` (plain one-line fields, no fences). Record the completed stage
separately from `current`, which must match the header after any transition;
use `paused` when waiting or ending a session. Other results are `in_progress`,
`completed`, `blocked`, `skipped`. Run
`python .agentic/aegis.py summary TASK-<id>` and copy its block before any
detailed explanation. Unknown values stay blank (`not recorded`); refresh
stale records and read omitted details before continuing. Preserve existing
approval stops and immediate deviation notices; this report adds no new stop.

**Resume context:** Read the summary first, then this stage's instructions,
the journal header/checklist and relevant log entries (scope, user limits,
unresolved issues, decisions and evidence); follow links to needed records.
This stage's required full reads still apply. Use linked requirements and
source as needed, not the whole register. Do not act on missing, stale, or
shortened reporting without reviewing the full journal information.

**Steps:**

Adoption has its own durable stage values so any later session can see
exactly where it stands: `stage: survey` → `stage: components` →
`stage: close` → `stage: done`. The `## Components` checklist plus the
`stage:` line are the complete resume state.

*Phase 1 — survey (one session).*

1. Run `python .agentic/aegis.py init`. If you are on the repo's default
   branch, create an adoption branch first (`git checkout -b adopt/<repo>`
   or the repo's own convention). Then open an adoption journal:
   `python .agentic/aegis.py task "Adopt <repo>" --type adopt`, and
   set `stage: survey` in its header.
2. Propose a component breakdown heuristically: directory structure,
   entry points, import clusters, existing docs, test file grouping. Aim
   for components a single session can read end to end.
3. Write the breakdown into the journal as `## Components`, one checklist
   item per component with a one-line scope and its file globs.
4. **Stop and hand the list to the owner.** They review and edit it —
   splitting, merging, renaming, dropping. This is the alignment moment
   of adoption; nothing else happens until the list is agreed. Record
   their edits in the log, then set `stage: components`.

*Phase 2 — one component per session.*

To parallelize across people or branches, split the work into one
adoption journal per person (each `--type adopt`, each owning a subset of
the components) — a single shared journal is a merge hotspot, separate
ones are not.

5. Take the first unticked component. Read its source **and its existing
   tests** — the tests are the primary evidence of intended behavior.
6. Write `.agentic/knowledge/<component>.md` from the template: purpose,
   public interface, key behaviors, architecture, files.
7. Draw the component's `## Architecture` diagram while its source is still
   in front of you — this session is the cheapest this drawing will ever
   be. Draw what the code does, not what it should do: an odd shape you
   cannot explain is a finding for the log, not something to tidy away in
   the picture. Where you cannot tell which way a dependency points, leave
   the arrow out and say so underneath rather than guessing.
8. Derive requirements from the behavior you found: `status = "active"`,
   `affected_paths` = the component's files, `linked_tests` = the
   existing tests that already verify each behavior. Adoption mostly
   *links* tests; it does not write them.
9. Add a spec only where a requirement alone would not be buildable.
10. Real behavior with no test: write a characterization test now if the
    behavior is load-bearing; otherwise leave `linked_tests` empty. `check`
    will flag it on every run — that standing list is the post-adoption
    test backlog, and it is meant to stay visible. A behavior no test
    could ever settle is different: start its `verification` with
    `Manual:` or `Inspection:` and name the method, and it is recorded as
    verified by hand instead of joining that backlog. Keep the two apart
    honestly — a test you have not written yet is not a manual method.
11. Behavior that looks *wrong*: still write the requirement — the
    register must describe what the code actually does — but say so
    plainly in its prose (`Adopted as-is <date>; suspected defect: <what
    looks wrong>`) and log it as a future task. What is forbidden is
    canonizing it *silently* as if intended, and fixing it during
    adoption; the fix is a separate task with its own journal.
12. Tick the component off, commit, and end the session. The next session
    resumes from the checklist.

*Phase 3 — close.*

13. When the last component is ticked, set `stage: close`. Run
    `python .agentic/aegis.py check` over the whole tree and fix-forward
    what it reports.
14. Run `python .agentic/aegis.py report TASK-<id>`, tick the checklist
    except the close-out item, **commit** — journal and report inside the
    adoption commit — and open the PR.
15. **Close out only after the outcome succeeded**: set `stage: done`,
    tick the close-out item, and make a small close-out commit on the
    same branch, pushed with it. If the outcome failed — or there is no
    remote, so the commit *is* the outcome, which is fine — log what
    actually happened; leave `stage: close` whenever the agreed outcome
    was not delivered, so the journal stays truthful in `status`.

**Outputs:**

- One adoption journal with the owner-agreed component checklist.
- `.agentic/knowledge/<component>.md` per adopted component.
- Requirement files, and specs only where needed.
- A log of untested behaviors and suspect behaviors, as the backlog.

**Done when:**

- [ ] component breakdown proposed and reviewed by the owner
- [ ] every agreed component has a knowledge page
- [ ] every knowledge page carries an `## Architecture` diagram of what the
      code does now
- [ ] every component's behaviors are covered by requirements
- [ ] `linked_tests` point at the existing tests that verify them
- [ ] untested and suspect behaviors logged as backlog, not hidden
- [ ] suspect behaviors adopted as-is, marked as suspected in their
      requirement prose, and logged as future tasks
- [ ] `check` reports no errors over the whole tree
- [ ] report generated; journal and report inside the adoption commit;
      agreed outcome delivered (PR where there is a remote)
- [ ] close-out: `stage: done` set and committed only after that

**Skip when:** The repo is already adopted — go straight to `1_frame.md`.
Partial adoption is normal and expected: adopt only the components you
actively work on, and let `check` warn you when a task touches an
un-adopted area.

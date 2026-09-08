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
- `python .agentic/aegis.py components` to inventory component pages already
  present before proposing or resuming the adoption checklist.
- `.agentic/templates/component.md` and `.agentic/templates/requirement.toml`.
- The adoption journal, if a previous session already created one.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

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
   for components a single session can read end to end. Compare it with the
   `python .agentic/aegis.py components` inventory so an existing page is
   reused or deliberately reconciled rather than duplicated.
3. Write the breakdown into the journal as `## Components`, one checklist
   item per component with a one-line scope and its file globs.
4. **Stop and hand the list to the owner.** They review and edit it —
   splitting, merging, renaming, dropping. This is the alignment moment
   of adoption; nothing else happens until the list is agreed. Record one
   consolidated approval outcome and any material boundary changes in the Log,
   then set `stage: components`.

*Phase 2 — one component per session.*

To parallelize across people or branches, split the work into one
adoption journal per person (each `--type adopt`, each owning a subset of
the components) — a single shared journal is a merge hotspot, separate
ones are not.

5. Take the first unticked component. Read its source **and its existing
   tests** — the tests are the primary evidence of intended behavior.
6. Write `.agentic/knowledge/<component>.md` from the template. Derive
   `## Routing`, `## Purpose and boundaries`, `## Public interface`,
   `## Invariants`, `## Key behaviors`, `## Architecture`, and `## Files`
   from the exact source and tests. Add `## Change map` when multiple
   independent edit-and-test seams would otherwise require broad discovery.
   The page is an orientation route; the exact source and tests remain the
   authority for future changes.
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
    looks wrong>`) and include it in one consolidated component finding or
    future-task record in the Log. What is forbidden is
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
- Untested behaviors remain visible through empty `linked_tests` and `check`;
  suspect behaviors remain in requirement prose and consolidated Log findings.

**Done when:**

- [ ] component breakdown proposed and reviewed by the owner
- [ ] every agreed component has a knowledge page
- [ ] every knowledge page routes a request to owned source and focused tests,
      with boundaries and invariants derived from current evidence
- [ ] every knowledge page carries an `## Architecture` diagram of what the
      code does now
- [ ] every component's behaviors are covered by requirements
- [ ] `linked_tests` point at the existing tests that verify them
- [ ] untested behaviors visible through requirement links and `check`, not
      duplicated line by line in the Log
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

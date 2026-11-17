<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Adopt an existing repository

**Purpose:** Bring a repository that already has code under this workflow,
component by component, by describing what is there — not by rewriting it.
Three phases: survey, one component per session, close.

**Read:**

- The repository's own README and any existing design or architecture docs.
- The top-level directory tree, the entry points, and the test layout.
- `python .agentic/aegis.py components`, to inventory the component pages
  already present before proposing or resuming the adoption checklist.
- `.agentic/templates/component.md` and `.agentic/templates/requirement.toml`.
- The adoption journal, if a previous session already created one.
- Existing `.agentic/context/project.md` and `.agentic/context/environment.md`.
  Populate their affected sections during survey from the confirmed purpose,
  implementation, manifests, setup documentation and verification
  configuration. Keep absent or uncertain facts in the journal; empty context
  sections are valid.

**Steps:**

The adoption journal walks `survey` → `components` → `close` → `done`.
`python .agentic/aegis.py advance TASK-<id>` moves it, `pause` records a stop,
and `brief` shows where it stands. The stage, the State and the
`## Components` checklist carry the resume state.

*Phase 1 — survey (one session).*

1. Run `python .agentic/aegis.py init`, then open the journal with
   `python .agentic/aegis.py task "Adopt <repo>" --type adopt` on the current
   branch; it starts at `survey`. Creating an adoption branch is the
   developer's call unless the user asks you to.
2. Propose a component breakdown heuristically: directory structure, entry
   points, import clusters, existing docs, test file grouping. Aim for
   components a single session can read end to end. Compare it with the
   `components` inventory so an existing page is reused or deliberately
   reconciled rather than duplicated.
3. Write the breakdown into the journal as `## Components`, one checklist
   item per component with a one-line scope and its file globs.
4. **Hand the list to the owner**, in both interaction modes:
   `pause TASK-<id> --next "Review the component list: split, merge, rename
   or drop?"`, show the summary and wait. This is adoption's alignment
   moment; nothing else happens until the list is agreed. When it is, log the
   material boundary changes and run `advance TASK-<id>`.

*Phase 2 — one component per session.*

To parallelize across people or branches, give each person their own
adoption journal (each `--type adopt`, each owning a subset of the
components): one shared journal is a merge hotspot, separate ones are not.

5. Take the first unticked component. Read its source **and its existing
   tests**; the tests are the primary evidence of intended behavior.
6. Write `.agentic/knowledge/<component>.md` from the template, leaving out
   the template's license comment and guidance comment. Derive
   `## Routing`, `## Purpose and boundaries`, `## Public interface`,
   `## Invariants`, `## Key behaviors` and `## Files` from the exact source
   and tests. Add `## Change map` when several independent edit-and-test
   seams would otherwise require broad discovery. The page is an orientation
   route; the source and tests stay the authority. Compare existing active
   requirements with the implementation before describing the interface:
   when code disagrees with a normative interface, label the interface as the
   agreed contract and describe the actual behavior separately, with
   source and test evidence. Keep the defect and its investigation in the
   journal; adoption neither fixes it nor changes the contract.
7. Derive requirements from the behavior you found: create each with
   `python .agentic/aegis.py req functional "<title>"` (or another category),
   then set `status = "active"`, `affected_paths` = the component's files and
   `linked_tests` = the existing tests that already verify each behavior.
   Adoption mostly *links* tests; it does not write them.
8. Add a spec only where a requirement alone would not be buildable.
9. Real behavior with no test: write a characterization test now if the
   behavior is load-bearing; otherwise leave `linked_tests` empty. `check`
   flags it on every run, and that standing list is the post-adoption test
   backlog, meant to stay visible. A behavior no test could ever settle is
   different: start its `verification` with `Manual:` or `Inspection:` and
   name the method. A test you have not written yet is not a manual method.
10. Behavior that looks *wrong*: `log` the observed behavior and the
    suspected defect as one consolidated finding with source and test
    evidence. Confirm the intended behavior with the owner before activating
    a requirement for it, and preserve an existing active contract while the
    mismatch is investigated. Requirement prose states only agreed positive
    behavior; the fix is a separate task.
11. Tick the component off, `pause TASK-<id> --next "Continue with
    <next component>?"` and end the session. The next session resumes from
    the checklist.

*Phase 3 — close.*

12. When the last component is ticked, `advance TASK-<id>` to `close` (in
    checkpoint mode, `pause` first and wait for the owner). Run
    `python .agentic/aegis.py check` over the whole tree and fix forward what
    it reports. Reconcile the context and component pages against the
    surveyed checkout: actual responsibilities and setup, stated positively;
    unresolved findings and adoption history stay in the journal.
13. Run `python .agentic/aegis.py report TASK-<id>`, then
    `pause TASK-<id> --next "Close the adoption?"`. When the owner agrees,
    `advance TASK-<id>` to `done`. Committing and opening a pull request
    follow the repository's procedures, outside AEGIS.

**Outputs:**

- One adoption journal with the owner-agreed component checklist.
- `.agentic/knowledge/<component>.md` per adopted component.
- Project and environment context describing confirmed current facts.
- Requirement files, and specs only where needed.
- Untested behaviors visible through empty `linked_tests` and `check`;
  suspect behaviors in consolidated Log findings pending clarification.

**Done when:**

- [ ] component breakdown proposed and reviewed by the owner
- [ ] every agreed component has a knowledge page
- [ ] every knowledge page routes a request to owned source and focused tests,
      with boundaries and invariants derived from current evidence
- [ ] agreed component behaviors are covered by requirements; disputed
      behavior is recorded with evidence for owner clarification
- [ ] `linked_tests` point at the existing tests that verify them
- [ ] untested behaviors visible through requirement links and `check`, not
      duplicated line by line in the Log
- [ ] suspected defects logged as future tasks, with requirement prose
      reserved for agreed behavior
- [ ] `check` reports no errors over the whole tree
- [ ] report appended and the owner agreed to close

**Skip when:** The repository is already adopted: go straight to
`.agentic/steps/1_frame.md`. Partial adoption is normal: adopt the components
you actively work on, and let `check` warn when a task touches an unadopted
area.

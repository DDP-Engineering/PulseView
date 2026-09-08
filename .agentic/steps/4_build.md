<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 4 — build

**Purpose:** Implement the linked requirements test-first, one at a time,
using focused project test commands as the inner loop, and keep requirement
links current for optional impacted selection.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`, including `## Design`.
- Every requirement on its `requirements:` line, and their specs.
- The existing tests for the files you are about to touch.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

**Steps:**

When build is re-entered from explicit review, Fix only recorded review
findings. Do not expand scope, reset the review round, or preserve either old
verdict while the candidate changes. Return to validate after focused proof.

A child is an ordinary governed task: follow the same test-first loop, keep
its journal and requirement links current, and expose its state to the parent
through the shared checkout. The parent does not treat child completion as
integrated proof.

Before running tests in a new checkout, follow the repository's documented
setup and readiness checks for the required runtimes, dependencies, services
and working directory. Inspect an active verification job before launching
another. Diagnose a missing prerequisite directly; do not repeatedly launch
whole suites to discover it. Setup never grants permission for host changes,
network downloads, or installation beyond existing authorization.

1. Pick one requirement. Work it to green before starting the next - do
   not open several at once.
   If implementation exposes an additional component not named in the design,
   run `python .agentic/aegis.py components`, read the selected page and exact
   seams, and log the scope effect before editing that component.
2. Write or extend a test that expresses that requirement's
   `verification` and fails for the right reason. Write the test
   **before** you touch any implementation file. Where `verification`
   declares a manual method (`Manual:` / `Inspection:`), there is no test
   to write: carry it out once the change is in, and log what you
   observed instead of the red-then-green line.
3. Run the test and watch it fail. Confirm the failure is the one you
   expect (missing behavior), not a typo, an import error, or a bad
   fixture.
4. Before implementing a meaningful behavior increment, record one consolidated
   observed failure in `## Log`. Related requirements that share the same test
   seam may use one record. Include their IDs, the **exact test selector or command**,
   its **non-zero exit code**, and the **expected missing-behavior failure reason**:
   `- <date> build red: command=\`pytest -q tests/x.py::test_y\`; exit=1;`
   ` expected missing behavior=<reason>.`
   Keep it reproducible but short; do not paste the full traceback or create a
   separate line per requirement when one run demonstrates the same gap. Do
   not log a typo, import error, bad fixture, tool failure, or corrected retry.
   This is an agent-authored journal record, not independent proof. For a
   `Manual:`/`Inspection:` method, record a **manual observation** after the
   implementation instead: method, action, and observed result.
5. Run `python .agentic/aegis.py anchor --task TASK-<id>` after the expected
   red failure and before implementation. AEGIS records a timestamped
   fingerprint of every Git-visible, non-ignored repository file except its
   own `.agentic/` state and generated Python bytecode caches. This describes
   the starting point; it is not tamper-proof and does not prove the red test
   was honest. For work without an automated red test, anchor immediately
   before the first implementation edit instead.
6. Implement the smallest change that makes the test pass. Resist adding
   behavior no requirement asks for.
7. Maintain the links **now, before running the focused set**:
   - add each source path you changed to that requirement's
     `affected_paths` (forward slashes, repo-relative);
   - add each new or changed test to `linked_tests` as
     `tests/path.py::test_name`;
   - set `status = "active"` and refresh `updated`.
   These two lists are what select the impacted set. Link first: an
   unlinked new test would not be in the set, and a changed source file
   no requirement covers makes `--impacted` refuse and fall back to the
   full suite (by design).
8. Run the smallest project-native command that proves this behavior increment.
   Where the configured runner honors selectors, optionally preview
   `python .agentic/aegis.py test --impacted --base HEAD --dry-run`, then use
   `python .agentic/aegis.py test --impacted --base HEAD --no-fallback`.
   The preview is not proof. If selection is unavailable or the project runner
   ignores selectors, use a focused native command instead; do not trigger a
   full-suite fallback after every edit. AEGIS does not infer runner syntax or
   guarantee that a configured command is focused. Keep the full project suite
   for final validation unless an identified integration risk requires it sooner.
   Do not log inner-loop retries. When the increment is green, append one
   consolidated result with the command, exit zero, and covered requirements.
   Repeat steps 2-8 until the requirement is done.
9. Move to the next requirement and repeat from step 1.
10. When all requirements are green, run
    `python .agentic/aegis.py evolution --task TASK-<id>`. Review every added,
    modified, and removed path, then run `python .agentic/aegis.py check`.
   Fix what it flags, or record in one log line which warning remains and why;
   state it as a deviation notice only when accepting that finding materially
   limits the candidate or its verification, per `AGENTS.md`; unrelated or
   corrected findings are ordinary evidence. Reconcile an unexpected
   `evolution` report.
   It becomes a deviation only if you accept candidate files or omissions that
   materially depart from the agreed scope or design.
11. Tick the checklist, set `stage: validate`, and **replace
    `## Done checklist`** with the validate stage's "Done when" list from
    `5_validate.md` — the checklist always shows the current stage's items.

**Outputs:**

- New and changed tests, and the implementation that satisfies them.
- Updated `affected_paths`, `linked_tests`, `status` on each requirement.
- Journal log lines: one reproducible red result and one final focused green
  result per meaningful behavior increment, a consolidated manual observation
  where applicable, plus material accepted warnings.

**Done when:**

- [ ] each automated behavior increment has a pre-implementation red record
      with requirement IDs, exact selector or command, non-zero exit, and
      expected failure reason, plus one final focused green result; each manual
      increment has a consolidated post-implementation observation
- [ ] repository anchor recorded after red and evolution reviewed after implementation
- [ ] implementation makes those tests pass
- [ ] focused project tests green, with their actual scope recorded
- [ ] `affected_paths` and `linked_tests` updated on every requirement
- [ ] `status = "active"` on every requirement this task delivers — or
      `"retired"`, with the reason in its prose, where this task
      deliberately removed the behavior
- [ ] `check` clean, or each remaining warning explained in the log
- [ ] `stage: validate`

**Skip when:** Never — the quick path goes through `build` too. If a task
genuinely changes no behavior (documentation only), say so in the log and
record which requirements you re-read to confirm it; do not invent a test.

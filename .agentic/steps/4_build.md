<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 4 — build

**Purpose:** Implement the linked requirements test-first, one at a time,
using the impacted-test set as the fast inner loop, and keep the
requirement links current so that set stays correct.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`, including `## Design`.
- Every requirement on its `requirements:` line, and their specs.
- The existing tests for the files you are about to touch.

**Steps:**

1. Pick one requirement. Work it to green before starting the next — do
   not open several at once.
2. Write or extend a test that expresses that requirement's
   `verification` and fails for the right reason. Write the test
   **before** you touch any implementation file. Where `verification`
   declares a manual method (`Manual:` / `Inspection:`), there is no test
   to write: carry it out once the change is in, and log what you
   observed instead of the red-then-green line.
3. Run the test and watch it fail. Confirm the failure is the one you
   expect (missing behavior), not a typo, an import error, or a bad
   fixture.
4. Record the observed failure in `## Log` before implementing. Include the
   **exact test selector or command**, its **non-zero exit code**, and the
   **expected missing-behavior failure reason**:
   `- <date> build red: command=\`pytest -q tests/x.py::test_y\`; exit=1;`
   ` expected missing behavior=<reason>.`
   Keep it reproducible but short; do not paste the full traceback. This is
   an agent-authored journal record, not independent proof. For a
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
8. Run `python .agentic/aegis.py test --impacted --base HEAD` as the inner
   loop. It runs only the tests linked to requirements whose
   `affected_paths` you touched, so it is fast enough to run after every
   edit. `--base HEAD` narrows it further to what you have not committed
   yet — without it the basis is the whole branch, which on a long-lived
   branch selects most of the suite. Repeat steps 2–8 until the
   requirement is done.
9. Move to the next requirement and repeat from step 1.
10. When all requirements are green, run
    `python .agentic/aegis.py evolution --task TASK-<id>`. Review every added,
    modified, and removed path, then run `python .agentic/aegis.py check`.
   Fix what it flags, or record in one log line which warning you accept
   and why.
11. Tick the checklist, set `stage: validate`, and **replace
    `## Done checklist`** with the validate stage's "Done when" list from
    `5_validate.md` — the checklist always shows the current stage's items.

**Outputs:**

- New and changed tests, and the implementation that satisfies them.
- Updated `affected_paths`, `linked_tests`, `status` on each requirement.
- Journal log lines: one reproducible red-test record per automated
  requirement, a manual observation where applicable, plus accepted warnings.

**Done when:**

- [ ] each automated requirement has a pre-implementation red record with
      exact selector or command, non-zero exit, and expected failure reason;
      each manual requirement has a post-implementation observation
- [ ] repository anchor recorded after red and evolution reviewed after implementation
- [ ] implementation makes those tests pass
- [ ] `test --impacted` green
- [ ] `affected_paths` and `linked_tests` updated on every requirement
- [ ] `status = "active"` on every requirement this task delivers — or
      `"retired"`, with the reason in its prose, where this task
      deliberately removed the behavior
- [ ] `check` clean, or each remaining warning explained in the log
- [ ] `stage: validate`

**Skip when:** Never — the quick path goes through `build` too. If a task
genuinely changes no behavior (documentation only), say so in the log and
record which requirements you re-read to confirm it; do not invent a test.

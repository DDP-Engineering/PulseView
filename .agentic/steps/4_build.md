<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 4 — build

**Purpose:** Implement the requirements test-first, one at a time, with
focused tests as the inner loop.

**Read:**

- The journal, including `## Design`, every requirement on its
  `requirements:` line, and their specs.
- The existing tests for the files you will touch.
- The relevant sections of `.agentic/context/environment.md`, and the
  commands in `.agentic/aegis.toml`.

**Steps:**

Before the first test run in a new checkout, follow the project's setup and
readiness checks. Diagnose a missing prerequisite directly instead of
relaunching whole suites; setup never permits installs or downloads beyond
what the user allowed.

Take one requirement at a time and finish it before starting the next:

1. Write or extend the test that expresses its `verification`, before any
   implementation change. Run it and confirm it fails for the expected
   reason: missing behavior, not a typo, an import error or a bad fixture.
2. Record the red result with
   `python .agentic/aegis.py log TASK-<id> "red: <command> exit <code> -
   <expected missing behavior> (<REQ-ids>)"`. Requirements that share one
   failing test share one line.
3. Before the task's first implementation edit, run
   `python .agentic/aegis.py anchor --task TASK-<id>`.
4. Implement the smallest change that makes the test pass, adding no
   behavior that no requirement asks for.
5. Update the requirement: add the changed source to `affected_paths` and the
   test to `linked_tests` as `<test file>`, or `<test file>::<test name>`
   where the test runner accepts that selector, set `status = "active"`, and
   refresh `updated`.
6. Run the smallest command that proves the increment:
   `python .agentic/aegis.py test --impacted --base HEAD --no-fallback` when
   the configured runner honors selectors, otherwise a focused native command.
   Keep the full suite for validate. Log one green line per increment:
   `log TASK-<id> "green: <command> exit 0 (<REQ-ids>)"`.

A `Manual:` or `Inspection:` verification has no test: carry it out after the
change and log the method, the action and the observed result. If the work
reaches an additional component the design did not name, run
`python .agentic/aegis.py components`, read its page and log the scope effect
before editing it. Update the docstrings, usage examples and setup
instructions the change affects.

When every requirement is green:

7. Run `python .agentic/aegis.py evolution --task TASK-<id>` and review every
   added, modified and removed path against the design.
8. Run `python .agentic/aegis.py check`. Fix what it flags, or log why a
   warning remains; a remaining warning that limits the candidate or its
   verification is a deviation.

Back from explicit review: fix only the recorded findings, without expanding
scope or resetting the review round, rerun the focused proof, and return to
validate.

**Finish:**

- Checkpoint: `python .agentic/aegis.py pause TASK-<id> --next "Continue to
  validate?" --evidence "<focused command> exit 0"`; show the summary and the
  choices: continue, change the implementation or tests, return to design or
  specify, or stop. When the user continues, `advance TASK-<id>` and read the
  next step file.
- Autopilot: `advance TASK-<id> --evidence "<focused command> exit 0"` and
  read the next step file.

**Done when:**

- [ ] each automated increment has a red line before its implementation and a
      green line after; each manual one a logged observation
- [ ] anchor recorded before implementation; evolution reviewed after
- [ ] focused tests green, with the command and its scope logged
- [ ] `affected_paths`, `linked_tests` and `status = "active"` current on every
      requirement, or `retired` with its reason
- [ ] affected docstrings, usage examples and setup instructions updated
- [ ] `check` clean, or each remaining warning explained in the Log

**Skip when:** Never. Documentation-only work logs which
requirements it re-read instead of inventing a test.

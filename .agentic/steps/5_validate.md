<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 5 — validate

**Purpose:** Review and reconcile everything that can still change the
candidate, prove it last, and close the task.

**Read:**

- The whole task journal, and every requirement on its `requirements:` line.
- The knowledge page of each component the change touched, and
  `.agentic/templates/component.md` when a page is missing or must be
  migrated. Run `python .agentic/aegis.py components` when the diff touches an
  additional component the task did not name.
- This step file again, even if you read it before build.

**Order:** correct first, prove last. Every candidate edit, knowledge and
context pages included, belongs to steps 1-8. Step 9 proves the result once;
after it only journal records change, and any other edit needs fresh review
and proof.

A parent task validates the integrated candidate: review the child tasks
visible in this checkout, confirm that each was independently validated, and
prove their combined behavior against the parent's scope and requirements. A
child's green suite is not the parent's proof.

**Steps:**

Correct the candidate first, and run no full proof yet:

1. Review the diff hunk by hunk against the Frame scope and exclusions, each
   requirement and its verification, the design, error paths, portability,
   secrets, security and unrequested work. Read the current checkout;
   `git show HEAD:<path>` is history, not the candidate. Read the existing
   tests before calling coverage missing: a return for missing coverage names
   the untested behavior. A `check` finding is a prompt to look, not a
   verdict: `source-no-test-changes` says no test file changed, not that the
   behavior is untested.
2. A wrong assumption goes back instead of being patched around:
   `python .agentic/aegis.py advance TASK-<id> --to <specify|design|build>
   --reason "<what>"`, then stop. The return waits for the user and clears
   enabled review verdicts.
3. Update or create the knowledge page of each materially changed component
   against the reviewed code and tests: Routing, Purpose and boundaries,
   Public interface, Invariants, Key behaviors, Files, and a Change map when
   the component has several independent seams. Find the existing page
   before choosing a new filename. Migrate a touched legacy page to the
   current template: remove a retired `## Architecture` section and keep any
   still-true constraint from it in Purpose and boundaries or Invariants. A
   page made from the template leaves out its license comment and its
   guidance comment.
4. Bring the affected sections of `.agentic/context/project.md` and
   `.agentic/context/environment.md` into line with the candidate. Replace
   stale claims and leave unrelated sections alone. On knowledge and context
   pages alike, edit the existing sections in place and add no section for
   one task; `check` reports a page above `[context] page_kb` or with a
   repeated heading.
5. Re-read each requirement: its status and prose describe the built
   behavior, its verification matches what settles it, and its paths and
   links are current. A mismatch with an established contract goes back to
   build or to the user; never weaken a requirement to fit the code.
6. Complete each `Manual:` or `Inspection:` verification, and log the
   method, the action and the observed result.
7. With explicit review enabled (`brief` shows `Review: policy=enabled`),
   follow `.agentic/steps/review.md` now.
8. If validation changed files outside `.agentic/`, rerun
   `python .agentic/aegis.py evolution --task TASK-<id>` and review it. A
   missing anchor stays a recorded limitation; do not create one now.

Then prove it, once, with no candidate edit afterwards:

9. **Prove last:** `python .agentic/aegis.py check --task TASK-<id> --strict
   --run`, after steps 1-8 and without a separate full test run before it.
   When the proof cannot run, because of a standing instruction or an
   environment limit, run the narrowest proof that covers the candidate, name
   what it misses, and say it as a deviation.
10. Log the result once:
    `log TASK-<id> "final: <command> exit <code>; <what ran>; <remaining
    warnings and why they are acceptable>"`. Never write green over a non-zero
    exit. A failure this task introduced goes back to the stage that owns it;
    a pre-existing failure is named and kept out of scope. A failure or
    limitation that remains also goes in `--issues` when you pause.
11. Run `python .agentic/aegis.py report TASK-<id>` and read what it appends.

**Finish:**

- Checkpoint: `python .agentic/aegis.py pause TASK-<id> --next "Close the
  task?" --evidence "<final command> exit <code>"`; show the summary, the
  final proof, accepted warnings, deviations and the changed files, and offer
  the choices: close, return to build for corrections, revisit the scope, or
  stop. When the user closes, `advance TASK-<id>` to `done`.
- Autopilot: when the proof passed, `advance TASK-<id> --evidence "<final
  command> exit 0"`; otherwise `pause TASK-<id> --blocked --next "<the
  decision or fix needed>" --issues "<the failure>"`.
- After `done`, report the outcome. Committing, pushing and opening a pull
  request follow the repository's procedures and the user's instructions;
  they are not AEGIS steps.

A legacy journal at `deliver` was validated under an earlier version of this
workflow: confirm that its recorded proof still describes the checkout, then
`advance TASK-<id>` to close it.

**Done when:**

- [ ] diff reviewed against scope, requirements, design, error paths,
      portability, security and unrequested work
- [ ] knowledge pages of changed components current with the reviewed code
- [ ] project and environment context reconciled with the candidate
- [ ] requirements re-read: status, prose, verification, paths and links true
- [ ] manual or inspection verification recorded where applicable
- [ ] explicit review approved, when enabled
- [ ] final `check --strict --run` result logged truthfully after the last edit
- [ ] remaining warnings and pre-existing failures explained
- [ ] `report` appended

**Skip when:** Never.

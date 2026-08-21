<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 5 - validate

**Purpose:** Reconcile everything that may still change the candidate, then
prove the final tree before it is presented for publication.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`, whole file.
- Every requirement on its `requirements:` line.
- The knowledge page of each component you touched, and
  `.agentic/templates/component.md`.

**Steps:**

1. Review the diff semantically, hunk by hunk, against the frame scope and
   exclusions, each requirement and its verification, the design note, error
   paths, Windows/Linux portability, secrets, security, and unrequested work.
2. Send wrong assumptions backwards instead of patching around them here. Set
   `stage:` to `specify` or `design`, replace the checklist with that stage's
   "Done when" list, log why, and stop. An implementation flaw returns to
   `build` by the same protocol.
3. Update component knowledge. For every component whose behavior, interface,
   or file set materially changed, update or create
   `.agentic/knowledge/<component>.md` from the template. Keep **Purpose**,
   **Public interface**, **Key behaviors**, **Architecture**, and **Files**
   true. Where `design` drew the architecture as it was going to be, check
   the built code against it now: reconcile any difference in the diagram's
   favor only if the code is right, and delete the line naming it an intended
   shape — from here the page describes what exists.
4. Re-read each requirement. Confirm its status and prose describe the built
   behavior, its verification matches the observation, and all affected paths
   and linked tests are current. Correct them now.
5. Complete and record every `Manual:` or `Inspection:` verification. Name the
   method, action, and observed result; never substitute a manual label for an
   automatable test that is merely missing. Where a manual method stands in for
   a test that could have been written, state it as a deviation notice in the
   conversation, per `AGENTS.md`.
6. If steps 1-5 changed source, tests, requirements, specs, or knowledge, rerun
   the impacted set and resolve the result before proving the repository.
7. If validation changed any repository file outside `.agentic/`, rerun
   `python .agentic/aegis.py evolution --task TASK-<id>` so the saved,
   timestamped report describes the final candidate. Review every added,
   modified, and removed path. The report is descriptive evidence, not a
   tamper-proof guarantee.
8. **Prove the final candidate only after every candidate-changing step:**
   `python .agentic/aegis.py check --task TASK-<id> --strict --run`.
   This executes the configured full verification commands plus the advisory
   catalog. If any fix changes the candidate, repeat the relevant review and
   this proof; the last proof must describe the tree handed to `deliver`.
9. Record the actual result in the log: command, exit code, commands/tests run,
   and remaining warnings with their accepted reasons. Never write "green"
   over a non-zero exit. A failure introduced by this task returns to the
   appropriate earlier stage. A pre-existing base-branch failure is named and
   kept out of scope, with its effect on CI stated honestly. A non-zero exit, a
   warning you accept, and a verification you skipped or could not run are each
   a deviation: state it as a deviation notice when you record it, per
   `AGENTS.md`, rather than letting `deliver` be the first the human hears of
   it.
10. Tick the checklist, set `stage: deliver`, and replace it with the delivery
   stage's "Done when" list from `6_deliver.md`. The task now means
   "validated, not yet published."

**Outputs:**

- Reviewed candidate with current requirements and component knowledge.
- Manual observations where required.
- Final suite and strict-check evidence in the journal log.
- Journal advanced to `stage: deliver` only after proof.

**Done when:**

- [ ] diff reviewed against scope, requirements, design, error paths,
      portability, security, and unrequested work
- [ ] knowledge pages updated for every materially changed component
- [ ] requirements re-read: status, prose, verification, paths, and links true
- [ ] manual or inspection verification completed and recorded where applicable
- [ ] final evolution report refreshed after the last candidate edit
- [ ] final `check --strict --run` result recorded truthfully after all edits
- [ ] remaining warnings and pre-existing failures explained
- [ ] `stage: deliver`

**Skip when:** Never, on either path. Quick path skips specification and design
when proportionate; it does not skip repository-wide proof.

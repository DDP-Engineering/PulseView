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

**Stage report (completion or pause):** After updating the log, header and
checklist, refresh the single `## Stage report` section in this task journal:
At every stage transition or pause, append any new Ruling and refresh the Handoff;
also refresh the Handoff for a blocker or session end.
`stage`, `result`, `current`, `changed`, `evidence`, `issues`, `next`,
`needs_user`, `spec_compliance`, `implementation_quality`, and `review_round`
(plain one-line fields, no fences). Record the completed stage
separately from `current`, which must match the header after any transition;
use `paused` when waiting or ending a session. Other results are `in_progress`,
`completed`, `blocked`, `skipped`. Run
`python .agentic/aegis.py summary TASK-<id>` and copy its block before any
detailed explanation. Unknown values stay blank (`not recorded`); refresh
stale records and read omitted details before continuing. Preserve existing
approval stops and immediate deviation notices; this report adds no new stop.

**Resume context:** Run `brief TASK-<id>` first, then read this stage's instructions,
the journal header/checklist and relevant log entries (scope, user limits,
unresolved issues, decisions and evidence); follow links to needed records.
This stage's required full reads still apply. Use linked requirements and
source as needed, not the whole register. Do not act on missing, stale, or
shortened reporting without reviewing the full journal information.

## Optional explicit review and bounded re-review

Read `[review]` in `.agentic/aegis.toml` before applying this protocol.
When review is disabled, record both verdicts as `disabled`, leave
`review_round` blank, and skip only explicit verdicts and their fix loop.
Existing semantic review, full suite, strict check, evidence, and the delivery
checkpoint remain mandatory.

When review is enabled:

1. Set the initial `review_round` to 1. The total bound is
   `1 + max_fix_cycles`; two fix cycles means three total review rounds.
2. Ask two questions and record independent verdicts. **Specification
   compliance** checks scope, exclusions, requirements, specs, and design.
   **Implementation quality** checks correctness, errors, tests, security,
   maintainability, portability, and unrequested work.
3. Both verdicts apply to the same current candidate. Any candidate change
   invalidates both verdicts: clear both while editing, then perform both
   reviews again.
4. If either verdict is `changes_required` and a cycle remains, append the
   findings to the log and route to the appropriate existing stage.
5. Fix only the recorded findings, rerun relevant proof, increment the round,
   and return here. Do not expand scope or reset the counter to continue.
6. A specification ambiguity or scope change uses the existing human
   checkpoint; do not guess inside the loop.
7. If both current verdicts are `approved`, continue with the final proof and
   delivery transition below.
8. If either verdict still requires changes on the final allowed round, set
   `result: blocked` and `needs_user: yes`; do not advance to deliver.
9. Only an explicit human Ruling that changes scope or policy can reset the
   counter.

**Steps:**

Parent validation owns the integrated candidate. Review all children visible
in this checkout, confirm each child was independently validated, and verify
their combined behavior against the parent's scope and requirements. A child
verdict or green suite does not replace integration proof in the parent.

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

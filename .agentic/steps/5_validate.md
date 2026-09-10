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
- `python .agentic/aegis.py components` if diff review exposes an additional
  touched component whose knowledge page the task did not already name.
- The knowledge page of each component you touched, and
  `.agentic/templates/component.md`.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

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
3. Update component knowledge. For every component whose routing, boundary,
   invariant, behavior, interface, architecture, or file set materially
   changed, update or create `.agentic/knowledge/<component>.md` from the
   template. A touched legacy page that lacks Routing or another standard
   section is knowledge drift; migrate it to the current template before
   reconciling **Routing**, **Purpose and boundaries**, **Public
   interface**, **Invariants**, **Key behaviors**, **Architecture**, and
   **Files** against the exact source and tests. Reconcile **Change map** when
   the component has multiple independent edit-and-test seams, and omit it
   when Routing and Files already identify one obvious seam. Read any
   `### Proposed architecture - TASK-<id>` diagram from the task's Design and
   compare it with the built code. Update the component page's
   `## Architecture` diagram to the resulting current-state implementation.
   Retain the task proposal as historical design evidence; never delete it.
   If the built code differs from the proposal, record the justified deviation
   or decision. When no proposal exists, derive the current-state diagram
   directly from the built code.
   Reconcile affected sections of `.agentic/context/project.md` and
   `.agentic/context/environment.md` with the same candidate and canonical
   configuration/setup references. Populate missing files only with known
   in-scope facts; preserve unrelated sections. Project and component documents
   state current positive responsibilities and behavior. Replace stale claims;
   keep proposals, removed-feature inventories, before/after narratives, and
   investigation history in the journal. Leave unchanged sections untouched.
4. Re-read each requirement. Confirm its status and prose describe the built
   behavior, its verification matches the observation, and all affected paths
   and linked tests are current. Correct documentation drift now; a mismatch
   with an established contract returns to build or an authorized scope
   decision, rather than weakening the requirement to match the code. Active
   prose states the current positive outcome and meaningful failure responses.
   Resolve draft-spec open decisions before activation and retain their decision
   history in the journal, not the active spec.
5. Complete and record every `Manual:` or `Inspection:` verification. Name the
   method, action, and observed result; never substitute a manual label for an
   automatable test that is merely missing. Where a manual method stands in for
   a test that could have been written, state it as a deviation notice in the
   conversation, per `AGENTS.md`.
6. If steps 1-5 changed executable behavior, tests, or verification configuration,
   run relevant focused proof as needed to resolve the change. Prose-only updates
   require semantic and traceability review; they do not alone require another
   runtime test run. Do not run an impacted set that expands to the full suite
   immediately before the final full proof.
7. If validation changed any repository file outside `.agentic/`, rerun
   `python .agentic/aegis.py evolution --task TASK-<id>` so the saved,
   timestamped report describes the final candidate. Review every added,
   modified, and removed path. The report is descriptive evidence, not a
   tamper-proof guarantee.
8. **Prove the final candidate only after every candidate-changing step:**
   `python .agentic/aegis.py check --task TASK-<id> --strict --run`.
   This executes the configured full verification commands plus the advisory
   catalog. Schedule this once after edits and review, rather than once per
   stage. A failure or subsequent candidate change requires relevant review and
   fresh proof; the last proof must describe the tree handed to `deliver`.
   Do not run a separate full `test` immediately before this command. An earlier
   full run, a dry-run preview, or an unchanged fingerprint on a cancelled job
   cannot substitute for the required successful final verification.
9. Record one consolidated final validation result in the log: command, exit
   code, commands/tests run, and remaining warnings with their accepted
   reasons. Record an earlier failed gate only when it exposed a candidate
   problem, caused an implementation or test change, or remains an accepted
   limitation; omit corrected operational retries. Never write "green" over a
   non-zero exit. A failure introduced by this task returns to the
   appropriate earlier stage. A pre-existing base-branch failure is named and
   kept out of scope, with its effect on CI stated honestly. State it as a
   deviation notice when the candidate advances while accepting a relevant
   failure or warning, omitting or weakening required verification, or
   substituting materially weaker evidence. A tool-use error or failed command that is
   corrected and rerun successfully without affecting the candidate or proof
   is operational detail, not a deviation. Apply the material-impact rule in
   `AGENTS.md` rather than turning every non-zero exit into a notice.
10. In checkpoint mode, present the `validate` Stage-boundary choices from
    `AGENTS.md`, refresh the waiting Handoff and paused Stage report, then stop
    before transition. After the user chooses to continue, or immediately in
    autopilot, tick the checklist, set `stage: deliver`, and replace it with
    the delivery stage's "Done when" list from `6_deliver.md`. The task now
    means "validated, not yet published."

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

<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 6 - deliver

**Purpose:** Present, report, commit, and publish a validated candidate without
changing what was proved.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`, whole file, especially the
  latest validation evidence.
- The final diff and repository status.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

**Steps:**

1. Confirm that this stage **does not edit the validated candidate**. Inspect
   the diff and status before publishing. If source, tests, requirements,
   specs, or knowledge changed after the recorded proof—or must change now—
   return to `validate`: set `stage: validate`, replace the checklist with
   `5_validate.md`'s "Done when" list, log why, and stop for revalidation.
2. When explicit review is enabled, confirm both current bound verdicts are
   `approved` for this unchanged candidate. Blank, malformed, stale,
   `disabled`, or `changes_required` evidence returns to validate. When
   explicit review is disabled, rely on the existing validation evidence and
   checkpoint; disabled review never skips them.
3. Keep the journal log append-only. Journal-only delivery records are
   expected here; never rewrite or delete earlier evidence.
4. **Stop and present in both interaction modes:** validation commands and
   results, accepted warnings and pre-existing failures, the exact diff
   summary, child status and integrated parent evidence when children are
   visible, what will be committed, exclusions, and the intended outcome.
    Present the `deliver` Stage-boundary choices from `AGENTS.md`, refresh the
    waiting Handoff and paused Stage report, and wait for the human's choice.
    Any deviation notices you gave along the
   way were notifications, not approvals: notices supplement this
   presentation and never shorten it, so repeat every deviation here even
   where you already said it, and state it as a deviation notice if this
   stage turns up a new one.
5. After approval, tick every checklist item except close-out, keep
   `stage: deliver`, log the decision, and run
   `python .agentic/aegis.py report TASK-<id>`. Read the appended report.
   Its check counts are a fresh report-time advisory snapshot, not a
   replacement for the validation evidence. Correct journal-only mistakes;
   any candidate correction returns to `validate` and requires new proof.
6. Deliver the approved outcome:
   - **Commit** on the task branch, with requirement IDs in the message.
   - **PR** by default. If CI runs `check --strict --run`, it decides merge.
   - Release or deployment beyond the PR requires the repository's separate
     process, explicit approval, and post-release verification.
   - With no remote, stop after the commit and report that no PR was opened.
     With no Git, stop after presentation and report that delivery is
     unavailable in this environment.
7. Close out only after the approved outcome succeeds - but let the outcome
   decide how many commits that takes:
   - **The outcome can still fail after the delivery commit** (a push, a PR, a
     release, a deployment): commit the delivery, wait for the outcome, then
     set `stage: done`, tick close-out, append one truthful log line, and make
     a small close-out commit pushed to the same PR. Only a later commit can
     report truthfully on something that had not happened yet.
   - **The outcome is the delivery commit itself** — a repository-local commit
     with no push, PR, release, or deployment — then nothing can fail after it,
     so close out *before* committing: set `stage: done`, tick close-out,
     append the log line, and let the same commit carry them. A second commit
     here records nothing that the first did not already prove.
   If delivery fails, record the failure and leave `stage: deliver` so `status`
   continues to show open work.

**Outputs:**

- Human-approved delivery decision in the journal.
- Report-time advisory snapshot appended to the journal.
- Delivery commit and the agreed outcome, normally a PR.
- A close-out commit once that outcome succeeds, or a single commit carrying
  the close-out where the commit is itself the whole outcome and so cannot
  fail after it.

**Done when:**

- [ ] validated candidate confirmed unchanged; otherwise returned to validate
- [ ] validation evidence, diff, exclusions, and outcome presented
- [ ] delivery confirmed by the human
- [ ] journal and report included in the delivery commit
- [ ] agreed outcome delivered, normally a PR
- [ ] close-out committed after the outcome succeeded, or carried by the
      delivery commit where nothing could fail after it

**Skip when:** Never. Validation proves the candidate; delivery records and
publishes the approved result.

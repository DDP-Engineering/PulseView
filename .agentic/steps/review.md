<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Explicit review (optional)

**Purpose:** Two independent verdicts on the same candidate before validate's
final proof, with a bounded fix loop. Read this file only when
`[review] enabled = true`; with review disabled, validate skips only these
verdicts and keeps every other step.

**Steps:**

1. Brief two independent reviewers with the task ID, the paths of its
   journal, requirements and specs in this checkout (even when untracked), the
   focused proof and the actual test assertions. The final strict proof comes
   after their approvals, so its absence is not a finding; missing focused
   proof or untested behavior is.
   - **Specification compliance** checks scope, exclusions, requirements,
     specs and design.
   - **Implementation quality** checks correctness, error handling, tests,
     security, maintainability, portability and unrequested work.
2. Record both verdicts and the round:
   `python .agentic/aegis.py verdict TASK-<id> --spec <approved|changes_required>
   --quality <approved|changes_required> --round <n>`. A new review starts at
   round 1; a resumed one keeps its round.
3. Both approved: continue with validate's next step.
4. Changes required while rounds remain (the total is `1 + max_fix_cycles`,
   so two fix cycles allow three rounds):
   log the findings, run `advance TASK-<id> --to build --reason "<findings>"`,
   fix only those findings, rerun the focused proof, return to validate and
   review both roles again with `--round <n+1>`. Any candidate edit
   invalidates both verdicts.
5. Changes still required on the last round: `pause TASK-<id> --blocked
   --next "<the scope or policy decision that would unblock it>"`. Do not
   repair, prove or close from here. Only a decision by the user, recorded
   with `ruling --source user`, changes the scope or the bound.
6. A specification ambiguity a reviewer finds is a question for the user, not
   something to settle inside the loop.

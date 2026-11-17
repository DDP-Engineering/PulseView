<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 1 — frame

**Purpose:** Turn the ask into an agreed scope, recorded in a new task
journal that every later stage reads.

**Read:**

- The request, and anything it points at.
- `python .agentic/aegis.py status`: when an open task already covers the
  ask, resume it with `brief` instead of framing it again.
- `.agentic/context/project.md` and the relevant sections of
  `.agentic/context/environment.md`, when present.
- `python .agentic/aegis.py components`, then the owning page's `## Routing`
  selection signals to confirm ownership, then the exact source and tests it
  names. A legacy page without Routing still locates them through its
  available sections; its migration belongs to validate. Missing context or
  pages are something to inspect, not a blocker.

**Steps:**

1. Use the current branch: the journal records it, and creating or switching
   branches is the developer's call unless the user asks you to. On the
   repository's default branch, note that under `Constraints` so the
   developer can move the work to a task branch.
2. Create the journal: `python .agentic/aegis.py task "<title>" --type
   feature` (or `fix`, `change`). Keep the printed ID and path, and use that
   journal from now on; never open a second one for the same task.
3. **Analyze.** Fill the journal's `## Frame` from the request and the
   evidence you read, labelling claims STATED, OBSERVED, INFERRED or UNKNOWN
   and keeping the user's terms. `Problem` is the condition to change;
   `Desired outcome` is what holds afterwards. A request for new behavior
   does not establish a current defect or existing data: keep unverified
   conditions UNKNOWN. Give at least one example, or say none was supplied,
   and a counterexample when it sharpens the boundary; an example that needs
   a value the user has not given names it, such as `N days`, instead of
   choosing a number.
4. **Challenge.** Look for contradictions with existing behavior,
   requirements and rules; missing triggers, boundaries and failure cases;
   and permission, compatibility, security and data effects. A question is
   decision-blocking when its answer changes the desired outcome, the
   authorized scope, or the handling of existing or deleted data.
   Put those under `Decision-blocking questions` and keep every other gap in
   `Unknowns`.
5. Do not settle open behavior by convention: error responses, exit codes,
   output formats, thresholds and reversibility stay UNKNOWN until the user
   or an established contract decides. List candidate answers under
   `Proposed behaviors`, marked as not accepted, and do not repeat them as
   scope, constraints or success signals. An exclusion in `Out of scope`
   needs a source too.
6. When existing requirements already cover the behavior, put their IDs on
   the header's `requirements:` line now; specify may then be skipped.
7. Decide whether the work needs child tasks: only for independently scoped
   work that can stand as an ordinary task.
8. **Audit.** Every STATED claim has the user's words behind it, every
   proposed behavior serves a success signal, no unknown became behavior,
   and scope, exclusions and examples agree.

**Finish:**

- Checkpoint: `python .agentic/aegis.py pause TASK-<id> --next "<question>"`,
  where the question is the first decision-blocking question or, when none
  remains, "Accept the framed scope and continue to specify?". Show the
  summary, the Frame in brief and the choices: continue, revise the scope,
  or stop. When the user accepts, run
  `python .agentic/aegis.py advance TASK-<id> --reason "scope accepted"` and
  read the next step file.
- Autopilot: with no blocking question, `advance TASK-<id>` and read the next
  step file; otherwise `pause TASK-<id> --blocked --next "<question>"`.

**Done when:**

- [ ] Frame states problem, outcome, actors, scenario, scope, examples,
      constraints, success signals, evidence and unknowns
- [ ] material claims labelled stated, observed, inferred or unknown
- [ ] decision-blocking questions answered or asked
- [ ] covering requirements named on the `requirements:` line, when they exist
- [ ] the journal's `branch:` matches the current checkout
- [ ] proposed behaviors serve the desired outcome and success signals
- [ ] scope accepted by the user (checkpoint) or recorded (autopilot)

**Skip when:** Never: every task starts here. An existing task resumes from
`brief` instead.

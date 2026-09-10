<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 1 — frame

**Purpose:** Turn the ask into an agreed scope and a chosen path, and open
the task journal that every later stage reads and updates.

**Read first:**

- The prompt itself, and anything it points at.
- `.agentic/AGENTS.md` (stage table, artifact locations, interaction modes).
- `.agentic/context/project.md` and relevant sections of
  `.agentic/context/environment.md`, when present. Follow their authoritative
  references; confirm facts against this checkout. Missing context is an
  invitation to inspect, not a blocker. Populate only confirmed current facts
  within scope; keep proposed features and unresolved questions in the Frame.
- `python .agentic/aegis.py status` — an open task may already cover this.
- `python .agentic/aegis.py components` when the prompt does not already name
  an exact component page; use its title-and-path list to choose candidates.
- The knowledge page for the area named in the ask, if one exists:
  `.agentic/knowledge/<component>.md`. Read its `## Routing` selection signals
  first to confirm ownership or follow the named adjacent route. If it is a
  legacy page without Routing, use its available sections only to locate the
  exact source and tests, and include page reconciliation in the task scope.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

## Frame card

Use the semantic analysis protocol in `.agentic/AGENTS.md`, then fill the
journal's `## Frame` section. Keep entries concise, but preserve every material
unknown instead of completing the picture by invention:

```text
Problem:
Desired outcome:
Actors:
Primary scenario: trigger -> system action -> observable result
Examples:
Counterexamples:
In scope:
Out of scope:
Constraints:
Success signals:
Evidence: STATED; OBSERVED with paths; INFERRED; UNKNOWN
Assumptions:
Unknowns:
Decision-blocking questions:
Proposed behaviors:
Path and reason:
```

**Steps:**

1. **Analyze.** Extract the user's problem, desired outcome, actors, primary
   scenario, examples, constraints, success signals, explicit scope, and
   exclusions. Preserve the user's terms where changing them could change
   meaning.
2. Locate the smallest sufficient repository evidence. Use
   `python .agentic/aegis.py components` to narrow broad discovery when the
   owning page is not already known, then use each current component page's
   `## Routing` selection signals to confirm ownership and its
   starting seams. For a legacy page, use the available sections as provisional
   orientation and record the missing routing contract for validation. Then
   inspect the exact interfaces, representative source, and tests. Record
   repository claims as `OBSERVED` with paths; mark conclusions as `INFERRED`.
   Do not edit product files.
3. **Challenge.** Look for contradictions between the request, existing
   behavior, requirements, and repository rules. Identify missing triggers,
   observers, boundaries, failure cases, permissions, compatibility effects,
   security or data concerns, and assumptions. Ask only decision-blocking
   questions; carry other gaps as `UNKNOWN`.
4. Draft the Frame card before performing branch or journal administration.
   Include at least one concrete example or record that none was supplied,
   and add a counterexample when it materially clarifies the boundary.
5. Choose the path. Take the **quick path** only when all of these hold: no
   new externally observable behavior, no new interface or data format, no
   new dependency, an existing requirement already covers the behavior, and
   no security- or data-handling behavior changes. Otherwise take the full
   path. Record one row per criterion as `criterion | yes | no | evidence`;
   any `no` or unknown selects the full path.
6. Decide whether the work is large enough for optional children. Use children
   only for independently scoped work that can remain an ordinary governed
   task; keep small or tightly coupled work in the parent.
7. Establish the branch. If you are on the repository's default branch, create
   a task branch now (`git checkout -b task/<short-slug>`, or the repository's
   convention), unless current user or repository instructions explicitly
   require the existing branch. Record that exception. The journal's
   `branch:` header must match `git branch --show-current`.
8. Create the journal:
   `python .agentic/aegis.py task "<title>" --type feature`
   (`--type fix` or `--type change` as appropriate).
9. Fill the journal header and copy the provisional Frame card into its
   `## Frame` section. Leave `requirements:` empty until `specify`
   (quick path: fill it now with the existing requirement IDs).
10. Keep the detailed scope, exclusions, unknowns, path analysis, and proposed
    behaviors in `## Frame`. Append one concise `frame` outcome line to
    `## Log`, naming the chosen path and whether scope was accepted or paused.
    Put durable authority or scope decisions in Rulings instead of repeating
    them in the Log.
11. **Audit.** Check that every material claim is classified, every proposed
    behavior supports a success signal, no unknown became invented behavior,
    and scope, exclusions, examples, and path agree. Copy the Done checklist.
12. Checkpoint mode: present the Frame card, chosen path, proposed behaviors,
    assumptions, decision-blocking questions and the `frame` Stage-boundary
    choices from `AGENTS.md`; refresh the waiting Handoff and paused Stage
    report, then stop. Describe the requested decision as scope acceptance, not implementation.
    Autopilot records the same concise frame outcome and
    continues without the intermediate menu.
13. After the user chooses to continue, or immediately in autopilot, record
    scope acceptance, set `stage: specify` (full path) or `stage: build`
    (quick path), and replace `## Done checklist` with the next stage's Done
    when list.

**Outputs:**

- `.agentic/tasks/TASK-<id>.md` - created with a complete header, durable
  Frame card, evidence classifications, one frame outcome line, and current
  checklist.

**Done when:**

- [ ] Frame card states the problem, outcome, actors, scenario, scope,
      examples, constraints, success signals, evidence, and unknowns
- [ ] material claims classified as stated, observed, inferred, or unknown
- [ ] contradictions and decision-blocking questions resolved or presented
- [ ] path chosen (`full` or `quick`) with its reason logged
- [ ] task branch established; `branch:` header matches the checkout
- [ ] task journal created with a complete header
- [ ] proposed behaviors map to the desired outcome and success signals
- [ ] scope confirmed by the user (checkpoint mode) or logged (autopilot)
- [ ] `stage:` advanced

**Skip when:** Never. Every task starts here, however small. If the prompt
names an existing task, do not frame it again — follow the resume
procedure in `.agentic/AGENTS.md` instead.

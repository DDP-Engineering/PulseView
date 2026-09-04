<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 3 — design

**Purpose:** Write a short design note for non-trivial work, so that
`build` has a sufficiently constrained implementation path, material open
decisions remain explicit, and a reviewer can see why the shape was chosen.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`.
- Every requirement listed on its `requirements:` line, and their specs.
- `python .agentic/aegis.py components` when boundaries or adjacent ownership
  leave an in-scope component page unnamed.
- The knowledge page for each component you will touch:
  `.agentic/knowledge/<component>.md`. Use `## Change map` for the relevant
  edit-and-test seam when present, then check the named exact source and tests.
  For a legacy page without Routing, use its available sections only as
  provisional orientation and leave migration to validation.

**Stage report (completion or pause):** At this boundary, record only durable
events allowed by the journal contract, update the header and checklist, and
refresh the single `## Stage report` section in this task journal:
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
the journal header/checklist, dedicated durable sections, and relevant log
entries (stage outcomes, blockers, material changes and consolidated evidence);
follow links to needed records.
This stage's required full reads still apply. Use linked requirements and
source as needed, not the whole register. Do not act on missing, stale, or
shortened reporting without reviewing the full journal information.

**Steps:**

1. Decide whether a note is needed; see Skip when. If not, record the reason in
   `## Design` and mark every coverage-table row `no design impact`.
2. **Analyze** the Frame, requirements, specs, current component knowledge,
   and representative implementation seams. Preserve the page's boundaries
   and invariants; use its `## Change map` only as a route, then verify the
   exact implementation. **Challenge** contradictions, infeasible constraints,
   implicit coupling, missing failure behavior, and unresolved decisions
   before choosing a shape.
3. Write the note under the journal's existing `## Design` heading. 30 lines is the default,
   not a hard limit: use the shortest record that makes
   the known implementation path sufficiently constrained. Add proportionate
   depth when the task changes an interface, data or state, trust boundary,
   concurrency, dependency, migration, compatibility, deployment, or recovery.
4. Cover the applicable parts in this order:

   - **Requirements coverage** - each ID maps to a decision or `no design impact`.
   - **Component responsibilities** - ownership and boundaries.
   - **Interfaces and contracts** - inputs, outputs, defaults, and errors.
   - **Data ownership and state transitions** - persistence, lifecycle, and units.
   - **Execution flow** - the primary path and material asynchronous work.
   - **Failure recovery** - partial failure, retries, cleanup, and idempotency.
   - **Security and trust boundaries** - only where relevant.
   - **Concurrency and ordering** - only where relevant.
   - **Compatibility and migration** - rollout, rollback, or deliberate break.
   - **Observability and operations** - evidence needed to diagnose behavior.
   - **Test seams** - where each requirement's failing and regression tests attach.
   - **Alternatives and tradeoffs** - meaningful rejected options and reasons.
   - **Expected files**, **Risks**, and **Open decisions**.

5. Cite the forcing requirement ID next to every requirement-driven decision;
   cite a named technical constraint for decisions that no requirement forces.
   Never convert an open product decision into an implementation choice.
6. Update the journal's `## Requirement coverage` table so every requirement
   names its design decision, test seam, or `no design impact`.
7. List expected files and update each requirement's `affected_paths`.
   For child tasks, define non-overlapping child scopes and requirement links;
   integration ownership remains with the parent.
8. When component structure will change, add a compact `### Proposed
   architecture - TASK-<id>` diagram to this task's Design. Use searchable
   code names and directional edges. During design, do not replace the current diagram
   in `.agentic/knowledge/<component>.md`; validate reconciles that canonical
   current-state page after the built code matches. Behavior-only changes may
   state that no architecture drawing is owed.
9. Keep requirement-specific format, protocol, algorithm, or edge behavior in
   the linked spec rather than duplicating it in the task design.
10. **Audit** traceability, feasibility, interfaces, state ownership, failure
    behavior, compatibility, verification seams, risks, and open decisions.
    Run `python .agentic/aegis.py check` and fix format errors.
11. Append one concise `design` outcome line pointing to `## Design` and any
    linked spec; do not copy decisions into the Log. Tick the checklist, set
    `stage: build`, and replace `## Done checklist` with the build stage's Done
    when list.

**Outputs:**

- `## Design` section in the task journal.
- Proposed architecture in the task journal where component structure changes;
  canonical current-state knowledge remains unchanged until validate.
- Updated `affected_paths` on the linked requirements.
- Updated spec sections where the detail belongs to the behavior.

**Done when:**

- [ ] design note written, or its absence justified in one line
- [ ] applicable component, interface, state, failure, security, concurrency,
      compatibility, migration, observability, and operational effects covered
- [ ] each decision cites a requirement ID or named technical constraint
- [ ] every requirement maps to a decision and test seam, or no design impact
- [ ] meaningful alternatives, risks, and open decisions recorded
- [ ] `affected_paths` match the expected file list
- [ ] proposed architecture is in the task when structure changes; current
      component knowledge remains true until validate
- [ ] `stage: build`

**Skip when:** The quick path; or the work is a single-file change with no
new interface, data format, or dependency; or the spec already answers
"how". Skipping is a judgement recorded in `## Design` and the concise design
outcome, not a step silently dropped.

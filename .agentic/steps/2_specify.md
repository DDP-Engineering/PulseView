<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 2 — specify

**Purpose:** Capture each behavior this task adds or changes as a durable,
independently verifiable requirement, and add a spec only where the
requirement alone is not enough to build from.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`.
- `.agentic/templates/requirement.toml` and `.agentic/templates/spec.md`.
- Existing requirements whose `affected_paths` touch the same files — you
  may be updating one rather than writing a new one.
- `python .agentic/aegis.py components` when the frame did not already name
  every component page needed for the behavior being specified.
- The knowledge page for each component in scope. Read its
  `## Purpose and boundaries`, `## Public interface`, `## Invariants`, and
  `## Key behaviors` sections before confirming each claim against the exact
  source and tests. If a legacy page lacks one or more sections, use only the
  available sections, do not infer the missing claims, and record page
  reconciliation as in-scope validation work.

**Reporting and resume:** Follow `.agentic/AGENTS.md` sections "Resume a task",
"Rulings and handoffs", and "Stage reporting". At transitions and pauses,
update the current checklist, minimal Handoff and Stage report, then show
`summary TASK-<id>`. Read required durable evidence; missing or shortened
context requires review. This adds no approval stop and never defers a material
deviation notice. Reuse unchanged instructions already read in this session.

**Steps:**

1. **Analyze.** Read the accepted `## Frame` and create a **Behavior
   inventory** before writing requirement files:

   `Frame outcome | Actor/system | Trigger or state | Response | Positive case | Boundary or failure | Observable result`

   Cover every proposed behavior, success signal, material constraint, and
   relevant negative or recovery case. Mark unsupported detail as unknown.
2. Split only when responses can vary, fail, change, or be verified
   independently. Keep clauses together when they form one inseparable atomic
   observable outcome. Final requirement prose normally contains one `shall`.
3. Reuse before creating, but compare semantics rather than titles. Reuse only
   when actor/system, trigger or state, response, constraints, and observable
   outcome match. Otherwise create a new requirement or deliberately revise the
   old one and record the behavioral change.
4. Create each new file:
   `python .agentic/aegis.py req <category> "<title>"`.
   Categories are `functional ux nfr security data platform reliability test`.
5. Fill `schema`, `id`, `title`, `status`, `requirement`, and
   `verification`. Start new work as `draft`; build activates it after
   tests are linked.
6. Write self-contained prose. Prefer the EARS shape that fits, preserve a
   named trigger or state, and do not add design choices merely to remove an
   unknown. A reader with no other context must be able to understand and
   check the behavior.
   State the positive observable outcome, including explicit responses to error
   conditions. Keep one current contract rather than rejected alternatives,
   removed features, adoption annotations, or before/after history. Draft
   requirements/specs hold agreed proposals; project and component context
   continues to describe the actual implementation until the proposal is built.
7. Derive concrete verification before reducing it to the TOML field:

   ```text
   Setup:
   Input or trigger:
   Action:
   Observable oracle:
   Boundary or failure:
   Automation: automated | manual | inspection
   ```

   The final field names the observation that settles the behavior and must
   not add conditions absent from the requirement or spec. Use `Manual:` or
   `Inspection:` only when the behavior is genuinely unautomatable.
8. Set `affected_paths` to the best current evidence-based estimate. Leave
   `linked_tests` empty until build.
9. Add a spec when exact build behavior needs a schema, wire or file format,
   protocol, state machine, non-obvious algorithm, multi-step interaction,
   compatibility rule, migration, or detailed error semantics. Record material
   assumptions and open decisions in the spec rather than silently choosing.
10. Fill the journal's `## Requirement coverage` table:

    `Frame outcome | Atomic behavior | Requirement | Positive case | Boundary or failure | Verification | Design decision or no impact`

    A broad Frame outcome may produce several atomic behavior rows. Each
    in-scope atomic behavior maps to exactly one requirement; explicitly mark
    deliberate many-to-one mappings and explain why the behaviors remain one
    inseparable observable outcome.
11. **Challenge.** Review the set for missing Frame outcomes, duplicated or
    overlapping behavior, a semantic conflict with existing requirements,
    inconsistent terminology, unhandled boundaries, and verification that
    merely restates prose. Resolve or preserve every material unknown.
12. Put every requirement ID on the journal's `requirements:` line. Append one
    consolidated `specify` outcome line with created, revised, reused, and
    retired counts; name individual IDs only for a retirement or material scope
    change. Keep requirement detail in the files and coverage table.
13. **Audit.** Read the requirements as a set in coverage-table order and
    confirm that every atomic behavior maps to exactly one requirement and
    satisfying all requirements would satisfy the accepted Frame without
    adding behavior. Run `python .agentic/aegis.py check` and fix
    every format error.
14. In checkpoint mode, present the `specify` Stage-boundary choices from
    `AGENTS.md`, refresh the waiting Handoff and paused Stage report, then stop
    before transition. After the user chooses to continue, or immediately in
    autopilot, tick the checklist, set `stage: design`, and replace
    `## Done checklist` with the design stage's Done when list.

**Retiring a requirement.** When a behavior is deliberately removed, do
not delete its file: set `status = "retired"` and append one line to the
prose (`Retired <date>: <why>`). **Keep the retired id on your own
journal's `requirements:` line** — it is the evidence of what this task
retired, and the report names it. Never edit other tasks' journals; if
another open task lists the same id, say so at delivery so its owner
decides. `check` stops applying active-only rules to retired files, so
the build stage's "every requirement ends `active`" rule reads as
"active, or retired by this task on purpose". Removing the behavior
itself is a normal task (`--type change`) whose scope says so.

**Outputs:**

- `.agentic/requirements/<category>/REQ-*.toml` - new or updated.
- `.agentic/specs/REQ-*.md` - only where genuinely needed.
- Journal `requirements:` line and `## Requirement coverage` updated, with one
  consolidated specify outcome in the Log.

**Done when:**

- [ ] every in-scope behavior has exactly one requirement
- [ ] behavior inventory covers positive, boundary, failure, and recovery cases
- [ ] required fields filled and prose is self-contained
- [ ] independently variable or verifiable responses are split; inseparable
      atomic outcomes remain together
- [ ] each final requirement normally uses one "shall", in an EARS shape
      where one fits
- [ ] verification names setup, trigger, action, observable oracle, and a
      relevant boundary or failure
- [ ] `affected_paths` set to the best current guess
- [ ] specs written for exact contracts that the requirement cannot carry alone
- [ ] Requirement coverage maps every Frame outcome without overlap or gaps
- [ ] semantic conflicts, assumptions, and unknowns resolved or recorded
- [ ] journal `requirements:` line lists every ID
- [ ] `check` reports no format errors
- [ ] `stage: design`

**Skip when:** The quick path — `frame` already named the existing
requirements, and `build` will update them. Also skip for a change with no
externally observable effect (a refactor fully covered by existing
requirements); include that judgement in the consolidated specify outcome.

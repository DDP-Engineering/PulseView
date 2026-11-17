<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 3 — design

**Purpose:** Choose how to build the requirements, briefly, so build follows a
constrained path and a reviewer can see why it was chosen.

**Read:**

- The journal, every requirement on its `requirements:` line, and their specs.
- The knowledge page of each component you will touch
  (`python .agentic/aegis.py components` lists them); use its `## Change map`
  as a route, then check the exact source and tests.
- The `Diagrams:` line of `python .agentic/aegis.py brief TASK-<id>`.

**Steps:**

1. Skip the note when the change stays in one file with no new interface,
   data format or dependency, or when a spec already says how: write the
   reason in `## Design` and finish with
   `python .agentic/aegis.py advance TASK-<id> --skipped --reason "<why>"`.
2. **Analyze** the Frame, the requirements and the current seams, keeping
   each component's boundaries and invariants. **Challenge** contradictions,
   infeasible constraints, hidden coupling and missing failure behavior
   before choosing a shape. A new interface that calls an existing function
   does not conflict with that function's contract.
3. Write the note in `## Design`, about 30 lines, under these headings:
   - **Approach**: the chosen shape and its primary flow, why, and any
     rejected alternative worth knowing.
   - **Interfaces and data**: inputs, outputs, defaults, errors and failure
     recovery, state and ownership.
   - **Files and test seams**: the files to change and where each
     requirement's tests attach.
   - **Risks and open decisions**: security, concurrency, compatibility or
     migration only when relevant.
   - **Requirement map**: each requirement ID with its decision, or
     `no design impact`.
4. Cite the requirement ID behind each requirement-driven decision, or the
   named technical constraint behind any other. An open product decision
   stays open; do not settle it as an implementation choice.
5. Fill the coverage table's design column and update each requirement's
   `affected_paths` from the file list. For child tasks, give each child a
   non-overlapping scope and its requirements.
6. Leave knowledge pages unchanged; validate updates them once the code
   exists.
7. **Audit** traceability, feasibility, interfaces, failure behavior and test
   seams, then run `python .agentic/aegis.py check` and fix format errors.
8. When `brief` shows `Diagrams: draw ...`, follow `.agentic/steps/diagrams.md`
   now.

**Finish:**

- Checkpoint: `python .agentic/aegis.py pause TASK-<id> --next "Accept the
  design and continue to build?"`; show the summary, any diagrams as
  `diagrams.md` describes, and the choices: continue, revise, return to
  specify, or stop. When the user continues, `advance TASK-<id>` and read the
  next step file.
- Autopilot: `advance TASK-<id>` and read the next step file.

**Done when:**

- [ ] design note written under the five headings, or its skip justified
- [ ] each decision cites a requirement ID or a named technical constraint
- [ ] every requirement maps to a decision and test seam, or no design impact
- [ ] risks and open decisions recorded
- [ ] `affected_paths` match the expected files
- [ ] knowledge pages unchanged

**Skip when:** Step 1 gives the one skip rule.

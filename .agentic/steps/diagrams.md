<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Design diagrams (optional)

**Purpose:** Show the human operator the proposed implementation before
build writes code. Read this file only when the `Diagrams:` line of
`python .agentic/aegis.py brief TASK-<id>` says `draw`. A task with no design
note (a design recorded as skipped) draws nothing.

**Steps:**

1. Draw exactly the types the `Diagrams:` line names. `brief` applies
   `[diagrams]` already: only `enabled = true` draws, a missing or non-list
   `types` means `structure`, and an empty or unknown-only list draws
   nothing, with no file and no link.
2. From the final `## Design` text and the source you already read, draw one
   Mermaid diagram for each listed type that the design covers:

   | Type | Header | Draw when the design | Show |
   |---|---|---|---|
   | `structure` | `flowchart LR` or `flowchart TD` | adds or changes components, modules, files, or how they connect | the parts the change touches and their calls or data flow |
   | `sequence` | `sequenceDiagram` | has an execution flow across three or more participants, a process boundary, or asynchronous work | the order of calls and responses on the primary path |
   | `state` | `stateDiagram-v2` | adds or changes a lifecycle, a status field, or state transitions | states and the transitions between them |

   For a listed type the design does not cover, write that type's heading
   with one line under it: `Not drawn: <reason>.`
   Before drawing structure, classify each node from an explicit Design edit:
   new node = added; changed implementation/responsibility = changed; removed
   node = removed; reused unchanged node = no class. Record this small map in
   the diagram file so the diagram can be checked against it. Participation in
   the task or a new incoming edge does not make an existing node changed.
3. Write the whole file `.agentic/tasks/diagram_TASK-<id>.md` each time design
   reaches this step:

   ````markdown
   # TASK-<id> diagrams

   Illustrates `## Design` in `TASK-<id>.md`. The Design text is authoritative.

   ## Structure

   ```mermaid
   flowchart LR
       classDef added fill:#e1f5ee,stroke:#0f6e56
       classDef changed fill:#faeeda,stroke:#854f0b
       classDef removed stroke-dasharray:4 3
       cli["cli.parse_args"]:::changed ==> report["report.render"]:::added
       report ==> store[("task journal")]
       cli -.-> legacy["report.legacy_text"]:::removed
   ```

   ## Sequence

   Not drawn: the change runs in one process with no asynchronous work.
   ````

4. Compare every structure-node class against that map and the saved Design.
   In particular, a node described as unchanged has no added/changed/removed
   class. Classify each edge independently. Fix any mismatch in the diagram
   before copying its blocks into a checkpoint response; do not change the
   Design to justify an accidental diagram marker.
5. Add this line to `## Design` unless it is already there:
   `Diagrams: [diagram_TASK-<id>.md](diagram_TASK-<id>.md)`.

6. **Checkpoint presentation:** when this stage wrote diagrams in checkpoint
   mode, assemble the final response as: the summary `pause` printed, in a
   text fence; then each saved heading and complete Mermaid fence copied
   verbatim; then the design choices. Include the blocks even when unresolved
   Design decisions prevent build. A link does not display a proposal. Read
   the saved file and check the outgoing response for every block before
   sending it.
7. **Autopilot presentation:** name the file in `--changed`; omit the diagram
   display and add no stop. An explicit stop at design still completes the
   diagrams and leaves the task at design.

**Drawing rules:**

- The Design text is authoritative and the diagram only illustrates it. Draw
  nothing the Design does not state.
- Name nodes and participants after searchable code names. Give each node a
  simple id of letters, digits and underscores, with its label in double
  quotes.
- In structure diagrams, use `:::added`, `:::changed` or `:::removed` only for
  nodes the Design proposes to add, modify or remove, with the corresponding
  `classDef` lines above; include all three definitions for a consistent legend.
  Leave a reused unchanged node unstyled, even when it
  receives a new incoming edge. Draw added edges as `==>`, removed edges as
  `-.->`, and unchanged edges as `-->`. Classify nodes and edges separately
  against the proposed Design; a new connection alone does not modify its node.
  Do not use removed-edge notation to distinguish a new test or dependency;
  those edges are added even when their target is unchanged.
- Keep each diagram to about 15 nodes. Split a larger change into one
  structure diagram per component.
- Put one diagram in each fenced block, using only the headers in the table
  above.

Nothing checks this file. It is not evidence, it is no Done when item, and no
later stage or review reads it.

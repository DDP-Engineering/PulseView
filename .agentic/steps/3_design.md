<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 3 — design

**Purpose:** Write a short design note for non-trivial work, so that
`build` has one decision-free path to follow and a reviewer can see why
the shape was chosen.

**Read first:**

- The task journal `.agentic/tasks/TASK-<id>.md`.
- Every requirement listed on its `requirements:` line, and their specs.
- The knowledge page for each component you will touch:
  `.agentic/knowledge/<component>.md`.

**Steps:**

1. Decide whether a note is needed at all — see "Skip when". If it is
   not, log that judgement in one line and move on.
2. Write the note in the journal under a `## Design` heading. Keep it
   under 30 lines; it is a decision record, not a document.
3. Cover, in this order: components touched, the interface change (public
   functions, commands, formats), data or storage decisions, and the one
   alternative you rejected with the reason.
4. Cite the requirement ID next to each decision, so a later reader can
   trace a choice back to the behavior that forced it.
5. Name the test seams: the place a failing test will attach for each
   requirement. `build` starts from these.
6. List the files you expect to create or modify, and update each
   requirement's `affected_paths` to match.
7. For each component whose internal shape this task changes, open its
   `.agentic/knowledge/<component>.md` and revise the `## Architecture`
   diagram to the shape it will have **after the change** — new nodes and
   arrows drawn as intended, removed ones taken out. Say in one line under
   the diagram that it is the intended shape and name this task, so a
   reader between design and delivery is not misled by a picture of code
   that does not exist yet; drop that line at `validate`, once the code
   matches. A component with no page yet, or a task that only changes
   behavior inside an existing shape, owes nothing here — say which in
   the log and move on.
8. Keep requirement-specific detail in the spec instead of the journal
   when it belongs to the behavior rather than to this task.
9. Run `python .agentic/aegis.py check`; fix errors.
10. Tick the checklist, set `stage: build`, and **replace
    `## Done checklist`** with the build stage's "Done when" list from
    `4_build.md` — the checklist always shows the current stage's items.

**Outputs:**

- `## Design` section in the task journal.
- Revised `## Architecture` diagrams on the knowledge pages of components
  whose shape this task changes, drawn as they will be afterwards.
- Updated `affected_paths` on the linked requirements.
- Updated spec sections where the detail belongs to the behavior.

**Done when:**

- [ ] design note written, or its absence justified in one line
- [ ] interface, data, and rejected alternative covered
- [ ] each decision cites a requirement ID
- [ ] test seams named for every requirement
- [ ] `affected_paths` match the expected file list
- [ ] `## Architecture` revised to the shape it will have after the change,
      for every component whose structure this task changes — or logged as
      owing nothing
- [ ] `stage: build`

**Skip when:** The quick path; or the work is a single-file change with no
new interface, data format, or dependency; or the spec already answers
"how". Skipping is a judgement you record, not a step you silently drop.

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
- The knowledge page for each component in scope.

**Stage report (completion or pause):** After updating the log, header and
checklist, refresh the single `## Stage report` section in this task journal:
`stage`, `result`, `current`, `changed`, `evidence`, `issues`, `next`,
`needs_user` (plain one-line fields, no fences). Record the completed stage
separately from `current`, which must match the header after any transition;
use `paused` when waiting or ending a session. Other results are `in_progress`,
`completed`, `blocked`, `skipped`. Run
`python .agentic/aegis.py summary TASK-<id>` and copy its block before any
detailed explanation. Unknown values stay blank (`not recorded`); refresh
stale records and read omitted details before continuing. Preserve existing
approval stops and immediate deviation notices; this report adds no new stop.

**Resume context:** Read the summary first, then this stage's instructions,
the journal header/checklist and relevant log entries (scope, user limits,
unresolved issues, decisions and evidence); follow links to needed records.
This stage's required full reads still apply. Use linked requirements and
source as needed, not the whole register. Do not act on missing, stale, or
shortened reporting without reviewing the full journal information.

**Steps:**

1. Split the scope into behaviors. One requirement = one behavior that can
   be verified on its own. If a sentence needs "and", it is two.
2. Reuse before creating. If an existing requirement already describes the
   behavior, update it (and its `updated` date) instead of adding a
   duplicate.
3. Create each new file:
   `python .agentic/aegis.py req <category> "<title>"`
   Categories: `functional ux nfr security data platform reliability test`.
4. Fill the required fields: `schema`, `id`, `title`, `status`,
   `requirement`, `verification`. Start `status = "draft"`; `build`
   promotes it to `"active"` once tests are linked.
5. Write the prose self-contained. A reader with no other context must be
   able to understand and check it: no ticket numbers, no run IDs, no
   "see the other requirement". `check` flags those patterns.
6. Prefer an **EARS** shape — the template lists all five. Pick the one
   that fits:
   - `The <system> shall <response>.` — always true
   - `When <trigger>, the <system> shall <response>.` — event
   - `While <state>, the <system> shall <response>.` — state
   - `If <condition>, then the <system> shall <response>.` — unwanted
   - `Where <feature is included>, the <system> shall <response>.`
   A stated trigger or condition is what the test has to arrange, so
   naming it here is what makes the behavior testable. Two "shall"
   clauses means two behaviors — split them. Do not contort prose to fit
   a pattern: a constraint that reads better plainly is better plainly.
7. Make `verification` concrete — the observation that settles whether the
   behavior holds, not a restatement of the requirement. It should follow
   from the requirement's trigger and response, not add new conditions.
   When no test can settle it — a look-and-see judgement, an install on
   clean hardware — start the field with `Manual:` or `Inspection:` and
   name the method. `check` then records it as verified by hand rather
   than as a test still owed. Use it because the behavior is genuinely
   unautomatable, never to quiet a warning about a test you could write.
8. Set `affected_paths` to your best current guess. Leave `linked_tests`
   empty; `build` fills it.
9. Add a spec only when the requirement alone is not buildable (a format,
   a protocol, a non-obvious algorithm). Copy
   `.agentic/templates/spec.md` to `.agentic/specs/<REQ-ID>.md` and set
   `spec = "specs/<REQ-ID>.md"` in the requirement.
10. Put every requirement ID on the journal's `requirements:` header line,
   comma-separated, and log what you created or changed.
11. Run `python .agentic/aegis.py check` and fix every format error it
    reports. A draft requirement's empty `linked_tests` is intentionally
    silent until build; if that warning appears now, the requirement was
    activated prematurely and its status must be corrected.
12. Tick the checklist, set `stage: design`, and **replace
    `## Done checklist`** with the design stage's "Done when" list from
    `3_design.md` — the checklist always shows the current stage's items.

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

- `.agentic/requirements/<category>/REQ-*.toml` — new or updated.
- `.agentic/specs/REQ-*.md` — only where genuinely needed.
- Journal `requirements:` line and log updated.

**Done when:**

- [ ] every in-scope behavior has exactly one requirement
- [ ] required fields filled and prose is self-contained
- [ ] each requirement states one behavior (one "shall"), in an
      EARS shape where one fits
- [ ] `affected_paths` set to the best current guess
- [ ] specs written only where the requirement was not buildable alone
- [ ] journal `requirements:` line lists every ID
- [ ] `check` reports no format errors
- [ ] `stage: design`

**Skip when:** The quick path — `frame` already named the existing
requirements, and `build` will update them. Also skip for a change with no
externally observable effect (a refactor fully covered by existing
requirements); log that judgement in one line.

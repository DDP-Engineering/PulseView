<!--
SPDX-FileCopyrightText: 2026 DDP Engineering
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Stage 2 — specify

**Purpose:** Record each behavior the task adds or changes as one durable,
verifiable requirement, with a spec only where the requirement cannot carry
the detail alone.

**Read:**

- The journal's accepted `## Frame` and its Rulings.
- `.agentic/templates/requirement.toml`, and `.agentic/templates/spec.md`
  when a spec is needed.
- The requirements that already govern the code in scope:
  `python .agentic/aegis.py explain <path>` lists them. You may revise one
  instead of writing a new one.
- For each component in scope, its knowledge page's `## Purpose and
  boundaries`, `## Public interface`, `## Invariants` and `## Key behaviors`,
  confirmed against the exact source and tests;
  `python .agentic/aegis.py components` lists the pages.

**Steps:**

1. **Analyze.** List the atomic behaviors in the journal's `## Requirement
   coverage` table, one row each. A behavior is atomic when it has one
   trigger or state and one observable response. Each response that can fail
   on its own — every error response included — is its own row and its own
   requirement. Cover each proposed behavior and success signal the Frame
   accepted, with its boundary, failure and recovery cases.
2. For each row, reuse an existing requirement only when actor, trigger,
   response, constraints and observable outcome all match; otherwise revise
   it deliberately or create one with `python .agentic/aegis.py req
   <category> "<title>"` (functional, ux, nfr, security, data, platform,
   reliability or test).
3. Write the requirement as one self-contained EARS sentence with one
   "shall", such as "When <trigger>, the <system> shall <response>." State
   the current positive outcome, including the explicit response to each
   error. New requirements start as `status = "draft"`; build activates them.
4. Write `verification` from setup, trigger, observable oracle and a boundary
   or failure case, adding nothing the requirement does not say. Use
   `Manual:` or `Inspection:` only for behavior no test can settle.
5. Set `affected_paths` to the best current estimate; leave `linked_tests`
   empty until build.
6. Write a spec in `.agentic/specs/` only for exact formats, protocols, state
   machines, algorithms, migrations or detailed error semantics, and keep its
   open decisions explicit.
7. **Challenge.** Look for Frame outcomes with no row, rows that overlap,
   conflicts with existing requirements, unhandled boundaries, and
   verification that only restates the prose. Keep each unresolved unknown
   visible.
8. Put every requirement ID on the journal's `requirements:` header line, run
   `python .agentic/aegis.py check`, and fix every format error.
9. **Audit.** Read the requirements in table order: satisfying all of them
   satisfies the accepted Frame, and adds nothing to it.

**Retiring a requirement:** set `status = "retired"`, append
`Retired <date>: <why>` to its prose, keep its ID on this journal's
`requirements:` line, and say it as a deviation. Never delete the file or
edit another task's journal.

**Finish:**

- Checkpoint: `python .agentic/aegis.py pause TASK-<id> --next "Accept these
  requirements and continue to design?" --changed "<n> created, <m> revised"`;
  show the summary and the choices: continue, revise, return to frame, or
  stop. When the user continues, `advance TASK-<id>` and read the next step
  file.
- Autopilot: `advance TASK-<id> --changed "<n> created, <m> revised"` and
  read the next step file.

**Done when:**

- [ ] every accepted behavior is one coverage row with exactly one requirement
- [ ] each error or failure response has its own requirement
- [ ] each requirement is one self-contained "shall" sentence
- [ ] verification names setup, trigger, oracle and a boundary or failure
- [ ] specs written only where the requirement cannot carry the detail
- [ ] conflicts, assumptions and unknowns resolved or recorded
- [ ] every ID on the journal's `requirements:` line; `check` shows no
      format errors

**Skip when:** The requirements frame put on the `requirements:` line already
cover the whole change, such as restoring behavior they require, and it adds
nothing they do not say: `advance TASK-<id> --skipped --reason "<why>"`.

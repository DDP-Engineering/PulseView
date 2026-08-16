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
- `python .agentic/aegis.py status` — an open task may already cover this.
- The knowledge page for the area named in the ask, if one exists:
  `.agentic/knowledge/<component>.md`.

**Steps:**

1. Restate the ask in one or two sentences, in your own words. Name what
   is in scope and, explicitly, what is not.
2. Locate the area: which components and which files this will touch.
   Skim them; do not edit anything yet.
3. Choose the path. Take the **quick path** (`frame → build → validate → deliver`)
   only when all of these hold: no new externally observable behavior, no
   new interface or data format, no new dependency, an existing
   requirement already covers the behavior you are changing, and the
   change touches no security- or data-handling behavior — those always
   take the full path. Otherwise take the full path.
4. Establish the branch. If you are on the repo's default branch, create
   a task branch now (`git checkout -b task/<short-slug>`, or the repo's
   own naming convention). The journal's `branch:` header must match
   `git branch --show-current` — later sessions verify this on resume.
5. Create the journal:
   `python .agentic/aegis.py task "<title>" --type feature`
   (`--type fix` or `--type change` as appropriate).
6. Fill the journal header: `stage`, `type`, `path`, `branch`, `opened`.
   Leave `requirements:` empty until `specify` (quick path: fill it now
   with the existing requirement IDs you will touch).
7. Write the scope, the exclusions, and the path decision with its reason
   into `## Log` as one or two lines.
8. List the requirements you expect to create or update, one line each,
   in the log — these are the proposal you present at the checkpoint.
9. Copy the "Done when" checklist below into `## Done checklist`.
10. Checkpoint mode: present the scope, the chosen path, and the proposed
    requirements, and wait for a yes before continuing. Autopilot: log the
    same three things and continue without stopping.
11. Set `stage: specify` (full path) or `stage: build` (quick path), and
    **replace `## Done checklist`** with the next stage's "Done when" list
    (from `2_specify.md`, or `4_build.md` on the quick path). The
    checklist always shows the current stage's items — that is what
    resume relies on.

**Outputs:**

- `.agentic/tasks/TASK-<id>.md` — created, header filled, first log lines
  written, checklist copied in.

**Done when:**

- [ ] scope and exclusions written in the log
- [ ] path chosen (`full` or `quick`) with its reason logged
- [ ] task branch established; `branch:` header matches the checkout
- [ ] task journal created with a complete header
- [ ] expected requirements listed
- [ ] scope confirmed (checkpoint mode) or logged (autopilot)
- [ ] `stage:` advanced

**Skip when:** Never. Every task starts here, however small. If the prompt
names an existing task, do not frame it again — follow the resume
procedure in `.agentic/AGENTS.md` instead.

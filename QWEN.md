# QWEN.md

<!-- AEGIS:BEGIN (managed by .agentic/aegis.py init) -->

## AEGIS workflow

The full contract is `.agentic/AGENTS.md` - read it before starting work.
This digest is enough to act on if you read nothing else.

AEGIS applies only to software development operations. Do not use it for
repository operations or package and delivery operations; follow the
repository's own procedures for those instead.

Stages, one step file each in `.agentic/steps/`: **frame** (agree scope,
open the task journal) -> **specify** (write the requirement, and a spec
when useful) -> **design** (a short note for non-trivial work) -> **build**
(failing test first, then the implementation, until green) -> **validate**
(review, knowledge, full suite and strict check) -> **deliver** (approval,
report, commit/PR). A small fix or change may take the quick path,
frame -> build -> validate -> deliver.

To resume: `python .agentic/aegis.py status` lists the task journals; run
`python .agentic/aegis.py summary TASK-<id>`, then read that journal's header,
current checklist, and relevant scope, decisions, issues, and evidence in
`## Log`. Open the current stage's step file and continue at its first
unticked item; required full journal reads still apply.

At stage completion or pause, update the journal's `## Stage report` fields
from observed facts, then run `python .agentic/aegis.py summary TASK-<id>` and
copy the block before detail. Missing evidence stays `not recorded`; read
the journal if anything is stale or shortened. This adds no approval stops
and never replaces immediate deviation notices or full delivery evidence.

Artifacts: requirements in `.agentic/requirements/<category>/`, specs in
`.agentic/specs/`, journals in `.agentic/tasks/`, component pages in
`.agentic/knowledge/`. `python .agentic/aegis.py check` is advisory - read
its findings and self-correct; nothing here blocks you mid-flight.

Say a deviation out loud when you record one, as one line -
`DEVIATION <stage>: <what> - <why accepted, or what it costs>` - then carry
on. It never pauses the work and autopilot never suppresses it. You owe one
for an accepted `check` warning, a non-zero exit or a verification you
skipped, an unexpected `anchor`/`evolution` report, a manual method standing
in for an automatable test, a retired requirement, and unrequested work found
in review.

<!-- AEGIS:END -->

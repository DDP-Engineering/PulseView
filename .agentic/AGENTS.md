# AEGIS - project workflow

AEGIS is an advisory, repository-local workflow for durable agent-assisted engineering. It records work without blocking it and never substitutes for explicit approval for Git, publishing, or other external actions.

For each substantive task, create a journal in `tasks/`, then work through: frame, specify, design, build, validate, and deliver. Use the quick path (`frame -> build -> validate -> deliver`) only for a small, clearly bounded change, and record why in its task journal.

Store one requirement per file under `requirements/<category>/`, optional specifications under `specs/`, component knowledge under `knowledge/`, and workflow templates under `templates/`. Keep journals truthful: record scope, decisions, validation performed, and any checks that remain unrun.

Default to checkpoint collaboration: present scope and proposed requirements after framing, then present the validated candidate before any delivery action.


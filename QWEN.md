# QWEN.md

<!-- AEGIS:BEGIN (managed by .agentic/aegis.py init) -->

## AEGIS workflow

This repository uses AEGIS for changes that add or change a durable product
rule: logic, data, security, performance, integrations, or a product-wide UI
rule such as a theme, layout system, accessibility or interaction
convention. For those, read `.agentic/AGENTS.md` first; it routes you to one
step file per stage.

Make other changes directly, with no journal or requirement: a bug fix that
restores intended behavior, a local UI adjustment (one element's position,
spacing, wording or style), a refactor with no behavior change, or a test,
docs or tooling fix. A fix that contradicts an active requirement, adds
behavior, or touches security or data handling uses AEGIS. The user's
explicit choice wins; otherwise start with one line,
`LANE: direct|aegis - <why>`.

- New AEGIS work: run `python .agentic/aegis.py status` (an open task may
  cover it), then follow `.agentic/steps/1_frame.md`.
- An existing task: run `python .agentic/aegis.py brief TASK-<id>` and read
  what its `Read next` line names.

Stages: frame -> specify -> design -> build -> validate -> done; specify and
design have skip rules for work that does not need them. The CLI writes the
journal state:
`advance` finishes a stage, `pause` stops for the user, `log` and `ruling`
record events and decisions. End every session with `advance` or `pause`.

AEGIS guides and never blocks; `python .agentic/aegis.py check` is advisory.
Commits, pushes, merges, tickets, releases and packaging follow the
repository's own procedures, not AEGIS.

Say a deviation when you record one, as one line -
`DEVIATION <stage>: <what> - <why accepted, or what it costs>` - then carry on.

<!-- AEGIS:END -->

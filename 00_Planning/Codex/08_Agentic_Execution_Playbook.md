<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Agentic execution playbook

## Audience

This is the operating contract for Codex, AI assistant, or another coding agent
implementing the plan over multiple sessions. Repository instructions and the
owner's current request always take precedence over this document.

## Start or resume procedure

1. Read the root `AGENTS.md` completely.
2. Read `.agentic/AGENTS.md` and the active stage file after the AEGIS payload
   is repaired.
3. Read the tool-specific root guidance, such as `assistant.md`, when applicable.
4. Run `python .agentic/aegis.py status`; if the CLI is not present, stop the
   implementation and complete P0's AEGIS repair rather than inventing state.
5. Open the active task journal and read its header, log, design, and current
   checklist.
6. Inspect Git status in the root and both upstream submodules. Treat all
   existing changes as user-owned until their origin is known.
7. Read this index and only the current roadmap phase plus directly relevant
   architecture, protocol, build, or test document.
8. Restate the current outcome, gate, allowed mutations, and tests to run in the
   journal or commentary before editing.

## Work-unit rule

Each implementation task must be small enough to satisfy one independently
verifiable behavior and produce a reviewable diff. Good work units include:

- decode one command structure with fixtures;
- add device discovery and lifecycle cleanup;
- expose one family of configuration values;
- decode one packed sample format;
- map one trigger category;
- add one packaging target.

Do not combine protocol guessing, public API design, UI construction, platform
packaging, and release publication in one task.

## Checkpoint markers

Use these literal markers in task checklists and handoffs:

- `[DEVICE]` - the DSO3062L must be connected in a stated safe setup;
- `[HUMAN]` - the owner must decide or perform an interactive action;
- `[ADMIN]` - an operator must deliberately elevate for driver/tool/rule setup;
- `[VENDOR]` - the official Hantek stack is the evidence source, not the
  production runtime.

An agent stops at the marker, reports prerequisites, expected effect, duration,
output path, and rollback, and waits only when the action needs authority or
physical intervention. Read-only preparation and offline work continue where
independent.

## AEGIS stage behavior

### Frame

- Name the exact component and repository boundary.
- State what is in and out of scope.
- Choose full or quick path truthfully; new driver behavior, protocol formats,
  dependencies, security-sensitive parsing, and public APIs use full path.
- Record the owner authority available for Git, hardware, driver changes, and
  external publication.

### Specify

- One requirement per independently testable behavior.
- Distinguish offline fixture verification, device-backed verification, and
  clean-platform verification.
- Mark Linux, Windows, and vendor-reference evidence separately.
- Reference exact affected paths in the root or upstream submodule.

### Design

- State the runtime interface and wire/data decision.
- Name bounds, timeouts, allocation caps, state transitions, and cleanup.
- Cite captured evidence for protocol constants; label hypotheses as hypotheses.
- Never invoke an undocumented SDK export from a guessed signature. Require
  reviewed header/import/call-site evidence before a controlled experiment.
- State the narrow test seam and rejected alternative.

### Build

- Write the failing focused test or fixture assertion first where practical.
- Keep parser/encoder logic isolated from live USB operations.
- Apply root code style to root-owned code and upstream style to upstream code.
- Run focused checks after each coherent edit.
- Do not modify capture evidence to make an implementation test pass; reconcile
  the code, fixture provenance, and protocol interpretation.

### Validate

- Review the diff in the correct repository and confirm no unrelated change.
- Run focused tests, static checks, and the phase gate suite.
- Run hardware tests only when the device, driver binding, and physical setup
  match the test procedure.
- Record every unrun test and platform; never translate "builds" into "works."
- Update protocol documentation, component knowledge, requirements, planning
  decisions, and root/upstream changelogs as applicable.

### Deliver

- Present exact changed files, revisions, tests, hardware evidence, limitations,
  and artifact hashes.
- Ask separately for commit, push, upstream request, or publication authority.
- Never push a root reference to an upstream submodule commit that has not been
  made available in an authorized remote.
- Keep the journal open until the approved delivery action and local close-out
  are truthful.

## Evidence discipline

Use these terms precisely:

- **documented** — appears in a named manual or SDK header;
- **observed** — appears in a captured vendor transaction or device response;
- **inferred** — best explanation of repeated observations, not yet replayed;
- **proven** — independently reproduced by native code and verified against the
  expected hardware outcome;
- **validated on Windows/WinUSB** or **validated on Linux** — exact platform and
  transport completed the stated test;
- **not run** — no claim can be made.

Every protocol constant in production code should trace to a catalogue entry
and capture/test evidence. Avoid comments like "magic" without a reference and
observed role.

## Git and upstream workflow

The root project and each upstream submodule have independent histories.

Before changing an upstream repository:

1. verify its upstream base and fork remote;
2. fetch without rebasing or merging automatically;
3. create the approved task branch;
4. keep commits reviewable in upstream style;
5. run that repository's own tests;
6. update the root submodule reference only after the submodule commit is
   durable in an authorized remote or the owner explicitly accepts a local-only
   reference.

Do not copy GPL source into a root-owned PolyForm file to avoid submodule work.
Do not apply the root legal header to an upstream GPL contribution.

## Hardware checkpoint protocol

Before a device-dependent action, report:

- requested physical connection and safe signal setup;
- expected Windows/Linux driver binding;
- whether the Hantek application must be open or closed;
- whether the action is read-only, volatile configuration, driver replacement,
  or potentially nonvolatile;
- expected duration and output files;
- rollback or disconnect instruction.

Initial inventory and ordinary acquisition are in scope after the owner
connects the device. Driver replacement, capture-tool installation, firmware or
calibration writes, and destructive system changes require explicit approval.

The optional 32-bit SDK harness is `[VENDOR]` research infrastructure only. It
must remain standalone, load the operator's local DLLs from an explicit path,
and never become a PulseView/libsigrok runtime bridge or a release dependency.

## Failure handling

When a command fails:

1. preserve the exact command, exit code, relevant log, revisions, and device
   state;
2. determine whether the failure belongs to environment, build, frontend,
   libsigrok API, driver, USB transport, protocol, or hardware setup;
3. run the smallest read-only or focused diagnostic that discriminates the
   likely causes;
4. do not retry a state-changing USB command blindly;
5. drain or terminate only confirmed orphaned processes/transfers;
6. add a regression fixture/test when the failure is understood;
7. update the task journal and gate status.

Three repeated failures with the same external blocker should be reported as a
blocked task with the exact required owner action or environment change.

## Handoff template

Every interrupted or transferred task ends with:

```text
Outcome sought:
AEGIS task and stage:
Root branch/revision/dirty state:
libsigrok branch/revision/dirty state:
PulseView branch/revision/dirty state:
Requirement IDs:
Completed work:
Files changed:
Evidence and test commands:
Hardware/OS/driver binding used:
Gate status:
Known failures or unrun validation:
Next exact step:
Authority still required:
```

The next step must be executable and narrow, such as "add the failing decoder
test for capture H3062-CAP-0012," not "continue implementation."

## Phase completion checklist

- [ ] requirement behavior is implemented or the planning/research output is complete
- [ ] focused regression is green
- [ ] phase gate suite is green or every exception is approved and recorded
- [ ] live hardware evidence exists where required
- [ ] Windows and Linux claims are separated
- [ ] protocol and component documentation match the implementation
- [ ] no unapproved vendor binary or large raw capture entered the diff
- [ ] root and submodule dirty states are understood
- [ ] changelog entries are updated in the correct repositories
- [ ] exact delivery candidate is presented before any Git/publication action

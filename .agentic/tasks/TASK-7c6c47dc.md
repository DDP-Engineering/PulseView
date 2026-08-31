<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

<!--
Task journal. One file per task, at .agentic/tasks/TASK-<id>.md, kept
after delivery as the task's historical record.

The header is the block of "key: value" lines directly under the title.
Keep it exactly in that form — one key per line, no blank lines inside
the block, no comments between the lines — so it stays machine-readable.

  stage         frame | specify | design | build | validate | deliver | done
                (adoption journals: survey | components | close | done)
  type          feature | fix | change | adopt
  path          full | quick
  requirements  comma-separated requirement IDs, empty until specify
  branch        the branch this task is delivered on
  base          the commit this task started from, filled in at creation;
                the delivery report and `check --task` measure the diff
                against it, so leave it alone once it is written. Empty
                when the repository had no history yet.
  opened        YYYY-MM-DD

Header lines are edited in place; log lines are only ever appended.
Keep each log line to one sentence.

Stage report is one replaceable latest snapshot, not an evidence store.
Use plain one-line fields with no fences or bullets inside that section.
stage is the reported stage; current must match the journal header after any
transition. result is in_progress | completed | paused | blocked | skipped.
Keep all observations and decisions in the append-only Log as well.
Leave unknown fields blank; summary prints not recorded, never an assumed pass.
Refresh after work or decisions even if current has not changed.
-->

# TASK-7c6c47dc — Bundle the Python stdlib in the AppImage so decoders load anywhere

stage: done
type: fix
path: quick
requirements: REQ-PLAT-aa8d5d46
branch: feature/arm64-linux-build
base: 5aa2f172c0095dea4077bcffb4af231420ad340d
opened: 2026-08-31

## Done checklist (current stage)

- [x] red evidence recorded (manual probe - no automated test can execute
      ELF artifacts on this host)
- [x] anchor recorded before implementation
- [x] implementation makes the probe pass on bare bookworm and trixie
      arm64 containers
- [x] `check` clean, or each remaining warning explained in the log
- [x] `stage: validate` (validated and closed; the user's commit is the
      delivery outcome and carries this journal)

## Log

- 2026-08-31 frame: Scope: the AppImage bundles libpython but not the Python standard library and never sets PYTHONHOME, so srd_init dies with "Could not find platform independent libraries" on any host without a /usr python3.10 - protocol decoders are dead in the aarch64 package AND the shipped x86_64 package (probed on bare arm64 bookworm/trixie and bare amd64 ubuntu:22.04, identical failure). Fix in build_appimage.sh for both arches: copy the builder's stdlib into the AppDir before the closure pass and export PYTHONHOME in AppRun.
- 2026-08-31 frame: Quick path: repairs the behavior REQ-PLAT-aa8d5d46 already promises ("self-contained"); no new interface or dependency; same branch. The shipped x86_64 AppImage is NOT rebuilt by this task - refreshing it is a separate delivery decision, recorded as a known-defect note.
- 2026-08-31 build red (manual): command=`docker run --rm --platform linux/arm64 -v .../07_Delivery:/pkg:ro debian:bookworm bash /vw/verify-arm64-appimage.sh`; observed=CLI and both drivers pass, then `-P uart --show` fails with PYTHONHOME unset / platform independent libraries not found; identical on trixie and on the x86_64 AppImage on bare ubuntu:22.04.
- 2026-08-31 build green (manual): AppImage rebuilt with the stdlib bundled (35.3 MB -> 40.5 MB); the same probe now prints the full uart decoder description and VERIFY-OK on bare debian:bookworm AND debian:trixie arm64 containers; arm64_appimage_smoke.sh passes; full suite 6 passed, 0 failed, 0 skipped - the first run of the suite with nothing skipped.
- 2026-08-31 validate: check errors=0; remaining warnings pre-existing plus outside-layout on the new 07_Delivery artifacts, which is where delivery artifacts live by contract; x86_64 rebuild with this fix flagged to the user as a follow-up chip, shipped x64 AppImage keeps the defect until then.
- 2026-08-31 deliver: outcome is the user's commit on feature/arm64-linux-build together with the other aarch64 work; closing out so that commit carries the journal.

## Stage report

stage: deliver
result: completed
current: done
changed: 02_Tools/build/build_appimage.sh (stdlib bundling + AppRun PYTHONHOME), CHANGELOG.md, 02_Tools/build/STATUS.md, 07_Delivery/PulseView-aarch64.AppImage rebuilt
evidence: uart decoder loads with full description and VERIFY-OK on bare arm64 debian:bookworm and debian:trixie; suite 6/0/0; check errors=0
issues: shipped x86_64 AppImage keeps the decoder defect until rebuilt (follow-up chip raised); on-Pi hardware verification still pending
next: user commits the branch; optionally starts the x64 rebuild chip
needs_user: yes - the commit, and the x64 rebuild decision

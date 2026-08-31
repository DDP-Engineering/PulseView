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
  parent        optional top-level TASK-id; blank for an ordinary task
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

# TASK-9b2fc9a0 — Add Raspberry Pi deb and complete delivery set

stage: deliver
type: feature
path: full
requirements: REQ-PLAT-7c68e538, REQ-FUNC-d6ba285a, REQ-REL-dae2e62f, REQ-UX-5295dc77
parent:
branch: feature/arm64-linux-build
base: b6d0e8ea529ce9d07b9e994ac26af99a258517f5
opened: 2026-08-31

## Done checklist (current stage)

- [ ] validated candidate confirmed unchanged; otherwise returned to validate
- [ ] validation evidence, diff, exclusions, and outcome presented
- [ ] delivery confirmed by the human
- [ ] journal and report included in the delivery commit
- [ ] agreed outcome delivered, normally a PR
- [ ] close-out committed after the outcome succeeded, or carried by the delivery commit where nothing could fail after it

## Log

- 2026-08-31 frame: Scope is an installable Raspberry Pi OS arm64 Debian package, a single repeatable release entry point for Windows x64 ZIP, Linux x86_64 AppImage and tarball, Raspberry Pi aarch64 AppImage and Debian package, plus SHA-256 evidence and supporting documentation.
- 2026-08-31 frame: Excluded are 32-bit armhf, a Windows installer, distro repository publication, source-code changes to PulseView or sigrok, Git commits, and Git publication.
- 2026-08-31 frame: Full path selected because the Debian package and release command are new externally visible packaging interfaces and file formats.
- 2026-08-31 frame: The existing non-default feature/arm64-linux-build branch is retained so the authorized implementation does not create another branch or disturb the validated ARM candidate.
- 2026-08-31 frame: Expected requirements are one platform behavior for the installable arm64 Debian package, one functional behavior for the five-package release matrix, and one reliability behavior for checksummed release completeness.
- 2026-08-31 frame: The user's direct instruction to create the Debian installer and update all delivery scripts and documentation confirms this scope.
- 2026-08-31 specify: Created REQ-PLAT-7c68e538, REQ-FUNC-d6ba285a, REQ-REL-dae2e62f, and REQ-UX-5295dc77, plus the Debian package layout and command specification in specs/REQ-PLAT-7c68e538.md.
- 2026-08-31 specify: AEGIS check reported zero errors; expected stale-path warnings name the scripts and tests that build will create, while remaining warnings predate this task or belong to the current dirty delivery candidate.
- 2026-08-31 design: The Debian builder extracts the verified aarch64 AppImage into a private /opt payload, owns standard PulseView commands plus menu/icon/udev/doc paths, supports a stage-only fixture seam, and archives with dpkg-deb [REQ-PLAT-7c68e538, REQ-UX-5295dc77].
- 2026-08-31 design: A ConstrainedLanguage-safe Windows PowerShell coordinator sequences the WSL/container builds, native Git Bash Windows verification/package step, arm64 Debian assembly, and final manifest gate; plan mode is the deterministic orchestration seam [REQ-FUNC-d6ba285a].
- 2026-08-31 design: A shell verifier matches exactly one artifact for each explicit architecture/format row, removes stale output before validation, and writes one sorted SHA256SUMS only after all five hashes self-verify [REQ-REL-dae2e62f].
- 2026-08-31 design: Rejected building a conventional dynamically linked Debian package directly from a Raspberry Pi OS root because it duplicates the dependency-closure logic and creates a second runtime payload distinct from the already-tested AppImage.
- 2026-08-31 design: Test seams are a fake AppDir passed to build_deb.sh --stage-only for payload/desktop metadata, build_delivery_set.ps1 -Plan for the five build phases, verify_delivery_set.sh fixtures for complete/missing/duplicate sets, and a physical Pi apt install/launch/remove integration run.
- 2026-08-31 design: Expected implementation paths are 02_Tools/build/build_deb.sh, build_delivery_set.ps1, verify_delivery_set.sh, 02_Tools/test/deb_package_test.sh, delivery_set_test.sh, README.md, 01_Documentation/Environment_Setup.md, 02_Tools/build/README.md, STATUS.md, 07_Delivery documentation/artifacts, CHANGELOG.md, and linux-build-tooling knowledge.
- 2026-08-31 build red: `bash 02_Tools/test/deb_package_test.sh` exited 1 with `FAIL: Debian package builder does not exist`, the expected pre-implementation failure for REQ-PLAT-7c68e538 and REQ-UX-5295dc77.
- 2026-08-31 build red: `bash 02_Tools/test/delivery_set_test.sh` exited 1 with `FAIL: delivery-set verifier does not exist`, the expected pre-implementation failure for REQ-FUNC-d6ba285a and REQ-REL-dae2e62f.
- 2026-08-31 build: The initial physical package build exposed two environment failures: a direct-script container exec and then a missing WSL arm64 binfmt registration; invoking through bash and re-registering the pinned emulator resolved those boundaries.
- 2026-08-31 build: dpkg-deb rejected the NTFS-backed package root as mode 0777, so real package assembly uses the existing native `/build` builder volume while host-only stage fixtures remain temporary; this is the repository's established container scratch convention.
- 2026-08-31 build: The first impacted AEGIS run fell back to the full suite and reported 8 passed, 1 failed, 3 skipped because WSL exposes powershell.exe without Git Bash's cygpath; delivery_set_test.sh now chooses cygpath or wslpath according to its host.
- 2026-08-31 build: Focused package and delivery-set tests pass in Windows Git Bash, and the PowerShell coordinator's six-phase plan executed successfully under the host's ConstrainedLanguage policy.
- 2026-08-31 build: The real arm64 builder checksum-verified and extracted PulseView-aarch64.AppImage, then dpkg-deb created and accepted pulseview-ddp_0.5.0+git5aa2f17.dirty_arm64.deb with SHA-256 e689b5dc93289dc0948df9e87b843cc56cf124c1238dec0b1d4aa4583ad82a17.
- 2026-08-31 build: On Raspberry Pi 4 ddp-remote running 64-bit Raspberry Pi OS Trixie, apt installed the final arm64 package, sigrok-cli loaded UART and listed atk-dl16 plus hantek-dso3062l, desktop/icon/udev paths existed, and PulseView remained running for GUI observations under labwc Wayland/XWayland.
- 2026-08-31 build: apt remove left zero package-owned paths and normal dpkg state rc, after which the package was reinstalled and the final rebuilt artifact again listed both drivers and sustained its GUI process; the Pi is left installed and ready.
- 2026-08-31 build: The complete-set verifier rejected the current mixed-revision candidate collection and left no SHA256SUMS, preventing the older 8e67ed1 Windows/tar artifacts from being mislabeled with the 5aa2f17-dirty AppImages and Debian package.
- 2026-08-31 build: AEGIS impacted proof fell back to the configured full suite and passed 9 tests with 0 failures and 3 environment skips in WSL; Windows Git Bash separately passed 11 with 0 failures and only the unavailable local Docker ARM runtime replay skipped.
- 2026-08-31 build: Evolution reported the expected 24 implementation/delivery paths; additional existing packager and sidecar paths absent from the design list were reviewed and accepted because they implement producer-level integrity and same-revision provenance for the release gate.
- 2026-08-31 build: Post-implementation check reported 0 errors and 38 warnings, all from pre-existing stale paths, the previous task awaiting Git authority, expected root/delivery layout, and opaque binary secret-scan coverage rather than this task's requirements or links.
- 2026-08-31 validate: The first end-to-end coordinator invocation stopped before builds because direct wslpath argument forwarding stripped Windows backslashes; the path conversion now runs through a quoted WSL shell command.
- 2026-08-31 validate: The full coordinator completed for `b6d0e8e-dirty`, rebuilt all five required packages, passed the native Windows package suite with 11 passes, 0 failures and one environment skip, generated a verified five-row SHA256SUMS, and emitted its explicit completion sentinel.
- 2026-08-31 validate: The exact final x86_64 AppImage loaded the UART decoder in bare Ubuntu 22.04 and Debian Bookworm containers, proving the bundled Python standard-library repair on both compatibility targets.
- 2026-08-31 validate: On the physical Raspberry Pi 4, apt upgraded the exact final arm64 Debian package, its SHA-256 matched the manifest, both project drivers and the UART decoder loaded, and both the installed GUI and exact final aarch64 AppImage GUI remained alive under the active desktop session.
- 2026-08-31 validate: Capture remains untested on the Pi because neither physical instrument was attached; installation, GUI startup, architecture, package integrity, driver registration and decoder runtime were tested.
- 2026-08-31 validate: Semantic diff review found the implementation consistent with the four active requirements, the package and delivery-set design, fail-closed error paths, Windows ConstrainedLanguage, Linux architecture mapping, repository layout, and the explicit exclusions; no unrequested source behavior or secret-bearing text was found.
- 2026-08-31 validate: Final evolution recorded and reviewed 33 candidate paths comprising the delivery coordinator, Debian builder, producer integrity/provenance changes, tests, documentation and final artifacts.
- 2026-08-31 validate: Final `python .agentic/aegis.py check --task TASK-9b2fc9a0 --strict --run` ran the configured test command successfully and reported 0 errors, 64 warnings and 7 notes, then exited 1 because strict promoted six opaque-binary secret-scan coverage warnings.
- 2026-08-31 validate: Accepted warnings are generated packages outside the source layout, opaque archives that the text secret scanner cannot inspect, pre-existing stale planning paths and a prior unticked delivery task, plus ARM build paths governed by requirements from the preceding task rather than this Debian/release task; none reports a test or artifact failure.

## Design

1. Package source: reuse the verified aarch64 AppImage payload and extract it in the arm64 AppImage builder; no second compile or dependency resolver [REQ-PLAT-7c68e538].
2. Installed interface: private AppDir in `/opt/pulseview-ddp`, standard `pulseview` and `sigrok-cli` wrappers, desktop entry/icon, shared udev rule, and Debian docs/control scripts [REQ-PLAT-7c68e538, REQ-UX-5295dc77].
3. Build interface: `build_deb.sh` defaults to the delivery AppImage and supports `--appdir` plus `--stage-only` for deterministic tests [REQ-PLAT-7c68e538].
4. Release interface: `build_delivery_set.ps1 [-Plan]` is the Windows owner entry point and invokes WSL for container builds, Git Bash for Windows package verification, then the manifest gate [REQ-FUNC-d6ba285a].
5. Integrity interface: `verify_delivery_set.sh DIRECTORY` accepts exactly one file per five fixed filename patterns and atomically replaces `SHA256SUMS` after `sha256sum --check` succeeds [REQ-REL-dae2e62f].
6. Storage: intermediate extraction/package roots remain in `.work` or the builder's native `/build` scratch volume; only verified `.deb`, README, sidecar digest, and complete-set manifest enter `07_Delivery` [REQ-PLAT-7c68e538, REQ-REL-dae2e62f].
7. Rejected alternative: direct Raspberry Pi OS dynamic packaging would fork the tested runtime closure and require per-release distro dependency maintenance.
8. Automated seams: package-stage fixture, release plan assertion, and complete/missing/duplicate manifest fixtures; physical Pi install/menu/remove is the integration seam.

## Rulings

<!-- Append decisions here; never edit history. Supersede with a new ruling.
- RULING-001 | date=YYYY-MM-DD | decision=<decision> | reason=<reason> | source=user | supersedes=none
source: user | repository | requirement | technical
-->

## Handoff

<!-- Replace these fields with the latest minimal resume snapshot.
status: ready | waiting | blocked
-->

current: deliver
status: ready
next: Present the validated unpublished candidate and wait for explicit Git/delivery authority.
must_read: .agentic/steps/6_deliver.md; .agentic/tasks/TASK-9b2fc9a0.md; .agentic/knowledge/linux-build-tooling.md
blockers: none

## Stage report

stage: validate
result: completed
current: deliver
changed: Validated the complete same-revision five-package release, final manifest, Debian installer, producer integrity/provenance, tests, documentation, and exact Raspberry Pi artifacts.
evidence: Coordinator sentinel b6d0e8e-dirty; Git Bash 11/0/1; five manifest hashes rechecked; bare Ubuntu 22.04 and Debian Bookworm decoder loads; physical Pi exact deb/AppImage CLI and GUI passed; AEGIS test command passed with 0 errors.
issues: Strict check exits 1 on six promoted opaque-binary scan-coverage warnings; 64 total warnings are accepted layout, stale-path, prior-task and coverage findings; physical capture was not possible without attached instruments.
next: Present the validated candidate and wait for explicit commit or publication authority.
needs_user: yes
spec_compliance: disabled
implementation_quality: disabled
review_round:

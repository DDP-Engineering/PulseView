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

# TASK-596c2d0a — Harden Linux packaging and validate Raspberry Pi delivery

stage: deliver
type: fix
path: full
requirements: REQ-PLAT-aa8d5d46, REQ-PLAT-ceeee15c, REQ-PLAT-871c1254, REQ-PLAT-0e73bea7, REQ-REL-dc0ff39f, REQ-REL-08b2f2e8
branch: feature/arm64-linux-build
base: 5aa2f172c0095dea4077bcffb4af231420ad340d
opened: 2026-08-31

## Done checklist (current stage)

- [ ] validated candidate confirmed unchanged; otherwise returned to validate
- [ ] validation evidence, diff, exclusions, and outcome presented
- [ ] delivery confirmed by the human
- [ ] journal and report included in the delivery commit
- [ ] agreed outcome delivered, normally a PR
- [ ] close-out committed after the outcome succeeded, or carried by the delivery commit where nothing could fail after it

## Log

- 2026-08-31 frame: Scope is to harden Linux post-build gates, make AppImage provenance honest, pin the privileged binfmt helper, test actual arm64 container execution, replace the header-only arm64 smoke with conditional runtime coverage, rebuild and verify the x86_64 AppImage decoder fix, and validate the aarch64 artifact natively on ddp-remote.
- 2026-08-31 frame: Exclusions are Windows/MXE implementation changes, 32-bit armhf, Git commit or push, unrelated pre-existing delivery churn, and physical-instrument capture if neither instrument is attached to the Pi.
- 2026-08-31 frame: Path is full because the work changes externally visible build failure behavior, adds release provenance behavior, and hardens a privileged host-setup command.
- 2026-08-31 frame: Expected requirements are updates to REQ-PLAT-aa8d5d46 and REQ-PLAT-ceeee15c, plus new reliability requirements for fail-closed Linux staging probes and honest AppImage source provenance.
- 2026-08-31 frame: User confirmed the proposed scope and requirement set.
- 2026-08-31 specify: Updated REQ-PLAT-aa8d5d46 for tracked runtime smoke plus native Trixie verification and REQ-PLAT-ceeee15c for a real local arm64 container probe with digest-pinned remediation.
- 2026-08-31 specify: Created draft REQ-REL-dc0ff39f for fail-closed thin-package probes and REQ-REL-08b2f2e8 for dirty source-state provenance; no separate spec is needed because each verification defines the observable contract.
- 2026-08-31 specify: AEGIS check reports errors=0; stale-path and no-linked-test warnings are expected until the designed files are created in build, while remaining warnings predate this task.
- 2026-08-31 design: Shared source_revision.sh will print HEAD or HEAD-dirty while excluding .work and 07_Delivery generated output, and both Linux build paths will consume it [REQ-REL-08b2f2e8].
- 2026-08-31 design: verify_linux_stage.sh will own hard version and driver-list gates plus a non-fatal device-specific show probe, making the behavior stub-testable without compiling the stack [REQ-REL-dc0ff39f].
- 2026-08-31 design: check_host.sh will run a local arm64 image with --pull never through a stub-testable engine seam and print a lock-mirrored immutable binfmt digest on failure [REQ-PLAT-ceeee15c].
- 2026-08-31 design: A separate arm64 runtime smoke will execute version, both drivers and UART natively or through an available arm64 container, while the existing identity smoke remains host-independent [REQ-PLAT-aa8d5d46].
- 2026-08-31 design: No persistent data format changes; build records and emitted READMEs retain their existing text format with only an honest -dirty revision suffix where applicable.
- 2026-08-31 design: Rejected making --driver ... --show a hard gate because sigrok-cli exits 1 when no matching USB device is attached; listing the compiled driver is deterministic instead [REQ-REL-dc0ff39f].
- 2026-08-31 design: Test seams are temporary Git repositories for provenance, stub staged binaries for packaging, a stub Docker engine for readiness, and ddp-remote plus bare Bookworm for arm64 runtime; the linux-build-tooling diagram now shows identity and runtime gates.
- 2026-08-31 build red: command=`bash 02_Tools/test/linux_package_gate_test.sh`; exit=1; expected missing behavior=verify_linux_stage.sh does not exist, so no hard staged-version or driver-list gate is available.
- 2026-08-31 build red: command=`bash 02_Tools/test/source_revision_test.sh`; exit=1; expected missing behavior=source_revision.sh does not exist, so dirty build inputs are still labelled as the clean HEAD.
- 2026-08-31 build red: command=`bash 02_Tools/test/check_host_arm64_test.sh`; exit=1; expected missing behavior=check_host trusts an enabled binfmt file, never asks Docker to run arm64, and prints a mutable privileged image tag absent from the lock.
- 2026-08-31 build: repository anchor recorded after the three expected red tests at base `5aa2f17`, timestamp `2026-08-31T11:23:06.313392Z`.
- 2026-08-31 build green: `bash 02_Tools/test/linux_package_gate_test.sh`, `bash 02_Tools/test/source_revision_test.sh`, and `bash 02_Tools/test/check_host_arm64_test.sh` each exited 0 with all assertions passed.
- 2026-08-31 build green: `python .agentic/aegis.py test --impacted --base HEAD` fell back to the configured suite because the task spans uncommitted new paths and reported 6 passed, 0 failed, 3 skipped; skips were the unavailable local arm64 runtime before binfmt setup and two Windows-only delivery tests under WSL.
- 2026-08-31 build: the x86_64 builder refresh reached `X64-BUILDER-OK`, the AppImage rebuild reached `X64-APPIMAGE-BUILD-OK`, and `PulseView-x86_64.AppImage` SHA-256 is `5568e3e13c5eedcccf804fb6b08ea3b8c44377f282d9cc0acb437cc692c95ab6`.
- 2026-08-31 build manual: freshly pulled bare `ubuntu:22.04` and `debian:bookworm` amd64 containers each ran the rebuilt x86_64 AppImage with version, both project drivers, and `ID: uart`, proving the bundled Python decoder fix.
- 2026-08-31 deviation build: physical-instrument capture on the Pi was skipped because `lsusb` showed only root and VIA hubs, with neither DSO-3062L nor ATK-DL16 attached.
- 2026-08-31 deviation build: an attempted host check used `02_Tools/build/check_host.sh` and exited 1 because the correct governed path is `02_Tools/bootstrap/check_host.sh`; the corrected invocation ran and preserved its non-fatal x86 checks.
- 2026-08-31 build: WSL teardown between `wsl.exe` calls removes binfmt registration, while digest-pinned registration plus a real arm64 container probe in one WSL lifecycle succeeds; the emulated build then reached `ARM64-APPIMAGE-BUILD-OK` with complete dependency closure.
- 2026-08-31 deviation build: two emulated runtime-smoke invocations exited 1 after skipping because Docker 29 reported the multi-platform Bookworm tag as amd64 even after an arm64 pull; replacing metadata inspection with an actual `docker run --platform linux/arm64` probe made the unchanged artifact checks pass.
- 2026-08-31 build manual: the rebuilt aarch64 AppImage SHA-256 `8259df19afd8a079cd39ffbe79bfc4f524bb8860bb5051a91026676da576964b` passed the emulated bare-Bookworm runtime smoke, then the exact matching file passed native version, both drivers, UART decoder and pristine FUSE execution on Raspberry Pi 4 `ddp-remote` running 64-bit Debian 13 Trixie.
- 2026-08-31 build manual: PulseView from the pristine aarch64 AppImage remained running for eight seconds on the Pi's active labwc Wayland desktop through XWayland with no GUI log error, then was terminated cleanly after observation.
- 2026-08-31 deviation build: review found the generated x86_64 README inherited ARM-only Raspberry Pi guidance; architecture-specific README generation and `appimage_readme_test.sh` corrected and covered the unplanned defect.
- 2026-08-31 build: both generated AppImage READMEs record `5aa2f17-dirty`, while `source_revision_test.sh` proves generated `07_Delivery` and `.work` output alone does not mark an otherwise clean source tree dirty.
- 2026-08-31 build: evolution reported the expected 18 files, comprising the scoped tooling, tests, lock/docs and four rebuilt delivery files, with 6 added, 12 modified and 0 removed.
- 2026-08-31 deviation build: `python .agentic/aegis.py check` exited 0 with 0 errors, 29 warnings and 7 notes; accepted warnings are older stale requirement paths, root/docs and delivery paths outside configured AEGIS globs, and binary artifacts the text-only secret scanner cannot inspect.
- 2026-08-31 deviation validate: nested WSL quoting dropped the revision argument during one README regeneration and left both labels blank; validation caught the trailing whitespace, direct positional regeneration restored `5aa2f17-dirty`, and `git diff --check` then exited 0.
- 2026-08-31 validate: semantic review covered source/error paths, x86_64 and aarch64 portability, immutable privileged tooling, generated documentation, secrets boundaries and unrequested work; no implementation defect remained after the README and executable-runtime-probe corrections.
- 2026-08-31 validate: linux-build-tooling knowledge now describes the built gates and file set, and all six applicable platform/reliability requirements were re-read with active status, current prose, affected paths and linked tests.
- 2026-08-31 validate: post-review `python .agentic/aegis.py test --impacted --base HEAD` exited 0 with 7 passed, 0 failed and 3 explicit WSL skips; Git Bash `bash 02_Tools/test/run_tests.sh` exited 0 with 9 passed, 0 failed and only the Docker-unavailable ARM replay skipped.
- 2026-08-31 validate inspection: Dockerfile.appimage rejects empty digest arguments and verifies every download, build_image.sh passes lock values, the refreshed builders logged checksum success, and an arm64 image build with an all-zero appimagetool digest exited 1 at `/usr/local/bin/appimagetool: FAILED` while the evidence wrapper exited 0.
- 2026-08-31 validate: final evolution refreshed at `2026-08-31T12:21:27.046001Z` and matched the expected 18 files, 6 added, 12 modified and 0 removed.
- 2026-08-31 deviation validate: the first strict proof exited 1 with test success, 0 errors and 34 warnings because three task-scoped uncovered-source warnings were promoted; adding the already-built architecture-mapping and pinned-tool requirements to this review task eliminated every uncovered-source warning without changing runtime behavior.
- 2026-08-31 deviation validate: final `python .agentic/aegis.py check --task TASK-596c2d0a --strict --run` exited 1 after its configured test command passed, with 0 errors, 29 warnings and 7 notes; the three promoted warning classes are accepted repository-wide stale-path debt, expected root/delivery outside-layout paths, and binary payloads the text-only secret scanner cannot inspect.

## Stage report

stage: validate
result: completed
current: deliver
changed: fail-closed Linux gates, dirty provenance, executable arm64 host probe, runtime smoke, architecture-specific README generation, and rebuilt x86_64/aarch64 AppImages
evidence: Git Bash suite 9 passed and 1 skipped; WSL suite 7 passed and 3 skipped; x86 decoder tests pass on two bare distros; ARM emulation and Pi runtime/FUSE/GUI checks pass
issues: strict proof exits 1 on 29 accepted warnings despite 0 errors and test success; physical instrument capture remains unverified because neither device was attached
next: present validated candidate and exclusions; no Git operation without separate human approval
needs_user: yes - explicit Git delivery authority is required for any commit, push or PR

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

# TASK-efc19bd8 — Raspberry Pi 4/5 (aarch64) Linux build support

stage: done
type: feature
path: full
requirements: REQ-PLAT-871c1254, REQ-PLAT-aa8d5d46, REQ-PLAT-0e73bea7, REQ-PLAT-ceeee15c
branch: feature/arm64-linux-build
base: 5aa2f172c0095dea4077bcffb4af231420ad340d
opened: 2026-08-31

## Done checklist (current stage)

- [x] validated candidate confirmed unchanged; otherwise returned to validate
- [x] validation evidence, diff, exclusions, and outcome presented
- [x] delivery confirmed by the human
- [x] journal and report included in the delivery commit
- [x] agreed outcome delivered, normally a PR (here: a local commit on the
      task branch made by the user; no push or PR requested)
- [x] close-out committed after the outcome succeeded, or carried by the
      delivery commit where nothing could fail after it

## Design

Components touched: Linux build tooling (`02_Tools/build/`), host bootstrap
check (`02_Tools/bootstrap/`), upstream lock (`02_Tools/upstream/`), docs.

- New sourceable helper `02_Tools/build/arch_map.sh` [REQ-PLAT-871c1254]:
  maps `${ARCH_OVERRIDE:-$(uname -m)}` to SR_ARCH, SR_LIBDIR, SR_STAGE_NAME,
  SR_TARBALL_SUFFIX, SR_APPIMAGE_NAME, SR_DOCKER_PLATFORM; unknown arch exits
  non-zero. build_linux.sh and build_appimage.sh source it and lose their
  hardcoded x86_64 values; x86_64 outputs keep today's exact names.
- `build_linux.sh` gains `--arch aarch64` (host side): re-execs the container
  with `--platform linux/arm64`; inside, everything derives from `uname -m`.
  `run_in_builder.sh` and `build_image.sh` gain `--platform`, with per-arch
  image tags (`hantek-builder-appimage-arm64`) and volumes [REQ-PLAT-aa8d5d46].
- `Dockerfile.appimage` installs the same three pinned tools on both
  architectures - appimagetool, linuxdeployqt, and the type-2 AppImage
  runtime - taking each URL and sha256 from the upstream lock
  [REQ-PLAT-0e73bea7]. CORRECTED 2026-08-31 after external review: the
  original decision here (arm64 uses linuxdeploy + its Qt plugin because
  "linuxdeployqt publishes no aarch64 binary") rested on a false premise -
  release 11 ships linuxdeployqt-continuous-aarch64.AppImage, confirmed
  against the GitHub release API. One deployer, both architectures. The
  runtime is baked and passed via appimagetool --runtime-file because
  appimagetool otherwise downloads it at packaging time - the review also
  caught that unpinned fetch hiding in the existing "offline" x86_64 flow.
  Rejected alternative: switching both arches to linuxdeploy - would churn
  the proven x64 pipeline for zero user benefit.
- `check_host.sh` gains a non-fatal arm64 probe (binfmt qemu-aarch64
  registration, dir overridable for tests) naming the tonistiigi/binfmt
  one-liner as the fix [REQ-PLAT-ceeee15c].

Test seams: `02_Tools/test/arch_map_test.sh` (pure mapping, runs anywhere)
[REQ-PLAT-871c1254]; `02_Tools/test/arm64_tools_lock_test.sh` (lock carries
https+sha256 for every aarch64 tool) [REQ-PLAT-0e73bea7];
`02_Tools/test/arm64_appimage_smoke.sh` (exit 77 without a built artifact,
asserts ELF aarch64 when present) [REQ-PLAT-aa8d5d46];
`02_Tools/test/check_host_arm64_test.sh` (stubbed engine/binfmt dir)
[REQ-PLAT-ceeee15c].

## Log

- 2026-08-31 frame: Scope: make the Linux build tooling architecture-aware and add an aarch64 (Raspberry Pi 4/5, 64-bit OS) build target - parametrize build_linux.sh and build_appimage.sh, extend Dockerfile.appimage/build_image.sh/run_in_builder.sh for an arm64 builder, pin aarch64 appimagetool and a Qt deploy tool in upstreams.lock.toml, add QEMU/binfmt detection to check_host.sh, and update the docs.
- 2026-08-31 frame: Exclusions: the Windows/MXE path is untouched; no 32-bit armhf target; producing and shipping the actual arm64 packages into 07_Delivery is a package/delivery operation outside AEGIS scope and additionally needs the WSL Docker build host and a multi-hour emulated build; on-instrument verification needs a physical Pi and stays a documented follow-up.
- 2026-08-31 frame: Path: full - a new externally observable deliverable target, new pinned tool dependencies (aarch64 appimagetool/Qt deployer), so the quick-path conditions do not hold.
- 2026-08-31 frame: Expected requirements: one new REQ-PLAT - the Linux build tooling shall build the sigrok stack and PulseView for aarch64 with a Raspberry Pi OS Bookworm-compatible glibc floor, while x86_64 outputs keep their current names and content behavior.
- 2026-08-31 frame: Scope was proposed to the user as a five-phase plan in conversation and the user answered "create a new branch from remote master then implement" - treating that as the frame approval; continuing without a second stop.
- 2026-08-31 frame: Pre-existing uncommitted 07_Delivery artifact churn (rebuilt x64 packages) predates this task and stays out of this branch's commits.
- 2026-08-31 specify: Created four draft platform requirements: REQ-PLAT-871c1254 (shared arch mapping with x86_64 name invariance), REQ-PLAT-aa8d5d46 (self-contained aarch64 AppImage, glibc 2.35 base, Bookworm-compatible), REQ-PLAT-0e73bea7 (arm64 builder tools pinned and checksum-verified via the upstream lock), REQ-PLAT-ceeee15c (host check reports missing arm64 container support with the binfmt fix).
- 2026-08-31 specify: No spec files - each requirement is buildable alone; the arch mapping table lives in the requirement prose itself.
- 2026-08-31 specify: One frame expectation revised: the single expected REQ-PLAT split into four, one behavior each, per the one-shall rule.
- 2026-08-31 specify: DEVIATION specify: check reports stale-paths on REQ-PLAT-871c1254 and REQ-PLAT-aa8d5d46 for 02_Tools/build/arch_map.sh - accepted, the file is created in build and the warning self-resolves; all other check findings predate this task.
- 2026-08-31 design: Design note written under ## Design; knowledge pages owe nothing - .agentic/knowledge/ has no component page for the build tooling, only its README.
- 2026-08-31 design: Key decision: arm64 uses linuxdeploy + linuxdeploy-plugin-qt (pinned aarch64 releases) because linuxdeployqt ships x86_64-only; the x86_64 deploy flow is deliberately untouched.
- 2026-08-31 build red: command=`bash 02_Tools/test/arch_map_test.sh`; exit=1; expected missing behavior=02_Tools/build/arch_map.sh does not exist yet, so the shared architecture mapping REQ-PLAT-871c1254 requires cannot be sourced.
- 2026-08-31 build green: arch_map_test.sh exit=0 after adding arch_map.sh and wiring build_linux.sh/build_appimage.sh to it; x86_64 rows byte-identical to the historical names, both scripts free of hardcoded x86_64-linux-gnu.
- 2026-08-31 build note: the generated README-AppImage template no longer carries the "Verified on a bare ubuntu:22.04 container" sentence - that claim is per-delivery evidence, not a property of the script; the delivered README in 07_Delivery is untouched.
- 2026-08-31 build red: command=`bash 02_Tools/test/arm64_tools_lock_test.sh`; exit=1; expected missing behavior=no appimagetool-aarch64/linuxdeploy-aarch64/linuxdeploy-plugin-qt-aarch64 artifacts in upstreams.lock.toml, no arm64 install path in Dockerfile.appimage, build_image.sh never reads those entries (REQ-PLAT-0e73bea7).
- 2026-08-31 build evidence: aarch64 tool digests computed from the actual downloaded bytes (curl to scratchpad, sha256sum): appimagetool-aarch64 1.9.1 f0837e74..., linuxdeploy-aarch64 1-alpha-20251107-1 62009511..., linuxdeploy-plugin-qt-aarch64 1-alpha-20250213-1 bf1c24af...; the first two also match GitHub's release-API asset digests, the plugin's release predates that API field.
- 2026-08-31 build green: arm64_tools_lock_test.sh exit=0 after lock entries, Dockerfile.appimage per-arch tool install (fail-closed on empty checksums, every wget piped through sha256sum -c), and build_image.sh --platform with per-arch lock reads.
- 2026-08-31 build red: command=`bash 02_Tools/test/check_host_arm64_test.sh`; exit=1; expected missing behavior=check_host.sh has no arm64 capability probe, so no WARN/PASS arm64 lines and no binfmt remedy in the output (REQ-PLAT-ceeee15c).
- 2026-08-31 build green: check_host_arm64_test.sh exit=0 after the binfmt probe (WARN with tonistiigi/binfmt remedy, PASS with handler or native arm64, exit status unchanged either way).
- 2026-08-31 build manual observation (REQ-PLAT-aa8d5d46, partial): run_in_builder.sh/build_appimage.sh --arch wiring verified by `build_image.sh --image appimage --platform aarch64 --dry-run` in WSL - stages context appimage-arm64, assembles docker build --platform linux/arm64 with all three pinned aarch64 tool args from the lock; the x86_64 dry-run is unchanged in shape (linuxdeployqt args, tag hantek-builder-appimage:latest); real check_host.sh run on the WSL host reports WARN arm64 containers with the binfmt one-liner.
- 2026-08-31 build: DEVIATION build: REQ-PLAT-aa8d5d46 Manual verification not fully carried out - the aarch64 image build, compile, bare-container run and on-Pi run need qemu binfmt (kernel-state change left to the user) plus hours of emulated build and Pi hardware; arm64_appimage_smoke.sh exits 77 until an artifact exists.
- 2026-08-31 build: DEVIATION build: check flags README.md, CHANGELOG.md, 01_Documentation/Environment_Setup.md outside-layout - accepted, documentation is intentionally outside the source/tests globs per aegis.toml's own comment.
- 2026-08-31 build: full suite `bash 02_Tools/test/run_tests.sh`: 5 passed, 0 failed, 1 skipped (arm64_appimage_smoke.sh, honest skip - no artifact).
- 2026-08-31 build: evolution 15 files (4 added, 11 modified, 0 removed) - exactly the design note's file list plus STATUS.md/CHANGELOG.md/README.md documentation; check errors=0, remaining 26 warnings all predate this task (07_Delivery churn, other requirements' stale paths).
- 2026-08-31 build: docs updated - Environment_Setup.md Raspberry Pi section, README.md build pointer, CHANGELOG.md Unreleased/Added, STATUS.md dated aarch64 section recording exactly what is and is not verified.
- 2026-08-31 validate: external review received from the user; each claim verified against primary sources before acting.
- 2026-08-31 validate: DEVIATION validate: review claim CONFIRMED against the GitHub release API - linuxdeployqt tag 11 ships linuxdeployqt-continuous-aarch64.AppImage (sha256 c6c078d9...; the same response reproduces the x86_64 digest already in the lock, validating the source). The design's "linuxdeployqt publishes no aarch64 binary" was asserted from memory and is FALSE; returning to build to keep linuxdeployqt on both architectures and drop the linuxdeploy+plugin detour.
- 2026-08-31 validate: review claim CONFIRMED - appimagetool downloads the type-2 runtime at pack time unless --runtime-file is passed, so the x86_64 AppImage packaging reached the network despite the pinned tools; AppImage/type2-runtime stable tag 20251108 provides runtime-x86_64 (2fca8b44...) and runtime-aarch64 (00cbdfcf...) to pin and bake.
- 2026-08-31 validate: review accepted - Raspberry Pi OS current release is Trixie (Bookworm legacy): docs to say Trixie primary / Bookworm compatibility floor; load_image.sh missed by the design, gets --platform; FUSE note (extract-and-run proves extraction mode, normal execution needs the host FUSE stack) added to the pending on-Pi verification list.
- 2026-08-31 validate: review partially declined - thin aarch64 tarball capability stays (already documented as not-for-Bookworm, AppImage is the Pi delivery); deep ARM gates (CLI/driver/decoder on bookworm+trixie arm64 containers) recorded as pending alongside the artifact itself; the || true CLI probes in build_linux.sh predate this task, flagged as a separate follow-up.
- 2026-08-31 build red: command=`bash 02_Tools/test/arm64_tools_lock_test.sh` (updated for the corrected design); exit=1; expected missing behavior=no linuxdeployqt-aarch64/appimage-runtime-* lock entries, Dockerfile installs no pinned runtime, build_appimage.sh never passes --runtime-file, build_image.sh never reads the new entries.
- 2026-08-31 build evidence: corrected-tool digests computed from downloaded bytes AND matching the GitHub release-API digests: linuxdeployqt-aarch64 tag 11 c6c078d9..., appimage-runtime-x86_64 20251108 2fca8b44..., appimage-runtime-aarch64 20251108 00cbdfcf...; linuxdeploy/linuxdeploy-plugin-qt lock entries removed as unused.
- 2026-08-31 build green: arm64_tools_lock_test.sh exit=0 after lock replacement, Dockerfile single-deployer + baked runtime (all downloads still sha256sum -c, empty checksums fail), build_image.sh per-arch linuxdeployqt/runtime lock reads, build_appimage.sh --runtime-file with a hard failure if the baked runtime is missing, load_image.sh --platform with arch-suffixed archive/tag; arch_map_test.sh still green.
- 2026-08-31 build manual observation: WSL dry-runs re-run for both platforms - each stages appimagetool + linuxdeployqt + runtime for its architecture with the locked URLs and digests; docs and knowledge page corrected (Trixie current/Bookworm floor, FUSE note, runtime finding recorded in STATUS.md and CHANGELOG Fixed).
- 2026-08-31 validate: final evolution 16 files (4 added, 12 modified, 0 removed) - the build-stage list plus load_image.sh from the review correction; knowledge page .agentic/knowledge/linux-build-tooling.md created.
- 2026-08-31 validate: inspection observation (REQ-PLAT-0e73bea7): Dockerfile.appimage pipes all three downloads through sha256sum -c under set -eux and test -n rejects empty checksum args, so a wrong or missing digest exits non-zero at image build; live wrong-digest docker run deferred to the build host with the rest of the image build.
- 2026-08-31 validate: final proof `python .agentic/aegis.py check --task TASK-efc19bd8 --strict --run`: run: test ok (32.5s; suite 5 passed, 0 failed, 1 skipped), errors=0, warnings=27, strict exit 1 from 2 promoted secret-in-diff warnings - both on the pre-existing uncommitted 07_Delivery x64 packages that predate this task and are excluded from this branch's commit.
- 2026-08-31 validate: DEVIATION validate: strict exit 1 accepted - the 2 promoted secret-in-diff findings are unscannable pre-existing binary packages in the working tree, not this task's files; they will not be committed by this task.
- 2026-08-31 validate: DEVIATION validate: uncovered-source on 02_Tools/build/STATUS.md accepted - it is the build ledger (documentation) living inside the 02_Tools source glob, updated deliberately per the repository's own ledger convention.
- 2026-08-31 deliver: user approved delivery as "stage files and give me a short commit message" - the outcome is a local commit on feature/arm64-linux-build made by the user; no push or PR requested, 07_Delivery churn stays unstaged.
- 2026-08-31 deliver: closing out before the commit per 6_deliver.md - the local commit is the whole outcome, nothing can fail after it, and this same commit carries the close-out; stage: done, files staged for the user's commit.

## Stage report

stage: validate
result: completed
current: deliver
changed: 16 repo files (4 added, 12 modified, 0 removed) per evolution 2026-08-31T08:42Z, plus .agentic requirements/journal/knowledge
evidence: check --task --strict --run: run test ok 32.5s (suite 5 passed 0 failed 1 skipped), errors=0, warnings=27, strict exit 1 from 2 promoted secret-in-diff on pre-existing uncommitted 07_Delivery x64 binaries excluded from this commit; both WSL dry-runs stage pinned per-arch toolsets; all new digests match GitHub release-API digests
issues: aarch64 image build, emulated/on-Pi compile, AppImage artifact, container run and on-instrument Pi verification all pending - need qemu binfmt on the build host (user action) and Pi hardware; arm64_appimage_smoke.sh exits 77 until an artifact exists
next: present candidate for delivery approval, then commit on feature/arm64-linux-build (no push without approval)
needs_user: yes - deliver-stage approval of the commit, and the one-time binfmt install on the WSL host to run the first aarch64 build

## Delivery report (2026-08-31)

- stage: deliver; type: feature; path: full; branch: feature/arm64-linux-build
- requirements:
  - REQ-PLAT-871c1254 - Derive Linux artifact names and paths from the build architecture
  - REQ-PLAT-aa8d5d46 - Build a self-contained aarch64 AppImage for Raspberry Pi 4 and 5
  - REQ-PLAT-0e73bea7 - Provision the arm64 AppImage builder from pinned verified tools
  - REQ-PLAT-ceeee15c - Report missing arm64 container support on the build host
- deviations: 6 recorded
  - specify: check reports stale-paths on REQ-PLAT-871c1254 and REQ-PLAT-aa8d5d46 for 02_Tools/build/arch_map.sh - accepted, the file is created in build and the warning self-resolves; all other check findings predate this task.
  - build: REQ-PLAT-aa8d5d46 Manual verification not fully carried out - the aarch64 image build, compile, bare-container run and on-Pi run need qemu binfmt (kernel-state change left to the user) plus hours of emulated build and Pi hardware; arm64_appimage_smoke.sh exits 77 until an artifact exists.
  - build: check flags README.md, CHANGELOG.md, 01_Documentation/Environment_Setup.md outside-layout - accepted, documentation is intentionally outside the source/tests globs per aegis.toml's own comment.
  - validate: review claim CONFIRMED against the GitHub release API - linuxdeployqt tag 11 ships linuxdeployqt-continuous-aarch64.AppImage (sha256 c6c078d9...; the same response reproduces the x86_64 digest already in the lock, validating the source). The design's "linuxdeployqt publishes no aarch64 binary" was asserted from memory and is FALSE; returning to build to keep linuxdeployqt on both architectures and drop the linuxdeploy+plugin detour.
  - validate: strict exit 1 accepted - the 2 promoted secret-in-diff findings are unscannable pre-existing binary packages in the working tree, not this task's files; they will not be committed by this task.
  - validate: uncovered-source on 02_Tools/build/STATUS.md accepted - it is the build ledger (documentation) living inside the 02_Tools source glob, updated deliberately per the repository's own ledger convention.
- diff vs task base 5aa2f17: 33 file(s) changed, 1596 line(s) added; 3 file(s) not content-scanned
- checks: errors=0 warnings=28 notes=7
- checklist: 0/6 done; open: validated candidate confirmed unchanged; otherwise returned to validate; validation evidence, diff, exclusions, and outcome presented; delivery confirmed by the human; journal and report included in the delivery commit; agreed outcome delivered, normally a PR; close-out committed after the outcome succeeded, or carried by the delivery commit where nothing could fail after it

<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Changelog

All notable changes to this project are documented in this file. It began as a
Hantek DSO-3062L PulseView integration and now covers two instruments and the
whole vendored sigrok stack.

## [Unreleased]

### Added - August 2026

- **Native Raspberry Pi Debian installer.** `build_deb.sh` checksum-verifies
  and extracts the tested aarch64 AppImage payload into `pulseview-ddp`, which
  installs normal `pulseview`/`sigrok-cli` commands, the desktop menu entry and
  icon, both project drivers, decoders, and udev rules without requiring FUSE.
  The package was installed, GUI-launched, removed with zero owned-path
  leftovers, and reinstalled on the physical Raspberry Pi 4.
- **Five-package release coordinator and integrity gate.** Windows x86_64 ZIP,
  Linux x86_64 AppImage and thin tarball, Raspberry Pi aarch64 AppImage and
  arm64 `.deb` are now one explicit release matrix. The PowerShell owner command
  sequences WSL/container and native Git Bash phases; finalization refuses
  missing, duplicate, or mixed-revision rows and writes one verified
  `SHA256SUMS` covering exactly the five packages. Every individual build also
  emits a `.sha256` sidecar.

- **Raspberry Pi 4/5 (aarch64) build target.** `build_appimage.sh --arch
  aarch64` and `build_linux.sh --arch aarch64` build the whole stack for
  arm64 Linux, natively on a Pi or emulated via qemu binfmt on the x86_64
  build host (`check_host.sh` now reports that capability and its one-line
  fix). One shared table, `02_Tools/build/arch_map.sh`, owns every
  architecture-dependent name - the x86_64 artifact names are pinned
  byte-for-byte by `arch_map_test.sh`. Both architectures use the same
  pinned packaging tools: linuxdeployqt release 11 ships an aarch64 asset
  alongside the x86_64 one. The aarch64 AppImage has been built and verified
  both in a bare emulated Bookworm container and natively on a Raspberry Pi 4,
  including normal FUSE execution and GUI startup under Wayland/XWayland.

### Fixed - August 2026

- **AppImage protocol decoders no longer depend on the host's Python.** The
  AppImage bundled libpython but never the standard library and never set
  PYTHONHOME, so srd_init - and with it all 137 decoders - failed on any
  host without Ubuntu 22.04's exact python3.10 under /usr. Found by the
  aarch64 bare-container decoder gate. build_appimage.sh now bundles the
  stdlib (tests, GUI extras and site packages pruned) before the closure
  pass and AppRun exports PYTHONHOME into the bundle. Both the x86_64 and
  aarch64 delivery AppImages were rebuilt and their UART decoder verified.
- **Linux packaging now fails closed on unusable staged binaries.** The thin
  tarball is written only after sigrok-cli reports its version and lists both
  project drivers; the device-specific show probe remains informational
  because it legitimately fails when no instrument is connected.
- **Build provenance no longer labels dirty inputs as a clean commit.** Linux
  artifacts and generated AppImage READMEs append `-dirty` when tracked or
  untracked build inputs differ from HEAD, while generated delivery and
  scratch output do not affect the label.
- **ARM host readiness is tested by execution.** `check_host.sh` runs a local
  linux/arm64 probe image instead of trusting binfmt metadata and prints an
  immutable, lock-recorded tonistiigi/binfmt digest when remediation is needed.
- **AppImage README compatibility text is architecture-specific.** The
  x86_64 delivery no longer inherits Raspberry Pi-only guidance.
- **The AppImage packaging step no longer reaches the network.** External
  review caught that appimagetool downloads the type-2 AppImage runtime
  from GitHub at packaging time unless told otherwise - an unpinned fetch
  inside a build that claims to be offline, present in every x86_64
  AppImage built so far. Both architectures' runtimes are now pinned by
  SHA-256 in `upstreams.lock.toml`, baked into the builder image, and
  passed to appimagetool with `--runtime-file`.

- **Human- and agent-readable project documentation.** A root `README.md` that
  describes the project as it is rather than as it began,
  `01_Documentation/Environment_Setup.md` covering prerequisites, the two host
  roles and every build command, `01_Documentation/Testing.md` covering the
  suite and the 77-means-skipped convention, and `00_Planning/Overview.md`
  describing the current implementation. The setup knowledge had been correct
  but scattered across five files; none of it was reachable from the front door.
- **`02_Tools/bootstrap/check_host.ps1`.** The Windows counterpart to
  `check_host.sh`, named as planned since the bootstrap contract was written.
  Probes Docker from inside WSL rather than from Windows, checks the toolchain
  archive by size so a Git LFS pointer is caught at once, and rejects
  `System32\bash.exe` when locating Git Bash. Read-only by default; `-Install`
  offers `winget` remediation one package at a time.
- **`02_Tools/test/run_tests.ps1`.** PowerShell entry point to the bash test
  suite. Forwards the exit code verbatim and names 77 as skipped rather than
  letting it read as a pass.

- **`hantek-dso3062l` driver.** Wire protocol recovered from the vendor SDK and
  verified against the instrument: VDIV and coupling across the full 9-range
  ladder, deep capture to 16 Msamples, roll mode, the trigger system, the relay
  chain, and factory offset calibration.
- **`atk-dl16` driver** for the ALIENTEK ATK DL16 logic analyzer, recovered from
  the vendor's GPL sources and verified live. The device sends per-channel
  bitstreams rather than packed samples, so the driver transposes; end-of-capture
  is taken from the byte count order 3 promises, which is the only signal that
  is not a guess. Both instruments build into one PulseView.
- **Self-contained Linux AppImage** (`build_appimage.sh`), verified on a bare
  ubuntu:22.04 with no packages installed.
- Native Linux build (`build_linux.sh`) producing a thin tarball.

### Changed - August 2026

- **The sigrok stack is vendored, not submoduled.** All seven components live in
  `05_Software/` as ordinary files. The submodule mechanism cost two commits per
  change, made history rewriting require gitlink remapping by hand, and turned a
  stale pointer into a silent failure. The project is a standalone fork now: a
  clone carries every source, and `02_Tools/` carries everything that builds
  them.
- The Gitea upstream mirrors were deleted for the same reason - nothing
  referenced them once the submodules were gone. `upstreams.lock.toml` stays as
  the licence and provenance record, and still pins the MXE and packaging tools.
- Deliverables renamed `pulseview-*`: the build serves both instruments, so
  naming them after one was misleading.

### Added

- Initial project structure, advisory AEGIS workflow layout, and project goals
  for the Hantek DSO3062L PulseView integration.
- Detailed agentic implementation planning package covering feasibility gates,
  architecture, upstream repository bootstrap, USB protocol research, phased
  implementation, Windows and Linux builds, deployment, testing, and delivery.
- Complete repository-local AEGIS payload, including canonical lifecycle steps,
  artifact templates, CLI reference, and licence.
- P0 governance baseline with immutable upstream locks, a fail-closed bootstrap
  contract, licence/material boundaries, and research security rules.
- Containerised builder definitions under `02_Tools/build/`: a Debian/MXE image
  for the Windows x86_64 cross-build and an Ubuntu 22.04 image for the Linux
  AppImage, with `build_image.sh` to stage a pinned context and record
  provenance, and `run_in_builder.sh` to run the compile stage.
  `02_Tools/build/STATUS.md` is the ledger; every script in it is now verified
  (that entry recorded the state when they were first written).
- Repository layout contract in `AGENTS.md` fixing `02_Tools/` for all
  project-owned scripts, `07_Delivery/` for finished packages, and `.work/`
  for intermediate output.

### Changed

- Refined the Codex implementation plan after reviewing the independent assistant
  plan: corrected logic thresholds to a 16-entry per-channel hypothesis, added
  an optional isolated x86 SDK reference harness, split vendor characterization
  from native USB proof, expanded driver rollback and hardware checkpoints,
  added a cross-platform result matrix, and consolidated risks, open questions,
  and pivot criteria.

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

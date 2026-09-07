<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

All notable changes to this project are documented in this file. It began as a
Hantek DSO-3062L PulseView integration and now covers two instruments and the
whole vendored sigrok stack.

## [Unreleased]

### Added - September 2026

- **Transactional builder-environment lifecycle.** Builder dependencies now
  come from strict architecture-selected contracts that generate Docker package
  input and are embedded with a resolved transitive inventory. Separate recipe,
  dependency-contract, and validation-policy identities avoid unnecessary
  rebuilds. `update_builder_environment.sh` builds isolated candidates, creates
  policy-keyed validation evidence and SPDX 2.3 JSON, audits schema-2 multipart
  archives, rolls back pre-commit failures, commits the stable manifest as the
  final filesystem promotion, and only then applies the stable local image tag.
  Installed current images no longer require archive files; legacy and stale
  historical restores require explicit modes.
- **Local multipart builder-image bootstrap.** The Windows/MXE and both
  AppImage builder architectures are stored as 1 GiB Git LFS parts with a
  small TOML manifest that pins every part, the reconstructed Docker archive,
  and the exact image ID by SHA-256. `ensure_build_environment.sh` and its
  PowerShell/WSL entry point validate an installed image, restore it entirely
  from local LFS content, or offer an explicit online rebuild from the pinned
  repository inputs. The workflow never downloads LFS content and never
  uploads or publishes an image. `save_image_parts.sh` regenerates the local
  multipart files when a maintainer deliberately replaces a builder. Debian
  Bookworm and Ubuntu 22.04 bases are now digest-pinned in the upstream lock,
  and the optional MXE rebuild uses its locked canonical HTTPS source rather
  than the deleted Gitea mirror.

### Fixed - September 2026

- **Removed stale builder-lifecycle guidance.** Current-state documentation now
  lists all five delivery packages and four target build scripts, routes normal
  AppImage setup through the bootstrap, explains the temporary schema-1 option
  in quick-start instructions, and describes the selected-input recipe
  identity accurately. Public examples and diagnostics consistently invoke
  mode-100644 project scripts through Bash, and lifecycle tests no longer cite
  requirement records that are not part of the repository.
- **Builder lifecycle operations now work from a mode-100644 clone without
  loading multi-gigabyte archives into memory.** Bootstrap, candidate update,
  and container re-entry invoke project shell scripts explicitly through Bash.
  Manifest and fixed-file hashing now stream bounded chunks, successful archive
  audits remove their temporary reconstructed tar, cached MXE input is rejected
  if it differs from the pinned commit, failed mandatory reruns cannot retain a
  stale pass report, and validation-policy identity includes smoke-test helper
  inputs as well as the top-level test scripts. AppImage promotion also uses
  the exact locked clean-base digest instead of depending on a separately
  cached floating Ubuntu tag.
- **Builder recipe identity now covers selected image-content inputs.**
  `builder_spec.sh` previously hashed broad lock and build-driver bytes while
  missing effective patch and option changes. It now hashes the normalized
  selected contract, consumed lock fields, Dockerfile and helper bytes,
  canonical profile, selected patch bytes, effective options, and metadata
  finalization input. Validation-only changes have a separate policy identity.
  The automatic MinGW profile excludes the obsolete `mxe_fixes.patch` and keeps
  `libusb1_upgrade.patch`; ordinary builds need no remembered skip option.
- **The build host's Python prerequisite is real, checked, and documented.**
  `ensure_build_environment.sh` and `build_image.sh` read pinned TOML with
  `tomllib`, standard library only from CPython 3.11, while
  `Environment_Setup.md` listed `python3` as *not* required on the build host
  and `check_host.sh` did not check it at all - so a 3.10 host got a
  `ModuleNotFoundError` traceback out of a heredoc. A shared
  `02_Tools/build/python_env.sh` now selects an interpreter that can actually
  import the module and otherwise fails with the minimum version and the
  install command; `check_host.sh` reports it as its own row.
- **The native Linux build no longer launches a floating tag.**
  `build_linux.sh` ran `ubuntu:24.04`, the one build path in the release
  coordinator with no reproducible base. It now resolves the digest-pinned
  `builder-base-ubuntu-24.04` artifact from `upstreams.lock.toml` and stops if
  that entry is absent. Its current apt-based implementation still needs the
  network on every run; making it offline would require an archived builder or
  pinned package snapshot/cache. `02_Tools/build/README.md` now states per-path
  network requirements instead of claiming that normal builds need none.
- **`check_host.sh` and `build_linux.sh` honour the selected container
  engine.** Both hardcoded `docker` while every other entry point offered
  `--engine docker|podman`, so a Podman host was told it had no engine.
  `check_host.sh` also gained the multipart archive check that `check_host.ps1`
  has always had, reporting missing parts and Git LFS pointer files without
  performing the bootstrap's full checksum pass.
- **Corrected stale build documentation.** `images/README.md` described the
  AppImage builder as x86_64-only and documented `MXE_APPLY_SIGROK_PATCHES`,
  which the Dockerfile replaced with `MXE_PATCHES`; `bootstrap/README.md`
  withdrew the obsolete `clone_upstreams.py` plan, which existed to materialize
  submodules the repository no longer has; `Environment_Setup.md` no longer
  presents `/mnt/f/2026_PulseView` as universal and no longer claims that
  nothing needs privileges, which was untrue of WSL and engine installation and
  of arm64 binfmt registration. Documented invocations use `bash <path>`
  because every tracked script has Git mode `100644` and a fresh clone cannot
  execute them directly.
- **Documented the preferred Windows route.** `Environment_Setup.md` now gives
  a step-by-step Docker Engine install inside WSL2 Ubuntu, with Docker Desktop
  as an explicit alternative rather than the assumed default.
- **Recorded builder aggregate licensing and inventory.**
  `07_Delivery/toolchain/README.md` states that the `GPL-3.0-or-later` OCI
  label describes this project's own recipe and that the image is an aggregate
  under upstream terms. New schema-2 generations now include a resolved package
  inventory and identity-bound SPDX 2.3 JSON SBOM.

### Changed - September 2026

- **Relicensed the software to GPL-3.0-or-later, ahead of publication.** The
  repository previously declared PolyForm Noncommercial 1.0.0 over everything,
  including the vendored GPL sigrok stack. GPLv3 section 7 forbids adding a
  restriction of that kind, so the claim was void as to those trees and could
  not be published as written. `LICENSE.txt` is now the GPL-3.0 text and covers
  `05_Software/` (including this project's `hantek-dso3062l` and `atk-dl16`
  drivers and the added decoders, which compile into GPL works and could never
  have carried other terms), `01_Documentation/`, `02_Tools/`, `06_SoftwareDocu/`
  and `07_Delivery/`. Three independent paths keep PolyForm Noncommercial in the
  new `LICENSE-PolyForm.txt`: `.agentic/`, `00_Planning/` and
  `05_Software/protocol_probe/`. The new `LICENSING.md` is the authoritative
  path-by-path map and governs where any file header disagrees.
- **Binary packages now carry a licence and corresponding-source notice.** The
  AppImage and `.deb` READMEs state the GPL terms and name the source revision,
  which GPLv3 section 6 requires of a distributed binary. The builder images'
  `org.opencontainers.image.licenses` label was corrected to `GPL-3.0-or-later`.
- **`04_HardwareDocu/README.md` now separates vendor material from our own.**
  The Hantek SDK, driver package and product manuals are manufacturer-supplied
  reference material under their originator's terms - neither GPL nor PolyForm,
  and not ours to license. The protocol analyses beside them are original work
  and are GPL along with the drivers they document.

### Renamed - September 2026

- **The Windows cross-toolchain image is no longer named after one instrument.**
  `hantek-builder-<image>` became `pulseview-builder-<image>` and the build
  volume `hantek-build-<image>` became `pulseview-build-<image>`. Because
  `docker load` restores the tag embedded at save time rather than the
  archive's filename, renaming the file alone would have left the old tag
  inside it; the archive was therefore re-saved under the new tag rather than
  worked around in the loader. The image is bit-identical - digest
  `sha256:9ae809d6c312484080b04a424850929ca302a2c3aab5a431d24b412a00551293`
  before and after - and only the embedded repository tag differs. The
  reconstructed multipart archive retains sha256
  `1893cd83f335e5f755b5eae87959fe0a2348665db41a43056ea7fbab6659384e`.
  The `hantek-dso3062l` driver keeps its name - that is a device driver, not
  build infrastructure.

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

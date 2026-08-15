<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Changelog

All notable changes to the Hantek DSO3062L PulseView integration are documented
in this file.

## [Unreleased]

### Added

- Initial project structure, advisory AEGIS workflow layout, and project goals
  for the Hantek DSO3062L PulseView integration.
- Detailed agentic implementation planning package covering feasibility gates,
  architecture, upstream repository bootstrap, USB protocol research, phased
  implementation, Windows and Linux builds, deployment, testing, and delivery.

### Changed

- Refined the Codex implementation plan after reviewing the independent assistant
  plan: corrected logic thresholds to a 16-entry per-channel hypothesis, added
  an optional isolated x86 SDK reference harness, split vendor characterization
  from native USB proof, expanded driver rollback and hardware checkpoints,
  added a cross-platform result matrix, and consolidated risks, open questions,
  and pivot criteria.

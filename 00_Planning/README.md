<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE-PolyForm.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Planning

Project scope, architecture decisions, milestones, and implementation plans.

## Documents

- [Overview](Overview.md) - what the project is and what is in it, in the
  present tense. Start here.
- [Builder Environment Lifecycle Improvement Plan](Builder_Environment_Lifecycle_Improvement_Plan.md)
  - proposed work to make builder dependencies declarative, verify environment
  completeness, detect stale archives, and update multipart builder images
  safely without publishing them.

The original project goals, the Codex implementation package and the
greenfield PulseView-type application plan were all removed once the work
they described was done. The result is documented where it is actually useful:
the wire protocols in `04_HardwareDocu/<device>/`, the build and packaging
in `02_Tools/build/`, and the drivers themselves in
`05_Software/libsigrok/src/hardware/`. A plan that no longer matches the
code is worse than no plan, because it still reads as authoritative.

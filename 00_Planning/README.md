<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Planning

Project scope, architecture decisions, milestones, and implementation plans.

## Documents

- [Project goals](00_Project_Goals.md)

The Codex implementation package and the greenfield PulseView-type
application plan were removed in August 2026. Both described work that has
since been done, and the result is documented where it is actually useful:
the wire protocols in `04_HardwareDocu/<device>/`, the build and packaging
in `02_Tools/build/`, and the drivers themselves in
`05_Software/libsigrok/src/hardware/`. A plan that no longer matches the
code is worse than no plan, because it still reads as authoritative.

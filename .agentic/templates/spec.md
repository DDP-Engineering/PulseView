<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

<!--
Spec for one requirement, at .agentic/specs/<REQ-ID>.md, referenced by
that requirement's `spec` field. A spec exists only when the requirement
alone is not enough to build from — a format, a protocol, a non-obvious
algorithm. Sections below are recommended, not mandatory.
-->

# REQ-FUNC-0000 — <requirement title>

## Behavior

What the system does, in enough detail to implement without guessing.
Cover the normal case first, then the edges and the error cases.

## Data / interface

Function signatures, command lines, file formats, schemas, wire formats.
Be exact about names, types, units, and defaults.

## Examples

Concrete input and expected output, including at least one edge case.
These are the natural seeds for the failing test written in build.

## Acceptance

What must be true for this spec to be considered satisfied, phrased so it
can be checked. This refines the requirement's `verification` field; it
never contradicts it.

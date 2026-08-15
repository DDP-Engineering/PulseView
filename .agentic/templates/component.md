<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

<!--
Component knowledge page, at .agentic/knowledge/<component>.md, one per
component. This is what a session loads instead of re-reading the whole
component's source, so keep it short, current, and true. Updated at
validate whenever the component's behavior, interface, or file set changed.
Sections below are recommended, not mandatory.
-->

# <component name>

## Purpose

Two or three sentences: what this component is responsible for, and what
it deliberately is not responsible for.

## Public interface

How the rest of the system uses it — entry points, exported functions or
classes, commands, input and output formats. Not the internals.

## Key behaviors

- `REQ-FUNC-0000` — one line describing the behavior.
- One line per behavior that has no requirement yet, marked `(no req)`.

## Files

- `src/<component>/<file>.py` — one line on its role.

Keep this list complete: it is how a reader finds the code, and stale
entries are the first sign the page has drifted.

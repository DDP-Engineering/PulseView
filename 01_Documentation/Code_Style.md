<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Code Style

## Purpose

This document defines the code style, documentation style, and related
implementation readability rules for AEGIS.

## General Code Style

- Code must be clear, simple, and easily maintainable by a human developer.
- Prefer small, composable modules.
- Avoid unnecessary abstraction, wrapper classes, and speculative architecture.
- Keep implementation sufficiently documented so intent, contracts, and
  non-obvious logic remain understandable during maintenance.
- Keep responsibilities separated across parsing, processing, orchestration,
  export, and UI.
- Avoid host-specific assumptions in reusable code.
- Prefer deterministic local configuration and storage paths.
- Preserve public interfaces unless change is explicitly requested.

## Python Documentation Style

For Python source and test files, use a consistent engineering-style header and
Doxygen-like documentation pattern.

Required file prologue:

1. shebang: `#!/usr/bin/env python3`
2. encoding line: `# -*- coding: utf-8 -*-`
3. copyright/license banner using dashed separator lines
4. module docstring with aligned tags. The following are required:
   - `@file`
   - `@brief`
   - `@details`
   Optional only when relevant:
   - `@example`

Docstrings carry no authorship or version tags (no `@author`, `@date`, or
`@version`) at module, function, method, class, or nested-helper level. The
file-top copyright/license banner is the sole in-file attribution. Versioning
is project-level only, tracked in the AEGIS payload version and the existing
changelog.

The banner to copy is the GPL one at the top of this file, which is correct for
almost everywhere. Three paths take the PolyForm banner instead - `.agentic/`,
`00_Planning/` and `05_Software/protocol_probe/`; copy it from an existing file
there. Inside the vendored trees under `05_Software/`, use that project's own
per-file header, not this one. [`LICENSING.md`](../LICENSING.md) is the map, and
governs if anything disagrees.

Required section markers where meaningful:

- `IMPORTS`
- `CONSTANTS`
- `DATA MODELS / TYPEDEFINITIONS`
- `HELPER FUNCTIONS` or `LOCAL HELPERS`
- `PUBLIC API` or `EXPORTED FUNCTIONS / PUBLIC API`
- `END OF FILE`

Function, method, class, and nested-helper docstrings should use Doxygen-like
tags whenever the callable or type is non-trivial, part of the public API,
implements important logic, or benefits from an explicit contract.

Required when applicable:

- `@brief`
- `@param[in]`
- `@param[out]`
- `@param[in,out]`
- `@return`

Use when applicable:

- `@exception`
- `@note`
- `@todo`
- `@retval`
- `@example`

Guidance:

- trivial one-line helpers may omit docstrings if the intent is already obvious
- public API functions should normally have docstrings
- classes should have a class-level docstring
- nested wrappers and decorator helpers should be documented when they carry
  non-obvious behavior

Keep these comments concise and engineering-focused. Avoid placeholder prose or
casual commentary.

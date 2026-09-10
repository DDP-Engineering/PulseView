<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt in the .agentic folder for full license details.
SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

<!--
Component knowledge page, at .agentic/knowledge/<component>.md, one per
component. This is the orientation route a session loads before inspecting
the implementation, so keep it short, current, and true. It reduces broad
discovery; it never replaces verification against the implementation. The
exact source and tests remain authoritative.

Updated at validate whenever the component's routing, boundary, invariant,
behavior, interface, architecture, or file set changed. Keep the standard
sections below. `Change map` is conditional as described in that section.
Describe only the current implementation and its positive behavior contract.
Keep proposals, removed features, before/after comparisons, suspected defects,
and decision history in task records. Preserve meaningful error and security
behavior as explicit conditions and responses. Link active requirements;
resolve a conflict with the owner rather than silently weakening a contract.
-->

# <component name>

## Routing

Name the request signals that select this page: domain terms, public names,
commands, events, and owned paths. Give the first source entry point and the
focused test location for this component. Name the nearest page or component
for requests that sound similar but belong elsewhere.

This section should let an agent decide quickly whether the component owns the
work and where exact inspection starts. It should not summarize the internals.

## Purpose and boundaries

Two or three sentences describing this component's current responsibilities.
Name adjacent components and their actual responsibilities where that clarifies
ownership. Describe what exists, using positive responsibility assignments.

## Public interface

How the rest of the system uses it — entry points, exported functions or
classes, commands, input and output formats. Not the internals.

## Invariants

List the properties a safe change must preserve: ordering, precedence,
authority, compatibility, failure, security, or data rules. Include only
claims supported by current source, tests, or durable requirements. Prefer a
small set of load-bearing rules over a behavior inventory.

## Change map

Keep this section when the component has multiple independent edit-and-test
seams. Omit it for a simple component where Routing and Files already identify
one obvious seam. Map request shapes to searchable source symbols or files and
focused verification; do not duplicate a call graph or full test inventory.

| Change requested | Start with | Focused verification |
|---|---|---|
| `<request shape>` | `<searchable symbol or file>` | `<test file or selector>` |

## Key behaviors

- `REQ-FUNC-0000` — one line describing the behavior.
- One line per behavior that has no requirement yet, marked `(no req)`.

## Architecture

How this component works inside, as a Mermaid diagram. Scope it to this
component: the parts a reader has to hold in their head to change it
safely, and the boundaries where it meets everything else. Not the whole
system, and not every function — if it does not change how someone would
edit this code, leave it out. Ten to fifteen nodes is usually the honest
size; past twenty, the component is probably two.

Arrows carry direction, so only draw one where you can say which way it
points: calls, data flow, ownership. Name each node after the thing in the
code, so a reader can search for it, and mark the boundary nodes — entry
points, storage, anything outside this component — differently from the
internals.

```mermaid
flowchart TD
    entry(["<entry point>"])
    entry --> step["<the work it delegates to>"]
    step --> store[("<what it reads or writes>")]
```

One or two sentences under the diagram for its scope and the current
constraint that explains its shape. Keep this drawn as the code is
now. A task records a proposed shape in its design, then updates this current
diagram at validate after the implementation matches.

## Files

- `src/<component>/<file>.py` — one line on its implementation role.
- `tests/<component>/test_<behavior>.py` — one line on the behavior seam it
  verifies.

Keep the owned implementation and focused test list complete: it is how a
reader confirms the route, and stale entries are the first sign the page has
drifted.

<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Codex implementation planning package

## Purpose

This package is the execution map for integrating the Hantek DSO3062L with
libsigrok and PulseView. It is written for resumable development by Codex,
AI assistant, or another repository-aware engineering agent.

The package is a plan, not evidence that the driver already works. Every
hardware claim must ultimately be backed by a recorded capture or a test on a
physical DSO3062L.

## Reading order

| Order | Document | Use |
|---:|---|---|
| 1 | [Feasibility and decision gates](01_Feasibility_and_Decision_Gates.md) | Understand what is known, conditional, and blocked. |
| 2 | [Architecture](02_Architecture.md) | Understand runtime layers, source boundaries, data flow, and trigger strategy. |
| 3 | [Repository and toolchain bootstrap](03_Repository_and_Toolchain_Bootstrap.md) | Initialize Git with approval, clone pinned upstream sources, and prove baseline builds. |
| 4 | [Implementation roadmap](04_Implementation_Roadmap.md) | Execute the work in dependency order with exit gates. |
| 5 | [USB protocol and hardware research](05_USB_Protocol_and_Hardware_Research.md) | Characterize the proprietary USB protocol safely and reproducibly. |
| 6 | [Build, deployment, and release](06_Build_Deployment_and_Release.md) | Implement build and packaging automation for Linux and Windows. |
| 7 | [Test and acceptance](07_Test_and_Acceptance.md) | Produce offline, integration, hardware, and platform evidence. |
| 8 | [Agentic execution playbook](08_Agentic_Execution_Playbook.md) | Start, resume, checkpoint, and hand off work under AEGIS. |
| 9 | [Risks and open questions](09_Risks_and_Open_Questions.md) | Track uncertainties, mitigations, pivot criteria, and owner decisions. |

## Fixed project decisions

- Implement device support in **libsigrok**, not as a PulseView-only plugin.
- Use a native **libusb** transport on Linux and Windows.
- Use **WinUSB** for the production Windows runtime; retain the Hantek driver
  only while capturing reference behavior.
- Treat the 32-bit Hantek SDK as a Windows reference oracle, never as a
  production or Linux dependency.
- If needed, build a narrowly scoped 32-bit Windows SDK reference harness for
  characterization only. It is not a PulseView bridge and is not delivered.
- Treat the SDK's 16-element logic-threshold array as evidence for a
  per-channel threshold candidate; advertise only the granularity proven on
  the connected device.
- Deliver simple triggers before extending libsigrok and PulseView for complex
  trigger expressions.
- Keep GPL upstream source and the PolyForm-licensed project material in
  separate repositories or submodules.
- Pin every upstream revision used for development and delivery.
- Do not redistribute Hantek DLLs, drivers, firmware, or calibration material
  without a verified redistribution right.

## Resumption rule

An agent must read the root `AGENTS.md`, `.agentic/AGENTS.md`, the active AEGIS
task journal, this index, and only then the document for the current phase.
The agent must not infer that a planned command was executed or that a hardware
gate passed merely because it appears in this package.

## Research snapshot

The upstream source survey was performed on 2026-08-15 against these revisions:

| Repository | Surveyed revision |
|---|---|
| `sigrokproject/libsigrok` | `0bc2487778e660f4d3116729b6f4aee2b1996bb0` |
| `sigrokproject/pulseview` | `af02198741b4e57c9f9b796bd5e6c0f2ae9f2f2b` |
| `sigrokproject/sigrok-cli` | `f44dd91347e7ac797cefc23162b9fcf0b7329f1f` |
| `sigrokproject/libsigrokdecode` | `71f451443029322d57376214c330b518efd84f88` |
| `sigrokproject/libserialport` | `21b3dfe5f68c205be4086469335fd2fc2ce11ed2` |
| `sigrokproject/sigrok-util` | `249b79d0a94e9ac4ec96533bf3108e2a50e6b38d` |

These are research pins, not permanent release pins. The bootstrap phase must
refresh upstream state, review changes, and deliberately write the chosen
commits to the project lock file.

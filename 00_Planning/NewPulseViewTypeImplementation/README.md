<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# New PulseView-Type Application Planning

This directory contains the architecture and agentic implementation plan for
an independent signal-acquisition and protocol-analysis application inspired
by PulseView.

The proposal is an alternative product direction. It does not replace the
existing plan to integrate the Hantek DSO3062L into PulseView and libsigrok
unless that decision is made explicitly.

## Documents

- [Architecture and implementation plan](01_Architecture_and_Implementation_Plan.md)

## Initial product scope

- Hantek DSO3062L analog acquisition.
- One separately identified eight-channel logic analyzer, referred to in the
  plan as LA8ch.
- UART, I2C, and SPI protocol decoding.
- Windows and Linux support.
- Offline-capable development kits and portable runtime archives.
- Extension contracts that make new hardware drivers and protocol decoders
  routine additions.

## Status

This is a proposed architecture and staged implementation plan. It does not
record approval to stop the existing PulseView integration work, copy GPL
implementation material, select a product name, or begin implementation.

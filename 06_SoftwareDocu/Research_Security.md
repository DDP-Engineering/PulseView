<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Research and automation security

## Authority model

An agent may continue read-only inspection and offline implementation within
the approved task scope. Silence, an ordinary continuation, or access to an
administrator account does not authorize a sensitive action.

| Action | Marker | Required approval and preflight |
|---|---|---|
| Read files, inspect Git status/remotes, query upstream metadata | none | In-scope task |
| Create or change branch, add submodule, stage, commit, push, merge, fork, PR | `[HUMAN]` | Exact repository, branch/path, URL, commit, and intended outcome |
| Install build/capture software or system packages | `[ADMIN]` | Package/source/version, host effect, rollback, explicit elevation |
| Connect or acquire from DSO3062L using current binding | `[DEVICE]` | Safe signal setup, binding, volatile operation, duration, output path |
| Replace Windows USB binding or install/remove a driver | `[HUMAN][ADMIN][DEVICE]` | Exact PnP instance, current/target driver, backup, restore proof |
| Call vendor SDK reference harness | `[VENDOR][DEVICE]` | DLL hashes, documented volatile call, timeout, application closed |
| Firmware, FPGA, EEPROM, serial, or calibration write | prohibited by default | Separate risk review and explicit operation-specific approval |
| Upload or publish source, captures, binaries, or release artifacts | `[HUMAN]` | Exact artifact inventory, licences, destination, visibility, hashes |

## USB and device safety

- Use conservative input voltage and probe settings within the manual limits.
- Start with read-only inventory and normal acquisition; change one volatile
  configuration value per controlled experiment.
- Bound every poll, transfer, allocation, sample count, cancellation, and
  process lifetime.
- Never replay an unknown command that might alter persistent state.
- Stop for repeated disconnects, abnormal heat, calibration errors, unexpected
  persistence, electrical uncertainty, or a hung vendor call.
- Preserve driver identity and a tested restoration procedure before WinUSB
  rebinding. Automation may verify binding but may not change it silently.

## Vendor reference harness

The optional 32-bit Windows harness is a research oracle only. It accepts an
explicit local DLL directory, verifies hashes, loads documented exports only,
and uses fixed-size, typed inputs. It must not load arbitrary DLLs, invoke an
arbitrary export name, guess a signature, bridge PulseView, or enter delivery.

If IPC is later approved, use a versioned length-prefixed schema, fixed-width
fields, strict size limits, owner-only local endpoints, an unpredictable
session nonce, per-request deadlines, and forced child cleanup. Never transmit
pointers or raw vendor structures across the boundary.

## Parser and capture-data security

- Parse lengths before allocating or dereferencing and reject overflow,
  truncation, impossible counts, invalid enums, and unexpected markers.
- Treat device bytes, PCAP files, and minimized fixtures as untrusted input.
- Keep raw PCAP and calibration data under ignored `.work/captures/raw/` paths.
- Track only minimized fixtures with a manifest, source hash, purpose,
  disclosure classification, and removal of unrelated payloads.
- Logs record identifiers, sizes, hashes, state transitions, and errors, not
  complete captures, credentials, or private calibration contents.

## Host and supply-chain security

- Use HTTPS canonical URLs plus immutable commits/digests from the lock.
- Verify repository identity and dirty state before any checkout mutation.
- Run downloaded tools only from pinned, reviewed sources or approved system
  packages; record versions and hashes.
- Do not use shell evaluation, base64 command transport, or user prompt text on
  command arguments to cross a trust boundary.
- Resolve cleanup targets to verified absolute paths inside the intended
  workspace; never recursively delete a repository root or unresolved path.

## Evidence and rollback

Every sensitive action record names the operator approval, host, device/PnP
identity, current and target state, exact command or UI steps, timestamps,
result, evidence hashes, and rollback result. A build, offline fixture, vendor
capture, Windows/WinUSB test, and Linux/libusb test are distinct evidence
classes and are never substituted for one another.

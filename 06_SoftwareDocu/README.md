# Software documentation

Installation, usage, architecture, and development documentation for project software.

The governance and research-security notes that used to live here were removed
in August 2026 - they set out rules for a project that was still deciding what
it was allowed to do. What actually governs the work now is concrete and lives
with the thing it governs:

- Licensing: `LICENSING.md` at the root is the path-by-path map, `LICENSE.txt`
  is the GPL-3.0 text that covers the software, and the per-component upstream
  licences are recorded in `02_Tools/upstream/upstreams.lock.toml`. The vendored
  sigrok stack under `05_Software/`, this project's own drivers and decoders
  inside it, the build tooling and the delivered packages are all GPL-3.0-or-later.
  Three independent paths - `.agentic/`, `00_Planning/` and
  `05_Software/protocol_probe/` - are PolyForm Noncommercial instead; see
  `LICENSE-PolyForm.txt`.
- Device safety: the drivers never write calibration, flash or EEPROM. See the
  protocol references in `04_HardwareDocu/<device>/` for what each opcode does
  and which ones were deliberately left alone.

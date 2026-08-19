# Software documentation

Installation, usage, architecture, and development documentation for project software.

The governance and research-security notes that used to live here were removed
in August 2026 - they set out rules for a project that was still deciding what
it was allowed to do. What actually governs the work now is concrete and lives
with the thing it governs:

- Licensing: `LICENSE.txt` at the root, and the per-component upstream licences
  recorded in `02_Tools/upstream/upstreams.lock.toml`. The vendored sigrok stack
  under `05_Software/` is GPL; this project's own code is PolyForm
  Noncommercial.
- Device safety: the drivers never write calibration, flash or EEPROM. See the
  protocol references in `04_HardwareDocu/<device>/` for what each opcode does
  and which ones were deliberately left alone.

# Tools

Project setup, maintenance, conversion, and validation tools.

Every project-owned script lives here, including scripts that only ever run
inside a container. Intermediate output goes to `.work/`; only finished,
verified artifacts go to `07_Delivery/`.

- `upstream/` contains immutable external-source locks and their review rules.
- `bootstrap/` defines the fail-closed contract for future workspace tools.
- `build/` holds the builder container definitions and the build drivers for
  the sigrok stack. See its `README.md` for the two-stage model and
  `STATUS.md` for what is implemented versus verified.

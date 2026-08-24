# Tools

Project setup, maintenance, conversion, and validation tools.

Every project-owned script lives here, including scripts that only ever run
inside a container. Intermediate output goes to `.work/`; only finished,
verified artifacts go to `07_Delivery/`.

- `upstream/` contains immutable external-source locks and their review rules.
- `bootstrap/` holds the host readiness checks - `check_host.sh` for a Linux or
  WSL build host, `check_host.ps1` for a Windows one - and defines the
  fail-closed contract for future workspace tools.
- `build/` holds the builder container definitions and the build drivers for
  the sigrok stack. See its `README.md` for the two-stage model and
  `STATUS.md` for what is implemented versus verified.
- `test/` holds the suite. `run_tests.sh` is the driver and is what
  `.agentic/aegis.toml` points its `test` command at; `run_tests.ps1` is the
  PowerShell entry point to the same suite.

Start with `01_Documentation/Environment_Setup.md` and
`01_Documentation/Testing.md`; they are the operator's route through all of
this.

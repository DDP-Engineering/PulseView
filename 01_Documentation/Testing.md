<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Testing

The suite lives in `02_Tools/test/`. It tests **built artifacts**, not source:
every test drives a staged `sigrok-cli` and asserts on what it prints. That
shapes everything else on this page, including why a test can legitimately
decline to run.

## Running it

On Linux, in WSL, or in Git Bash on Windows:

```bash
bash 02_Tools/test/run_tests.sh
```

From a PowerShell prompt:

```powershell
.\02_Tools\test\run_tests.ps1
```

The PowerShell entry point locates Git Bash, translates the repository path, and
forwards the exit code verbatim. It is a real entry point, not a wrapper that
swallows failures - if it cannot find `bash.exe` it says so and exits 77.

Both accept an alternative staging directory:

```bash
bash 02_Tools/test/run_tests.sh 07_Delivery/staging/pulseview-linux-x86_64
```

```powershell
.\02_Tools\test\run_tests.ps1 -StagingDir 07_Delivery\staging\pulseview-linux-x86_64
```

`run_tests.sh` is also what `.agentic/aegis.toml` points its `test` command at,
so an AEGIS `check --run` executes exactly this.

## Exit codes, and why 77 matters

| Code | Meaning |
|---|---|
| 0 | Passed. |
| 1 | Failed. |
| **77** | **Could not run here. Not a pass.** |

77 is the autotools convention, and it is load-bearing. These tests need a
staged tree *and* a way to execute it - a Windows host or Wine for the `.exe`, a
`python3` for the capture generator. On a machine with neither, "skipped" is the
truthful answer and pretending otherwise would be worse than useless.

`run_tests.sh` reports skips on their own line and in the summary, and if
**everything** skipped it exits 77 itself with `nothing ran; this is not a
passing suite`. A green suite that executed no assertion is not a green suite.

## The tests

### `windows_python_smoke.sh`

Proves the embedded Python works and every installed decoder is visible.

```bash
02_Tools/test/windows_python_smoke.sh [staging-dir]
```

Default staging dir: `07_Delivery/staging/pulseview-windows-x86_64`.

It asserts, in order:

1. The Python reported by `sigrok-cli --version` is 3.9 or newer.
2. Every decoder directory on disk - minus `common` and `__pycache__` - appears
   in `sigrok-cli -L`.
3. A probe decoder written on the fly using f-strings, annotations, `IntFlag`
   and `dataclass` loads and is listed. This is the test that would have caught
   the old Python 3.4.4 runtime, which loaded decoders fine right up until one
   used modern syntax.
4. Removing the probe returns the count to baseline.

Note that step 3 **transiently writes into the staged tree**, at
`share/libsigrokdecode/decoders/zz_fstring_probe/`. A trap removes it and every
`__pycache__` on exit. If a run is killed hard, check for that directory before
shipping the tree.

Needs: a runner for the `.exe` - Windows natively, or `wine64`/`wine` elsewhere.
No Python on the host, no pytest.

### `networking_stack_decode_smoke.sh`

Proves the first-party decoder chain actually *decodes*, which the test above
deliberately says nothing about.

```bash
02_Tools/test/networking_stack_decode_smoke.sh [staging-dir]
```

`gen_networking_stack_captures.py` builds two real Ethernet II frames - correct
FCS, IPv4 header checksum and UDP checksum - and encodes them as the exact
inverse of the `nrzi` and `4b5b` decoders' own state machines, down to a raw
one-byte-per-sample stream. libsigrok's `binary` input module feeds that to
`sigrok-cli`:

```
-P nrzi:preamble_len=4,4b5b,ethernet,arp
-P nrzi:preamble_len=4,4b5b,ethernet,ipv4,udp:format=ascii
```

The test then requires 23 specific field values to appear in the annotation
output: the broadcast destination MAC, `EtherType: Address Resolution Protocol
(0x0806)`, `Who has 10.0.0.2? Tell 10.0.0.5 (02:00:00:00:00:01)`, the IPv4
addresses and protocol, ports 40000 and 5353, three separate checksum `OK`s, and
each byte of the `BATCH1OK` payload.

Needs: `python3` or `python` on PATH (standard library only - `struct`, `sys`,
`zlib`), plus a runner for the CLI. Pass the Linux staging tree's path
explicitly to check that build; there is no Wine fallback for the Linux binary
since it is not a `.exe`.

## Writing a new test

`run_tests.sh` globs `*_smoke.sh` and `*_test.sh` in its own directory, so a new
file matching that pattern is picked up with no registration step.

- **Name it `<subject>_smoke.sh` or `<subject>_test.sh`**, in `02_Tools/test/`.
  Every project-owned script lives under `02_Tools/`, without exception.
- **Carry the licence header.** Copy the six-line block from the top of any
  existing test; the exact wording is at the top of
  [Code_Style.md](Code_Style.md).
- **Derive paths from the script's own location**, never from the working
  directory:
  ```bash
  REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
  STAGE="${1:-${REPO}/07_Delivery/staging/pulseview-windows-x86_64}"
  ```
- **Honour the 77 contract.** If the prerequisite for running is absent - no
  runner, no `python3` - print a `skip:` line and `exit 77`. Reserve exit 1 for
  a real failure, including a missing staged tree, which is a setup error rather
  than an inability to run.
- **Assert on values, not on loading.** A decoder that loads and decodes nothing
  is a failure, not a pass. This is the standing bar, written down as
  `REQ-FUNC-f9a157d9` in `.agentic/requirements/functional/`: a decoder test must
  show real field values coming out of the real decoder.
- **Clean up after yourself**, with a trap, if you write into the staged tree.

## What is not in the suite

**Hardware-in-the-loop verification is manual.** Both drivers were verified
against real instruments - VDIV and coupling across the nine-range ladder, deep
capture to 16 Msamples, roll mode, the trigger system, the relay chain, factory
offset calibration on the Hantek; the per-channel bitstream transposition and
end-of-capture handling on the ATK-DL16 - but none of it is automated, because
it needs the instrument on the bench. What each opcode does, and which ones are
safe to send, is recorded per device in `04_HardwareDocu/<device>/`.

**libsigrok's own unit tests do not run on the Windows build.** `check` is
excluded from the MXE package set - libcheck and winpthreads clash over
`clock_gettime` - so they cannot be cross-built. See
`02_Tools/build/STATUS.md`.

**There is no CI.** Tests are run by hand, on the host that can run them.

## See also

- [Environment_Setup.md](Environment_Setup.md) - producing the staged trees the
  tests need.
- [`02_Tools/build/STATUS.md`](../02_Tools/build/STATUS.md) - which scripts are
  verified, on which host, with which command.

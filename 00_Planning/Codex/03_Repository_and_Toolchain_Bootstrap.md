<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Repository and toolchain bootstrap

## Goal

Produce a reproducible, source-controlled workspace with separate upstream GPL
forks, pinned dependency inputs, clean baseline builds, and no implicit Git or
publication action.

## Preconditions

- The owner explicitly authorizes each Git mutation: initialization, branch
  creation, adding submodules, staging, committing, pushing, and opening an
  upstream request are separate actions.
- Git, Python 3.12 or newer, and PowerShell 7 are available on Windows.
- A native Linux x86_64 system, VM, or WSL2 environment is available for
  baseline and Windows cross-build work.
- User-owned forks of `sigrokproject/libsigrok` and
  `sigrokproject/pulseview` exist before implementation commits must be shared.
- The connected DSO3062L remains on the vendor driver during the initial USB
  capture phase.
- Optional SDK-reference work requires Visual Studio Build Tools with the MSVC
  x86 C/C++ workload. It is separate from the MXE production toolchain.

Steps marked `[HUMAN]` require an owner decision or interactive system action.
Steps marked `[DEVICE]` require the physical DSO3062L. `[ADMIN]` means the
operator, not an agent script, deliberately supplies elevated privileges.

## Step 1 — repair and validate AEGIS

The current `.agentic` directory contains guidance and empty artifact folders,
but it does not contain the expected `aegis.py`, stage files, CLI reference, or
templates. Before implementation:

1. Obtain the approved AEGIS release payload.
2. Back up or compare the current repository-owned `.agentic/aegis.toml`, task
   records, requirements, specifications, and knowledge pages.
3. Install or upgrade the payload using its documented preservation rules.
4. Run `python .agentic/aegis.py init`; use `init --git` only if Git
   initialization has separately been authorized.
5. Configure source and test layout only after the upstream submodules and
   project-owned test tools exist.
6. Run `python .agentic/aegis.py status` and `check`; reconcile findings without
   deleting project-owned overlays.

Exit evidence: AEGIS status and check output plus the preserved configuration
diff. Installing AEGIS must not silently initialize Git.

## Step 2 — initialize the root repository

After explicit authorization, the planned root command is:

```powershell
git init -b main
git status --short --branch
```

Before a baseline commit:

- inspect `.gitignore` and `.gitattributes`;
- add ignore rules for build workspaces, upstream dependency clones, raw USB
  captures, package staging, and generated delivery output;
- ensure vendor PDFs, ZIPs, DLLs, LIBs, and drivers have an intentional tracking
  decision rather than being accidentally swept into a commit;
- run a secret and large-file inventory;
- record the chosen branch and base in the AEGIS task.

Do not create the baseline commit until the owner explicitly authorizes it.

## Step 3 — establish upstream remotes

Use two development submodules:

```text
05_Software/upstream/libsigrok
05_Software/upstream/pulseview
```

Planned source inventory:

| Component | Canonical source | Local role and path |
|---|---|---|
| libsigrok | `https://github.com/sigrokproject/libsigrok.git` | Modified owner fork at `05_Software/upstream/libsigrok` |
| PulseView | `https://github.com/sigrokproject/pulseview.git` | Modified owner fork at `05_Software/upstream/pulseview` |
| libserialport | `https://github.com/sigrokproject/libserialport.git` | Locked build dependency under `.work/upstreams` |
| libsigrokdecode | `https://github.com/sigrokproject/libsigrokdecode.git` | Locked build dependency under `.work/upstreams` |
| sigrok-cli | `https://github.com/sigrokproject/sigrok-cli.git` | Locked diagnostic frontend under `.work/upstreams` |
| sigrok-util | `https://github.com/sigrokproject/sigrok-util.git` | Locked build-script reference under `.work/upstreams` |
| libusb | `https://github.com/libusb/libusb.git` | Locked transport dependency or builder package |
| MXE | `https://github.com/mxe/mxe.git` | Locked Windows cross-toolchain under the build workspace |

Do not clone `sigrok-firmware` or `sigrok-firmware-fx2lafw` into the production
build by default. Add firmware sources only if native USB characterization proves
that the DSO3062L needs a loadable image and the licence/distribution path is
approved.

The equivalent manual submodule sequence, shown for review rather than implied
authorization, is:

```powershell
git submodule add <libsigrok-owner-fork-url> 05_Software/upstream/libsigrok
git submodule add <pulseview-owner-fork-url> 05_Software/upstream/pulseview
git -C 05_Software/upstream/libsigrok remote add upstream https://github.com/sigrokproject/libsigrok.git
git -C 05_Software/upstream/pulseview remote add upstream https://github.com/sigrokproject/pulseview.git
```

The bootstrap script replaces these manual commands in normal use and verifies
every resulting remote and revision.

The bootstrap tool will require explicit fork URLs:

```text
clone_upstreams.py \
  --libsigrok-url <owner-fork-url> \
  --pulseview-url <owner-fork-url> \
  --lock 02_Tools/upstream/upstreams.lock.toml
```

For each submodule, configure:

- `origin`: the owner fork used for authorized pushes;
- `upstream`: `https://github.com/sigrokproject/<repository>.git`;
- default work branch: `ddp/hantek-dso3062l`;
- detached checkout for release builds at the exact lock-file revision.

The tool must verify that each URL names the expected repository, refuse a
dirty target, and print the Git actions it intends to perform. It must never
commit, push, or create a fork.

## Step 4 — create the upstream lock

Implement `02_Tools/upstream/upstreams.lock.toml` with one table per source:

```toml
schema = 1

[libsigrok]
url = "https://github.com/sigrokproject/libsigrok.git"
commit = "0bc2487778e660f4d3116729b6f4aee2b1996bb0"
role = "modified-submodule"

[pulseview]
url = "https://github.com/sigrokproject/pulseview.git"
commit = "af02198741b4e57c9f9b796bd5e6c0f2ae9f2f2b"
role = "modified-submodule"
```

Add locked entries for sigrok-cli, libsigrokdecode, libserialport, sigrok-util,
libusb, MXE, the Linux builder image, and packaging tools. The initial values
come from the research snapshot in this package, but the first bootstrap task
must review and deliberately refresh them.

Each lock entry records URL, full commit or immutable digest, role, licence,
and the date it was reviewed. Branch names and moving tags are not release
identifiers.

## Step 5 — implement bootstrap automation

Create root-owned scripts:

```text
02_Tools/bootstrap/check_host.ps1
02_Tools/bootstrap/check_host.sh
02_Tools/bootstrap/clone_upstreams.py
02_Tools/bootstrap/verify_upstreams.py
02_Tools/bootstrap/create_build_workspace.py
```

Contract:

- Inputs are named arguments or a TOML lock file, never prompts in CI.
- Repositories clone into submodule paths or an ignored `.work/upstreams`
  directory according to their role.
- A mismatch, dirty tree, missing commit, unexpected remote, or checksum error
  fails closed.
- Re-running at the requested revision is idempotent.
- Output includes component, URL, requested revision, actual revision, dirty
  state, and local path.
- No script stages, commits, pushes, changes branches in an existing dirty
  checkout, or deletes an unverified path.

## Step 6 — provision the Linux build host

Select one project baseline, initially Debian 12 or Ubuntu 24.04 x86_64, and
pin the container image digest. The host must provide at least:

- GCC/G++, make, CMake, Git, pkg-config;
- autoconf, automake, autoconf-archive, libtool;
- GLib/GLibmm, libzip, libusb 1.0, libserialport;
- Check for libsigrok tests;
- Python 3 development files for libsigrokdecode;
- Qt 5.3+ or Qt 6.2+, Qt SVG, Boost, and Asciidoctor where manuals are built;
- NSIS and MXE prerequisites for the Windows cross-build image.

Hardware acceptance runs on a native Linux host or VM with USB passthrough, not
inside an opaque build container. Containers are used for deterministic builds.

## Step 7 - prove unmodified baseline builds

Build into an isolated prefix such as `.work/prefix/linux-x86_64`:

```bash
export PREFIX="$PWD/.work/prefix/linux-x86_64"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export LD_LIBRARY_PATH="$PREFIX/lib"

# libserialport
./autogen.sh
./configure --prefix="$PREFIX"
make -j"$(nproc)"
make install

# libsigrok
./autogen.sh
mkdir -p build && cd build
../configure --prefix="$PREFIX"
make -j"$(nproc)"
make check
make install

# libsigrokdecode and sigrok-cli use the same Autotools pattern.
# PulseView uses an out-of-tree CMake build.
cmake -S . -B build \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_DECODE=ON \
  -DENABLE_TESTS=ON \
  -DDISABLE_WERROR=OFF
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --install build
```

The project build wrappers must supply paths rather than rely on a user's
global installation. Do not mix distribution libsigrok packages with pinned
source-built PulseView components.

## Step 8 - record the baseline

Store a machine-readable build record containing:

- operating system and architecture;
- compiler, CMake, Autotools, Python, Qt, Boost, libusb, and MXE versions;
- every upstream revision and dirty state;
- configure/CMake options;
- command exit codes and log hashes;
- installed prefix inventory;
- unit-test totals;
- artifact hashes.

Only after this baseline passes may implementation failures be attributed to
the DSO3062L changes rather than the environment.

## Step 9 - provision the optional Windows reference host

Perform this P2A step only after the G1 baseline. It is for characterization
and does not change the release architecture.

1. `[DEVICE]` Inventory the current driver, device instance, official Hantek
   application version, supplied SDK hashes, and a successful vendor capture.
2. Verify Windows edition, x64 host architecture, Secure Boot state, and
   whether the supplied vendor driver loads without warnings. Do not infer that
   an old or unsigned driver is compatible with current Windows.
3. Install USBPcap/Wireshark and MSVC x86 tools only after `[HUMAN]` approval.
4. Create a documented driver rollback record before any binding change; keep
   the vendor driver installed until reference captures are complete.
5. Build a minimal x86 harness that dynamically loads the locally supplied
   `HTHardDLL.dll`. Do not copy vendor files into source control or delivery.
6. Run the harness only against documented volatile SDK calls, with the Hantek
   application closed and bounded timeouts.

Exit evidence: host/tool versions, DLL hashes, driver inventory, harness build
record, one controlled result, and a correlated USB capture. Failure is a
research limitation, not a reason to make the SDK a product dependency.

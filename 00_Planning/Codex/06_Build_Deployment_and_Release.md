<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Build, deployment, and release

## Automation layout

Implement project-owned automation under:

```text
02_Tools/
├── README.md
├── bootstrap/
│   ├── README.md
│   ├── check_host.ps1
│   ├── check_host.sh
│   ├── clone_upstreams.py
│   └── verify_upstreams.py
├── upstream/
│   ├── README.md
│   └── upstreams.lock.toml
├── build/
│   ├── README.md
│   ├── build_linux.sh
│   ├── build_windows_mxe.sh
│   ├── build_component.sh
│   └── images/
├── research/
│   ├── README.md
│   ├── inventory_windows_usb.ps1
│   └── decode_capture.py
├── test/
│   ├── README.md
│   ├── run_offline.sh
│   ├── run_hardware_linux.sh
│   └── run_hardware_windows.ps1
├── deploy/
│   ├── README.md
│   ├── package_linux.sh
│   ├── package_windows.sh
│   ├── install_udev_rules.sh
│   └── verify_windows_driver.ps1
└── release/
    ├── README.md
    ├── create_manifest.py
    ├── create_checksums.py
    └── verify_delivery.py
```

The optional reference tool adds
`02_Tools/research/sdk_reference/README.md`,
`02_Tools/research/sdk_reference/build_sdk_reference.ps1`, and
`02_Tools/research/sdk_reference/STATUS.md`.

Every folder gets a README. Python and project-owned scripts follow the root
code style and legal header. Upstream build files retain upstream style.

## Common script contract

All build and deployment scripts must:

- accept explicit source, build, prefix, output, configuration, and target
  parameters;
- resolve and validate paths before any cleanup;
- refuse a dirty modified upstream tree for release mode;
- print tool versions and locked source revisions;
- write logs and a structured result record;
- use noninteractive package-manager flags only in documented container images;
- fail on a command error, missing dependency, revision mismatch, missing
  expected artifact, or checksum mismatch;
- preserve the previous successful delivery until the new candidate verifies;
- never stage, commit, push, publish, install a Windows driver, or use root
  privileges without an explicit operator action outside the build;
- support `--help` and `--dry-run` where the action has system impact;
- emit no secrets, raw captures, or private calibration contents into logs.

Use stable output roots:

```text
.work/build/<platform>/<configuration>/<component>/
.work/prefix/<platform>/<configuration>/
.work/logs/<build-id>/
07_Delivery/staging/<build-id>/
07_Delivery/releases/<version>/
```

Build and staging directories are ignored. Final release records and selected
artifacts follow an explicit tracking/publication decision.

## Script status ledger

Each automation folder maintains a `STATUS.md` table with script path, owner,
planned/implemented/verified status, supported host, last verification date,
verification command, and known limitation. A script named in this plan is not
treated as available until the ledger and an execution record say it is
implemented and verified.

The SDK-reference build is the sole exception to the cross-platform production
toolchain: `build_sdk_reference.ps1` invokes MSVC x86 for the research harness.
It accepts an explicit SDK path, verifies header and DLL hashes plus any import
library actually used,
copies needed vendor runtime files only into an ignored local run directory,
and never packages them. Failure to build this optional tool does not change
the native libusb release design.

## Build host

Decision, 2026-08-17: both release artifacts are produced from a single pinned
Linux container. No build step runs natively on Windows.

The host is confirmed available and is the intended builder:

| Property | Value |
|---|---|
| WSL distribution | Ubuntu 24.04.4 LTS, x86_64, WSL2 kernel 6.18.33.2 |
| Container runtimes | Docker 29.6.1, Podman 4.9.3, Buildah 1.33.7 |
| Resources | 24 CPU, 31 GB RAM, 921 GB free on rootfs |
| Repository path inside WSL | `/mnt/f/2026_Hantek_DSO3062L` |

Container definitions live in `02_Tools/build/images/`. The image is pinned by
base-image digest, not tag.

`sigrok-util/cross-compile` carries six targets: `android`, `appimage`,
`linux`, `macosx`, `mingw`, `msys2`. Five of the six are Linux-hosted, and the
two this project needs are among them, so one image produces both deliverables:

- `mingw/sigrok-cross-mingw` produces Windows x64 executables and the NSIS
  installer, using MXE;
- `appimage/sigrok-native-appimage` produces the Linux x86_64 AppImage.

The `mingw` README lists the host requirements as bash, gcc, make, cmake, git,
wget, p7zip, unzip, pkg-config, sdcc, nsis, and MXE. All are installable in a
Debian or Ubuntu base image.

### MSYS2 is rejected

`msys2/sigrok-native-msys2` is the only Windows-hosted script, and it is broken
as written: it clones `git://github.com/dickens/libusb` at branch
`event-abstraction-v4`, which no longer exists in that repository. The `git://`
protocol is also no longer served by GitHub. This confirms the earlier survey
note that the MSYS2 script does not fully support PulseView packaging.

Two further reasons stand independently of the breakage. A native MSYS2 tree
modifies the operator's Windows system outside this repository. Its offline
archive is a package cache, which is inert without a correctly configured MSYS2
to consume it, whereas a container image archived with `docker save` is a single
tarball holding the complete built environment. The container therefore gives a
stronger offline guarantee at lower host cost.

### Functional scope to preserve

The pinned upstream trees provide 87 hardware drivers
(`libsigrok/src/hardware/*`) and 132 protocol decoders
(`libsigrokdecode/decoders/*`). Both counts must survive into the delivered
artifacts. The decoder set is the primary reason PulseView is the target front
end rather than a project-owned application.

Reimplementing the stack in another language to obtain a simpler dependency
graph was considered and rejected: any rewrite starts at zero on both counts,
and the decoder set is a hard requirement. The build is awkward but solved;
the functionality is not reproducible at this project's scale.

## Linux build

### Development build

`build_linux.sh` builds, in order:

1. libserialport;
2. libsigrok including C++ bindings and `hantek-dso3062l`;
3. libsigrokdecode;
4. sigrok-cli;
5. PulseView.

Inputs:

```text
--lock <upstreams.lock.toml>
--configuration Debug|Release
--prefix <absolute path>
--jobs <positive integer>
--with-tests
--with-decoders
--clean verified|none
```

The script exports a private `PKG_CONFIG_PATH`, `LD_LIBRARY_PATH`, and
`CMAKE_PREFIX_PATH`. It uses out-of-tree build directories and does not install
to `/usr` or `/usr/local`.

Required validation:

- libsigrok `make check`;
- libsigrokdecode `make check` where enabled;
- PulseView `ctest --output-on-failure`;
- sigrok-cli version, driver list, and driver option inspection;
- PulseView launch smoke in an environment capable of Qt display or headless
  Qt smoke where appropriate;
- no link to an unintended system libsigrok, verified with `ldd` or equivalent.

### Linux packages

Produce two initial formats:

1. a versioned `tar.zst` portable prefix for engineering and diagnostics;
2. an x86_64 AppImage for end-user delivery after the portable bundle passes.

The portable bundle contains PulseView, sigrok-cli, required libraries,
protocol decoders, documentation, udev rules, licences, provenance manifest,
and checksums. Do not bundle vendor Hantek binaries.

AppImage work may use sigrok-util's AppImage script as a reference, but the
surveyed script targets an old distribution and AppImageKit flow. Pin and test a
maintained packaging tool rather than silently relying on an obsolete download.

## Windows x64 cross-build

The official sigrok guidance recommends `sigrok-cross-mingw` with MXE from a
Linux host. Native Visual Studio builds are not the project baseline, and the
surveyed MSYS2 script does not fully support PulseView packaging.

### Builder

- Run in the pinned Linux container described under "Build host". Docker under
  WSL2 Ubuntu 24.04 is the confirmed environment.
- Pin MXE and every applied patch.
- Build MXE in its own image layer so the multi-hour Qt5 compile is paid once
  and survives as a cached layer and in the `docker save` archive.
- The MXE README freezes Qt to 5.7.x for Windows XP support, which this project
  does not claim. Evaluate a current Qt5 before adopting the freeze plugin.
- Target `x86_64-w64-mingw32.static.posix` only for v1.
- Use the surveyed sigrok-util script as architectural reference, not as an
  unquestioned release script: it contains legacy Python 3.4 downloads and Qt5
  compatibility choices that require refresh and legal/provenance review.

### Build order

1. build the pinned MXE dependency set;
2. build libserialport and libsigrok statically for the target;
3. build libsigrokdecode and a supported embedded Python runtime if decoders
   are included;
4. build sigrok-cli for diagnostics;
5. build PulseView with the same libsigrok revision;
6. run cross-compiled unit tests under Wine only as supplemental evidence;
7. assemble a portable ZIP;
8. assemble an NSIS installer;
9. test both on native Windows x64.

The Windows build record includes MXE revision, target triplet, compiler,
Python, Qt, Boost, libusb, NSIS, configure/CMake options, and all input hashes.

### Windows USB deployment

PulseView uses WinUSB through libusb. The installer must not silently replace
the Hantek driver. Delivery includes:

- a signed or reviewed driver-binding guide using Zadig;
- `verify_windows_driver.ps1`, which reports whether the selected DSO3062L PnP
  instance is bound to WinUSB;
- the exact vendor-driver restoration procedure;
- a warning that the Hantek application and PulseView normally require
  different driver bindings;
- no automatic driver-store deletion.

If a future signed INF for WinUSB is produced, treat it as a separate security,
signing, and deployment project.

## Linux USB deployment

Add `04b5:3062` to the upstream libsigrok `contrib/60-libsigrok.rules` device
identification. Use the upstream `61-libsigrok-uaccess.rules` policy on systemd
desktop distributions and document the `plugdev` alternative.

`install_udev_rules.sh` must:

- require an explicit source and destination;
- display the files and target paths in dry-run mode;
- install only after the operator invokes it with appropriate privilege;
- set normal rule permissions;
- reload rules and print the reconnect step;
- offer verification and a documented removal command;
- never run PulseView as root as a workaround.

## Versioning and provenance

Use a project version plus component revisions. A delivery manifest records:

- project version and build ID;
- source-date epoch;
- root revision and dirty state;
- libsigrok and PulseView fork revisions and upstream bases;
- every locked dependency revision or digest;
- platform, architecture, configuration, and toolchain;
- build/test result record hashes;
- artifact names, sizes, SHA-256 values, and media types;
- licences and notices included;
- vendor components: expected to be an empty list by default;
- hardware evidence IDs used for acceptance;
- known limitations.

Set deterministic timestamps where upstream tooling permits it. Compare two
clean builds from the same inputs; record any nondeterministic files and remove
or normalize their uncontrolled fields before claiming reproducibility.

## Release assembly

`create_manifest.py` inventories an already-built staging directory. It does
not build, publish, or modify source. `create_checksums.py` covers every release
artifact and the manifest. `verify_delivery.py` starts from an empty temporary
directory and verifies:

1. manifest schema and required fields;
2. filenames and hashes;
3. licence and notice presence;
4. absence of unapproved vendor binaries;
5. expected executables, libraries, udev rules, and documentation;
6. component version output;
7. driver and decoder counts equal to the pinned upstream revisions, so a build
   that silently drops libsigrokdecode or a driver group fails verification
   rather than shipping;
8. extraction without path traversal;
9. optional clean-machine smoke results supplied as signed-off evidence.

Release outputs:

```text
07_Delivery/releases/<version>/
├── README.md
├── RELEASE_NOTES.md
├── manifest.json
├── SHA256SUMS
├── licences/
├── windows-x86_64/
└── linux-x86_64/
```

Artifact creation does not authorize a commit, push, upload, or upstream
publication.

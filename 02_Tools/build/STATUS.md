<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Build automation status ledger

Current state, and the findings behind it. Most of this file is a record of
what the toolchain investigation actually cost - the dead patch, the glibmm
gap, the two traps that burned three bisections. That part is still the
reason the build works and is kept verbatim; the status around it is
updated as the build changes.

**All three deliveries build and are verified against hardware.**

| Target | Script | Result |
|---|---|---|
| Windows x86_64 | `build_windows_mxe.sh` | `sigrok-cli.exe`, `pulseview.exe`, statically linked |
| Linux x86_64 (thin) | `build_linux.sh` | tarball; needs runtime libs from the distro |
| Linux x86_64 (portable) | `build_appimage.sh` | self-contained AppImage, no host packages |

| Component | Result |
|---|---|
| libserialport | built |
| libsigrok | built, C++ bindings enabled, 84 drivers |
| libsigrokdecode | built against CPython 3.13.15; 131 decoders, all loading |
| `sigrok-cli.exe` | 15 MB, PE32+ console x86-64 |
| `pulseview.exe` | 33 MB, PE32+ GUI x86-64 |
| `PulseView-x86_64.AppImage` | 36 MB, self-contained |

The Windows binaries link statically. Their only non-system import is
`python313.dll`; everything else resolves against stock Windows DLLs. The
Python runtime beside them is python.org's official Windows embeddable
package, shipped whole - see "The Windows Python problem" below.

Driver count is 84, not the 82 an earlier revision of this file recorded:
the two additions are ours, `hantek-dso3062l` and `atk-dl16`. Both have been
run against the physical instruments, not merely compiled - see
`04_HardwareDocu/<device>/` for what was verified and how.

This project no longer tracks upstream sigrok. `05_Software/` holds the
whole stack as ordinary files in this repository, so a clone carries the
sources and `02_Tools/` carries everything needed to build them.

**Both run on Windows**, verified 2026-08-17 by executing the staged binaries
directly from `07_Delivery/staging/`:

- `sigrok-cli --version` reports libsigrok 0.6.0, glib 2.89.1 (the held
  version), Python 3.13.15 (3.4.4 until 2026-08-23), libusb 1.0.27, hidapi,
  libftdi.
- `pulseview --version` reports PulseView 0.5.0, Qt 5.15.19, glibmm 2.66.2,
  Boost 1_92.
- `sigrok-cli -P uart --show` loads and executes a Python decoder.
- `sigrok-cli -d demo --samples 64 -P parallel:...` acquires and emits
  decoded annotations, exercising the whole chain: driver, capture,
  libsigrokdecode, Python, annotation output.

One benign message appears on every PulseView start: `asix-omega-rtm-cli:
Cannot execute RTM CLI process`. That driver shells out to a helper binary
that is not shipped; it affects nothing else.

(That was written of the initial stock-sigrok probe, when the GUI had not
been opened and no hardware attached. Both have since happened: PulseView
runs, and both drivers have been exercised against the physical
instruments.)

Not built by this probe, and needed for a real package: `sigrok-firmware`,
`sigrok-firmware-fx2lafw`, `sigrok-dumps`, the NSIS installers, and Zadig.

| Path | Status | Host | Last verified | Verification command | Known limitation |
|---|---|---|---|---|---|
| `images/Dockerfile.mingw` | verified | WSL2 Ubuntu 24.04 + Docker | 2026-08-17 | `./build_image.sh --image mingw --skip-patch mxe_fixes.patch` | Builds a 7.28 GB image. `check` excluded, glib held at 2.89.1 - see deviations below. |
| `images/Dockerfile.appimage` | verified | WSL2 Ubuntu 24.04 + Docker | 2026-08-19 | `./build_image.sh --image appimage` | The `appimagetool` and `linuxdeployqt` artifacts it needed were finally added to the lock; it had indeed been failing closed until then. Also pre-creates `/build` - without that the volume mounts root-owned and the build cannot write to it. |
| `build_image.sh` | verified | WSL2 Ubuntu 24.04 | 2026-08-17 | `./build_image.sh --image mingw --skip-patch mxe_fixes.patch` | Full path exercised: clone, pin check, patch check, base-digest pinning, build, provenance record. `--save` is still untested. |
| `run_in_builder.sh` | verified | WSL2 Ubuntu 24.04 | 2026-08-17 | `./run_in_builder.sh --image mingw -- bash /work/.work/probe-verify.sh` | Drove the whole stock-sigrok build. Its first run failed on a root-owned `/build`; fixed in the image, not the script. |
| `build_windows_mxe.sh` | verified | WSL2 container | 2026-08-23 | `./build_windows_mxe.sh --offline --clean --stage` | Full clean build with the network denied: 84 drivers, 132 decoder directories, both executables, CPython 3.13.15. Does not build firmware, dumps, or the NSIS installers. |
| `02_Tools/test/windows_python_smoke.sh` | verified | Windows 11 host | 2026-08-23 | `02_Tools/test/windows_python_smoke.sh` | Host-side, not a build step: it runs `sigrok-cli.exe`, which the MXE image cannot do (no Wine). Runs on Windows directly or on Linux with wine; exits 77 where it can run neither. |
| `load_image.sh` | verified | WSL2 Ubuntu 24.04 | 2026-08-17 | `./load_image.sh --image mingw --force` | Checksum-verifies and loads the 2.2 GB archive. Detects an unsmudged Git LFS pointer and says so. |
| `bootstrap/check_host.sh` | verified | WSL2 Ubuntu 24.04 | 2026-08-17 | `02_Tools/bootstrap/check_host.sh` | Read-only. Found a missing git-lfs on its first run. Windows host equivalent not written. |
| `build_linux.sh` | verified | ubuntu:24.04 container | 2026-08-19 | `./build_linux.sh` | Native build, thin tarball. Bundles only the sigrok libraries; Qt5, boost, glib and the rest are an `apt install` on the target, listed in the emitted README. Use the AppImage where that is not acceptable. |
| `build_appimage.sh` | verified | appimage builder image | 2026-08-19 | `./build_appimage.sh` | Self-contained AppImage, both binaries behind one AppRun (`--cli` selects sigrok-cli). Verified on a bare ubuntu:22.04 with zero packages installed. PulseView still needs the host's libGL and display - deliberate; graphics libraries must match the kernel driver. |
| `build_component.sh` | planned | WSL2 container | n/a | n/a | Not written, and no longer obviously needed - the three per-target scripts cover the deliveries. |

## What the first dry run found

Worth recording, because both were real and neither would have surfaced from
reading the script.

**WSL has no SSH identity.** It has its own home directory, so the keys set up
under Windows are invisible to it. `git clone` from the Gitea mirror fails with
`Permission denied (publickey)`.

**The script hung instead of failing.** Without batch mode, `ssh` blocked on an
interactive prompt that could never be answered - ten minutes, no output, no
error. Fixed by exporting `GIT_SSH_COMMAND` with `BatchMode=yes` and
`ConnectTimeout=10`, `GIT_TERMINAL_PROMPT=0`, and probing with `git ls-remote`
before attempting the clone. The same failure now reports in four seconds with
the remedy. `--mxe-src` was added as an escape hatch for hosts that cannot
reach the mirror at all.

## What the second dry run found: mxe_fixes.patch is dead

With SSH working, the clone succeeded and the pin verified. Checking the two
sigrok MXE patches against the actual tree then found a second case of R-20.

`libusb1_upgrade.patch` **applies cleanly and is worth keeping.** It enables
the WinUSB `RAW_IO` policy for transfers whose length is divisible by 512.
The DSO3062L's bulk endpoints are 512 bytes, so this is a throughput
improvement on our own data path, not incidental upstream housekeeping.

`mxe_fixes.patch` **does not apply, in every hunk**:

```
src/binutils-1-fixes.patch: No such file or directory
src/binutils.mk: patch does not apply
src/glib-1-fixes.patch: patch does not apply
src/glib.mk: patch does not apply
```

The binutils failure is explained: the file the patch deletes was removed
upstream by MXE commit `d28c0859 Update binutils to 2.46.0`. The patch was
written against an older MXE and the tree has moved past all of it.

Decision: build with `--skip-patch mxe_fixes.patch`. If glib or binutils then
fails to build, the individual glib hunks are the place to look - but there is
no reason to reapply changes whose targets no longer exist.

Patch handling was changed from an all-or-nothing flag to a per-patch list as
a result. `build_image.sh` now checks each patch against the staged clone and
refuses to continue on a patch that will not apply, rather than discovering it
partway into a multi-hour image build. Skipping one is possible but must be
asked for explicitly, and the choice is written into the build record.

## What building unmodified sigrok found

Planning doc 09 Q-15 asks whether the pinned toolchain can build stock sigrok
at all. It can, but three things had to be fixed first, and none of them
appear in any upstream requirement list.

**Doxygen was missing, and it silently disables PulseView.** libsigrok
generates its C++ bindings by parsing Doxygen's XML dump of its own headers
(`libsigrok/configure.ac:471`). Without it, `configure` succeeds and merely
reports `C++ ... no (missing: Doxygen)`; PulseView, which is C++ and links
those bindings, then cannot be built. Nothing fails loudly - the summary block
is the only warning. It is now installed in the `final` stage rather than
`base`, because `base` is the ancestor of every MXE stage and a package added
there costs a multi-hour toolchain rebuild for a tool the toolchain never uses.

**The `/build` volume was root-owned.** `run_in_builder.sh` had never been
executed; its first run failed on the first `mkdir`. Docker seeds a named
volume from the image's directory including ownership, but only if that
directory exists - and it did not. Creating it in the image is what makes the
volume writable.

**MXE's cmake wrapper needs a writable ccache directory.** It routes the
compiler through ccache with `CCACHE_DIR` inside the MXE tree, which arrives
root-owned. CMake reports this as a broken compiler, which is a misleading
description of a directory permission. Autotools builds never notice, so this
only surfaced at PulseView - the last and slowest component.

### Windows driver count: 82, not 87

Doc 09's R-19 assertion should be 82 for the Windows target. Five of the 87
drivers disable themselves, and four are legitimately unavailable there:

| Driver | Missing | Fixable? |
|---|---|---|
| `baylibre-acme` | `sys/timerfd.h` | No - Linux-only API |
| `beaglelogic` | `sys/mman.h`, `sys/ioctl.h` | No - Linux-only API |
| `hp-3478a` | `libgpib` | No - Linux-only |
| `mooshimeter-dmm` | `bluetooth_comm` | No - no Bluetooth in this build |
| `rdtech-tc` | `libnettle` | **Yes** - add `nettle` to the MXE package set |

All decoders build.

**A note on that figure: 131 decoders, not 132.** The build record's `decoders`
line counts directories under `share/libsigrokdecode/decoders`, and one of
those directories is `common` - the shared helper package the decoders import
(`common.srdhelper` and friends), which is not itself a decoder and correctly
never appears in `sigrok-cli -L`. So the record has always said 132 where the
listing says 131. The record is left counting directories so old and new
records stay comparable; `02_Tools/test/windows_python_smoke.sh` checks the
invariant that actually matters, which is that every directory except `common`
produces a listed decoder - and it names the ones that do not, rather than
only counting them.

### The Windows Python problem, and how it was closed

libsigrokdecode embeds CPython, and MXE has no Python for the Windows target -
only host-side helpers. Verified in the built image: `/opt/mxe/src` carries
`python-conf.mk`, `python-mako.mk`, `python-markupsafe.mk` and
`python-setuptools.mk`, and nothing else. The earlier note in
`Dockerfile.mingw` claiming MXE builds one as a dependency was wrong, and has
been corrected.

**Until 2026-08-23 this was upstream's workaround, carried as debt.** Upstream
avoids cross-compiling CPython by downloading a repackaged **Python 3.4.4**
from `sigrok.org/tmp` over plaintext HTTP and hand-writing a `python3.pc` that
points at it. It worked, and it was what sigrok's own installers shipped, so
the decoders were known to run against it.

It was not merely untidy. Python 3.4 cannot parse f-strings, variable
annotations, `enum.IntFlag` or dataclasses, and
`srd_decoder_load_all_path()` discards the error from every decoder that
fails to load - so such a decoder was simply **absent from the list, with no
diagnostic anywhere**, on Windows only, while working on Linux where the build
uses the distribution's python3. That platform split blocked importing
decoders from other sigrok derivatives, and would have been expensive to
diagnose later.

**Now: CPython 3.13.15 from python.org, two artifacts, both pinned.**

| | |
|---|---|
| `python-3.13.15-embed-amd64.zip` | the official Windows embeddable package - the runtime that ships |
| `Python-3.13.15.tar.xz` | headers only; nothing here is compiled |

Both are fetched over HTTPS from the canonical python.org release directory,
pinned by version and SHA-256 in `upstreams.lock.toml` as `cpython-windows-embed`
and `cpython-source`, and baked into the builder image at `/opt/sigrok-deps`.
A build reaches no network; `build_windows_mxe.sh --offline` proves it.
`gendef`/`dlltool` still manufactures the import library the official 64-bit
package does not ship, exactly as upstream does - that part of the workaround
was sound and was kept.

Four things worth knowing, each of which was checked rather than assumed:

**`pyconfig.patch` is no longer applied, and no longer needed.** It existed
for upstream bug #1195: the 3.4 header left `MS_WIN64` undefined under mingw,
so `Py_ssize_t` came out 4 bytes wide on 64-bit Windows and *no* decoder
worked. CPython carries that `__MINGW32__` block itself now. Rather than trust
that, `build_windows_mxe.sh` compiles a probe on every build that asserts
`MS_WIN64`, `sizeof(Py_ssize_t) == 8` and `PY_VERSION_HEX >= 0x030900F0`. It
appears in the build output as `abi-check`.

**3.13, not 3.12.** Python 3.12 is in its security-only phase and those
releases are source-only - `python-3.12.11-embed-amd64.zip` is a 404 - so
pinning 3.12 would have meant pinning the much older 3.12.10. 3.14 was avoided
to limit C-API churn against the pinned libsigrokdecode.

**The package ships whole, not hand-picked.** An import-table walk shows it is
exactly self-closed: `_ctypes.pyd` needs `libffi-8.dll`, `_hashlib.pyd` needs
`libcrypto-3.dll`, and every other import is an `api-ms-win-*` UCRT stub
present on any supported Windows. Dropping a `.pyd` to save space would come
back as a decoder that silently fails to import. The staging step now walks
those import tables and fails if any PE needs a DLL the tree does not carry;
it appears in the build output as `imports`. The tree costs about 21 MB of
Python against the old 7 MB.

**`configure.ac` did not need touching.** It probes `python-3.12-embed` and
friends by module name and then falls back to `python3 >= 3.2`; the
hand-written `python3.pc` satisfies that last alternative, and the configure
log confirms it: `checking for glib-2.0 python3 >= 3.2... yes`.

Windows now runs a *newer* Python than either Linux delivery - the AppImage
builder has 3.10 and the thin Linux build takes the distribution's 3.12 - so
3.10 is the floor across platforms, rather than 3.4.

## How the stage-2 scripts were arrived at

They exist now: `build_windows_mxe.sh`, `build_linux.sh`, `build_appimage.sh`.

They were deliberately not written up front, because they would have been
guesses. `sigrok-cross-mingw` has hard-coded prefixes, an expectation of MXE
at `$HOME/mxe-git`, and legacy Python download logic. Wrapping behaviour
nobody had observed would have produced a script needing a rewrite after the
first real run.

The order actually followed:

1. Build the mingw image.
2. Get a shell in it and run the upstream script by hand against
   **unmodified** sigrok. Record what it needs, what it breaks on, and where
   it puts things.
3. Turn the working invocation into `build_windows_mxe.sh`.
4. Only then add the drivers.

Step 2 was the one worth not skipping. Had the driver gone in first and the
build failed, the cause would have been ambiguous between our code and the
toolchain - and the toolchain turned out to have three separate faults
(below), any of which would have been blamed on the driver.

## Deviations from upstream sigrok's release toolchain

Both are deliberate and both are upstream bit-rot, not local misconfiguration.
Record them in the delivery manifest.

| Deviation | Reason | Cost |
|---|---|---|
| `mxe_fixes.patch` not applied | Fails every hunk against the pinned MXE; the file it deletes was already removed upstream by MXE's binutils 2.46.0 update | None observed. If glib or binutils misbehaves, look here first. |
| `check` not in the Windows package set | libcheck 0.15.2 defines `clock_gettime` in `lib/clock_gettime.c`; mingw-w64 v14's winpthreads declares it in `pthread_time.h:112`. Duplicate definition, compile fails. 0.15.2 is the current release. | libsigrok's unit tests cannot be cross-built for Windows. They still run natively on the Linux build, and doc 06 already treats Wine test runs as supplemental only. |
| glib held at 2.89.1 instead of the pinned MXE's 2.89.3 | glib 2.89.2 changed declarations that glibmm 2.66.2's generated headers duplicate. Bisected: 2.89.1 builds glibmm, 2.89.2 does not. | One release of divergence. glibmm, the C++ bindings and PulseView all build. |

### The glibmm gap, and how it was closed

MXE pins glibmm 2.66.2, untouched since March 2022, while an automated updater
walked glib from 2.85.4 to 2.89.3 over the past year - a run of unattended
`glib: update X -> Y` commits with no matching glibmm work. Few MXE packages
depend on glibmm, so nobody noticed it had broken.

Bisected against this toolchain, with each candidate's `glib.mk`, patches and
checksum taken from the MXE commit that shipped it:

| glib | glibmm 2.66.2 |
|---|---|
| 2.87.2 | builds |
| 2.89.0 | builds |
| 2.89.1 | builds |
| 2.89.2 | conflicting declaration |
| 2.89.3 (MXE pin) | conflicting declaration |

So the break is in **glib 2.89.2**, one release before the pin. `mxe-glib-hold`
replaces `src/glib.mk` and its patches with the 2.89.1 set, and glibmm, the
C++ bindings and PulseView all build.

The alternative - adding `libsigc++-3` and `glibmm-2.68`, which both libsigrok
(`configure.ac:462`) and PulseView (`CMakeLists.txt:129`) accept - is not
needed now, but remains the answer if glibmm 2.66 ever stops working entirely.

Rolling the whole MXE pin back was the worst option and was not taken: it
drags gcc and Qt backwards too, reintroducing rot already cleared, and every
bisection step would cost a full toolchain rebuild.

### Two traps that cost three worthless bisections

Both produced confident-looking results that measured nothing. Worth recording
because neither is obvious.

**MXE plugin patches are additive.** `MXE_PLUGIN_DIRS` looked like the tidy way
to override glib, but `PKG_PATCHES` globs `<dir>/glib-[0-9]*.patch` across
*every* plugin dir including `src/`, and `PKG_MAKEFILES` does the same for
`glib.mk`. A plugin therefore supplements `src/` rather than replacing it: both
copies of the patch get applied, MXE reports "Reversed (or previously applied)
patch detected", and the build dies before glibmm is reached. Worse, a plugin
directory left behind from an earlier attempt keeps overriding the version
silently. `mxe-glib-hold` now deletes `plugins/glib-hold` on every run and
edits `src/` in place.

**MXE leaves stale logs.** `log/<pkg>_<target>` is not cleared when a build
fails before reaching that package, so it happily serves output from a previous
run. Three diagnoses were made from a log whose timings were identical to three
decimal places across supposedly different runs. Always confirm the log
actually changed, and check the make invocation succeeded - `make
glib_x86_64-pc-linux-gnu` is not a valid MXE target and fails with `No rule to
make target`, touching no log at all.

`libusb1_upgrade.patch` **is** applied and should stay: it enables the WinUSB
`RAW_IO` policy for transfers divisible by 512, and the DSO3062L's bulk
endpoints are 512 bytes.

## Image structure

Multi-stage, for two reasons that were both learned the hard way.

MXE's downloaded tarballs are 2-3 GB. Deleting them in a later layer only
hides them - the bytes stay in the earlier layer's diff, and this image *is*
the offline archive. They now never leave the throwaway `mxe-builder` stage.

The MXE build is split into three layers - `gcc`, then the sigrok libraries,
then Qt - ordered so a failure costs as little as possible to retry. As one
combined layer, every attempt recompiled the entire toolchain, which is
expensive enough to discourage investigating a failure properly.

`mxe-build.sh` exists because MXE prints only a make summary and writes the
real compiler output to `log/<pkg>_<target>`, which dies with the failed
layer. It parses MXE's own `Failed to build package <name>` line and dumps
that package's log. Selecting the log by name or mtime does not work:
packages still building when one fails finish afterwards.

## Verified toolchain contents

Read out of the built image, not assumed:

| Component | Version |
|---|---|
| cross gcc | 11.5.0 |
| glib / gio | 2.89.1 (held) |
| glibmm | 2.66.2 |
| libsigc++ | 2.10.7 |
| libusb-1.0 | 1.0.27, with the RAW_IO patch |
| libftdi1 | 1.5 |
| hidapi | 0.11.0-dev |
| libzip | 1.5.2 |
| Qt5 Core/Widgets/Svg | 5.15.19 |
| NSIS | 3.08 |

Everything libsigrok, libsigrokdecode, sigrok-cli and PulseView need for the
Windows target is present.

One trap worth knowing: a login shell sources `/etc/profile`, which overwrites
`PATH` and hides the toolchain, so `bash -lc "...-gcc"` failed in an image
where the compiler was plainly there. The image now also drops the path into
`/etc/profile.d/mxe.sh`, so both shell forms work.

## Reproducing this on another machine

The target is a developer on the same network. The mirrors at
`192.168.1.15:2222` are deliberately LAN-only; this is not intended to build
from outside it.

```sh
git clone ssh://git@192.168.1.15:2222/dpasare/2026_Hantek_DSO3062L.git
cd 2026_Hantek_DSO3062L
git lfs pull                              # the 2.2 GB toolchain image
02_Tools/bootstrap/check_host.sh          # reports what is missing
02_Tools/build/load_image.sh --image mingw
02_Tools/build/build_windows_mxe.sh --stage
```

No `git submodule update` step: the sigrok stack was folded into this
repository as plain files in August 2026, so the clone above already carries
every source it builds. `git lfs pull` replaces the step that used to matter
- without it the toolchain archive is a ~130-byte pointer file and
`load_image.sh` says so rather than failing obscurely.

For Linux:

```sh
02_Tools/build/build_linux.sh             # thin tarball, needs distro libs
02_Tools/build/build_image.sh --image appimage
02_Tools/build/build_appimage.sh          # self-contained AppImage
```

`check_host.sh` is read-only by contract: it names the missing prerequisite
and the exact command to fix it, and installs nothing.

### The offline claim, tested

Proven 2026-08-17, not assumed. A full clean build ran with `--offline`,
which passes `--network none` to the container - the build had no network
interface at all, so a forgotten download could not have quietly succeeded:

```
./build_windows_mxe.sh --offline --clean --stage
```

It produced 82 drivers, 132 decoders, `sigrok-cli.exe` and `pulseview.exe`.
The staged `pulseview.exe` hashes to `572567b3...`, matching the build
record, and runs on Windows: `--version` reports PulseView 0.5.0 / Qt
5.15.19, and `sigrok-cli -d demo -P parallel` still emits decoded
annotations.

Everything the build needs now comes from the image or the repository.

### What can still expire, and what no longer can

The toolchain image is saved to `07_Delivery/toolchain/` and tracked in Git
LFS. That is what makes the rest of this list short.

| Dependency | State |
|---|---|
| MXE's upstream tarballs, from **117 distinct hosts** | **Retired.** Baked into the image; a load never reaches them |
| CPython 3.13.15 from `python.org` over HTTPS | **Retired.** Pinned in the lock, baked into the image at `/opt/sigrok-deps`, checksum-verified at bake time and again at build time. Replaced the plaintext-HTTP Python 3.4.4 from `sigrok.org` on 2026-08-23 |
| Debian base image and apt packages | Baked in. Only a from-source image rebuild re-fetches them |
| The 7 sigrok sources | **Retired.** Vendored into `05_Software/` as plain files; a clone carries them |
| `sigrok-firmware`, `fx2lafw` tarball | **Still exposed.** Not mirrored, not yet needed - no build so far uses them |
| `appimagetool`, `linuxdeployqt` | **Still exposed.** Pinned by version and SHA-256 in the lock, but fetched from GitHub when the appimage image is built |

Nothing in the Windows path depends on a third-party host any more, and the
sigrok sources cannot expire at all now that they live in this repository.

The Linux AppImage image is the remaining exposure: building it downloads two
packaging tools from GitHub. Both are checksum-verified, so they cannot change
underneath us - but they could disappear. That only affects rebuilding the
appimage *builder image*; once built, `build_appimage.sh` needs no network.
Saving that image to `07_Delivery/toolchain/` the way the mingw one is would
close it, at the cost of another multi-gigabyte LFS object.

### What is deliberately not solved

**apt package versions are not pinned.** A from-source image rebuild in a
year gets whatever Bookworm serves then. This matters far less than it
sounds, because the image archive means the rebuild is rare - and pinning
every apt version would break the moment a security update lands.

**LFS storage grows per revision.** Git LFS does not deduplicate between
versions, so each regenerated archive costs another ~2.2 GB permanently.
Regenerate on a real toolchain change, not on every image rebuild.

**The build is repeatable, not bit-reproducible.** Two builds from the same
inputs produce working binaries, not identical ones. Nothing here sets
`SOURCE_DATE_EPOCH` or normalizes build paths, and proving bit-reproducibility
is a substantially larger job than making the build repeatable.

## Open inputs

| Needed | For | Blocking |
|---|---|---|
| An SSH key for the WSL user, registered in Gitea | cloning MXE inside WSL | the Windows artifact, unless `--mxe-src` is used |
| `appimagetool` version and SHA-256 in `upstreams.lock.toml` | `Dockerfile.appimage` | the Linux artifact |
| The two CPython artifacts mirrored | `libsigrokdecode` on Windows | not blocking. They are pinned by SHA-256 and carried in the image, so they cannot change underneath us and a build does not fetch them; only a from-source image rebuild would, and only python.org can serve them |
| A recorded base-image digest for both Dockerfiles | reproducibility | not blocking; the first build records one |

The SSH key is an operator action. Generating one inside WSL and adding the
public half to Gitea is the clean fix; copying a private key across from the
Windows home directory is not, and the script says so rather than offering it.

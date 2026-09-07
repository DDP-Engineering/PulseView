<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE-PolyForm.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Overview

What this project is and what is in it, in the present tense.

This is deliberately not a plan. The earlier planning documents - the original
charter, the implementation package - were removed once the work they described
was done, on the principle that a plan which no longer matches the code is worse
than no plan, because it still reads as authoritative. This page describes the
code that exists, and is subject to the same rule: correct it when it drifts
rather than leaving it standing.

## What was built

Two libsigrok hardware drivers, both written here from protocols recovered by
this project, both verified against the instrument on a bench:

**`hantek-dso3062l`** - Hantek DSO-3062L mixed-signal oscilloscope. The wire
protocol was recovered from the vendor SDK under
`04_HardwareDocu/Hantek_DSO3062L/SDK_3062L/`
using the `protocol_probe` harness, then confirmed live. It covers VDIV and
coupling across the full nine-range ladder, deep capture to 16 Msamples, roll
mode, the trigger system, the relay chain, and factory offset calibration.

**`atk-dl16`** - ALIENTEK ATK-DL16 logic analyzer, recovered from the vendor's
GPL sources. The device sends per-channel bitstreams rather than packed samples,
so the driver transposes them; end-of-capture is taken from the byte count
order 3 promises, which is the only signal in the protocol that is not an
inference. It also drives the device's PWM generators.

Both build into a single PulseView. That is why the deliverables are named
`pulseview-*` rather than after either instrument.

Alongside them, a **first-party decoder set**: six stacking decoders forming a
100BASE-FX networking chain, bringing the total from 131 upstream to 137.

And **five packaged deliverables**, all in `07_Delivery/`: a statically linked
Windows x86_64 zip, a thin Linux x86_64 tarball, self-contained x86_64 and
aarch64 AppImages, and an arm64 Debian package derived from the verified
aarch64 AppImage.

## Why the whole stack is here

libsigrok has no runtime plugin ABI. Drivers are collected at link time, so a
new device means recompiling libsigrok - and on Windows PulseView is statically
linked against it, so it means recompiling PulseView too. A plugin was never an
option; a fork was the only shape this could take.

The stack was originally carried as git submodules pinned to Gitea mirrors. That
was abandoned in August 2026 and everything now lives in `05_Software/` as
**ordinary files in this repository's own history**. Submodules cost two commits
per change, made history rewriting require gitlink remapping by hand, and turned
a stale pointer into a silent failure. The mirrors were deleted at the same time
because nothing referenced them any more.

The consequence worth internalising: a clone carries every source it builds.
There is no `git submodule update` step, and `05_Software` is not a passive copy
that can be re-vendored from upstream without losing work.

### Components

| Path | Role |
|---|---|
| `05_Software/libsigrok` | Acquisition library. **Locally authored** - both drivers live in `src/hardware/`. Deliberately absent from the lock file, because a re-vendor would overwrite them. |
| `05_Software/libsigrokdecode` | Decoder engine and the 137 decoders. A **modified vendor tree** since the decoder import; `clone_enabled = false`. |
| `05_Software/pulseview` | The Qt GUI, 0.5.0. Unmodified so far. |
| `05_Software/sigrok-cli` | CLI frontend. Every test in the suite drives decoding through it. |
| `05_Software/libserialport`, `libusb` | Vendored transport dependencies. `libusb` carries a WinUSB RAW_IO patch for 512-byte-aligned transfers, which is these devices' endpoint size. |
| `05_Software/sigrok-util` | Upstream build and firmware helper scripts, kept for reference. |
| `05_Software/protocol_probe` | **First party.** The Python reverse-engineering harness the drivers came out of: DLL analysis, command mapping, and per-subsystem probes. |

Provenance, upstream commits, licences and role transitions are recorded in
`02_Tools/upstream/upstreams.lock.toml`, under
`policy = "immutable-commits-only"`. When a vendored tree stops being a passive
copy, its entry is required to say so, and to say what a future upstream rebase
would cost.

## How it is built and shipped

Two stages, and the distinction matters more than anything else in the build.

**Stage one builds the toolbox, in hours, once.** `build_image.sh` produces a
Docker image containing MXE with every sigrok dependency already cross-compiled
for Windows - gcc 11.5.0, Qt 5.15.19, glib held at 2.89.1, glibmm 2.66.2, and
CPython 3.13.15 at `/opt/sigrok-deps`. It contains none of this project, so
changing a driver never invalidates it. Qualified images are exported as
checksum-bound multipart `docker save` archives under
`07_Delivery/toolchain/` and tracked in Git LFS. Their manifests bind the exact
image, dependency declaration, resolved inventory, validation policy, and SPDX
SBOM. This is what makes later archived-builder builds offline: MXE otherwise
downloads from 117 distinct hosts, and the risk there is disappearance, not
corruption.

**Stage two builds the application, in minutes, on every change.** The four
target build scripts re-exec themselves into the appropriate container and
compile or package the vendored sources. The Windows path additionally embeds
CPython and, at staging, walks the PE import table to prove the only non-system
import is `python313.dll`. All of this runs from WSL, because the container
engine lives there; the host-side tests run natively on Windows, because that
is where the `.exe` can execute.

The AppImage has a separate builder image on Ubuntu 22.04 rather than sharing
the Debian one. An AppImage runs on any glibc newer than the one it was built
against and none older, so the base image *is* the Linux compatibility floor,
and merging the two images would silently raise it.

Operator detail is in
[`01_Documentation/Environment_Setup.md`](../01_Documentation/Environment_Setup.md).
The verification ledger - which script was proved on which host, with which
command - is `02_Tools/build/STATUS.md`.

## The decoder expansion

Beyond the two drivers, the project imports protocol decoders from ATK-Logic in
checkpointed batches, tiered by usefulness. Each batch is a separate task with
its own requirements and its own decode evidence, rather than one bulk import.

**Batch one, complete: the networking stack.** Six decoders forming a single
chain, `logic -> nrzi -> 4b5b -> ethernet -> {arp | ipv4 -> udp}`. The
`ethernet` decoder additionally emits pcapng binary output, so a capture can be
opened in Wireshark.

They were verified with a synthesized capture rather than hardware. The demo
driver's canned patterns do not speak NRZI or 4B5B, and no 100BASE-FX capture
gear was available - so `gen_networking_stack_captures.py` builds real Ethernet
II frames with correct FCS, IPv4 header checksum and UDP checksum, and encodes
them as the exact inverse of the `nrzi` and `4b5b` decoders' own state machines.
The test then requires 23 specific decoded field values to appear. A decoder
that loads but decodes nothing counts as a failure here, not a pass; that is
written down as `REQ-FUNC-f9a157d9` and it is the standing bar for every later
batch.

**Remaining: 59 further Tier A decoders**, plus Tier B, C and D.

These six were confirmed byte-identical in header, id and directory name to the
still-open upstream PR `sigrokproject/libsigrokdecode#62`. That PR proposes
merging `ipv4` and `arp` and folding `nrzi`, `4b5b` and `ethernet` into a single
`100base-fx` decoder. The restructure was **not** adopted: staying identical to
the submitted form keeps a future upstream merge cheap, and the stacked form is
more useful for inspecting a link one layer at a time.

## Deliberately not done

- **Bit-reproducible builds.** The build is repeatable - two builds from the
  same inputs produce working binaries, not identical ones. Nothing sets
  `SOURCE_DATE_EPOCH` or normalizes build paths.
- **libsigrok's unit tests on Windows.** `check` is excluded from the MXE
  package set because libcheck and winpthreads clash over `clock_gettime`, so
  they cannot be cross-built for that target.
- **ALIENTEK's forked base decoders** - `i2c`, `spi`, `uart`, `ps2`, `jtag`,
  `onewire_network`. ATK-Logic ships modified versions; importing them would
  mean diverging from upstream on decoders that already work.
- **Mirrored upstreams.** The Gitea mirrors were deleted on 2026-08-19 and
  `clone_enabled = false` on every git source. The lock file is now a provenance
  and licence record, not a fetch plan.
- **CI.** Tests are run by hand, on a host that can run them.

## Where the authority lives

This page summarises. When the detail matters, these are the sources, and they
are the ones to correct:

| Question | Authority |
|---|---|
| What does this opcode do, and is it safe to send? | `04_HardwareDocu/<device>/` |
| Why was the build done this way, and what is verified? | `02_Tools/build/STATUS.md` |
| Where did this source come from, under what licence? | `02_Tools/upstream/upstreams.lock.toml` |
| How do I set up and build? | `01_Documentation/Environment_Setup.md` |
| How do I test, and what does the suite prove? | `01_Documentation/Testing.md` |
| What is being worked on right now? | `.agentic/tasks/` - `python .agentic/aegis.py status` |
| What changed and when? | `CHANGELOG.md` |

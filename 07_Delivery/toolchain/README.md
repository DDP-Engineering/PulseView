<!--
Copyright (c) 2026 DDP Engineering
This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.
See the LICENSE.txt file for full license details.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Saved builder images

This directory holds multipart container archives for the three canonical
builder variants. Git LFS tracks archive parts. Stable TOML manifests and JSON
sidecars remain ordinary Git content.

## Normal use

The commands below are the steady-state schema-2 workflow. The archives
currently checked in are still schema 1, so a clean host must temporarily add
`--allow-legacy-restore` to use those exact bytes, or `--rebuild` to create a
current image online. After all three schema-2 generations are committed, no
migration option is needed.

Run the bootstrap in WSL or on Linux:

```sh
bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform amd64
bash 02_Tools/bootstrap/ensure_build_environment.sh --image appimage --platform arm64
```

The bootstrap checks a current installed image first. A valid installed image
needs its current recipe and dependency-contract identities, matching type and
architecture, quick offline probes, and current external validation evidence.
It does **not** need a manifest or archive parts.

If no current image is usable, the bootstrap audits a local archive before it
loads any bytes. If local recovery is unavailable, it can offer an explicit
online rebuild. It never downloads LFS objects and never publishes data.

## Canonical variants

| Stable manifest | Builder |
|---|---|
| `pulseview-builder-mingw.manifest.toml` | Windows x86_64 MXE cross-toolchain |
| `pulseview-builder-appimage.manifest.toml` | Linux amd64 AppImage environment |
| `pulseview-builder-appimage-arm64.manifest.toml` | Linux arm64 AppImage and Debian package environment |

## Schema 2 generations

A new schema-2 stable manifest is the commit point for one generation. It
binds all of these values:

- builder type, architecture, install tag, archive tag, and exact image ID;
- separate builder-recipe, dependency-contract, and validation-policy
  identities;
- the embedded normalized dependency contract and resolved package inventory;
- one SPDX 2.3 JSON SBOM;
- the complete logical container archive; and
- every generation-specific archive part by filename, size, and SHA-256.

Generation files include the image-ID prefix in their names. This lets the old
and new sets coexist while an update is staged. The stable manifest is replaced
atomically only after the candidate passes validation and archive round-trip
audit.

The three archives currently checked in predate schema 2. Their schema-1
manifests remain readable for migration, but normal bootstrap does not treat
them as current verified builders. Use `--allow-legacy-restore` only for the
bounded migration path. Regenerate all three variants before removing that
option.

## Updating a builder

Use the owner command. Do not combine manual build, tag, save, and file-copy
steps:

```sh
bash 02_Tools/build/update_builder_environment.sh --image mingw --plan
bash 02_Tools/build/update_builder_environment.sh --image mingw --replace
bash 02_Tools/build/update_builder_environment.sh \
  --image appimage --platform amd64 --plan
bash 02_Tools/build/update_builder_environment.sh \
  --image appimage --platform amd64 --replace
bash 02_Tools/build/update_builder_environment.sh \
  --image appimage --platform arm64 --plan
bash 02_Tools/build/update_builder_environment.sh \
  --image appimage --platform arm64 --replace
```

Plan mode makes no output-directory changes. Replacement is explicit,
Docker-only, and serialized per builder variant.

The replacement command does the following work:

1. builds under a content-derived candidate tag and unique volume;
2. runs quick and standard dependency checks;
3. builds representative product output under `.work/` with no network;
4. runs every mandatory product check, where exit 77 is a failure;
5. creates the resolved inventory and SPDX sidecars;
6. exports, splits, and audits a schema-2 archive;
7. promotes verified identity-bearing generation files;
8. replaces the stable manifest as the final filesystem commit point; and
9. tags the exact round-trip image for normal local use.

A handled pre-commit failure preserves the old stable tag and manifest and
removes newly promoted files. A post-commit tagging failure leaves the complete
new manifest authoritative so bootstrap can restore it; it does not roll back
to mixed archive data. The command performs no repository staging, commit, push, LFS
upload, registry push, or release publication. Those actions remain explicit
maintainer work.

`save_image_parts.sh` is the lower-level local export command. Prefer the
coordinator because direct export does not build or qualify a candidate.

## Historical verification

A stale schema-2 archive is rejected during normal selection. A maintainer can
request explicit historical verification:

```sh
bash 02_Tools/bootstrap/ensure_build_environment.sh \
  --image appimage --platform amd64 \
  --allow-historical-builder --force-restore
```

This mode verifies the manifest's exact image ID, embedded normalized contract,
resolved inventory, and historical dependency probes. It prints a prominent
warning because the selected builder is not the current repository recipe.

## Reproducibility boundary

Archive restore is exact and offline. A deliberate builder rebuild still uses
live Debian or Ubuntu package repositories and, for MXE, its pinned source plus
upstream package downloads. The lifecycle records resolved package versions and
binds them in the SBOM, but exact online reconstruction from repository state is
deferred. That would require dated package snapshots or preserved package
payloads.

Docker is the required engine. The scripts propagate an explicit engine and are
kept compatible with Podman where practical, but Podman lifecycle operation is
experimental until an end-to-end generation is recorded.

## Git LFS notes

A clone without Git LFS receives small pointer files instead of archive bytes.
Archive audit rejects those files before container-engine load. Install LFS and
fetch the real objects if exact archive recovery is required:

```sh
git lfs install
git lfs pull
```

Container archive layers are already compressed. Splitting the uncompressed
`docker save` stream keeps each LFS object below common per-file limits without
adding another compression format.

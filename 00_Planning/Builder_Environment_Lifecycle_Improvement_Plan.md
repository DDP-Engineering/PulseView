<!--
Copyright (c) 2026 DDP Engineering
This software is licensed under the PolyForm Noncommercial License 1.0.0.
Commercial use requires a separate commercial license.
See the LICENSE-PolyForm.txt file for full license details. SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-->

# Builder Environment Lifecycle Improvement Plan

Status: approved for implementation

Date: 2026-09-07

## Purpose

Turn the existing builder-image creation, archive, and restoration tools into a
complete lifecycle for maintaining the build environment as dependencies
change.

A developer must be able to prepare a current, verified build environment after
cloning the repository. A maintainer must be able to update that environment
through one safe local workflow.

Committing Git LFS objects and publishing repository changes remain deliberate
developer actions.

## Current baseline

The repository already has the principal mechanisms:

- `Dockerfile.mingw` and `Dockerfile.appimage` describe the builder types.
- `build_image.sh` creates a local builder from repository recipes and pinned
  upstream inputs.
- `builder_spec.sh` identifies the recipe, architecture, build options, helper
  scripts, and selected patch contents.
- `save_image_parts.sh` exports an image as checksum-verified, Git LFS-sized
  archive parts and a TOML manifest.
- `ensure_build_environment.sh` validates an installed image or reconstructs
  one from local archive parts.
- The bootstrap offers an explicit online rebuild when restoration is not
  possible.
- The test suite covers recipe identity, archive corruption, host
  prerequisites, architecture mapping, and container-engine argument flow.

These mechanisms establish archive integrity and local image creation. They do
not provide one atomic update command or a comprehensive dependency contract.

The three current manifests are schema-1 records with an empty `builder_spec`.
Their exact `image_id` proves that the archived bytes were restored correctly.
It does not prove that the archive represents the current repository recipe.

Normal development therefore cannot distinguish an intact historical image
from an intact current image.

## Required outcome

### Installed current image

An already-installed image may be used without local archive parts when all of
these conditions hold:

1. Its image type and architecture match the requested build.
2. Its `builder_recipe_spec` matches the current selected repository recipe.
3. Its `dependency_contract_spec` matches the current selected contract.
4. The applicable dependency-contract checks pass inside the image.
5. Its validation evidence is current for the applicable
   `validation_policy_spec`.

The bootstrap must not require Git LFS archive availability when such an image
is valid.

### Archive restoration or audit

When an archive is restored or audited:

1. Its manifest syntax, image type, architecture, and archive identity match
   the request.
2. Every archive part passes exact size and SHA-256 verification.
3. The reconstructed archive passes exact size and SHA-256 verification.
4. The restored image has the exact manifest `image_id`.
5. The embedded normalized contract and resolved inventory match their
   manifest and image-label hashes.
6. Normal mode also requires the current recipe and contract identities.

Archive parts are required only for restoration or an explicit archive audit.

### Regeneration and replacement

A regenerated builder must satisfy these conditions:

1. Its declared dependency contract passes.
2. A clean product build completes with container networking disabled.
3. Every mandatory builder-specific smoke test runs and passes.
4. Its archive reconstructs to the exact candidate image.
5. A failed or interrupted update leaves the previous archive usable.
6. Candidate output remains under `.work/` until promotion.
7. The lifecycle does not stage, commit, push, upload, or publish anything.

## Non-goals

- Automating Git staging, commits, tags, pushes, or Git LFS publication.
- Publishing to Gitea, GitHub, GitLab, or an OCI registry.
- Hiding network use during a local online rebuild.
- Claiming bit-reproducible product binaries without separately controlling
  timestamps, paths, and other nondeterminism.
- Treating a short command-presence probe as proof that the product can build.
- Qualifying Podman for builder regeneration in the core implementation.
- Making online package resolution exactly reproducible in the core
  implementation.
- Automating hardware-dependent or physical-Pi release evidence.

## Identity model

The lifecycle uses separate identities for separate claims.

### `builder_recipe_spec`

This identifies only inputs that can change image contents. It includes:

- the selected Dockerfile;
- the canonical builder profile and effective content-changing options;
- the selected normalized dependency contract;
- build-context and image-construction code;
- selected helper scripts and patch bytes;
- only relevant upstream-lock entries for the builder and architecture;
- the selected platform and target.

An unrelated upstream-lock change must not change this identity.

A dependency-contract change that changes installed image contents must change
both `dependency_contract_spec` and `builder_recipe_spec`.

### `dependency_contract_spec`

This is the SHA-256 identity of the normalized dependency contract selected for
the builder and architecture.

Normalization must be deterministic. Comments, irrelevant architecture
sections, and source-file location must not affect the selected identity.

### `validation_policy_spec`

This identifies the verifier implementation, probe definitions, mandatory test
policy, and their relevant helper code.

A validation-policy change requires revalidation. It does not require an image
rebuild when image contents and the dependency contract are unchanged.

Local revalidation evidence must be keyed by image ID and
`validation_policy_spec`. It belongs under `.work/` and must not alter image
bytes merely to record a new validation result.

### Exact byte identities

- `image_id` identifies the exact produced container image.
- `archive_sha256` identifies the exact saved archive bytes.
- Each archive part, inventory, report, and SBOM has its own size and SHA-256.

Recipe equivalence, validation currency, and exact bytes must not be conflated.

## Embedded builder metadata

Each new builder image must contain these machine-readable files under:

```text
/usr/local/share/pulseview-builder/
```

At minimum, the directory contains:

- the normalized selected dependency contract;
- the resolved distribution-package inventory;
- metadata naming the builder type, platform, and canonical profile;
- the identity values associated with those files.

Image labels must record at least:

- `builder_recipe_spec`;
- `dependency_contract_spec`;
- the normalized-contract SHA-256;
- the resolved-inventory SHA-256;
- the selected base-image digest.

The labels and embedded metadata must agree. The archive manifest must record
the same identities and hashes.

## Historical-image policy

Historical reproduction is explicit and must never be confused with normal
current development.

Historical mode must verify:

1. the exact archived image ID;
2. the embedded normalized contract against the manifest hash;
3. the embedded resolved inventory against the manifest hash;
4. the image using its embedded historical contract.

Historical mode does not require the historical recipe or contract to match the
current checkout.

The command must prominently report that the selected image does not represent
the current repository recipe.

A schema-1 legacy image has no embedded contract or inventory. It may be
accepted only through the temporary explicit legacy option during migration.

## Canonical builder profiles

### Canonical MinGW profile

The repository owns one canonical MinGW profile:

- `mxe_fixes.patch` is excluded;
- `libusb1_upgrade.patch` is applied;
- the Qt 5.7 freeze is disabled;
- the repository-default glib hold/version is used;
- the target is `x86_64-w64-mingw32.static.posix`;
- the host platform is Linux x86-64.

The update coordinator must apply this profile automatically. A maintainer must
not have to remember `--skip-patch mxe_fixes.patch`.

Experimental overrides may be supported. An overridden image must not replace
the canonical archive unless a separate explicit action promotes that exact
profile as the repository canonical profile.

The plan mode and update report must show the effective profile and whether it
is canonical.

### AppImage profiles

The AppImage builder has separate selected profiles for Linux x86-64 and Linux
ARM64. Architecture-specific contract and lock entries must not leak between
them.

## Container-engine policy

Docker is the required and verified engine for heavy builder regeneration,
full verification, and archive promotion.

Keep Podman-compatible argument handling and fixture coverage. Report Podman as
experimental until all builder variants complete the full lifecycle with it.

Podman qualification must not block the core implementation.

## Git boundary

Lifecycle tools may perform read-only Git operations against the project
repository.

The MinGW build may clone, fetch, inspect, and check out pinned MXE source under
`.work/`. Those operations are build-input preparation and do not mutate the
project repository.

Lifecycle tools must not:

- mutate the project checkout or index;
- run `git add`, `commit`, `reset`, `branch`, `tag`, or `push`;
- upload Git LFS objects;
- publish an image to a registry;
- publish repository changes through any forge command.

Tests must distinguish permitted input-fetch operations from forbidden project
or publication operations.

## Design principles

### One source of truth for direct dependencies

The list used to install direct packages and the list used to verify them must
come from the same reviewed dependency contract.

Maintaining independent lists in a Dockerfile and a test would allow both lists
to drift from the real build.

Transitive operating-system packages may be recorded as resolved inventory.
They are not manually declared as direct requirements.

### Integrity, currency, and validation are separate

An exact image ID proves archive restoration. A recipe-spec match proves recipe
currency. A contract-spec match proves declaration currency.

A validation-policy match or revalidation record proves that the applicable
checks ran under the current policy.

Normal development requires all applicable claims. Historical mode replaces
currency with explicit exact-image and embedded-contract checks.

### Functional checks close the declaration gap

No static package list can discover every future C or C++ build dependency.
Configure systems can also silently disable optional functionality.

The lifecycle must combine declarative checks with a real clean offline product
build and assertions about required features.

### Replacement is transactional

Generation and verification occur under `.work/`. The stable manifest is
replaced only after candidate files and reconstructed image validation pass.

Identity-bearing part names allow old and new generations to coexist. A failure
or interruption leaves the previous stable manifest and generation usable.

### Candidates are isolated

Every update uses:

- a content-derived candidate image tag;
- a unique candidate build volume;
- an explicit output root under `.work/`;
- candidate archives, reports, and product artifacts under `.work/`.

No candidate product or archive output may be written under `07_Delivery/`.
Retagging and delivery promotion occur only after every mandatory check passes.

## Proposed file layout

All implementation remains under the repository layout contract:

| Proposed path | Responsibility |
|---|---|
| `02_Tools/build/images/dependencies.mingw.toml` | Selected MinGW packages, commands, files, libraries, target outputs, and required features. |
| `02_Tools/build/images/dependencies.appimage.toml` | AppImage dependency contract with architecture-specific entries. |
| `02_Tools/build/images/builder_profile.mingw.toml` | Repository-owned canonical MinGW options and target. |
| `02_Tools/build/verify_builder_environment.sh` | Quick, standard, and full verification. |
| `02_Tools/build/update_builder_environment.sh` | Transactional build, validation, export, round trip, and promotion coordinator. |
| `.work/build-context/` | Generated normalized contracts and Docker build contexts. |
| `.work/bootstrap/` | Candidate archives, manifests, reconstruction, validation evidence, inventories, SBOMs, and update reports. |
| `07_Delivery/toolchain/` | Stable manifests and their final verified parts, inventories, and SPDX SBOMs. |

Existing build entry points must gain the parameters required for candidate
tag, unique build volume, and explicit `.work/` output-root isolation.

No generated package list or candidate archive may be written elsewhere.

## Dependency-contract model

Define a small, versioned TOML schema for the properties the product depends
on. For example:

```toml
schema = 1

direct_packages = ["cmake", "pkg-config"]

[[command]]
name = "cmake"
version_args = ["--version"]
level = "quick"

[[pkg_config]]
name = "libusb-1.0"
level = "standard"

[[file]]
path = "/usr/local/lib/appimage/runtime"
sha256_artifact = "appimage-runtime-x86_64"
level = "quick"

[[feature]]
name = "libsigrok-hantek-dso3062l"
probe = "product-feature"
level = "full"
```

The final schema must support:

- direct distribution packages;
- required commands and optional version constraints;
- `pkg-config` modules;
- headers and compile-and-link library probes;
- fixed files whose checksums come from `upstreams.lock.toml`;
- MXE target tools and installed target outputs;
- architecture-specific requirements;
- required product features that configure must not disable;
- explicit quick, standard, and full verification levels.

Unknown fields and unsupported contract versions must fail closed.

Every checksum-pinned file must refer to an existing applicable lock artifact.
The normalized selected contract must be generated before the Docker build.

The Dockerfile consumes its direct-package projection. The verifier consumes
the same normalized contract.

## Verification levels

### Quick

Quick verification runs whenever `ensure_build_environment.sh` selects an
already-installed image.

It must remain fast and offline. It checks:

- image type and architecture;
- current or explicitly historical identity policy;
- embedded contract and inventory hashes;
- essential commands and fixed files marked `quick`;
- current validation evidence or the need for revalidation.

Quick verification does not require local archive parts.

### Standard

Standard verification runs after image creation, after a validation-policy
change when required, and before archive export.

It checks:

- every declared direct package with `dpkg-query`;
- required commands and declared version constraints;
- `pkg-config` modules;
- required headers;
- compile-and-link probes for important native libraries;
- MXE target compilers and declared target outputs;
- Python embedding files;
- AppImage tools and the pinned runtime checksum;
- all applicable `standard` contract entries;
- embedded contract and inventory hashes.

A failure must name the exact contract entry and useful remedy context.

### Full

Full verification runs during deliberate builder regeneration and before
archive promotion.

It performs a clean product build with container networking disabled. It then
runs every mandatory builder-specific smoke test.

Exit 77 is not accepted for archive promotion. Each mandatory test must run or
use a defined equivalent runner.

Hardware-dependent checks and physical-Pi checks remain separate release
evidence. They are not builder-completeness promotion gates.

## Mandatory full-verification matrix

### MinGW

All of these checks are mandatory:

- the dependency contract passes;
- a clean offline build completes for `libserialport`, `libsigrok`,
  `libsigrokdecode`, `sigrok-cli`, and PulseView;
- Windows ZIP staging succeeds;
- `hantek-dso3062l` and `atk-dl16` are listed;
- embedded Python 3.13 works;
- all expected decoders are present;
- the first-party NRZI, 4B5B, Ethernet, ARP, IPv4, and UDP stack is present and
  passes its functional decode smoke;
- PE import-closure validation passes;
- Windows-native or Wine runtime smoke passes.

### AppImage x86-64

All of these checks are mandatory:

- the dependency contract passes;
- a clean offline AppImage build completes;
- AppImage identity validation passes;
- CLI version, both project drivers, and decoder loading pass;
- runtime testing passes in a clean supported base;
- an automated GUI-startup smoke passes where practical.

If GUI automation is not practical on the selected host, the implementation
must define an equivalent automated runner before promotion is allowed.

### AppImage ARM64

All of these checks are mandatory:

- the dependency contract passes;
- a clean offline ARM64 AppImage build completes;
- ARM64 ELF and type-2 AppImage identity validation passes;
- CLI, both project drivers, and decoder smoke pass under native ARM64 or
  verified binfmt emulation;
- the ARM64 Debian package build and metadata verification pass.

Physical-Pi execution remains separate release evidence and is not required to
promote the builder archive.

## Manifest schema 2

Schema 2 retains archive and part checksums and adds separated identities and
embedded metadata hashes. At minimum, it records:

```toml
schema = 2
format = "docker-archive"
image = "mingw"
platform = "linux/amd64"
install_tag = "pulseview-builder-mingw:latest"
archive_tag = "pulseview-builder-mingw:candidate-<identity>"
image_id = "sha256:..."
builder_recipe_spec = "..."
dependency_contract_spec = "..."
validation_policy_spec = "..."
normalized_contract_sha256 = "..."
resolved_inventory_sha256 = "..."
base_image = "docker.io/library/debian@sha256:..."
archive = "pulseview-builder-mingw-<identity>.tar"
archive_size = 0
archive_sha256 = "..."
inventory = "pulseview-builder-mingw-<identity>.inventory.json"
inventory_size = 0
inventory_sha256 = "..."
```

After the SPDX phase, a final promoted manifest also records the SPDX 2.3 JSON
file name, byte size, and SHA-256.

The manifest contains one `[[part]]` entry per file with its exact name, byte
size, and SHA-256.

The archive may retain its content-derived candidate tag. Restore validates the
exact image ID, then applies `install_tag` only after verification succeeds.

Schema-2 parsing must validate required fields, types, safe file names, duplicate
entries, image type, platform, archive format, and identity relationships.

## Authoritative implementation phases

The phases below are authoritative. Each phase must preserve the previous
working archive and must satisfy its acceptance criteria before the next phase.

### Phase 1 - Dependency-contract schema

1. Define the versioned MinGW and AppImage contract schemas.
2. Define deterministic normalization and architecture selection.
3. Define quick, standard, and full entry levels.
4. Define version-constraint and probe semantics.
5. Add fail-closed parser and fixture tests.
6. Define the canonical MinGW profile in repository data.

Acceptance criteria:

- unknown fields and unsupported versions fail closed;
- architecture-specific entries cannot leak into another image;
- every lock-file reference resolves to an applicable artifact;
- normalization is deterministic;
- adding or removing a selected entry changes `dependency_contract_spec`;
- the canonical MinGW profile expresses all approved effective options.

### Phase 2 - Quick and standard verifier

1. Create `verify_builder_environment.sh`.
2. Implement quick and standard levels from the same normalized contract.
3. Produce exact entry-level diagnostics.
4. Add fixture engines and small image-contract fixtures.
5. Add local revalidation evidence keyed by image and policy identity.

Acceptance criteria:

- removing a declared package, command, module, header, or fixed file fails;
- quick verification stays suitable for normal bootstrap;
- standard verification covers every applicable declaration;
- stale validation policy triggers revalidation, not an image rebuild;
- failures identify the exact contract entry and remedy context.

### Phase 3 - Docker builds consume the contracts

1. Normalize the selected contract into `.work/build-context/`.
2. Generate the direct-package projection from that contract.
3. Remove duplicate hand-maintained direct-package lists from Dockerfiles.
4. Embed the normalized contract under the stable image metadata path.
5. Record and embed the resolved distribution-package inventory.
6. Add the approved identity and metadata labels.

Acceptance criteria:

- installation and verification consume the same package declaration;
- changing a selected direct package changes image contents and identities;
- the normalized contract and inventory are present inside each image;
- embedded file hashes match image labels;
- no generated package list is written outside `.work/`.

### Phase 4 - Builder and validation identities

1. Replace the ambiguous builder identity with the separated identity model.
2. Hash only applicable lock entries into `builder_recipe_spec`.
3. Include selected image-producing inputs and effective canonical options.
4. Define `validation_policy_spec` from verifier and test-policy inputs.
5. Preserve compatibility diagnostics for the old builder label.

Acceptance criteria:

- unrelated lock edits do not change a builder recipe identity;
- relevant lock, contract, Dockerfile, helper, profile, or patch changes do;
- verifier-only changes alter `validation_policy_spec`, not
  `builder_recipe_spec`;
- all identities are deterministic across equivalent paths and hosts.

### Phase 5 - Schema-2 generation and legacy reading

1. Generate strict schema-2 manifests with identity-bearing artifact names.
2. Read schema 1 and report it explicitly as legacy.
3. Keep a temporary explicit legacy-acceptance option.
4. Add schema, archive, part, embedded-file, and identity fixture coverage.

Acceptance criteria:

- schema 2 binds parts, archive, image, contract, inventory, and identities;
- schema-1 archives remain diagnosable during migration;
- legacy acceptance is never implicit;
- corruption, missing LFS content, legacy format, and staleness have distinct
  diagnostics.

### Phase 6 - Strict current and historical selection

1. Make current recipe, contract, and validation policy the normal default.
2. Add explicit `--allow-historical-builder` behavior.
3. Verify historical images with their embedded historical contract.
4. Keep installed-current-image selection independent of LFS availability.
5. Offer the existing explicit online rebuild path when restoration cannot
   supply a current image.

Acceptance criteria:

- editing a builder input makes the prior archive stale for normal use;
- an installed current valid image works without archive parts;
- stale archives are not selected silently;
- historical mode verifies exact identity and embedded metadata;
- historical mode prominently reports its stale status;
- schema-1 use requires the temporary legacy option.

### Phase 7 - Transactional update coordinator

Create `update_builder_environment.sh` as the maintainer entry point:

```bash
bash 02_Tools/build/update_builder_environment.sh \
    --image mingw \
    --replace
```

The coordinator must:

1. validate the lock, profile, and selected dependency contract;
2. calculate all intended identities;
3. build under a content-derived candidate tag;
4. use a unique candidate build volume and `.work/` output root;
5. confirm candidate labels and embedded metadata;
6. run standard verification;
7. invoke full verification before any real promotion;
8. export into a new `.work/bootstrap/` generation;
9. split below the configured Git LFS size ceiling;
10. generate a schema-2 candidate manifest;
11. verify every part and reconstruct the archive;
12. load or inspect the reconstruction and require the candidate image ID;
13. move verified identity-bearing files into `07_Delivery/toolchain/`;
14. replace the stable manifest last;
15. retag the verified image for normal use only after all checks pass;
16. remove only the specifically superseded local generation;
17. print a concise report and paths the developer may stage.

The coordinator must refuse replacement without `--replace`.

Plan mode must show inputs, profile, identities, tags, volumes, paths, and
removals without building or changing delivery files.

Concurrent updates for the same builder variant must be serialized. Promotion
must use destination-local temporary files and atomic renames.

During this phase, fixture-driven transaction tests and non-promoting candidate
runs may execute. Real `--replace` promotion must remain disabled until Phase 8
implements every mandatory full-verification gate.

Acceptance criteria:

- every failure before stable-manifest replacement preserves the old generation;
- interruption cannot create a manifest that references mixed generations;
- candidate output never enters product delivery paths;
- a round trip restores the exact candidate image;
- the coordinator performs no forbidden Git or publication operation;
- Docker is enforced for promotion while Podman remains experimental.

### Phase 8 - Full clean offline verification

1. Add isolated clean-build invocation for every builder variant.
2. Deny container networking during product builds.
3. Implement the mandatory verification matrix above.
4. Define equivalent runners where the default host cannot execute a test.
5. Treat exit 77 as a failed promotion gate.
6. Record every command, result, and runner in the candidate report.

Acceptance criteria:

- removing a real build dependency fails the full offline build;
- disabling a required feature fails even when compilation succeeds;
- MinGW runtime smoke runs under Windows or Wine;
- x86-64 AppImage runtime and GUI-startup smoke run in a clean base;
- ARM64 smoke runs under native ARM64 or verified emulation;
- ARM64 Debian package and metadata verification pass;
- no mandatory promotion check is skipped.

### Phase 9 - Regenerate and round-trip all archives

Regenerate these variants through the coordinator:

1. MinGW x86-64;
2. AppImage x86-64;
3. AppImage ARM64.

Acceptance criteria:

- all three use canonical profiles and schema 2;
- all three pass standard and full verification;
- all three round trips reproduce the exact candidate image ID;
- every final archive has embedded contract and inventory metadata;
- the prior generation remains usable until each manifest is replaced;
- generated review reports name every promoted file.

### Phase 10 - Require schema 2 by default

1. Make schema 2 mandatory for normal bootstrap.
2. Retain historical schema-2 selection.
3. Retire the schema-1 legacy option after migrated archives are distributed.
4. Update authoritative bootstrap and build documentation.

Acceptance criteria:

- normal bootstrap rejects schema 1;
- all current archive variants are schema 2;
- stale, historical, corrupt, and missing-LFS cases remain distinct;
- historical schema-2 archives remain usable through explicit mode.

Core lifecycle implementation is complete after this phase.

### Phase 11 - Final inventory sidecars and SPDX SBOM

Resolved package inventory is a core image input and is already embedded in
Phase 3. This phase publishes verified sidecars and adds the canonical SBOM.

1. Export the final resolved inventory beside each archive manifest.
2. Generate an SPDX 2.3 JSON SBOM for each builder image.
3. Bind both files by name, size, and SHA-256 in the stable manifest.
4. Ensure the SBOM and report name the same image and identities.
5. Document the image as an aggregate whose contents retain upstream licences.

Candidate inventories, update reports, and SBOMs remain under `.work/`.
Update reports remain there after promotion.

Only final verified inventory and SBOM copies belong under
`07_Delivery/toolchain/`.

CycloneDX is not canonical. It may be added later as a derived artifact for
vulnerability tooling.

Acceptance criteria:

- every image exposes a machine-readable resolved inventory;
- every final manifest binds its inventory and SPDX 2.3 JSON SBOM;
- inventory, report, SBOM, image labels, and manifest agree on image identity;
- documentation does not apply one project licence to the aggregate contents.

### Phase 12 - Consider exact online reconstruction separately

Exact online reconstruction is explicitly deferred.

The supported exact path is restoration of the archived image.

Online rebuild remains a functional recovery path. It uses pinned base-image
digests and checksum-pinned external artifacts, while `apt` resolves packages
from live repositories.

A later decision may choose:

1. dated Debian and Ubuntu repository snapshots with pinned package versions;
2. preservation of the required `.deb` closure as verified artifacts.

That decision requires a separate storage, availability, maintenance, and
licensing assessment.

## Verification strategy

The lightweight repository suite uses fixture engines and small archives for
fast control-flow coverage.

Add coverage for:

- contract parsing, normalization, and unknown-field rejection;
- architecture-specific contract selection;
- canonical MinGW profile selection;
- separated identity behavior;
- schema-1 migration and schema-2 validation;
- stale archive rejection and explicit historical acceptance;
- embedded historical-contract verification;
- missing packages, commands, modules, headers, libraries, and fixed files;
- validation-policy revalidation without image rebuild;
- candidate tag, volume, and output-root isolation;
- failed verification preventing replacement;
- interrupted export preserving the previous generation;
- concurrent update serialization;
- multipart export and restore round trip;
- Docker promotion enforcement and Podman-compatible argument flow;
- permitted MXE source operations and forbidden Git/publication operations.

Real image creation and full offline product builds are heavy tests. They run
during deliberate regeneration and any future heavy or scheduled CI job.

The current lightweight test command remains:

```bash
bash 02_Tools/test/run_tests.sh
```

Implementation must add syntax and static-analysis commands appropriate to new
shell and Python code, and record them in the authoritative test documentation.

## Intended workflows

### Normal clone and build

```bash
git lfs pull
bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw
bash 02_Tools/build/build_windows_mxe.sh --offline --stage
```

If a valid current image is already installed, missing archive parts do not
prevent its use.

### Deliberate historical reproduction

```bash
bash 02_Tools/bootstrap/ensure_build_environment.sh \
    --image mingw \
    --allow-historical-builder
```

The command verifies the exact image and its embedded historical contract. It
prominently reports that the environment does not match the current recipe.

### Dependency update

1. Edit the dependency contract.
2. Update relevant `upstreams.lock.toml` entries when pinned inputs change.
3. Update the Dockerfile or helper only for behavior beyond the contract.
4. Run the update coordinator in plan mode.
5. Review the canonical profile and calculated identities.
6. Run the real update with `--replace`.
7. Review the report and repository diff.
8. Stage, commit, and publish manually.

## Completion criteria

The core lifecycle is complete when:

- adding a direct dependency has one reviewed source-of-truth change;
- an installed current image works without local LFS archive parts;
- an obsolete archive cannot be selected silently;
- historical mode verifies its embedded historical contract;
- every current builder passes its declarative contract;
- every promoted builder proves a clean offline product build;
- every mandatory promotion check runs and passes;
- archive replacement is isolated, transactional, and round-trip verified;
- all three platforms use non-legacy manifests;
- identities distinguish recipe, contract, validation policy, and exact bytes;
- unrelated lock or verifier changes do not force image rebuilding;
- the developer remains solely responsible for Git and publication actions;
- exact archive restoration and functional online rebuilding are documented
  without conflating them.

The provenance follow-up is complete when each final manifest also binds its
resolved inventory and canonical SPDX 2.3 JSON SBOM.

Once implementation is reflected in authoritative build documentation, remove
this planning document rather than retain a stale second description.

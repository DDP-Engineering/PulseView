#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build a sigrok builder image - stage 1 of the two-stage build.
#
# This is the slow half that happens once. It stages a minimal build context,
# resolves pins from upstreams.lock.toml, pins the base image by digest, builds
# the image, and writes a build record. Stage 2 (compiling sigrok itself) is
# run_in_builder.sh and takes minutes.
#
# Run this inside WSL, not Git Bash: the container engine lives there.
#
#   ./build_image.sh --image mingw
#   ./build_image.sh --image mingw --save 07_Delivery/toolchain/mingw.tar
#   ./build_image.sh --image appimage --dry-run
#   ./build_image.sh --image appimage --platform aarch64   Raspberry Pi 4/5
#                    builder (on an x86_64 host this needs qemu binfmt -
#                    check_host.sh reports whether it is set up)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"
IMAGES_DIR="${SCRIPT_DIR}/images"
CONTEXT_ROOT="${REPO_ROOT}/.work/build-context"
LOG_ROOT="${REPO_ROOT}/.work/logs"

IMAGE=""
TAG=""
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
SAVE=""
NO_CACHE=0
DRY_RUN=0
QT5_FREEZE=0
SKIP_PATCHES=""
SUB_JOBS=4
PKG_JOBS=""
MXE_SRC_LOCAL=""
GLIB_VERSION=""

usage() {
    sed -n '8,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --image mingw|appimage   Which builder to produce.            (required)
  --platform ARCH          Target architecture: x86_64 or aarch64 (arm64).
                           Default: the host architecture. Only the
                           appimage image builds for aarch64; the mingw
                           cross-toolchain is x86_64-hosted.
  --tag NAME               Image tag. Default pulseview-builder-<image>:latest
                           (x86_64) or pulseview-builder-<image>-arm64:latest
  --engine docker|podman   Container engine. Default docker.
  --mxe-src PATH           Use an existing local MXE clone instead of
                           cloning the locked canonical source online.
  --save PATH              Also write a `docker save` tarball to PATH.
                           Relative paths resolve against the repo root.
  --pkg-jobs N             MXE package-level parallelism. Default nproc/4.
  --sub-jobs N             MXE per-package parallelism. Default 4.
                           Real load is pkg-jobs * sub-jobs; keep at or
                           under the core count.
  --qt5-freeze             Reproduce upstream's Qt 5.7 freeze (Windows XP).
                           Off by default; this project does not claim XP.
  --glib-version V         Hold glib at version V instead of whatever the
                           pinned MXE carries. Defaults to the Dockerfile's
                           value (2.89.1), the newest that builds glibmm.
  --skip-patch NAME        Exclude one MXE patch by filename. Repeatable.
  --no-sigrok-patches      Exclude all of them; build a plain MXE.
  --no-cache               Rebuild every layer from scratch.
  --dry-run                Stage the context and print the build command
                           without running it.
  -h, --help               This text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

# Never let a git operation block on an interactive prompt. This script runs
# unattended, so a missing key must be an immediate error with a readable
# message, not an ssh process waiting forever on a tty that will never exist.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
export GIT_TERMINAL_PROMPT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --image)              IMAGE="${2:-}"; shift 2 ;;
        --platform)           PLATFORM="${2:-}"; shift 2 ;;
        --tag)                TAG="${2:-}"; shift 2 ;;
        --engine)             ENGINE="${2:-}"; shift 2 ;;
        --mxe-src)            MXE_SRC_LOCAL="${2:-}"; shift 2 ;;
        --glib-version)       GLIB_VERSION="${2:-}"; shift 2 ;;
        --save)               SAVE="${2:-}"; shift 2 ;;
        --pkg-jobs)           PKG_JOBS="${2:-}"; shift 2 ;;
        --sub-jobs)           SUB_JOBS="${2:-}"; shift 2 ;;
        --qt5-freeze)         QT5_FREEZE=1; shift ;;
        --skip-patch)         SKIP_PATCHES="${SKIP_PATCHES} ${2:-}"; shift 2 ;;
        --no-sigrok-patches)  SKIP_PATCHES="mxe_fixes.patch libusb1_upgrade.patch"; shift ;;
        --no-cache)           NO_CACHE=1; shift ;;
        --dry-run)            DRY_RUN=1; shift ;;
        -h|--help)            usage; exit 0 ;;
        *)                    die "unknown option: $1 (try --help)" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    "")  usage; exit 2 ;;
    *)   die "--image must be mingw or appimage, got '${IMAGE}'" ;;
esac

# Resolve the target architecture through the one shared mapping. Accepts
# x86_64/amd64/aarch64/arm64 and the docker linux/<arch> spelling.
ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"
if [ "${IMAGE}" = "mingw" ] && [ "${SR_ARCH}" != "x86_64" ]; then
    die "the mingw cross-toolchain image is x86_64-hosted; --platform ${SR_ARCH} is not a thing for it"
fi
TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = "x86_64" ] || TAG_ARCH_SUFFIX="-arm64"

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

# The lock is TOML, read with tomllib: the prerequisite is an interpreter that
# can import it, not merely one that exists. See 02_Tools/build/python_env.sh.
# shellcheck source=python_env.sh
. "${SCRIPT_DIR}/python_env.sh"
sr_require_python || exit 1
PY="${SR_PYTHON}"

[ -f "${LOCK}" ] || die "lock file missing: ${LOCK}"

# Read one field of one [[source]] or [[artifact]] entry from the lock.
lock_get() {
    "${PY}" - "${LOCK}" "$@" <<'PYEOF'
import sys, tomllib
lock, table, name, field = sys.argv[1:5]
with open(lock, "rb") as fh:
    data = tomllib.load(fh)
for entry in data.get(table, []):
    if entry.get("name") == name:
        value = entry.get(field)
        if value is None:
            sys.exit(f"{table}.{name} has no field '{field}'")
        print(value)
        break
else:
    sys.exit(f"no {table} named '{name}' in the lock")
PYEOF
}

TAG="${TAG:-pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest}"
BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)-${IMAGE}${TAG_ARCH_SUFFIX}"
CONTEXT="${CONTEXT_ROOT}/${IMAGE}${TAG_ARCH_SUFFIX}"
LOG_DIR="${LOG_ROOT}/${BUILD_ID}"
mkdir -p "${CONTEXT}" "${LOG_DIR}"

if [ -z "${PKG_JOBS}" ]; then
    cores="$(nproc 2>/dev/null || echo 4)"
    PKG_JOBS=$(( cores / SUB_JOBS ))
    [ "${PKG_JOBS}" -ge 1 ] || PKG_JOBS=1
fi

BUILD_ARGS=()
printf '=== staging context for %s\n' "${IMAGE}"

CANONICAL_PATCHES=""
if [ "${IMAGE}" = mingw ]; then
    PROFILE_JSON="$("${PY}" "${SCRIPT_DIR}/builder_identity.py" profile \
        --image mingw --platform "${SR_ARCH}" --lock "${LOCK}" \
        --contract "${IMAGES_DIR}/dependencies.mingw.toml" \
        --profile "${IMAGES_DIR}/builder_profile.mingw.toml")"
    mapfile -t PROFILE_VALUES < <("${PY}" -c \
        'import json,sys; p=json.load(sys.stdin); print("1" if p["qt5_freeze"] else "0"); print(p["glib_version"]); print(" ".join(p["include_patches"]))' \
        <<<"${PROFILE_JSON}")
    [ "${PROFILE_VALUES[0]%$'\r'}" = 0 ] || QT5_FREEZE=1
    PROFILE_GLIB="${PROFILE_VALUES[1]%$'\r'}"
    if [ -z "${GLIB_VERSION}" ] && [ "${PROFILE_GLIB}" != dockerfile-default ]; then
        GLIB_VERSION="${PROFILE_GLIB}"
    fi
    CANONICAL_PATCHES="${PROFILE_VALUES[2]%$'\r'}"
fi

# The normalized selected contract is the one source for both Docker package
# installation and later verification. Generated bytes stay in .work.
CONTRACT="${IMAGES_DIR}/dependencies.${IMAGE}.toml"
NORMALIZED_CONTRACT="${CONTEXT}/dependency-contract.json"
DIRECT_PACKAGES="${CONTEXT}/direct-packages.txt"
DEPENDENCY_CONTRACT_SPEC="$("${PY}" "${SCRIPT_DIR}/dependency_contract.py" normalize \
    --contract "${CONTRACT}" --image "${IMAGE}" --platform "${SR_ARCH}" \
    --lock "${LOCK}" --output "${NORMALIZED_CONTRACT}" \
    --packages-output "${DIRECT_PACKAGES}")"
cp "${SCRIPT_DIR}/dependency_contract.py" "${CONTEXT}/dependency_contract.py"
note "dependency contract ${DEPENDENCY_CONTRACT_SPEC:0:12}..."

if [ "${IMAGE}" = "mingw" ]; then
    MXE_COMMIT="$(lock_get source mxe commit)"
    MXE_URL="$(lock_get source mxe canonical_url)"
    note "MXE pin ${MXE_COMMIT:0:12} from ${MXE_URL}"

    # Cloned on the host so the image build itself receives no credentials.
    # The full commit pin is checked before anything enters the context.
    MXE_SRC="${CONTEXT}/mxe"
    if [ -n "${MXE_SRC_LOCAL}" ]; then
        # Escape hatch for an offline host or an existing approved clone.
        # Git hardlinks local objects where possible, so this is cheap.
        [ -d "${MXE_SRC_LOCAL}/.git" ] \
            || die "--mxe-src ${MXE_SRC_LOCAL} is not a git clone"
        note "using local MXE clone ${MXE_SRC_LOCAL}"
        rm -rf "${MXE_SRC}"
        git clone "${MXE_SRC_LOCAL}" "${MXE_SRC}"
    elif [ -d "${MXE_SRC}/.git" ]; then
        note "updating existing MXE clone"
        git -C "${MXE_SRC}" remote set-url origin "${MXE_URL}"
        git -C "${MXE_SRC}" fetch --prune origin
    else
        # Probe first. A clone that fails on credentials halfway through
        # leaves a partial tree and a confusing error; ls-remote fails in a
        # second and lets us say something useful.
        note "checking access to ${MXE_URL}"
        if ! git ls-remote --heads "${MXE_URL}" >/dev/null 2>"${LOG_DIR}/ls-remote.err"; then
            printf 'error: cannot reach the canonical MXE source.\n\n' >&2
            sed 's/^/  /' "${LOG_DIR}/ls-remote.err" >&2
            cat >&2 <<EOF

  The local rebuild fallback needs internet access to the URL recorded in
  upstreams.lock.toml. Restore connectivity and retry, or clone the pinned MXE
  source somewhere already reachable and point at it:

         ./build_image.sh --image mingw --mxe-src /path/to/mxe
EOF
            exit 1
        fi
        note "cloning MXE (full clone; the pin must be verifiable)"
        rm -rf "${MXE_SRC}"
        git clone "${MXE_URL}" "${MXE_SRC}"
    fi
    git -C "${MXE_SRC}" checkout --detach "${MXE_COMMIT}"
    git -C "${MXE_SRC}" rev-parse HEAD >"${LOG_DIR}/mxe.commit"
    git -C "${MXE_SRC}" status --porcelain --untracked-files=all \
        --ignored=matching >"${LOG_DIR}/mxe.worktree-status"
    if [ -s "${LOG_DIR}/mxe.worktree-status" ]; then
        printf 'error: cached MXE source contains files outside the pinned commit:\n' >&2
        sed 's/^/  /' "${LOG_DIR}/mxe.worktree-status" >&2
        die "remove the cached context or use --mxe-src with a clean clone"
    fi

    # sigrok-util's MXE patches, taken from the pinned submodule. They are
    # checked against the actual clone rather than assumed: they are pinned
    # against an older MXE and have not aged equally. A patch that does not
    # apply is an error here, where it costs a second, instead of a failure
    # partway through a multi-hour image build.
    PATCH_SRC="${REPO_ROOT}/05_Software/sigrok-util/cross-compile/mingw"
    [ -d "${PATCH_SRC}" ] \
        || die "sigrok-util submodule not checked out at ${PATCH_SRC}"
    rm -rf "${CONTEXT}/patches"
    mkdir -p "${CONTEXT}/patches"

    MXE_PATCHES=""
    for p in mxe_fixes.patch libusb1_upgrade.patch; do
        case " ${CANONICAL_PATCHES} " in
            *" ${p} "*) ;;
            *) continue ;;
        esac
        skipped=0
        for s in ${SKIP_PATCHES}; do
            [ "${s}" = "${p}" ] && skipped=1
        done
        if [ "${skipped}" -eq 1 ]; then
            note "patch ${p}: skipped by request"
            continue
        fi
        [ -f "${PATCH_SRC}/${p}" ] || die "missing patch: ${PATCH_SRC}/${p}"
        if git -C "${MXE_SRC}" apply --check "${PATCH_SRC}/${p}" 2>"${LOG_DIR}/${p}.err"; then
            cp "${PATCH_SRC}/${p}" "${CONTEXT}/patches/${p}"
            MXE_PATCHES="${MXE_PATCHES}${MXE_PATCHES:+ }${p}"
            note "patch ${p}: applies"
        else
            printf 'error: patch %s does not apply to MXE %s\n\n' \
                "${p}" "${MXE_COMMIT:0:12}" >&2
            sed 's/^/  /' "${LOG_DIR}/${p}.err" >&2
            cat >&2 <<EOF

  These patches are pinned against an older MXE than the one in the lock.
  Decide deliberately, then re-run:

    --skip-patch ${p}    exclude just this one
    --no-sigrok-patches  build a plain MXE

  Record the decision; a skipped patch is a toolchain difference from
  upstream sigrok's own release build (planning doc 09, R-20).
EOF
            exit 1
        fi
    done
    note "MXE patches to apply: ${MXE_PATCHES:-none}"

    # The Windows Python that libsigrokdecode embeds. Taken from the lock so
    # the version, URL and digest live in exactly one place; the Dockerfile
    # bakes these into /opt/sigrok-deps and build_windows_mxe.sh consumes
    # them from there without touching the network.
    PY_VERSION="$(lock_get artifact cpython-windows-embed version)"
    PY_EMBED_URL="$(lock_get artifact cpython-windows-embed url)"
    PY_EMBED_SHA256="$(lock_get artifact cpython-windows-embed sha256)"
    PY_SRC_URL="$(lock_get artifact cpython-source url)"
    PY_SRC_SHA256="$(lock_get artifact cpython-source sha256)"
    PY_SRC_VERSION="$(lock_get artifact cpython-source version)"
    [ "${PY_VERSION}" = "${PY_SRC_VERSION}" ] || die \
        "lock mismatch: cpython-windows-embed is ${PY_VERSION} but
  cpython-source is ${PY_SRC_VERSION}. The headers must come from the same
  release as the runtime, or libsigrokdecode compiles against one CPython
  and links against another."
    note "windows python ${PY_VERSION} sha256 ${PY_EMBED_SHA256:0:12}..."

    BASE_IMAGE="$(lock_get artifact builder-base-debian-bookworm-slim url)"
    BASE_IMAGE="${BASE_IMAGE#docker://}"
    BUILD_ARGS+=(
        --build-arg "MXE_COMMIT=${MXE_COMMIT}"
        --build-arg "MXE_QT5_FREEZE=${QT5_FREEZE}"
        --build-arg "MXE_PATCHES=${MXE_PATCHES}"
        --build-arg "PKG_JOBS=${PKG_JOBS}"
        --build-arg "SUB_JOBS=${SUB_JOBS}"
        --build-arg "PY_VERSION=${PY_VERSION}"
        --build-arg "PY_EMBED_URL=${PY_EMBED_URL}"
        --build-arg "PY_EMBED_SHA256=${PY_EMBED_SHA256}"
        --build-arg "PY_SRC_URL=${PY_SRC_URL}"
        --build-arg "PY_SRC_SHA256=${PY_SRC_SHA256}"
    )
    if [ -n "${GLIB_VERSION}" ]; then
        BUILD_ARGS+=(--build-arg "MXE_GLIB_VERSION=${GLIB_VERSION}")
        note "glib held at ${GLIB_VERSION}"
    fi
    note "parallelism ${PKG_JOBS} packages x ${SUB_JOBS} jobs"
else
    # Same three tools on both architectures - appimagetool, linuxdeployqt,
    # and the type-2 AppImage runtime appimagetool would otherwise fetch
    # from the network at packaging time. Only the lock entry names differ
    # by architecture; URLs come from the lock too, so the file names live
    # in exactly one place.
    if [ "${SR_ARCH}" = "x86_64" ]; then
        AIT_LOCK="appimagetool"
        LDQT_LOCK="linuxdeployqt"
    else
        AIT_LOCK="appimagetool-aarch64"
        LDQT_LOCK="linuxdeployqt-aarch64"
    fi
    RUNTIME_LOCK="appimage-runtime-${SR_ARCH}"
    AIT_VERSION="$(lock_get artifact "${AIT_LOCK}" version)"
    AIT_URL="$(lock_get artifact "${AIT_LOCK}" url)"
    AIT_SHA256="$(lock_get artifact "${AIT_LOCK}" sha256)"
    LDQT_VERSION="$(lock_get artifact "${LDQT_LOCK}" version)"
    LDQT_URL="$(lock_get artifact "${LDQT_LOCK}" url)"
    LDQT_SHA256="$(lock_get artifact "${LDQT_LOCK}" sha256)"
    RUNTIME_VERSION="$(lock_get artifact "${RUNTIME_LOCK}" version)"
    RUNTIME_URL="$(lock_get artifact "${RUNTIME_LOCK}" url)"
    RUNTIME_SHA256="$(lock_get artifact "${RUNTIME_LOCK}" sha256)"
    note "${AIT_LOCK} ${AIT_VERSION} sha256 ${AIT_SHA256:0:12}..."
    note "${LDQT_LOCK} ${LDQT_VERSION} sha256 ${LDQT_SHA256:0:12}..."
    note "${RUNTIME_LOCK} ${RUNTIME_VERSION} sha256 ${RUNTIME_SHA256:0:12}..."
    BASE_IMAGE="$(lock_get artifact builder-base-ubuntu-22.04 url)"
    BASE_IMAGE="${BASE_IMAGE#docker://}"
    BUILD_ARGS+=(
        --build-arg "APPIMAGETOOL_VERSION=${AIT_VERSION}"
        --build-arg "APPIMAGETOOL_URL=${AIT_URL}"
        --build-arg "APPIMAGETOOL_SHA256=${AIT_SHA256}"
        --build-arg "LINUXDEPLOYQT_VERSION=${LDQT_VERSION}"
        --build-arg "LINUXDEPLOYQT_URL=${LDQT_URL}"
        --build-arg "LINUXDEPLOYQT_SHA256=${LDQT_SHA256}"
        --build-arg "APPIMAGE_RUNTIME_VERSION=${RUNTIME_VERSION}"
        --build-arg "APPIMAGE_RUNTIME_URL=${RUNTIME_URL}"
        --build-arg "APPIMAGE_RUNTIME_SHA256=${RUNTIME_SHA256}"
    )
fi

# A locally rebuilt image has a different image ID from the saved archive, but
# it must still be recognizable as the exact recipe in this checkout. This
# content hash excludes host UID/GID and all generated build output.
#
# The effective options go in too, not just the files: --skip-patch,
# --qt5-freeze and --glib-version each produce a materially different image
# from the same Dockerfile, so an identity blind to them would label them
# identically. Anything passed here must match what this run actually builds.
SPEC_ARGS=(--image "${IMAGE}" --platform "${SR_ARCH}")
if [ "${IMAGE}" = "mingw" ]; then
    if [ "${QT5_FREEZE}" -eq 1 ]; then SPEC_ARGS+=(--qt5-freeze); fi
    if [ -n "${GLIB_VERSION}" ]; then
        SPEC_ARGS+=(--glib-version "${GLIB_VERSION}")
    fi
    for skipped_patch in ${SKIP_PATCHES}; do
        SPEC_ARGS+=(--skip-patch "${skipped_patch}")
    done
fi
BUILDER_SPEC="$(bash "${SCRIPT_DIR}/builder_spec.sh" "${SPEC_ARGS[@]}")"
BUILD_ARGS+=(
    --build-arg "BUILDER_SPEC=${BUILDER_SPEC}"
    --build-arg "DEPENDENCY_CONTRACT_SPEC=${DEPENDENCY_CONTRACT_SPEC}"
)
note "builder recipe ${BUILDER_SPEC:0:12}..."

cp "${IMAGES_DIR}/Dockerfile.${IMAGE}" "${CONTEXT}/Dockerfile"
if [ "${IMAGE}" = "mingw" ]; then
    for helper in mxe-build.sh mxe-glib-hold.sh; do
        cp "${IMAGES_DIR}/${helper}" "${CONTEXT}/${helper}"
    done
fi

# Base references come from the lock and normally already contain a digest.
# Pull and inspect them anyway so a malformed or unavailable pin fails before
# the multi-hour build starts and the provenance record names the exact bytes.
printf '=== verifying base image\n'
if [ "${DRY_RUN}" -eq 0 ]; then
    "${ENGINE}" pull --platform "${SR_DOCKER_PLATFORM}" "${BASE_IMAGE}" >/dev/null
    BASE_PINNED="$("${ENGINE}" image inspect --format '{{index .RepoDigests 0}}' \
        "${BASE_IMAGE}" 2>/dev/null || true)"
else
    BASE_PINNED=""
fi
if [ -n "${BASE_PINNED}" ]; then
    note "${BASE_PINNED}"
else
    case "${BASE_IMAGE}" in
        *@sha256:*)
            BASE_PINNED="${BASE_IMAGE}"
            note "${BASE_PINNED} (locked; not pulled in dry run)"
            ;;
        *) die "base image has no resolvable digest: ${BASE_IMAGE}" ;;
    esac
fi

BUILD_ARGS+=(
    --build-arg "BASE_IMAGE=${BASE_PINNED}"
    --build-arg "USER_UID=$(id -u)"
    --build-arg "USER_GID=$(id -g)"
)
[ "${NO_CACHE}" -eq 1 ] && BUILD_ARGS+=(--no-cache)

CONTENT_TAG="${TAG}-content-${BUILD_ID}"
CMD=("${ENGINE}" build --platform "${SR_DOCKER_PLATFORM}" \
    --tag "${CONTENT_TAG}" "${BUILD_ARGS[@]}" "${CONTEXT}")

printf '=== build content image\n'
printf '  %q' "${CMD[@]}"; printf '\n'

if [ "${DRY_RUN}" -eq 1 ]; then
    printf '=== finalize lifecycle metadata\n'
    printf '  content tag: %s\n' "${CONTENT_TAG}"
    printf '  final tag:   %s\n' "${TAG}"
    printf '\ndry run: context staged at %s, nothing built\n' "${CONTEXT}"
    exit 0
fi

CONTAINER_NAME=""
cleanup_candidate_build() {
    [ -z "${CONTAINER_NAME}" ] \
        || "${ENGINE}" rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    "${ENGINE}" image rm "${CONTENT_TAG}" >/dev/null 2>&1 || true
}
trap cleanup_candidate_build EXIT

"${CMD[@]}" 2>&1 | tee "${LOG_DIR}/build-content.log"

# Read metadata without executing the target architecture. This keeps arm64
# image finalization usable on amd64 hosts without relying on emulation.
CONTAINER_NAME="pulseview-builder-metadata-${BUILD_ID//[^A-Za-z0-9_.-]/-}"
"${ENGINE}" create --name "${CONTAINER_NAME}" "${CONTENT_TAG}" >/dev/null
"${ENGINE}" cp \
    "${CONTAINER_NAME}:/usr/local/share/pulseview-builder/dependency-contract.json" \
    "${LOG_DIR}/dependency-contract.json"
"${ENGINE}" cp \
    "${CONTAINER_NAME}:/usr/local/share/pulseview-builder/resolved-inventory.json" \
    "${LOG_DIR}/resolved-inventory.json"
"${ENGINE}" rm -f "${CONTAINER_NAME}" >/dev/null
CONTAINER_NAME=""

EMBEDDED_CONTRACT_SHA="$(sha256sum "${LOG_DIR}/dependency-contract.json" | cut -d' ' -f1)"
INVENTORY_SHA="$(sha256sum "${LOG_DIR}/resolved-inventory.json" | cut -d' ' -f1)"
[ "${EMBEDDED_CONTRACT_SHA}" = "${DEPENDENCY_CONTRACT_SPEC}" ] || die \
    "built image contract hash ${EMBEDDED_CONTRACT_SHA} does not match selected contract ${DEPENDENCY_CONTRACT_SPEC}"
note "resolved inventory ${INVENTORY_SHA:0:12}..."

METADATA_CONTEXT="${CONTEXT}/metadata-finalization"
mkdir -p "${METADATA_CONTEXT}"
cp "${IMAGES_DIR}/Dockerfile.builder-metadata" "${METADATA_CONTEXT}/Dockerfile"
METADATA_CMD=(
    "${ENGINE}" build --platform "${SR_DOCKER_PLATFORM}"
    --tag "${TAG}"
    --build-arg "BASE_IMAGE=${CONTENT_TAG}"
    --build-arg "BUILDER_IMAGE=${IMAGE}"
    --build-arg "BUILDER_RECIPE_SPEC=${BUILDER_SPEC}"
    --build-arg "DEPENDENCY_CONTRACT_SPEC=${DEPENDENCY_CONTRACT_SPEC}"
    --build-arg "NORMALIZED_CONTRACT_SHA256=${EMBEDDED_CONTRACT_SHA}"
    --build-arg "RESOLVED_INVENTORY_SHA256=${INVENTORY_SHA}"
    "${METADATA_CONTEXT}"
)
printf '=== finalize lifecycle metadata\n'
printf '  %q' "${METADATA_CMD[@]}"; printf '\n'
"${METADATA_CMD[@]}" 2>&1 | tee "${LOG_DIR}/build-metadata.log"
"${ENGINE}" image rm "${CONTENT_TAG}" >/dev/null 2>&1 || true
trap - EXIT

IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${TAG}")"

{
    printf 'build_id     %s\n' "${BUILD_ID}"
    printf 'image        %s\n' "${IMAGE}"
    printf 'tag          %s\n' "${TAG}"
    printf 'image_id     %s\n' "${IMAGE_ID}"
    printf 'base         %s\n' "${BASE_PINNED}"
    printf 'engine       %s (%s)\n' "${ENGINE}" "$("${ENGINE}" --version)"
    printf 'platform     %s\n' "${SR_DOCKER_PLATFORM}"
    printf 'builder_spec %s\n' "${BUILDER_SPEC}"
    printf 'contract     %s\n' "${DEPENDENCY_CONTRACT_SPEC}"
    printf 'inventory    %s\n' "${INVENTORY_SHA}"
    printf 'host         %s\n' "$(uname -srm)"
    if [ "${IMAGE}" = "mingw" ]; then
        printf 'mxe_commit   %s\n' "${MXE_COMMIT}"
        printf 'qt5_freeze   %s\n' "${QT5_FREEZE}"
        printf 'mxe_patches  %s\n' "${MXE_PATCHES:-none}"
        printf 'glib_hold    %s\n' "${GLIB_VERSION:-2.89.1 (Dockerfile default)}"
        printf 'python       %s\n' "${PY_VERSION}"
        printf 'python_sha   %s\n' "${PY_EMBED_SHA256}"
    else
        printf 'appimagetool %s\n' "${AIT_VERSION}"
    fi
} | tee "${LOG_DIR}/record.txt"

if [ -n "${SAVE}" ]; then
    case "${SAVE}" in
        /*) SAVE_PATH="${SAVE}" ;;
        *)  SAVE_PATH="${REPO_ROOT}/${SAVE}" ;;
    esac
    mkdir -p "$(dirname -- "${SAVE_PATH}")"
    printf '=== saving image to %s\n' "${SAVE_PATH}"
    printf '    this is the offline archive; it is large and slow to write\n'
    "${ENGINE}" save --output "${SAVE_PATH}" "${TAG}"
    ( cd "$(dirname -- "${SAVE_PATH}")" \
        && sha256sum "$(basename -- "${SAVE_PATH}")" \
        > "$(basename -- "${SAVE_PATH}").sha256" )
    note "$(du -h "${SAVE_PATH}" | cut -f1) written"
fi

printf '\ndone: %s\n' "${TAG}"
printf 'record: %s\n' "${LOG_DIR}/record.txt"

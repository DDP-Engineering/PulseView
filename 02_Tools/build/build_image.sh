#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"
IMAGES_DIR="${SCRIPT_DIR}/images"
CONTEXT_ROOT="${REPO_ROOT}/.work/build-context"
LOG_ROOT="${REPO_ROOT}/.work/logs"

IMAGE=""
TAG=""
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
  --tag NAME               Image tag. Default hantek-builder-<image>:latest
  --engine docker|podman   Container engine. Default docker.
  --mxe-src PATH           Use an existing local MXE clone instead of
                           cloning from Gitea. For hosts without SSH
                           access to the mirror.
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

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

PY="$(command -v python3 || command -v python)" \
    || die "python3 is required to read the lock file"

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

TAG="${TAG:-hantek-builder-${IMAGE}:latest}"
BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)-${IMAGE}"
CONTEXT="${CONTEXT_ROOT}/${IMAGE}"
LOG_DIR="${LOG_ROOT}/${BUILD_ID}"
mkdir -p "${CONTEXT}" "${LOG_DIR}"

if [ -z "${PKG_JOBS}" ]; then
    cores="$(nproc 2>/dev/null || echo 4)"
    PKG_JOBS=$(( cores / SUB_JOBS ))
    [ "${PKG_JOBS}" -ge 1 ] || PKG_JOBS=1
fi

BUILD_ARGS=()
printf '=== staging context for %s\n' "${IMAGE}"

if [ "${IMAGE}" = "mingw" ]; then
    MXE_COMMIT="$(lock_get source mxe commit)"
    MXE_URL="$(lock_get source mxe fork_url)"
    note "MXE pin ${MXE_COMMIT:0:12} from ${MXE_URL}"

    # Cloned on the host so the image never needs credentials or a route to
    # github.com. Uses your existing SSH access to Gitea.
    MXE_SRC="${CONTEXT}/mxe"
    if [ -n "${MXE_SRC_LOCAL}" ]; then
        # Escape hatch for a host that cannot reach Gitea. Clone from a local
        # path instead; git hardlinks the objects, so this is cheap.
        [ -d "${MXE_SRC_LOCAL}/.git" ] \
            || die "--mxe-src ${MXE_SRC_LOCAL} is not a git clone"
        note "using local MXE clone ${MXE_SRC_LOCAL}"
        rm -rf "${MXE_SRC}"
        git clone "${MXE_SRC_LOCAL}" "${MXE_SRC}"
    elif [ -d "${MXE_SRC}/.git" ]; then
        note "updating existing MXE clone"
        git -C "${MXE_SRC}" fetch --prune origin
    else
        # Probe first. A clone that fails on credentials halfway through
        # leaves a partial tree and a confusing error; ls-remote fails in a
        # second and lets us say something useful.
        note "checking access to ${MXE_URL}"
        if ! git ls-remote --heads "${MXE_URL}" >/dev/null 2>"${LOG_DIR}/ls-remote.err"; then
            printf 'error: cannot reach the MXE mirror as this user.\n\n' >&2
            sed 's/^/  /' "${LOG_DIR}/ls-remote.err" >&2
            cat >&2 <<EOF

  This host has no usable SSH identity for the Gitea server. Note that WSL
  has its own home directory: keys set up under Windows are not visible here.

  Fix it in one of these ways, then re-run:

    1. Give this host its own key (recommended):
         ssh-keygen -t ed25519 -C "\$(whoami)@\$(hostname) hantek build"
         cat ~/.ssh/id_ed25519.pub
       then add that public key to Gitea under Settings -> SSH Keys.

    2. Clone MXE wherever you already have access, and point at it:
         ./build_image.sh --image mingw --mxe-src /path/to/mxe

  Do not copy a private key between hosts to work around this.
EOF
            exit 1
        fi
        note "cloning MXE (full clone; the pin must be verifiable)"
        rm -rf "${MXE_SRC}"
        git clone "${MXE_URL}" "${MXE_SRC}"
    fi
    git -C "${MXE_SRC}" checkout --detach "${MXE_COMMIT}"
    git -C "${MXE_SRC}" rev-parse HEAD >"${LOG_DIR}/mxe.commit"

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

    BASE_IMAGE="debian:bookworm-slim"
    BUILD_ARGS+=(
        --build-arg "MXE_COMMIT=${MXE_COMMIT}"
        --build-arg "MXE_QT5_FREEZE=${QT5_FREEZE}"
        --build-arg "MXE_PATCHES=${MXE_PATCHES}"
        --build-arg "PKG_JOBS=${PKG_JOBS}"
        --build-arg "SUB_JOBS=${SUB_JOBS}"
    )
    if [ -n "${GLIB_VERSION}" ]; then
        BUILD_ARGS+=(--build-arg "MXE_GLIB_VERSION=${GLIB_VERSION}")
        note "glib held at ${GLIB_VERSION}"
    fi
    note "parallelism ${PKG_JOBS} packages x ${SUB_JOBS} jobs"
else
    AIT_VERSION="$(lock_get artifact appimagetool version)"
    AIT_SHA256="$(lock_get artifact appimagetool sha256)"
    note "appimagetool ${AIT_VERSION} sha256 ${AIT_SHA256:0:12}..."
    BASE_IMAGE="ubuntu:22.04"
    BUILD_ARGS+=(
        --build-arg "APPIMAGETOOL_VERSION=${AIT_VERSION}"
        --build-arg "APPIMAGETOOL_SHA256=${AIT_SHA256}"
    )
fi

cp "${IMAGES_DIR}/Dockerfile.${IMAGE}" "${CONTEXT}/Dockerfile"
if [ "${IMAGE}" = "mingw" ]; then
    for helper in mxe-build.sh mxe-glib-hold.sh; do
        cp "${IMAGES_DIR}/${helper}" "${CONTEXT}/${helper}"
    done
fi

# Pin the base by digest rather than tag, so a rebuild months from now starts
# from the same bytes. The tag is only used to discover the digest.
printf '=== resolving base image\n'
if [ "${DRY_RUN}" -eq 0 ]; then
    "${ENGINE}" pull "${BASE_IMAGE}" >/dev/null
    BASE_PINNED="$("${ENGINE}" image inspect --format '{{index .RepoDigests 0}}' \
        "${BASE_IMAGE}" 2>/dev/null || true)"
else
    BASE_PINNED=""
fi
if [ -n "${BASE_PINNED}" ]; then
    note "${BASE_PINNED}"
else
    BASE_PINNED="${BASE_IMAGE}"
    note "digest unresolved, falling back to tag ${BASE_IMAGE}"
fi

BUILD_ARGS+=(
    --build-arg "BASE_IMAGE=${BASE_PINNED}"
    --build-arg "USER_UID=$(id -u)"
    --build-arg "USER_GID=$(id -g)"
)
[ "${NO_CACHE}" -eq 1 ] && BUILD_ARGS+=(--no-cache)

CMD=("${ENGINE}" build --tag "${TAG}" "${BUILD_ARGS[@]}" "${CONTEXT}")

printf '=== build\n'
printf '  %q' "${CMD[@]}"; printf '\n'

if [ "${DRY_RUN}" -eq 1 ]; then
    printf '\ndry run: context staged at %s, nothing built\n' "${CONTEXT}"
    exit 0
fi

"${CMD[@]}" 2>&1 | tee "${LOG_DIR}/build.log"

IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${TAG}")"

{
    printf 'build_id     %s\n' "${BUILD_ID}"
    printf 'image        %s\n' "${IMAGE}"
    printf 'tag          %s\n' "${TAG}"
    printf 'image_id     %s\n' "${IMAGE_ID}"
    printf 'base         %s\n' "${BASE_PINNED}"
    printf 'engine       %s (%s)\n' "${ENGINE}" "$("${ENGINE}" --version)"
    printf 'host         %s\n' "$(uname -srm)"
    if [ "${IMAGE}" = "mingw" ]; then
        printf 'mxe_commit   %s\n' "${MXE_COMMIT}"
        printf 'qt5_freeze   %s\n' "${QT5_FREEZE}"
        printf 'mxe_patches  %s\n' "${MXE_PATCHES:-none}"
        printf 'glib_hold    %s\n' "${GLIB_VERSION:-2.89.1 (Dockerfile default)}"
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

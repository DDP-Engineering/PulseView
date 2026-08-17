#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Run a command inside a builder image - the entry point for stage 2.
#
# Mounts, and why each is what it is:
#
#   /work    the repository, read-write. autotools regenerates configure
#            inside the source tree, so this cannot be read-only.
#   /build   a named container volume for out-of-tree build trees. This is
#            deliberately NOT on /mnt/f: the Windows drive reaches WSL over
#            9p, which is slow enough to dominate a compile. Keep object
#            files here and the build is several times faster.
#   /out     07_Delivery, read-write. The only place finished artifacts go.
#
# Without a command it drops you in an interactive shell.
#
#   ./run_in_builder.sh --image mingw
#   ./run_in_builder.sh --image mingw -- bash -c 'x86_64-w64-mingw32.static.posix-gcc --version'

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="mingw"
TAG=""
ENGINE="${BUILDER_ENGINE:-docker}"
VOLUME=""
KEEP=0
OFFLINE=0

usage() {
    cat <<'EOF'
Run a command inside a sigrok builder image.

Options:
  --image mingw|appimage   Which builder to use. Default mingw.
  --tag NAME               Override the image tag.
  --engine docker|podman   Container engine. Default docker.
  --volume NAME            Named volume for /build.
                           Default hantek-build-<image>.
  --keep-volume            Do not warn about stale build state.
  --offline                Run with no network at all (--network none).
                           The point of the saved image is that a build needs
                           nothing external; this is how that gets proven
                           rather than asserted.
  -h, --help               This text.
  -- CMD...                Command to run. Default: interactive bash.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

CMD=()
while [ $# -gt 0 ]; do
    case "$1" in
        --image)        IMAGE="${2:-}"; shift 2 ;;
        --tag)          TAG="${2:-}"; shift 2 ;;
        --engine)       ENGINE="${2:-}"; shift 2 ;;
        --volume)       VOLUME="${2:-}"; shift 2 ;;
        --keep-volume)  KEEP=1; shift ;;
        --offline)      OFFLINE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        --)             shift; CMD=("$@"); break ;;
        *)              die "unknown option: $1 (try --help)" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage, got '${IMAGE}'" ;;
esac

TAG="${TAG:-hantek-builder-${IMAGE}:latest}"
VOLUME="${VOLUME:-hantek-build-${IMAGE}}"

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

"${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1 \
    || die "image ${TAG} not found. Build it first: ./build_image.sh --image ${IMAGE}"

DELIVERY="${REPO_ROOT}/07_Delivery"
mkdir -p "${DELIVERY}/staging"

RUN_ARGS=(
    --rm
    --init
    --volume "${REPO_ROOT}:/work"
    --volume "${VOLUME}:/build"
    --volume "${DELIVERY}:/out"
    --workdir /work
    --env "BUILD_DIR=/build"
    --env "DELIVERY_DIR=/out"
    --env "REPO_DIR=/work"
)

# Expecting a build not to use the network is not the same as denying it one.
# Only the second one finds the download nobody remembered was there.
if [ "${OFFLINE}" -eq 1 ]; then
    RUN_ARGS+=(--network none)
    printf 'note: running with no network\n' >&2
fi

# An interactive shell needs a TTY; a scripted command must not demand one,
# so that this works unchanged from CI or a non-interactive invocation.
if [ "${#CMD[@]}" -eq 0 ]; then
    CMD=(/bin/bash)
    RUN_ARGS+=(--interactive --tty)
elif [ -t 0 ] && [ -t 1 ]; then
    RUN_ARGS+=(--tty)
fi

if [ "${KEEP}" -eq 0 ] \
   && "${ENGINE}" volume inspect "${VOLUME}" >/dev/null 2>&1; then
    printf 'note: reusing build volume %s; remove it with\n' "${VOLUME}" >&2
    printf '      %s volume rm %s   if you want a clean tree\n' \
        "${ENGINE}" "${VOLUME}" >&2
fi

exec "${ENGINE}" run "${RUN_ARGS[@]}" "${TAG}" "${CMD[@]}"

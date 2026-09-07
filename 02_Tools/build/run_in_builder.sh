#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
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
#   bash 02_Tools/build/run_in_builder.sh --image mingw
#   bash 02_Tools/build/run_in_builder.sh --image mingw -- \
#       bash -c 'x86_64-w64-mingw32.static.posix-gcc --version'

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="mingw"
TAG="${BUILDER_TAG:-}"
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
VOLUME="${BUILDER_VOLUME:-}"
KEEP=0
OFFLINE=0

usage() {
    cat <<'EOF'
Run a command inside a sigrok builder image.

Options:
  --image mingw|appimage   Which builder to use. Default mingw.
  --platform ARCH          Target architecture: x86_64 or aarch64/arm64
                           (linux/<arch> also accepted). Default: the host.
                           Non-x86_64 selects the arch-suffixed image tag
                           and volume, and runs the container emulated on
                           an x86_64 host (needs qemu binfmt).
  --tag NAME               Override the image tag.
  --engine docker|podman   Container engine. Default docker.
  --volume NAME            Named volume for /build.
                           Default pulseview-build-<image> plus the arch
                           suffix for non-x86_64.
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
        --platform)     PLATFORM="${2:-}"; shift 2 ;;
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

# One shared mapping resolves the architecture and its docker platform
# string; the image tag and build volume get an arch suffix so an arm64
# build can never poison the x86_64 build tree or vice versa.
ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"
TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = "x86_64" ] || TAG_ARCH_SUFFIX="-arm64"

TAG="${TAG:-pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest}"
VOLUME="${VOLUME:-pulseview-build-${IMAGE}${TAG_ARCH_SUFFIX}}"

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

"${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1 \
    || die "image ${TAG} not found. Prepare it first:
  bash 02_Tools/bootstrap/ensure_build_environment.sh --image ${IMAGE} --platform ${SR_ARCH}"

DELIVERY="${BUILDER_OUTPUT_DIR:-${REPO_ROOT}/07_Delivery}"
case "${DELIVERY}" in
    /*) ;;
    *) die "builder output directory must be absolute: ${DELIVERY}" ;;
esac
mkdir -p "${DELIVERY}/staging"

RUN_ARGS=(
    --rm
    --init
    --platform "${SR_DOCKER_PLATFORM}"
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

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Load the saved builder image, so a fresh clone does not have to rebuild it.
#
# This is the reason the archive exists. Building the toolchain from source
# takes hours and downloads MXE's upstream tarballs from 117 distinct hosts,
# every one of which is free to disappear. Loading the archive takes about a
# minute and reaches no network at all.
#
#   bash 02_Tools/build/load_image.sh                  load the mingw toolchain
#   bash 02_Tools/build/load_image.sh --image appimage
#
# The archive is carried by Git LFS. A clone made without LFS installed gets
# a ~130 byte pointer file instead of a 2.2 GB tarball; this script detects
# that and says so, rather than letting `docker load` fail obscurely.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="mingw"
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
ARCHIVE=""
ARCHIVE_EXPLICIT=0
FORCE=0
ALLOW_LEGACY=0
ALLOW_HISTORICAL=0

usage() {
    cat <<'EOF'
Load a saved builder image from 07_Delivery/toolchain/.

Options:
  --image mingw|appimage   Which toolchain. Default mingw.
  --platform ARCH          Target architecture: x86_64 or aarch64/arm64.
                           Default x86_64. Non-x86_64 selects the
                           arch-suffixed archive and image tag, matching
                           what build_image.sh --platform produces.
  --archive PATH           Load this file instead of the default location.
  --engine docker|podman   Container engine. Default docker.
  --force                  Load even if an image with that tag exists.
  --allow-legacy-restore   Explicit schema-1 migration restore.
  --allow-historical-builder
                           Explicit stale schema-2 verification and restore.
  -h, --help               This text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)    IMAGE="${2:-}"; shift 2 ;;
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --archive)  ARCHIVE="${2:-}"; ARCHIVE_EXPLICIT=1; shift 2 ;;
        --engine)   ENGINE="${2:-}"; shift 2 ;;
        --force)    FORCE=1; shift ;;
        --allow-legacy-restore) ALLOW_LEGACY=1; shift ;;
        --allow-historical-builder) ALLOW_HISTORICAL=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage, got '${IMAGE}'" ;;
esac

# Same arch-suffix convention as build_image.sh and run_in_builder.sh, from
# the same shared mapping. The default is x86_64 rather than the host so an
# arm64 machine loading the x86_64 archive by habit is not surprised.
ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="x86_64"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"
if [ "${IMAGE}" = "mingw" ] && [ "${SR_ARCH}" != "x86_64" ]; then
    die "the mingw cross-toolchain image is x86_64-hosted; --platform ${SR_ARCH} is not a thing for it"
fi
TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = "x86_64" ] || TAG_ARCH_SUFFIX="-arm64"

TAG="pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest"
ARCHIVE="${ARCHIVE:-${REPO_ROOT}/07_Delivery/toolchain/pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}.tar}"
MANIFEST="${REPO_ROOT}/07_Delivery/toolchain/pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}.manifest.toml"

# Multipart manifests are the current format. Always delegate normal loading
# to the shared selector, even if delivery files are absent: a current local
# image is intentionally sufficient on its own. Keep the single-tar path below
# only for explicit --archive compatibility.
if [ "${ARCHIVE_EXPLICIT}" -eq 0 ]; then
    ENSURE_ARGS=(--image "${IMAGE}" --platform "${SR_ARCH}" \
        --engine "${ENGINE}" --manifest "${MANIFEST}" --no-rebuild)
    [ "${FORCE}" -eq 1 ] && ENSURE_ARGS+=(--force-restore)
    [ "${ALLOW_LEGACY}" -eq 1 ] && ENSURE_ARGS+=(--allow-legacy-restore)
    [ "${ALLOW_HISTORICAL}" -eq 1 ] && ENSURE_ARGS+=(--allow-historical-builder)
    exec bash "${REPO_ROOT}/02_Tools/bootstrap/ensure_build_environment.sh" \
        "${ENSURE_ARGS[@]}"
fi

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

if [ "${FORCE}" -eq 0 ] && "${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1; then
    note "${TAG} already present; nothing to do (--force to reload)"
    exit 0
fi

[ -f "${ARCHIVE}" ] || die "archive not found: ${ARCHIVE}
  Either this clone predates the archive, or it was never generated.
  Build the toolchain instead: bash 02_Tools/build/build_image.sh --image ${IMAGE}"

# An unsmudged LFS pointer is a small text file beginning with a version line.
# Detecting it here turns a baffling 'unexpected EOF' from docker load into an
# actionable message.
SIZE="$(wc -c < "${ARCHIVE}")"
if [ "${SIZE}" -lt 1048576 ]; then
    if head -1 "${ARCHIVE}" | grep -q '^version https://git-lfs'; then
        die "${ARCHIVE} is a Git LFS pointer, not the archive itself (${SIZE} bytes).
  This clone was made without Git LFS. Install it and fetch the real file:
    git lfs install
    git lfs pull"
    fi
    die "${ARCHIVE} is only ${SIZE} bytes; it is not a container image archive."
fi

SUMFILE="${ARCHIVE}.sha256"
if [ -f "${SUMFILE}" ]; then
    note "verifying checksum"
    ( cd "$(dirname -- "${ARCHIVE}")" && sha256sum --check --status \
        "$(basename -- "${SUMFILE}")" ) \
        || die "checksum mismatch for ${ARCHIVE}.
  Do not load it. Re-fetch with: git lfs pull"
    note "checksum ok"
else
    # Not fatal - the archive may predate the checksum convention - but say so.
    note "no ${SUMFILE##*/}; loading unverified"
fi

note "loading ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"
"${ENGINE}" load --input "${ARCHIVE}"

"${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1 \
    || die "loaded, but ${TAG} is not present. The archive may hold a different tag:
  ${ENGINE} load --input ${ARCHIVE}   and read what it reports."

note "${TAG} ready"
note "next: 02_Tools/build/build_windows_mxe.sh"

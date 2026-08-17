#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Load the saved builder image, so a fresh clone does not have to rebuild it.
#
# This is the reason the archive exists. Building the toolchain from source
# takes hours and downloads MXE's upstream tarballs from 117 distinct hosts,
# every one of which is free to disappear. Loading the archive takes about a
# minute and reaches no network at all.
#
#   ./load_image.sh                  load the mingw toolchain
#   ./load_image.sh --image appimage
#
# The archive is carried by Git LFS. A clone made without LFS installed gets
# a ~130 byte pointer file instead of a 2.2 GB tarball; this script detects
# that and says so, rather than letting `docker load` fail obscurely.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="mingw"
ENGINE="${BUILDER_ENGINE:-docker}"
ARCHIVE=""
FORCE=0

usage() {
    cat <<'EOF'
Load a saved builder image from 07_Delivery/toolchain/.

Options:
  --image mingw|appimage   Which toolchain. Default mingw.
  --archive PATH           Load this file instead of the default location.
  --engine docker|podman   Container engine. Default docker.
  --force                  Load even if an image with that tag exists.
  -h, --help               This text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)   IMAGE="${2:-}"; shift 2 ;;
        --archive) ARCHIVE="${2:-}"; shift 2 ;;
        --engine)  ENGINE="${2:-}"; shift 2 ;;
        --force)   FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage, got '${IMAGE}'" ;;
esac

TAG="hantek-builder-${IMAGE}:latest"
ARCHIVE="${ARCHIVE:-${REPO_ROOT}/07_Delivery/toolchain/hantek-builder-${IMAGE}.tar}"

command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "${ENGINE} not found. Run this inside WSL, where the engine lives."

if [ "${FORCE}" -eq 0 ] && "${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1; then
    note "${TAG} already present; nothing to do (--force to reload)"
    exit 0
fi

[ -f "${ARCHIVE}" ] || die "archive not found: ${ARCHIVE}
  Either this clone predates the archive, or it was never generated.
  Build the toolchain instead: 02_Tools/build/build_image.sh --image ${IMAGE}"

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

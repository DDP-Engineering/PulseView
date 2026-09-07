#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Save one local builder image as checksum-verified Git LFS-sized parts.
# This script creates local files only. Publishing them is deliberately outside
# the repository automation contract.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

IMAGE="mingw"
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
OUT_DIR="${REPO_ROOT}/07_Delivery/toolchain"
PART_SIZE_MIB=1024
TAG=""

usage() {
    cat <<'EOF'
Save a local builder image as a multipart archive and manifest.

Options:
  --image mingw|appimage   Builder image. Default mingw.
  --platform ARCH          x86_64/amd64 or aarch64/arm64.
  --engine docker|podman   Container engine. Default docker.
  --tag NAME               Override the normal builder image tag.
  --out-dir PATH           Destination. Default 07_Delivery/toolchain.
  --part-size-mib N        Part size in MiB. Default 1024.
  -h, --help               This text.

The command refuses to overwrite an existing manifest or part. Remove the
specific old generation deliberately before regenerating it.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)         IMAGE="${2:-}"; shift 2 ;;
        --platform)      PLATFORM="${2:-}"; shift 2 ;;
        --engine)        ENGINE="${2:-}"; shift 2 ;;
        --tag)           TAG="${2:-}"; shift 2 ;;
        --out-dir)       OUT_DIR="${2:-}"; shift 2 ;;
        --part-size-mib) PART_SIZE_MIB="${2:-}"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *)               die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage" ;;
esac
case "${PART_SIZE_MIB}" in
    ''|*[!0-9]*) die "--part-size-mib must be a positive integer" ;;
esac
[ "${PART_SIZE_MIB}" -gt 0 ] || die "--part-size-mib must be greater than zero"

ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"
if [ "${IMAGE}" = "mingw" ] && [ "${SR_ARCH}" != "x86_64" ]; then
    die "the mingw builder is available only for x86_64 hosts"
fi

TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = "x86_64" ] || TAG_ARCH_SUFFIX="-arm64"
TAG="${TAG:-pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest}"
STEM="pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}"
MANIFEST="${OUT_DIR}/${STEM}.manifest.toml"
PART_PREFIX="${OUT_DIR}/${STEM}.tar.part-"

command -v "${ENGINE}" >/dev/null 2>&1 || die "${ENGINE} not found"
command -v split >/dev/null 2>&1 || die "split not found"
"${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1 \
    || die "image not found: ${TAG}"

mkdir -p "${OUT_DIR}" "${REPO_ROOT}/.work/bootstrap"
[ ! -e "${MANIFEST}" ] || die "manifest already exists: ${MANIFEST}"
if find "${OUT_DIR}" -maxdepth 1 -type f -name "${STEM}.tar.part-*" -print -quit \
    | grep -q .; then
    die "archive parts already exist for ${STEM}; remove that generation deliberately first"
fi

TEMP_ARCHIVE="${REPO_ROOT}/.work/bootstrap/${STEM}.tar"
COMPLETE=0
cleanup() {
    rm -f -- "${TEMP_ARCHIVE}" "${MANIFEST}.tmp"
    if [ "${COMPLETE}" -eq 0 ]; then
        find "${OUT_DIR}" -maxdepth 1 -type f \
            -name "${STEM}.tar.part-*" -delete
    fi
}
trap cleanup EXIT
[ ! -e "${TEMP_ARCHIVE}" ] || die "temporary archive already exists: ${TEMP_ARCHIVE}"

printf '==> saving %s\n' "${TAG}"
"${ENGINE}" save --output "${TEMP_ARCHIVE}" "${TAG}"
ARCHIVE_SIZE="$(wc -c < "${TEMP_ARCHIVE}" | tr -d ' ')"
ARCHIVE_SHA256="$(sha256sum "${TEMP_ARCHIVE}" | cut -d' ' -f1)"
IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${TAG}")"
BUILDER_SPEC="$("${ENGINE}" image inspect \
    --format '{{index .Config.Labels "io.ddp.builder.spec"}}' "${TAG}" 2>/dev/null || true)"

printf '==> splitting into %s MiB parts\n' "${PART_SIZE_MIB}"
split --bytes "${PART_SIZE_MIB}M" --numeric-suffixes=1 --suffix-length=3 \
    "${TEMP_ARCHIVE}" "${PART_PREFIX}"

{
    cat <<'EOF'
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

schema = 1
format = "docker-archive"
EOF
    printf 'image = "%s"\n' "${IMAGE}"
    printf 'platform = "%s"\n' "${SR_DOCKER_PLATFORM}"
    printf 'tag = "%s"\n' "${TAG}"
    printf 'image_id = "%s"\n' "${IMAGE_ID}"
    printf 'builder_spec = "%s"\n' "${BUILDER_SPEC}"
    printf 'archive = "%s.tar"\n' "${STEM}"
    printf 'archive_size = %s\n' "${ARCHIVE_SIZE}"
    printf 'archive_sha256 = "%s"\n' "${ARCHIVE_SHA256}"

    while IFS= read -r part; do
        file="$(basename -- "${part}")"
        size="$(wc -c < "${part}" | tr -d ' ')"
        digest="$(sha256sum "${part}" | cut -d' ' -f1)"
        printf '\n[[part]]\n'
        printf 'file = "%s"\n' "${file}"
        printf 'size = %s\n' "${size}"
        printf 'sha256 = "%s"\n' "${digest}"
    done < <(find "${OUT_DIR}" -maxdepth 1 -type f \
        -name "${STEM}.tar.part-*" -print | sort)
} > "${MANIFEST}.tmp"
mv -- "${MANIFEST}.tmp" "${MANIFEST}"
COMPLETE=1

PART_COUNT="$(find "${OUT_DIR}" -maxdepth 1 -type f \
    -name "${STEM}.tar.part-*" | wc -l | tr -d ' ')"
printf '==> wrote %s parts and %s\n' "${PART_COUNT}" "${MANIFEST}"
printf '    archive sha256 %s\n' "${ARCHIVE_SHA256}"
printf '    local files only; publishing is the developer\047s responsibility\n'

# END OF FILE

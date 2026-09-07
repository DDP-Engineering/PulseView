#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compute the content identity of one builder recipe. The value deliberately
# excludes generated build contexts and host-specific values such as UID/GID.
#
# Identity covers everything that changes the resulting image: the pinned
# inputs, the Dockerfile and its helpers, and - because these are real build
# choices, not conveniences - the patch selection, the Qt5 freeze, the held
# glib version, and the bytes of every patch that will actually be applied.
# Two recipes that would produce materially different images must never share
# one io.ddp.builder.spec label.
#
# Patches are identified by content, never by where they were read from, so
# --patch-dir selects a different copy without changing the identity of an
# unchanged one. The selection is the *requested* one - candidates minus
# skips - rather than the verified-applied one: this must stay computable
# without an MXE clone, and build_image.sh already refuses to build when a
# requested patch does not apply, so the two coincide in every build that
# completes.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"
IMAGES_DIR="${SCRIPT_DIR}/images"
DEFAULT_PATCH_DIR="${REPO_ROOT}/05_Software/sigrok-util/cross-compile/mingw"

# The candidate MXE patches, in the order build_image.sh considers them.
MXE_PATCH_CANDIDATES="mxe_fixes.patch libusb1_upgrade.patch"

IMAGE=""
PLATFORM=""
PATCH_DIR="${DEFAULT_PATCH_DIR}"
BUILD_DRIVER="${SCRIPT_DIR}/build_image.sh"
QT5_FREEZE=0
GLIB_VERSION=""
SKIP_PATCHES=""

usage() {
    cat <<'EOF'
Usage: builder_spec.sh --image mingw|appimage [options]

Print the SHA-256 identity of the inputs and options that define a builder.

Options:
  --image mingw|appimage   Which builder.                        (required)
  --platform ARCH          x86_64/amd64 or aarch64/arm64. Default: host.
  --qt5-freeze             Identity of a Qt 5.7 freeze build.       (mingw)
  --glib-version V         Identity of a build holding glib at V.   (mingw)
  --skip-patch NAME        Exclude one MXE patch. Repeatable.       (mingw)
  --no-sigrok-patches      Exclude all of them.                     (mingw)
  --patch-dir PATH         Read the MXE patches from here instead.  (mingw)
  --build-driver PATH      Read the context/build orchestrator from here.
  -h, --help               This text.

The mingw options must match the ones build_image.sh was or will be given;
build_image.sh passes its own effective values through.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)             IMAGE="${2:-}"; shift 2 ;;
        --platform)          PLATFORM="${2:-}"; shift 2 ;;
        --patch-dir)         PATCH_DIR="${2:-}"; shift 2 ;;
        --build-driver)      BUILD_DRIVER="${2:-}"; shift 2 ;;
        --glib-version)      GLIB_VERSION="${2:-}"; shift 2 ;;
        --qt5-freeze)        QT5_FREEZE=1; shift ;;
        --skip-patch)        SKIP_PATCHES="${SKIP_PATCHES} ${2:-}"; shift 2 ;;
        --no-sigrok-patches) SKIP_PATCHES="${MXE_PATCH_CANDIDATES}"; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage" ;;
esac

# Options that describe an MXE build say nothing about the AppImage builder.
# Accepting them silently would let two different invocations claim one
# identity for the same image, which is the failure this script exists to
# prevent.
if [ "${IMAGE}" = "appimage" ]; then
    [ "${QT5_FREEZE}" -eq 0 ] || die "--qt5-freeze applies only to the mingw builder"
    [ -z "${GLIB_VERSION}" ] || die "--glib-version applies only to the mingw builder"
    [ -z "${SKIP_PATCHES# }" ] || die "MXE patch options apply only to the mingw builder"
fi

ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"

if [ "${IMAGE}" = "mingw" ] && [ "${SR_ARCH}" != "x86_64" ]; then
    die "the mingw builder is available only for x86_64 hosts"
fi

FILES=(
    "${LOCK}"
    "${SCRIPT_DIR}/arch_map.sh"
    "${IMAGES_DIR}/Dockerfile.${IMAGE}"
)
if [ "${IMAGE}" = "mingw" ]; then
    FILES+=(
        "${IMAGES_DIR}/mxe-build.sh"
        "${IMAGES_DIR}/mxe-glib-hold.sh"
    )
fi

for file in "${FILES[@]}"; do
    [ -f "${file}" ] || die "builder input missing: ${file}"
done
[ -f "${BUILD_DRIVER}" ] || die "builder input missing: ${BUILD_DRIVER}"

# The patches this recipe selects, in the fixed candidate order so the digest
# input does not depend on the order the skips were given in.
selected_patches() {
    local candidate skip skipped
    for candidate in ${MXE_PATCH_CANDIDATES}; do
        skipped=0
        for skip in ${SKIP_PATCHES}; do
            [ "${skip}" = "${candidate}" ] && skipped=1
        done
        [ "${skipped}" -eq 1 ] || printf '%s\n' "${candidate}"
    done
}

{
    printf 'image=%s\nplatform=%s\n' "${IMAGE}" "${SR_DOCKER_PLATFORM}"

    if [ "${IMAGE}" = "mingw" ]; then
        # An empty glib_version means "whatever the Dockerfile holds", and the
        # Dockerfile is hashed below - so the default needs no value of its own.
        printf 'option.qt5_freeze=%s\n' "${QT5_FREEZE}"
        printf 'option.glib_version=%s\n' "${GLIB_VERSION}"
    fi

    for file in "${FILES[@]}"; do
        relative="${file#"${REPO_ROOT}/"}"
        digest="$(sha256sum "${file}" | cut -d' ' -f1)"
        printf '%s=%s\n' "${relative}" "${digest}"
    done

    # build_image.sh decides what enters the generated context and which build
    # arguments reach the Dockerfile, so it is recipe input even though it is
    # not copied into the image. Name the role, not the source path, to keep an
    # identical review/test copy equivalent.
    digest="$(sha256sum "${BUILD_DRIVER}" | cut -d' ' -f1)"
    printf '02_Tools/build/build_image.sh=%s\n' "${digest}"

    if [ "${IMAGE}" = "mingw" ]; then
        while IFS= read -r patch; do
            [ -n "${patch}" ] || continue
            [ -f "${PATCH_DIR}/${patch}" ] \
                || die "selected patch missing: ${PATCH_DIR}/${patch}"
            digest="$(sha256sum "${PATCH_DIR}/${patch}" | cut -d' ' -f1)"
            printf 'patch=%s=%s\n' "${patch}" "${digest}"
        done < <(selected_patches)
    fi
} | sha256sum | cut -d' ' -f1

# END OF FILE

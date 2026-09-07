#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The builder recipe identity must change when anything that changes the image
# changes: the patch selection, the Qt5 freeze, the held glib version, or the
# bytes of a patch that will be applied. It must not change when nothing does,
# and it must not depend on where the patches were read from.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"
SPEC="${REPO_ROOT}/02_Tools/build/builder_spec.sh"
PATCH_SRC="${REPO_ROOT}/05_Software/sigrok-util/cross-compile/mingw"
BUILD_DRIVER="${REPO_ROOT}/02_Tools/build/build_image.sh"

[ -f "${SPEC}" ] || { echo 'FAIL: builder_spec.sh is missing' >&2; exit 1; }
[ -f "${BUILD_DRIVER}" ] || { echo 'FAIL: build_image.sh is missing' >&2; exit 1; }
[ -d "${PATCH_SRC}" ] || { echo 'SKIP: sigrok-util patches not present' >&2; exit 77; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

spec() { bash "${SPEC}" --image mingw --platform x86_64 "$@"; }

BASE="$(spec)"
[ -n "${BASE}" ] || { echo 'FAIL: baseline identity is empty' >&2; exit 1; }

# Stable across runs. An identity that moves on its own cannot detect anything.
[ "$(spec)" = "${BASE}" ] \
    || { echo 'FAIL: identity is not reproducible across runs' >&2; exit 1; }

assert_differs() {
    local label="$1" value="$2"
    [ -n "${value}" ] || { echo "FAIL: ${label} produced an empty identity" >&2; exit 1; }
    [ "${value}" != "${BASE}" ] \
        || { echo "FAIL: ${label} did not change the builder identity" >&2; exit 1; }
    case "${SEEN}" in
        *"${value}"*)
            echo "FAIL: ${label} collided with an earlier variant" >&2; exit 1 ;;
    esac
    SEEN="${SEEN} ${value}"
}

SEEN="${BASE}"

assert_differs 'skip-patch mxe_fixes.patch' "$(spec --skip-patch mxe_fixes.patch)"
assert_differs 'no-sigrok-patches'          "$(spec --no-sigrok-patches)"
assert_differs 'qt5 freeze'                 "$(spec --qt5-freeze)"
assert_differs 'custom glib version'        "$(spec --glib-version 2.80.0)"

# The patch directory is an input by content, not by path: an untouched copy
# must reproduce the baseline exactly, and one changed byte must not.
cp -a "${PATCH_SRC}" "${TMP}/patches"
[ "$(spec --patch-dir "${TMP}/patches")" = "${BASE}" ] \
    || { echo 'FAIL: an identical patch copy changed the identity' >&2; exit 1; }

printf '\n# appended by builder_spec_identity_test\n' \
    >> "${TMP}/patches/libusb1_upgrade.patch"
assert_differs 'edited libusb1_upgrade.patch' \
    "$(spec --patch-dir "${TMP}/patches")"

# The host-side driver assembles the context and build arguments, so its bytes
# are recipe input too. As with patches, location alone must not matter.
cp "${BUILD_DRIVER}" "${TMP}/build_image.sh"
[ "$(spec --build-driver "${TMP}/build_image.sh")" = "${BASE}" ] \
    || { echo 'FAIL: an identical build driver copy changed the identity' >&2; exit 1; }
printf '\n# changed by builder_spec_identity_test\n' >> "${TMP}/build_image.sh"
assert_differs 'edited build_image.sh' \
    "$(spec --build-driver "${TMP}/build_image.sh")"

# A patch excluded from the build must not affect the identity of that build:
# skipping both patches makes the bytes of either irrelevant.
NONE_A="$(spec --no-sigrok-patches --patch-dir "${TMP}/patches")"
NONE_B="$(spec --no-sigrok-patches --patch-dir "${PATCH_SRC}")"
[ "${NONE_A}" = "${NONE_B}" ] \
    || { echo 'FAIL: excluded patch bytes still affect the identity' >&2; exit 1; }

# The appimage builder has no MXE patches; its identity must still be stable
# and must differ from the mingw builder's.
APP="$(bash "${SPEC}" --image appimage --platform x86_64)"
[ -n "${APP}" ] || { echo 'FAIL: appimage identity is empty' >&2; exit 1; }
[ "${APP}" != "${BASE}" ] \
    || { echo 'FAIL: appimage and mingw share one identity' >&2; exit 1; }
[ "$(bash "${SPEC}" --image appimage --platform aarch64)" != "${APP}" ] \
    || { echo 'FAIL: appimage identity ignores the platform' >&2; exit 1; }

printf 'builder spec identity: all assertions passed\n'
exit 0

# END OF FILE

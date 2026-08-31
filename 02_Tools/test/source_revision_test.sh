#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-REL-08b2f2e8: provenance names HEAD honestly when source/build inputs
# are clean and appends -dirty when tracked or untracked inputs differ.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REVISION="${HERE}/../build/source_revision.sh"
[ -f "${REVISION}" ] || { echo "FAIL: source_revision.sh is missing" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
REPO="${TMP}/repo"
mkdir -p "${REPO}/02_Tools/build"
git -C "${REPO}" init -q
git -C "${REPO}" config user.name test
git -C "${REPO}" config user.email test@example.invalid
echo tracked >"${REPO}/02_Tools/build/tracked.sh"
git -C "${REPO}" add .
git -C "${REPO}" commit -qm initial
HEAD_SHORT="$(git -C "${REPO}" rev-parse --short HEAD)"

expect_revision() {
    local want="$1" label="$2" got
    got="$(bash "${REVISION}" "${REPO}")"
    [ "${got}" = "${want}" ] || {
        echo "FAIL: ${label}: got '${got}', want '${want}'" >&2
        exit 1
    }
}

expect_revision "${HEAD_SHORT}" clean

echo modified >>"${REPO}/02_Tools/build/tracked.sh"
expect_revision "${HEAD_SHORT}-dirty" tracked-modification
git -C "${REPO}" checkout -q -- 02_Tools/build/tracked.sh

echo new >"${REPO}/02_Tools/build/untracked.sh"
expect_revision "${HEAD_SHORT}-dirty" untracked-build-input
rm "${REPO}/02_Tools/build/untracked.sh"

mkdir -p "${REPO}/07_Delivery" "${REPO}/.work"
echo generated >"${REPO}/07_Delivery/package.AppImage"
echo scratch >"${REPO}/.work/log.txt"
expect_revision "${HEAD_SHORT}" generated-output-only

printf 'source revision: all assertions passed\n'

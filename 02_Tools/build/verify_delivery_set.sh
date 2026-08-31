#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

set -euo pipefail

REV=""
if [ "${1:-}" = "--revision" ]; then
    REV="${2:?--revision needs a value}"
    shift 2
fi
[ "$#" -eq 1 ] || {
    echo "usage: verify_delivery_set.sh --revision REV DELIVERY_DIR" >&2
    exit 2
}
[ -n "${REV}" ] || { echo "error: --revision is required" >&2; exit 2; }

DIR="$(cd -- "$1" 2>/dev/null && pwd)" \
    || { echo "error: delivery directory not found: $1" >&2; exit 1; }
MANIFEST="${DIR}/SHA256SUMS"
rm -f -- "${MANIFEST}" "${MANIFEST}.tmp"
trap 'rm -f -- "${MANIFEST}.tmp"' EXIT

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "${REV}" in
    *[!A-Za-z0-9._+-]*) die "revision contains unsupported characters: ${REV}" ;;
esac
DEB_REV="$(printf '%s' "${REV}" | tr '[:upper:]_-' '[:lower:]..' \
    | sed 's/[^a-z0-9.+~]/./g; s/\.\{2,\}/./g; s/^\.//; s/\.$//')"

shopt -s nullglob
DATE_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
WINDOWS=("${DIR}"/pulseview-${DATE_GLOB}-"${REV}"-windows-x64.zip)
LINUX_TAR=("${DIR}"/pulseview-${DATE_GLOB}-"${REV}"-linux-x64.tar.gz)
X64_APP=("${DIR}"/PulseView-x86_64.AppImage)
ARM_APP=("${DIR}"/PulseView-aarch64.AppImage)
ARM_DEB=("${DIR}"/pulseview-ddp_*+git"${DEB_REV}"_arm64.deb)

for row in WINDOWS LINUX_TAR X64_APP ARM_APP ARM_DEB; do
    eval 'count=${#'"${row}"'[@]}'
    [ "${count}" -eq 1 ] || die "${row} target has ${count} package(s), expected exactly one"
done

for readme in README-AppImage.txt README-AppImage-aarch64.txt; do
    [ -f "${DIR}/${readme}" ] || die "missing AppImage provenance file ${readme}"
    grep -Fx -- "Source revision: ${REV}" "${DIR}/${readme}" >/dev/null \
        || die "${readme} does not identify source revision ${REV}"
done

FILES=(
    "${WINDOWS[0]}"
    "${X64_APP[0]}"
    "${LINUX_TAR[0]}"
    "${ARM_APP[0]}"
    "${ARM_DEB[0]}"
)

for file in "${FILES[@]}"; do
    [ -s "${file}" ] || die "package is missing or empty: $(basename "${file}")"
done

(
    cd "${DIR}"
    for file in "${FILES[@]}"; do
        sha256sum "$(basename "${file}")"
    done | sort -k2 > "$(basename "${MANIFEST}").tmp"
    sha256sum --check "$(basename "${MANIFEST}").tmp" >/dev/null
)
mv -- "${MANIFEST}.tmp" "${MANIFEST}"
trap - EXIT

printf 'verified complete delivery set for %s:\n' "${REV}"
sed 's/^/  /' "${MANIFEST}"

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
VERIFY="${REPO}/02_Tools/build/verify_delivery_set.sh"
COORDINATOR="${REPO}/02_Tools/build/build_delivery_set.ps1"
REV="abc123-dirty"
DEB_REV="abc123.dirty"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "${VERIFY}" ] || fail "delivery-set verifier does not exist"
[ -f "${COORDINATOR}" ] || fail "delivery-set coordinator does not exist"

for token in \
    'Windows x86_64 ZIP' \
    'Linux x86_64 AppImage' \
    'Linux x86_64 tarball' \
    'Raspberry Pi aarch64 AppImage' \
    'Raspberry Pi arm64 Debian package'; do
    grep -F -- "${token}" "${COORDINATOR}" >/dev/null \
        || fail "coordinator does not name phase: ${token}"
done

for command in \
    'build_windows_mxe.sh --stage' \
    'build_linux.sh' \
    'build_appimage.sh' \
    'build_appimage.sh --arch aarch64' \
    'build_deb.sh' \
    'package_windows.sh --rev' \
    'verify_delivery_set.sh --revision'; do
    grep -F -- "${command}" "${COORDINATOR}" >/dev/null \
        || fail "coordinator does not invoke: ${command}"
done

if command -v powershell.exe >/dev/null 2>&1; then
    PS_COORDINATOR=""
    if command -v cygpath >/dev/null 2>&1; then
        PS_COORDINATOR="$(cygpath -w "${COORDINATOR}")"
    elif command -v wslpath >/dev/null 2>&1; then
        PS_COORDINATOR="$(wslpath -w "${COORDINATOR}")"
    fi
    [ -n "${PS_COORDINATOR}" ] || fail "cannot map coordinator path for powershell.exe"
    PLAN="$(powershell.exe -NoProfile -ExecutionPolicy Bypass \
        -File "${PS_COORDINATOR}" -Plan | tr -d '\r')"
    for token in \
        'Windows x86_64 ZIP' \
        'Linux x86_64 AppImage' \
        'Linux x86_64 tarball' \
        'Raspberry Pi aarch64 AppImage' \
        'Raspberry Pi arm64 Debian package'; do
        grep -F -- "${token}" <<<"${PLAN}" >/dev/null \
            || fail "-Plan output omitted phase: ${token}"
    done
fi

TMP="$(mktemp -d)"
trap 'rm -rf -- "${TMP}"' EXIT

make_complete_set() {
    local dir="$1"
    mkdir -p "${dir}"
    printf 'windows\n' > "${dir}/pulseview-20260831-${REV}-windows-x64.zip"
    printf 'linux appimage\n' > "${dir}/PulseView-x86_64.AppImage"
    printf 'linux tar\n' > "${dir}/pulseview-20260831-${REV}-linux-x64.tar.gz"
    printf 'pi appimage\n' > "${dir}/PulseView-aarch64.AppImage"
    printf 'pi deb\n' > "${dir}/pulseview-ddp_0.5.0+git${DEB_REV}_arm64.deb"
    printf 'Source revision: %s\n' "${REV}" > "${dir}/README-AppImage.txt"
    printf 'Source revision: %s\n' "${REV}" > "${dir}/README-AppImage-aarch64.txt"
}

GOOD="${TMP}/good"
make_complete_set "${GOOD}"
bash "${VERIFY}" --revision "${REV}" "${GOOD}"

[ -f "${GOOD}/SHA256SUMS" ] || fail "complete set did not produce SHA256SUMS"
[ "$(wc -l < "${GOOD}/SHA256SUMS" | tr -d ' ')" = 5 ] \
    || fail "SHA256SUMS does not contain exactly five packages"
(cd "${GOOD}" && sha256sum --check SHA256SUMS >/dev/null) \
    || fail "generated checksums do not verify"

mapfile -t REQUIRED < <(awk '{print $2}' "${GOOD}/SHA256SUMS")
for missing in "${REQUIRED[@]}"; do
    CASE="${TMP}/missing-$(basename "${missing}" | tr '+.' '__')"
    make_complete_set "${CASE}"
    rm -f -- "${CASE}/${missing#\*}"
    if bash "${VERIFY}" --revision "${REV}" "${CASE}" >/dev/null 2>&1; then
        fail "verifier accepted a set missing ${missing}"
    fi
    [ ! -e "${CASE}/SHA256SUMS" ] \
        || fail "failed verification left a checksum manifest"
done

DUPLICATE="${TMP}/duplicate"
make_complete_set "${DUPLICATE}"
printf 'duplicate\n' > "${DUPLICATE}/pulseview-20260901-${REV}-windows-x64.zip"
if bash "${VERIFY}" --revision "${REV}" "${DUPLICATE}" >/dev/null 2>&1; then
    fail "verifier accepted two Windows packages"
fi
[ ! -e "${DUPLICATE}/SHA256SUMS" ] \
    || fail "duplicate failure left a checksum manifest"

WRONG_REV="${TMP}/wrong-revision"
make_complete_set "${WRONG_REV}"
printf 'Source revision: stale\n' > "${WRONG_REV}/README-AppImage-aarch64.txt"
if bash "${VERIFY}" --revision "${REV}" "${WRONG_REV}" >/dev/null 2>&1; then
    fail "verifier accepted mismatched AppImage provenance"
fi

printf 'PASS: complete delivery set is five exact same-revision packages with verified hashes\n'

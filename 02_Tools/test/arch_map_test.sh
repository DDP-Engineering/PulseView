#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-PLAT-871c1254: every architecture-dependent value the Linux build
# scripts use comes from one shared mapping, and the x86_64 row of that
# mapping reproduces the historical artifact names byte for byte. A rename
# there would silently break the delivery ledger and every download
# instruction already published, which is why the expected values are
# spelled out literally here instead of being computed.
#
# Pure logic, no Docker and no built artifacts: this test runs everywhere.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${HERE}/../build"
MAP="${BUILD_DIR}/arch_map.sh"

FAILURES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

[ -f "${MAP}" ] || { fail "arch_map.sh does not exist at ${MAP}"; exit 1; }

# Source the mapping for one architecture in a clean subshell and print the
# exported values as one |-separated line.
probe() {
    bash -c 'set -e; ARCH_OVERRIDE="$1" . "$2" \
        && printf "%s|%s|%s|%s|%s|%s" \
            "${SR_ARCH}" "${SR_LIBDIR}" "${SR_STAGE_NAME}" \
            "${SR_TARBALL_SUFFIX}" "${SR_APPIMAGE_NAME}" \
            "${SR_DOCKER_PLATFORM}"' probe "$1" "${MAP}"
}

# --- x86_64: the historical names, byte for byte -------------------------
GOT="$(probe x86_64)" || fail "mapping rejected x86_64"
WANT="x86_64|x86_64-linux-gnu|pulseview-linux-x86_64|linux-x64|PulseView-x86_64.AppImage|linux/amd64"
[ "${GOT}" = "${WANT}" ] \
    || fail "x86_64 mapping drifted: got '${GOT}' want '${WANT}'"

# --- aarch64: the Raspberry Pi 4/5 target --------------------------------
GOT="$(probe aarch64)" || fail "mapping rejected aarch64"
WANT="aarch64|aarch64-linux-gnu|pulseview-linux-aarch64|linux-arm64|PulseView-aarch64.AppImage|linux/arm64"
[ "${GOT}" = "${WANT}" ] \
    || fail "aarch64 mapping drifted: got '${GOT}' want '${WANT}'"

# arm64 is the same machine: uname -m says aarch64 on Linux but Docker's
# TARGETARCH and macOS say arm64. Both spellings must land on one row.
GOT_ALIAS="$(probe arm64)" || fail "mapping rejected arm64 alias"
[ "${GOT_ALIAS}" = "${GOT}" ] \
    || fail "arm64 alias diverged from aarch64: '${GOT_ALIAS}'"

# --- an unmapped architecture must fail loudly, not emit empty strings ---
if OUT="$(probe riscv64 2>/dev/null)"; then
    fail "unmapped riscv64 was accepted with '${OUT}' instead of failing"
fi

# --- the build scripts must consume the mapping, not carry their own -----
for script in build_linux.sh build_appimage.sh; do
    grep -q 'arch_map\.sh' "${BUILD_DIR}/${script}" \
        || fail "${script} does not source arch_map.sh"
done
# The one place the x86_64 multiarch dir may still be written out is the
# mapping itself; a literal left in a build script is a fork waiting to drift.
for script in build_linux.sh build_appimage.sh; do
    if grep -q 'x86_64-linux-gnu' "${BUILD_DIR}/${script}"; then
        fail "${script} still hardcodes x86_64-linux-gnu"
    fi
done

if [ "${FAILURES}" -gt 0 ]; then
    printf '%d assertion(s) failed\n' "${FAILURES}" >&2
    exit 1
fi
printf 'arch_map: all assertions passed\n'
exit 0

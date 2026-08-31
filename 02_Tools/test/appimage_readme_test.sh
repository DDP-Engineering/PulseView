#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WRITER="${HERE}/../build/write_appimage_readme.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

bash "${WRITER}" "${TMP}/x64.txt" x86_64 PulseView-x86_64.AppImage test-dirty
grep -q '^Linux x86_64 AppImage - built test-dirty$' "${TMP}/x64.txt"
grep -q '^Source revision: test-dirty$' "${TMP}/x64.txt"
grep -q '64-bit Intel/AMD Linux systems' "${TMP}/x64.txt"
if grep -q 'Raspberry Pi' "${TMP}/x64.txt"; then
    echo "FAIL: x86_64 README contains ARM-only Raspberry Pi guidance" >&2
    exit 1
fi

bash "${WRITER}" "${TMP}/arm64.txt" aarch64 PulseView-aarch64.AppImage test-dirty
grep -q '^Linux aarch64 AppImage - built test-dirty$' "${TMP}/arm64.txt"
grep -q '^Source revision: test-dirty$' "${TMP}/arm64.txt"
grep -q 'Raspberry Pi 4 and 5' "${TMP}/arm64.txt"
grep -q 'A 32-bit OS' "${TMP}/arm64.txt"

if bash "${WRITER}" "${TMP}/bad.txt" riscv64 PulseView-riscv64.AppImage test \
        >/dev/null 2>&1; then
    echo "FAIL: unsupported README architecture was accepted" >&2
    exit 1
fi

echo "AppImage README: architecture-specific assertions passed"

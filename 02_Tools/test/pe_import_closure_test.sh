#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Require every non-system PE import to resolve within the staged tree.

set -euo pipefail

STAGE="${1:-}"
[ -n "${STAGE}" ] && [ -d "${STAGE}" ] \
    || { echo 'SKIP: Windows staging tree unavailable'; exit 77; }
if [ -n "${BUILDER_TAG:-}" ]; then
    ENGINE="${BUILDER_ENGINE:-docker}"
    command -v "${ENGINE}" >/dev/null 2>&1 \
        || { echo "SKIP: ${ENGINE} unavailable"; exit 77; }
    "${ENGINE}" run --rm --network none --platform linux/amd64 \
        --volume "${STAGE}:/candidate:ro" \
        --volume "${BASH_SOURCE[0]}:/tmp/pe_import_closure_test.sh:ro" \
        "${BUILDER_TAG}" bash /tmp/pe_import_closure_test.sh /candidate
    exit $?
fi
OBJDUMP="${OBJDUMP:-$(command -v x86_64-w64-mingw32-objdump || command -v objdump || true)}"
[ -n "${OBJDUMP}" ] || { echo 'SKIP: PE objdump unavailable'; exit 77; }
mapfile -t BINARIES < <(find "${STAGE}" -type f \( -iname '*.exe' -o -iname '*.dll' \) | sort)
[ "${#BINARIES[@]}" -gt 0 ] || { echo 'FAIL: no staged PE binaries' >&2; exit 1; }
mapfile -t PRESENT < <(find "${STAGE}" -type f -iname '*.dll' -printf '%f\n' | tr '[:upper:]' '[:lower:]' | sort -u)
SYSTEM='^(advapi32|bcrypt|comdlg32|crypt32|dwmapi|gdi32|imm32|iphlpapi|kernel32|mpr|msvcrt|netapi32|ntdll|ole32|oleaut32|rpcrt4|secur32|setupapi|shell32|shlwapi|user32|userenv|uxtheme|version|winmm|winspool|ws2_32)\.dll$'
FAILED=0
for binary in "${BINARIES[@]}"; do
    while IFS= read -r imported; do
        name="$(printf '%s' "${imported}" | tr '[:upper:]' '[:lower:]')"
        printf '%s\n' "${name}" | grep -Eq "${SYSTEM}" && continue
        printf '%s\n' "${PRESENT[@]}" | grep -qxF "${name}" || {
            printf 'FAIL: %s imports missing %s\n' "${binary#${STAGE}/}" "${imported}" >&2
            FAILED=1
        }
    done < <("${OBJDUMP}" -p "${binary}" | awk '/DLL Name:/{print $3}')
done
[ "${FAILED}" -eq 0 ] || exit 1
printf 'PE import closure passed for %s binaries\n' "${#BINARIES[@]}"

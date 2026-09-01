#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run every test in this directory. This is what `aegis.toml` points its
# `test` command at.
#
# Exit 77 from a test means "cannot run here", not "failed" - the convention
# autotools uses. It matters because these tests drive built artifacts:
# windows_python_smoke.sh needs a staged Windows tree and either a Windows
# host or Wine, and on a machine with neither, "skipped" is the truthful
# result. A skip is reported on its own line and in the summary so it can
# never be mistaken for a pass.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=""
SKIPPED_NAMES=""

for t in "${HERE}"/*_smoke.sh "${HERE}"/*_test.sh; do
    [ -f "${t}" ] || continue
    name="$(basename "${t}")"
    printf '\n--- %s\n' "${name}"
    bash "${t}" "$@"
    rc=$?
    case "${rc}" in
        0)  PASS=$((PASS + 1)) ;;
        77) SKIP=$((SKIP + 1)); SKIPPED_NAMES="${SKIPPED_NAMES} ${name}" ;;
        *)  FAIL=$((FAIL + 1)); FAILED_NAMES="${FAILED_NAMES} ${name}" ;;
    esac
done

printf '\n=== %d passed, %d failed, %d skipped\n' "${PASS}" "${FAIL}" "${SKIP}"
[ -n "${SKIPPED_NAMES}" ] && printf '    skipped:%s\n' "${SKIPPED_NAMES}"
[ -n "${FAILED_NAMES}" ] && printf '    failed:%s\n' "${FAILED_NAMES}"

[ "${FAIL}" -eq 0 ] || exit 1

# A run where everything skipped proves nothing; say so rather than reporting
# a green suite that never executed an assertion.
if [ "${PASS}" -eq 0 ] && [ "${SKIP}" -gt 0 ]; then
    printf '    nothing ran; this is not a passing suite\n'
    exit 77
fi
exit 0

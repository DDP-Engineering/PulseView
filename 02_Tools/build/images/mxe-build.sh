#!/bin/bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Build a set of MXE packages, and on failure show the error.
#
# This exists because MXE writes each package's real compiler output to
# log/<pkg>_<target> and prints only a make summary to stdout. Inside a
# container that log dies with the failed layer, so without this a failure
# reports which package broke and gives no way to find out why.
#
# Runs inside the image; expects MXE_DIR, MXE_TARGET, PKG_JOBS, SUB_JOBS.
# Takes the package list as arguments.

set -euo pipefail

cd "${MXE_DIR}"

# MXE takes a space-separated list in one MXE_PLUGIN_DIRS variable. The glib
# hold is deliberately not here: plugin patches are applied on top of the ones
# in src/ rather than replacing them, so it edits src/ directly instead.
dirs=""
if [ "${MXE_QT5_FREEZE:-0}" = "1" ]; then
    dirs="plugins/examples/qt5-freeze"
fi
plugin=()
if [ -n "${dirs}" ]; then
    plugin=("MXE_PLUGIN_DIRS=${dirs}")
    echo "using MXE plugins: ${dirs}"
fi

out="$(mktemp)"

# pipefail is what makes `if make | tee` report make's status rather than
# tee's. Getting this wrong is how a failed build reports success.
if make -j"${PKG_JOBS}" JOBS="${SUB_JOBS}" \
        MXE_TARGETS="${MXE_TARGET}" \
        "${plugin[@]}" \
        qtbase_CONFIGURE_OPTS='-no-sql-mysql' \
        "$@" 2>&1 | tee "${out}"; then
    exit 0
fi

echo
echo "==================== MXE build failed ===================="

# MXE names the culprit; use that rather than guessing from the log directory.
# Sorting logs by name or mtime both pick the wrong file - packages that were
# still building when this one failed finish afterwards.
pkg="$(grep -oE 'Failed to build package [A-Za-z0-9_.+-]+' "${out}" \
       | head -1 | awk '{print $NF}')"

if [ -n "${pkg}" ]; then
    echo "failing package: ${pkg}"
    log="${MXE_DIR}/log/${pkg}_${MXE_TARGET}"
    if [ -f "${log}" ]; then
        echo "----------------------------- ${log}"
        tail -200 "${log}"
        exit 1
    fi
    echo "no log found at ${log}"
fi

echo "could not identify the failing package; newest target logs follow"
for l in $(ls -t "${MXE_DIR}"/log/*_"${MXE_TARGET}" 2>/dev/null | head -2); do
    echo "----------------------------- ${l}"
    tail -100 "${l}"
done
exit 1

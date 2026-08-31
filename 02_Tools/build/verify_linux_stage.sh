#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Fail-closed runtime gate for the thin Linux staging tree. This runs inside
# the native or emulated build container, where the distro runtime libraries
# used during compilation are present.

set -euo pipefail

STAGE="${1:?usage: verify_linux_stage.sh STAGE_DIR}"
CLI="${STAGE}/sigrok-cli"
[ -x "${CLI}" ] || { echo "staged sigrok-cli is missing or not executable: ${CLI}" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

if ! "${CLI}" --version >"${TMP}/version.log" 2>&1; then
    echo "staged sigrok-cli could not report its version" >&2
    cat "${TMP}/version.log" >&2
    exit 1
fi
head -2 "${TMP}/version.log"

if ! "${CLI}" -L >"${TMP}/supported.log" 2>&1; then
    echo "staged sigrok-cli could not list supported drivers" >&2
    cat "${TMP}/supported.log" >&2
    exit 1
fi
for driver in hantek-dso3062l atk-dl16; do
    grep -q "^[[:space:]]*${driver}[[:space:]]" "${TMP}/supported.log" || {
        echo "staged sigrok-cli does not list required driver: ${driver}" >&2
        exit 1
    }
done
echo "required drivers listed: hantek-dso3062l, atk-dl16"

# --show scans for a device and exits 1 when none is attached. Preserve the
# diagnostic, but never confuse an empty build bench with a broken package.
if ! "${CLI}" --driver hantek-dso3062l --show >"${TMP}/device.log" 2>&1; then
    echo "device probe skipped as a hard gate (no instrument may be attached)"
fi
head -3 "${TMP}/device.log" || true

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Print the source revision consumed by a build. Generated packages and
# scratch state do not affect provenance; every other tracked or untracked
# change makes the revision explicitly dirty.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:-$(cd -- "${SCRIPT_DIR}/../.." && pwd)}"

if ! REV="$(git -C "${REPO}" rev-parse --short HEAD 2>/dev/null)"; then
    echo unknown
    exit 0
fi

DIRTY="$(git -C "${REPO}" status --porcelain --untracked-files=normal -- \
    . ':(exclude)07_Delivery' ':(exclude)07_Delivery/**' \
    ':(exclude).work' ':(exclude).work/**')"
[ -z "${DIRTY}" ] || REV="${REV}-dirty"
printf '%s\n' "${REV}"

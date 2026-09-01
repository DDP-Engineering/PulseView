#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
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

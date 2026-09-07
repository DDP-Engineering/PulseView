#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Verify the actual arm64 Debian package's architecture and dependency floor.

set -euo pipefail

DEB="${DEB_PATH:-}"
[ -n "${DEB}" ] && [ -f "${DEB}" ] \
    || { echo 'SKIP: DEB_PATH is not a built package'; exit 77; }
command -v dpkg-deb >/dev/null 2>&1 \
    || { echo 'SKIP: dpkg-deb unavailable'; exit 77; }
ARCH="$(dpkg-deb -f "${DEB}" Architecture)"
[ "${ARCH}" = arm64 ] || { echo "FAIL: Debian Architecture is ${ARCH}, not arm64" >&2; exit 1; }
DEPS="$(dpkg-deb -f "${DEB}" Depends)"
for dependency in 'libc6 (>= 2.35)' 'libstdc++6' 'libgl1' 'libegl1'; do
    printf '%s' "${DEPS}" | grep -qF "${dependency}" \
        || { echo "FAIL: missing Debian dependency: ${dependency}" >&2; exit 1; }
done
printf 'Debian artifact metadata passed: arm64\n'

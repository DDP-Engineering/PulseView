#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The one table of architecture-dependent values the Linux build scripts
# use. Source this, do not execute it:
#
#   . "$(dirname "$0")/arch_map.sh"          # maps $(uname -m)
#   ARCH_OVERRIDE=aarch64 . .../arch_map.sh  # maps a named architecture
#
# Exports:
#   SR_ARCH             canonical architecture name (x86_64 | aarch64)
#   SR_LIBDIR           Debian/Ubuntu multiarch library directory
#   SR_STAGE_NAME       staging directory under 07_Delivery/staging/
#   SR_TARBALL_SUFFIX   suffix of the delivery tarball name
#   SR_APPIMAGE_NAME    file name of the AppImage delivery
#   SR_DOCKER_PLATFORM  --platform value for the build container
#
# The x86_64 row reproduces the names existing deliveries already use, byte
# for byte - they are load-bearing in the delivery ledger and in published
# download instructions, so a rename here is a breaking change even though
# it looks cosmetic. 02_Tools/test/arch_map_test.sh pins every row.
#
# aarch64 and arm64 are one machine with two spellings: Linux uname -m says
# aarch64, Docker's TARGETARCH and macOS say arm64. Both land on one row.
#
# An architecture with no row is an error, loudly. Emitting empty strings
# would let a build stage a nameless tarball and fail somewhere far away.

_SR_MACHINE="${ARCH_OVERRIDE:-$(uname -m)}"

case "${_SR_MACHINE}" in
    x86_64|amd64)
        SR_ARCH="x86_64"
        SR_LIBDIR="x86_64-linux-gnu"
        SR_STAGE_NAME="pulseview-linux-x86_64"
        SR_TARBALL_SUFFIX="linux-x64"
        SR_APPIMAGE_NAME="PulseView-x86_64.AppImage"
        SR_DOCKER_PLATFORM="linux/amd64"
        ;;
    aarch64|arm64)
        SR_ARCH="aarch64"
        SR_LIBDIR="aarch64-linux-gnu"
        SR_STAGE_NAME="pulseview-linux-aarch64"
        SR_TARBALL_SUFFIX="linux-arm64"
        SR_APPIMAGE_NAME="PulseView-aarch64.AppImage"
        SR_DOCKER_PLATFORM="linux/arm64"
        ;;
    *)
        printf 'arch_map.sh: no mapping for architecture "%s"\n' \
            "${_SR_MACHINE}" >&2
        printf 'arch_map.sh: known: x86_64 (amd64), aarch64 (arm64)\n' >&2
        unset _SR_MACHINE
        return 1 2>/dev/null || exit 1
        ;;
esac

unset _SR_MACHINE
export SR_ARCH SR_LIBDIR SR_STAGE_NAME SR_TARBALL_SUFFIX \
    SR_APPIMAGE_NAME SR_DOCKER_PLATFORM

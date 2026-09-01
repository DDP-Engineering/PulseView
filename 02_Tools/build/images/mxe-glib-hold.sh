#!/bin/bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build an MXE plugin that holds glib at an older version.
#
# Why this is needed: MXE pins glibmm at 2.66.2, untouched since March 2022,
# while an automated updater has walked glib from 2.85 to 2.89 over the past
# year. They no longer compile together - glibmm's generated headers collide
# with glib's own declarations:
#
#   giomm/dbusactiongroup.h:32: error: conflicting declaration
#     'using GDBusActionGroupClass = struct _GDBusActionGroupClass'
#
# libsigrok's C++ bindings need glibmm, and PulseView needs those, so glibmm
# cannot simply be dropped the way `check` was.
#
# Overriding only $(PKG)_VERSION on the make command line does not work:
# src/glib-1-fixes.patch is written against the version in the tree and will
# not apply to a different tarball. So glib.mk and its patches are taken
# together, from the MXE commit that actually shipped the wanted version.
# That is also where the checksum comes from - it is a value MXE verified,
# not one invented here.
#
# This replaces the files in src/ rather than adding an MXE_PLUGIN_DIRS
# plugin. A plugin looked like the tidier option, being MXE's own extension
# point, but its patches are applied *in addition to* the ones in src/, not
# instead of them. With both the current and the older glib-1-fixes.patch in
# play MXE hits "Reversed (or previously applied) patch detected", leaves
# rejects behind and fails before glibmm is ever reached. Replacing in-tree is
# also what sigrok's own libusb1_upgrade.patch does.
#
# Usage:  mxe-glib-hold <glib-version>     e.g. mxe-glib-hold 2.84.1

set -euo pipefail

VERSION="${1:?usage: mxe-glib-hold <glib-version>}"
MXE_DIR="${MXE_DIR:-/opt/mxe}"

cd "${MXE_DIR}"

# A leftover plugin directory from an earlier approach silently wins over
# src/: MXE globs <dir>/glib.mk and <dir>/glib-[0-9]*.patch across every
# plugin dir and includes them alongside src/, so a stale copy pins the wrong
# version and double-applies patches. That cost three worthless bisections.
rm -rf "${MXE_DIR}/plugins/glib-hold"

# Find the newest commit whose src/glib.mk declares the wanted version. Search
# the whole history of the file rather than assuming the pinned checkout still
# contains that revision.
commit=""
while read -r c; do
    v="$(git show "${c}:src/glib.mk" 2>/dev/null \
         | sed -n 's/^\$(PKG)_VERSION *:= *//p' | head -1)"
    if [ "${v}" = "${VERSION}" ]; then
        commit="${c}"
        break
    fi
done < <(git log --format=%H --all -- src/glib.mk)

if [ -z "${commit}" ]; then
    echo "mxe-glib-hold: no MXE commit ships glib ${VERSION}" >&2
    echo "available versions:" >&2
    git log --format=%H --all -- src/glib.mk | while read -r c; do
        git show "${c}:src/glib.mk" 2>/dev/null \
            | sed -n 's/^\$(PKG)_VERSION *:= *//p' | head -1
    done | sort -Vru | head -20 | sed 's/^/  /' >&2
    exit 1
fi

# Drop the current glib patches before writing the older set. The patch list
# differs between versions, so leaving a stale one behind reintroduces exactly
# the double-apply this function exists to avoid.
rm -f src/glib-[0-9]*.patch

git show "${commit}:src/glib.mk" > src/glib.mk

written=""
for p in $(git ls-tree --name-only "${commit}" src/ | grep -E '^src/glib-[0-9]+-.*\.patch$'); do
    git show "${commit}:${p}" > "${p}"
    written="${written} $(basename "${p}")"
done

checksum="$(sed -n 's/^\$(PKG)_CHECKSUM *:= *//p' src/glib.mk | head -1)"
actual="$(sed -n 's/^\$(PKG)_VERSION *:= *//p' src/glib.mk | head -1)"

test "${actual}" = "${VERSION}" \
    || { echo "mxe-glib-hold: wrote glib ${actual}, wanted ${VERSION}" >&2; exit 1; }

echo "mxe-glib-hold: glib ${VERSION} from MXE ${commit:0:12}"
echo "  checksum ${checksum}"
echo "  patches: ${written:- none}"

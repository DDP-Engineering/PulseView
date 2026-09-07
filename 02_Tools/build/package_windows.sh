#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Package the staged Windows tree as a delivery zip.
#
# build_windows_mxe.sh --stage deliberately stops at 07_Delivery/staging: at
# that point nothing has been run on Windows, and 07_Delivery is reserved for
# verified packages. This script is the step that crosses that line, so it
# refuses to cross it blind - it runs the host-side test suite against the
# staged tree first, and only packages a tree that passed.
#
# That means it belongs on the Windows host, in Git Bash. The suite drives
# sigrok-cli.exe, which needs Windows or Wine; in WSL it exits 77 ("cannot run
# here"), and 77 is not a pass, so packaging stops there rather than shipping
# an unverified tree.
#
#   bash 02_Tools/build/package_windows.sh \
#       [--stage DIR] [--out DIR] [--rev REV] [--skip-verify]
#
# Output: 07_Delivery/pulseview-<date>-<rev>-windows-x64.zip and a .sha256,
# matching the naming build_linux.sh uses for its tarball.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

STAGE="${REPO}/07_Delivery/staging/pulseview-windows-x86_64"
OUT="${REPO}/07_Delivery"
REV=""
SKIP_VERIFY=0

usage() {
    cat <<'EOF'
Package the staged Windows tree as a delivery zip.

Options:
  --stage DIR     Staged tree. Default 07_Delivery/staging/pulseview-windows-x86_64.
  --out DIR       Where to write the zip. Default 07_Delivery.
  --rev REV       Revision for the filename. Default: git rev-parse --short HEAD.
  --skip-verify   Package without running the test suite. See below.
  -h, --help      This text.

--skip-verify exists for the case where the tree was verified elsewhere and
this host cannot run the .exe. It is not a way to ship a failing tree: a suite
that FAILS still stops the packaging. It only tolerates "cannot run here".
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stage) STAGE="${2:-}"; shift 2 ;;
        --out)   OUT="${2:-}"; shift 2 ;;
        --rev)   REV="${2:-}"; shift 2 ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
    esac
done

note() { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# The staged tree must actually be one
# --------------------------------------------------------------------------

[ -d "${STAGE}" ] || die "no staged tree at ${STAGE}
       run: bash 02_Tools/build/build_windows_mxe.sh --stage"

for required in pulseview.exe sigrok-cli.exe share/libsigrokdecode/decoders; do
    [ -e "${STAGE}/${required}" ] || die "staged tree is incomplete: no ${required}"
done

# --------------------------------------------------------------------------
# Verify before crossing into 07_Delivery
# --------------------------------------------------------------------------

if [ "${SKIP_VERIFY}" -eq 1 ]; then
    note "skipping verification by request"
    printf '    The zip will carry no evidence from this host.\n'
else
    note "verifying the staged tree"
    bash "${REPO}/02_Tools/test/run_tests.sh" "${STAGE}"
    rc=$?
    case "${rc}" in
        0) note "suite passed" ;;
        77) die "the suite could not run here (77), so this tree is unverified.
       The tests drive sigrok-cli.exe: run this on Windows in Git Bash, or on
       Linux with wine installed. Use --skip-verify only if it was verified
       elsewhere." ;;
        *) die "the suite failed (${rc}). Not packaging a failing tree." ;;
    esac
fi

# --------------------------------------------------------------------------
# Revision
# --------------------------------------------------------------------------

if [ -z "${REV}" ]; then
    REV="$(bash "${SCRIPT_DIR}/source_revision.sh" "${REPO}")"
fi

# A package labelled with a revision whose tree it does not match is a
# provenance claim that cannot be checked later. Say so rather than let the
# filename imply something untrue.
if [[ "${REV}" != *-dirty ]] && ! git -C "${REPO}" diff-index --quiet HEAD -- 2>/dev/null; then
    printf '\n'
    printf 'WARNING: the working tree has uncommitted changes.\n'
    printf '         This package will be labelled %s, which does not\n' "${REV}"
    printf '         contain them. Commit first, or pass --rev %s-dirty.\n\n' "${REV}"
fi

STAGE_NAME="$(basename "${STAGE}")"
ZIP="${OUT}/pulseview-$(date +%Y%m%d)-${REV}-windows-x64.zip"

# --------------------------------------------------------------------------
# Package
# --------------------------------------------------------------------------

# python3 -m zipfile, not zip or 7z: neither ships with Git for Windows, and
# neither is present in the WSL image either, while python3 is on both and is
# already a prerequisite of the test suite. It roots the archive at the staged
# directory name, which is the layout the earlier packages used.
PY=""
for cand in python3 python; do
    command -v "${cand}" >/dev/null 2>&1 && { PY="${cand}"; break; }
done
[ -n "${PY}" ] || die "no python3 on PATH to build the zip"

mkdir -p "${OUT}"
rm -f "${ZIP}"

note "packaging ${STAGE_NAME} -> $(basename "${ZIP}")"
( cd "${STAGE}/.." && "${PY}" -m zipfile -c "${ZIP}" "${STAGE_NAME}" ) \
    || die "zip creation failed"

[ -f "${ZIP}" ] || die "zip was not created"

( cd "${OUT}" && sha256sum "$(basename "${ZIP}")" > "$(basename "${ZIP}").sha256" )

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

printf '\n'
note "done"
ls -la "${ZIP}" "${ZIP}.sha256"
printf '\n'
if [ -f "${STAGE}/build-record.txt" ]; then
    printf 'build record:\n'
    sed 's/^/    /' "${STAGE}/build-record.txt"
fi

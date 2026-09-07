#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Two build-host prerequisites the bootstrap actually depends on:
#
#   1. A Python that can import tomllib. ensure_build_environment.sh and
#      build_image.sh both read pinned TOML with it, so a 3.10 host must be
#      told the minimum version instead of receiving a traceback from inside
#      a heredoc.
#   2. The multipart builder archives. check_host.ps1 has always inspected
#      them; the Linux check must reach the same verdict about the same host.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"
PYENV="${REPO_ROOT}/02_Tools/build/python_env.sh"
CHECK="${REPO_ROOT}/02_Tools/bootstrap/check_host.sh"
ENSURE="${REPO_ROOT}/02_Tools/bootstrap/ensure_build_environment.sh"

[ -f "${PYENV}" ] || { echo "FAIL: missing ${PYENV}" >&2; exit 1; }
[ -f "${CHECK}" ] || { echo "FAIL: missing ${CHECK}" >&2; exit 1; }
[ -f "${ENSURE}" ] || { echo "FAIL: missing ${ENSURE}" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# --------------------------------------------------------------------------
# 1. The manifest-reading Python prerequisite
# --------------------------------------------------------------------------

REAL_PYTHON="$(command -v python3 || command -v python || true)"
[ -n "${REAL_PYTHON}" ] || { echo 'SKIP: no python on PATH' >&2; exit 77; }
if ! "${REAL_PYTHON}" -c 'import tomllib' 2>/dev/null; then
    echo 'SKIP: the host python cannot import tomllib' >&2
    exit 77
fi

# A stand-in for a Debian 12 / Ubuntu 22.04 host: python3 exists, reports a
# plausible version, and has no tomllib.
mkdir -p "${TMP}/old"
cat > "${TMP}/old/python3" <<'STUB'
#!/bin/bash
case "$*" in
    *--version*) echo "Python 3.10.12"; exit 0 ;;
    *"import tomllib"*) echo "ModuleNotFoundError: No module named 'tomllib'" >&2; exit 1 ;;
esac
exit 0
STUB
cat > "${TMP}/old/test-engine" <<'STUB'
#!/bin/bash
exit 1
STUB
cat > "${TMP}/ubuntu-22.04-os-release" <<'EOF'
ID=ubuntu
VERSION_ID="22.04"
EOF
chmod +x "${TMP}/old/python3" "${TMP}/old/test-engine"
ln -s "$(command -v head)" "${TMP}/old/head"

out="${TMP}/old.out"
if ( PATH="${TMP}/old"; export PATH
     SR_OS_RELEASE="${TMP}/ubuntu-22.04-os-release"; export SR_OS_RELEASE
     # shellcheck source=../build/python_env.sh
     . "${PYENV}"
     sr_require_python ) >"${out}" 2>&1; then
    echo 'FAIL: a python without tomllib was accepted' >&2
    exit 1
fi
grep -qi 'tomllib' "${out}" \
    || { echo 'FAIL: the error does not name the missing module' >&2; cat "${out}" >&2; exit 1; }
grep -q '3\.11' "${out}" \
    || { echo 'FAIL: the error does not name the minimum version' >&2; cat "${out}" >&2; exit 1; }
grep -q 'Ubuntu 24\.04' "${out}" \
    || { echo 'FAIL: Ubuntu 22.04 remedy does not require a compatible host' >&2; cat "${out}" >&2; exit 1; }
grep -qi 'Traceback' "${out}" \
    && { echo 'FAIL: a traceback reached the operator' >&2; exit 1; }

# The two operator-facing entry points must use the same helper. Restrict the
# candidates so a newer parallel interpreter cannot hide the simulated 3.10.
ENTRY_PATH="${TMP}/old:${PATH}"
if PATH="${ENTRY_PATH}" SR_PYTHON_CANDIDATES=python3 \
   SR_OS_RELEASE="${TMP}/ubuntu-22.04-os-release" \
   bash "${ENSURE}" --engine test-engine --no-rebuild \
       >"${TMP}/ensure-old.out" 2>&1; then
    echo 'FAIL: ensure_build_environment.sh accepted Python 3.10' >&2
    exit 1
fi
grep -q 'Ubuntu 24\.04' "${TMP}/ensure-old.out" \
    || { echo 'FAIL: ensure_build_environment.sh did not report the compatible-host remedy' >&2
         cat "${TMP}/ensure-old.out" >&2; exit 1; }

PATH="${ENTRY_PATH}" SR_PYTHON_CANDIDATES=python3 \
SR_OS_RELEASE="${TMP}/ubuntu-22.04-os-release" \
bash "${CHECK}" --engine test-engine --toolchain-dir "${TMP}/absent-toolchain" \
    >"${TMP}/check-old.out" 2>&1 || true
grep -Eq 'FAIL +python \(tomllib\)' "${TMP}/check-old.out" \
    && grep -q '3\.11' "${TMP}/check-old.out" \
    || { echo 'FAIL: check_host.sh did not fail its Python 3.11 row' >&2
         cat "${TMP}/check-old.out" >&2; exit 1; }

# The same helper must accept the real interpreter and name it.
found="$( . "${PYENV}"; sr_require_python && printf '%s' "${SR_PYTHON}" )"
[ -n "${found}" ] || { echo 'FAIL: a usable python was not reported' >&2; exit 1; }
"${found}" -c 'import tomllib' \
    || { echo 'FAIL: the selected interpreter cannot import tomllib' >&2; exit 1; }

# --------------------------------------------------------------------------
# 2. Multipart archive availability, as the Linux host check reports it
# --------------------------------------------------------------------------

manifest_row() {
    # Print the status of the "toolchain archive" check from a --result file.
    "${REAL_PYTHON}" - "$1" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
for check in data["checks"]:
    if check["check"] == "toolchain archive":
        print(check["status"] + "|" + check["detail"])
        break
else:
    print("ABSENT|no toolchain archive row")
PYEOF
}

make_toolchain() {
    local dir="$1"
    mkdir -p "${dir}"
    cat > "${dir}/pulseview-builder-demo.manifest.toml" <<'EOF'
schema = 1
format = "docker-archive"
image = "demo"
archive = "pulseview-builder-demo.tar"

[[part]]
file = "pulseview-builder-demo.tar.part-001"
size = 4096
sha256 = "not-used-by-host-check"

[[part]]
file = "pulseview-builder-demo.tar.part-002"
size = 4096
sha256 = "not-used-by-host-check"
EOF
}

run_check() {
    local dir="$1" result="$2"
    # Exit status is not the oracle here: an unrelated FAIL on this host (no
    # ssh identity, no arm64 emulation) must not decide an archive assertion.
    bash "${CHECK}" --toolchain-dir "${dir}" --result "${result}" \
        >/dev/null 2>&1 || true
}

# Complete: every part declared by the manifest is present.
GOOD="${TMP}/tc-good"
make_toolchain "${GOOD}"
head -c 4096 /dev/urandom > "${GOOD}/pulseview-builder-demo.tar.part-001"
head -c 4096 /dev/urandom > "${GOOD}/pulseview-builder-demo.tar.part-002"
run_check "${GOOD}" "${TMP}/good.json"
row="$(manifest_row "${TMP}/good.json")"
case "${row}" in
    PASS*) ;;
    *) echo "FAIL: complete archive did not pass: ${row}" >&2; exit 1 ;;
esac

# One matching part is not enough when the manifest declares two.
PARTIAL="${TMP}/tc-partial"
make_toolchain "${PARTIAL}"
head -c 4096 /dev/urandom > "${PARTIAL}/pulseview-builder-demo.tar.part-001"
run_check "${PARTIAL}" "${TMP}/partial.json"
row="$(manifest_row "${TMP}/partial.json")"
case "${row}" in
    FAIL*pulseview-builder-demo.tar.part-002*) ;;
    *) echo "FAIL: a missing declared part did not fail by name: ${row}" >&2; exit 1 ;;
esac

# Manifest with no parts beside it.
NOPARTS="${TMP}/tc-noparts"
make_toolchain "${NOPARTS}"
run_check "${NOPARTS}" "${TMP}/noparts.json"
row="$(manifest_row "${TMP}/noparts.json")"
case "${row}" in
    FAIL*) ;;
    *) echo "FAIL: a manifest with no parts did not fail: ${row}" >&2; exit 1 ;;
esac

# A part that is still a Git LFS pointer.
POINTER="${TMP}/tc-pointer"
make_toolchain "${POINTER}"
cat > "${POINTER}/pulseview-builder-demo.tar.part-001" <<'EOF'
version https://git-lfs.github.com/spec/v1
oid sha256:0000000000000000000000000000000000000000000000000000000000000000
size 1073741824
EOF
head -c 4096 /dev/urandom > "${POINTER}/pulseview-builder-demo.tar.part-002"
run_check "${POINTER}" "${TMP}/pointer.json"
row="$(manifest_row "${TMP}/pointer.json")"
case "${row}" in
    FAIL*) ;;
    *) echo "FAIL: a Git LFS pointer part did not fail: ${row}" >&2; exit 1 ;;
esac
case "${row}" in
    *LFS*|*lfs*) ;;
    *) echo "FAIL: the pointer failure does not name Git LFS: ${row}" >&2; exit 1 ;;
esac

printf 'build host prerequisites: all assertions passed\n'
exit 0

# END OF FILE

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-PLAT-aa8d5d46: the aarch64 AppImage delivery really is an aarch64
# AppImage. This drives a BUILT artifact - like windows_python_smoke.sh it
# exits 77 (skip) where the artifact does not exist, because "not built on
# this machine" is not a failure. What it can check without an arm64
# execution environment is the file's own identity: ELF, 64-bit, EM_AARCH64
# machine, and the type-2 AppImage magic. Actually RUNNING it (on a bare
# arm64 container, then on a physical Pi) is the manual half recorded in the
# requirement.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
AI="${REPO}/07_Delivery/PulseView-aarch64.AppImage"

if [ ! -f "${AI}" ]; then
    printf 'SKIP: %s not built\n' "${AI#${REPO}/}"
    exit 77
fi

# A clone without Git LFS leaves a ~130-byte pointer file where the binary
# should be. That is a broken checkout, not a broken build - but this test
# cannot verify anything from it, and saying "pass" would be a lie.
if head -c 40 "${AI}" | grep -q '^version https://git-lfs'; then
    printf 'SKIP: %s is an unsmudged Git LFS pointer; run git lfs pull\n' \
        "${AI#${REPO}/}"
    exit 77
fi

PY="$(command -v python3 || command -v python)" || {
    printf 'SKIP: no python available to parse the ELF header\n'; exit 77; }

"${PY}" - "${AI}" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    head = fh.read(20)

bad = 0
if head[0:4] != b"\x7fELF":
    print(f"FAIL: not an ELF file (starts {head[0:4]!r})"); bad = 1
else:
    if head[4] != 2:
        print(f"FAIL: not a 64-bit ELF (EI_CLASS={head[4]})"); bad = 1
    # Type-2 AppImages carry 'AI\x02' in the ELF padding at offset 8.
    if head[8:11] != b"AI\x02":
        print(f"FAIL: no type-2 AppImage magic at offset 8 (got {head[8:11]!r})")
        bad = 1
    machine = int.from_bytes(head[18:20], "little")
    EM_AARCH64 = 183
    if machine != EM_AARCH64:
        print(f"FAIL: ELF machine is {machine}, not EM_AARCH64 ({EM_AARCH64})")
        bad = 1

if bad:
    sys.exit(1)
print("aarch64 AppImage identity: ELF64, EM_AARCH64, type-2 AppImage magic")
PYEOF
rc=$?
[ "${rc}" -eq 0 ] || exit 1
exit 0

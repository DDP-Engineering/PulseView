#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Verify a candidate AppImage's ELF class, machine and type-2 magic.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
ARCH="${BUILDER_ARCHITECTURE:-amd64}"
DEFAULT="${REPO}/07_Delivery/PulseView-${ARCH/amd64/x86_64}.AppImage"
APPIMAGE="${APPIMAGE_PATH:-${DEFAULT}}"
[ -f "${APPIMAGE}" ] || { echo "SKIP: AppImage not built: ${APPIMAGE}"; exit 77; }
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python unavailable'; exit 77; }
"${PY}" - "${APPIMAGE}" "${ARCH}" <<'PYEOF'
import pathlib, sys
path=pathlib.Path(sys.argv[1]); arch=sys.argv[2]
with path.open("rb") as stream:
    head=stream.read(20)
if len(head) < 20 or head[:4] != b"\x7fELF" or head[4] != 2:
    raise SystemExit("FAIL: candidate is not ELF64")
if head[8:11] != b"AI\x02":
    raise SystemExit("FAIL: candidate has no type-2 AppImage magic")
expected={"amd64":62,"arm64":183}[arch]
machine=int.from_bytes(head[18:20], "little")
if machine != expected:
    raise SystemExit(f"FAIL: ELF machine {machine} != {expected} for {arch}")
print(f"AppImage identity: ELF64 type-2 {arch}")
PYEOF

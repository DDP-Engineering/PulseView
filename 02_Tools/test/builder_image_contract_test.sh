#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-PLAT-de1e172d, REQ-DATA-9654b6df: Docker contexts consume one selected
# package projection and embed canonical contract plus resolved inventory.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
BUILD="${REPO}/02_Tools/build/build_image.sh"
TOOL="${REPO}/02_Tools/build/dependency_contract.py"
APP_DOCKERFILE="${REPO}/02_Tools/build/images/Dockerfile.appimage"
MINGW_DOCKERFILE="${REPO}/02_Tools/build/images/Dockerfile.mingw"
CONTEXT="${REPO}/.work/build-context/appimage"
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python is unavailable' >&2; exit 77; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/engine-stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/bin/engine-stub"

# Resolved package inventory is canonical and rejects duplicate package keys.
printf 'zlib1g\t1:1.2.13\tamd64\ncmake\t3.25.1\tamd64\n' \
    | "${PY}" "${TOOL}" inventory --output "${TMP}/inventory.json" >/dev/null
"${PY}" - "${TMP}/inventory.json" <<'PYEOF'
import json
import pathlib
import sys
p=pathlib.Path(sys.argv[1]); raw=p.read_bytes(); data=json.loads(raw)
assert raw.endswith(b"\n")
assert data == {
    "packages": [
        {"architecture": "amd64", "name": "cmake", "version": "3.25.1"},
        {"architecture": "amd64", "name": "zlib1g", "version": "1:1.2.13"},
    ],
    "schema": 1,
}
PYEOF
if printf 'cmake\t1\tamd64\ncmake\t2\tamd64\n' \
    | "${PY}" "${TOOL}" inventory --output "${TMP}/duplicate.json" \
        >/dev/null 2>&1; then
    echo 'FAIL: duplicate resolved package was accepted' >&2
    exit 1
fi
[ ! -e "${TMP}/duplicate.json" ] \
    || { echo 'FAIL: rejected inventory left output' >&2; exit 1; }

rm -rf "${CONTEXT}"
PATH="${TMP}/bin:${PATH}" bash "${BUILD}" --image appimage --platform amd64 \
    --engine engine-stub --dry-run >"${TMP}/dry-run.out"

for file in dependency-contract.json direct-packages.txt dependency_contract.py; do
    [ -f "${CONTEXT}/${file}" ] \
        || { echo "FAIL: build context misses ${file}" >&2; exit 1; }
done
# The canonical contract carries its selected architecture and package list.
"${PY}" - "${CONTEXT}/dependency-contract.json" "${CONTEXT}/direct-packages.txt" <<'PYEOF'
import json
import pathlib
import sys
contract=json.loads(pathlib.Path(sys.argv[1]).read_text())
packages=pathlib.Path(sys.argv[2]).read_text().splitlines()
assert contract["architecture"] == "amd64"
assert packages == sorted(item["name"] for item in contract["direct_package"])
assert "xvfb" in packages and "xauth" in packages
PYEOF

for dockerfile in "${APP_DOCKERFILE}" "${MINGW_DOCKERFILE}"; do
    grep -q 'COPY direct-packages.txt' "${dockerfile}" \
        || { echo "FAIL: $(basename "${dockerfile}") does not consume package projection" >&2; exit 1; }
    grep -q 'dependency-contract.json' "${dockerfile}" \
        || { echo "FAIL: $(basename "${dockerfile}") does not embed contract" >&2; exit 1; }
    grep -q 'resolved-inventory.json' "${dockerfile}" \
        || { echo "FAIL: $(basename "${dockerfile}") does not create inventory" >&2; exit 1; }
    grep -q 'xargs.*apt-get install' "${dockerfile}" \
        || { echo "FAIL: $(basename "${dockerfile}") does not install generated packages" >&2; exit 1; }
done

if grep -q 'autoconf automake autoconf-archive' "${APP_DOCKERFILE}" \
   || grep -q 'autoconf automake autoconf-archive' "${MINGW_DOCKERFILE}"; then
    echo 'FAIL: a Dockerfile still carries the independent package list' >&2
    exit 1
fi
if grep -q 'org.opencontainers.image.licenses="GPL-3.0-or-later"' \
        "${APP_DOCKERFILE}" "${MINGW_DOCKERFILE}"; then
    echo 'FAIL: aggregate builder image is mislabeled as wholly project-licensed' >&2
    exit 1
fi
grep -q -- 'status --porcelain --untracked-files=all' "${BUILD}" \
    || { echo 'FAIL: cached MXE source is not checked for drift' >&2; exit 1; }
grep -q 'builder-base-ubuntu-22.04' \
    "${REPO}/02_Tools/test/appimage_runtime_smoke.sh" \
    || { echo 'FAIL: AppImage runtime gate does not use the pinned clean base' >&2; exit 1; }
! grep -q 'APPIMAGE_RUNTIME_IMAGE:-ubuntu:22.04' \
    "${REPO}/02_Tools/test/appimage_runtime_smoke.sh" \
    || { echo 'FAIL: AppImage runtime gate still defaults to a floating tag' >&2; exit 1; }

printf 'builder image contract: all assertions passed\n'

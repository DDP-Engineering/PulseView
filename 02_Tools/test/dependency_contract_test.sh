#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-DATA-1730e5fb, REQ-PLAT-de1e172d: dependency contracts are strict,
# architecture-selected, deterministic, and the sole direct-package source.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
TOOL="${REPO}/02_Tools/build/dependency_contract.py"

[ -f "${TOOL}" ] || {
    echo 'FAIL: dependency_contract.py is missing' >&2
    exit 1
}

PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python is unavailable' >&2
    exit 77
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat >"${TMP}/lock.toml" <<'EOF'
schema = 1
[[artifact]]
name = "runtime-amd64"
version = "1"
url = "https://example.invalid/runtime"
sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EOF

cat >"${TMP}/contract.toml" <<'EOF'
schema = 1
image = "appimage"

[[direct_package]]
name = "zlib1g-dev"

[[direct_package]]
name = "cmake"

[[direct_package]]
name = "amd64-only"
architectures = ["amd64"]

[[direct_package]]
name = "arm64-only"
architectures = ["arm64"]

[[command]]
name = "cmake"
version_args = ["--version"]
version_regex = "^cmake version"
level = "quick"

[[pkg_config]]
name = "libusb-1.0"
min_version = "1.0.0"

[[header]]
path = "/usr/include/libusb-1.0/libusb.h"

[[library]]
name = "libusb"
language = "c"
header = "libusb-1.0/libusb.h"
symbol = "libusb_init"
pkg_config = "libusb-1.0"

[[file]]
path = "/usr/local/lib/appimage/runtime"
sha256_artifact = "runtime-amd64"
architectures = ["amd64"]
level = "quick"

[[target_output]]
name = "example"
path = "/opt/example/output.a"

[[feature]]
name = "driver"
probe = "driver-list"
expected = "hantek-dso3062l"
level = "full"
EOF

normalize() {
    "${PY}" "${TOOL}" normalize \
        --contract "$1" --image "$2" --platform "$3" \
        --lock "${TMP}/lock.toml" --output "$4" \
        --packages-output "$5" >/dev/null
}

normalize "${TMP}/contract.toml" appimage x86_64 \
    "${TMP}/amd64.json" "${TMP}/amd64.packages"
normalize "${TMP}/contract.toml" appimage linux/amd64 \
    "${TMP}/amd64-again.json" "${TMP}/amd64-again.packages"
cmp -s "${TMP}/amd64.json" "${TMP}/amd64-again.json" \
    || { echo 'FAIL: equivalent architecture spellings changed output' >&2; exit 1; }

cat >"${TMP}/expected.packages" <<'EOF'
amd64-only
cmake
zlib1g-dev
EOF
cmp -s "${TMP}/expected.packages" "${TMP}/amd64.packages" \
    || { echo 'FAIL: direct-package projection is not selected and sorted' >&2; exit 1; }

"${PY}" - "${TMP}/amd64.json" <<'PYEOF'
import hashlib
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = path.read_bytes()
assert raw.endswith(b"\n")
data = json.loads(raw)
assert data["schema"] == 1
assert data["image"] == "appimage"
assert data["architecture"] == "amd64"
assert [item["name"] for item in data["direct_package"]] == [
    "amd64-only", "cmake", "zlib1g-dev"
]
assert data["pkg_config"][0]["level"] == "standard"
assert data["feature"][0]["level"] == "full"
assert len(hashlib.sha256(raw).hexdigest()) == 64
PYEOF

# Editing an unselected architecture must not change amd64 normalized bytes.
cp "${TMP}/contract.toml" "${TMP}/irrelevant.toml"
printf '\n[[command]]\nname = "arm-extra"\narchitectures = ["arm64"]\n' \
    >>"${TMP}/irrelevant.toml"
normalize "${TMP}/irrelevant.toml" appimage amd64 \
    "${TMP}/irrelevant.json" "${TMP}/irrelevant.packages"
cmp -s "${TMP}/amd64.json" "${TMP}/irrelevant.json" \
    || { echo 'FAIL: unselected architecture changed normalized bytes' >&2; exit 1; }

normalize "${TMP}/irrelevant.toml" appimage aarch64 \
    "${TMP}/arm64.json" "${TMP}/arm64.packages"
grep -qx 'arm64-only' "${TMP}/arm64.packages" \
    || { echo 'FAIL: arm64 package was not selected' >&2; exit 1; }
! grep -qx 'amd64-only' "${TMP}/arm64.packages" \
    || { echo 'FAIL: amd64 package leaked into arm64' >&2; exit 1; }

expect_rejected() {
    local label="$1" contract="$2"
    rm -f "${TMP}/bad.json" "${TMP}/bad.packages"
    if normalize "${contract}" appimage amd64 \
        "${TMP}/bad.json" "${TMP}/bad.packages" >/dev/null 2>&1; then
        echo "FAIL: ${label} was accepted" >&2
        exit 1
    fi
    [ ! -e "${TMP}/bad.json" ] && [ ! -e "${TMP}/bad.packages" ] || {
        echo "FAIL: ${label} left usable output" >&2
        exit 1
    }
}

cp "${TMP}/contract.toml" "${TMP}/bad-version.toml"
"${PY}" - "${TMP}/bad-version.toml" <<'PYEOF'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("schema = 1", "schema = 99", 1))
PYEOF
expect_rejected 'unsupported schema' "${TMP}/bad-version.toml"

cp "${TMP}/contract.toml" "${TMP}/unknown-top.toml"
printf '\nunknown = true\n' >>"${TMP}/unknown-top.toml"
expect_rejected 'unknown top-level field' "${TMP}/unknown-top.toml"

cp "${TMP}/contract.toml" "${TMP}/unknown-entry.toml"
printf '\n[[command]]\nname = "bad"\nextra = true\n' >>"${TMP}/unknown-entry.toml"
expect_rejected 'unknown entry field' "${TMP}/unknown-entry.toml"

cp "${TMP}/contract.toml" "${TMP}/duplicate.toml"
printf '\n[[command]]\nname = "cmake"\n' >>"${TMP}/duplicate.toml"
expect_rejected 'duplicate semantic key' "${TMP}/duplicate.toml"

cp "${TMP}/contract.toml" "${TMP}/bad-lock.toml"
printf '\n[[file]]\npath = "/tmp/missing"\nsha256_artifact = "absent"\n' \
    >>"${TMP}/bad-lock.toml"
expect_rejected 'unknown lock artifact' "${TMP}/bad-lock.toml"

if "${PY}" "${TOOL}" normalize --contract "${TMP}/contract.toml" \
    --image mingw --platform arm64 --lock "${TMP}/lock.toml" \
    --output "${TMP}/wrong.json" >/dev/null 2>&1; then
    echo 'FAIL: arm64 MinGW contract selection was accepted' >&2
    exit 1
fi

# The repository contracts must validate for every supported variant.
for item in 'mingw amd64' 'appimage amd64' 'appimage arm64'; do
    set -- ${item}
    contract="${REPO}/02_Tools/build/images/dependencies.$1.toml"
    "${PY}" "${TOOL}" normalize --contract "${contract}" \
        --image "$1" --platform "$2" \
        --lock "${REPO}/02_Tools/upstream/upstreams.lock.toml" \
        --output "${TMP}/repo-$1-$2.json" \
        --packages-output "${TMP}/repo-$1-$2.packages" >/dev/null
done

printf 'dependency contract: all assertions passed\n'

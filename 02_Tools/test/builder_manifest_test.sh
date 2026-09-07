#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-DATA-0bfdaf73, REQ-DATA-c1cbc4a8: strict schema-2 lifecycle manifests
# retain schema-1 read compatibility and verify all referenced bytes.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
TOOL="${REPO}/02_Tools/build/builder_manifest.py"
[ -f "${TOOL}" ] || { echo 'FAIL: builder_manifest.py is missing' >&2; exit 1; }
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python unavailable' >&2; exit 77; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

printf 'archive bytes\n' >"${TMP}/builder.tar"
split -b 5 -d -a 3 --additional-suffix='' "${TMP}/builder.tar" "${TMP}/part-"
printf '{"schema":1}\n' >"${TMP}/contract.json"
printf '{"packages":[],"schema":1}\n' >"${TMP}/inventory.json"
SHA_A="$(printf a | sha256sum | cut -d' ' -f1)"
SHA_B="$(printf b | sha256sum | cut -d' ' -f1)"
SHA_C="$(sha256sum "${TMP}/contract.json" | cut -d' ' -f1)"
SHA_D="$(printf d | sha256sum | cut -d' ' -f1)"
"${PY}" "${REPO}/02_Tools/build/generate_builder_sbom.py" generate \
    --inventory "${TMP}/inventory.json" --image appimage --platform amd64 \
    --image-id "${SHA_A}" --builder-recipe-spec "${SHA_B}" \
    --dependency-contract-spec "${SHA_C}" --created 2026-09-07T00:00:00Z \
    --output "${TMP}/sbom.spdx.json"

mapfile -t PARTS < <(find "${TMP}" -maxdepth 1 -name 'part-*' -type f | sort)
CREATE=(
    "${PY}" "${TOOL}" create --output "${TMP}/builder.manifest.toml"
    --image appimage --platform amd64 --install-tag stable --archive-tag candidate
    --image-id "sha256:${SHA_A}" --builder-recipe-spec "${SHA_B}"
    --dependency-contract-spec "${SHA_C}" --validation-policy-spec "${SHA_D}"
    --contract-file "${TMP}/contract.json" --inventory-file "${TMP}/inventory.json"
    --sbom-file "${TMP}/sbom.spdx.json" --archive "${TMP}/builder.tar"
)
for part in "${PARTS[@]}"; do CREATE+=(--part "${part}"); done
"${CREATE[@]}"
cp "${TMP}/builder.manifest.toml" "${TMP}/first.manifest.toml"
"${CREATE[@]}"
cmp "${TMP}/first.manifest.toml" "${TMP}/builder.manifest.toml"

"${PY}" "${TOOL}" verify --manifest "${TMP}/builder.manifest.toml" --mode metadata >/dev/null
"${PY}" "${TOOL}" verify --manifest "${TMP}/builder.manifest.toml" --mode archive \
    --reconstructed-output "${TMP}/reconstructed.tar" >/dev/null
cmp "${TMP}/builder.tar" "${TMP}/reconstructed.tar"

# Archive and part hashing must stream. Real MinGW generations are several
# gigabytes, so Path.read_bytes() would require unreasonable peak memory.
"${PY}" - "${TOOL}" "${TMP}/builder.tar" <<'PYEOF'
import hashlib
import importlib.util
from pathlib import Path
import sys

tool = Path(sys.argv[1])
archive = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("builder_manifest", tool)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
expected = hashlib.sha256(archive.open("rb").read()).hexdigest()
original = Path.read_bytes

def forbidden_read_bytes(self):
    raise AssertionError(f"non-streaming read attempted: {self}")

Path.read_bytes = forbidden_read_bytes
try:
    artifact = module.file_artifact(archive)
    assert artifact["sha256"] == expected
    module.verify_one(archive.parent, artifact, "archive fixture")
finally:
    Path.read_bytes = original
PYEOF

"${PY}" "${TOOL}" read --manifest "${TMP}/builder.manifest.toml" \
    --format json >"${TMP}/manifest.json"
"${PY}" - "${TMP}/manifest.json" <<'PYEOF'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert m["schema"] == 2 and not m["legacy"]
assert m["image"] == "appimage" and m["architecture"] == "amd64"
assert len(m["part"]) == 3
for key in ("builder_recipe_spec", "dependency_contract_spec", "validation_policy_spec",
            "normalized_contract_sha256", "resolved_inventory_sha256", "sbom_sha256"):
    assert len(m[key]) == 64, key
PYEOF

# Every strictness failure leaves no requested output.
assert_rejected() {
    local label="$1" manifest="$2"
    rm -f "${TMP}/bad.json"
    if "${PY}" "${TOOL}" read --manifest "${manifest}" --format json \
        --output "${TMP}/bad.json" >/dev/null 2>&1; then
        echo "FAIL: ${label} was accepted" >&2
        exit 1
    fi
    [ ! -e "${TMP}/bad.json" ] || { echo "FAIL: ${label} left output" >&2; exit 1; }
}

cp "${TMP}/builder.manifest.toml" "${TMP}/unknown.toml"
printf '\nunknown = true\n' >>"${TMP}/unknown.toml"
assert_rejected 'unknown schema-2 field' "${TMP}/unknown.toml"
cp "${TMP}/builder.manifest.toml" "${TMP}/traversal.toml"
"${PY}" - "${TMP}/traversal.toml" <<'PYEOF'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('file = "part-000"','file = "../part-000"',1))
PYEOF
assert_rejected 'path traversal' "${TMP}/traversal.toml"
cp "${TMP}/builder.manifest.toml" "${TMP}/duplicate.toml"
cat >>"${TMP}/duplicate.toml" <<EOF

[[part]]
file = "part-000"
size = 5
sha256 = "${SHA_A}"
EOF
assert_rejected 'duplicate part name' "${TMP}/duplicate.toml"

# Existing schema-1 manifests remain readable and verifiable as legacy data.
cp "${REPO}/07_Delivery/toolchain/pulseview-builder-appimage.manifest.toml" \
    "${TMP}/legacy.manifest.toml"
cp "${REPO}/07_Delivery/toolchain/pulseview-builder-appimage.tar.part-001" "${TMP}/"
"${PY}" "${TOOL}" read --manifest "${TMP}/legacy.manifest.toml" --format json \
    >"${TMP}/legacy.json"
"${PY}" - "${TMP}/legacy.json" <<'PYEOF'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert m["schema"] == 1 and m["legacy"]
assert m["builder_recipe_spec"] is None
PYEOF
"${PY}" "${TOOL}" verify --manifest "${TMP}/legacy.manifest.toml" --mode archive \
    --reconstructed-output "${TMP}/legacy.tar" >/dev/null

# Tampering with any referenced schema-2 artifact is detected.
printf x >>"${TMP}/inventory.json"
if "${PY}" "${TOOL}" verify --manifest "${TMP}/builder.manifest.toml" \
    --mode metadata >/dev/null 2>&1; then
    echo 'FAIL: changed inventory passed manifest verification' >&2
    exit 1
fi

printf 'builder manifest: all assertions passed\n'

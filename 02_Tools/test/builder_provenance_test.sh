#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-DATA-9654b6df, REQ-DATA-c1cbc4a8: resolved inventory deterministically
# produces an identity-bound SPDX 2.3 JSON document.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
TOOL="${REPO}/02_Tools/build/generate_builder_sbom.py"
[ -f "${TOOL}" ] || { echo 'FAIL: generate_builder_sbom.py is missing' >&2; exit 1; }
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python unavailable' >&2; exit 77; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat >"${TMP}/inventory.json" <<'EOF'
{"packages":[{"architecture":"amd64","name":"zlib1g","version":"1:1.2.13"},{"architecture":"all","name":"cmake-data","version":"3.25.1"}],"schema":1}
EOF
IMAGE_ID="$(printf image | sha256sum | cut -d' ' -f1)"
RECIPE="$(printf recipe | sha256sum | cut -d' ' -f1)"
CONTRACT="$(printf contract | sha256sum | cut -d' ' -f1)"
INVENTORY="$(sha256sum "${TMP}/inventory.json" | cut -d' ' -f1)"

COMMON=(
    --inventory "${TMP}/inventory.json" --image appimage --platform amd64
    --image-id "${IMAGE_ID}" --builder-recipe-spec "${RECIPE}"
    --dependency-contract-spec "${CONTRACT}"
    --created 2026-09-07T00:00:00Z
)
"${PY}" "${TOOL}" generate "${COMMON[@]}" --output "${TMP}/sbom.json"
cp "${TMP}/sbom.json" "${TMP}/first.json"
"${PY}" "${TOOL}" generate "${COMMON[@]}" --output "${TMP}/sbom.json"
cmp "${TMP}/first.json" "${TMP}/sbom.json"

"${PY}" "${TOOL}" verify "${COMMON[@]}" --sbom "${TMP}/sbom.json"
"${PY}" - "${TMP}/sbom.json" "${IMAGE_ID}" "${RECIPE}" "${CONTRACT}" "${INVENTORY}" <<'PYEOF'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); raw=p.read_bytes(); s=json.loads(raw)
assert raw.endswith(b"\n")
assert s["spdxVersion"] == "SPDX-2.3"
assert s["dataLicense"] == "CC0-1.0"
assert s["creationInfo"]["created"] == "2026-09-07T00:00:00Z"
assert [p["name"] for p in s["packages"]] == ["builder-image", "cmake-data", "zlib1g"]
identity=json.loads(s["packages"][0]["comment"])
assert identity == {
    "architecture":"amd64", "builder_recipe_spec":sys.argv[3],
    "dependency_contract_spec":sys.argv[4], "image":"appimage",
    "image_id":sys.argv[2], "resolved_inventory_sha256":sys.argv[5],
}
PYEOF

# Identity or SPDX mutation is rejected and a failed generation is atomic.
for mutation in spdx image recipe contract inventory; do
    cp "${TMP}/sbom.json" "${TMP}/${mutation}.json"
    "${PY}" - "${TMP}/${mutation}.json" "${mutation}" <<'PYEOF'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); m=sys.argv[2]; d=json.loads(p.read_text())
if m == "spdx": d["spdxVersion"]="SPDX-2.2"
else:
    i=json.loads(d["packages"][0]["comment"])
    key={"image":"image_id","recipe":"builder_recipe_spec","contract":"dependency_contract_spec","inventory":"resolved_inventory_sha256"}[m]
    i[key]="0"*64
    d["packages"][0]["comment"]=json.dumps(i,sort_keys=True,separators=(",",":"))
p.write_text(json.dumps(d,sort_keys=True,separators=(",",":"))+"\n")
PYEOF
    if "${PY}" "${TOOL}" verify "${COMMON[@]}" \
        --sbom "${TMP}/${mutation}.json" >/dev/null 2>&1; then
        echo "FAIL: ${mutation} SBOM mutation was accepted" >&2
        exit 1
    fi
done

printf '{bad json' >"${TMP}/bad-inventory.json"
printf sentinel >"${TMP}/atomic.json"
if "${PY}" "${TOOL}" generate "${COMMON[@]/${TMP}\/inventory.json/${TMP}\/bad-inventory.json}" \
    --output "${TMP}/atomic.json" >/dev/null 2>&1; then
    echo 'FAIL: malformed inventory generated an SBOM' >&2
    exit 1
fi
[ "$(cat "${TMP}/atomic.json")" = sentinel ] \
    || { echo 'FAIL: failed generation replaced output' >&2; exit 1; }

printf 'builder provenance: all assertions passed\n'

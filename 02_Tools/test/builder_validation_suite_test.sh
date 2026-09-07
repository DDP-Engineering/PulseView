#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-TEST-525b91ce: every configured mandatory probe must pass; exit 77 is a
# hard candidate failure rather than a successful skip.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
TOOL="${REPO}/02_Tools/build/run_builder_validation.py"
VERIFIER="${REPO}/02_Tools/build/verify_builder_environment.sh"
[ -f "${TOOL}" ] || { echo 'FAIL: run_builder_validation.py is missing' >&2; exit 1; }
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python unavailable' >&2; exit 77; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/tests"
cat >"${TMP}/policy.toml" <<'EOF'
schema = 1
[[policy]]
image = "appimage"
architecture = "amd64"
mandatory_tests = ["passes", "also-passes"]
EOF
for name in passes also_passes; do
    cat >"${TMP}/tests/${name}.sh" <<'EOF'
#!/usr/bin/env bash
printf 'pass\n'
exit 0
EOF
    chmod +x "${TMP}/tests/${name}.sh"
done

policy_spec() {
    local policy="${1:-${TMP}/policy.toml}"
    PYTHONPATH="${REPO}/02_Tools/build" "${PY}" - \
        "${policy}" "${TMP}/tests" "${VERIFIER}" <<'PYEOF'
import argparse
import pathlib
import sys
import builder_identity
args = argparse.Namespace(
    policy=pathlib.Path(sys.argv[1]), image="appimage", platform="amd64",
    tests_dir=pathlib.Path(sys.argv[2]), verifier=pathlib.Path(sys.argv[3]),
)
print(builder_identity.validation_inputs(args)[1])
PYEOF
}
refresh_common() {
    POLICY_SPEC="$(policy_spec)"
    COMMON=(--policy "${TMP}/policy.toml" --policy-spec "${POLICY_SPEC}" \
        --verifier "${VERIFIER}" --image appimage --platform amd64 \
        --tests-dir "${TMP}/tests" --report "${TMP}/report.json")
}
refresh_common
"${PY}" "${TOOL}" "${COMMON[@]}"
"${PY}" - "${TMP}/report.json" <<'PYEOF'
import json, pathlib, sys
r=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r["schema"] == 1 and r["result"] == "pass"
assert len(r["validation_policy_spec"]) == 64
assert [x["role"] for x in r["tests"]] == ["passes", "also-passes"]
assert all(x["exit_code"] == 0 for x in r["tests"])
for result in r["tests"]:
    assert isinstance(result["command"], list) and result["command"]
    assert isinstance(result["runner"], dict) and result["runner"]["bash"]
    assert result["started_at"].endswith("Z")
    assert result["finished_at"].endswith("Z")
    assert pathlib.Path(sys.argv[1]).parent.joinpath(result["output_log"]).is_file()
PYEOF

if "${PY}" "${TOOL}" --policy "${TMP}/policy.toml" \
    --policy-spec "$(printf '0%.0s' {1..64})" --verifier "${VERIFIER}" \
    --image appimage --platform amd64 --tests-dir "${TMP}/tests" \
    --report "${TMP}/wrong-policy.json" >"${TMP}/wrong-policy.out" 2>&1; then
    echo 'FAIL: mandatory suite accepted a mismatched policy identity' >&2
    exit 1
fi
grep -q 'policy identity mismatch' "${TMP}/wrong-policy.out" \
    || { echo 'FAIL: policy identity mismatch was not explained' >&2; exit 1; }

cat >"${TMP}/tests/also_passes.sh" <<'EOF'
#!/usr/bin/env bash
printf 'cannot execute here\n' >&2
exit 77
EOF
chmod +x "${TMP}/tests/also_passes.sh"
refresh_common
if "${PY}" "${TOOL}" "${COMMON[@]}" >"${TMP}/skip.out" 2>&1; then
    echo 'FAIL: mandatory exit 77 was accepted' >&2
    exit 1
fi
grep -q 'exit 77' "${TMP}/skip.out" \
    || { echo 'FAIL: mandatory skip was not explained' >&2; exit 1; }
[ ! -e "${TMP}/report.json" ] \
    || { echo 'FAIL: failed mandatory suite retained a stale pass report' >&2; exit 1; }

cat >"${TMP}/tests/also_passes.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMP}/tests/also_passes.sh"
refresh_common
if "${PY}" "${TOOL}" "${COMMON[@]}" >/dev/null 2>&1; then
    echo 'FAIL: mandatory exit 1 was accepted' >&2
    exit 1
fi

# Missing, duplicate and unknown policy data are strict errors.
for fault in missing duplicate unknown; do
    cp "${TMP}/policy.toml" "${TMP}/${fault}.toml"
    case "${fault}" in
        missing) rm "${TMP}/tests/also_passes.sh" ;;
        duplicate) printf '\n[[policy]]\nimage="appimage"\narchitecture="amd64"\nmandatory_tests=["passes"]\n' >>"${TMP}/${fault}.toml" ;;
        unknown) printf '\nextra=true\n' >>"${TMP}/${fault}.toml" ;;
    esac
    if "${PY}" "${TOOL}" --policy "${TMP}/${fault}.toml" \
        --policy-spec "${POLICY_SPEC}" --verifier "${VERIFIER}" --image appimage --platform amd64 --tests-dir "${TMP}/tests" \
        --report "${TMP}/${fault}.json" >/dev/null 2>&1; then
        echo "FAIL: ${fault} policy fault was accepted" >&2
        exit 1
    fi
done

# Policy roles are identifiers, never path fragments that can escape tests-dir.
cat >"${TMP}/outside.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP}/outside.sh"
cat >"${TMP}/traversal.toml" <<'EOF'
schema = 1
[[policy]]
image = "appimage"
architecture = "amd64"
mandatory_tests = ["../outside"]
EOF
TRAVERSAL_SPEC="$(printf '0%.0s' {1..64})"
if "${PY}" "${TOOL}" --policy "${TMP}/traversal.toml" \
    --policy-spec "${TRAVERSAL_SPEC}" --verifier "${VERIFIER}" \
    --image appimage --platform amd64 --tests-dir "${TMP}/tests" \
    --report "${TMP}/traversal.json" >/dev/null 2>&1; then
    echo 'FAIL: policy role escaped the mandatory test directory' >&2
    exit 1
fi

printf 'builder validation suite: all assertions passed\n'

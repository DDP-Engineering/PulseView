#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-PLAT-e0da0179, REQ-PLAT-5d4643e0: recipe, dependency and validation
# identities have separate boundaries and remain path-independent.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
SPEC="${REPO}/02_Tools/build/builder_spec.sh"
IDENTITY="${REPO}/02_Tools/build/builder_identity.py"
PATCH_SRC="${REPO}/05_Software/sigrok-util/cross-compile/mingw"

[ -f "${IDENTITY}" ] || { echo 'FAIL: builder_identity.py is missing' >&2; exit 1; }
[ -f "${SPEC}" ] || { echo 'FAIL: builder_spec.sh is missing' >&2; exit 1; }
[ -d "${PATCH_SRC}" ] || { echo 'SKIP: sigrok-util patches not present' >&2; exit 77; }

PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python is unavailable' >&2; exit 77; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cp "${REPO}/02_Tools/upstream/upstreams.lock.toml" "${TMP}/lock.toml"
cp "${REPO}/02_Tools/build/images/dependencies.mingw.toml" "${TMP}/contract.toml"
cp "${REPO}/02_Tools/build/images/builder_profile.mingw.toml" "${TMP}/profile.toml"
cp "${REPO}/02_Tools/build/images/Dockerfile.mingw" "${TMP}/Dockerfile.mingw"
cp "${REPO}/02_Tools/build/images/Dockerfile.builder-metadata" \
    "${TMP}/Dockerfile.builder-metadata"
cp -a "${PATCH_SRC}" "${TMP}/patches"
mkdir -p "${TMP}/helpers" "${TMP}/tests"
cp "${REPO}/02_Tools/build/images/mxe-build.sh" "${TMP}/helpers/"
cp "${REPO}/02_Tools/build/images/mxe-glib-hold.sh" "${TMP}/helpers/"
cat >"${TMP}/verifier.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TMP}/tests/one.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TMP}/policy.toml" <<'EOF'
schema = 1
[[policy]]
image = "mingw"
architecture = "amd64"
mandatory_tests = ["one"]
EOF

# Keep test-seam overrides explicit and readable.
identity_with() {
    local lock="${LOCK_OVERRIDE:-${TMP}/lock.toml}"
    local contract="${CONTRACT_OVERRIDE:-${TMP}/contract.toml}"
    local profile="${PROFILE_OVERRIDE:-${TMP}/profile.toml}"
    local dockerfile="${DOCKERFILE_OVERRIDE:-${TMP}/Dockerfile.mingw}"
    local metadata="${METADATA_OVERRIDE:-${TMP}/Dockerfile.builder-metadata}"
    local helpers="${HELPERS_OVERRIDE:-${TMP}/helpers}"
    local patches="${PATCHES_OVERRIDE:-${TMP}/patches}"
    local policy="${POLICY_OVERRIDE:-${TMP}/policy.toml}"
    local verifier="${VERIFIER_OVERRIDE:-${TMP}/verifier.sh}"
    local tests="${TESTS_OVERRIDE:-${TMP}/tests}"
    "${PY}" "${IDENTITY}" all --image mingw --platform amd64 \
        --lock "${lock}" --contract "${contract}" --profile "${profile}" \
        --dockerfile "${dockerfile}" --metadata-dockerfile "${metadata}" \
        --helpers-dir "${helpers}" --patch-dir "${patches}" --policy "${policy}" \
        --verifier "${verifier}" --tests-dir "${tests}"
}

field() {
    "${PY}" -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

BASE_JSON="$(identity_with)"
BASE_RECIPE="$(printf '%s' "${BASE_JSON}" | field builder_recipe_spec)"
BASE_CONTRACT="$(printf '%s' "${BASE_JSON}" | field dependency_contract_spec)"
BASE_POLICY="$(printf '%s' "${BASE_JSON}" | field validation_policy_spec)"
[ "${#BASE_RECIPE}" -eq 64 ] && [ "${#BASE_CONTRACT}" -eq 64 ] \
    && [ "${#BASE_POLICY}" -eq 64 ] \
    || { echo 'FAIL: one identity is not SHA-256 shaped' >&2; exit 1; }
[ "$(identity_with)" = "${BASE_JSON}" ] \
    || { echo 'FAIL: unchanged identities are not deterministic' >&2; exit 1; }

assert_recipe_change() {
    local label="$1" json="$2"
    [ "$(printf '%s' "${json}" | field builder_recipe_spec)" != "${BASE_RECIPE}" ] \
        || { echo "FAIL: ${label} did not change recipe identity" >&2; exit 1; }
}

assert_recipe_same() {
    local label="$1" json="$2"
    [ "$(printf '%s' "${json}" | field builder_recipe_spec)" = "${BASE_RECIPE}" ] \
        || { echo "FAIL: ${label} changed recipe identity" >&2; exit 1; }
}

# Selected contract data changes contract and recipe identities.
cp "${TMP}/contract.toml" "${TMP}/contract-changed.toml"
printf '\n[[command]]\nname = "new-tool"\n' >>"${TMP}/contract-changed.toml"
CONTRACT_OVERRIDE="${TMP}/contract-changed.toml" changed="$(identity_with)"
unset CONTRACT_OVERRIDE
assert_recipe_change 'selected contract' "${changed}"
[ "$(printf '%s' "${changed}" | field dependency_contract_spec)" != "${BASE_CONTRACT}" ] \
    || { echo 'FAIL: selected contract did not change contract identity' >&2; exit 1; }

# An unselected architecture section changes neither selected identity.
cp "${TMP}/contract.toml" "${TMP}/contract-arm.toml"
printf '\n[[command]]\nname = "arm-only"\narchitectures = ["arm64"]\n' \
    >>"${TMP}/contract-arm.toml"
CONTRACT_OVERRIDE="${TMP}/contract-arm.toml" irrelevant="$(identity_with)"
unset CONTRACT_OVERRIDE
assert_recipe_same 'unselected architecture' "${irrelevant}"
[ "$(printf '%s' "${irrelevant}" | field dependency_contract_spec)" = "${BASE_CONTRACT}" ] \
    || { echo 'FAIL: unselected architecture changed contract identity' >&2; exit 1; }

# Relevant Dockerfile, metadata finalizer, helper, profile and selected patch
# bytes change recipe.
for item in docker metadata helper profile patch; do
    case "${item}" in
        docker)
            cp "${TMP}/Dockerfile.mingw" "${TMP}/Dockerfile.changed"
            printf '\n# recipe change\n' >>"${TMP}/Dockerfile.changed"
            DOCKERFILE_OVERRIDE="${TMP}/Dockerfile.changed" value="$(identity_with)"
            unset DOCKERFILE_OVERRIDE ;;
        metadata)
            cp "${TMP}/Dockerfile.builder-metadata" "${TMP}/metadata.changed"
            printf '\n# recipe change\n' >>"${TMP}/metadata.changed"
            METADATA_OVERRIDE="${TMP}/metadata.changed" value="$(identity_with)"
            unset METADATA_OVERRIDE ;;
        helper)
            cp -a "${TMP}/helpers" "${TMP}/helpers-changed"
            printf '\n# recipe change\n' >>"${TMP}/helpers-changed/mxe-build.sh"
            HELPERS_OVERRIDE="${TMP}/helpers-changed" value="$(identity_with)"
            unset HELPERS_OVERRIDE ;;
        profile)
            cp "${TMP}/profile.toml" "${TMP}/profile-changed.toml"
            "${PY}" - "${TMP}/profile-changed.toml" <<'PYEOF'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('qt5_freeze = false','qt5_freeze = true'))
PYEOF
            PROFILE_OVERRIDE="${TMP}/profile-changed.toml" value="$(identity_with)"
            unset PROFILE_OVERRIDE ;;
        patch)
            cp -a "${TMP}/patches" "${TMP}/patches-changed"
            printf '\n# recipe change\n' >>"${TMP}/patches-changed/libusb1_upgrade.patch"
            PATCHES_OVERRIDE="${TMP}/patches-changed" value="$(identity_with)"
            unset PATCHES_OVERRIDE ;;
    esac
    assert_recipe_change "${item}" "${value}"
done

# A relevant consumed lock field changes recipe; unrelated lock data does not.
cp "${TMP}/lock.toml" "${TMP}/lock-relevant.toml"
"${PY}" - "${TMP}/lock-relevant.toml" <<'PYEOF'
from pathlib import Path
import sys
p=Path(sys.argv[1]); p.write_text(p.read_text().replace('version = "3.13.15"','version = "3.13.16"',1))
PYEOF
LOCK_OVERRIDE="${TMP}/lock-relevant.toml" relevant="$(identity_with)"
unset LOCK_OVERRIDE
assert_recipe_change 'relevant lock field' "${relevant}"

cp "${TMP}/lock.toml" "${TMP}/lock-unrelated.toml"
printf '\n[[artifact]]\nname = "unrelated"\nversion = "1"\nurl = "https://example.invalid/u"\nsha256 = "%064d"\n' 0 \
    >>"${TMP}/lock-unrelated.toml"
LOCK_OVERRIDE="${TMP}/lock-unrelated.toml" unrelated="$(identity_with)"
unset LOCK_OVERRIDE
assert_recipe_same 'unrelated lock entry' "${unrelated}"

# Validation-only changes alter policy identity and preserve recipe/contract.
cp "${TMP}/verifier.sh" "${TMP}/verifier-changed.sh"
printf '\n# policy change\n' >>"${TMP}/verifier-changed.sh"
VERIFIER_OVERRIDE="${TMP}/verifier-changed.sh" policy_change="$(identity_with)"
unset VERIFIER_OVERRIDE
assert_recipe_same 'verifier policy' "${policy_change}"
[ "$(printf '%s' "${policy_change}" | field dependency_contract_spec)" = "${BASE_CONTRACT}" ] \
    || { echo 'FAIL: verifier changed contract identity' >&2; exit 1; }
[ "$(printf '%s' "${policy_change}" | field validation_policy_spec)" != "${BASE_POLICY}" ] \
    || { echo 'FAIL: verifier did not change validation identity' >&2; exit 1; }

# A mandatory test's helper inputs are part of the validation policy too.
# Otherwise old evidence could survive a capture-generator behavior change.
mkdir -p "${TMP}/runtime-tests"
cp "${REPO}/02_Tools/test/appimage_runtime_smoke.sh" "${TMP}/runtime-tests/"
cp "${REPO}/02_Tools/test/gen_networking_stack_captures.py" "${TMP}/runtime-tests/"
cat >"${TMP}/runtime-policy.toml" <<'EOF'
schema = 1
[[policy]]
image = "appimage"
architecture = "amd64"
mandatory_tests = ["appimage-runtime"]
EOF
runtime_policy() {
    bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage \
        --platform amd64 --kind validation --policy "${TMP}/runtime-policy.toml" \
        --verifier "${TMP}/verifier.sh" --tests-dir "${TMP}/runtime-tests"
}
RUNTIME_POLICY="$(runtime_policy)"
printf '\n# changed fixture generation\n' \
    >>"${TMP}/runtime-tests/gen_networking_stack_captures.py"
[ "$(runtime_policy)" != "${RUNTIME_POLICY}" ] \
    || { echo 'FAIL: mandatory test helper did not change validation identity' >&2; exit 1; }
rm "${TMP}/runtime-tests/gen_networking_stack_captures.py"
if runtime_policy >/dev/null 2>&1; then
    echo 'FAIL: validation identity accepted a missing mandatory test helper' >&2
    exit 1
fi

# Location alone is irrelevant.
mkdir -p "${TMP}/copy"
cp "${TMP}/contract.toml" "${TMP}/copy/contract.toml"
CONTRACT_OVERRIDE="${TMP}/copy/contract.toml" moved="$(identity_with)"
unset CONTRACT_OVERRIDE
[ "${moved}" = "${BASE_JSON}" ] \
    || { echo 'FAIL: equivalent input location changed identities' >&2; exit 1; }

# The compatibility shell entry prints the same recipe digest by default.
SHELL_SPEC="$(bash "${SPEC}" --image mingw --platform amd64 \
    --lock "${TMP}/lock.toml" --contract "${TMP}/contract.toml" \
    --profile "${TMP}/profile.toml" --dockerfile "${TMP}/Dockerfile.mingw" \
    --helpers-dir "${TMP}/helpers" --patch-dir "${TMP}/patches")"
[ "${SHELL_SPEC}" = "${BASE_RECIPE}" ] \
    || { echo 'FAIL: builder_spec.sh compatibility digest differs' >&2; exit 1; }

printf 'builder spec identity: all assertions passed\n'

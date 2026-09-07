#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Quick and standard verification use embedded metadata and policy-keyed
# external evidence without archive access.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
VERIFY="${REPO}/02_Tools/build/verify_builder_environment.sh"
[ -f "${VERIFY}" ] || {
    echo 'FAIL: verify_builder_environment.sh is missing' >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
STATE="${TMP}/state"
mkdir -p "${STATE}"

cat >"${STATE}/contract.json" <<'EOF'
{"architecture":"amd64","command":[],"direct_package":[],"feature":[],"file":[],"header":[],"image":"appimage","library":[],"pkg_config":[],"schema":1,"target_output":[]}
EOF
cat >"${STATE}/inventory.json" <<'EOF'
{"packages":[{"architecture":"amd64","name":"cmake","version":"1"}],"schema":1}
EOF
CONTRACT_SHA="$(sha256sum "${STATE}/contract.json" | cut -d' ' -f1)"
INVENTORY_SHA="$(sha256sum "${STATE}/inventory.json" | cut -d' ' -f1)"
RECIPE_SHA="$(printf recipe | sha256sum | cut -d' ' -f1)"
POLICY_A="$(printf policy-a | sha256sum | cut -d' ' -f1)"
POLICY_B="$(printf policy-b | sha256sum | cut -d' ' -f1)"
export STATE CONTRACT_SHA INVENTORY_SHA RECIPE_SHA

ENGINE="${TMP}/engine"
cat >"${ENGINE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${STATE}/calls"
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
    format=""
    while [ $# -gt 0 ]; do
        [ "$1" = --format ] && { format="$2"; break; }
        shift
    done
    case "${format}" in
        '{{.Id}}|{{.Architecture}}') echo 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|amd64' ;;
        '{{index .Config.Labels "io.ddp.builder.image"}}') echo 'appimage' ;;
        '{{index .Config.Labels "io.ddp.builder.recipe-spec"}}') echo "${RECIPE_SHA}" ;;
        '{{index .Config.Labels "io.ddp.builder.dependency-contract-spec"}}') echo "${CONTRACT_SHA}" ;;
        '{{index .Config.Labels "io.ddp.builder.normalized-contract-sha256"}}') echo "${CONTRACT_SHA}" ;;
        '{{index .Config.Labels "io.ddp.builder.resolved-inventory-sha256"}}') echo "${INVENTORY_SHA}" ;;
        *) exit 2 ;;
    esac
    exit 0
fi
if [ "${1:-}" = run ]; then
    case "$*" in
        *'cat /usr/local/share/pulseview-builder/dependency-contract.json'*)
            cat "${STATE}/contract.json" ;;
        *'cat /usr/local/share/pulseview-builder/resolved-inventory.json'*)
            cat "${STATE}/inventory.json" ;;
        *verify_dependency_contract.py*)
            [ ! -f "${STATE}/fail-contract" ] ;;
        *) exit 2 ;;
    esac
    exit 0
fi
exit 2
EOF
chmod +x "${ENGINE}"

RECORDS="${TMP}/records"
COMMON=(
    --image appimage --platform amd64 --tag candidate
    --engine "${ENGINE}" --expected-recipe "${RECIPE_SHA}"
    --expected-contract "${CONTRACT_SHA}" --record-root "${RECORDS}"
)

bash "${VERIFY}" "${COMMON[@]}" --level standard \
    --validation-policy-spec "${POLICY_A}" >/dev/null
RECORD_A="${RECORDS}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/${POLICY_A}.json"
[ -f "${RECORD_A}" ] || { echo 'FAIL: standard verification wrote no evidence' >&2; exit 1; }

grep -q -- '--network none' "${STATE}/calls" \
    || { echo 'FAIL: contract verification was not offline' >&2; exit 1; }

# Quick selection uses current evidence and never looks for a manifest or part.
rm -f "${STATE}/calls"
bash "${VERIFY}" "${COMMON[@]}" --level quick \
    --validation-policy-spec "${POLICY_A}" >/dev/null
! grep -qi 'manifest\|part-' "${STATE}/calls" \
    || { echo 'FAIL: quick verification touched archive state' >&2; exit 1; }

# A policy change requires standard revalidation, not an image build.
if bash "${VERIFY}" "${COMMON[@]}" --level quick \
    --validation-policy-spec "${POLICY_B}" >"${TMP}/stale.out" 2>&1; then
    echo 'FAIL: quick verification accepted stale policy evidence' >&2
    exit 1
fi
grep -qi 'revalidation' "${TMP}/stale.out" \
    || { echo 'FAIL: stale policy did not request revalidation' >&2; exit 1; }
! grep -q '^build ' "${STATE}/calls" \
    || { echo 'FAIL: policy change invoked an image build' >&2; exit 1; }

bash "${VERIFY}" "${COMMON[@]}" --level standard \
    --validation-policy-spec "${POLICY_B}" >/dev/null
[ -f "${RECORDS}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/${POLICY_B}.json" ] \
    || { echo 'FAIL: revalidation did not create new policy evidence' >&2; exit 1; }

# Contract failure must not create passing evidence.
POLICY_C="$(printf policy-c | sha256sum | cut -d' ' -f1)"
: >"${STATE}/fail-contract"
if bash "${VERIFY}" "${COMMON[@]}" --level standard \
    --validation-policy-spec "${POLICY_C}" >/dev/null 2>&1; then
    echo 'FAIL: failed contract verification passed' >&2
    exit 1
fi
[ ! -e "${RECORDS}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/${POLICY_C}.json" ] \
    || { echo 'FAIL: failed verification left pass evidence' >&2; exit 1; }
rm -f "${STATE}/fail-contract"

# Historical mode omits current expected identities and verifies the embedded
# generation contract/inventory under its recorded policy.
HISTORICAL_RECORDS="${TMP}/historical-records"
bash "${VERIFY}" --image appimage --platform amd64 --tag candidate \
    --engine "${ENGINE}" --level standard \
    --validation-policy-spec "${POLICY_A}" \
    --record-root "${HISTORICAL_RECORDS}" >/dev/null
[ -f "${HISTORICAL_RECORDS}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/${POLICY_A}.json" ] \
    || { echo 'FAIL: historical embedded-contract verification left no evidence' >&2; exit 1; }

# Every semantic mismatch rejects the image.
for field in recipe contract image; do
    args=("${COMMON[@]}")
    case "${field}" in
        recipe) args+=(--expected-recipe "$(printf wrong | sha256sum | cut -d' ' -f1)") ;;
        contract) args+=(--expected-contract "$(printf wrong | sha256sum | cut -d' ' -f1)") ;;
        image) args[1]=mingw ;;
    esac
    if bash "${VERIFY}" "${args[@]}" --level standard \
        --validation-policy-spec "${POLICY_C}" >/dev/null 2>&1; then
        echo "FAIL: ${field} mismatch was accepted" >&2
        exit 1
    fi
done

printf 'builder environment verifier: all assertions passed\n'

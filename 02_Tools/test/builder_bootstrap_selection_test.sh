#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-REL-a6360bb2, REQ-PLAT-5d4643e0: current installed-image selection is
# independent of archive availability and policy-only staleness revalidates.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
ENSURE="${REPO}/02_Tools/bootstrap/ensure_build_environment.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/state"
RECIPE="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind recipe)"
CONTRACT="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind contract)"
POLICY="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind validation)"
export TEST_STATE="${TMP}/state" RECIPE CONTRACT POLICY
printf current >"${TEST_STATE}/mode"

cat >"${TMP}/engine" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_STATE}/engine-calls"
[ "$1" = image ] && [ "$2" = inspect ] || exit 2
mode="$(cat "${TEST_STATE}/mode")"
format=""
while [ $# -gt 0 ]; do [ "$1" = --format ] && { format="$2"; break; }; shift; done
case "${format}" in
    '') exit 0 ;;
    '{{.Id}}|{{.Architecture}}')
        [ "${mode}" = wrong-arch ] && echo 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|arm64' \
            || echo 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|amd64' ;;
    '{{index .Config.Labels "io.ddp.builder.image"}}')
        [ "${mode}" = wrong-image ] && echo mingw || echo appimage ;;
    '{{index .Config.Labels "io.ddp.builder.recipe-spec"}}')
        [ "${mode}" = wrong-recipe ] && printf '%064d\n' 0 || echo "${RECIPE}" ;;
    '{{index .Config.Labels "io.ddp.builder.dependency-contract-spec"}}')
        [ "${mode}" = wrong-contract ] && printf '%064d\n' 0 || echo "${CONTRACT}" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "${TMP}/engine"

cat >"${TMP}/verifier" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_STATE}/verify-calls"
level=""
while [ $# -gt 0 ]; do [ "$1" = --level ] && { level="$2"; break; }; shift; done
mode="$(cat "${TEST_STATE}/mode")"
if [ "${mode}" = probe-fail ]; then echo 'probe failed' >&2; exit 1; fi
if [ "${level}" = quick ] && [ "${mode}" = stale-policy ]; then
    echo 'error: revalidation required for current validation policy' >&2
    exit 1
fi
exit 0
EOF
chmod +x "${TMP}/verifier"
# Project shell scripts are mode 100644 in a fresh clone. The selector must
# invoke its verifier through Bash rather than depending on a local mode bit.
chmod -x "${TMP}/verifier"

COMMON=(--image appimage --platform amd64 --engine "${TMP}/engine" \
    --verifier-command "${TMP}/verifier" --manifest "${TMP}/does-not-exist.toml" \
    --no-rebuild)

bash "${ENSURE}" "${COMMON[@]}" >/dev/null
! grep -Eq '^(load|pull|build)([[:space:]]|$)' "${TEST_STATE}/engine-calls" \
    || { echo 'FAIL: valid installed image accessed restore/build path' >&2; exit 1; }

printf stale-policy >"${TEST_STATE}/mode"
rm -f "${TEST_STATE}/verify-calls"
bash "${ENSURE}" "${COMMON[@]}" >/dev/null
grep -q -- '--level quick' "${TEST_STATE}/verify-calls" \
    && grep -q -- '--level standard' "${TEST_STATE}/verify-calls" \
    || { echo 'FAIL: policy-only staleness did not revalidate' >&2; exit 1; }

for mode in wrong-arch wrong-image wrong-recipe wrong-contract probe-fail; do
    printf '%s' "${mode}" >"${TEST_STATE}/mode"
    if bash "${ENSURE}" "${COMMON[@]}" >"${TMP}/${mode}.out" 2>&1; then
        echo "FAIL: ${mode} image was selected" >&2
        exit 1
    fi
    grep -qi 'archive\|rebuild\|mismatch\|failed' "${TMP}/${mode}.out" \
        || { echo "FAIL: ${mode} rejection was not actionable" >&2; exit 1; }
done

printf current >"${TEST_STATE}/mode"
if bash "${ENSURE}" "${COMMON[@]}" --force-restore >/dev/null 2>&1; then
    echo 'FAIL: force restore succeeded without a manifest' >&2
    exit 1
fi

printf 'builder bootstrap selection: all assertions passed\n'

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Canonical replacement is explicit, Docker-only, serialized, exact-round-trip
# audited, and atomic.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
UPDATE="${REPO}/02_Tools/build/update_builder_environment.sh"
MANIFEST_TOOL="${REPO}/02_Tools/build/builder_manifest.py"
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python is unavailable' >&2; exit 77; }
[ -f "${UPDATE}" ] || { echo 'FAIL: update_builder_environment.sh is missing' >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin" "${TMP}/delivery" "${TMP}/work" "${TMP}/state"

OLD_ID="sha256:$(printf 'a%.0s' {1..64})"
NEW_ID="sha256:$(printf 'd%.0s' {1..64})"
STABLE_KEY="pulseview-builder-appimage_latest"

cat >"${TMP}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_LOG}/engine.log"
state="${TEST_STATE}"
if [ "$1" = image ] && [ "$2" = inspect ]; then
    tag="${@: -1}"
    key="$(printf '%s' "${tag}" | tr '/:' '__')"
    [ -f "${state}/${key}" ] || exit 1
    if printf '%s' "$*" | grep -q -- '--format'; then cat "${state}/${key}"; fi
    exit 0
fi
if [ "$1" = tag ]; then
    [ "${FAIL_STAGE:-}" != tag ] || exit 1
    source_key="$(printf '%s' "$2" | tr '/:' '__')"
    target_key="$(printf '%s' "$3" | tr '/:' '__')"
    if [ -f "${state}/${source_key}" ]; then cp "${state}/${source_key}" "${state}/${target_key}"
    else printf '%s\n' "$2" >"${state}/${target_key}"
    fi
    exit 0
fi
if [ "$1" = image ] && [ "$2" = rm ]; then
    key="$(printf '%s' "${@: -1}" | tr '/:' '__')"
    rm -f "${state}/${key}"
    exit 0
fi
if [ "$1" = volume ] && [ "$2" = rm ]; then exit 0; fi
exit 2
EOF
cp "${TMP}/bin/docker" "${TMP}/bin/podman"

cat >"${TMP}/bin/build" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${FAIL_STAGE:-}" != build ] || exit 1
printf '%s\n' "$*" >>"${TEST_LOG}/build.log"
tag=""
while [ $# -gt 0 ]; do [ "$1" = --tag ] && { tag="$2"; break; }; shift; done
[ -n "${tag}" ] || exit 2
key="$(printf '%s' "${tag}" | tr '/:' '__')"
printf '%s\n' "${NEW_ID}" >"${TEST_STATE}/${key}"
EOF
cat >"${TMP}/bin/verify" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_LOG}/verify.log"
printf '%s' "$*" | grep -q -- '--level standard' \
    && [ "${FAIL_STAGE:-}" = standard ] && exit 1
printf '%s' "$*" | grep -q -- '--level full' \
    && [ "${FAIL_STAGE:-}" = full ] && exit 1
exit 0
EOF
cat >"${TMP}/bin/representative" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${FAIL_STAGE:-}" != representative ] || exit 1
printf '%s\n' "$*" >>"${TEST_LOG}/representative.log"
out=""
while [ $# -gt 0 ]; do [ "$1" = --output-dir ] && { out="$2"; break; }; shift; done
case "${out}" in "${TEST_WORK}"/*) ;; *) exit 3 ;; esac
mkdir -p "${out}"
printf 'appimage\n' >"${out}/PulseView-x86_64.AppImage"
EOF
cat >"${TMP}/bin/save" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${FAIL_STAGE:-}" != archive ] || exit 1
printf '%s\n' "$*" >>"${TEST_LOG}/save.log"
out=""; tag=""; install=""; policy=""
while [ $# -gt 0 ]; do
    case "$1" in
        --out-dir) out="$2"; shift 2 ;;
        --tag) tag="$2"; shift 2 ;;
        --install-tag) install="$2"; shift 2 ;;
        --validation-policy-spec) policy="$2"; shift 2 ;;
        *) shift ;;
    esac
done
mkdir -p "${out}"
contract_sha="$("${PY}" "${TEST_REPO}/02_Tools/build/dependency_contract.py" normalize \
    --contract "${TEST_REPO}/02_Tools/build/images/dependencies.appimage.toml" \
    --image appimage --platform amd64 \
    --lock "${TEST_REPO}/02_Tools/upstream/upstreams.lock.toml" \
    --output "${out}/new.contract.json" \
    --packages-output "${out}/packages.txt")"
rm -f "${out}/packages.txt"
recipe_sha="$(bash "${TEST_REPO}/02_Tools/build/builder_spec.sh" \
    --image appimage --platform amd64 --kind recipe)"
printf '{}\n' >"${out}/new.inventory.json"
printf '{}\n' >"${out}/new.spdx.json"
printf 'new archive\n' >"${out}/new.tar"
cp "${out}/new.tar" "${out}/new.tar.part-001"
"${PY}" "${MANIFEST_TOOL}" create \
    --output "${out}/pulseview-builder-appimage.manifest.toml" \
    --image appimage --platform amd64 --install-tag "${install}" \
    --archive-tag "${tag}" --image-id "${NEW_ID}" \
    --builder-recipe-spec "${recipe_sha}" \
    --dependency-contract-spec "${contract_sha}" \
    --validation-policy-spec "${policy}" \
    --contract-file "${out}/new.contract.json" \
    --inventory-file "${out}/new.inventory.json" \
    --sbom-file "${out}/new.spdx.json" --archive "${out}/new.tar" \
    --part "${out}/new.tar.part-001"
rm -f "${out}/new.tar"
EOF
cat >"${TMP}/bin/audit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_LOG}/audit.log"
[ "${FAIL_STAGE:-}" != audit ] || exit 1
printf '%s' "$*" | grep -q -- "--expected-image-id ${NEW_ID}"
printf '%s' "$*" | grep -q -- '--reconstructed-output '
EOF
chmod +x "${TMP}/bin/"*
# Only the engine is an executable command. Project-owned component scripts
# are mode 100644 in a fresh clone and must be run explicitly through Bash.
chmod -x "${TMP}/bin/build" "${TMP}/bin/verify" "${TMP}/bin/save" \
    "${TMP}/bin/audit" "${TMP}/bin/representative"

export TEST_STATE="${TMP}/state"
export TEST_LOG="${TMP}/log"
export TEST_WORK="${TMP}/work"
export NEW_ID MANIFEST_TOOL PY TEST_REPO="${REPO}"
mkdir -p "${TEST_LOG}"

reset_old() {
    rm -rf "${TMP}/delivery" "${TMP}/work" "${TMP}/state" "${TEST_LOG}"
    mkdir -p "${TMP}/delivery" "${TMP}/work" "${TMP}/state" "${TEST_LOG}"
    printf '%s\n' "${OLD_ID}" >"${TMP}/state/${STABLE_KEY}"
    printf 'old archive\n' >"${TMP}/delivery/old.tar.part-001"
    old_size="$(wc -c <"${TMP}/delivery/old.tar.part-001" | tr -d ' ')"
    old_sha="$(sha256sum "${TMP}/delivery/old.tar.part-001" | cut -d' ' -f1)"
    cat >"${TMP}/delivery/pulseview-builder-appimage.manifest.toml" <<EOF
schema = 1
format = "docker-archive"
image = "appimage"
platform = "linux/amd64"
tag = "pulseview-builder-appimage:latest"
image_id = "${OLD_ID}"
builder_spec = ""
archive = "old.tar"
archive_size = ${old_size}
archive_sha256 = "${old_sha}"
[[part]]
file = "old.tar.part-001"
size = ${old_size}
sha256 = "${old_sha}"
EOF
}

COMMON=(
    --image appimage --platform amd64 --engine "${TMP}/bin/docker"
    --delivery-dir "${TMP}/delivery" --work-root "${TMP}/work"
    --build-command "${TMP}/bin/build" --verify-command "${TMP}/bin/verify"
    --save-command "${TMP}/bin/save" --audit-command "${TMP}/bin/audit"
    --representative-command "${TMP}/bin/representative"
)

assert_old() {
    [ "$(cat "${TMP}/state/${STABLE_KEY}")" = "${OLD_ID}" ] \
        || { echo "FAIL: $1 changed stable tag" >&2; exit 1; }
    grep -q '^schema = 1$' "${TMP}/delivery/pulseview-builder-appimage.manifest.toml" \
        || { echo "FAIL: $1 changed stable manifest" >&2; exit 1; }
    [ -f "${TMP}/delivery/old.tar.part-001" ] \
        || { echo "FAIL: $1 removed the old generation" >&2; exit 1; }
    [ "$(find "${TMP}/delivery" -maxdepth 1 -type f | wc -l)" -eq 2 ] \
        || { echo "FAIL: $1 left mixed generation files" >&2; exit 1; }
    [ "$(find "${TMP}/state" -type f -name '*candidate*' | wc -l)" -eq 0 ] \
        || { echo "FAIL: $1 left a candidate tag" >&2; exit 1; }
}

reset_old
if bash "${UPDATE}" "${COMMON[@]}" >/dev/null 2>&1; then
    echo 'FAIL: replacement without --replace passed' >&2
    exit 1
fi
assert_old 'missing mode'

# Plan is read-only, reports every intended identity/resource and permits an
# experimental engine because it performs no build or promotion.
rm -rf "${TMP}/plan-delivery" "${TMP}/plan-work"
bash "${UPDATE}" --plan --image appimage --platform amd64 \
    --engine "${TMP}/bin/podman" --delivery-dir "${TMP}/plan-delivery" \
    --work-root "${TMP}/plan-work" >"${TMP}/plan.out"
for field in builder_recipe_spec dependency_contract_spec validation_policy_spec \
    candidate_tag candidate_volume work_root stable_manifest superseded_files; do
    grep -q "^${field}:" "${TMP}/plan.out" \
        || { echo "FAIL: plan omits ${field}" >&2; exit 1; }
done
[ ! -e "${TMP}/plan-delivery" ] && [ ! -e "${TMP}/plan-work" ] \
    || { echo 'FAIL: plan mode changed output directories' >&2; exit 1; }
grep -Eq '^candidate_tag: .*:candidate-[0-9a-f]{12}$' "${TMP}/plan.out" \
    || { echo 'FAIL: candidate tag is not content-derived' >&2; exit 1; }

reset_old
PODMAN_COMMON=("${COMMON[@]}")
PODMAN_COMMON[5]="${TMP}/bin/podman"
if bash "${UPDATE}" --replace "${PODMAN_COMMON[@]}" >/dev/null 2>&1; then
    echo 'FAIL: canonical replacement accepted Podman' >&2
    exit 1
fi
assert_old 'Podman rejection'

# A pre-existing per-variant lock serializes concurrent replacements.
mkdir -p "${TMP}/work/locks/appimage-amd64.lock"
if bash "${UPDATE}" --replace "${COMMON[@]}" >/dev/null 2>&1; then
    echo 'FAIL: concurrent replacement acquired an occupied lock' >&2
    exit 1
fi
assert_old 'concurrent lock rejection'

for phase in build standard representative full archive audit; do
    reset_old
    if FAIL_STAGE="${phase}" bash "${UPDATE}" --replace "${COMMON[@]}" \
        >/dev/null 2>&1; then
        echo "FAIL: injected ${phase} failure passed" >&2
        exit 1
    fi
    assert_old "${phase} failure"
done

for point in promoted-file-1 promoted-file-3 files-promoted; do
    reset_old
    if bash "${UPDATE}" --replace "${COMMON[@]}" --fail-after "${point}" \
        >/dev/null 2>&1; then
        echo "FAIL: injected ${point} interruption passed" >&2
        exit 1
    fi
    assert_old "${point} interruption"
done

# The manifest is the commit point. A later local-tag failure keeps the new,
# internally complete generation and leaves the prior stable tag untouched.
reset_old
if FAIL_STAGE=tag bash "${UPDATE}" --replace "${COMMON[@]}" >/dev/null 2>&1; then
    echo 'FAIL: injected post-manifest tag failure passed' >&2
    exit 1
fi
grep -q '^schema = 2$' "${TMP}/delivery/pulseview-builder-appimage.manifest.toml" \
    || { echo 'FAIL: tag failure rolled back the committed manifest' >&2; exit 1; }
[ "$(cat "${TMP}/state/${STABLE_KEY}")" = "${OLD_ID}" ] \
    || { echo 'FAIL: tag failure damaged the prior stable tag' >&2; exit 1; }
[ -f "${TMP}/delivery/new.tar.part-001" ] \
    || { echo 'FAIL: tag failure removed the committed generation' >&2; exit 1; }

reset_old
bash "${UPDATE}" --replace "${COMMON[@]}" >"${TMP}/success.out"
[ "$(cat "${TMP}/state/${STABLE_KEY}")" = "${NEW_ID}" ] \
    || { echo 'FAIL: success did not tag the exact verified image ID' >&2; exit 1; }
grep -q '^schema = 2$' "${TMP}/delivery/pulseview-builder-appimage.manifest.toml" \
    || { echo 'FAIL: success did not commit the schema-2 manifest' >&2; exit 1; }
[ -f "${TMP}/delivery/new.tar.part-001" ] \
    && [ -f "${TMP}/delivery/new.spdx.json" ] \
    || { echo 'FAIL: success did not promote generation files' >&2; exit 1; }
[ ! -e "${TMP}/delivery/old.tar.part-001" ] \
    || { echo 'FAIL: success did not remove the superseded referenced part' >&2; exit 1; }
[ "$(find "${TMP}/state" -type f -name '*candidate*' | wc -l)" -eq 0 ] \
    || { echo 'FAIL: success left candidate tag' >&2; exit 1; }
grep -Eq -- '--tag pulseview-builder-appimage:candidate-[0-9a-f]{12}' \
    "${TEST_LOG}/build.log" \
    || { echo 'FAIL: build did not receive the content-derived candidate tag' >&2; exit 1; }
grep -q -- '--expected-image-id sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
    "${TEST_LOG}/audit.log" \
    || { echo 'FAIL: archive audit did not bind the expected image ID' >&2; exit 1; }
grep -q '^report:' "${TMP}/success.out" \
    || { echo 'FAIL: success omitted the review report path' >&2; exit 1; }
find "${TMP}/work" -type f -name reconstructed.tar -print -quit \
    | grep -q . \
    && { echo 'FAIL: success retained the multi-gigabyte reconstructed archive' >&2; exit 1; }

# Coordinator policy prohibits project Git invocation and publication actions.
if grep -Eq '(^|[;&|[:space:]])git([[:space:]]|$)' "${UPDATE}"; then
    echo 'FAIL: updater contains prohibited Git/publication command' >&2
    exit 1
fi

printf 'builder update transaction: all assertions passed\n'

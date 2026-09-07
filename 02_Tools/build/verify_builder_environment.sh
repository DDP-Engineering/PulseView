#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Verify one installed builder from embedded contract/inventory metadata. This
# command never requires an archive manifest or archive parts.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
ENGINE="docker"
IMAGE=""
PLATFORM=""
TAG=""
LEVEL="quick"
EXPECTED_RECIPE=""
EXPECTED_CONTRACT=""
POLICY_SPEC=""
RECORD_ROOT="${REPO_ROOT}/.work/builder-validation"
CONTRACT_SOURCE="embedded"
POLICY=""
TESTS_DIR="${REPO_ROOT}/02_Tools/test"
STAGE=""
APPIMAGE=""
DEB=""
SUITE_REPORT=""

usage() {
    cat <<'EOF'
Usage: verify_builder_environment.sh --image TYPE --platform ARCH --tag TAG [options]

Options:
  --level quick|standard|full
                           Probe level. Standard/full write validation evidence.
  --engine COMMAND         Container engine. Default: docker.
  --expected-recipe SHA    Require this current recipe identity.
  --expected-contract SHA  Require this current dependency-contract identity.
  --validation-policy-spec SHA
                           Required policy identity for evidence lookup/write.
  --record-root PATH       External evidence root under .work.
  --contract-source PATH   Verify an explicit normalized contract; default embedded.
  --policy PATH            Validation policy required by full verification.
  --tests-dir PATH         Mandatory test directory.
  --stage PATH             Representative staged product tree.
  --appimage PATH          Representative AppImage artifact.
  --deb PATH               Representative Debian package artifact.
  --suite-report PATH      Full mandatory-test evidence output.
  -h, --help               This text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:-}"; shift 2 ;;
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --tag) TAG="${2:-}"; shift 2 ;;
        --level) LEVEL="${2:-}"; shift 2 ;;
        --engine) ENGINE="${2:-}"; shift 2 ;;
        --expected-recipe) EXPECTED_RECIPE="${2:-}"; shift 2 ;;
        --expected-contract) EXPECTED_CONTRACT="${2:-}"; shift 2 ;;
        --validation-policy-spec) POLICY_SPEC="${2:-}"; shift 2 ;;
        --record-root) RECORD_ROOT="${2:-}"; shift 2 ;;
        --contract-source) CONTRACT_SOURCE="${2:-}"; shift 2 ;;
        --policy) POLICY="${2:-}"; shift 2 ;;
        --tests-dir) TESTS_DIR="${2:-}"; shift 2 ;;
        --stage) STAGE="${2:-}"; shift 2 ;;
        --appimage) APPIMAGE="${2:-}"; shift 2 ;;
        --deb) DEB="${2:-}"; shift 2 ;;
        --suite-report) SUITE_REPORT="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in mingw|appimage) ;; *) die "--image must be mingw or appimage" ;; esac
case "${PLATFORM}" in
    x86_64|amd64|linux/amd64) ARCH="amd64" ;;
    aarch64|arm64|linux/arm64) ARCH="arm64" ;;
    *) die "unsupported platform: ${PLATFORM}" ;;
esac
[ "${IMAGE}" != mingw ] || [ "${ARCH}" = amd64 ] \
    || die "the MinGW builder supports only amd64"
case "${LEVEL}" in quick|standard|full) ;; *) die "--level must be quick, standard, or full" ;; esac
[ -n "${TAG}" ] || die "--tag is required"
command -v "${ENGINE}" >/dev/null 2>&1 || die "container engine not found: ${ENGINE}"

is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
[ -z "${EXPECTED_RECIPE}" ] || is_sha256 "${EXPECTED_RECIPE}" \
    || die "--expected-recipe must be lowercase SHA-256"
[ -z "${EXPECTED_CONTRACT}" ] || is_sha256 "${EXPECTED_CONTRACT}" \
    || die "--expected-contract must be lowercase SHA-256"
is_sha256 "${POLICY_SPEC}" \
    || die "--validation-policy-spec must be lowercase SHA-256"

INSPECT="$("${ENGINE}" image inspect --format '{{.Id}}|{{.Architecture}}' "${TAG}")" \
    || die "image is not installed: ${TAG}"
IMAGE_ID="${INSPECT%%|*}"
ACTUAL_ARCH="${INSPECT#*|}"
IMAGE_ID="${IMAGE_ID#sha256:}"
is_sha256 "${IMAGE_ID}" || die "engine returned an invalid image ID"
[ "${ACTUAL_ARCH}" = "${ARCH}" ] \
    || die "image architecture mismatch: ${ACTUAL_ARCH} != ${ARCH}"

label() {
    "${ENGINE}" image inspect --format "{{index .Config.Labels \"$1\"}}" "${TAG}"
}

ACTUAL_IMAGE="$(label io.ddp.builder.image)"
RECIPE_SPEC="$(label io.ddp.builder.recipe-spec)"
CONTRACT_SPEC="$(label io.ddp.builder.dependency-contract-spec)"
CONTRACT_SHA="$(label io.ddp.builder.normalized-contract-sha256)"
INVENTORY_SHA="$(label io.ddp.builder.resolved-inventory-sha256)"
[ "${ACTUAL_IMAGE}" = "${IMAGE}" ] \
    || die "builder type mismatch: ${ACTUAL_IMAGE} != ${IMAGE}"
for pair in \
    "recipe identity:${RECIPE_SPEC}" \
    "contract identity:${CONTRACT_SPEC}" \
    "contract content hash:${CONTRACT_SHA}" \
    "inventory content hash:${INVENTORY_SHA}"; do
    is_sha256 "${pair#*:}" || die "image has invalid ${pair%%:*} label"
done
[ -z "${EXPECTED_RECIPE}" ] || [ "${RECIPE_SPEC}" = "${EXPECTED_RECIPE}" ] \
    || die "builder recipe identity mismatch"
[ -z "${EXPECTED_CONTRACT}" ] || [ "${CONTRACT_SPEC}" = "${EXPECTED_CONTRACT}" ] \
    || die "dependency contract identity mismatch"

TMP="$(mktemp -d "${REPO_ROOT}/.work/builder-verify.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
EMBEDDED_CONTRACT="${TMP}/dependency-contract.json"
INVENTORY="${TMP}/resolved-inventory.json"
"${ENGINE}" run --rm --network none --platform "linux/${ARCH}" "${TAG}" \
    sh -c 'cat /usr/local/share/pulseview-builder/dependency-contract.json' \
    >"${EMBEDDED_CONTRACT}"
"${ENGINE}" run --rm --network none --platform "linux/${ARCH}" "${TAG}" \
    sh -c 'cat /usr/local/share/pulseview-builder/resolved-inventory.json' \
    >"${INVENTORY}"
ACTUAL_CONTRACT_SHA="$(sha256sum "${EMBEDDED_CONTRACT}" | cut -d' ' -f1)"
ACTUAL_INVENTORY_SHA="$(sha256sum "${INVENTORY}" | cut -d' ' -f1)"
[ "${ACTUAL_CONTRACT_SHA}" = "${CONTRACT_SHA}" ] \
    || die "embedded contract does not match its image label"
[ "${ACTUAL_CONTRACT_SHA}" = "${CONTRACT_SPEC}" ] \
    || die "embedded contract does not match dependency contract identity"
[ "${ACTUAL_INVENTORY_SHA}" = "${INVENTORY_SHA}" ] \
    || die "embedded inventory does not match its image label"

VERIFY_CONTRACT="/usr/local/share/pulseview-builder/dependency-contract.json"
VOLUME_ARGS=()
if [ "${CONTRACT_SOURCE}" != embedded ]; then
    [ -f "${CONTRACT_SOURCE}" ] || die "explicit contract not found: ${CONTRACT_SOURCE}"
    EXPLICIT_SHA="$(sha256sum "${CONTRACT_SOURCE}" | cut -d' ' -f1)"
    [ "${EXPLICIT_SHA}" = "${CONTRACT_SPEC}" ] \
        || die "explicit contract does not match image contract identity"
    VOLUME_ARGS+=(--volume "${CONTRACT_SOURCE}:/tmp/explicit-contract.json:ro")
    VERIFY_CONTRACT="/tmp/explicit-contract.json"
fi

"${ENGINE}" run --rm --network none --platform "linux/${ARCH}" \
    --volume "${SCRIPT_DIR}/verify_dependency_contract.py:/tmp/verify_dependency_contract.py:ro" \
    "${VOLUME_ARGS[@]}" --entrypoint python3 "${TAG}" \
    /tmp/verify_dependency_contract.py --contract "${VERIFY_CONTRACT}" \
    --level "${LEVEL}" >/dev/null \
    || die "${LEVEL} dependency contract verification failed"

# shellcheck source=python_env.sh
. "${SCRIPT_DIR}/python_env.sh"
sr_require_python || exit 1
if [ "${LEVEL}" = full ]; then
    [ -f "${POLICY}" ] || die "full verification requires --policy"
    SUITE_REPORT="${SUITE_REPORT:-${RECORD_ROOT}/${IMAGE_ID}/${POLICY_SPEC}.suite.json}"
    SUITE_ARGS=(
        --policy "${POLICY}" --policy-spec "${POLICY_SPEC}"
        --verifier "${SCRIPT_DIR}/verify_builder_environment.sh"
        --image "${IMAGE}" --platform "${ARCH}"
        --tests-dir "${TESTS_DIR}" --report "${SUITE_REPORT}"
    )
    [ -z "${STAGE}" ] || SUITE_ARGS+=(--stage "${STAGE}")
    [ -z "${APPIMAGE}" ] || SUITE_ARGS+=(--appimage "${APPIMAGE}")
    [ -z "${DEB}" ] || SUITE_ARGS+=(--deb "${DEB}")
    BUILDER_ENGINE="${ENGINE}" BUILDER_TAG="${TAG}" \
        "${SR_PYTHON}" "${SCRIPT_DIR}/run_builder_validation.py" \
        "${SUITE_ARGS[@]}" \
        || die "full mandatory validation suite failed"
fi

RECORD="${RECORD_ROOT}/${IMAGE_ID}/${POLICY_SPEC}.json"
IDENTITY_ARGS=(
    --image-id "${IMAGE_ID}" --image "${IMAGE}" --architecture "${ARCH}"
    --recipe "${RECIPE_SPEC}" --contract "${CONTRACT_SPEC}"
    --normalized-contract "${CONTRACT_SHA}" --inventory "${INVENTORY_SHA}"
    --policy "${POLICY_SPEC}"
)
if [ "${LEVEL}" = quick ]; then
    if [ ! -f "${RECORD}" ] || ! "${SR_PYTHON}" \
        "${SCRIPT_DIR}/builder_validation_record.py" check \
        --input "${RECORD}" "${IDENTITY_ARGS[@]}" >/dev/null 2>&1; then
        die "revalidation required for current validation policy"
    fi
else
    "${SR_PYTHON}" "${SCRIPT_DIR}/builder_validation_record.py" write \
        --output "${RECORD}" --level "${LEVEL}" "${IDENTITY_ARGS[@]}"
fi

printf '%s builder %s verification passed: %s\n' "${IMAGE}" "${LEVEL}" "${TAG}"

# END OF FILE

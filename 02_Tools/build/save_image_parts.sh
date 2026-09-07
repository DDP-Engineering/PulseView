#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Save one qualified local builder as generation-specific archive parts,
# identity-bearing sidecars, SPDX 2.3 JSON, and a schema-2 manifest.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
IMAGE="mingw"
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
OUT_DIR="${REPO_ROOT}/07_Delivery/toolchain"
PART_SIZE_MIB=1024
ARCHIVE_TAG=""
INSTALL_TAG=""
POLICY_SPEC=""
FAIL_AFTER=""

usage() {
    cat <<'EOF'
Usage: save_image_parts.sh [options]

Options:
  --image mingw|appimage   Builder image. Default mingw.
  --platform ARCH          x86_64/amd64 or aarch64/arm64.
  --engine COMMAND         Container engine. Default docker.
  --tag NAME               Qualified candidate/archive tag.
  --install-tag NAME       Stable tag recorded for restore.
  --validation-policy-spec SHA
                           Policy that qualified this generation.
  --out-dir PATH           Empty destination or staging directory.
  --part-size-mib N        Part size in MiB. Default 1024.
  -h, --help               This text.

The manifest is written last. Existing manifests or generation files are never
replaced by this command.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:-}"; shift 2 ;;
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --engine) ENGINE="${2:-}"; shift 2 ;;
        --tag) ARCHIVE_TAG="${2:-}"; shift 2 ;;
        --install-tag) INSTALL_TAG="${2:-}"; shift 2 ;;
        --validation-policy-spec) POLICY_SPEC="${2:-}"; shift 2 ;;
        --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
        --part-size-mib) PART_SIZE_MIB="${2:-}"; shift 2 ;;
        # Failure seam used only by transactional fixture tests.
        --fail-after) FAIL_AFTER="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in mingw|appimage) ;; *) die "--image must be mingw or appimage" ;; esac
case "${PART_SIZE_MIB}" in ''|*[!0-9]*) die "--part-size-mib must be a positive integer" ;; esac
[ "${PART_SIZE_MIB}" -gt 0 ] || die "--part-size-mib must be greater than zero"

ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=arch_map.sh
. "${SCRIPT_DIR}/arch_map.sh"
if [ "${IMAGE}" = mingw ] && [ "${SR_ARCH}" != x86_64 ]; then
    die "the MinGW builder is available only for x86_64"
fi
TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = x86_64 ] || TAG_ARCH_SUFFIX="-arm64"
INSTALL_TAG="${INSTALL_TAG:-pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest}"
ARCHIVE_TAG="${ARCHIVE_TAG:-${INSTALL_TAG}}"
STABLE_STEM="pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}"
MANIFEST="${OUT_DIR}/${STABLE_STEM}.manifest.toml"

command -v "${ENGINE}" >/dev/null 2>&1 || die "container engine not found: ${ENGINE}"
command -v split >/dev/null 2>&1 || die "split not found"
"${ENGINE}" image inspect "${ARCHIVE_TAG}" >/dev/null 2>&1 \
    || die "image not found: ${ARCHIVE_TAG}"
mkdir -p "${OUT_DIR}"
[ ! -e "${MANIFEST}" ] || die "manifest already exists: ${MANIFEST}"

label() {
    "${ENGINE}" image inspect --format "{{index .Config.Labels \"$1\"}}" \
        "${ARCHIVE_TAG}"
}
IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${ARCHIVE_TAG}")"
IMAGE_HEX="${IMAGE_ID#sha256:}"
[[ "${IMAGE_HEX}" =~ ^[0-9a-f]{64}$ ]] || die "engine returned invalid image ID"
[ "$(label io.ddp.builder.image)" = "${IMAGE}" ] || die "builder type label mismatch"
RECIPE_SPEC="$(label io.ddp.builder.recipe-spec)"
CONTRACT_SPEC="$(label io.ddp.builder.dependency-contract-spec)"
CONTRACT_SHA="$(label io.ddp.builder.normalized-contract-sha256)"
INVENTORY_SHA="$(label io.ddp.builder.resolved-inventory-sha256)"
for pair in \
    "recipe:${RECIPE_SPEC}" "contract:${CONTRACT_SPEC}" \
    "normalized contract:${CONTRACT_SHA}" "inventory:${INVENTORY_SHA}"; do
    [[ "${pair#*:}" =~ ^[0-9a-f]{64}$ ]] || die "invalid ${pair%%:*} label"
done
[ "${CONTRACT_SPEC}" = "${CONTRACT_SHA}" ] \
    || die "contract identity and embedded content label differ"
if [ -z "${POLICY_SPEC}" ]; then
    POLICY_SPEC="$(bash "${SCRIPT_DIR}/builder_spec.sh" --image "${IMAGE}" \
        --platform "${SR_ARCH}" --kind validation)"
fi
[[ "${POLICY_SPEC}" =~ ^[0-9a-f]{64}$ ]] \
    || die "validation policy identity must be lowercase SHA-256"

GENERATION="${STABLE_STEM}-${IMAGE_HEX:0:16}"
ARCHIVE="${OUT_DIR}/${GENERATION}.tar"
PART_PREFIX="${OUT_DIR}/${GENERATION}.tar.part-"
CONTRACT_FILE="${OUT_DIR}/${GENERATION}.dependency-contract.json"
INVENTORY_FILE="${OUT_DIR}/${GENERATION}.resolved-inventory.json"
SBOM_FILE="${OUT_DIR}/${GENERATION}.spdx.json"
for path in "${ARCHIVE}" "${CONTRACT_FILE}" "${INVENTORY_FILE}" "${SBOM_FILE}"; do
    [ ! -e "${path}" ] || die "generation file already exists: ${path}"
done
if find "${OUT_DIR}" -maxdepth 1 -type f -name "${GENERATION}.tar.part-*" \
    -print -quit | grep -q .; then
    die "archive parts already exist for generation ${GENERATION}"
fi

COMPLETE=0
CONTAINER_NAME="pulseview-archive-${IMAGE_HEX:0:16}"
cleanup() {
    "${ENGINE}" rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    rm -f -- "${ARCHIVE}" "${MANIFEST}.tmp"
    # The atomic rename is the commit point. Preserve its complete referenced
    # generation if interruption precedes the following shell assignment.
    if [ "${COMPLETE}" -eq 0 ] && [ -f "${MANIFEST}" ]; then COMPLETE=1; fi
    if [ "${COMPLETE}" -eq 0 ]; then
        rm -f -- "${CONTRACT_FILE}" "${INVENTORY_FILE}" "${SBOM_FILE}"
        find "${OUT_DIR}" -maxdepth 1 -type f \
            -name "${GENERATION}.tar.part-*" -delete
    fi
}
trap cleanup EXIT

printf '==> extracting embedded lifecycle metadata\n'
"${ENGINE}" create --name "${CONTAINER_NAME}" "${ARCHIVE_TAG}" >/dev/null
"${ENGINE}" cp \
    "${CONTAINER_NAME}:/usr/local/share/pulseview-builder/dependency-contract.json" \
    "${CONTRACT_FILE}"
"${ENGINE}" cp \
    "${CONTAINER_NAME}:/usr/local/share/pulseview-builder/resolved-inventory.json" \
    "${INVENTORY_FILE}"
"${ENGINE}" rm -f "${CONTAINER_NAME}" >/dev/null
[ "$(sha256sum "${CONTRACT_FILE}" | cut -d' ' -f1)" = "${CONTRACT_SHA}" ] \
    || die "extracted contract hash does not match image label"
[ "$(sha256sum "${INVENTORY_FILE}" | cut -d' ' -f1)" = "${INVENTORY_SHA}" ] \
    || die "extracted inventory hash does not match image label"

# shellcheck source=python_env.sh
. "${SCRIPT_DIR}/python_env.sh"
sr_require_python || exit 1
CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"${SR_PYTHON}" "${SCRIPT_DIR}/generate_builder_sbom.py" generate \
    --inventory "${INVENTORY_FILE}" --image "${IMAGE}" --platform "${SR_ARCH}" \
    --image-id "${IMAGE_HEX}" --builder-recipe-spec "${RECIPE_SPEC}" \
    --dependency-contract-spec "${CONTRACT_SPEC}" --created "${CREATED}" \
    --output "${SBOM_FILE}"

printf '==> saving %s\n' "${ARCHIVE_TAG}"
"${ENGINE}" save --output "${ARCHIVE}" "${ARCHIVE_TAG}"
printf '==> splitting into %s MiB parts\n' "${PART_SIZE_MIB}"
split --bytes "${PART_SIZE_MIB}M" --numeric-suffixes=1 --suffix-length=3 \
    "${ARCHIVE}" "${PART_PREFIX}"
mapfile -t PARTS < <(find "${OUT_DIR}" -maxdepth 1 -type f \
    -name "${GENERATION}.tar.part-*" -print | sort)
[ "${#PARTS[@]}" -gt 0 ] || die "archive split produced no parts"

MANIFEST_ARGS=(
    create --output "${MANIFEST}.tmp" --image "${IMAGE}"
    --platform "${SR_ARCH}" --install-tag "${INSTALL_TAG}"
    --archive-tag "${ARCHIVE_TAG}" --image-id "${IMAGE_ID}"
    --builder-recipe-spec "${RECIPE_SPEC}"
    --dependency-contract-spec "${CONTRACT_SPEC}"
    --validation-policy-spec "${POLICY_SPEC}"
    --contract-file "${CONTRACT_FILE}" --inventory-file "${INVENTORY_FILE}"
    --sbom-file "${SBOM_FILE}" --archive "${ARCHIVE}"
)
for part in "${PARTS[@]}"; do MANIFEST_ARGS+=(--part "${part}"); done
"${SR_PYTHON}" "${SCRIPT_DIR}/builder_manifest.py" "${MANIFEST_ARGS[@]}"
"${SR_PYTHON}" "${SCRIPT_DIR}/builder_manifest.py" verify \
    --manifest "${MANIFEST}.tmp" --mode archive >/dev/null
mv -- "${MANIFEST}.tmp" "${MANIFEST}"
[ "${FAIL_AFTER}" != manifest-committed ] \
    || die "injected interruption after manifest commit"
COMPLETE=1
rm -f -- "${ARCHIVE}"

printf '==> wrote %s generation parts and %s\n' "${#PARTS[@]}" "${MANIFEST}"
printf '    local files only; publishing is the developer\047s responsibility\n'

# END OF FILE

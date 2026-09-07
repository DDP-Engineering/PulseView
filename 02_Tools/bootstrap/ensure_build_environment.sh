#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Select a current installed builder first; only archive restore and an
# explicitly allowed online rebuild depend on delivery files.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/02_Tools/build"
TOOLCHAIN_DIR="${REPO_ROOT}/07_Delivery/toolchain"
IMAGE="mingw"
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
MANIFEST=""
REBUILD_MODE="ask"
FORCE_RESTORE=0
ALLOW_LEGACY=0
ALLOW_HISTORICAL=0
VERIFIER_COMMAND="${BUILD_DIR}/verify_builder_environment.sh"

usage() {
    cat <<'EOF'
Usage: ensure_build_environment.sh [options]

Options:
  --image mingw|appimage   Builder image. Default mingw.
  --platform ARCH          amd64/x86_64 or arm64/aarch64. Default host.
  --engine COMMAND         Container engine. Default docker.
  --manifest PATH          Override the stable archive manifest.
  --force-restore          Bypass installed-image selection.
  --allow-legacy-restore   Explicitly restore a schema-1 archive without
                           treating it as a current verified builder.
  --allow-historical-builder
                           Explicitly restore and verify a stale schema-2 image.
  --rebuild                Rebuild online without prompting if needed.
  --no-rebuild             Never offer an online rebuild.
  -h, --help               This text.

A valid installed current image does not require a manifest or archive parts.
The command never fetches LFS data and never publishes images.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:-}"; shift 2 ;;
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --engine) ENGINE="${2:-}"; shift 2 ;;
        --manifest) MANIFEST="${2:-}"; shift 2 ;;
        --verifier-command) VERIFIER_COMMAND="${2:-}"; shift 2 ;;
        --force-restore) FORCE_RESTORE=1; shift ;;
        --allow-legacy-restore) ALLOW_LEGACY=1; shift ;;
        --allow-historical-builder) ALLOW_HISTORICAL=1; shift ;;
        --rebuild) REBUILD_MODE=yes; shift ;;
        --no-rebuild) REBUILD_MODE=no; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
case "${IMAGE}" in mingw|appimage) ;; *) die "--image must be mingw or appimage" ;; esac
command -v "${ENGINE}" >/dev/null 2>&1 || die "container engine not found: ${ENGINE}"
if [ ! -f "${VERIFIER_COMMAND}" ] || [ ! -r "${VERIFIER_COMMAND}" ]; then
    die "verifier command not found or unreadable: ${VERIFIER_COMMAND}"
fi

ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=../build/arch_map.sh
. "${BUILD_DIR}/arch_map.sh"
if [ "${IMAGE}" = mingw ] && [ "${SR_ARCH}" != x86_64 ]; then
    die "the MinGW builder is available only for x86_64"
fi
ARCH=amd64; [ "${SR_ARCH}" = x86_64 ] || ARCH=arm64
SUFFIX=""; [ "${ARCH}" = amd64 ] || SUFFIX=-arm64
TAG="pulseview-builder-${IMAGE}${SUFFIX}:latest"
MANIFEST="${MANIFEST:-${TOOLCHAIN_DIR}/pulseview-builder-${IMAGE}${SUFFIX}.manifest.toml}"
RECORD_ROOT="${REPO_ROOT}/.work/builder-validation"
mkdir -p "${REPO_ROOT}/.work/bootstrap" "${RECORD_ROOT}"

# shellcheck source=../build/python_env.sh
. "${BUILD_DIR}/python_env.sh"
sr_require_python || exit 1
PY="${SR_PYTHON}"
RECIPE_SPEC="$(bash "${BUILD_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind recipe)"
CONTRACT_SPEC="$(bash "${BUILD_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind contract)"
POLICY_SPEC="$(bash "${BUILD_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind validation)"

verify_current() {
    local details actual_arch actual_image actual_recipe actual_contract output
    details="$("${ENGINE}" image inspect --format '{{.Id}}|{{.Architecture}}' \
        "${TAG}" 2>/dev/null)" || return 1
    actual_arch="${details#*|}"
    [ "${actual_arch}" = "${ARCH}" ] || {
        printf 'warning: installed builder architecture mismatch: %s != %s\n' \
            "${actual_arch}" "${ARCH}" >&2; return 1; }
    actual_image="$("${ENGINE}" image inspect \
        --format '{{index .Config.Labels "io.ddp.builder.image"}}' "${TAG}" 2>/dev/null || true)"
    actual_recipe="$("${ENGINE}" image inspect \
        --format '{{index .Config.Labels "io.ddp.builder.recipe-spec"}}' "${TAG}" 2>/dev/null || true)"
    actual_contract="$("${ENGINE}" image inspect \
        --format '{{index .Config.Labels "io.ddp.builder.dependency-contract-spec"}}' "${TAG}" 2>/dev/null || true)"
    [ "${actual_image}" = "${IMAGE}" ] || {
        printf 'warning: installed builder type mismatch\n' >&2; return 1; }
    [ "${actual_recipe}" = "${RECIPE_SPEC}" ] || {
        printf 'warning: installed builder recipe mismatch\n' >&2; return 1; }
    [ "${actual_contract}" = "${CONTRACT_SPEC}" ] || {
        printf 'warning: installed dependency contract mismatch\n' >&2; return 1; }

    if output="$(bash "${VERIFIER_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
        --tag "${TAG}" --engine "${ENGINE}" --level quick \
        --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
        --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}" 2>&1)"; then
        return 0
    fi
    if printf '%s\n' "${output}" | grep -qi 'revalidation required'; then
        note "validation policy changed; revalidating installed image"
        bash "${VERIFIER_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
            --tag "${TAG}" --engine "${ENGINE}" --level standard \
            --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
            --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}"
        return $?
    fi
    printf '%s\n' "${output}" >&2
    printf 'warning: installed builder quick verification failed\n' >&2
    return 1
}

rebuild_allowed() {
    case "${REBUILD_MODE}" in
        yes) return 0 ;;
        no) return 1 ;;
    esac
    [ -t 0 ] || return 1
    printf 'Rebuild %s online from pinned inputs? [y/N] ' "${IMAGE}" >&2
    read -r answer
    [ "${answer}" = y ] || [ "${answer}" = Y ]
}

rebuild_image() {
    note "building current ${IMAGE} image from pinned inputs"
    bash "${BUILD_DIR}/build_image.sh" --image "${IMAGE}" --platform "${ARCH}" \
        --engine "${ENGINE}" --tag "${TAG}"
    bash "${VERIFIER_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
        --tag "${TAG}" --engine "${ENGINE}" --level standard \
        --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
        --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}"
}

if [ "${FORCE_RESTORE}" -eq 0 ] && verify_current; then
    note "installed builder is current and verified: ${TAG}"
    exit 0
fi

RESTORE_ERROR=""
if [ ! -f "${MANIFEST}" ]; then
    RESTORE_ERROR="archive manifest is unavailable: ${MANIFEST}"
else
    NORMALIZED_MANIFEST="${REPO_ROOT}/.work/bootstrap/${IMAGE}${SUFFIX}.manifest.json"
    ARCHIVE="${REPO_ROOT}/.work/bootstrap/${IMAGE}${SUFFIX}.restore.tar"
    rm -f -- "${NORMALIZED_MANIFEST}" "${ARCHIVE}"
    if ! "${PY}" "${BUILD_DIR}/builder_manifest.py" read --manifest "${MANIFEST}" \
        --format json --output "${NORMALIZED_MANIFEST}" 2>"${NORMALIZED_MANIFEST}.err"; then
        RESTORE_ERROR="invalid archive manifest: $(tr '\n' ' ' <"${NORMALIZED_MANIFEST}.err")"
    else
        readarray -t META < <("${PY}" - "${NORMALIZED_MANIFEST}" <<'PYEOF'
import json, pathlib, sys
sys.stdout.reconfigure(newline="\n")
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(m["schema"]); print(m["image"]); print(m["architecture"])
print(m["image_id"]); print(m["install_tag"])
print(m["builder_recipe_spec"] or ""); print(m["dependency_contract_spec"] or "")
print(m["validation_policy_spec"] or "")
PYEOF
)
        if [ "${META[1]}" != "${IMAGE}" ] || [ "${META[2]}" != "${ARCH}" ]; then
            RESTORE_ERROR="archive manifest image/platform mismatch"
        elif [ "${META[0]}" = 1 ] && [ "${ALLOW_LEGACY}" -ne 1 ]; then
            RESTORE_ERROR="schema-1 archive requires --allow-legacy-restore and cannot be selected as current"
        elif ! "${PY}" "${BUILD_DIR}/builder_manifest.py" verify \
            --manifest "${MANIFEST}" --mode archive \
            --reconstructed-output "${ARCHIVE}" 2>"${NORMALIZED_MANIFEST}.err"; then
            RESTORE_ERROR="archive verification failed: $(tr '\n' ' ' <"${NORMALIZED_MANIFEST}.err")"
        elif ! "${ENGINE}" load --input "${ARCHIVE}" >/dev/null; then
            RESTORE_ERROR="container engine could not load verified archive"
        else
            rm -f -- "${ARCHIVE}"
            LOADED_DETAILS="$("${ENGINE}" image inspect --format '{{.Id}}|{{.Architecture}}' \
                "${META[3]}" 2>/dev/null || true)"
            if [ "${LOADED_DETAILS}" != "${META[3]}|${ARCH}" ]; then
                RESTORE_ERROR="loaded archive image ID or architecture does not match manifest"
            fi
            if [ -n "${RESTORE_ERROR}" ]; then
                :
            elif [ "${META[0]}" = 1 ]; then
                if "${ENGINE}" tag "${META[3]}" "${TAG}" >/dev/null 2>&1; then
                    note "legacy archive restored by explicit request: ${TAG}"
                    rm -f -- "${NORMALIZED_MANIFEST}" "${NORMALIZED_MANIFEST}.err"
                    exit 0
                fi
                RESTORE_ERROR="container engine could not tag the verified legacy image"
            elif { [ "${META[5]}" != "${RECIPE_SPEC}" ] \
                || [ "${META[6]}" != "${CONTRACT_SPEC}" ]; } \
                && [ "${ALLOW_HISTORICAL}" -eq 1 ]; then
                printf 'WARNING: HISTORICAL BUILDER: %s is not the current repository recipe.\n' \
                    "${META[3]}" >&2
                if bash "${VERIFIER_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
                    --tag "${META[3]}" --engine "${ENGINE}" --level standard \
                    --validation-policy-spec "${META[7]}" \
                    --record-root "${RECORD_ROOT}/historical"; then
                    if "${ENGINE}" tag "${META[3]}" "${TAG}" >/dev/null 2>&1; then
                        note "explicit historical builder verified: ${TAG}"
                        rm -f -- "${NORMALIZED_MANIFEST}" "${NORMALIZED_MANIFEST}.err"
                        exit 0
                    fi
                    RESTORE_ERROR="container engine could not tag the verified historical image"
                else
                    RESTORE_ERROR="historical archive failed embedded contract verification"
                fi
            elif [ "${META[5]}" != "${RECIPE_SPEC}" ] \
                || [ "${META[6]}" != "${CONTRACT_SPEC}" ]; then
                RESTORE_ERROR="restored archive identities are stale; use --allow-historical-builder for explicit historical verification"
            elif bash "${VERIFIER_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
                --tag "${META[3]}" --engine "${ENGINE}" --level standard \
                --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
                --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}"; then
                if "${ENGINE}" tag "${META[3]}" "${TAG}" >/dev/null 2>&1; then
                    note "verified archive restored: ${TAG}"
                    rm -f -- "${NORMALIZED_MANIFEST}" "${NORMALIZED_MANIFEST}.err"
                    exit 0
                fi
                RESTORE_ERROR="container engine could not tag the verified current image"
            else
                RESTORE_ERROR="restored archive failed current contract verification"
            fi
        fi
    fi
    rm -f -- "${ARCHIVE}" "${NORMALIZED_MANIFEST}" "${NORMALIZED_MANIFEST}.err"
fi

printf 'warning: %s\n' "${RESTORE_ERROR}" >&2
if rebuild_allowed; then
    rebuild_image
    exit 0
fi
die "online rebuild disabled or not accepted; no current verified builder is available"

# END OF FILE

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Plan or transactionally replace one canonical builder environment.
# This command changes no checkout/index state and performs no publication.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
IMAGE=""
PLATFORM=""
ENGINE="${BUILDER_ENGINE:-docker}"
DELIVERY_DIR="${REPO_ROOT}/07_Delivery/toolchain"
WORK_ROOT="${REPO_ROOT}/.work/bootstrap"
PART_SIZE_MIB=1024
MODE=""
BUILD_COMMAND="${SCRIPT_DIR}/build_image.sh"
VERIFY_COMMAND="${SCRIPT_DIR}/verify_builder_environment.sh"
SAVE_COMMAND="${SCRIPT_DIR}/save_image_parts.sh"
AUDIT_COMMAND=""
REPRESENTATIVE_COMMAND=""
FAIL_AFTER=""

usage() {
    cat <<'EOF'
Usage: update_builder_environment.sh --image mingw|appimage (--plan | --replace) [options]

Modes:
  --plan                   Print intended inputs, identities and paths only.
  --replace                Build, qualify and transactionally replace the archive.

Options:
  --platform ARCH          amd64/x86_64 or arm64/aarch64. Default: host.
  --engine COMMAND         Container engine. Docker is required for --replace.
  --delivery-dir PATH      Stable archive-manifest directory.
  --work-root PATH         Candidate root. Default: .work/bootstrap.
  --part-size-mib N        Archive part size. Default: 1024.
  -h, --help               This text.

Replacement uses a content-derived candidate tag, an isolated run volume and
output root, full mandatory validation, exact archive round-trip inspection,
destination-local atomic moves, stable-manifest commit, and only then stable
local tagging. It performs no repository staging, commit, push, or publication.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
set_mode() {
    [ -z "${MODE}" ] || die "choose exactly one of --plan or --replace"
    MODE="$1"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="${2:-}"; shift 2 ;;
        --platform) PLATFORM="${2:-}"; shift 2 ;;
        --engine) ENGINE="${2:-}"; shift 2 ;;
        --delivery-dir) DELIVERY_DIR="${2:-}"; shift 2 ;;
        --work-root) WORK_ROOT="${2:-}"; shift 2 ;;
        --part-size-mib) PART_SIZE_MIB="${2:-}"; shift 2 ;;
        --plan) set_mode plan; shift ;;
        --replace) set_mode replace; shift ;;
        # Explicit component seams and failure points are fixture-test only.
        --build-command) BUILD_COMMAND="${2:-}"; shift 2 ;;
        --verify-command) VERIFY_COMMAND="${2:-}"; shift 2 ;;
        --save-command) SAVE_COMMAND="${2:-}"; shift 2 ;;
        --audit-command) AUDIT_COMMAND="${2:-}"; shift 2 ;;
        --representative-command) REPRESENTATIVE_COMMAND="${2:-}"; shift 2 ;;
        --fail-after) FAIL_AFTER="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -n "${MODE}" ] || die "replacement is explicit; select --plan or --replace"
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
ARCH="amd64"; [ "${SR_ARCH}" = x86_64 ] || ARCH="arm64"
SUFFIX=""; [ "${ARCH}" = amd64 ] || SUFFIX="-arm64"
VARIANT="${IMAGE}-${ARCH}"
STABLE_TAG="pulseview-builder-${IMAGE}${SUFFIX}:latest"
STABLE_MANIFEST_NAME="pulseview-builder-${IMAGE}${SUFFIX}.manifest.toml"
STABLE_MANIFEST="${DELIVERY_DIR}/${STABLE_MANIFEST_NAME}"
POLICY="${SCRIPT_DIR}/images/validation_policy.toml"

# These commands also strictly validate the lock, canonical profile and selected
# dependency contract before plan output or replacement effects are allowed.
RECIPE_SPEC="$(bash "${SCRIPT_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind recipe)"
CONTRACT_SPEC="$(bash "${SCRIPT_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind contract)"
POLICY_SPEC="$(bash "${SCRIPT_DIR}/builder_spec.sh" --image "${IMAGE}" \
    --platform "${ARCH}" --kind validation)"
RECIPE12="${RECIPE_SPEC:0:12}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
CANDIDATE_TAG="pulseview-builder-${IMAGE}${SUFFIX}:candidate-${RECIPE12}"
CANDIDATE_VOLUME="pulseview-build-${VARIANT}-candidate-${RECIPE12}-${RUN_ID}"
CANDIDATE_ROOT="${WORK_ROOT}/${VARIANT}-${RECIPE12}-${RUN_ID}"
STAGE_DIR="${CANDIDATE_ROOT}/archive"
OUTPUT_DIR="${CANDIDATE_ROOT}/output"
RECORD_ROOT="${CANDIDATE_ROOT}/validation"
RECONSTRUCTED_ARCHIVE="${CANDIDATE_ROOT}/reconstructed.tar"
REPORT="${CANDIDATE_ROOT}/update-report.txt"
LOCK_DIR="${WORK_ROOT}/locks/${VARIANT}.lock"

# shellcheck source=python_env.sh
. "${SCRIPT_DIR}/python_env.sh"
sr_require_python || exit 1
PY="${SR_PYTHON}"

manifest_references() {
    "${PY}" "${SCRIPT_DIR}/builder_manifest.py" read --manifest "$1" \
        | "${PY}" -c '
import json, sys
m = json.load(sys.stdin)
names = [item["file"] for item in m["part"]]
for key in ("normalized_contract", "resolved_inventory", "sbom"):
    value = m.get(key)
    if isinstance(value, dict):
        names.append(value["file"])
for name in sorted(set(names)):
    sys.stdout.buffer.write(name.encode("utf-8") + b"\n")
'
}

require_free_bytes() {
    path="$1"; required_bytes="$2"; purpose="$3"
    available_kib="$(df -Pk -- "${path}" | awk 'END {print $4}')"
    case "${available_kib}" in
        ''|*[!0-9]*) die "cannot determine free space for ${purpose}: ${path}" ;;
    esac
    required_kib=$(( (required_bytes + 1023) / 1024 ))
    [ "${available_kib}" -ge "${required_kib}" ] \
        || die "insufficient free space for ${purpose}: need ${required_kib} KiB, have ${available_kib} KiB"
}

OLD_REFERENCES=()
if [ -e "${STABLE_MANIFEST}" ]; then
    [ -f "${STABLE_MANIFEST}" ] && [ ! -L "${STABLE_MANIFEST}" ] \
        || die "stable manifest is not a regular non-symlink file: ${STABLE_MANIFEST}"
    mapfile -t OLD_REFERENCES < <(manifest_references "${STABLE_MANIFEST}")
fi
SUPERSEDED="none"
[ "${#OLD_REFERENCES[@]}" -eq 0 ] \
    || SUPERSEDED="$(IFS=,; printf '%s' "${OLD_REFERENCES[*]}")"

if [ "${MODE}" = plan ]; then
    printf 'image: %s\n' "${IMAGE}"
    printf 'platform: linux/%s\n' "${ARCH}"
    if [ "${IMAGE}" = mingw ]; then
        printf 'profile: %s\n' "${SCRIPT_DIR}/images/builder_profile.mingw.toml"
    else
        printf 'profile: canonical AppImage defaults\n'
    fi
    printf 'lock: %s\n' "${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"
    printf 'dependency_contract: %s\n' \
        "${SCRIPT_DIR}/images/dependencies.${IMAGE}.toml"
    printf 'builder_recipe_spec: %s\n' "${RECIPE_SPEC}"
    printf 'dependency_contract_spec: %s\n' "${CONTRACT_SPEC}"
    printf 'validation_policy_spec: %s\n' "${POLICY_SPEC}"
    printf 'candidate_tag: %s\n' "${CANDIDATE_TAG}"
    printf 'candidate_volume: %s\n' "${CANDIDATE_VOLUME}"
    printf 'work_root: %s\n' "${CANDIDATE_ROOT}"
    printf 'output_root: %s\n' "${OUTPUT_DIR}"
    printf 'stable_tag: %s\n' "${STABLE_TAG}"
    printf 'stable_manifest: %s\n' "${STABLE_MANIFEST}"
    printf 'superseded_files: %s\n' "${SUPERSEDED}"
    exit 0
fi

case "$(basename -- "${ENGINE}")" in
    docker|docker.exe) ;;
    *) die "canonical replacement requires Docker; Podman remains experimental" ;;
esac
command -v "${ENGINE}" >/dev/null 2>&1 \
    || die "required command not found: ${ENGINE}"
for command in "${BUILD_COMMAND}" "${VERIFY_COMMAND}" "${SAVE_COMMAND}"; do
    [ -f "${command}" ] && [ -r "${command}" ] \
        || die "required script not found or unreadable: ${command}"
done
if [ -n "${AUDIT_COMMAND}" ]; then
    [ -f "${AUDIT_COMMAND}" ] && [ -r "${AUDIT_COMMAND}" ] \
        || die "audit script not found or unreadable: ${AUDIT_COMMAND}"
fi

mkdir -p "$(dirname -- "${LOCK_DIR}")"
mkdir "${LOCK_DIR}" 2>/dev/null \
    || die "another ${VARIANT} builder replacement holds ${LOCK_DIR}"
LOCK_HELD=1
COMMITTED=0
PROMOTED_FILES=()
STABLE_TMP="${STABLE_MANIFEST}.tmp-${RUN_ID}"
cleanup() {
    status=$?
    # Close the signal-sized gap between the atomic manifest rename and the
    # following in-memory state update. Matching bytes mean commit completed.
    if [ "${COMMITTED}" -eq 0 ] && [ -n "${STAGED_MANIFEST:-}" ] \
       && [ -f "${STAGED_MANIFEST}" ] && [ -f "${STABLE_MANIFEST}" ] \
       && cmp -s "${STAGED_MANIFEST}" "${STABLE_MANIFEST}"; then
        COMMITTED=1
    fi
    if [ "${COMMITTED}" -eq 0 ]; then
        for promoted in "${PROMOTED_FILES[@]}"; do rm -f -- "${promoted}"; done
        rm -f -- "${STABLE_TMP}"
        rm -rf -- "${CANDIDATE_ROOT}"
    fi
    "${ENGINE}" image rm "${CANDIDATE_TAG}" >/dev/null 2>&1 || true
    "${ENGINE}" volume rm "${CANDIDATE_VOLUME}" >/dev/null 2>&1 || true
    if [ "${LOCK_HELD}" -eq 1 ]; then
        rmdir "${LOCK_DIR}" >/dev/null 2>&1 || true
    fi
    if [ "${status}" -ne 0 ]; then
        if [ "${COMMITTED}" -eq 1 ]; then
            printf 'candidate update failed after manifest commit; committed generation remains authoritative\n' >&2
        else
            printf 'candidate update failed; stable pre-commit state preserved\n' >&2
        fi
    fi
    exit "${status}"
}
trap cleanup EXIT

mkdir -p "${STAGE_DIR}" "${OUTPUT_DIR}" "${RECORD_ROOT}" "${DELIVERY_DIR}"
if "${ENGINE}" image inspect "${CANDIDATE_TAG}" >/dev/null 2>&1; then
    die "candidate tag already exists: ${CANDIDATE_TAG}"
fi

printf '==> build isolated candidate %s\n' "${CANDIDATE_TAG}"
bash "${BUILD_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" --engine "${ENGINE}" \
    --tag "${CANDIDATE_TAG}"
CANDIDATE_IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' \
    "${CANDIDATE_TAG}")"
[[ "${CANDIDATE_IMAGE_ID}" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || die "candidate engine returned an invalid image ID"

printf '==> standard candidate verification\n'
bash "${VERIFY_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
    --tag "${CANDIDATE_TAG}" --engine "${ENGINE}" --level standard \
    --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
    --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}"

printf '==> build representative output offline\n'
if [ -n "${REPRESENTATIVE_COMMAND}" ]; then
    bash "${REPRESENTATIVE_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
        --tag "${CANDIDATE_TAG}" --volume "${CANDIDATE_VOLUME}" \
        --output-dir "${OUTPUT_DIR}"
else
    export BUILDER_ENGINE="${ENGINE}"
    export BUILDER_TAG="${CANDIDATE_TAG}"
    export BUILDER_VOLUME="${CANDIDATE_VOLUME}"
    export BUILDER_OUTPUT_DIR="${OUTPUT_DIR}"
    if [ "${IMAGE}" = mingw ]; then
        bash "${SCRIPT_DIR}/build_windows_mxe.sh" --clean --stage --offline
    else
        bash "${SCRIPT_DIR}/build_appimage.sh" --arch "${ARCH}"
        if [ "${ARCH}" = arm64 ]; then
            bash "${SCRIPT_DIR}/build_deb.sh" \
                --appimage "${OUTPUT_DIR}/PulseView-aarch64.AppImage" \
                --out "${OUTPUT_DIR}"
        fi
    fi
fi

VERIFY_ARTIFACT_ARGS=()
if [ "${IMAGE}" = mingw ]; then
    VERIFY_ARTIFACT_ARGS+=(--stage "${OUTPUT_DIR}/staging/pulseview-windows-x86_64")
else
    APPIMAGE_NAME="PulseView-x86_64.AppImage"
    [ "${ARCH}" = amd64 ] || APPIMAGE_NAME="PulseView-aarch64.AppImage"
    VERIFY_ARTIFACT_ARGS+=(--appimage "${OUTPUT_DIR}/${APPIMAGE_NAME}")
    if [ "${ARCH}" = arm64 ]; then
        mapfile -t DEB_FILES < <(find "${OUTPUT_DIR}" -maxdepth 1 -type f \
            -name '*.deb' -print | sort)
        [ "${#DEB_FILES[@]}" -eq 1 ] \
            || die "representative arm64 build must produce exactly one Debian package"
        VERIFY_ARTIFACT_ARGS+=(--deb "${DEB_FILES[0]}")
    fi
fi

printf '==> full mandatory candidate verification\n'
# Promotion always uses the policy's digest-pinned clean base, never an ambient
# developer override that would make evidence host-dependent.
[ "${IMAGE}" != appimage ] || unset APPIMAGE_RUNTIME_IMAGE
bash "${VERIFY_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" \
    --tag "${CANDIDATE_TAG}" --engine "${ENGINE}" --level full \
    --expected-recipe "${RECIPE_SPEC}" --expected-contract "${CONTRACT_SPEC}" \
    --validation-policy-spec "${POLICY_SPEC}" --record-root "${RECORD_ROOT}" \
    --policy "${POLICY}" --tests-dir "${REPO_ROOT}/02_Tools/test" \
    --suite-report "${RECORD_ROOT}/mandatory-suite.json" \
    "${VERIFY_ARTIFACT_ARGS[@]}"

printf '==> stage schema-2 archive generation\n'
bash "${SAVE_COMMAND}" --image "${IMAGE}" --platform "${ARCH}" --engine "${ENGINE}" \
    --tag "${CANDIDATE_TAG}" --install-tag "${STABLE_TAG}" \
    --validation-policy-spec "${POLICY_SPEC}" --out-dir "${STAGE_DIR}" \
    --part-size-mib "${PART_SIZE_MIB}"
STAGED_MANIFEST="${STAGE_DIR}/${STABLE_MANIFEST_NAME}"
[ -f "${STAGED_MANIFEST}" ] && [ ! -L "${STAGED_MANIFEST}" ] \
    || die "archive stage did not produce ${STABLE_MANIFEST_NAME}"

MANIFEST_JSON="$("${PY}" "${SCRIPT_DIR}/builder_manifest.py" read \
    --manifest "${STAGED_MANIFEST}")"
"${PY}" - "${MANIFEST_JSON}" \
    "${IMAGE}" "${ARCH}" "${STABLE_TAG}" "${CANDIDATE_TAG}" \
    "${CANDIDATE_IMAGE_ID}" "${RECIPE_SPEC}" "${CONTRACT_SPEC}" \
    "${POLICY_SPEC}" <<'PYEOF'
import json
import sys

expected_keys = (
    "image", "architecture", "install_tag", "archive_tag", "image_id",
    "builder_recipe_spec", "dependency_contract_spec", "validation_policy_spec",
)
expected_values = sys.argv[2:]
manifest = json.loads(sys.argv[1])
if manifest.get("schema") != 2 or manifest.get("legacy"):
    raise SystemExit("candidate manifest must be strict schema 2")
for key, expected in zip(expected_keys, expected_values, strict=True):
    if manifest.get(key) != expected:
        raise SystemExit(f"candidate manifest {key} mismatch")
PYEOF
mapfile -t NEW_REFERENCES < <(manifest_references "${STAGED_MANIFEST}")
[ "${#NEW_REFERENCES[@]}" -gt 0 ] || die "candidate manifest references no files"
ARCHIVE_SIZE="$("${PY}" - "${MANIFEST_JSON}" <<'PYEOF'
import json
import sys
value = str(json.loads(sys.argv[1])["archive"]["size"])
sys.stdout.buffer.write(value.encode("ascii"))
PYEOF
)"
require_free_bytes "${CANDIDATE_ROOT}" "${ARCHIVE_SIZE}" \
    "archive reconstruction"

printf '==> audit and reconstruct complete staged generation\n'
if [ -n "${AUDIT_COMMAND}" ]; then
    bash "${AUDIT_COMMAND}" --manifest "${STAGED_MANIFEST}" --engine "${ENGINE}" \
        --candidate-tag "${CANDIDATE_TAG}" \
        --expected-image-id "${CANDIDATE_IMAGE_ID}" \
        --reconstructed-output "${RECONSTRUCTED_ARCHIVE}"
else
    "${PY}" "${SCRIPT_DIR}/builder_manifest.py" verify \
        --manifest "${STAGED_MANIFEST}" --mode archive \
        --reconstructed-output "${RECONSTRUCTED_ARCHIVE}" >/dev/null
    "${ENGINE}" image rm "${CANDIDATE_TAG}" >/dev/null
    "${ENGINE}" load --input "${RECONSTRUCTED_ARCHIVE}" >/dev/null
fi
ROUND_TRIP_ID="$("${ENGINE}" image inspect --format '{{.Id}}' \
    "${CANDIDATE_TAG}")"
[ "${ROUND_TRIP_ID}" = "${CANDIDATE_IMAGE_ID}" ] \
    || die "archive round trip produced ${ROUND_TRIP_ID}, expected ${CANDIDATE_IMAGE_ID}"
rm -f -- "${RECONSTRUCTED_ARCHIVE}"

# Preflight every referenced source and destination before the first move.
for name in "${NEW_REFERENCES[@]}"; do
    source="${STAGE_DIR}/${name}"
    target="${DELIVERY_DIR}/${name}"
    [ -f "${source}" ] && [ ! -L "${source}" ] \
        || die "candidate reference is missing or unsafe: ${name}"
    if [ -e "${target}" ]; then
        [ -f "${target}" ] && [ ! -L "${target}" ] && cmp -s "${source}" "${target}" \
            || die "generation collision at ${target}"
    fi
done

DESTINATION_BYTES=0
for name in "${NEW_REFERENCES[@]}"; do
    size="$(wc -c <"${STAGE_DIR}/${name}" | tr -d '[:space:]')"
    DESTINATION_BYTES=$((DESTINATION_BYTES + size))
done
DESTINATION_BYTES=$((DESTINATION_BYTES + $(wc -c <"${STAGED_MANIFEST}")))
require_free_bytes "${DELIVERY_DIR}" "${DESTINATION_BYTES}" \
    "destination-local promotion copies"

printf '==> promote immutable generation files\n'
MOVE_INDEX=0
for name in "${NEW_REFERENCES[@]}"; do
    source="${STAGE_DIR}/${name}"
    target="${DELIVERY_DIR}/${name}"
    if [ ! -e "${target}" ]; then
        temporary="${target}.tmp-${RUN_ID}"
        cp -- "${source}" "${temporary}"
        [ "$(sha256sum "${source}" | cut -d' ' -f1)" = \
          "$(sha256sum "${temporary}" | cut -d' ' -f1)" ] \
            || die "copied digest mismatch for ${name}"
        mv -- "${temporary}" "${target}"
        PROMOTED_FILES+=("${target}")
    fi
    MOVE_INDEX=$((MOVE_INDEX + 1))
    [ "${FAIL_AFTER}" != "promoted-file-${MOVE_INDEX}" ] \
        || die "injected interruption after promoted file ${MOVE_INDEX}"
done
[ "${FAIL_AFTER}" != files-promoted ] \
    || die "injected interruption after identity-file promotion"

# The stable manifest is the final filesystem commit point.
cp -- "${STAGED_MANIFEST}" "${STABLE_TMP}"
[ "$(sha256sum "${STAGED_MANIFEST}" | cut -d' ' -f1)" = \
  "$(sha256sum "${STABLE_TMP}" | cut -d' ' -f1)" ] \
    || die "stable manifest temporary copy digest mismatch"
"${PY}" "${SCRIPT_DIR}/builder_manifest.py" read \
    --manifest "${STABLE_TMP}" >/dev/null
mv -- "${STABLE_TMP}" "${STABLE_MANIFEST}"
COMMITTED=1
[ "${FAIL_AFTER}" != manifest-committed ] \
    || die "injected interruption after stable manifest commit"

# Stable local selection changes only after the complete archive is committed.
"${ENGINE}" tag "${CANDIDATE_IMAGE_ID}" "${STABLE_TAG}"

# Remove only files named by the superseded manifest and not by the new one.
for old_name in "${OLD_REFERENCES[@]}"; do
    keep=0
    for new_name in "${NEW_REFERENCES[@]}"; do
        [ "${old_name}" = "${new_name}" ] && keep=1
    done
    [ "${keep}" -eq 1 ] || rm -f -- "${DELIVERY_DIR}/${old_name}"
done

{
    printf 'image: %s\n' "${IMAGE}"
    printf 'platform: linux/%s\n' "${ARCH}"
    printf 'builder_recipe_spec: %s\n' "${RECIPE_SPEC}"
    printf 'dependency_contract_spec: %s\n' "${CONTRACT_SPEC}"
    printf 'validation_policy_spec: %s\n' "${POLICY_SPEC}"
    printf 'candidate_image_id: %s\n' "${CANDIDATE_IMAGE_ID}"
    printf 'mandatory_suite_report: %s\n' "${RECORD_ROOT}/mandatory-suite.json"
    printf 'stable_tag: %s\n' "${STABLE_TAG}"
    printf 'stable_manifest: %s\n' "${STABLE_MANIFEST}"
    printf 'promoted_files:\n'
    printf '  %s\n' "${NEW_REFERENCES[@]}" "${STABLE_MANIFEST_NAME}"
    printf 'superseded_files: %s\n' "${SUPERSEDED}"
} >"${REPORT}"

printf '==> promoted %s and %s\n' "${STABLE_TAG}" "${STABLE_MANIFEST_NAME}"
printf 'report: %s\n' "${REPORT}"
printf 'review and stage only the listed delivery files; publication is separate\n'

# END OF FILE

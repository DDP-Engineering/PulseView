#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compatibility shell entry point for separated builder lifecycle identities.
# Recipe identity covers selected image-content inputs. Contract and validation
# policy have independent identities and can be requested explicitly.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"
IMAGES_DIR="${SCRIPT_DIR}/images"
PATCH_DIR="${REPO_ROOT}/05_Software/sigrok-util/cross-compile/mingw"
HELPERS_DIR="${IMAGES_DIR}"
POLICY="${IMAGES_DIR}/validation_policy.toml"
VERIFIER="${SCRIPT_DIR}/verify_builder_environment.sh"
TESTS_DIR="${REPO_ROOT}/02_Tools/test"

IMAGE=""
PLATFORM=""
CONTRACT=""
PROFILE=""
DOCKERFILE=""
KIND="recipe"
FORMAT="text"
QT5_FREEZE=0
GLIB_VERSION=""
NO_PATCHES=0
SKIP_PATCHES=()
BUILD_DRIVER=""

usage() {
    cat <<'EOF'
Usage: builder_spec.sh --image mingw|appimage [options]

Print a separated builder lifecycle identity.

Options:
  --image mingw|appimage   Builder type. Required.
  --platform ARCH          x86_64/amd64 or aarch64/arm64. Default: host.
  --kind KIND              recipe, contract, validation, or all. Default recipe.
  --format text|json       Output form. Default text; all always emits JSON.
  --contract PATH          Dependency contract override.
  --profile PATH           Canonical MinGW profile override.
  --lock PATH              Upstream lock override.
  --dockerfile PATH        Selected Dockerfile override.
  --helpers-dir PATH       Builder helper directory override.
  --patch-dir PATH         Selected patch directory override.
  --policy PATH            Validation policy override.
  --verifier PATH          Verifier override for policy identity tests.
  --tests-dir PATH         Mandatory test directory override.
  --qt5-freeze             Effective experimental MinGW recipe option.
  --glib-version V         Effective experimental MinGW glib hold.
  --skip-patch NAME        Exclude a selected MinGW patch. Repeatable.
  --no-sigrok-patches      Exclude all selected MinGW patches.
  --build-driver PATH      Deprecated compatibility option; not identity input.
  -h, --help               This text.

The default remains one recipe SHA-256 on standard output.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)             IMAGE="${2:-}"; shift 2 ;;
        --platform)          PLATFORM="${2:-}"; shift 2 ;;
        --kind)              KIND="${2:-}"; shift 2 ;;
        --format)            FORMAT="${2:-}"; shift 2 ;;
        --contract)          CONTRACT="${2:-}"; shift 2 ;;
        --profile)           PROFILE="${2:-}"; shift 2 ;;
        --lock)              LOCK="${2:-}"; shift 2 ;;
        --dockerfile)        DOCKERFILE="${2:-}"; shift 2 ;;
        --helpers-dir)       HELPERS_DIR="${2:-}"; shift 2 ;;
        --patch-dir)         PATCH_DIR="${2:-}"; shift 2 ;;
        --policy)            POLICY="${2:-}"; shift 2 ;;
        --verifier)          VERIFIER="${2:-}"; shift 2 ;;
        --tests-dir)         TESTS_DIR="${2:-}"; shift 2 ;;
        --build-driver)      BUILD_DRIVER="${2:-}"; shift 2 ;;
        --glib-version)      GLIB_VERSION="${2:-}"; shift 2 ;;
        --qt5-freeze)        QT5_FREEZE=1; shift ;;
        --skip-patch)        SKIP_PATCHES+=("${2:-}"); shift 2 ;;
        --no-sigrok-patches) NO_PATCHES=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage" ;;
esac
case "${KIND}" in
    recipe|contract|validation|all) ;;
    *) die "--kind must be recipe, contract, validation, or all" ;;
esac
case "${FORMAT}" in
    text|json) ;;
    *) die "--format must be text or json" ;;
esac

PLATFORM="${PLATFORM:-$(uname -m)}"
CONTRACT="${CONTRACT:-${IMAGES_DIR}/dependencies.${IMAGE}.toml}"
DOCKERFILE="${DOCKERFILE:-${IMAGES_DIR}/Dockerfile.${IMAGE}}"

if [ "${IMAGE}" = "mingw" ]; then
    PROFILE="${PROFILE:-${IMAGES_DIR}/builder_profile.mingw.toml}"
else
    [ -z "${PROFILE}" ] || die "--profile applies only to the mingw builder"
    [ "${QT5_FREEZE}" -eq 0 ] || die "--qt5-freeze applies only to the mingw builder"
    [ -z "${GLIB_VERSION}" ] || die "--glib-version applies only to the mingw builder"
    [ "${NO_PATCHES}" -eq 0 ] || die "patch options apply only to the mingw builder"
    [ "${#SKIP_PATCHES[@]}" -eq 0 ] || die "patch options apply only to the mingw builder"
fi

# Accepted only so older callers fail neither parsing nor identity calculation.
# The undifferentiated build-driver bytes are deliberately not identity input;
# the canonical values it produces are.
: "${BUILD_DRIVER}"

# shellcheck source=python_env.sh
. "${SCRIPT_DIR}/python_env.sh"
sr_require_python || exit 1

ARGS=(
    "${KIND}"
    --image "${IMAGE}"
    --platform "${PLATFORM}"
    --lock "${LOCK}"
    --contract "${CONTRACT}"
    --dockerfile "${DOCKERFILE}"
    --helpers-dir "${HELPERS_DIR}"
    --patch-dir "${PATCH_DIR}"
)
if [ -n "${PROFILE}" ]; then ARGS+=(--profile "${PROFILE}"); fi
if [ "${QT5_FREEZE}" -eq 1 ]; then ARGS+=(--qt5-freeze); fi
if [ -n "${GLIB_VERSION}" ]; then ARGS+=(--glib-version "${GLIB_VERSION}"); fi
if [ "${NO_PATCHES}" -eq 1 ]; then ARGS+=(--no-sigrok-patches); fi
for patch in "${SKIP_PATCHES[@]}"; do ARGS+=(--skip-patch "${patch}"); done
if [ "${KIND}" = "validation" ] || [ "${KIND}" = "all" ]; then
    ARGS+=(--policy "${POLICY}" --verifier "${VERIFIER}" --tests-dir "${TESTS_DIR}")
fi
if [ "${FORMAT}" = "json" ]; then ARGS+=(--json); fi

exec "${SR_PYTHON}" "${SCRIPT_DIR}/builder_identity.py" "${ARGS[@]}"

# END OF FILE

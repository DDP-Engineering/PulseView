#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Ensure that one local builder image is usable. Restore the exact image from
# checksum-verified Git LFS parts when possible; otherwise offer a local online
# rebuild from the repository's pinned inputs. Nothing is uploaded or published.

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

usage() {
    cat <<'EOF'
Ensure that a local PulseView builder image is installed and complete.

Options:
  --image mingw|appimage   Builder image. Default mingw.
  --platform ARCH          x86_64/amd64 or aarch64/arm64.
  --engine docker|podman   Container engine. Default docker.
  --manifest PATH          Override the normal multipart manifest.
  --force-restore          Ignore an installed image and restore the archive.
  --rebuild                Rebuild without prompting if restore is impossible.
  --no-rebuild             Never offer an online rebuild.
  -h, --help               This text.

This command reads only local Git/LFS files unless an online rebuild is
explicitly accepted. It never downloads LFS files and never publishes images.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --image)         IMAGE="${2:-}"; shift 2 ;;
        --platform)      PLATFORM="${2:-}"; shift 2 ;;
        --engine)        ENGINE="${2:-}"; shift 2 ;;
        --manifest)      MANIFEST="${2:-}"; shift 2 ;;
        --force-restore) FORCE_RESTORE=1; shift ;;
        --rebuild)       REBUILD_MODE="yes"; shift ;;
        --no-rebuild)    REBUILD_MODE="no"; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               die "unknown option: $1" ;;
    esac
done

case "${IMAGE}" in
    mingw|appimage) ;;
    *) die "--image must be mingw or appimage" ;;
esac

ARCH_OVERRIDE="${PLATFORM#linux/}"
[ -n "${ARCH_OVERRIDE}" ] || ARCH_OVERRIDE="$(uname -m)"
# shellcheck source=../build/arch_map.sh
. "${BUILD_DIR}/arch_map.sh"
if [ "${IMAGE}" = "mingw" ] && [ "${SR_ARCH}" != "x86_64" ]; then
    die "the mingw builder is available only for x86_64 hosts"
fi

# mxe_fixes.patch fails every hunk against the pinned MXE and is excluded from
# the rebuild (02_Tools/build/STATUS.md records the deviation). It is named
# once here because validate_installed and rebuild_image have to agree: a
# recipe identity computed with different options would reject the very image
# this script had just rebuilt correctly.
MINGW_PATCH_SKIPS=(mxe_fixes.patch)

TAG_ARCH_SUFFIX=""
[ "${SR_ARCH}" = "x86_64" ] || TAG_ARCH_SUFFIX="-arm64"

SPEC_ARGS=(--image "${IMAGE}" --platform "${SR_ARCH}")
if [ "${IMAGE}" = "mingw" ]; then
    for skipped_patch in "${MINGW_PATCH_SKIPS[@]}"; do
        SPEC_ARGS+=(--skip-patch "${skipped_patch}")
    done
fi
DEFAULT_TAG="pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}:latest"
MANIFEST="${MANIFEST:-${TOOLCHAIN_DIR}/pulseview-builder-${IMAGE}${TAG_ARCH_SUFFIX}.manifest.toml}"
EXPECTED_ARCH="${SR_DOCKER_PLATFORM#linux/}"

command -v "${ENGINE}" >/dev/null 2>&1 || die "${ENGINE} not found"

# The manifest is TOML and is read with tomllib, so "python3 exists" is not
# the prerequisite - "python3 can import tomllib" is. python_env.sh says which
# and explains the remedy when none can.
# shellcheck source=../build/python_env.sh
. "${BUILD_DIR}/python_env.sh"
sr_require_python || exit 1
PY="${SR_PYTHON}"

manifest_value() {
    "${PY}" - "${MANIFEST}" "$1" <<'PYEOF'
import sys
import tomllib

sys.stdout.reconfigure(newline="\n")
with open(sys.argv[1], "rb") as stream:
    data = tomllib.load(stream)
value = data.get(sys.argv[2])
if value is None:
    raise SystemExit(f"manifest has no {sys.argv[2]!r} field")
print(value)
PYEOF
}

manifest_parts() {
    "${PY}" - "${MANIFEST}" <<'PYEOF'
import sys
import tomllib

sys.stdout.reconfigure(newline="\n")
with open(sys.argv[1], "rb") as stream:
    data = tomllib.load(stream)
parts = data.get("part", [])
if not parts:
    raise SystemExit("manifest contains no archive parts")
for part in parts:
    print(f"{part['file']}\t{part['size']}\t{part['sha256']}")
PYEOF
}

health_command() {
    case "${IMAGE}" in
        mingw)
            printf '%s' 'test -x /opt/mxe/usr/bin/x86_64-w64-mingw32.static.posix-gcc && test -f /opt/sigrok-deps/python-3.13.15-embed-amd64.zip && doxygen --version >/dev/null'
            ;;
        appimage)
            printf '%s' 'command -v cmake >/dev/null && command -v appimagetool >/dev/null && command -v linuxdeployqt >/dev/null && test -r /usr/local/lib/appimage/runtime'
            ;;
    esac
}

validate_installed() {
    local tag="$1" expected_id="${2:-}" details image_id architecture image_spec current_spec
    local exact_archive=0 native_arch
    details="$("${ENGINE}" image inspect --format '{{.Id}}|{{.Architecture}}' \
        "${tag}" 2>/dev/null)" || return 1
    image_id="${details%%|*}"
    architecture="${details#*|}"
    [ "${architecture}" = "${EXPECTED_ARCH}" ] || {
        printf 'warning: %s has architecture %s, expected %s\n' \
            "${tag}" "${architecture}" "${EXPECTED_ARCH}" >&2
        return 1
    }

    current_spec="$(bash "${BUILD_DIR}/builder_spec.sh" "${SPEC_ARGS[@]}")"
    image_spec="$("${ENGINE}" image inspect \
        --format '{{index .Config.Labels "io.ddp.builder.spec"}}' \
        "${tag}" 2>/dev/null || true)"
    if [ -n "${expected_id}" ] && [ "${image_id}" = "${expected_id}" ]; then
        exact_archive=1
    elif [ -n "${image_spec}" ] && [ "${image_spec}" = "${current_spec}" ]; then
        :
    else
        printf 'warning: %s does not match the archived image or current builder recipe\n' \
            "${tag}" >&2
        return 1
    fi

    if ! "${ENGINE}" run --rm --network none --platform "${SR_DOCKER_PLATFORM}" \
        "${tag}" sh -ec "$(health_command)" >/dev/null 2>&1; then
        case "$(uname -m)" in
            x86_64|amd64) native_arch="amd64" ;;
            aarch64|arm64) native_arch="arm64" ;;
            *) native_arch="unknown" ;;
        esac
        if [ "${exact_archive}" -eq 1 ] && [ "${architecture}" != "${native_arch}" ]; then
            note "${tag} identity verified; runtime health check needs ${architecture} execution support"
        else
            printf 'warning: %s failed its offline health check\n' "${tag}" >&2
            return 1
        fi
    fi
    return 0
}

verify_manifest_identity() {
    local schema manifest_image manifest_platform manifest_tag
    local manifest_format
    schema="$(manifest_value schema 2>/dev/null)" || {
        printf 'invalid archive manifest: %s\n' "${MANIFEST}" >&2
        return 1
    }
    manifest_format="$(manifest_value format 2>/dev/null)" || return 1
    manifest_image="$(manifest_value image 2>/dev/null)" || return 1
    manifest_platform="$(manifest_value platform 2>/dev/null)" || return 1
    manifest_tag="$(manifest_value tag 2>/dev/null)" || return 1
    [ "${schema}" = "1" ] || {
        printf 'unsupported manifest schema %s\n' "${schema}" >&2
        return 1
    }
    [ "${manifest_format}" = "docker-archive" ] || {
        printf 'only docker-archive manifests are supported\n' >&2
        return 1
    }
    [ "${manifest_image}" = "${IMAGE}" ] || {
        printf 'manifest image is %s, expected %s\n' \
            "${manifest_image}" "${IMAGE}" >&2
        return 1
    }
    [ "${manifest_platform}" = "${SR_DOCKER_PLATFORM}" ] || {
        printf 'manifest platform is %s, expected %s\n' \
            "${manifest_platform}" "${SR_DOCKER_PLATFORM}" >&2
        return 1
    }
    [ "${manifest_tag}" = "${DEFAULT_TAG}" ] || {
        printf 'manifest tag is %s, expected %s\n' \
            "${manifest_tag}" "${DEFAULT_TAG}" >&2
        return 1
    }
}

restore_archive() {
    local archive_name archive_sha archive_size archive_path part_file part_size part_sha
    local actual_size actual_sha part_path

    [ -f "${MANIFEST}" ] || {
        printf 'archive manifest not found: %s\n' "${MANIFEST}" >&2
        return 1
    }
    verify_manifest_identity || return 1
    archive_name="$(manifest_value archive 2>/dev/null)" || return 1
    archive_sha="$(manifest_value archive_sha256 2>/dev/null)" || return 1
    archive_size="$(manifest_value archive_size 2>/dev/null)" || return 1
    case "${archive_name}" in
        */*|*\\*|''|.|..)
            printf 'unsafe archive name in manifest: %s\n' "${archive_name}" >&2
            return 1
            ;;
    esac

    mkdir -p "${REPO_ROOT}/.work/bootstrap"
    archive_path="${REPO_ROOT}/.work/bootstrap/${archive_name}"
    rm -f -- "${archive_path}"

    note "verifying Git LFS archive parts"
    while IFS=$'\t' read -r part_file part_size part_sha; do
        case "${part_file}" in
            */*|*\\*|''|.|..)
                printf 'unsafe part name in manifest: %s\n' "${part_file}" >&2
                rm -f -- "${archive_path}"
                return 1
                ;;
        esac
        part_path="$(dirname -- "${MANIFEST}")/${part_file}"
        if [ ! -f "${part_path}" ]; then
            printf 'missing archive part: %s\n' "${part_path}" >&2
            rm -f -- "${archive_path}"
            return 1
        fi
        actual_size="$(wc -c < "${part_path}" | tr -d ' ')"
        if [ "${actual_size}" -lt 1024 ] \
           && head -1 "${part_path}" | grep -q '^version https://git-lfs'; then
            printf '%s is a Git LFS pointer, not downloaded content\n' "${part_path}" >&2
            printf 'run git lfs pull, then retry\n' >&2
            rm -f -- "${archive_path}"
            return 1
        fi
        [ "${actual_size}" = "${part_size}" ] || {
            printf 'size mismatch for %s: got %s, expected %s\n' \
                "${part_file}" "${actual_size}" "${part_size}" >&2
            rm -f -- "${archive_path}"
            return 1
        }
        actual_sha="$(sha256sum "${part_path}" | cut -d' ' -f1)"
        [ "${actual_sha}" = "${part_sha}" ] || {
            printf 'checksum mismatch for %s\n' "${part_file}" >&2
            rm -f -- "${archive_path}"
            return 1
        }
        cat -- "${part_path}" >> "${archive_path}"
    done < <(manifest_parts)

    actual_size="$(wc -c < "${archive_path}" | tr -d ' ')"
    actual_sha="$(sha256sum "${archive_path}" | cut -d' ' -f1)"
    [ "${actual_size}" = "${archive_size}" ] || {
        rm -f -- "${archive_path}"
        printf 'reconstructed archive size mismatch\n' >&2
        return 1
    }
    [ "${actual_sha}" = "${archive_sha}" ] || {
        rm -f -- "${archive_path}"
        printf 'reconstructed archive checksum mismatch\n' >&2
        return 1
    }

    note "loading verified archive"
    "${ENGINE}" load --input "${archive_path}"
    rm -f -- "${archive_path}"

    if validate_installed "${DEFAULT_TAG}" "$(manifest_value image_id)"; then
        note "${DEFAULT_TAG} restored and verified"
        return 0
    fi
    printf 'loaded image failed identity or health validation\n' >&2
    return 1
}

rebuild_image() {
    local args
    args=(--image "${IMAGE}" --engine "${ENGINE}")
    if [ "${IMAGE}" = "mingw" ]; then
        for skipped_patch in "${MINGW_PATCH_SKIPS[@]}"; do
            args+=(--skip-patch "${skipped_patch}")
        done
    else
        args+=(--platform "${SR_ARCH}")
    fi
    note "building ${DEFAULT_TAG} locally from pinned online inputs"
    bash "${BUILD_DIR}/build_image.sh" "${args[@]}"
    validate_installed "${DEFAULT_TAG}" "" \
        || die "locally rebuilt image failed identity or health validation"
    note "${DEFAULT_TAG} rebuilt and verified"
}

offer_rebuild() {
    local answer
    case "${REBUILD_MODE}" in
        yes) rebuild_image; return ;;
        no)
            printf 'online rebuild disabled; no usable builder image is available\n' >&2
            return 1
            ;;
    esac

    printf '\nThe local archive could not restore %s.\n' "${DEFAULT_TAG}" >&2
    printf 'Run git lfs pull and retry, or build it locally from pinned online inputs.\n' >&2
    if [ ! -t 0 ]; then
        printf 'Non-interactive session: rerun with --rebuild to accept the online build.\n' >&2
        return 1
    fi
    read -r -p 'Build the image locally now? [y/N] ' answer
    case "${answer}" in
        y|Y|yes|YES) rebuild_image ;;
        *) return 1 ;;
    esac
}

EXPECTED_IMAGE_ID=""
if [ -f "${MANIFEST}" ]; then
    if verify_manifest_identity; then
        EXPECTED_IMAGE_ID="$(manifest_value image_id 2>/dev/null || true)"
    fi
fi

if [ "${FORCE_RESTORE}" -eq 0 ] \
   && validate_installed "${DEFAULT_TAG}" "${EXPECTED_IMAGE_ID}"; then
    note "${DEFAULT_TAG} is already installed and verified"
    exit 0
fi

if restore_archive; then
    exit 0
fi

offer_rebuild

# END OF FILE

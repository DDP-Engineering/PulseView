#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Inspect the Linux build host and report whether it can build this project.
#
# Read-only by contract (02_Tools/bootstrap/README.md): this reports what is
# missing and the exact command to fix it, and installs nothing. It never
# touches git state, never writes outside --result, and needs no privileges.
#
# Run it inside the Linux build host - on Windows that means WSL:
#
#   wsl -d Ubuntu-24.04 -- bash /mnt/f/2026_PulseView/02_Tools/bootstrap/check_host.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"

RESULT=""
ENGINE="${BUILDER_ENGINE:-docker}"
TOOLCHAIN_DIR="${REPO_ROOT}/07_Delivery/toolchain"
IMAGE_TAG="pulseview-builder-mingw:latest"
ARM64_PROBE_IMAGE="${ARM64_PROBE_IMAGE:-pulseview-builder-appimage-arm64:latest}"
BINFMT_IMAGE="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"

# Disk needed for the image plus one build tree. The image alone is ~7.3 GB
# unpacked; the build volume reaches a few GB more.
NEED_GB=30

usage() {
    cat <<'EOF'
Report whether this host can build the project. Changes nothing.

Options:
  --result PATH         Also write a JSON record here.
  --tag NAME            Builder image to look for.
                        Default pulseview-builder-mingw:latest.
  --engine docker|podman  Container engine to probe. Default docker, or
                        BUILDER_ENGINE when that is set. Docker is the engine
                        this project verifies its builds on; Podman is
                        accepted by the scripts but not verified.
  --toolchain-dir PATH  Where the builder archive manifests and parts live.
                        Default 07_Delivery/toolchain.
  -h, --help            This text.

Exit status is 1 if any check FAILED, 0 otherwise. WARN does not fail.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --result)         RESULT="${2:-}"; shift 2 ;;
        --tag)            IMAGE_TAG="${2:-}"; shift 2 ;;
        --engine)         ENGINE="${2:-}"; shift 2 ;;
        --toolchain-dir)  TOOLCHAIN_DIR="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
    esac
done

FAILED=0
WARNED=0
JSON_ROWS=""

# status name detail remedy
report() {
    local status="$1" name="$2" detail="$3" remedy="${4:-}"
    case "${status}" in
        PASS) ;;
        WARN) WARNED=$((WARNED + 1)) ;;
        FAIL) FAILED=$((FAILED + 1)) ;;
    esac
    printf '  %-4s  %-22s %s\n' "${status}" "${name}" "${detail}"
    [ -n "${remedy}" ] && printf '        %s\n' "${remedy}"
    # Assembled by hand rather than with jq, which is not guaranteed present
    # on a host whose prerequisites are precisely what we are checking.
    JSON_ROWS="${JSON_ROWS}${JSON_ROWS:+,}
    {\"check\": \"${name}\", \"status\": \"${status}\", \"detail\": \"${detail//\"/\\\"}\"}"
}

printf '\nHost check: %s\n' "$(uname -srm)"
printf 'Repository: %s\n\n' "${REPO_ROOT}"

# --------------------------------------------------------------------------
printf 'Environment\n'

if grep -qi microsoft /proc/version 2>/dev/null; then
    report PASS "wsl" "running under WSL"
else
    report WARN "wsl" "not WSL - a native Linux host is fine but untested here"
fi

case "${REPO_ROOT}" in
    /mnt/*) report WARN "repo location" "on a Windows drive (${REPO_ROOT})" \
        "9p makes this slow. Builds use a container volume for objects, so this is tolerable." ;;
    *) report PASS "repo location" "on the Linux filesystem" ;;
esac

# --------------------------------------------------------------------------
printf '\nTools\n'

check_tool() {
    local bin="$1" name="$2" remedy="$3"
    if command -v "${bin}" >/dev/null 2>&1; then
        report PASS "${name}" "$("${bin}" --version 2>&1 | head -1)"
        return 0
    fi
    report FAIL "${name}" "not found" "${remedy}"
    return 1
}

engine_install_remedy() {
    case "$(basename -- "${ENGINE}")" in
        docker)
            printf '%s' 'Install Docker Engine inside this distribution - see 01_Documentation/Environment_Setup.md. Docker Desktop with WSL integration is an alternative.'
            ;;
        podman)
            printf '%s' 'Install Podman with: sudo apt-get install podman'
            ;;
        *)
            printf 'Install the selected container engine %s, or choose one with --engine.' "${ENGINE}"
            ;;
    esac
}

engine_reachability_remedy() {
    case "$(basename -- "${ENGINE}")" in
        docker)
            printf '%s' 'Start it: sudo service docker start. With Docker Desktop instead, enable WSL integration for this distro.'
            ;;
        *)
            printf 'Run `%s info` and correct the engine or connection error it reports.' "${ENGINE}"
            ;;
    esac
}

check_tool git "git" "sudo apt-get install git"
check_tool "${ENGINE}" "${ENGINE}" "$(engine_install_remedy)"

# The bootstrap reads the upstream lock and every archive manifest with
# tomllib, so the prerequisite is an interpreter that can import it - standard
# library from CPython 3.11. A 3.10 host has a python3 and still cannot run
# ensure_build_environment.sh; saying so here is the whole point of this check.
# shellcheck source=../build/python_env.sh
. "${REPO_ROOT}/02_Tools/build/python_env.sh"
PY_STATUS="$(sr_python_status)"
PY_KIND="${PY_STATUS%%|*}"
PY_PATH="${PY_STATUS#*|}"; PY_PATH="${PY_PATH%%|*}"
PY_VERSION="${PY_STATUS##*|}"
case "${PY_KIND}" in
    ok)
        report PASS "python (tomllib)" "${PY_VERSION} at ${PY_PATH}" ;;
    old)
        report FAIL "python (tomllib)" \
            "${PY_VERSION} at ${PY_PATH} cannot import tomllib" \
            "CPython ${SR_PYTHON_MIN} or newer is required: $(sr_python_remedy)" ;;
    *)
        report FAIL "python (tomllib)" "no interpreter on PATH" \
            "CPython ${SR_PYTHON_MIN} or newer is required: $(sr_python_remedy)" ;;
esac

# Git LFS carries the saved toolchain image. Without it a clone silently gets
# pointer files instead of the archive - a failure that surfaces much later,
# as a corrupt tarball rather than a missing tool.
#
# Whether this host needs LFS depends on who owns the checkout. With the repo
# on a Windows drive, Windows git did the cloning and its LFS is the one that
# matters; this side only reads the files. Only a checkout on the Linux
# filesystem makes LFS here a hard requirement.
if git lfs version >/dev/null 2>&1; then
    report PASS "git-lfs" "$(git lfs version 2>&1 | head -1)"
else
    case "${REPO_ROOT}" in
        /mnt/*)
            report WARN "git-lfs" "not found here, but the checkout is Windows-owned" \
                "Confirm on the Windows side: git lfs version" ;;
        *)
            report FAIL "git-lfs" "not found" \
                "sudo apt-get install git-lfs && git lfs install" ;;
    esac
fi

# --------------------------------------------------------------------------
printf '\nContainer engine\n'

if command -v "${ENGINE}" >/dev/null 2>&1; then
    if "${ENGINE}" info >/dev/null 2>&1; then
        report PASS "engine daemon" "${ENGINE} reachable"
        if "${ENGINE}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
            report PASS "builder image" "${IMAGE_TAG} present"
        else
            report WARN "builder image" "${IMAGE_TAG} not present" \
                "Run bash 02_Tools/bootstrap/ensure_build_environment.sh --image mingw"
        fi
    else
        report FAIL "engine daemon" "${ENGINE} not reachable" \
            "$(engine_reachability_remedy)"
    fi
fi

# --------------------------------------------------------------------------
printf '\nBuilder archives\n'

# Presence and pointer detection only. The manifests are ordinary Git content
# and are always present; the parts are Git LFS objects and are exactly what a
# clone without LFS silently replaces with a 130-byte pointer. Full checksum
# verification is ensure_build_environment.sh's job and costs gigabytes of
# reads - this has to stay cheap enough to run on every host check.
if [ ! -d "${TOOLCHAIN_DIR}" ]; then
    report FAIL "toolchain archive" "no such directory: ${TOOLCHAIN_DIR}"
else
    archive_detail=""
    archive_status="PASS"
    archive_remedy=""
    manifest_count=0
    for manifest in "${TOOLCHAIN_DIR}"/*.manifest.toml; do
        [ -f "${manifest}" ] || continue
        manifest_count=$((manifest_count + 1))
        stem="$(basename -- "${manifest}" .manifest.toml)"

        if [ "${PY_KIND}" != "ok" ]; then
            archive_status="FAIL"
            archive_detail="${archive_detail}${archive_detail:+; }${stem}: cannot read manifest without Python ${SR_PYTHON_MIN}+"
            continue
        fi

        parts_text="$("${PY_PATH}" - "${manifest}" 2>/dev/null <<'PYEOF'
import sys
import tomllib

sys.stdout.reconfigure(newline="\n")
with open(sys.argv[1], "rb") as stream:
    data = tomllib.load(stream)
parts = data.get("part", [])
if not parts:
    raise SystemExit("manifest contains no archive parts")
for part in parts:
    print(part["file"])
PYEOF
        )" || {
            archive_status="FAIL"
            archive_detail="${archive_detail}${archive_detail:+; }${stem}: invalid or empty part manifest"
            continue
        }

        parts=()
        while IFS= read -r part_file; do
            [ -n "${part_file}" ] && parts+=("${part_file}")
        done <<< "${parts_text}"

        total=0
        manifest_problem=""
        for part_file in "${parts[@]}"; do
            case "${part_file}" in
                */*|*\\*|''|.|..)
                    manifest_problem="unsafe part name ${part_file}"
                    break
                    ;;
            esac
            part="${TOOLCHAIN_DIR}/${part_file}"
            if [ ! -f "${part}" ]; then
                manifest_problem="missing ${part_file}"
                archive_remedy="git lfs install && git lfs pull"
                break
            fi
            size="$(wc -c < "${part}" | tr -d ' ')"
            total=$((total + size))
            if [ "${size}" -lt 1024 ] \
               && head -1 "${part}" 2>/dev/null | grep -q '^version https://git-lfs'; then
                manifest_problem="${part_file} is a Git LFS pointer"
                archive_remedy="git lfs install && git lfs pull"
                break
            fi
        done

        if [ -n "${manifest_problem}" ]; then
            archive_status="FAIL"
            archive_detail="${archive_detail}${archive_detail:+; }${stem}: ${manifest_problem}"
        else
            archive_detail="${archive_detail}${archive_detail:+; }${stem}: ${#parts[@]} parts, $((total / 1048576)) MB"
        fi
    done

    if [ "${manifest_count}" -eq 0 ]; then
        report WARN "toolchain archive" "no builder manifests in ${TOOLCHAIN_DIR}"
    else
        report "${archive_status}" "toolchain archive" "${archive_detail}" \
            "${archive_remedy}"
    fi
fi

# --------------------------------------------------------------------------
printf '\narm64 build capability\n'

# The aarch64 (Raspberry Pi 4/5) builds run in linux/arm64 containers. Do not
# infer capability from a binfmt file: an enabled registration can name a
# missing interpreter, and a remote Docker context may use another kernel.
# Run a LOCAL image with pulling forbidden; --rm leaves no container behind.
# This is a WARN, never a FAIL: the x86_64 builds need none of it.
#
# ARM64_PROBE_IMAGE is overridable so tests and hosts with another known-local
# arm64 image do not need to mutate the image store.
if command -v "${ENGINE}" >/dev/null 2>&1 \
   && "${ENGINE}" info >/dev/null 2>&1 \
   && "${ENGINE}" run --rm --pull never --platform linux/arm64 \
        --entrypoint /usr/bin/true "${ARM64_PROBE_IMAGE}" >/dev/null 2>&1; then
    report PASS "arm64 containers" \
        "${ENGINE} executed linux/arm64 (${ARM64_PROBE_IMAGE})"
else
    report WARN "arm64 containers" \
        "${ENGINE} could not execute local probe image ${ARM64_PROBE_IMAGE}" \
        "Needed only for aarch64 builds. Ensure the probe image exists, then enable emulation once per boot with:
        ${ENGINE} run --privileged --rm ${BINFMT_IMAGE} --install arm64"
fi

# --------------------------------------------------------------------------
printf '\nRepository state\n'

if [ -f "${LOCK}" ]; then
    report PASS "lock file" "$(basename "${LOCK}")"
else
    report FAIL "lock file" "missing at ${LOCK}"
fi

if [ -d "${REPO_ROOT}/.git" ]; then
    # The sigrok stack used to live under 05_Software as git submodules,
    # each with its own pinned commit to verify. It is now vendored as plain
    # files in this repo - a normal clone brings everything, so all that is
    # left to check is that the vendored trees are actually present and not
    # some leftover empty directory from an interrupted checkout.
    missing=""
    for name in libsigrok libsigrokdecode sigrok-cli sigrok-util pulseview \
                libserialport libusb; do
        dir="${REPO_ROOT}/05_Software/${name}"
        [ -d "${dir}" ] && [ -n "$(ls -A "${dir}" 2>/dev/null)" ] && continue
        missing="${missing} ${name}"
    done

    if [ -n "${missing# }" ]; then
        report FAIL "vendored sources" "missing or empty:${missing}" \
            "git checkout -- 05_Software"
    else
        report PASS "vendored sources" "all present"
    fi
else
    report FAIL "git repository" "not a git checkout"
fi

# --------------------------------------------------------------------------
printf '\nUpstream access\n'

# Gitea is on a private network by design. Probe rather than assume, and
# never let ssh block on a prompt nobody can answer.
#
# This used to test connectivity against mirror-mxe.git specifically - one
# of the sigrok upstream mirrors. Those mirrors are gone (2026-08-19: the
# project moved to a single repo, nothing referenced them anymore), so the
# probe now targets this repo's own origin instead. That is a strictly
# better test anyway: it is the one remote every clone of this project
# actually needs, and it cannot go stale the way a specific mirror name can.
ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null)"
MIRROR_HOST="$(printf '%s' "${ORIGIN_URL}" | sed -n 's|ssh://git@\([^:]*\):.*|\1|p')"
MIRROR_PORT="$(printf '%s' "${ORIGIN_URL}" | sed -n 's|ssh://git@[^:]*:\([0-9]*\)/.*|\1|p')"

if [ -z "${MIRROR_HOST}" ]; then
    report WARN "git host" "origin is not an ssh:// remote (got '${ORIGIN_URL}')"
elif ! command -v git >/dev/null 2>&1; then
    :
else
    if [ -f "${HOME}/.ssh/id_ed25519.pub" ] || [ -f "${HOME}/.ssh/id_rsa.pub" ]; then
        report PASS "ssh identity" "a public key exists in ${HOME}/.ssh"
    else
        report FAIL "ssh identity" "no key in ${HOME}/.ssh" \
            "WSL has its own home directory; Windows keys are not visible here.
        ssh-keygen -t ed25519 -C \"\$(whoami)@\$(hostname)\"   then add the .pub to Gitea"
    fi

    if [ -n "${ORIGIN_URL}" ]; then
        if GIT_TERMINAL_PROMPT=0 \
           GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=8" \
           git ls-remote --heads "${ORIGIN_URL}" >/dev/null 2>&1; then
            report PASS "git host" "${MIRROR_HOST}:${MIRROR_PORT} reachable"
        else
            report FAIL "git host" "cannot reach ${MIRROR_HOST}:${MIRROR_PORT}" \
                "Gitea is LAN-only. Connect to that network, or pass
        --mxe-src to build_image.sh with a local MXE clone."
        fi
    fi
fi

# --------------------------------------------------------------------------
printf '\nCapacity\n'

# Docker and Podman expose different storage-root fields. An unavailable or
# unfamiliar engine falls back to that engine family's conventional path.
case "$(basename -- "${ENGINE}")" in
    podman)
        ENGINE_ROOT="$("${ENGINE}" info --format '{{.Store.GraphRoot}}' 2>/dev/null || true)"
        [ -n "${ENGINE_ROOT}" ] || ENGINE_ROOT=/var/lib/containers/storage
        ;;
    *)
        ENGINE_ROOT="$("${ENGINE}" info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
        [ -n "${ENGINE_ROOT}" ] || ENGINE_ROOT=/var/lib/docker
        ;;
esac
AVAIL_GB="$(df -BG --output=avail "${ENGINE_ROOT}" 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "${AVAIL_GB}" ]; then
    if [ "${AVAIL_GB}" -ge "${NEED_GB}" ]; then
        report PASS "disk (engine)" "${AVAIL_GB} GB free, need ~${NEED_GB} GB"
    else
        report FAIL "disk (engine)" "${AVAIL_GB} GB free, need ~${NEED_GB} GB" \
            "The image is ~7.3 GB unpacked and the build tree adds several more."
    fi
else
    report WARN "disk (engine)" "could not determine free space at ${ENGINE_ROOT}"
fi

CORES="$(nproc 2>/dev/null || echo 0)"
if [ "${CORES}" -ge 4 ]; then
    report PASS "cpu" "${CORES} cores"
else
    report WARN "cpu" "${CORES} cores - the toolchain build will be slow"
fi

# --------------------------------------------------------------------------
printf '\n'
if [ "${FAILED}" -gt 0 ]; then
    printf 'RESULT: %d failed, %d warnings. Fix the failures above.\n\n' \
        "${FAILED}" "${WARNED}"
else
    printf 'RESULT: ready. %d warnings.\n\n' "${WARNED}"
fi

if [ -n "${RESULT}" ]; then
    mkdir -p "$(dirname -- "${RESULT}")"
    cat > "${RESULT}" <<EOF
{
  "schema": 1,
  "tool": "check_host.sh",
  "host": "$(uname -srm)",
  "repo_root": "${REPO_ROOT}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "failed": ${FAILED},
  "warnings": ${WARNED},
  "checks": [${JSON_ROWS}
  ]
}
EOF
    printf 'record: %s\n' "${RESULT}"
fi

[ "${FAILED}" -eq 0 ]

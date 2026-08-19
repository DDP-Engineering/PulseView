#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Inspect the Linux build host and report whether it can build this project.
#
# Read-only by contract (02_Tools/bootstrap/README.md): this reports what is
# missing and the exact command to fix it, and installs nothing. It never
# touches git state, never writes outside --result, and needs no privileges.
#
# Run it inside the Linux build host - on Windows that means WSL:
#
#   wsl -d Ubuntu-24.04 -- /mnt/f/2026_Hantek_DSO3062L/02_Tools/bootstrap/check_host.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"

RESULT=""
IMAGE_TAG="hantek-builder-mingw:latest"

# Disk needed for the image plus one build tree. The image alone is ~7.3 GB
# unpacked; the build volume reaches a few GB more.
NEED_GB=30

usage() {
    cat <<'EOF'
Report whether this host can build the project. Changes nothing.

Options:
  --result PATH   Also write a JSON record here.
  --tag NAME      Builder image to look for. Default hantek-builder-mingw:latest.
  -h, --help      This text.

Exit status is 1 if any check FAILED, 0 otherwise. WARN does not fail.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --result) RESULT="${2:-}"; shift 2 ;;
        --tag)    IMAGE_TAG="${2:-}"; shift 2 ;;
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

check_tool git "git" "sudo apt-get install git"
check_tool docker "docker" "Install Docker Engine, or Docker Desktop with WSL integration enabled."

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
printf '\nDocker\n'

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        report PASS "docker daemon" "reachable"
        if docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
            report PASS "builder image" "${IMAGE_TAG} present"
        else
            report WARN "builder image" "${IMAGE_TAG} not present" \
                "Load the archive, or build it: 02_Tools/build/build_image.sh --image mingw"
        fi
    else
        report FAIL "docker daemon" "not reachable" \
            "Start Docker. If using Docker Desktop, enable WSL integration for this distro."
    fi
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

DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)"
AVAIL_GB="$(df -BG --output=avail "${DOCKER_ROOT}" 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "${AVAIL_GB}" ]; then
    if [ "${AVAIL_GB}" -ge "${NEED_GB}" ]; then
        report PASS "disk (docker)" "${AVAIL_GB} GB free, need ~${NEED_GB} GB"
    else
        report FAIL "disk (docker)" "${AVAIL_GB} GB free, need ~${NEED_GB} GB" \
            "The image is ~7.3 GB unpacked and the build tree adds several more."
    fi
else
    report WARN "disk (docker)" "could not determine free space at ${DOCKER_ROOT}"
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

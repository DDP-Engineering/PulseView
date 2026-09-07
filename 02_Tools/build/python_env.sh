#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One shared answer to "which Python can read this repository's pinned TOML".
# Sourced, never executed - the same shape as arch_map.sh next to it.
#
# The scripts that resolve pins (build_image.sh) and verify archive manifests
# (ensure_build_environment.sh) both parse TOML with tomllib, which is standard
# library only from CPython 3.11. A host with 3.10 has a python3 on PATH and
# fails inside a heredoc with a ModuleNotFoundError, which tells the operator
# nothing about what to install. Probing for the module rather than parsing a
# version string also covers a locally provided compatibility module: the
# question is whether the import works here, not what the version number says.
#
#   . "${BUILD_DIR}/python_env.sh"
#   sr_require_python          # sets SR_PYTHON or fails with a remedy
#
# On success SR_PYTHON holds the interpreter path. On failure the function
# writes an actionable message to stderr and returns 1; callers decide whether
# that is fatal (the build scripts) or one reported row (check_host.sh).

# The first release whose standard library carries tomllib.
SR_PYTHON_MIN="3.11"

# Interpreters worth trying, most-likely first. The bare names come first so a
# virtualenv or a distribution default wins over a parallel install.
SR_PYTHON_CANDIDATES="${SR_PYTHON_CANDIDATES:-python3 python python3.14 python3.13 python3.12 python3.11}"
SR_OS_RELEASE="${SR_OS_RELEASE:-/etc/os-release}"

SR_PYTHON="${SR_PYTHON:-}"

# Report a remedy that cannot leave the known host on the same incompatible
# interpreter. Ubuntu 22.04's `python3` package is 3.10, so repeating apt there
# is not a fix; the supported Ubuntu build host must first be upgraded to 24.04.
sr_python_remedy() {
    local distro_id="" distro_version=""
    if [ -r "${SR_OS_RELEASE}" ]; then
        distro_id="$(
            ID="" VERSION_ID=""
            # shellcheck disable=SC1090
            . "${SR_OS_RELEASE}"
            printf '%s' "${ID:-}"
        )"
        distro_version="$(
            ID="" VERSION_ID=""
            # shellcheck disable=SC1090
            . "${SR_OS_RELEASE}"
            printf '%s' "${VERSION_ID:-}"
        )"
    fi

    case "${distro_id}:${distro_version}" in
        ubuntu:20.*|ubuntu:22.*)
            printf '%s' 'Upgrade to Ubuntu 24.04, then run: sudo apt-get install python3'
            ;;
        ubuntu:*|debian:*)
            printf '%s' 'sudo apt-get install python3'
            ;;
        *)
            printf '%s' 'Install CPython 3.11 or newer with this system\047s package manager'
            ;;
    esac
}

# Echo the first candidate that can actually import tomllib. Returns 1 when
# none can, printing nothing.
sr_find_python() {
    local candidate resolved
    for candidate in ${SR_PYTHON_CANDIDATES}; do
        resolved="$(command -v "${candidate}" 2>/dev/null)" || continue
        if "${resolved}" -c 'import tomllib' >/dev/null 2>&1; then
            printf '%s' "${resolved}"
            return 0
        fi
    done
    return 1
}

# Report what is on this host, for a human-readable check row. Echoes one of
#   ok|<path>|<version line>
#   old|<path>|<version line>      an interpreter exists but has no tomllib
#   none||                         nothing on PATH at all
sr_python_status() {
    local resolved candidate version
    if resolved="$(sr_find_python)"; then
        version="$("${resolved}" --version 2>&1 | head -1)"
        printf 'ok|%s|%s' "${resolved}" "${version}"
        return 0
    fi
    for candidate in ${SR_PYTHON_CANDIDATES}; do
        resolved="$(command -v "${candidate}" 2>/dev/null)" || continue
        version="$("${resolved}" --version 2>&1 | head -1)"
        printf 'old|%s|%s' "${resolved}" "${version}"
        return 0
    done
    printf 'none||'
    return 0
}

# Set SR_PYTHON, or explain exactly what is missing and how to fix it.
sr_require_python() {
    local status kind path version
    status="$(sr_python_status)"
    kind="${status%%|*}"
    path="${status#*|}"; path="${path%%|*}"
    version="${status##*|}"

    if [ "${kind}" = "ok" ]; then
        SR_PYTHON="${path}"
        export SR_PYTHON
        return 0
    fi

    if [ "${kind}" = "old" ]; then
        printf 'error: %s cannot import tomllib (%s).\n' "${path}" "${version}" >&2
        printf '  This repository reads its pinned upstream lock and archive\n' >&2
        printf '  manifests with tomllib, which needs CPython %s or newer.\n' \
            "${SR_PYTHON_MIN}" >&2
    else
        printf 'error: no Python interpreter found on PATH.\n' >&2
        printf '  This repository reads its pinned upstream lock and archive\n' >&2
        printf '  manifests with tomllib, which needs CPython %s or newer.\n' \
            "${SR_PYTHON_MIN}" >&2
    fi
    printf '  Install one and retry:  %s\n' "$(sr_python_remedy)" >&2
    return 1
}

# END OF FILE

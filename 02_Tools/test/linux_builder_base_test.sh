#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The native Linux build must launch a base image pinned by digest in the
# upstream lock, the same way every other build path already does. A floating
# ubuntu:24.04 tag makes the release coordinator's Linux tarball
# unreproducible, and a lock without that entry must stop the build rather
# than silently fall back to the tag.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"
BUILD_LINUX="${REPO_ROOT}/02_Tools/build/build_linux.sh"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"

[ -f "${BUILD_LINUX}" ] || { echo "FAIL: missing ${BUILD_LINUX}" >&2; exit 1; }

PY="$(command -v python3 || command -v python || true)"
[ -n "${PY}" ] || { echo 'SKIP: no python on PATH' >&2; exit 77; }
"${PY}" -c 'import tomllib' 2>/dev/null \
    || { echo 'SKIP: host python cannot import tomllib' >&2; exit 77; }

# --print-base validates the launch prerequisites before reporting what would
# be launched, so it needs the engine to exist even though it starts nothing.
command -v "${BUILDER_ENGINE:-docker}" >/dev/null 2>&1 \
    || { echo 'SKIP: no container engine on PATH' >&2; exit 77; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# --------------------------------------------------------------------------
# The resolved base is the lock's immutable digest, not a tag
# --------------------------------------------------------------------------

BASE="$(bash "${BUILD_LINUX}" --print-base)"
case "${BASE}" in
    *@sha256:*) ;;
    *) echo "FAIL: resolved base is not digest-pinned: ${BASE}" >&2; exit 1 ;;
esac
printf '%s' "${BASE}" | grep -Eq '@sha256:[0-9a-f]{64}$' \
    || { echo "FAIL: base digest is malformed: ${BASE}" >&2; exit 1; }
case "${BASE}" in
    *ubuntu*) ;;
    *) echo "FAIL: resolved base is not an ubuntu image: ${BASE}" >&2; exit 1 ;;
esac

# The digest must be the one the lock actually records, not one baked into the
# script beside the lock entry.
LOCK_DIGEST="$("${PY}" - "${LOCK}" <<'PYEOF'
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    data = tomllib.load(stream)
for item in data.get("artifact", []):
    if item.get("name") == "builder-base-ubuntu-24.04":
        print(item.get("sha256", ""))
        break
else:
    raise SystemExit("FAIL: lock has no builder-base-ubuntu-24.04 artifact")
PYEOF
)"
[ -n "${LOCK_DIGEST}" ] || { echo 'FAIL: lock records no digest' >&2; exit 1; }
case "${BASE}" in
    *"${LOCK_DIGEST}"*) ;;
    *) echo "FAIL: resolved base ignores the lock digest" >&2; exit 1 ;;
esac

# --------------------------------------------------------------------------
# A lock without the entry stops the build, before any container starts
# --------------------------------------------------------------------------

"${PY}" - "${LOCK}" "${TMP}/nolock.toml" <<'PYEOF'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
# Drop the whole [[artifact]] block naming the Linux base.
blocks = re.split(r"\n(?=\[\[artifact\]\])", text)
kept = [b for b in blocks if 'name = "builder-base-ubuntu-24.04"' not in b]
if len(kept) == len(blocks):
    raise SystemExit("FAIL: no builder-base-ubuntu-24.04 block to remove")
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write("\n".join(kept))
PYEOF

if bash "${BUILD_LINUX}" --lock "${TMP}/nolock.toml" --print-base \
       >"${TMP}/missing.out" 2>&1; then
    echo 'FAIL: a lock without the base entry was accepted' >&2
    cat "${TMP}/missing.out" >&2
    exit 1
fi
grep -q 'builder-base-ubuntu-24.04' "${TMP}/missing.out" \
    || { echo 'FAIL: the error does not name the missing lock entry' >&2
         cat "${TMP}/missing.out" >&2; exit 1; }

# --------------------------------------------------------------------------
# No floating tag survives in the launch path
# --------------------------------------------------------------------------

if grep -nE '^[^#]*[^-a-zA-Z0-9_/.]ubuntu:24\.04' "${BUILD_LINUX}"; then
    echo 'FAIL: build_linux.sh still references the floating ubuntu:24.04 tag' >&2
    exit 1
fi

printf 'linux builder base: all assertions passed\n'
exit 0

# END OF FILE

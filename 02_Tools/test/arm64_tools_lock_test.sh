#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-PLAT-0e73bea7: the arm64 AppImage builder installs its packaging tools
# only from artifacts pinned in upstreams.lock.toml - HTTPS URL plus SHA-256
# - and the Dockerfile verifies every one of those digests before install.
# That includes the type-2 AppImage RUNTIME: appimagetool downloads it at
# packaging time unless --runtime-file is passed, which would put a network
# fetch inside a build that claims to be offline. Both architectures'
# runtimes are pinned and baked for the same reason the tools are.
# The image build itself takes a network and a container engine; the pinning
# discipline it depends on is checkable everywhere, so that part is a test
# rather than something a reviewer has to remember to inspect.
#
# Needs a python3 with tomllib (3.11+), same floor build_image.sh already has.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
LOCK="${REPO}/02_Tools/upstream/upstreams.lock.toml"
DOCKERFILE="${REPO}/02_Tools/build/images/Dockerfile.appimage"
BUILD_IMAGE="${REPO}/02_Tools/build/build_image.sh"

PY="$(command -v python3 || command -v python)" || {
    printf 'SKIP: no python available\n'; exit 77; }
"${PY}" -c 'import tomllib' 2>/dev/null || {
    printf 'SKIP: python has no tomllib (needs 3.11+)\n'; exit 77; }

FAILURES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

# --- every aarch64 packaging tool is pinned: https URL + 64-hex sha256 ---
OUT="$("${PY}" - "${LOCK}" <<'PYEOF'
import re, sys, tomllib
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
arts = {a.get("name"): a for a in data.get("artifact", [])}
# name -> architecture token its URL must carry
needed = {
    "appimagetool-aarch64": "aarch64",
    "linuxdeployqt-aarch64": "aarch64",
    "appimage-runtime-aarch64": "aarch64",
    "appimage-runtime-x86_64": "x86_64",
}
bad = 0
for name, arch in needed.items():
    a = arts.get(name)
    if a is None:
        print(f"missing artifact '{name}'"); bad = 1; continue
    url = a.get("url", "")
    if not url.startswith("https://"):
        print(f"{name}: url is not https: '{url}'"); bad = 1
    if arch not in url:
        print(f"{name}: url does not name an {arch} asset: '{url}'"); bad = 1
    sha = a.get("sha256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        print(f"{name}: sha256 is not 64 lowercase hex: '{sha}'"); bad = 1
    if not a.get("version"):
        print(f"{name}: no version pinned"); bad = 1
sys.exit(bad)
PYEOF
)" || fail "lock entries: ${OUT}"

# --- the Dockerfile bakes the runtime and verifies what it downloads ------
grep -q 'APPIMAGE_RUNTIME_URL' "${DOCKERFILE}" \
    || fail "Dockerfile.appimage never installs a pinned AppImage runtime"
WGETS="$(grep -c 'wget -O' "${DOCKERFILE}")"
CHECKS="$(grep -c 'sha256sum -c' "${DOCKERFILE}")"
[ "${CHECKS}" -ge "${WGETS}" ] \
    || fail "Dockerfile.appimage: ${WGETS} downloads but only ${CHECKS} sha256sum -c verifications"

# --- the AppImage-format tools must be executable under qemu binfmt -------
# The type-2 AppImage magic AI\x02 at ELF offset 8 defeats qemu's
# binfmt_misc magic match, so an emulated arm64 container cannot exec the
# tools at all ("Exec format error" - the first emulated build died there).
# The Dockerfile zeroes those three padding bytes after verifying each
# tool's checksum; the kernel and the tools themselves never read them.
MAGIC_FIXES="$(grep -c 'seek=8 count=3 conv=notrunc' "${DOCKERFILE}")"
[ "${MAGIC_FIXES}" -ge 2 ] \
    || fail "Dockerfile.appimage neutralizes the AppImage magic on ${MAGIC_FIXES} tool(s), expected both appimagetool and linuxdeployqt"

# --- the packer is told to use the baked runtime, not the network ---------
grep -q -- '--runtime-file' "${REPO}/02_Tools/build/build_appimage.sh" \
    || fail "build_appimage.sh never passes --runtime-file to appimagetool"

# --- build_image.sh feeds the arm64 pins from the lock, not from thin air ---
grep -q 'linuxdeployqt-aarch64' "${BUILD_IMAGE}" \
    || fail "build_image.sh never reads the linuxdeployqt-aarch64 lock entry"
grep -q 'appimagetool-aarch64' "${BUILD_IMAGE}" \
    || fail "build_image.sh never reads the appimagetool-aarch64 lock entry"
grep -q 'appimage-runtime-' "${BUILD_IMAGE}" \
    || fail "build_image.sh never reads the appimage-runtime lock entries"

if [ "${FAILURES}" -gt 0 ]; then
    printf '%d assertion(s) failed\n' "${FAILURES}" >&2
    exit 1
fi
printf 'arm64 tool pinning: all assertions passed\n'
exit 0

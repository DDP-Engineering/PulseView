#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The build-environment archive must split deterministically, verify every
# local Git LFS part, restore the exact image, reject corruption, and avoid
# touching the archive when an already-installed image is valid.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"
ENSURE="${REPO_ROOT}/02_Tools/bootstrap/ensure_build_environment.sh"
SAVE="${REPO_ROOT}/02_Tools/build/save_image_parts.sh"
LOCK="${REPO_ROOT}/02_Tools/upstream/upstreams.lock.toml"

python3 - "${LOCK}" <<'PYEOF'
import re
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    data = tomllib.load(stream)
artifacts = {item["name"]: item for item in data.get("artifact", [])}
for name in ("builder-base-debian-bookworm-slim", "builder-base-ubuntu-22.04"):
    item = artifacts.get(name)
    if item is None:
        raise SystemExit(f"FAIL: lock has no {name}")
    match = re.fullmatch(r"docker://.+@sha256:([0-9a-f]{64})", item.get("url", ""))
    if match is None or match.group(1) != item.get("sha256"):
        raise SystemExit(f"FAIL: {name} is not pinned by a matching digest")
PYEOF

ATTR="$(git -C "${REPO_ROOT}" check-attr filter -- \
    07_Delivery/toolchain/example.tar.part-001 | awk '{print $3}')"
[ "${ATTR}" = "lfs" ] \
    || { echo 'FAIL: multipart image files are not tracked by Git LFS' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
STATE="${TMP}/engine-state"
FAKE_ENGINE="${TMP}/fake-engine"
FIXTURE_ARCHIVE="${TMP}/fixture.tar"
export STATE FIXTURE_ARCHIVE

dd if=/dev/zero of="${FIXTURE_ARCHIVE}" bs=1024 count=1536 2>/dev/null
printf 'pulseview multipart archive fixture\n' | dd of="${FIXTURE_ARCHIVE}" \
    conv=notrunc 2>/dev/null

cat > "${FAKE_ENGINE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Every invocation is recorded so a test can assert what the restore did NOT
# do. "Failed closed" means no image was loaded, not merely a non-zero exit.
mkdir -p "${STATE}"
printf '%s\n' "$*" >> "${STATE}/calls"

case "${1:-}" in
    image)
        [ "${2:-}" = "inspect" ] || exit 2
        [ -f "${STATE}/installed" ] || exit 1
        if [ "${3:-}" = "--format" ]; then
            case "${4:-}" in
                '{{.Id}}|{{.Architecture}}') printf '%s\n' 'sha256:fixture|amd64' ;;
                '{{.Id}}') printf '%s\n' 'sha256:fixture' ;;
                *) printf '\n' ;;
            esac
        fi
        ;;
    run)
        [ -f "${STATE}/installed" ] || exit 1
        ;;
    load)
        [ "${2:-}" = "--input" ] || exit 2
        cmp -s "${3}" "${FIXTURE_ARCHIVE}" || exit 1
        mkdir -p "${STATE}"
        : > "${STATE}/installed"
        printf 'Loaded image: pulseview-builder-mingw:latest\n'
        ;;
    save)
        [ "${2:-}" = "--output" ] || exit 2
        cp "${FIXTURE_ARCHIVE}" "${3}"
        ;;
    *) exit 2 ;;
esac
EOF
chmod +x "${FAKE_ENGINE}"

mkdir -p "${STATE}"
: > "${STATE}/installed"
OUT="${TMP}/out"
bash "${SAVE}" --image mingw --engine "${FAKE_ENGINE}" \
    --out-dir "${OUT}" --part-size-mib 1 >/dev/null

MANIFEST="${OUT}/pulseview-builder-mingw.manifest.toml"
[ -f "${MANIFEST}" ] || { echo 'FAIL: save did not write the manifest' >&2; exit 1; }
[ "$(find "${OUT}" -name '*.part-*' | wc -l | tr -d ' ')" = 2 ] \
    || { echo 'FAIL: fixture was not split into two parts' >&2; exit 1; }

rm -f "${STATE}/installed"
bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
    --manifest "${MANIFEST}" --force-restore --no-rebuild >/dev/null
[ -f "${STATE}/installed" ] \
    || { echo 'FAIL: verified multipart archive was not loaded' >&2; exit 1; }
[ ! -f "${REPO_ROOT}/.work/bootstrap/pulseview-builder-mingw.tar" ] \
    || { echo 'FAIL: reconstructed archive was not removed' >&2; exit 1; }

# A valid installed image does not need its archive parts to remain available.
mkdir -p "${TMP}/held"
mv "${OUT}"/*.part-* "${TMP}/held/"
bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
    --manifest "${MANIFEST}" --no-rebuild >/dev/null
mv "${TMP}/held"/*.part-* "${OUT}/"

# Corruption must fail closed and must not invoke a rebuild when disabled.
rm -f "${STATE}/installed"
printf 'corruption' >> "${OUT}/pulseview-builder-mingw.tar.part-001"
if bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
    --manifest "${MANIFEST}" --force-restore --no-rebuild \
    >"${TMP}/corrupt.out" 2>&1; then
    echo 'FAIL: corrupt archive part was accepted' >&2
    exit 1
fi
grep -q 'size mismatch\|checksum mismatch' "${TMP}/corrupt.out" \
    || { echo 'FAIL: corruption error was not actionable' >&2; exit 1; }

# A malformed manifest is another recoverable archive failure. It must reach
# the rebuild policy instead of terminating in the TOML parser.
printf '\ninvalid = [\n' >> "${MANIFEST}"
if bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
    --manifest "${MANIFEST}" --force-restore --no-rebuild \
    >"${TMP}/manifest.out" 2>&1; then
    echo 'FAIL: malformed manifest was accepted' >&2
    exit 1
fi
grep -q 'invalid archive manifest' "${TMP}/manifest.out" \
    || { echo 'FAIL: malformed manifest error was not actionable' >&2; exit 1; }
grep -q 'online rebuild disabled' "${TMP}/manifest.out" \
    || { echo 'FAIL: malformed manifest bypassed the rebuild policy' >&2; exit 1; }

# --------------------------------------------------------------------------
# Fail-closed paths that the restore already contained but nothing exercised:
# a part named by the manifest that is not there, a part that is still a Git
# LFS pointer, and a set of parts that each verify while the archive they join
# into does not. All three must stop before the engine is asked to load
# anything.
# --------------------------------------------------------------------------

OUT2="${TMP}/out2"
MANIFEST2="${OUT2}/pulseview-builder-mingw.manifest.toml"
mkdir -p "${STATE}"
: > "${STATE}/installed"
bash "${SAVE}" --image mingw --engine "${FAKE_ENGINE}" \
    --out-dir "${OUT2}" --part-size-mib 1 >/dev/null
cp "${MANIFEST2}" "${TMP}/manifest2.pristine"

# The reconstructed archive must never be left behind by a failed restore.
WORK_ARCHIVE="${REPO_ROOT}/.work/bootstrap/pulseview-builder-mingw.tar"

# Drive one failing restore and return its output file. Asserts the shared
# postconditions: non-zero exit, no engine load, no leftover archive.
expect_closed() {
    local label="$1" out="$2"
    rm -f "${STATE}/installed" "${STATE}/calls"
    if bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
        --manifest "${MANIFEST2}" --force-restore --no-rebuild \
        >"${out}" 2>&1; then
        echo "FAIL: ${label} was accepted" >&2
        exit 1
    fi
    if [ -f "${STATE}/calls" ] && grep -q '^load' "${STATE}/calls"; then
        echo "FAIL: ${label} still reached an image load" >&2
        exit 1
    fi
    [ ! -f "${WORK_ARCHIVE}" ] \
        || { echo "FAIL: ${label} left a reconstructed archive behind" >&2; exit 1; }
    [ ! -f "${STATE}/installed" ] \
        || { echo "FAIL: ${label} installed an image" >&2; exit 1; }
}

# 1. A part the manifest names is missing entirely.
mv "${OUT2}/pulseview-builder-mingw.tar.part-002" "${TMP}/withheld.part"
expect_closed 'a missing archive part' "${TMP}/missing.out"
grep -q 'missing archive part' "${TMP}/missing.out" \
    || { echo 'FAIL: the missing-part error is not actionable' >&2
         cat "${TMP}/missing.out" >&2; exit 1; }
grep -q 'part-002' "${TMP}/missing.out" \
    || { echo 'FAIL: the missing-part error does not name the part' >&2; exit 1; }
mv "${TMP}/withheld.part" "${OUT2}/pulseview-builder-mingw.tar.part-002"

# 2. A clone without Git LFS: the part is a 130-byte pointer, not content.
cp "${OUT2}/pulseview-builder-mingw.tar.part-002" "${TMP}/real.part"
cat > "${OUT2}/pulseview-builder-mingw.tar.part-002" <<'PTR'
version https://git-lfs.github.com/spec/v1
oid sha256:1111111111111111111111111111111111111111111111111111111111111111
size 1048576
PTR
expect_closed 'a Git LFS pointer part' "${TMP}/pointer.out"
grep -qi 'lfs' "${TMP}/pointer.out" \
    || { echo 'FAIL: the pointer error does not mention Git LFS' >&2
         cat "${TMP}/pointer.out" >&2; exit 1; }
grep -q 'git lfs pull' "${TMP}/pointer.out" \
    || { echo 'FAIL: the pointer error offers no remedy' >&2; exit 1; }
cp "${TMP}/real.part" "${OUT2}/pulseview-builder-mingw.tar.part-002"

# 3. Every part matches its own digest, but the whole archive does not match
#    the one the manifest claims. Only the final check can catch this.
python3 - "${MANIFEST2}" <<'PYEOF'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
new, count = re.subn(
    r'^archive_sha256 = "[0-9a-f]{64}"$',
    'archive_sha256 = "' + "9" * 64 + '"',
    text,
    count=1,
    flags=re.M,
)
if count != 1:
    raise SystemExit("FAIL: could not rewrite archive_sha256")
open(path, "w", encoding="utf-8", newline="\n").write(new)
PYEOF
expect_closed 'a whole-archive digest mismatch' "${TMP}/whole.out"
grep -q 'reconstructed archive checksum mismatch' "${TMP}/whole.out" \
    || { echo 'FAIL: the whole-archive error is not actionable' >&2
         cat "${TMP}/whole.out" >&2; exit 1; }
cp "${TMP}/manifest2.pristine" "${MANIFEST2}"

# The same parts, unmolested, must still restore - otherwise the three
# assertions above would pass on a restore that never works at all.
rm -f "${STATE}/installed" "${STATE}/calls"
bash "${ENSURE}" --image mingw --engine "${FAKE_ENGINE}" \
    --manifest "${MANIFEST2}" --force-restore --no-rebuild >/dev/null
[ -f "${STATE}/installed" ] \
    || { echo 'FAIL: the repaired archive no longer restores' >&2; exit 1; }

printf 'build environment archive: all assertions passed\n'
exit 0

# END OF FILE

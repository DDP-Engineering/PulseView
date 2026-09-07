#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Schema-2 archive save/restore verifies every local LFS-sized part while
# current installed-image reuse remains independent of all archive files.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
ENSURE="${REPO}/02_Tools/bootstrap/ensure_build_environment.sh"
SAVE="${REPO}/02_Tools/build/save_image_parts.sh"
LOCK="${REPO}/02_Tools/upstream/upstreams.lock.toml"
PY="$(command -v python3 || command -v python)" || {
    echo 'SKIP: Python unavailable' >&2; exit 77; }

"${PY}" - "${LOCK}" <<'PYEOF'
import re, sys, tomllib
with open(sys.argv[1], "rb") as stream: data=tomllib.load(stream)
a={x["name"]:x for x in data.get("artifact",[])}
for name in ("builder-base-debian-bookworm-slim","builder-base-ubuntu-22.04"):
    item=a.get(name); match=re.fullmatch(r"docker://.+@sha256:([0-9a-f]{64})", item.get("url","") if item else "")
    if match is None or match.group(1) != item.get("sha256"): raise SystemExit(f"FAIL: {name} is not digest-pinned")
PYEOF

ATTR="$(git -C "${REPO}" check-attr filter -- \
    07_Delivery/toolchain/example.tar.part-001 | awk '{print $3}')"
[ "${ATTR}" = lfs ] || { echo 'FAIL: archive parts are not Git LFS paths' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
STATE="${TMP}/state"; mkdir -p "${STATE}"
FIXTURE="${TMP}/fixture.tar"
dd if=/dev/zero of="${FIXTURE}" bs=1024 count=1536 2>/dev/null
printf 'builder archive fixture\n' | dd of="${FIXTURE}" conv=notrunc 2>/dev/null
IMAGE_ID="$(printf image | sha256sum | cut -d' ' -f1)"
RECIPE="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind recipe)"
CONTRACT="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind contract)"
POLICY="$(bash "${REPO}/02_Tools/build/builder_spec.sh" --image appimage --platform amd64 --kind validation)"
"${PY}" "${REPO}/02_Tools/build/dependency_contract.py" normalize \
    --contract "${REPO}/02_Tools/build/images/dependencies.appimage.toml" \
    --image appimage --platform amd64 --lock "${LOCK}" \
    --output "${STATE}/contract.json" >/dev/null
printf '{"packages":[{"architecture":"amd64","name":"cmake","version":"1"}],"schema":1}\n' \
    >"${STATE}/inventory.json"
INVENTORY="$(sha256sum "${STATE}/inventory.json" | cut -d' ' -f1)"
[ "$(sha256sum "${STATE}/contract.json" | cut -d' ' -f1)" = "${CONTRACT}" ] \
    || { echo 'FAIL: fixture contract identity mismatch' >&2; exit 1; }
export STATE FIXTURE IMAGE_ID RECIPE CONTRACT INVENTORY
: >"${STATE}/installed"

ENGINE="${TMP}/engine"
cat >"${ENGINE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${STATE}/calls"
case "${1:-}" in
 image)
  case "${2:-}" in
   inspect)
    [ -f "${STATE}/installed" ] || exit 1
    format=""; while [ $# -gt 0 ]; do [ "$1" = --format ] && { format="$2"; break; }; shift; done
    case "${format}" in
     '') ;;
     '{{.Id}}') echo "sha256:${IMAGE_ID}" ;;
     '{{.Id}}|{{.Architecture}}') echo "sha256:${IMAGE_ID}|amd64" ;;
     '{{index .Config.Labels "io.ddp.builder.image"}}') echo appimage ;;
     '{{index .Config.Labels "io.ddp.builder.recipe-spec"}}') echo "${RECIPE}" ;;
     '{{index .Config.Labels "io.ddp.builder.dependency-contract-spec"}}') echo "${CONTRACT}" ;;
     '{{index .Config.Labels "io.ddp.builder.normalized-contract-sha256"}}') echo "${CONTRACT}" ;;
     '{{index .Config.Labels "io.ddp.builder.resolved-inventory-sha256"}}') echo "${INVENTORY}" ;;
     *) exit 2 ;;
    esac ;;
   rm) rm -f "${STATE}/installed" ;;
   *) exit 2 ;;
  esac ;;
 create) : >"${STATE}/container" ;;
 cp)
  case "$2" in
   *dependency-contract.json) cp "${STATE}/contract.json" "$3" ;;
   *resolved-inventory.json) cp "${STATE}/inventory.json" "$3" ;;
   *) exit 2 ;;
  esac ;;
 rm) rm -f "${STATE}/container" ;;
 save) [ "$2" = --output ] || exit 2; cp "${FIXTURE}" "$3" ;;
 load) [ "$2" = --input ] || exit 2; cmp -s "$3" "${FIXTURE}" || exit 1; : >"${STATE}/installed" ;;
 tag) : >"${STATE}/installed" ;;
 *) exit 2 ;;
esac
EOF
chmod +x "${ENGINE}"
VERIFIER="${TMP}/verifier"
printf '#!/usr/bin/env bash\nexit 0\n' >"${VERIFIER}"; chmod +x "${VERIFIER}"

OUT="${TMP}/out"
bash "${SAVE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --validation-policy-spec "${POLICY}" --out-dir "${OUT}" \
    --part-size-mib 1 >/dev/null
MANIFEST="${OUT}/pulseview-builder-appimage.manifest.toml"
[ -f "${MANIFEST}" ] || { echo 'FAIL: save wrote no stable manifest' >&2; exit 1; }
mapfile -t PARTS < <(find "${OUT}" -maxdepth 1 -name '*.part-*' -type f | sort)
[ "${#PARTS[@]}" -eq 2 ] || { echo 'FAIL: archive did not split into two parts' >&2; exit 1; }
"${PY}" "${REPO}/02_Tools/build/builder_manifest.py" verify \
    --manifest "${MANIFEST}" --mode archive >/dev/null

# Interruption immediately after manifest rename leaves a complete committed
# generation rather than a manifest whose referenced files were cleaned up.
INTERRUPTED="${TMP}/interrupted"
if bash "${SAVE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --validation-policy-spec "${POLICY}" --out-dir "${INTERRUPTED}" \
    --part-size-mib 1 --fail-after manifest-committed >/dev/null 2>&1; then
    echo 'FAIL: injected post-manifest interruption passed' >&2
    exit 1
fi
"${PY}" "${REPO}/02_Tools/build/builder_manifest.py" verify \
    --manifest "${INTERRUPTED}/pulseview-builder-appimage.manifest.toml" \
    --mode archive >/dev/null \
    || { echo 'FAIL: post-manifest interruption damaged committed generation' >&2; exit 1; }

rm -f "${STATE}/installed"
bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" --manifest "${MANIFEST}" \
    --force-restore --no-rebuild >/dev/null
[ -f "${STATE}/installed" ] || { echo 'FAIL: verified archive was not loaded' >&2; exit 1; }

# Current installed selection remains valid with manifest and every part absent.
mkdir "${TMP}/held"; mv "${PARTS[@]}" "${TMP}/held/"; mv "${MANIFEST}" "${TMP}/held/"
bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" --manifest "${MANIFEST}" --no-rebuild >/dev/null
mv "${TMP}/held"/* "${OUT}/"

# Schema-1 archives are identified as legacy and require their temporary,
# explicit migration option.
LEGACY="${TMP}/legacy"; mkdir -p "${LEGACY}"
split --bytes 1M --numeric-suffixes=1 --suffix-length=3 \
    "${FIXTURE}" "${LEGACY}/legacy.tar.part-"
{
    cat <<EOF
schema = 1
format = "docker-archive"
image = "appimage"
platform = "linux/amd64"
tag = "pulseview-builder-appimage:latest"
image_id = "sha256:${IMAGE_ID}"
builder_spec = ""
archive = "legacy.tar"
archive_size = $(wc -c <"${FIXTURE}" | tr -d ' ')
archive_sha256 = "$(sha256sum "${FIXTURE}" | cut -d' ' -f1)"
EOF
    while IFS= read -r part; do
        printf '\n[[part]]\nfile = "%s"\nsize = %s\nsha256 = "%s"\n' \
            "$(basename "${part}")" "$(wc -c <"${part}" | tr -d ' ')" \
            "$(sha256sum "${part}" | cut -d' ' -f1)"
    done < <(find "${LEGACY}" -name '*.part-*' -type f | sort)
} >"${LEGACY}/legacy.manifest.toml"
rm -f "${STATE}/installed"
if bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" --manifest "${LEGACY}/legacy.manifest.toml" \
    --force-restore --no-rebuild >"${TMP}/legacy-denied.out" 2>&1; then
    echo 'FAIL: schema-1 archive passed without legacy mode' >&2
    exit 1
fi
grep -qi 'schema-1.*--allow-legacy-restore' "${TMP}/legacy-denied.out" \
    || { echo 'FAIL: legacy rejection did not explain migration option' >&2; exit 1; }
rm -f "${STATE}/installed"
bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" --manifest "${LEGACY}/legacy.manifest.toml" \
    --force-restore --allow-legacy-restore --no-rebuild >/dev/null
[ -f "${STATE}/installed" ] || { echo 'FAIL: explicit legacy restore did not load' >&2; exit 1; }

# A stale schema-2 generation requires explicit historical mode and produces a
# prominent warning before embedded-contract verification.
CURRENT_RECIPE="${RECIPE}"
RECIPE="$(printf historical | sha256sum | cut -d' ' -f1)"; export RECIPE
HIST="${TMP}/historical"; : >"${STATE}/installed"
bash "${SAVE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --validation-policy-spec "${POLICY}" --out-dir "${HIST}" --part-size-mib 1 >/dev/null
RECIPE="${CURRENT_RECIPE}"; export RECIPE
rm -f "${STATE}/installed"
TAGS_BEFORE="$(grep -c '^tag ' "${STATE}/calls" || true)"
if bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" \
    --manifest "${HIST}/pulseview-builder-appimage.manifest.toml" \
    --force-restore --no-rebuild >"${TMP}/historical-denied.out" 2>&1; then
    echo 'FAIL: stale schema-2 archive passed without historical mode' >&2
    exit 1
fi
grep -q -- '--allow-historical-builder' "${TMP}/historical-denied.out" \
    || { echo 'FAIL: stale archive did not explain historical mode' >&2; exit 1; }
TAGS_AFTER="$(grep -c '^tag ' "${STATE}/calls" || true)"
[ "${TAGS_AFTER}" = "${TAGS_BEFORE}" ] \
    || { echo 'FAIL: rejected stale archive changed the normal-use tag' >&2; exit 1; }
rm -f "${STATE}/installed"
bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --verifier-command "${VERIFIER}" \
    --manifest "${HIST}/pulseview-builder-appimage.manifest.toml" \
    --force-restore --allow-historical-builder --no-rebuild \
    >"${TMP}/historical.out" 2>&1
grep -q 'WARNING: HISTORICAL BUILDER' "${TMP}/historical.out" \
    || { echo 'FAIL: historical restore warning is not prominent' >&2; exit 1; }

expect_closed() {
    local label="$1" needle="$2"
    rm -f "${STATE}/installed" "${STATE}/calls"
    if bash "${ENSURE}" --image appimage --platform amd64 --engine "${ENGINE}" \
        --verifier-command "${VERIFIER}" --manifest "${MANIFEST}" \
        --force-restore --no-rebuild >"${TMP}/failure.out" 2>&1; then
        echo "FAIL: ${label} was accepted" >&2; exit 1
    fi
    grep -qi "${needle}" "${TMP}/failure.out" \
        || { echo "FAIL: ${label} error is not actionable" >&2; cat "${TMP}/failure.out" >&2; exit 1; }
    [ ! -f "${STATE}/calls" ] || ! grep -q '^load ' "${STATE}/calls" \
        || { echo "FAIL: ${label} reached engine load" >&2; exit 1; }
}

# Missing part, LFS pointer, checksum mutation, and malformed manifest fail closed.
LAST="${PARTS[1]}"; mv "${LAST}" "${TMP}/part"
expect_closed 'missing part' 'missing\|not a regular file'
mv "${TMP}/part" "${LAST}"
cp "${LAST}" "${TMP}/part"
cat >"${LAST}" <<'EOF'
version https://git-lfs.github.com/spec/v1
oid sha256:1111111111111111111111111111111111111111111111111111111111111111
size 1
EOF
expect_closed 'LFS pointer' 'size mismatch\|checksum mismatch'
mv "${TMP}/part" "${LAST}"
printf x >>"${LAST}"
expect_closed 'changed part' 'size mismatch\|checksum mismatch'
printf '%s' "${FIXTURE}" >/dev/null
# Restore pristine generation by saving afresh in a second directory for syntax test.
OUT2="${TMP}/out2"; : >"${STATE}/installed"
bash "${SAVE}" --image appimage --platform amd64 --engine "${ENGINE}" \
    --validation-policy-spec "${POLICY}" --out-dir "${OUT2}" --part-size-mib 1 >/dev/null
MANIFEST="${OUT2}/pulseview-builder-appimage.manifest.toml"
printf '\ninvalid = [\n' >>"${MANIFEST}"
expect_closed 'malformed manifest' 'invalid archive manifest'

printf 'build environment archive: all assertions passed\n'

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Execute candidate CLI, required drivers and one decoder in a clean local base.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
GENERATOR="${HERE}/gen_networking_stack_captures.py"
APPIMAGE="${APPIMAGE_PATH:-}"
ARCH="${BUILDER_ARCHITECTURE:-amd64}"
ENGINE="${BUILDER_ENGINE:-docker}"
[ -n "${APPIMAGE}" ] && [ -f "${APPIMAGE}" ] \
    || { echo 'SKIP: APPIMAGE_PATH is not a built file'; exit 77; }
PY="$(command -v python3 || command -v python || true)"
[ -n "${PY}" ] || { echo 'SKIP: Python unavailable for runtime validation'; exit 77; }
BASE="${APPIMAGE_RUNTIME_IMAGE:-}"
if [ -z "${BASE}" ]; then
    BASE="$("${PY}" - "${REPO}/02_Tools/upstream/upstreams.lock.toml" <<'PYEOF'
from pathlib import Path
import sys
import tomllib

lock = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
matches = [
    item for item in lock.get("artifact", [])
    if item.get("name") == "builder-base-ubuntu-22.04"
]
if len(matches) != 1:
    raise SystemExit("lock must contain one builder-base-ubuntu-22.04 artifact")
entry = matches[0]
url = entry.get("url", "")
digest = entry.get("sha256", "")
if url != f"docker://docker.io/library/ubuntu@sha256:{digest}":
    raise SystemExit("runtime base URL and SHA-256 pin do not agree")
print(url.removeprefix("docker://"))
PYEOF
    )"
fi
command -v "${ENGINE}" >/dev/null 2>&1 \
    || { echo "SKIP: ${ENGINE} unavailable"; exit 77; }
"${ENGINE}" image inspect "${BASE}" >/dev/null 2>&1 \
    || { echo "SKIP: local runtime image unavailable: ${BASE}"; exit 77; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
cp "${APPIMAGE}" "${TMP}/PulseView.AppImage"
chmod +x "${TMP}/PulseView.AppImage"
"${PY}" "${GENERATOR}" "${TMP}" >/dev/null
case "$(uname -m):${ARCH}" in
    x86_64:arm64|amd64:arm64|aarch64:amd64|arm64:amd64)
        printf '\0\0\0' | dd of="${TMP}/PulseView.AppImage" bs=1 seek=8 \
            count=3 conv=notrunc status=none ;;
esac
cat >"${TMP}/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export APPIMAGE_EXTRACT_AND_RUN=1
AI=/candidate/PulseView.AppImage
"${AI}" --cli --version | grep -q '^sigrok-cli '
LIST="$("${AI}" --cli -L)"
printf '%s\n' "${LIST}" | grep -q '^[[:space:]]*hantek-dso3062l[[:space:]]'
printf '%s\n' "${LIST}" | grep -q '^[[:space:]]*atk-dl16[[:space:]]'
"${AI}" --cli -P uart --show | grep -q '^ID: uart$'
ARP="$("${AI}" --cli -i /candidate/arp_capture.bin \
    -I binary:numchannels=1:samplerate=1000000 \
    -P nrzi:preamble_len=4,4b5b,ethernet,arp)"
printf '%s\n' "${ARP}" | grep -q 'Frame Check Sequence: OK'
printf '%s\n' "${ARP}" | grep -q 'Operation: Request'
UDP="$("${AI}" --cli -i /candidate/ipv4_udp_capture.bin \
    -I binary:numchannels=1:samplerate=1000000 \
    -P nrzi:preamble_len=4,4b5b,ethernet,ipv4,udp:format=ascii)"
printf '%s\n' "${UDP}" | grep -q 'Header Checksum: OK'
printf '%s\n' "${UDP}" | grep -q 'Checksum: OK'
EOF
chmod +x "${TMP}/verify.sh"
"${ENGINE}" run --rm --pull never --network none --platform "linux/${ARCH}" \
    --volume "${TMP}:/candidate:ro" "${BASE}" bash /candidate/verify.sh
printf 'AppImage clean-base runtime passed: %s on %s\n' "${ARCH}" "${BASE}"

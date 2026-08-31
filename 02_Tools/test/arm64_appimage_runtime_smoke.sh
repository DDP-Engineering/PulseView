#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-PLAT-aa8d5d46: execute the aarch64 delivery, both project drivers and
# one Python protocol decoder. Native arm64 runs the pristine AppImage;
# x86_64 may replay the same checks in a known-local bare arm64 container.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
AI="${ARM64_APPIMAGE:-${REPO}/07_Delivery/PulseView-aarch64.AppImage}"

[ -f "${AI}" ] || { echo "SKIP: ${AI} not built"; exit 77; }
if head -c 40 "${AI}" | grep -q '^version https://git-lfs'; then
    echo "SKIP: ${AI} is an unsmudged Git LFS pointer"
    exit 77
fi

verify_cli() {
    local -a command=("$@")
    local out
    out="$(APPIMAGE_EXTRACT_AND_RUN=1 "${command[@]}" --cli --version 2>&1)"
    printf '%s\n' "${out}" | grep -q '^sigrok-cli ' || {
        echo "FAIL: --cli --version did not identify sigrok-cli" >&2
        return 1
    }
    out="$(APPIMAGE_EXTRACT_AND_RUN=1 "${command[@]}" --cli -L 2>&1)"
    for driver in hantek-dso3062l atk-dl16; do
        printf '%s\n' "${out}" | grep -q "^[[:space:]]*${driver}[[:space:]]" || {
            echo "FAIL: required driver not listed: ${driver}" >&2
            return 1
        }
    done
    out="$(APPIMAGE_EXTRACT_AND_RUN=1 "${command[@]}" --cli -P uart --show 2>&1)"
    printf '%s\n' "${out}" | grep -q '^ID: uart$' || {
        echo "FAIL: UART decoder did not load" >&2
        return 1
    }
}

case "$(uname -m)" in
    aarch64|arm64)
        verify_cli "${AI}"
        echo "arm64 AppImage runtime: native CLI, drivers and decoder passed"
        ;;
    *)
        command -v docker >/dev/null 2>&1 || {
            echo "SKIP: not native arm64 and Docker is unavailable"; exit 77; }
        IMAGE="${ARM64_RUNTIME_IMAGE:-debian:bookworm}"
        docker image inspect "${IMAGE}" >/dev/null 2>&1 || {
            echo "SKIP: local runtime image ${IMAGE} is unavailable"; exit 77; }
        BINFMT="${BINFMT_DIR:-/proc/sys/fs/binfmt_misc}/qemu-aarch64"
        [ -f "${BINFMT}" ] && grep -q '^enabled' "${BINFMT}" 2>/dev/null || {
            echo "SKIP: qemu-aarch64 binfmt is not enabled"; exit 77; }
        docker run --rm --pull never --platform linux/arm64 \
            --entrypoint /usr/bin/true "${IMAGE}" >/dev/null 2>&1 || {
            echo "SKIP: Docker cannot execute ${IMAGE} as linux/arm64"; exit 77; }

        TMP="$(mktemp -d)"
        trap 'rm -rf "${TMP}"' EXIT
        cp "${AI}" "${TMP}/PulseView-aarch64.AppImage"
        # qemu binfmt interprets the type-2 AI magic as part of its own match;
        # zero only the temporary copy, never the delivery artifact.
        printf '\0\0\0' | dd of="${TMP}/PulseView-aarch64.AppImage" \
            bs=1 seek=8 count=3 conv=notrunc status=none
        chmod +x "${TMP}/PulseView-aarch64.AppImage"
        cat >"${TMP}/verify.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
AI=/candidate/PulseView-aarch64.AppImage
export APPIMAGE_EXTRACT_AND_RUN=1
"${AI}" --cli --version | grep -q '^sigrok-cli '
LIST="$("${AI}" --cli -L)"
printf '%s\n' "${LIST}" | grep -q '^[[:space:]]*hantek-dso3062l[[:space:]]'
printf '%s\n' "${LIST}" | grep -q '^[[:space:]]*atk-dl16[[:space:]]'
"${AI}" --cli -P uart --show | grep -q '^ID: uart$'
INNER
        chmod +x "${TMP}/verify.sh"
        docker run --rm --pull never --platform linux/arm64 \
            --volume "${TMP}:/candidate:ro" \
            "${IMAGE}" bash /candidate/verify.sh
        echo "arm64 AppImage runtime: emulated bare-container checks passed"
        ;;
esac

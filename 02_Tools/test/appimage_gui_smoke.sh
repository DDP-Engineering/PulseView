#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Start the amd64 AppImage under Xvfb and require a visible PulseView window.

set -euo pipefail

APPIMAGE="${APPIMAGE_PATH:-}"
[ -n "${APPIMAGE}" ] && [ -x "${APPIMAGE}" ] \
    || { echo 'SKIP: executable APPIMAGE_PATH unavailable'; exit 77; }
if [ -n "${BUILDER_TAG:-}" ]; then
    ENGINE="${BUILDER_ENGINE:-docker}"
    command -v "${ENGINE}" >/dev/null 2>&1 \
        || { echo "SKIP: ${ENGINE} unavailable"; exit 77; }
    "${ENGINE}" run --rm --network none --platform linux/amd64 \
        --volume "${APPIMAGE}:/candidate/PulseView.AppImage:ro" \
        --volume "${BASH_SOURCE[0]}:/tmp/appimage_gui_smoke.sh:ro" \
        --env APPIMAGE_PATH=/candidate/PulseView.AppImage \
        "${BUILDER_TAG}" bash /tmp/appimage_gui_smoke.sh
    exit $?
fi
for command in Xvfb xdotool; do
    command -v "${command}" >/dev/null 2>&1 \
        || { echo "SKIP: ${command} unavailable"; exit 77; }
done
TMP="$(mktemp -d)"
DISPLAY_NUMBER=97
cleanup() {
    [ -z "${APP_PID:-}" ] || kill "${APP_PID}" >/dev/null 2>&1 || true
    [ -z "${XVFB_PID:-}" ] || kill "${XVFB_PID}" >/dev/null 2>&1 || true
    rm -rf "${TMP}"
}
trap cleanup EXIT
Xvfb ":${DISPLAY_NUMBER}" -screen 0 1280x800x24 >"${TMP}/xvfb.log" 2>&1 &
XVFB_PID=$!
export DISPLAY=":${DISPLAY_NUMBER}" APPIMAGE_EXTRACT_AND_RUN=1
sleep 1
"${APPIMAGE}" >"${TMP}/app.log" 2>&1 &
APP_PID=$!
for _ in $(seq 1 30); do
    if xdotool search --onlyvisible --name 'PulseView' >/dev/null 2>&1; then
        printf 'AppImage GUI startup passed\n'
        exit 0
    fi
    kill -0 "${APP_PID}" >/dev/null 2>&1 \
        || { cat "${TMP}/app.log" >&2; echo 'FAIL: PulseView exited before opening a window' >&2; exit 1; }
    sleep 1
done
cat "${TMP}/app.log" >&2
echo 'FAIL: no visible PulseView window within 30 seconds' >&2
exit 1

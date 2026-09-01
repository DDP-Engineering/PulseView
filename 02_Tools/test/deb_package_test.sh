#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${HERE}/../.." && pwd)"
BUILDER="${REPO}/02_Tools/build/build_deb.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "missing file: $1"; }
assert_exec() { [ -x "$1" ] || fail "not executable: $1"; }
assert_contains() {
    grep -F -- "$2" "$1" >/dev/null || fail "$1 does not contain: $2"
}

[ -f "${BUILDER}" ] || fail "Debian package builder does not exist"

TMP="$(mktemp -d)"
trap 'rm -rf -- "${TMP}"' EXIT
APPDIR="${TMP}/AppDir"
STAGE="${TMP}/package-root"

mkdir -p "${APPDIR}/usr/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "${APPDIR}/AppRun"
printf '#!/usr/bin/env bash\nexit 0\n' > "${APPDIR}/usr/bin/pulseview"
printf '#!/usr/bin/env bash\nexit 0\n' > "${APPDIR}/usr/bin/sigrok-cli"
printf 'fixture-icon\n' > "${APPDIR}/pulseview.png"
chmod +x "${APPDIR}/AppRun" "${APPDIR}/usr/bin/pulseview" \
    "${APPDIR}/usr/bin/sigrok-cli"

bash "${BUILDER}" \
    --appdir "${APPDIR}" \
    --stage-only "${STAGE}" \
    --version 0.5.0 \
    --rev abc123-dirty

CONTROL="${STAGE}/DEBIAN/control"
DESKTOP="${STAGE}/usr/share/applications/pulseview-ddp.desktop"

assert_file "${CONTROL}"
assert_contains "${CONTROL}" 'Package: pulseview-ddp'
assert_contains "${CONTROL}" 'Version: 0.5.0+gitabc123.dirty'
assert_contains "${CONTROL}" 'Architecture: arm64'
assert_contains "${CONTROL}" 'Depends: libc6 (>= 2.35), libstdc++6, libgl1, libegl1'
assert_contains "${CONTROL}" 'Conflicts: pulseview, sigrok-cli'

assert_exec "${STAGE}/usr/bin/pulseview"
assert_exec "${STAGE}/usr/bin/sigrok-cli"
assert_contains "${STAGE}/usr/bin/pulseview" '/opt/pulseview-ddp/AppRun'
assert_contains "${STAGE}/usr/bin/sigrok-cli" '/opt/pulseview-ddp/AppRun --cli'
assert_exec "${STAGE}/opt/pulseview-ddp/AppRun"

assert_file "${DESKTOP}"
assert_contains "${DESKTOP}" 'Name=PulseView'
assert_contains "${DESKTOP}" 'Exec=pulseview'
assert_contains "${DESKTOP}" 'Icon=pulseview-ddp'
assert_contains "${DESKTOP}" 'Categories=Development;Electronics;'

assert_file "${STAGE}/usr/share/icons/hicolor/48x48/apps/pulseview-ddp.png"
assert_file "${STAGE}/lib/udev/rules.d/60-sigrok-instruments.rules"
assert_file "${STAGE}/usr/share/doc/pulseview-ddp/copyright"
assert_exec "${STAGE}/DEBIAN/postinst"
assert_exec "${STAGE}/DEBIAN/postrm"
assert_contains "${STAGE}/DEBIAN/postinst" 'udevadm control --reload-rules'
assert_contains "${STAGE}/DEBIAN/postrm" 'udevadm control --reload-rules'

printf 'PASS: Debian package stage has the required arm64 metadata and installed UX\n'

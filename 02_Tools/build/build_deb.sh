#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Turn the verified Raspberry Pi AppImage payload into a native arm64 Debian
# package. The installed package uses the extracted AppDir, so it has no FUSE
# runtime dependency and no second dependency-closure implementation.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
APPIMAGE="${REPO}/07_Delivery/PulseView-aarch64.AppImage"
APPDIR=""
OUT="${REPO}/07_Delivery"
STAGE_ONLY=""
VERSION=""
REV=""

usage() {
    cat <<'EOF'
Build the Raspberry Pi arm64 Debian package.

Usage: build_deb.sh [options]

Options:
  --appimage FILE   Verified aarch64 AppImage to extract.
  --appdir DIR      Use an already-extracted AppDir (test/development seam).
  --out DIR         Artifact directory. Default: 07_Delivery.
  --stage-only DIR  Assemble the Debian package root there, but do not archive.
  --version VALUE   PulseView version. Default: read CMakeLists.txt.
  --rev VALUE       Source revision. Default: source_revision.sh.
  -h, --help        Show this text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --appimage)  APPIMAGE="${2:?--appimage needs a file}"; shift 2 ;;
        --appdir)    APPDIR="${2:?--appdir needs a directory}"; shift 2 ;;
        --out)       OUT="${2:?--out needs a directory}"; shift 2 ;;
        --stage-only) STAGE_ONLY="${2:?--stage-only needs a directory}"; shift 2 ;;
        --version)   VERSION="${2:?--version needs a value}"; shift 2 ;;
        --rev)       REV="${2:?--rev needs a value}"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
done

SUPPLIED_APPDIR="${APPDIR}"

# Real AppImage extraction and dpkg assembly must run as arm64. Fixture staging
# is deliberately host-neutral so the package contract is testable in Git Bash.
if [ -z "${APPDIR}" ] && { [ "$(uname -m)" != aarch64 ] || [ ! -x /usr/local/bin/appimagetool ]; }; then
    [ -f "${APPIMAGE}" ] || die "aarch64 AppImage not found: ${APPIMAGE}"
    APPIMAGE="$(realpath "${APPIMAGE}")"
    OUT="$(realpath -m "${OUT}")"
    to_container_path() {
        case "$1" in
            "${REPO}/07_Delivery") printf '/out\n' ;;
            "${REPO}/07_Delivery/"*) printf '/out/%s\n' "${1#"${REPO}/07_Delivery/"}" ;;
            "${REPO}") printf '/work\n' ;;
            "${REPO}/"*) printf '/work/%s\n' "${1#"${REPO}/"}" ;;
            *) return 1 ;;
        esac
    }
    CONTAINER_APPIMAGE="$(to_container_path "${APPIMAGE}")" \
        || die "--appimage must be inside the repository so the builder can mount it"
    CONTAINER_OUT="$(to_container_path "${OUT}")" \
        || die "--out must be inside the repository so the builder can mount it"
    INNER_ARGS=(--appimage "${CONTAINER_APPIMAGE}" --out "${CONTAINER_OUT}")
    [ -z "${VERSION}" ] || INNER_ARGS+=(--version "${VERSION}")
    [ -z "${REV}" ] || INNER_ARGS+=(--rev "${REV}")
    exec "${SCRIPT_DIR}/run_in_builder.sh" --image appimage --keep-volume \
        --platform aarch64 -- bash /work/02_Tools/build/build_deb.sh \
        "${INNER_ARGS[@]}"
fi

[ -n "${VERSION}" ] || VERSION="$(sed -n 's/^[[:space:]]*set(PV_VERSION_STRING "\([^"]*\)").*/\1/p' \
    "${REPO}/05_Software/pulseview/CMakeLists.txt" | head -n 1)"
[ -n "${VERSION}" ] || die "could not determine PulseView version"
if [ -z "${REV}" ]; then
    if [ -z "${SUPPLIED_APPDIR}" ]; then
        APPIMAGE_README="$(dirname "${APPIMAGE}")/README-AppImage-aarch64.txt"
        [ -f "${APPIMAGE_README}" ] \
            || die "missing AppImage provenance file: ${APPIMAGE_README}"
        REV="$(sed -n \
            -e 's/^Source revision: //p' \
            -e 's/^Linux aarch64 AppImage - built //p' \
            "${APPIMAGE_README}" | head -n 1)"
        [ -n "${REV}" ] || die "could not read source revision from ${APPIMAGE_README}"
    else
        REV="$(bash "${SCRIPT_DIR}/source_revision.sh" "${REPO}")"
    fi
fi

# Debian versions allow letters, digits, plus, dot and tilde. A dirty Git
# suffix becomes dotted local-version metadata, e.g. 0.5.0+gitabc123.dirty.
SAFE_REV="$(printf '%s' "${REV}" | tr '[:upper:]_-' '[:lower:]..' \
    | sed 's/[^a-z0-9.+~]/./g; s/\.\{2,\}/./g; s/^\.//; s/\.$//')"
[ -n "${SAFE_REV}" ] || die "revision normalizes to an empty Debian version"
DEB_VERSION="${VERSION}+git${SAFE_REV}"

WORK_ROOT=""
PACKAGE_ROOT=""
cleanup() {
    [ -z "${WORK_ROOT}" ] || rm -rf -- "${WORK_ROOT}"
    [ -z "${PACKAGE_ROOT}" ] || rm -rf -- "${PACKAGE_ROOT}"
}
trap cleanup EXIT

if [ -z "${APPDIR}" ]; then
    [ -f "${APPIMAGE}" ] || die "aarch64 AppImage not found: ${APPIMAGE}"
    [ -f "${APPIMAGE}.sha256" ] \
        || die "missing AppImage checksum: ${APPIMAGE}.sha256"
    (cd "$(dirname "${APPIMAGE}")" && \
        sha256sum --check "$(basename "${APPIMAGE}").sha256" >/dev/null) \
        || die "aarch64 AppImage checksum verification failed"
    WORK_BASE="${BUILD_DIR:-${REPO}/.work}"
    mkdir -p "${WORK_BASE}"
    WORK_ROOT="$(mktemp -d "${WORK_BASE}/deb-extract.XXXXXX")"
    RUNNER="${WORK_ROOT}/PulseView-aarch64.extract"
    cp "${APPIMAGE}" "${RUNNER}"
    # AppImage's AI\x02 marker at offset 8 prevents qemu binfmt from treating
    # the file as ELF. Zero only the marker in the temporary copy.
    printf '\0\0\0' | dd of="${RUNNER}" bs=1 seek=8 conv=notrunc status=none
    chmod +x "${RUNNER}"
    note "extracting $(basename "${APPIMAGE}")"
    (cd "${WORK_ROOT}" && "${RUNNER}" --appimage-extract >/dev/null)
    APPDIR="${WORK_ROOT}/squashfs-root"
fi

[ -x "${APPDIR}/AppRun" ] || die "AppDir has no executable AppRun: ${APPDIR}"
[ -x "${APPDIR}/usr/bin/pulseview" ] || die "AppDir has no PulseView binary"
[ -x "${APPDIR}/usr/bin/sigrok-cli" ] || die "AppDir has no sigrok-cli binary"

if [ -n "${STAGE_ONLY}" ]; then
    ROOT="${STAGE_ONLY}"
    [ ! -e "${ROOT}" ] \
        || die "--stage-only destination already exists; choose an empty new path"
else
    WORK_BASE="${BUILD_DIR:-${REPO}/.work}"
    mkdir -p "${WORK_BASE}"
    ROOT="$(mktemp -d "${WORK_BASE}/deb-root.XXXXXX")"
    PACKAGE_ROOT="${ROOT}"
fi

note "assembling pulseview-ddp ${DEB_VERSION}"
mkdir -p \
    "${ROOT}/DEBIAN" \
    "${ROOT}/opt/pulseview-ddp" \
    "${ROOT}/usr/bin" \
    "${ROOT}/usr/share/applications" \
    "${ROOT}/usr/share/icons/hicolor/48x48/apps" \
    "${ROOT}/usr/share/doc/pulseview-ddp" \
    "${ROOT}/lib/udev/rules.d"
cp -a "${APPDIR}/." "${ROOT}/opt/pulseview-ddp/"

cat > "${ROOT}/usr/bin/pulseview" <<'EOF'
#!/usr/bin/env bash
exec /opt/pulseview-ddp/AppRun "$@"
EOF
cat > "${ROOT}/usr/bin/sigrok-cli" <<'EOF'
#!/usr/bin/env bash
exec /opt/pulseview-ddp/AppRun --cli "$@"
EOF
chmod 0755 "${ROOT}/usr/bin/pulseview" "${ROOT}/usr/bin/sigrok-cli"

cat > "${ROOT}/usr/share/applications/pulseview-ddp.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=PulseView
Comment=View and analyze signals from sigrok-compatible instruments
Exec=pulseview
Icon=pulseview-ddp
Terminal=false
Categories=Development;Electronics;
EOF

ICON="${APPDIR}/pulseview.png"
[ -f "${ICON}" ] || ICON="${APPDIR}/usr/share/icons/hicolor/48x48/apps/pulseview.png"
[ -f "${ICON}" ] || die "AppDir has no PulseView icon"
cp "${ICON}" "${ROOT}/usr/share/icons/hicolor/48x48/apps/pulseview-ddp.png"

RULES="${REPO}/07_Delivery/60-sigrok-instruments.rules"
[ -f "${RULES}" ] || die "shared instrument udev rules not found: ${RULES}"
cp "${RULES}" "${ROOT}/lib/udev/rules.d/60-sigrok-instruments.rules"
cp "${REPO}/LICENSE.txt" "${ROOT}/usr/share/doc/pulseview-ddp/copyright"
chmod 0644 \
    "${ROOT}/usr/share/applications/pulseview-ddp.desktop" \
    "${ROOT}/usr/share/icons/hicolor/48x48/apps/pulseview-ddp.png" \
    "${ROOT}/lib/udev/rules.d/60-sigrok-instruments.rules" \
    "${ROOT}/usr/share/doc/pulseview-ddp/copyright"

cat > "${ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
fi
exit 0
EOF
cat > "${ROOT}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
fi
exit 0
EOF
chmod 0755 "${ROOT}/DEBIAN/postinst" "${ROOT}/DEBIAN/postrm"
chmod 0755 "${ROOT}/DEBIAN"

INSTALLED_SIZE="$(du -sk "${ROOT}/opt" "${ROOT}/usr" "${ROOT}/lib" \
    | awk '{n += $1} END {print n + 0}')"
cat > "${ROOT}/DEBIAN/control" <<EOF
Package: pulseview-ddp
Version: ${DEB_VERSION}
Section: electronics
Priority: optional
Architecture: arm64
Installed-Size: ${INSTALLED_SIZE}
Maintainer: DDP Engineering
Depends: libc6 (>= 2.35), libstdc++6, libgl1, libegl1
Conflicts: pulseview, sigrok-cli
Replaces: pulseview, sigrok-cli
Provides: pulseview, sigrok-cli
Description: PulseView and sigrok-cli with DDP instrument drivers
 Self-contained Raspberry Pi 4/5 build with the Hantek DSO-3062L and
 ALIENTEK ATK-DL16 drivers, bundled protocol decoders, and USB rules.
EOF

if [ -n "${STAGE_ONLY}" ]; then
    note "stage-only package root ready: ${ROOT}"
    exit 0
fi

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb is required in the builder"
mkdir -p "${OUT}"
DEB="${OUT}/pulseview-ddp_${DEB_VERSION}_arm64.deb"
rm -f -- "${DEB}" "${DEB}.sha256"
dpkg-deb --build --root-owner-group "${ROOT}" "${DEB}" >/dev/null
dpkg-deb --info "${DEB}" >/dev/null
dpkg-deb --contents "${DEB}" >/dev/null
(cd "${OUT}" && sha256sum "$(basename "${DEB}")" > "$(basename "${DEB}").sha256")

cat > "${OUT}/README-RaspberryPi-deb.txt" <<EOF
Copyright (c) 2026 DDP Engineering
Licensed under the GNU General Public License v3.0 or later (LICENSE.txt).

PulseView for Raspberry Pi 4/5 - Debian installer
=================================================

Package: $(basename "${DEB}")
Source revision: ${REV}
Architecture: arm64 (64-bit Raspberry Pi OS only)

Install:
  sudo apt install ./$(basename "${DEB}")

Start:
  PulseView from the desktop application menu, or: pulseview
  Command line: sigrok-cli --version

The package installs both project USB drivers, protocol decoders, and udev
rules. It conflicts with Raspberry Pi OS's pulseview and sigrok-cli packages
because it owns the standard command names. The AppImage remains available
when an install-free package is preferred.

Remove:
  sudo apt remove pulseview-ddp
EOF

note "done"
ls -la "${DEB}" "${DEB}.sha256" "${OUT}/README-RaspberryPi-deb.txt"

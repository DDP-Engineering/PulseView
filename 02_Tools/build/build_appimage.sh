#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Linux x86_64 AppImage: a delivery that runs on another machine with ZERO
# extra downloads, installs, or `apt` commands - not even the runtime
# libraries build_linux.sh's plain tarball still requires the target machine
# to already have.
#
# Why this exists and build_linux.sh's tarball is not enough: that tarball
# only bundles the sigrok-specific libraries built from source, and documents
# the rest (Qt5, glib, boost, libftdi, libusb, hidapi, libzip, python3...) as
# an `apt install` the target machine must run first. That is a legitimate,
# common strategy, but it is not "zero dependency" - and Qt makes "just
# bundle everything ldd finds" insufficient on its own too: Qt loads its
# platform backend (the X11/xcb integration a GUI needs to appear at all) as
# a PLUGIN at runtime, which the ELF dynamic linker - and therefore plain
# ldd - never sees. linuxdeployqt is what actually walks that plugin tree;
# appimagetool only packs whatever AppDir it is given into a self-extracting
# archive, with no dependency resolution of its own.
#
# Two binaries, one AppImage. AppImage wants exactly one entry point, and
# building two nearly-identical AppDirs (one per binary) would duplicate the
# whole ~150 MB Qt/boost/glib closure a second time for no reason - sigrok-cli
# does not need its own copy of libQt5Widgets. AppRun here dispatches: pass
# `--cli` as the first argument to run sigrok-cli instead of PulseView.
#
# Run it from the host; it re-executes itself inside the builder image:
#
#   bash 02_Tools/build/build_appimage.sh
#       host-architecture AppImage
#   bash 02_Tools/build/build_appimage.sh --arch aarch64
#       Raspberry Pi 4/5 AppImage in the arm64 builder image (on an x86_64
#       host this needs qemu binfmt; check_host.sh reports whether it is set up)
#
# Architecture-dependent names come from arch_map.sh; the builder image for
# a non-host architecture must first be prepared with
# ensure_build_environment.sh --image appimage --platform <arch>.
#
# Output: 07_Delivery/<AppImage name from arch_map.sh>

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------
# Re-execute inside the container unless we are already in it
# --------------------------------------------------------------------------
if [ ! -x /usr/local/bin/appimagetool ]; then
    ARCH_OVERRIDE="$(uname -m)"
    PASS_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --arch) ARCH_OVERRIDE="${2:?--arch needs a value}"; shift 2 ;;
            *)      PASS_ARGS+=("$1"); shift ;;
        esac
    done
    export ARCH_OVERRIDE
    # shellcheck source=arch_map.sh
    . "${SCRIPT_DIR}/arch_map.sh"
    exec bash "${SCRIPT_DIR}/run_in_builder.sh" --image appimage --keep-volume \
        --platform "${SR_DOCKER_PLATFORM}" --offline \
        -- bash /work/02_Tools/build/build_appimage.sh \
        ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
fi

# --------------------------------------------------------------------------
# Inside the container from here down
# --------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
# Inside the container the machine architecture IS the target architecture
# (the host side selected the builder platform), so no override is needed.
# shellcheck source=arch_map.sh
. /work/02_Tools/build/arch_map.sh
REPO=/work
SRC="${REPO}/05_Software"
BUILD="${BUILD_DIR:-/build}/appimage"
PREFIX="${BUILD}/prefix"
APPDIR="${BUILD}/AppDir"
OUT="${DELIVERY_DIR:-/out}"
JOBS="$(nproc)"

note() { printf '\n==> %s\n' "$*"; }

REV="$(bash /work/02_Tools/build/source_revision.sh "${REPO}")"

mkdir -p "${BUILD}" "${PREFIX}"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/${SR_LIBDIR}/pkgconfig"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/${SR_LIBDIR}"

# Sync into the build tree rather than build in place - same reasoning as
# build_windows_mxe.sh: autotools writes configure/Makefiles/config.h into
# the source directory, which is now plain tracked files in this repo, not a
# submodule that can go quietly dirty.
sync_source() {
    local name="$1"
    mkdir -p "${BUILD}/src"
    if [ -d "${BUILD}/src/${name}" ]; then
        cp -au "${SRC}/${name}/." "${BUILD}/src/${name}/"
    else
        cp -a "${SRC}/${name}" "${BUILD}/src/${name}"
    fi
}

build_autotools() {
    local name="$1"; shift
    note "building ${name}"
    sync_source "${name}"
    cd "${BUILD}/src/${name}"
    [ -x ./autogen.sh ] && ./autogen.sh >/dev/null
    ./configure --prefix="${PREFIX}" "$@" >/dev/null
    make -j"${JOBS}" >/dev/null
    make install >/dev/null
}

build_autotools libserialport
build_autotools libsigrok
build_autotools libsigrokdecode
build_autotools sigrok-cli

note "building pulseview"
sync_source pulseview
cd "${BUILD}/src/pulseview"
cmake -B build -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DDISABLE_WERROR=y \
    -DENABLE_TESTS=n >/dev/null
cmake --build build -j"${JOBS}" >/dev/null
cmake --install build >/dev/null

# --------------------------------------------------------------------------
# Assemble the AppDir
# --------------------------------------------------------------------------
note "assembling AppDir"
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" \
    "${APPDIR}/usr/share/applications" \
    "${APPDIR}/usr/share/icons/hicolor/48x48/apps" \
    "${APPDIR}/usr/share/libsigrokdecode"

cp "${PREFIX}/bin/pulseview" "${PREFIX}/bin/sigrok-cli" "${APPDIR}/usr/bin/"
cp -a "${PREFIX}/share/libsigrokdecode/." "${APPDIR}/usr/share/libsigrokdecode/"

# Pre-place the sigrok libraries and hand each to linuxdeployqt as an
# -executable below. Without this, libsigrok.so.4 gets copied in as a
# dependency but its OWN dependencies are never followed, and libusb-1.0
# silently goes missing - the binary then dies at startup on any machine
# that does not happen to have libusb installed, which is the whole thing
# this AppImage exists to avoid.
cp -a "${PREFIX}"/lib/lib*.so* "${APPDIR}/usr/lib/" 2>/dev/null || true
cp -a "${PREFIX}/lib/${SR_LIBDIR}"/lib*.so* "${APPDIR}/usr/lib/" 2>/dev/null || true

cp "${SRC}/pulseview/contrib/org.sigrok.PulseView.desktop" \
    "${APPDIR}/usr/share/applications/pulseview.desktop"
cp "${SRC}/pulseview/icons/pulseview.png" \
    "${APPDIR}/usr/share/icons/hicolor/48x48/apps/pulseview.png"
# appimagetool also wants a copy at the AppDir root, alongside a .desktop
# there and a top-level .DirIcon - linuxdeployqt creates the rest, but wants
# the source .desktop next to the binary tree first.
cp "${APPDIR}/usr/share/applications/pulseview.desktop" "${APPDIR}/pulseview.desktop"
cp "${APPDIR}/usr/share/icons/hicolor/48x48/apps/pulseview.png" "${APPDIR}/pulseview.png"

# --------------------------------------------------------------------------
# linuxdeployqt: walk both binaries' dependency closures, Qt plugins
# included, and rewrite their rpaths to find the bundled copies. The same
# tool on both architectures - release 11 ships an aarch64 asset too, and
# the builder image installs the one matching its own platform.
# --------------------------------------------------------------------------
note "running linuxdeployqt"
export VERSION="${REV}"
cd "${APPDIR}"
QMAKE_BIN="$(command -v qmake)"
[ -n "${QMAKE_BIN}" ] || { echo "qmake not found on PATH" >&2; exit 1; }
LDQT_ARGS=(
    "${APPDIR}/pulseview.desktop"
    -qmake="${QMAKE_BIN}"
    -executable="${APPDIR}/usr/bin/sigrok-cli"
    -bundle-non-qt-libs
    -no-translations
    -verbose=2
)
# Every bundled sigrok library, so their dependency closures are followed too.
for so in "${APPDIR}"/usr/lib/lib*.so*; do
    [ -f "${so}" ] || continue
    LDQT_ARGS+=(-executable="${so}")
done
/usr/local/bin/linuxdeployqt "${LDQT_ARGS[@]}"

# Fail loudly rather than package an AppImage with nothing actually bundled -
# that is exactly the failure mode that motivated writing this script.
LIB_COUNT="$(find "${APPDIR}/usr/lib" -maxdepth 1 -name '*.so*' 2>/dev/null | wc -l)"
note "bundled ${LIB_COUNT} shared libraries"
[ "${LIB_COUNT}" -ge 20 ] \
    || { echo "only ${LIB_COUNT} libraries bundled - linuxdeployqt did not do its job, refusing to package" >&2; exit 1; }
find "${APPDIR}" -iname 'libqxcb*' -o -iname 'libQt5Core*' | grep -q . \
    || { echo "Qt platform plugin / Qt5Core not found in the bundle" >&2; exit 1; }

# --------------------------------------------------------------------------
# Custom AppRun: dispatch to sigrok-cli when invoked with --cli, PulseView
# otherwise. linuxdeployqt writes its own AppRun; replace it, since a bare
# `exec pulseview "$@"` cannot reach sigrok-cli at all.
#
# rm FIRST. linuxdeployqt leaves AppRun as a SYMLINK to usr/bin/pulseview,
# so `cat > AppRun` follows it and overwrites the actual PulseView binary
# with this shell script - which then recurses into itself via a doubled
# usr/bin/usr/bin path. Silent, and fatal.
# --------------------------------------------------------------------------
note "writing AppRun"
rm -f "${APPDIR}/AppRun"
cat > "${APPDIR}/AppRun" <<'RUN'
#!/usr/bin/env bash
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="${HERE}/usr/plugins:${QT_PLUGIN_PATH:-}"
export SIGROKDECODE_DIR="${HERE}/usr/share/libsigrokdecode/decoders"
# The bundled stdlib for the bundled libpython - decoders die without it.
export PYTHONHOME="${HERE}/usr"
export PYTHONNOUSERSITE=1
if [ "${1:-}" = "--cli" ]; then
    shift
    exec "${HERE}/usr/bin/sigrok-cli" "$@"
fi
exec "${HERE}/usr/bin/pulseview" "$@"
RUN
chmod +x "${APPDIR}/AppRun"

# --------------------------------------------------------------------------
# Package
# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# Bundle the Python standard library.
#
# linuxdeployqt bundles libpython3.x.so because libsigrokdecode links it -
# but the STDLIB is not an ELF dependency, so nothing bundles it, and
# embedded CPython then dies at srd_init ("Could not find platform
# independent libraries") on any host whose /usr does not happen to carry
# the exact same python3.x. That was every protocol decoder, silently dead
# in the shipped AppImage; found by the arm64 bare-container decoder gate.
# This runs BEFORE the closure pass so lib-dynload's C extensions get their
# own dependencies (libssl, libffi...) closed and patched like everything
# else. AppRun exports PYTHONHOME so libpython looks inside the bundle.
# --------------------------------------------------------------------------
note "bundling the python standard library"
PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
PYSTD="/usr/lib/python${PYVER}"
[ -d "${PYSTD}" ] || { echo "python stdlib not found at ${PYSTD}" >&2; exit 1; }
cp -a "${PYSTD}" "${APPDIR}/usr/lib/python${PYVER}"
# Drop what decoders can never need: tests, caches, build-config static
# library, GUI/toolchain extras, and site/dist packages (decoders are
# stdlib-only by libsigrokdecode's own requirement).
rm -rf "${APPDIR}/usr/lib/python${PYVER}/test" \
       "${APPDIR}/usr/lib/python${PYVER}/idlelib" \
       "${APPDIR}/usr/lib/python${PYVER}/tkinter" \
       "${APPDIR}/usr/lib/python${PYVER}/turtledemo" \
       "${APPDIR}/usr/lib/python${PYVER}/ensurepip" \
       "${APPDIR}/usr/lib/python${PYVER}/lib2to3" \
       "${APPDIR}/usr/lib/python${PYVER}/dist-packages" \
       "${APPDIR}/usr/lib/python${PYVER}"/config-*
find "${APPDIR}/usr/lib/python${PYVER}" -name __pycache__ -type d \
    -exec rm -rf {} + 2>/dev/null || true

# --------------------------------------------------------------------------
# Close the dependency graph ourselves.
#
# linuxdeployqt ships the AppImage community "excludelist" and libusb-1.0 is
# ON it - the list assumes libusb is a system library the host will provide.
# For an application whose entire purpose is talking to USB instruments that
# assumption is backwards, and it is the difference between "runs anywhere"
# and "dies at startup on a clean machine".
#
# So: walk the ELF closure and copy anything still missing, EXCEPT the
# libraries that genuinely must come from the host - glibc itself (bundling
# it breaks more than it fixes) and the GPU/graphics stack, which has to
# match the host's kernel driver.
# --------------------------------------------------------------------------
note "closing dependency graph"

host_only() {
    case "$1" in
        ld-linux*|libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|\
        libresolv.so.*|libanl.so.*|libnss_*|libthread_db*|libmvec.so.*|\
        libBrokenLocale.so.*|libcidn.so.*|libstdc++.so.*|libgcc_s.so.*|\
        libGL.so.*|libEGL.so.*|libGLX.so.*|libGLdispatch.so.*|libOpenGL.so.*|\
        libdrm.so.*|libglapi.so.*|libgbm.so.*) return 0 ;;
    esac
    return 1
}

for pass in 1 2 3 4 5; do
    ADDED=0
    while IFS= read -r elf; do
        while IFS= read -r dep; do
            [ -n "${dep}" ] || continue
            host_only "${dep}" && continue
            [ -e "${APPDIR}/usr/lib/${dep}" ] && continue
            SRC_LIB="$(LD_LIBRARY_PATH="${APPDIR}/usr/lib" ldd "${elf}" 2>/dev/null \
                | awk -v d="${dep}" '$1==d && $3 ~ /^\// {print $3; exit}')"
            if [ -n "${SRC_LIB}" ] && [ -e "${SRC_LIB}" ]; then
                cp -aL "${SRC_LIB}" "${APPDIR}/usr/lib/${dep}"
                patchelf --set-rpath '$ORIGIN' "${APPDIR}/usr/lib/${dep}" 2>/dev/null || true
                echo "    + ${dep}"
                ADDED=$((ADDED + 1))
            fi
        done < <(objdump -p "${elf}" 2>/dev/null | awk '/NEEDED/ {print $2}')
    done < <(find "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/plugins" \
                -type f \( -name '*.so*' -o -perm -u+x \) 2>/dev/null)
    [ "${ADDED}" -eq 0 ] && break
    note "pass ${pass}: added ${ADDED}"
done

# Verify the AppDir before packaging it. Every one of these checks exists
# because that exact failure shipped a broken AppImage during development:
# a clobbered binary and a missing libusb both packaged and "succeeded".
note "verifying AppDir"
[ -x "${APPDIR}/usr/bin/pulseview" ] \
    || { echo "usr/bin/pulseview missing" >&2; exit 1; }
file "${APPDIR}/usr/bin/pulseview" | grep -q 'ELF .*executable' \
    || { echo "usr/bin/pulseview is not an ELF binary - AppRun symlink clobbered it" >&2; exit 1; }
file "${APPDIR}/usr/bin/sigrok-cli" | grep -q 'ELF .*executable' \
    || { echo "usr/bin/sigrok-cli is not an ELF binary" >&2; exit 1; }
[ ! -L "${APPDIR}/AppRun" ] \
    || { echo "AppRun is still a symlink; it must be a real file" >&2; exit 1; }

# Check the ELF closure by FILE PRESENCE in the AppDir, not with ldd.
#
# ldd was the first thing tried here and it is useless for this: it happily
# resolves against the build container's own /usr/lib, so it reported a
# complete closure while the shipped AppImage was still missing libusb and
# died instantly on a clean machine. The only question that matters is
# "is this file inside the bundle", so ask exactly that.
note "verifying dependency closure"
CLOSURE_FAIL=0
while IFS= read -r elf; do
    while IFS= read -r dep; do
        [ -n "${dep}" ] || continue
        host_only "${dep}" && continue
        if [ ! -e "${APPDIR}/usr/lib/${dep}" ]; then
            echo "  MISSING ${dep}  (needed by ${elf#${APPDIR}/})" >&2
            CLOSURE_FAIL=1
        fi
    done < <(objdump -p "${elf}" 2>/dev/null | awk '/NEEDED/ {print $2}')
done < <(find "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" "${APPDIR}/usr/plugins" \
            -type f \( -name '*.so*' -o -perm -u+x \) 2>/dev/null)
[ "${CLOSURE_FAIL}" -eq 0 ] \
    || { echo "dependency closure incomplete - refusing to package" >&2; exit 1; }
note "dependency closure complete"

note "running appimagetool"
mkdir -p "${OUT}"
NAME="${SR_APPIMAGE_NAME}"
rm -f "${OUT}/${NAME}"
# --runtime-file: without it appimagetool downloads the type-2 runtime from
# GitHub at packaging time - a network fetch inside a build that must not
# have one. The builder image bakes the pinned, checksum-verified runtime
# for its own architecture at this path.
[ -f /usr/local/lib/appimage/runtime ] \
    || { echo "baked AppImage runtime missing - rebuild the builder image" >&2; exit 1; }
/usr/local/bin/appimagetool --runtime-file /usr/local/lib/appimage/runtime \
    "${APPDIR}" "${OUT}/${NAME}" >/dev/null
chmod +x "${OUT}/${NAME}"

# The x86_64 README keeps its historical name; other architectures get an
# arch-suffixed file so building two architectures back to back cannot leave
# one README describing the other's binary.
README_NAME="README-AppImage.txt"
[ "${SR_ARCH}" = "x86_64" ] || README_NAME="README-AppImage-${SR_ARCH}.txt"
bash /work/02_Tools/build/write_appimage_readme.sh \
    "${OUT}/${README_NAME}" "${SR_ARCH}" "${NAME}" "${REV}"
( cd "${OUT}" && sha256sum "${NAME}" > "${NAME}.sha256" )
# Both instruments. The DL16 rule was missing from the earlier Linux
# delivery, which would have left it root-only.
cat > "${OUT}/60-sigrok-instruments.rules" <<'UDEV'
# Hantek DSO-3062L - accessible to the plugdev group.
SUBSYSTEM=="usb", ATTRS{idVendor}=="04b5", ATTRS{idProduct}=="3062", MODE="0660", GROUP="plugdev", TAG+="uaccess"
# ALIENTEK ATK DL16 logic analyzer.
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="ffcc", MODE="0660", GROUP="plugdev", TAG+="uaccess"
UDEV

note "done"
ls -la "${OUT}/${NAME}"

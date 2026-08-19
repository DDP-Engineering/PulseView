#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Native Linux x86_64 build of the sigrok stack with the DSO-3062L driver.
#
# Unlike the Windows path (MXE cross-compile from a baked image), this builds
# natively against distribution libraries. It runs inside an ubuntu:24.04
# container so the host needs no dev packages and no sudo - Docker provides
# root in the container. The base matches a common WSL Ubuntu, so the result
# runs there after the runtime libraries are installed (listed in the emitted
# README).
#
# It re-execs itself into the container, like build_windows_mxe.sh.
#
#   ./build_linux.sh            build everything and stage a tarball
#
# Output: 07_Delivery/staging/pulseview-linux-x86_64/ and a .tar.gz beside it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

# --------------------------------------------------------------------------
# Re-exec into the container unless already inside it
# --------------------------------------------------------------------------
if [ ! -f /.dockerenv ]; then
    echo "==> launching ubuntu:24.04 build container"
    # Resolve the build revision on the host. libsigrok used to be its own
    # submodule checkout with its own HEAD; now it is plain files in this
    # repo, so the repo's own revision IS the driver revision.
    HOST_REV="$(git -C "${REPO}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    exec docker run --rm -i \
        -e "HDRIVER_REV=${HOST_REV}" \
        -v "${REPO}:/work" \
        -w /work \
        ubuntu:24.04 \
        bash /work/02_Tools/build/build_linux.sh "$@"
fi

# --------------------------------------------------------------------------
# Inside the container from here
# --------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
SRC=/work/05_Software
BUILD=/tmp/build
PREFIX=/tmp/prefix
STAGE_NAME=pulseview-linux-x86_64
STAGE=/work/07_Delivery/staging/${STAGE_NAME}
JOBS="$(nproc)"

note() { printf '\n==> %s\n' "$*"; }

note "installing build dependencies"
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential git ca-certificates pkg-config \
    autoconf automake libtool autoconf-archive \
    cmake \
    libglib2.0-dev libzip-dev libusb-1.0-0-dev libftdi1-dev \
    libhidapi-dev libserialport-dev \
    python3-dev python3-numpy python3-gi \
    libglibmm-2.4-dev \
    qtbase5-dev qtbase5-dev-tools libqt5svg5-dev \
    qttools5-dev qttools5-dev-tools \
    libboost-all-dev \
    doxygen swig >/dev/null

# Copy sources into the container so autogen/cmake never dirty the repo.
note "copying sources"
rm -rf "${BUILD}" "${PREFIX}"
mkdir -p "${BUILD}" "${PREFIX}"
for c in libserialport libsigrok libsigrokdecode sigrok-cli pulseview; do
    cp -a "${SRC}/${c}" "${BUILD}/${c}"
done

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/x86_64-linux-gnu/pkgconfig"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/x86_64-linux-gnu"

build_autotools() {
    local c="$1"; shift
    note "building ${c}"
    cd "${BUILD}/${c}"
    [ -x ./autogen.sh ] && ./autogen.sh >/dev/null
    ./configure --prefix="${PREFIX}" "$@" >/dev/null
    make -j"${JOBS}" >/dev/null
    make install >/dev/null
}

# The system libserialport is present, but build the pinned one for parity.
build_autotools libserialport
build_autotools libsigrok
build_autotools libsigrokdecode
build_autotools sigrok-cli

note "building pulseview"
cd "${BUILD}/pulseview"
cmake -B build -G "Unix Makefiles" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DDISABLE_WERROR=y \
    -DENABLE_TESTS=n >/dev/null
cmake --build build -j"${JOBS}" >/dev/null
cmake --install build >/dev/null

# --------------------------------------------------------------------------
# Stage a relocatable directory
# --------------------------------------------------------------------------
note "staging ${STAGE}"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/bin" "${STAGE}/lib" "${STAGE}/share"

cp "${PREFIX}/bin/pulseview" "${PREFIX}/bin/sigrok-cli" "${STAGE}/bin/"
# Bundle the sigrok shared libraries (not the system Qt/glib - those come
# from the distro, listed as runtime deps in the README).
cp -a "${PREFIX}"/lib/libsigrok*.so* "${STAGE}/lib/" 2>/dev/null || true
cp -a "${PREFIX}"/lib/libserialport*.so* "${STAGE}/lib/" 2>/dev/null || true
cp -a "${PREFIX}"/lib/x86_64-linux-gnu/libsigrok*.so* "${STAGE}/lib/" 2>/dev/null || true
cp -a "${PREFIX}"/lib/x86_64-linux-gnu/libserialport*.so* "${STAGE}/lib/" 2>/dev/null || true
cp -a "${PREFIX}/share/libsigrokdecode" "${STAGE}/share/"

# Launcher: set library and decoder paths relative to the extraction dir.
cat > "${STAGE}/pulseview" <<'LAUNCH'
#!/usr/bin/env bash
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${HERE}/lib:${LD_LIBRARY_PATH}"
export SIGROKDECODE_DIR="${HERE}/share/libsigrokdecode/decoders"
exec "${HERE}/bin/pulseview" "$@"
LAUNCH
cat > "${STAGE}/sigrok-cli" <<'LAUNCH'
#!/usr/bin/env bash
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${HERE}/lib:${LD_LIBRARY_PATH}"
export SIGROKDECODE_DIR="${HERE}/share/libsigrokdecode/decoders"
exec "${HERE}/bin/sigrok-cli" "$@"
LAUNCH
chmod +x "${STAGE}/pulseview" "${STAGE}/sigrok-cli"

# udev rule so the device is accessible without root.
cat > "${STAGE}/60-hantek-dso3062l.rules" <<'UDEV'
# Hantek DSO-3062L - accessible to the plugdev group.
SUBSYSTEM=="usb", ATTRS{idVendor}=="04b5", ATTRS{idProduct}=="3062", MODE="0660", GROUP="plugdev", TAG+="uaccess"
UDEV

cat > "${STAGE}/README-DSO3062L.txt" <<'RM'
PulseView / sigrok-cli for the Hantek DSO-3062L (Linux x86_64)
==============================================================

Built natively against Ubuntu 24.04 libraries. Runs on Ubuntu 24.04 (incl.
WSL) and compatible distributions once the runtime libraries below are
installed.

Runtime dependencies (once):
  sudo apt install libglib2.0-0 libzip4 libusb-1.0-0 libftdi1-2 \
    libglibmm-2.4-1t64 libqt5core5a libqt5gui5 libqt5widgets5 \
    libqt5svg5 python3 python3-numpy

Device access (once):
  sudo cp 60-hantek-dso3062l.rules /etc/udev/rules.d/
  sudo udevadm control --reload && sudo udevadm trigger
  (add yourself to the plugdev group if needed, then re-login)

Run:
  ./pulseview          # GUI
  ./sigrok-cli --driver hantek-dso3062l --scan

Capabilities and notes are identical to the Windows build; see the project
protocol reference. Use -O srzip (not CSV) for triggered captures.
RM

# --------------------------------------------------------------------------
# Tarball
# --------------------------------------------------------------------------
note "packaging tarball"
REV="${HDRIVER_REV:-unknown}"
TAR="/work/07_Delivery/pulseview-hantek-dso3062l-$(date +%Y%m%d)-${REV}-linux-x64.tar.gz"
( cd "${STAGE}/.." && tar czf "${TAR}" "${STAGE_NAME}" )
( cd "${STAGE}" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )

note "done"
ls -la "${TAR}"
echo "staged: ${STAGE}"
"${STAGE}/sigrok-cli" --version 2>&1 | head -2 || true
"${STAGE}/sigrok-cli" --driver hantek-dso3062l --show 2>&1 | head -3 || true

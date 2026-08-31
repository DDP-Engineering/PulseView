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
#   ./build_linux.sh                  build for the host architecture
#   ./build_linux.sh --arch aarch64   build for Raspberry Pi 4/5 (arm64
#                                     container; on an x86_64 host this
#                                     needs qemu binfmt - check_host.sh
#                                     reports whether it is set up)
#
# Every architecture-dependent name comes from arch_map.sh - one shared
# table, so this script has no per-arch fork. The aarch64 tarball targets
# arm64 Ubuntu 24.04; Raspberry Pi OS Bookworm users should prefer the
# aarch64 AppImage, whose older glibc floor covers Bookworm.
#
# Output: 07_Delivery/staging/<stage-name>/ and a .tar.gz beside it.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

# --------------------------------------------------------------------------
# Re-exec into the container unless already inside it
# --------------------------------------------------------------------------
if [ ! -f /.dockerenv ]; then
    ARCH_OVERRIDE="$(uname -m)"
    PASS_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --arch) ARCH_OVERRIDE="${2:?--arch needs a value}"; shift 2 ;;
            *)      PASS_ARGS+=("$1"); shift ;;
        esac
    done
    # shellcheck source=arch_map.sh
    . "${SCRIPT_DIR}/arch_map.sh"
    echo "==> launching ubuntu:24.04 build container (${SR_ARCH})"
    # Resolve the build revision on the host. libsigrok used to be its own
    # submodule checkout with its own HEAD; now it is plain files in this
    # repo, so the repo's own revision IS the driver revision.
    HOST_REV="$(bash "${SCRIPT_DIR}/source_revision.sh" "${REPO}")"
    exec docker run --rm -i \
        --platform "${SR_DOCKER_PLATFORM}" \
        -e "HDRIVER_REV=${HOST_REV}" \
        -v "${REPO}:/work" \
        -w /work \
        ubuntu:24.04 \
        bash /work/02_Tools/build/build_linux.sh \
        ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
fi

# --------------------------------------------------------------------------
# Inside the container from here
# --------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
# Inside the container the machine architecture IS the target architecture
# (the host side selected the container platform), so the mapping needs no
# override here.
# shellcheck source=arch_map.sh
. /work/02_Tools/build/arch_map.sh
SRC=/work/05_Software
BUILD=/tmp/build
PREFIX=/tmp/prefix
STAGE_NAME="${SR_STAGE_NAME}"
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

export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib/${SR_LIBDIR}/pkgconfig"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/lib/${SR_LIBDIR}"

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
cp -a "${PREFIX}/lib/${SR_LIBDIR}"/libsigrok*.so* "${STAGE}/lib/" 2>/dev/null || true
cp -a "${PREFIX}/lib/${SR_LIBDIR}"/libserialport*.so* "${STAGE}/lib/" 2>/dev/null || true
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

cat > "${STAGE}/README.txt" <<RM
PulseView / sigrok-cli for the Hantek DSO-3062L (Linux ${SR_ARCH})
==============================================================

Built natively against Ubuntu 24.04 (${SR_ARCH}) libraries. Runs on Ubuntu
24.04 (incl. WSL) and compatible distributions once the runtime libraries
below are installed. On a Raspberry Pi 4/5 running Raspberry Pi OS Bookworm,
prefer the aarch64 AppImage instead: this tarball's glibc is newer than
Bookworm's and will not load there.

Runtime dependencies (once):
  sudo apt install libglib2.0-0 libzip4 libusb-1.0-0 libftdi1-2 \
    libglibmm-2.4-1t64 libhidapi-hidraw0 libpython3.12 \
    libqt5core5a libqt5gui5 libqt5widgets5 \
    libqt5svg5 python3 python3-numpy

  Two of those are easy to leave out and produce the same symptom: sigrok-cli
  exits 127 with "error while loading shared libraries" and never starts.
  libhidapi-hidraw0 is linked by libsigrok. libpython3.12 is what actually
  ships libpython3.12.so.1.0 - the python3 package installs the interpreter
  but not the shared library libsigrokdecode links against.

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
note "verifying staged runtime"
bash /work/02_Tools/build/verify_linux_stage.sh "${STAGE}"

note "packaging tarball"
REV="${HDRIVER_REV:-unknown}"
TAR="/work/07_Delivery/pulseview-$(date +%Y%m%d)-${REV}-${SR_TARBALL_SUFFIX}.tar.gz"
( cd "${STAGE}/.." && tar czf "${TAR}" "${STAGE_NAME}" )
( cd "${STAGE}" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )
( cd "$(dirname "${TAR}")" && sha256sum "$(basename "${TAR}")" > "$(basename "${TAR}").sha256" )

note "done"
ls -la "${TAR}"
echo "staged: ${STAGE}"

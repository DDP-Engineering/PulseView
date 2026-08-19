#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Stage 2 for Windows: cross-compile sigrok with the MXE toolchain image.
#
# This is sigrok-util's `sigrok-cross-mingw` rewritten around what that script
# actually does, with the parts that no longer work replaced. The differences,
# all deliberate:
#
#   - Builds the vendored sources under 05_Software instead of cloning from
#     git://sigrok.org, which is a retired protocol (planning doc 09, R-20).
#   - Targets x86_64 rather than i686, and does not freeze Qt to 5.7. That
#     freeze exists for Windows XP, which this project does not claim.
#   - Verifies the downloaded Python 3.4.4 artifacts against known checksums.
#     Upstream fetches them over plaintext HTTP with --no-check-certificate.
#   - Skips `make manual`, which needs asciidoc and xsltproc and produces
#     documentation rather than a working application.
#   - Is incremental. Upstream deletes its build directory on every run; that
#     is fine when you build once per release and unusable when you are
#     iterating on a driver.
#
# Run it from the host; it re-executes itself inside the builder image:
#
#   ./build_windows_mxe.sh                       everything
#   ./build_windows_mxe.sh libsigrok pulseview   just those, in that order
#   ./build_windows_mxe.sh --clean               discard the build tree first
#   ./build_windows_mxe.sh --stage               assemble a runnable directory

set -euo pipefail

# --------------------------------------------------------------------------
# Re-execute inside the container unless we are already in it
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d /opt/mxe ]; then
    # --offline is for the container, not for us; spot it and hand it over.
    OUTER=()
    for a in "$@"; do
        [ "${a}" = "--offline" ] && OUTER+=(--offline)
    done
    exec "${SCRIPT_DIR}/run_in_builder.sh" --image mingw --keep-volume \
        "${OUTER[@]}" -- /work/02_Tools/build/build_windows_mxe.sh "$@"
fi

# --------------------------------------------------------------------------
# Inside the container from here down
# --------------------------------------------------------------------------
REPO=/work
SRC="${REPO}/05_Software"
UTIL="${SRC}/sigrok-util/cross-compile/mingw"
BUILD="${BUILD_DIR:-/build}/win"
PREFIX="${BUILD}/prefix"
STAGE="${DELIVERY_DIR:-/out}/staging/pulseview-windows-x86_64"
MXE=/opt/mxe
TRIPLET="${MXE_TARGET}"

BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)-windows"
LOG_DIR="${REPO}/.work/logs/${BUILD_ID}"

export PATH="${MXE}/usr/bin:${PATH}"
# MXE looks for a target-suffixed variable, not plain PKG_CONFIG_PATH. Our own
# prefix comes first so a component links what we just built, not a stale copy.
export PKG_CONFIG_PATH_x86_64_w64_mingw32_static_posix="${PREFIX}/lib/pkgconfig:${MXE}/usr/${TRIPLET}/lib/pkgconfig"

# CPPFLAGS is upstream's: mingw's printf is the gnu one, and without saying so
# every format-string warning in libsigrok is wrong.
CONF_COMMON="--host=${TRIPLET} --prefix=${PREFIX} CPPFLAGS=-D__printf__=__gnu_printf__"
CONF_STATIC="--disable-shared --enable-static"

# Python 3.4.4, repackaged by the sigrok project from the official Windows
# MSI. Cross-compiling CPython is genuinely hard and MXE has no Windows python
# package, so this is the only proven route - but it is end-of-life since March
# 2019 and arrives over plaintext HTTP, so the checksums are not optional.
#
# TODO move these to 02_Tools/upstream/upstreams.lock.toml as [[artifact]]
# entries and mirror the files. Until then this build is repeatable but not
# reproducible: it depends on a third-party host staying up and honest.
PY_BASE=http://www.sigrok.org/tmp
PY_SHA_Python34_x86_64_tar_gz=b50cb8e2f4297ef362d5dad0d516a10f58b74e95a10dc03760f4512e9ceffd86
PY_SHA_python34_x86_64_dll=a3b3ea1e583c3565cb422af954acc7efa3c3d8031afd1e55921962e6736650d4
PY_SHA_python34_x86_64_zip=56d95f69220c068e92617a92f80571314a1b16c02a6d5cb2a0b2613c5b15f3a3

ALL_COMPONENTS="libserialport libsigrok libsigrokdecode sigrok-cli pulseview"

CLEAN=0
DO_STAGE=0
COMPONENTS=""

usage() {
    cat <<EOF
Cross-compile sigrok for Windows x86_64.

Usage: build_windows_mxe.sh [options] [component ...]

Components, in dependency order:
  ${ALL_COMPONENTS}
Default is all of them.

Options:
  --clean     Delete the build tree first. Costs a full rebuild.
  --stage     Assemble a runnable directory under 07_Delivery/staging.
  -h, --help  This text.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --clean)   CLEAN=1; shift ;;
        --stage)   DO_STAGE=1; shift ;;
        # Consumed by the re-exec above; accepted here so the inner run, which
        # receives the same argument list, does not reject it.
        --offline) shift ;;
        -h|--help) usage; exit 0 ;;
        -*)        die "unknown option: $1 (try --help)" ;;
        *)         COMPONENTS="${COMPONENTS}${COMPONENTS:+ }$1"; shift ;;
    esac
done

if [ -z "${COMPONENTS}" ]; then
    COMPONENTS="${ALL_COMPONENTS}"
else
    for c in ${COMPONENTS}; do
        case " ${ALL_COMPONENTS} " in
            *" ${c} "*) ;;
            *) die "unknown component: ${c}" ;;
        esac
    done
fi

mkdir -p "${LOG_DIR}" "${PREFIX}"
[ "${CLEAN}" -eq 1 ] && { note "discarding build tree"; rm -rf "${BUILD:?}"; \
    mkdir -p "${PREFIX}"; }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

# Run a stage, sending output to its own log. Only the failure is verbose:
# a successful cross-build prints thousands of lines nobody reads.
run() {
    local name="$1" stage="$2"
    shift 2
    if "$@" > "${LOG_DIR}/${name}-${stage}.log" 2>&1; then
        printf '    %-10s ok\n' "${stage}"
        return 0
    fi
    printf '    %-10s FAILED\n' "${stage}"
    printf '\n--- %s ---\n' "${LOG_DIR}/${name}-${stage}.log" >&2
    grep -nE 'error:|Error [0-9]|CMake Error|No package|undefined reference' \
        "${LOG_DIR}/${name}-${stage}.log" | head -20 >&2 || true
    printf '\n' >&2
    tail -15 "${LOG_DIR}/${name}-${stage}.log" >&2
    return 1
}

# Sync source into the build tree without discarding object files.
#
# The tree is copied rather than built in place because autotools writes
# configure, Makefiles and config.h into the source directory, and these are
# vendored, plain-tracked files - building in place would dirty the working
# tree of the main repo itself. `cp -au` copies only files newer than their
# counterpart, so an edited driver rebuilds and nothing else does. rsync would
# be the obvious tool and is not in the image.
sync_source() {
    local name="$1"
    [ -d "${SRC}/${name}" ] || die "not checked out: ${SRC}/${name}"
    if [ -d "${BUILD}/${name}" ]; then
        cp -au "${SRC}/${name}/." "${BUILD}/${name}/"
    else
        mkdir -p "${BUILD}"
        cp -a "${SRC}/${name}" "${BUILD}/${name}"
    fi
    cd "${BUILD}/${name}"
}

# autogen.sh and configure are expensive and only need re-running when their
# inputs change - but "change" has to include the case that matters most here.
# Adding a driver edits configure.ac and Makefile.am, and a guard that only
# asked whether ./configure exists would skip both steps and produce a build
# with the new driver silently absent. cp -au preserves mtimes, so comparing
# against the generated files catches it.
autotools_build() {
    local name="$1"
    shift
    sync_source "${name}"

    if [ ! -f ./configure ] || [ configure.ac -nt ./configure ]; then
        run "${name}" autogen ./autogen.sh || return 1
    fi
    if [ ! -f ./config.status ] || [ ./configure -nt ./config.status ]; then
        # shellcheck disable=SC2086
        run "${name}" configure ./configure "$@" || return 1
    fi

    run "${name}" make make -j"$(nproc)" || return 1
    run "${name}" install make install || return 1
}

fetch_verified() {
    local file="$1" want="$2" dest="${BUILD}/dl/${1}"
    mkdir -p "${BUILD}/dl"
    # Prefer the copy baked into the image. That is the whole point of baking
    # it: the build then reaches no network at all, and does not depend on a
    # single third-party host still serving an end-of-life Python over
    # plaintext HTTP. The download below is the fallback for an older image.
    if [ ! -f "${dest}" ] && [ -f "/opt/sigrok-deps/${file}" ]; then
        cp "/opt/sigrok-deps/${file}" "${dest}"
    fi
    if [ ! -f "${dest}" ]; then
        note "  ${file} not in image; downloading"
        wget -q -O "${dest}.part" "${PY_BASE}/${file}" \
            || { rm -f "${dest}.part"; die "download failed: ${file}"; }
        mv "${dest}.part" "${dest}"
    fi
    local got
    got="$(sha256sum "${dest}" | cut -d' ' -f1)"
    [ "${got}" = "${want}" ] || die \
        "checksum mismatch for ${file}
  expected ${want}
  got      ${got}
  The upstream host serves this over plaintext HTTP. Do not proceed until
  this is explained; delete ${dest} to retry the download."
}

# --------------------------------------------------------------------------
# Components
# --------------------------------------------------------------------------

build_libserialport() {
    # shellcheck disable=SC2086
    autotools_build libserialport ${CONF_COMMON} ${CONF_STATIC}
}

build_libsigrok() {
    # shellcheck disable=SC2086
    autotools_build libsigrok ${CONF_COMMON} ${CONF_STATIC} || return 1
    # configure reports a missing C++ binding as one line in a summary block
    # and then exits successfully. PulseView cannot be built without it, so
    # catch it here rather than 20 minutes later with an unrelated error.
    if [ ! -f "${PREFIX}/lib/libsigrokcxx.a" ]; then
        printf '\n' >&2
        sed -n '/onfiguration summary/,$p' \
            "${LOG_DIR}/libsigrok-configure.log" >&2 2>/dev/null || true
        die "libsigrok built without its C++ bindings, so PulseView cannot link.
  The usual cause is a missing host doxygen: libsigrok generates the
  bindings from Doxygen's XML dump of its own headers."
    fi
}

# libsigrokdecode embeds CPython, so the Windows target needs a Python to link
# against. MXE has none. These are upstream's steps, with checksums added.
build_libsigrokdecode() {
    note "  preparing Windows Python 3.4.4"
    fetch_verified Python34_x86_64.tar.gz "${PY_SHA_Python34_x86_64_tar_gz}"
    fetch_verified python34_x86_64.dll    "${PY_SHA_python34_x86_64_dll}"
    fetch_verified python34_x86_64.zip    "${PY_SHA_python34_x86_64_zip}"

    if [ ! -f "${PREFIX}/Python34/libs/libpython34.a" ]; then
        rm -rf "${PREFIX}/Python34"
        tar xzf "${BUILD}/dl/Python34_x86_64.tar.gz" -C "${PREFIX}"
        cp -f "${BUILD}/dl/python34_x86_64.dll" "${PREFIX}/python34.dll"
        cp -f "${BUILD}/dl/python34_x86_64.zip" "${PREFIX}/python34.zip"

        # Upstream bug #1195: the 64-bit pyconfig.h does not compile as shipped.
        patch -p1 "${PREFIX}/Python34/include/pyconfig.h" \
            < "${UTIL}/pyconfig.patch" > "${LOG_DIR}/pyconfig.log" 2>&1 \
            || die "pyconfig.patch failed; see ${LOG_DIR}/pyconfig.log"

        # The 64-bit Python installer ships no import library, so build one
        # from the DLL's export table.
        ( cd "${BUILD}/dl" \
          && cp -f "${PREFIX}/python34.dll" . \
          && "${MXE}/usr/${TRIPLET}/bin/gendef" python34.dll \
          && "${MXE}/usr/bin/${TRIPLET}-dlltool" --dllname python34.dll \
                --def python34.def --output-lib libpython34.a \
          && mv -f libpython34.a "${PREFIX}/Python34/libs/" \
          && rm -f python34.dll ) > "${LOG_DIR}/gendef.log" 2>&1 \
            || die "building libpython34.a failed; see ${LOG_DIR}/gendef.log"

        # Some stdlib modules (ctypes) need their .pyd alongside - bug #1409.
        unzip -qo "${PREFIX}/python34.zip" '*.pyd' -d "${PREFIX}"

        # pkg-config knows nothing about any of the above; describe it.
        mkdir -p "${PREFIX}/lib/pkgconfig"
        cat > "${PREFIX}/lib/pkgconfig/python3.pc" <<EOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: Python
Description: Python library
Version: 3.4
Libs: ${PREFIX}/Python34/libs/libpython34.a
Cflags: -I${PREFIX}/Python34/include
EOF
        printf '    %-10s ok\n' "python"
    else
        printf '    %-10s cached\n' "python"
    fi

    # shellcheck disable=SC2086
    autotools_build libsigrokdecode ${CONF_COMMON} ${CONF_STATIC}
}

build_sigrok_cli() {
    # No --disable-shared here; upstream does not pass it to the frontends.
    # shellcheck disable=SC2086
    autotools_build sigrok-cli ${CONF_COMMON}
}

build_pulseview() {
    sync_source pulseview
    for p in pulseview-boost-numeric-literals.patch \
             pulseview-manual-pdf-hack.patch; do
        if patch -p1 --forward --dry-run < "${UTIL}/${p}" >/dev/null 2>&1; then
            patch -p1 --forward < "${UTIL}/${p}" >/dev/null 2>&1
            printf '    %-10s %s\n' "patch" "${p}"
        else
            # Already applied on an incremental run, or genuinely dead. Both
            # are survivable; a dead patch shows up as a build failure.
            printf '    %-10s %s (skipped)\n' "patch" "${p}"
        fi
    done
    cp -f "${UTIL}/FileAssociation.nsh" contrib/ 2>/dev/null || true

    [ -f ./CMakeCache.txt ] || run pulseview cmake "${TRIPLET}-cmake" \
        -DCMAKE_INSTALL_PREFIX:PATH="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DDISABLE_WERROR=y \
        -DENABLE_TESTS=y \
        . || return 1
    run pulseview make make -j"$(nproc)" || return 1
    run pulseview install make install/strip || return 1
}

# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

note "target ${TRIPLET}"
note "prefix ${PREFIX}"
note "logs   ${LOG_DIR}"

for c in ${COMPONENTS}; do
    note "${c}"
    case "${c}" in
        libserialport)    build_libserialport ;;
        libsigrok)        build_libsigrok ;;
        libsigrokdecode)  build_libsigrokdecode ;;
        sigrok-cli)       build_sigrok_cli ;;
        pulseview)        build_pulseview ;;
    esac
done

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

DRIVERS=0
DECODERS=0
# The driver count comes from libsigrok's configure summary, which only
# exists in runs where configure actually re-ran. On an incremental build it
# does not, so look in the build tree's own config.log rather than this run's
# log directory - otherwise the record reports a flat 0 drivers and looks
# like the catastrophe R-19 exists to catch.
DRIVER_LOG="${LOG_DIR}/libsigrok-configure.log"
# `|| true` is load-bearing: with `set -euo pipefail`, a glob that matches
# nothing makes ls exit 2, pipefail propagates that through `| head`, and the
# whole build dies here - after a successful compile, silently, taking the
# staging step with it. Which is exactly what happened once .work/logs was
# cleaned out and there was no previous configure log to find.
[ -f "${DRIVER_LOG}" ] || DRIVER_LOG="$(ls -t "${REPO}"/.work/logs/*/libsigrok-configure.log 2>/dev/null | head -1 || true)"
if [ -n "${DRIVER_LOG}" ] && [ -f "${DRIVER_LOG}" ]; then
    DRIVERS="$(sed -n '/Enabled hardware drivers/,/Enabled serial/p'         "${DRIVER_LOG}" | grep -cE '\.\.\.+ yes' || true)"
fi
if [ -d "${PREFIX}/share/libsigrokdecode/decoders" ]; then
    DECODERS="$(find "${PREFIX}/share/libsigrokdecode/decoders"         -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l || true)"
fi

{
    printf 'build_id     %s\n' "${BUILD_ID}"
    printf 'target       %s\n' "${TRIPLET}"
    printf 'components   %s\n' "${COMPONENTS}"
    printf 'prefix       %s\n' "${PREFIX}"
    printf 'drivers      %s\n' "${DRIVERS}"
    printf 'decoders     %s\n' "${DECODERS}"
    for exe in sigrok-cli pulseview; do
        [ -f "${PREFIX}/bin/${exe}.exe" ] && printf '%-12s %s\n' "${exe}" \
            "$(sha256sum "${PREFIX}/bin/${exe}.exe" | cut -d' ' -f1)"
    done
    printf 'source_revs\n'
    for c in ${ALL_COMPONENTS}; do
        printf '  %-18s %s\n' "${c}" \
            "$(git -C "${SRC}/${c}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    done
} > "${LOG_DIR}/record.txt" || true

printf '\n'
cat "${LOG_DIR}/record.txt"

# --------------------------------------------------------------------------
# Optional staging
# --------------------------------------------------------------------------

if [ "${DO_STAGE}" -eq 1 ]; then
    printf '\n'
    note "staging to ${STAGE}"
    # Deliberately not 07_Delivery itself: nothing has been run, let alone
    # verified on Windows, and doc 06 reserves 07_Delivery for verified
    # packages. This is a directory you can copy to a Windows box and try.
    rm -rf "${STAGE}"
    mkdir -p "${STAGE}"
    # Layout is not free choice. libsigrokdecode locates its decoders at
    # runtime with g_win32_get_package_installation_directory_of_module(),
    # then appends share\libsigrokdecode\decoders. So the executables sit at
    # the top and the decoders go under share/ - the same layout upstream's
    # NSIS installer produces. Putting the exe in bin/ or the decoders at the
    # top level gives a PulseView that starts with no decoders and no error.
    cp "${PREFIX}/bin/pulseview.exe" "${PREFIX}/bin/sigrok-cli.exe" "${STAGE}/"
    # python34.dll is the only non-system DLL either binary imports;
    # python34.zip is the stdlib the decoders import from.
    cp "${PREFIX}/python34.dll" "${PREFIX}/python34.zip" "${STAGE}/"
    mkdir -p "${STAGE}/share"
    cp -r "${PREFIX}/share/libsigrokdecode" "${STAGE}/share/"
    find "${PREFIX}" -maxdepth 1 -name '*.pyd' -exec cp {} "${STAGE}/" \;
    cp "${LOG_DIR}/record.txt" "${STAGE}/build-record.txt"
    ( cd "${STAGE}" && find . -type f ! -name SHA256SUMS \
        -exec sha256sum {} + > SHA256SUMS )
    du -sh "${STAGE}"
    cat <<EOF

  Unverified. Neither binary has been run on Windows. The device also needs a
  WinUSB association before it will enumerate.
EOF
fi

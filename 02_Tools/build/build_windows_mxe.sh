#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
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
#   - Embeds CPython 3.13 from python.org instead of the repackaged 3.4.4 that
#     upstream fetches over plaintext HTTP with --no-check-certificate. 3.4 has
#     been end-of-life since March 2019 and cannot parse f-strings, variable
#     annotations, enum.IntFlag or dataclasses, so any decoder using them was
#     silently absent on Windows while working on Linux.
#   - Skips `make manual`, which needs asciidoc and xsltproc and produces
#     documentation rather than a working application.
#   - Is incremental. Upstream deletes its build directory on every run; that
#     is fine when you build once per release and unusable when you are
#     iterating on a driver.
#
# Run it from the host; it re-executes itself inside the builder image:
#
#   bash build_windows_mxe.sh                       everything
#   bash build_windows_mxe.sh libsigrok pulseview   just those, in that order
#   bash build_windows_mxe.sh --clean               discard the build tree first
#   bash build_windows_mxe.sh --stage               assemble a runnable directory

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
        "${OUTER[@]}" -- bash /work/02_Tools/build/build_windows_mxe.sh "$@"
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

# The Windows CPython that libsigrokdecode embeds. MXE has no python3 for the
# Windows target - only host-side helpers - so the interpreter comes from
# python.org: the official Windows embeddable package for the runtime, and the
# release source tarball for the headers, which that package does not ship.
#
# Both are pinned by version and sha256 in 02_Tools/upstream/upstreams.lock.toml
# and baked into the builder image at /opt/sigrok-deps, so a normal build
# reaches no network at all. These values are the fallback for an older image
# that predates the bake; they are checked against the image's own manifest
# below, so the two cannot drift apart silently.
#
# Bumping the version is these three lines plus the two lock entries. PY_TAG is
# the suffix python.org uses for the DLL, the stdlib zip and the ._pth file.
PY_VERSION=3.13.15
PY_TAG=313
PY_SHA_EMBED=d1f04d990aee1253d8569e8e5104e30fa9f5fa830899f14843448872d936a2cf
PY_SHA_SOURCE=1e66a7945a48390ee4c2a4268a0e4185884059a13c4aab6d148aa208deea4a76

PY_EMBED_ZIP="python-${PY_VERSION}-embed-amd64.zip"
PY_SOURCE_TAR="Python-${PY_VERSION}.tar.xz"
PY_BASE="https://www.python.org/ftp/python/${PY_VERSION}"
# Where the unpacked runtime and headers live inside the build prefix. Not
# named after the version, so nothing but the constants above has to change.
PYDIR="${PREFIX}/python-win"

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
    # it: the build then reaches no network at all, and does not depend on
    # python.org being reachable at the moment somebody rebuilds.
    # The download below is the fallback for an image predating the bake.
    if [ ! -f "${dest}" ] && [ -f "/opt/sigrok-deps/${file}" ]; then
        cp "/opt/sigrok-deps/${file}" "${dest}"
    fi
    if [ ! -f "${dest}" ]; then
        note "  ${file} not in image; downloading"
        wget -q -O "${dest}.part" "${PY_BASE}/${file}" \
            || { rm -f "${dest}.part"; die "download failed: ${file}
  A normal build never reaches here: the artifact should be baked into the
  builder image at /opt/sigrok-deps. Rebuild the image with build_image.sh,
  or check that this run has a network if the image predates the bake."; }
        mv "${dest}.part" "${dest}"
    fi
    local got
    got="$(sha256sum "${dest}" | cut -d' ' -f1)"
    [ "${got}" = "${want}" ] || die \
        "checksum mismatch for ${file}
  expected ${want}
  got      ${got}
  This artifact is pinned in 02_Tools/upstream/upstreams.lock.toml. Do not
  proceed until the difference is explained; delete ${dest} to retry."
}

# The image bakes one Python version; this script names one. If a newer script
# meets an older image the mismatch has to be loud, because the failure it
# otherwise produces is a compile against one CPython's headers and a link
# against another's import library - which builds, and then misbehaves at
# runtime in ways nobody would trace back to here.
check_image_python() {
    local baked="/opt/sigrok-deps/PY_VERSION"
    [ -f "${baked}" ] || return 0
    local have
    have="$(cat "${baked}")"
    [ "${have}" = "${PY_VERSION}" ] || die \
        "builder image carries Python ${have}, this script expects ${PY_VERSION}
  Rebuild the image: bash 02_Tools/build/build_image.sh --image mingw"
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
# against. MXE has none, so assemble one from python.org's own artifacts.
#
# The shape is upstream's - unpack a Windows Python, manufacture an import
# library from the DLL, hand-write a python3.pc - but the inputs are the
# official embeddable package and release source tarball rather than a
# repackaged end-of-life build from a third-party host.
prepare_python() {
    check_image_python
    fetch_verified "${PY_EMBED_ZIP}"   "${PY_SHA_EMBED}"
    fetch_verified "${PY_SOURCE_TAR}"  "${PY_SHA_SOURCE}"

    # Reuse the unpacked tree only when it is the same release. Testing for
    # the import library alone would be wrong: 3.13.15 and 3.13.16 both
    # produce libpython313.a, so a patch-level bump would find the old tree,
    # skip this whole function, and quietly ship the previous interpreter on
    # an incremental build. The stamp is the version, so any bump re-prepares.
    if [ "$(cat "${PYDIR}/VERSION" 2>/dev/null)" = "${PY_VERSION}" ] \
       && [ -f "${PYDIR}/libs/libpython${PY_TAG}.a" ]; then
        printf '    %-10s cached %s\n' "python" "${PY_VERSION}"
        return 0
    fi

    rm -rf "${PYDIR}"
    mkdir -p "${PYDIR}/runtime" "${PYDIR}/libs" "${PYDIR}/include"

    # The runtime, exactly as python.org ships it. Kept whole rather than
    # hand-picked: an import-table walk shows the package is precisely
    # self-closed - _ctypes.pyd needs libffi-8.dll, _hashlib.pyd needs
    # libcrypto-3.dll - and everything else it imports is an api-ms-win-*
    # UCRT stub present on any supported Windows. Dropping a .pyd to save a
    # few megabytes would come back as a decoder that fails to import, and
    # libsigrokdecode discards decoder load errors, so it would come back
    # silently.
    unzip -qo "${BUILD}/dl/${PY_EMBED_ZIP}" -d "${PYDIR}/runtime"

    # Headers. The embeddable package ships none, and since 3.13 CPython
    # generates the Windows pyconfig.h at build time from PC/pyconfig.h.in
    # instead of shipping a static PC/pyconfig.h - that .in file is the
    # standard-build header verbatim, so copy it into place.
    tar xJf "${BUILD}/dl/${PY_SOURCE_TAR}" -C "${PYDIR}/include" \
        --strip-components=2 --wildcards \
        "Python-${PY_VERSION}/Include/*" || die "unpacking Python headers failed"
    tar xJf "${BUILD}/dl/${PY_SOURCE_TAR}" -O --wildcards \
        "Python-${PY_VERSION}/PC/pyconfig.h.in" > "${PYDIR}/include/pyconfig.h" \
        || die "extracting PC/pyconfig.h.in failed"
    [ -s "${PYDIR}/include/pyconfig.h" ] || die "PC/pyconfig.h.in came out empty"

    # sigrok-util's pyconfig.patch is deliberately NOT applied. It exists for
    # upstream bug #1195, where the 3.4 header left MS_WIN64 undefined under
    # mingw so Py_ssize_t came out 4 bytes wide on 64-bit Windows and no
    # decoder worked at all. CPython carries that __MINGW32__ block itself
    # now. The probe below is what proves it, every build, rather than this
    # comment being taken on trust.
    #
    # The official 64-bit Python ships no import library, so build one from
    # the DLL's export table.
    ( cd "${PYDIR}/libs" \
      && cp -f "${PYDIR}/runtime/python${PY_TAG}.dll" . \
      && "${MXE}/usr/${TRIPLET}/bin/gendef" "python${PY_TAG}.dll" \
      && "${MXE}/usr/bin/${TRIPLET}-dlltool" \
            --dllname "python${PY_TAG}.dll" \
            --def "python${PY_TAG}.def" \
            --output-lib "libpython${PY_TAG}.a" \
      && rm -f "python${PY_TAG}.dll" ) > "${LOG_DIR}/gendef.log" 2>&1 \
        || die "building libpython${PY_TAG}.a failed; see ${LOG_DIR}/gendef.log"

    # pkg-config knows nothing about any of the above; describe it.
    # libsigrokdecode's configure.ac probes python-3.12-embed and friends by
    # module name and then falls back to `python3 >= 3.2`, which is the
    # alternative this file satisfies - so the version list in configure.ac
    # does not need extending for a newer Python.
    mkdir -p "${PREFIX}/lib/pkgconfig"
    cat > "${PREFIX}/lib/pkgconfig/python3.pc" <<EOF
prefix=${PYDIR}
exec_prefix=\${prefix}
libdir=\${prefix}/libs
includedir=\${prefix}/include
Name: Python
Description: Python library
Version: ${PY_VERSION%.*}
Libs: \${libdir}/libpython${PY_TAG}.a
Cflags: -I\${includedir}
EOF
    # Written last, so an interrupted preparation is not mistaken for a
    # complete one on the next run.
    printf '%s\n' "${PY_VERSION}" > "${PYDIR}/VERSION"
    printf '    %-10s %s\n' "python" "${PY_VERSION}"
}

# Compile-only guard against the bug #1195 class of failure: a header set that
# leaves the interpreter's word size or version wrong builds cleanly and then
# loses every decoder at runtime with no diagnostic. Cheap enough to run on
# every build - it is one invocation of the compiler and no link.
check_python_headers() {
    local probe="${BUILD}/dl/pyabi_probe.c"
    cat > "${probe}" <<'EOF'
#include <Python.h>
/* Bug #1195: without MS_WIN64 the 64-bit build gets a 4-byte Py_ssize_t,
   which compiles and then breaks every decoder at runtime. */
#ifndef MS_WIN64
#error "MS_WIN64 undefined: pyconfig.h is missing the mingw translation (bug #1195)"
#endif
_Static_assert(sizeof(Py_ssize_t) == 8, "Py_ssize_t must be 8 bytes on win64");
_Static_assert(sizeof(void *) == 8, "pointer must be 8 bytes on win64");
/* Decoders may use f-strings, variable annotations, enum.IntFlag and
   dataclasses. The oldest interpreter that parses all of those is 3.7; 3.9 is
   the floor this project commits to. */
_Static_assert(PY_VERSION_HEX >= 0x030900F0, "embedded CPython must be 3.9 or newer");
EOF
    "${TRIPLET}-gcc" -fsyntax-only -I"${PYDIR}/include" "${probe}" \
        > "${LOG_DIR}/python-abi.log" 2>&1 \
        || { sed -n '1,20p' "${LOG_DIR}/python-abi.log" >&2
             die "Python header check failed; see ${LOG_DIR}/python-abi.log"; }
    printf '    %-10s ok\n' "abi-check"
}

build_libsigrokdecode() {
    note "  preparing Windows Python ${PY_VERSION}"
    prepare_python
    check_python_headers

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

# Walk the import table of every PE in the staged tree and require each
# imported DLL to be either a Windows system DLL or present in the tree.
#
# This is the check that makes shipping the Python runtime whole safe to
# maintain. The alternative failure is quiet and slow to diagnose: a missing
# libffi-8.dll means _ctypes fails to import, which means a decoder that
# imports ctypes fails to load, and libsigrokdecode discards decoder load
# errors - so the decoder is simply absent from the list, with nothing
# anywhere saying why.
#
# api-ms-win-* and ext-ms-* are the API-set stubs resolved by Windows itself,
# and the rest of the list is the stock system DLL set. Anything else has to
# be in the directory.
check_stage_imports() {
    local sysre='^(api-ms-win-|ext-ms-)'
    local known='kernel32|kernelbase|user32|advapi32|ws2_32|shlwapi|ole32|oleaut32|shell32|version|crypt32|bcrypt|rpcrt4|gdi32|gdiplus|winmm|msvcrt|ucrtbase|imagehlp|iphlpapi|netapi32|mswsock|secur32|userenv|wldap32|dbghelp|psapi|comdlg32|comctl32|setupapi|cfgmgr32|winhttp|wininet|mpr|pdh|powrprof|propsys|windowscodecs|dwmapi|uxtheme|d3d9|d3d11|dxgi|opengl32|glu32|wtsapi32|authz|dnsapi|sspicli|normaliz|profapi|winspool.drv|imm32|hid|usp10|dcomp|dwrite'
    local missing=0 f dll base
    while IFS= read -r f; do
        while IFS= read -r dll; do
            base="$(printf '%s' "${dll}" | tr '[:upper:]' '[:lower:]')"
            printf '%s' "${base}" | grep -qE "${sysre}" && continue
            printf '%s' "${base}" | grep -qE "^(${known})\.dll$" && continue
            # Case-insensitively: is it here?
            if ! find "${STAGE}" -maxdepth 1 -iname "${base}" \
                 | grep -q .; then
                printf '    MISSING  %s needs %s\n' \
                    "$(basename "${f}")" "${dll}" >&2
                missing=$((missing + 1))
            fi
        done < <("${TRIPLET}-objdump" -p "${f}" 2>/dev/null \
                 | sed -n 's/^\s*DLL Name: //p')
    done < <(find "${STAGE}" -maxdepth 1 -type f \
             \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.pyd' \))
    [ "${missing}" -eq 0 ] || die \
        "${missing} unresolved DLL import(s) in the staged tree.
  Every one of these is a module that will fail to import on the target. A
  decoder that imports such a module is dropped without a diagnostic, so this
  has to be fixed here rather than found later."
    printf '    %-10s ok\n' "imports"
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
# Directories, not listed decoders: one of them is `common`, the shared helper
# package the decoders import, which is not itself a decoder and never appears
# in `sigrok-cli -L`. So this figure is one higher than the listing, and has
# been since the first build - kept as-is so records stay comparable.
# 02_Tools/test/windows_python_smoke.sh is what checks the real invariant,
# that every decoder directory except `common` actually loads.
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
    printf 'python       %s\n' "${PY_VERSION}"
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
    # The Python runtime goes beside the executables, whole. python<tag>._pth
    # travels with it and is what fixes sys.path to [python<tag>.zip, .] once
    # the interpreter starts: the stdlib comes out of the zip and the loose
    # .pyd modules - _ctypes among them, for upstream bug #1409 - are found in
    # the directory itself. No PYTHONPATH, and no reading of the registry, so
    # another Python installed on the target cannot capture this one.
    cp "${PYDIR}"/runtime/* "${STAGE}/"
    mkdir -p "${STAGE}/share"
    cp -r "${PREFIX}/share/libsigrokdecode" "${STAGE}/share/"
    cp "${LOG_DIR}/record.txt" "${STAGE}/build-record.txt"
    check_stage_imports
    ( cd "${STAGE}" && find . -type f ! -name SHA256SUMS \
        -exec sha256sum {} + > SHA256SUMS )
    du -sh "${STAGE}"
    cat <<EOF

  Unverified. Neither binary has been run on Windows. The device also needs a
  WinUSB association before it will enumerate.
EOF
fi

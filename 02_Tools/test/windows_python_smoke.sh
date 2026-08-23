#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Smoke test for the Python embedded in the staged Windows build.
#
# This is a host-side test, not a build step, because it runs Windows
# executables and the MXE builder image has no Wine. Run it on Windows (Git
# Bash) against a staged tree, or on Linux with wine installed:
#
#   02_Tools/test/windows_python_smoke.sh [staging-dir]
#
# What it settles, and why it is shaped this way: libsigrokdecode's
# srd_decoder_load_all_path() discards the error from every decoder that fails
# to load, so a decoder the interpreter cannot parse does not appear in the
# listing and nothing anywhere says why. The only way to observe that is to
# count. So the test establishes a baseline count, adds a decoder that an
# interpreter older than 3.6 cannot parse, and requires the count to go up -
# then removes it and requires the count to come back down, which is what
# distinguishes "the decoder loaded" from "the listing is not what I think".
#
# Exit codes: 0 pass, 1 fail, 77 cannot run here (no runner for .exe).

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="${1:-${REPO}/07_Delivery/staging/pulseview-windows-x86_64}"
DECODERS="${STAGE}/share/libsigrokdecode/decoders"
PROBE_ID="zz-fstring-probe"
PROBE_DIR="${DECODERS}/${PROBE_ID//-/_}"

pass() { printf '    ok    %s\n' "$*"; }
fail() { printf '    FAIL  %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }
note() { printf '==> %s\n' "$*"; }
FAILED=0

[ -d "${STAGE}" ] || { printf 'error: no staged tree at %s\n' "${STAGE}" >&2; exit 1; }
[ -d "${DECODERS}" ] || { printf 'error: no decoders at %s\n' "${DECODERS}" >&2; exit 1; }

CLI="${STAGE}/sigrok-cli.exe"
[ -f "${CLI}" ] || { printf 'error: no sigrok-cli.exe in %s\n' "${STAGE}" >&2; exit 1; }

# Pick a runner. On Windows the .exe is native; elsewhere it needs Wine.
RUNNER=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)  if command -v wine64 >/dev/null 2>&1; then RUNNER=(wine64)
        elif command -v wine >/dev/null 2>&1; then RUNNER=(wine)
        else
            printf 'skip: not Windows and no wine on PATH; cannot run %s\n' \
                "$(basename "${CLI}")" >&2
            exit 77
        fi ;;
esac

TMP="$(mktemp -d)"

# Always leave the staged tree as we found it, including on a failed
# assertion - this runs against a real delivery directory.
cleanup() { rm -rf "${PROBE_DIR}"; find "${DECODERS}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null; }
trap 'cleanup; rm -rf "${TMP}"' EXIT

run_cli() { ( cd "${STAGE}" && "${RUNNER[@]}" "./$(basename "${CLI}")" "$@" 2>&1 ); }

# `-L` lists drivers, input, output and transform modules before the decoders,
# every entry two-space indented, with CRLF line endings. The decoder section
# is last, so take everything from its heading on.
list_decoders() {
    run_cli -L | tr -d '\r' \
        | sed -n '/^Supported protocol decoders:/,$p' \
        | grep -E '^  [a-z0-9]' | awk '{print $1}' | sort
}

# The decoder directories that should each produce one listed decoder.
# `common` is excluded: it is the shared helper package that decoders import
# (common.srdhelper and friends), not a decoder, and it is correctly absent
# from the listing.
installed_decoders() {
    find "${DECODERS}" -maxdepth 1 -mindepth 1 -type d \
        ! -name '__pycache__' ! -name 'common' \
        | while IFS= read -r d; do basename "${d}"; done | sort
}

note "staged tree ${STAGE}"

# ---------------------------------------------------------------------------
# 1. The embedded interpreter is one that can parse post-3.4 syntax at all.
# ---------------------------------------------------------------------------
VERSION_OUT="$(run_cli --version)"
PYVER="$(printf '%s\n' "${VERSION_OUT}" | grep -oiE 'python [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')"
if [ -z "${PYVER}" ]; then
    fail "no Python version in --version output"
else
    PY_MAJ="${PYVER%%.*}"; PY_MIN="$(printf '%s' "${PYVER}" | cut -d. -f2)"
    if [ "${PY_MAJ}" -gt 3 ] || { [ "${PY_MAJ}" -eq 3 ] && [ "${PY_MIN}" -ge 9 ]; }; then
        pass "embedded Python ${PYVER} is 3.9 or newer"
    else
        fail "embedded Python ${PYVER} is older than 3.9"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Every installed decoder directory is actually listed. A decoder that
#    fails to load is silently missing, so the count is the only signal.
# ---------------------------------------------------------------------------
installed_decoders > "${TMP}/installed"
list_decoders > "${TMP}/baseline"
INSTALLED="$(wc -l < "${TMP}/installed" | tr -d ' ')"
BASELINE="$(wc -l < "${TMP}/baseline" | tr -d ' ')"
MISSING="$(comm -23 "${TMP}/installed" "${TMP}/baseline" | tr '\n' ' ')"
if [ -z "${MISSING}" ] && [ "${BASELINE}" -eq "${INSTALLED}" ]; then
    pass "all ${INSTALLED} installed decoders are listed"
else
    fail "${INSTALLED} decoders installed but ${BASELINE} listed; failed to load silently: ${MISSING:-none}"
fi

# ---------------------------------------------------------------------------
# 3. A decoder using syntax that 3.4 cannot parse loads and is listed.
# ---------------------------------------------------------------------------
rm -rf "${PROBE_DIR}"
mkdir -p "${PROBE_DIR}"
cat > "${PROBE_DIR}/__init__.py" <<'EOF'
from .pd import Decoder
EOF
# f-string (3.6), variable annotation (3.6), enum.IntFlag (3.6), dataclass
# (3.7). Each of these is a SyntaxError or ImportError on 3.4, and each is
# used by decoders this build is meant to be able to accept.
cat > "${PROBE_DIR}/pd.py" <<'EOF'
import enum
from dataclasses import dataclass
import sigrokdecode as srd

@dataclass
class Probe:
    width: int = 7

class Flags(enum.IntFlag):
    NONE = 0
    SET = 1

_answer: int = Probe().width * 6
_label: str = f'probe {_answer} {Flags.SET.value}'

class Decoder(srd.Decoder):
    api_version = 3
    id = 'zz_fstring_probe'
    name = 'zz-fstring-probe'
    longname = f'Throwaway probe {_label}'
    desc = 'Temporary decoder used by windows_python_smoke.sh; safe to delete.'
    license = 'gplv2+'
    inputs = ['logic']
    outputs = []
    tags = ['Util']
    channels = (
        {'id': 'data', 'name': 'Data', 'desc': 'Data line'},
    )
    annotations = (
        ('probe', 'Probe'),
    )

    def __init__(self):
        self.reset()

    def reset(self):
        self.out_ann = None

    def start(self):
        self.out_ann = self.register(srd.OUTPUT_ANN)

    def decode(self):
        pass
EOF

if list_decoders | grep -qx 'zz_fstring_probe'; then
    pass "decoder using f-string, annotation, IntFlag and dataclass is listed"
else
    fail "decoder using post-3.4 syntax did not load; libsigrokdecode discards the load error, so there is no diagnostic to read"
fi

# ---------------------------------------------------------------------------
# 4. Removing it returns the listing to the baseline. Without this, step 3
#    could pass against a listing that counts something other than decoders.
# ---------------------------------------------------------------------------
cleanup
AFTER="$(list_decoders | wc -l | tr -d ' ')"
if [ "${AFTER}" -eq "${BASELINE}" ]; then
    pass "listing returned to ${BASELINE} after removing the probe"
else
    fail "listing is ${AFTER} after removing the probe, expected ${BASELINE}"
fi

printf '\n'
if [ "${FAILED}" -eq 0 ]; then
    note "windows python smoke: pass"
    exit 0
fi
note "windows python smoke: ${FAILED} failed"
exit 1

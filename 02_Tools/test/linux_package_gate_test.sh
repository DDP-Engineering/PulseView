#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-REL-dc0ff39f: a thin Linux package is emitted only after the staged
# CLI starts and exposes both project drivers. A device-specific --show
# remains informational because no USB instrument is required on a build host.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="${HERE}/../build/verify_linux_stage.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

[ -f "${VERIFY}" ] || {
    fail "verify_linux_stage.sh is missing"
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
STAGE="${TMP}/stage"
mkdir -p "${STAGE}"

cat >"${STAGE}/sigrok-cli" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --version)
        [ "${STUB_VERSION_FAIL:-0}" -eq 0 ] || {
            echo 'cannot load staged binary' >&2
            exit 7
        }
        echo 'sigrok-cli test-version'
        ;;
    -L|--list-supported)
        printf '%b\n' "${STUB_DRIVERS:-}"
        ;;
    --driver|-d)
        echo 'No devices found.'
        exit "${STUB_SHOW_RC:-1}"
        ;;
    *)
        echo "unexpected arguments: $*" >&2
        exit 9
        ;;
esac
STUB
chmod +x "${STAGE}/sigrok-cli"

GOOD_DRIVERS='  atk-dl16             ALIENTEK ATK DL16\n  hantek-dso3062l      Hantek DSO-3062L'

if STUB_VERSION_FAIL=1 STUB_DRIVERS="${GOOD_DRIVERS}" \
   bash "${VERIFY}" "${STAGE}" >/dev/null 2>&1; then
    fail "a staged CLI that cannot report its version was accepted"
fi

if STUB_DRIVERS='  hantek-dso3062l      Hantek DSO-3062L' \
   bash "${VERIFY}" "${STAGE}" >/dev/null 2>&1; then
    fail "a stage missing atk-dl16 was accepted"
fi

OUT="$(STUB_DRIVERS="${GOOD_DRIVERS}" STUB_SHOW_RC=1 \
      bash "${VERIFY}" "${STAGE}" 2>&1)" ||
    fail "valid stage failed because the no-hardware probe returned non-zero"
printf '%s\n' "${OUT}" | grep -q 'sigrok-cli test-version' ||
    fail "successful version output was not reported"
printf '%s\n' "${OUT}" | grep -q 'device probe skipped' ||
    fail "non-fatal no-hardware result was not identified"

if [ "${FAILURES}" -gt 0 ]; then
    printf '%d assertion(s) failed\n' "${FAILURES}" >&2
    exit 1
fi
printf 'linux package gate: all assertions passed\n'

#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shell scripts are intentionally tracked without executable mode. Public
# examples and container re-entry points must therefore invoke them with bash
# rather than relying on a checkout-specific executable bit.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"

DOCS=(
    "${REPO_ROOT}/README.md"
    "${REPO_ROOT}/01_Documentation/Environment_Setup.md"
    "${REPO_ROOT}/01_Documentation/Testing.md"
    "${REPO_ROOT}/02_Tools/bootstrap/README.md"
    "${REPO_ROOT}/02_Tools/build/README.md"
    "${REPO_ROOT}/02_Tools/build/STATUS.md"
    "${REPO_ROOT}/02_Tools/build/images/README.md"
    "${REPO_ROOT}/07_Delivery/toolchain/README.md"
)

DIRECT_PATTERN='^[[:space:]]*(\./|02_Tools/)[A-Za-z0-9_./-]+\.sh([[:space:]]|$)'
for document in "${DOCS[@]}"; do
    if grep -nE "${DIRECT_PATTERN}" "${document}"; then
        echo "FAIL: $(basename "${document}") contains a direct non-executable shell-script invocation" >&2
        exit 1
    fi
done

grep -q -- '-- bash /work/02_Tools/build/build_appimage.sh' \
    "${REPO_ROOT}/02_Tools/build/build_appimage.sh" \
    || { echo 'FAIL: AppImage container re-entry does not use bash' >&2; exit 1; }
grep -q -- '-- bash /work/02_Tools/build/build_windows_mxe.sh' \
    "${REPO_ROOT}/02_Tools/build/build_windows_mxe.sh" \
    || { echo 'FAIL: MXE container re-entry does not use bash' >&2; exit 1; }
grep -q -- '-- bash /mnt/f/2026_PulseView/02_Tools/bootstrap/check_host.sh' \
    "${REPO_ROOT}/02_Tools/bootstrap/check_host.sh" \
    || { echo 'FAIL: check_host.sh WSL example does not use bash' >&2; exit 1; }

printf 'shell invocation contract: all assertions passed\n'
exit 0

# END OF FILE

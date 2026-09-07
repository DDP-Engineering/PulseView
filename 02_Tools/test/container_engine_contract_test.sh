#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Every entry point that runs a container must obey the same engine selection.
# build_image.sh, ensure_build_environment.sh, run_in_builder.sh, load_image.sh
# and save_image_parts.sh have always offered --engine docker|podman; the host
# check and the native Linux build used to hardcode docker, so a Podman host
# was told it had no engine while the scripts it was about to run were happy.

set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${HERE}/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/02_Tools/build"
BOOTSTRAP_DIR="${REPO_ROOT}/02_Tools/bootstrap"
CHECK="${BOOTSTRAP_DIR}/check_host.sh"
BUILD_LINUX="${BUILD_DIR}/build_linux.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PY="$(command -v python3 || command -v python || true)"

# --------------------------------------------------------------------------
# Every entry point offers the same option and the same default
# --------------------------------------------------------------------------

for script in \
    "${BUILD_DIR}/build_image.sh" \
    "${BUILD_DIR}/build_linux.sh" \
    "${BUILD_DIR}/run_in_builder.sh" \
    "${BUILD_DIR}/load_image.sh" \
    "${BUILD_DIR}/save_image_parts.sh" \
    "${BOOTSTRAP_DIR}/ensure_build_environment.sh" \
    "${BOOTSTRAP_DIR}/check_host.sh"
do
    [ -f "${script}" ] || { echo "FAIL: missing ${script}" >&2; exit 1; }
    grep -q 'BUILDER_ENGINE:-docker' "${script}" \
        || { echo "FAIL: $(basename "${script}") does not honor BUILDER_ENGINE" >&2
             exit 1; }
    grep -q -- '--engine)' "${script}" \
        || { echo "FAIL: $(basename "${script}") has no --engine option" >&2; exit 1; }
done

# --------------------------------------------------------------------------
# No entry point invokes a hardcoded engine binary
# --------------------------------------------------------------------------

for script in "${BUILD_LINUX}" "${CHECK}"; do
    if grep -nE '^[^#]*(^|[^_a-zA-Z0-9"])docker[[:space:]]+(run|info|image|load|save|volume)' \
        "${script}"; then
        echo "FAIL: $(basename "${script}") calls docker directly" >&2
        exit 1
    fi
done

# --------------------------------------------------------------------------
# An unavailable engine is reported as that engine, not as docker
# --------------------------------------------------------------------------

MISSING_ENGINE="pulseview-absent-engine"

# --print-base is deliberate: the engine check must come first, so this can
# never start a real build even if that ordering regresses.
if BUILDER_ENGINE="${MISSING_ENGINE}" bash "${BUILD_LINUX}" --print-base \
       >"${TMP}/linux.out" 2>&1; then
    echo 'FAIL: build_linux.sh ran with no container engine present' >&2
    exit 1
fi
grep -q "${MISSING_ENGINE}" "${TMP}/linux.out" \
    || { echo 'FAIL: build_linux.sh did not name the selected engine' >&2
         cat "${TMP}/linux.out" >&2; exit 1; }
grep -qi 'apt-get\|docker run\|pulling' "${TMP}/linux.out" \
    && { echo 'FAIL: build_linux.sh got past the engine check' >&2; exit 1; }

if [ -n "${PY}" ]; then
    bash "${CHECK}" --engine "${MISSING_ENGINE}" --result "${TMP}/check.json" \
        >/dev/null 2>&1 || true
    row="$("${PY}" - "${TMP}/check.json" "${MISSING_ENGINE}" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
names = [c["check"] for c in data["checks"]]
if sys.argv[2] not in names:
    print("ABSENT|" + ",".join(names))
else:
    for check in data["checks"]:
        if check["check"] == sys.argv[2]:
            print(check["status"] + "|" + check["detail"])
            break
PYEOF
)"
    case "${row}" in
        FAIL*) ;;
        *) echo "FAIL: check_host.sh did not fail on the selected engine: ${row}" >&2
           exit 1 ;;
    esac
fi

# --------------------------------------------------------------------------
# A selected non-Docker engine survives the container boundary
# --------------------------------------------------------------------------

mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/podman-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ENGINE_LOG}"
case "${1:-}" in
    --version) echo 'podman-stub 1.0'; exit 0 ;;
    info) exit 1 ;;
    run) exit 0 ;;
    *) exit 1 ;;
esac
STUB
chmod +x "${TMP}/bin/podman-stub"

ENGINE_LOG="${TMP}/engine.log" PATH="${TMP}/bin:${PATH}" \
    bash "${BUILD_LINUX}" --engine podman-stub >"${TMP}/podman-build.out" 2>&1

grep -q '^run ' "${TMP}/engine.log" \
    || { echo 'FAIL: build_linux.sh did not invoke the selected engine' >&2; exit 1; }
grep -q -- '-e BUILDER_ENGINE=podman-stub' "${TMP}/engine.log" \
    || { echo 'FAIL: build_linux.sh did not forward engine selection into the container' >&2
         cat "${TMP}/engine.log" >&2; exit 1; }
grep -q '/run/\.containerenv' "${BUILD_LINUX}" \
    || { echo 'FAIL: build_linux.sh does not recognize the Podman container marker' >&2; exit 1; }

ENGINE_LOG="${TMP}/check-engine.log" PATH="${TMP}/bin:${PATH}" \
    bash "${CHECK}" --engine podman-stub --toolchain-dir "${TMP}/absent" \
        >"${TMP}/podman-check.out" 2>&1 || true
grep -q 'podman-stub info' "${TMP}/podman-check.out" \
    || { echo 'FAIL: non-Docker engine failure has no selected-engine remedy' >&2
         cat "${TMP}/podman-check.out" >&2; exit 1; }
if grep -q 'sudo service docker start' "${TMP}/podman-check.out"; then
    echo 'FAIL: non-Docker engine failure recommends starting Docker' >&2
    exit 1
fi

printf 'container engine contract: all assertions passed\n'
exit 0

# END OF FILE

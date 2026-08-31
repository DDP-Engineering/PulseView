#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# REQ-PLAT-ceeee15c: prove arm64 support through the configured container
# engine, not by the mere presence of a binfmt file, and keep the privileged
# remediation image pinned to an immutable digest.
#
# The full host check has other probes. A stub Docker command isolates the
# arm64 behavior and records the exact run arguments without touching Docker.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${HERE}/../bootstrap/check_host.sh"
LOCK="${HERE}/../upstream/upstreams.lock.toml"

FAILURES=0
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

PINNED_IMAGE="$(python3 - "${LOCK}" <<'PYEOF' 2>/dev/null
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
for item in data.get("artifact", []):
    if item.get("name") == "tonistiigi-binfmt-image":
        print(item["url"].removeprefix("docker://"))
        break
PYEOF
)"
[ -n "${PINNED_IMAGE}" ] || fail "tonistiigi-binfmt-image is not pinned in the upstream lock"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/none" "${TMP}/yes"
printf 'enabled\ninterpreter /usr/bin/qemu-aarch64-static\n' \
    > "${TMP}/yes/qemu-aarch64"
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --version) echo 'Docker version test'; exit 0 ;;
    info)
        if [ "${2:-}" = "--format" ]; then echo /tmp; fi
        exit 0
        ;;
    image) exit 1 ;;
    run)
        printf '%s\n' "$*" >>"${STUB_DOCKER_LOG}"
        [ "${STUB_ARM_RUN:-fail}" = pass ] && exit 0
        exit 1
        ;;
esac
exit 0
STUB
chmod +x "${TMP}/bin/docker"

# The full script runs real environment probes around the one under test;
# their outcome is irrelevant here, only the arm64 lines are inspected.
run_check() {
    CHECK_HOST_MACHINE="$1" BINFMT_DIR="$2" \
    STUB_ARM_RUN="$3" STUB_DOCKER_LOG="${TMP}/docker.log" \
    PATH="${TMP}/bin:${PATH}" bash "${CHECK}" 2>&1
}

# --- an enabled handler is not enough when Docker execution fails --------
: >"${TMP}/docker.log"
OUT="$(run_check x86_64 "${TMP}/yes" fail)"; RC_NONE=$?
printf '%s\n' "${OUT}" | grep -E '^\s*WARN\s+arm64' >/dev/null \
    || fail "no WARN arm64 line when the Docker arm64 run fails"
printf '%s\n' "${OUT}" | grep -Fq "${PINNED_IMAGE}" \
    || fail "the binfmt remedy does not use the image pinned in the upstream lock"
printf '%s\n' "${OUT}" | grep -E '^\s*FAIL\s+arm64' >/dev/null \
    && fail "a missing arm64 capability must WARN, not FAIL"
grep -q -- '--pull never' "${TMP}/docker.log" \
    || fail "arm64 probe may pull or mutate the local image store"
grep -q -- '--platform linux/arm64' "${TMP}/docker.log" \
    || fail "Docker probe did not request linux/arm64"

# --- a successful Docker execution is the PASS condition -----------------
OUT="$(run_check x86_64 "${TMP}/yes" pass)"; RC_YES=$?
printf '%s\n' "${OUT}" | grep -E '^\s*PASS\s+arm64' >/dev/null \
    || fail "no PASS arm64 line when the Docker arm64 run succeeds"

# --- the probe result must not change the script's exit status -----------
[ "${RC_NONE}" -eq "${RC_YES}" ] \
    || fail "exit status differs with (${RC_YES}) and without (${RC_NONE}) arm64 support"

if [ "${FAILURES}" -gt 0 ]; then
    printf '%d assertion(s) failed\n' "${FAILURES}" >&2
    exit 1
fi
printf 'check_host arm64 probe: all assertions passed\n'
exit 0

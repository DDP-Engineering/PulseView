#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Decode evidence for the batch-one Tier A networking stack: nrzi -> 4b5b ->
# ethernet -> arp, and nrzi -> 4b5b -> ethernet -> ipv4 -> udp.
#
# windows_python_smoke.sh proves every installed decoder directory loads; it
# says nothing about whether a stacked decoder chain actually decodes. This
# test is that other half: it generates two synthetic captures with
# gen_networking_stack_captures.py (a real Ethernet II frame, correct FCS,
# IPv4 header checksum, and UDP checksum, NRZI/4B5B-encoded down to a raw
# sample stream) and requires each expected protocol field to appear in the
# real decoders' own annotation output - not merely that the chain loads and
# produces nothing.
#
#   02_Tools/test/networking_stack_decode_smoke.sh [staging-dir]
#
# Like windows_python_smoke.sh, this is host-side, not a build step, and
# runs against a staged tree. staging-dir defaults to the Windows staging
# tree; pass the Linux staging tree's path explicitly to check that build
# instead (native only there - no wine fallback is attempted for the Linux
# binary since it is not a .exe).
#
# Exit codes: 0 pass, 1 fail, 77 cannot run here (no runner, or no python3).

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="${1:-${REPO}/07_Delivery/staging/pulseview-windows-x86_64}"
GEN="${REPO}/02_Tools/test/gen_networking_stack_captures.py"

pass() { printf '    ok    %s\n' "$*"; }
fail() { printf '    FAIL  %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }
note() { printf '==> %s\n' "$*"; }
FAILED=0

[ -d "${STAGE}" ] || { printf 'error: no staged tree at %s\n' "${STAGE}" >&2; exit 1; }

PY=""
for cand in python3 python; do
    command -v "${cand}" >/dev/null 2>&1 && { PY="${cand}"; break; }
done
[ -n "${PY}" ] || { printf 'skip: no python3/python on PATH to generate captures\n' >&2; exit 77; }

# Pick the sigrok-cli entry point and how to run it: the Windows .exe
# (native on Windows, wine elsewhere) or the Linux tree's wrapper script
# (native only - it is not a .exe, so wine does not apply).
RUNNER=()
if [ -f "${STAGE}/sigrok-cli.exe" ]; then
    CLI="${STAGE}/sigrok-cli.exe"
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
elif [ -f "${STAGE}/sigrok-cli" ]; then
    CLI="${STAGE}/sigrok-cli"
else
    printf 'error: no sigrok-cli(.exe) in %s\n' "${STAGE}" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

run_cli() { ( cd "${STAGE}" && "${RUNNER[@]}" "./$(basename "${CLI}")" "$@" 2>&1 ); }

note "staged tree ${STAGE}"

"${PY}" "${GEN}" "${TMP}" || { printf 'error: capture generation failed\n' >&2; exit 1; }

# ---------------------------------------------------------------------------
# ARP: nrzi -> 4b5b -> ethernet -> arp
# ---------------------------------------------------------------------------
ARP_OUT="$(run_cli -i "${TMP}/arp_capture.bin" -I binary:numchannels=1:samplerate=1000000 \
    -P nrzi:preamble_len=4,4b5b,ethernet,arp)"

check_contains() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s' "${haystack}" | grep -qF "${needle}"; then
        pass "${label}"
    else
        fail "${label}: '${needle}' not found in decoder output"
    fi
}

check_contains "ethernet FCS validates"        "Frame Check Sequence: OK" "${ARP_OUT}"
check_contains "ethernet destination MAC"      "Destination MAC: FF:FF:FF:FF:FF:FF (Broadcast)" "${ARP_OUT}"
check_contains "ethernet EtherType is ARP"     "EtherType: Address Resolution Protocol (0x0806)" "${ARP_OUT}"
check_contains "arp operation"                 "Operation: Request" "${ARP_OUT}"
check_contains "arp source IP"                 "Source IP: 10.0.0.5" "${ARP_OUT}"
check_contains "arp destination IP"            "Destination IP: 10.0.0.2" "${ARP_OUT}"
check_contains "arp message"                   "Who has 10.0.0.2? Tell 10.0.0.5 (02:00:00:00:00:01)" "${ARP_OUT}"

# ---------------------------------------------------------------------------
# IPv4/UDP: nrzi -> 4b5b -> ethernet -> ipv4 -> udp
# ---------------------------------------------------------------------------
UDP_OUT="$(run_cli -i "${TMP}/ipv4_udp_capture.bin" -I binary:numchannels=1:samplerate=1000000 \
    -P nrzi:preamble_len=4,4b5b,ethernet,ipv4,udp:format=ascii)"

check_contains "ethernet FCS validates"        "Frame Check Sequence: OK" "${UDP_OUT}"
check_contains "ipv4 header checksum validates" "Header Checksum: OK" "${UDP_OUT}"
check_contains "ipv4 protocol is UDP"          "Protocol: User Datagram Protocol (UDP)" "${UDP_OUT}"
check_contains "ipv4 source address"           "Source IP Address: 10.0.0.5" "${UDP_OUT}"
check_contains "ipv4 destination address"      "Destination IP Address: 10.0.0.2" "${UDP_OUT}"
check_contains "udp source port"               "Source Port: 40000" "${UDP_OUT}"
check_contains "udp destination port"          "Destination Port: 5353" "${UDP_OUT}"
check_contains "udp checksum validates"        "Checksum: OK" "${UDP_OUT}"
for ch in B A T C H 1 O K; do
    check_contains "udp payload byte '${ch}'" "'${ch}'" "${UDP_OUT}"
done

printf '\n'
if [ "${FAILED}" -eq 0 ]; then
    note "networking stack decode smoke: pass"
    exit 0
fi
note "networking stack decode smoke: ${FAILED} failed"
exit 1

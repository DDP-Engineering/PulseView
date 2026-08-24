#!/usr/bin/env python3
# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Build synthetic NRZI/4B5B-encoded Ethernet captures for the batch-one
# networking-stack decode evidence (nrzi -> 4b5b -> ethernet -> arp | ipv4 ->
# udp, imported from ATK-Logic's Tier A decoder set).
#
# The demo driver's canned patterns cannot exercise this stack - it does not
# speak NRZI or 4B5B - and no 100BASE-FX/TX capture hardware is available, so
# this generates the capture instead. It builds a real Ethernet II frame
# (correct FCS, IPv4 header checksum, and UDP checksum, each computed with
# the exact algorithm the corresponding decoder uses to validate it) and
# encodes it down to a raw one-channel logic sample stream, using the exact
# inverse of decoders/nrzi/pd.py and decoders/4b5b/pd.py's own decode state
# machines. The result is decodable by the real, unmodified vendored
# decoders - not a canned answer key.
#
# Output: raw binary, 1 byte per sample, LSB = channel 0 level (0 or 1).
# Feed to sigrok-cli with: -I binary:numchannels=1:samplerate=<RATE>
#
# Usage: gen_networking_stack_captures.py <output-dir>
# Writes arp_capture.bin and ipv4_udp_capture.bin there.

import struct
import sys
import zlib

SYMBOL_LEN = 8            # samples per NRZI bit; must be even
PREAMBLE_LEN = 4           # nrzi decoder's preamble_len option (smallest allowed)
SAMPLERATE = 1_000_000

# 4B5B symbol tables, copied from decoders/4b5b/symbols.py.
SYM_DATA = {
    0b11110: 0x0, 0b01001: 0x1, 0b10100: 0x2, 0b10101: 0x3,
    0b01010: 0x4, 0b01011: 0x5, 0b01110: 0x6, 0b01111: 0x7,
    0b10010: 0x8, 0b10011: 0x9, 0b10110: 0xA, 0b10111: 0xB,
    0b11010: 0xC, 0b11011: 0xD, 0b11100: 0xE, 0b11101: 0xF,
}
SYM_DATA_ENC = {v: k for k, v in SYM_DATA.items()}
SYM_CTRL_ENC = {
    'H': 0b00100, 'I': 0b11111, 'J': 0b11000, 'K': 0b10001,
    'L': 0b00110, 'Q': 0b00000, 'R': 0b00111, 'S': 0b11001, 'T': 0b01101,
}


def bits_of(code5):
    return [int(c) for c in format(code5, '05b')]


def encode_byte_bits(byte_val):
    # 4b5b/pd.py builds a byte as (second_nibble << 4) | first_nibble, so
    # the low nibble is transmitted first.
    lo = byte_val & 0xF
    hi = (byte_val >> 4) & 0xF
    return bits_of(SYM_DATA_ENC[lo]) + bits_of(SYM_DATA_ENC[hi])


def encode_ctrl_bits(letter):
    return bits_of(SYM_CTRL_ENC[letter])


def build_logical_bits(frame_bytes, preamble_len=PREAMBLE_LEN):
    """frame_bytes: dst(6) + src(6) + ethertype(2) + payload, WITHOUT the FCS."""
    # nrzi/pd.py's SYNC state consumes exactly (2*preamble_len + 1) rising
    # edges before switching to DECODE; with a continuous run of "1" bits
    # (each toggling the line once, at its window's mid-point) that is
    # exactly (2*preamble_len + 1) whole bit windows, so DECODE's first
    # consumed bit is precisely the next one - the first bit of 'J' below.
    bits = [1] * (2 * preamble_len + 1)
    bits += encode_ctrl_bits('J')
    bits += encode_ctrl_bits('K')
    for b in [0x55] * 7 + [0xD5]:          # Ethernet preamble + SFD
        bits += encode_byte_bits(b)
    for b in frame_bytes:
        bits += encode_byte_bits(b)
    fcs = zlib.crc32(bytes(frame_bytes)) & 0xFFFFFFFF
    fcs_bytes = struct.pack('<I', fcs)
    check = zlib.crc32(bytes(frame_bytes) + fcs_bytes) & 0xFFFFFFFF
    assert check == 0x2144DF1C, \
        f'FCS self-check failed: crc32(frame+fcs)=0x{check:08X}, expected 0x2144DF1C'
    for b in fcs_bytes:
        bits += encode_byte_bits(b)
    bits += encode_ctrl_bits('T')
    # Trailing flush padding: libsigrokdecode drops a decoder's pending
    # self.wait() when the session ends mid-window, so without extra samples
    # after the last real bit, its window (and the 'T' symbol depending on
    # it) never completes. A few silent (no-edge) bits give every pending
    # wait() somewhere to time out before the capture ends.
    bits += [0] * 4
    return bits


def nrzi_4b5b_samples(bits, symbol_len=SYMBOL_LEN):
    """Inverse of nrzi/pd.py's DECODE state: bit 1 -> one transition, placed
    at the window's mid-point (matched[0]=True, edge_samp==symbol_len//2);
    bit 0 -> no transition for the whole window (matched[0]=False)."""
    assert symbol_len % 2 == 0
    half = symbol_len // 2
    rest = symbol_len - half
    level = 0
    samples = []
    for b in bits:
        if b:
            samples.extend([level] * half)
            level ^= 1
            samples.extend([level] * rest)
        else:
            samples.extend([level] * symbol_len)
    return samples


def ip_checksum(header20):
    """Standard Internet checksum (RFC 1071) over a 20-byte IPv4 header
    that already has its checksum field zeroed."""
    cs = 0
    for i in range(0, len(header20), 2):
        cs += (header20[i] << 8) | header20[i + 1]
    cs = (cs & 0xFFFF) + (cs >> 16)
    cs = (cs & 0xFFFF) + (cs >> 16)
    return (~cs) & 0xFFFF


def verify_ip_checksum(header20):
    """Mirrors decoders/ipv4/pd.py's own OK/FAILED check exactly."""
    cs = 0
    for i in range(0, 20, 2):
        cs += (header20[i] << 8) | header20[i + 1]
    cs = (cs + (cs >> 16)) & 0xFFFF
    return cs == 0xFFFF


def udp_checksum(src_ip, dst_ip, udp_seg):
    pseudo = bytearray()
    pseudo.extend(src_ip)
    pseudo.extend(dst_ip)
    pseudo.extend(b'\x00\x11')             # zero byte + UDP protocol number
    pseudo.extend(struct.pack('>H', len(udp_seg)))
    pseudo.extend(udp_seg)
    if len(pseudo) % 2:
        pseudo.append(0)
    cs = 0
    for i in range(0, len(pseudo), 2):
        cs += (pseudo[i] << 8) | pseudo[i + 1]
    cs = (cs & 0xFFFF) + (cs >> 16)
    cs = (cs & 0xFFFF) + (cs >> 16)
    return (~cs) & 0xFFFF


def verify_udp_checksum(src_ip, dst_ip, udp_seg):
    """Mirrors decoders/udp/pd.py's own OK/FAILED check exactly."""
    buffer = bytearray()
    buffer.extend(src_ip)
    buffer.extend(dst_ip)
    buffer.extend(b'\x00\x11')
    buffer.extend(struct.pack('>H', len(udp_seg)))
    buffer.extend(udp_seg)
    cs = 0
    for i in range(0, len(buffer), 2):
        cs += (buffer[i] << 8) | buffer[i + 1]
    cs = (cs + (cs >> 16)) & 0xFFFF
    return cs == 0xFFFF


def build_arp_frame():
    """Broadcast ARP request: 'Who has 10.0.0.2? Tell 10.0.0.5'."""
    dst = bytes.fromhex('FFFFFFFFFFFF')
    src = bytes.fromhex('020000000001')
    ethertype = struct.pack('>H', 0x0806)
    sha, spa = src, bytes([10, 0, 0, 5])
    tha, tpa = bytes(6), bytes([10, 0, 0, 2])
    arp_payload = struct.pack('>2H2BH6s4s6s4s', 1, 0x0800, 6, 4, 1, sha, spa, tha, tpa)
    assert len(arp_payload) == 28
    return dst + src + ethertype + arp_payload


def build_ipv4_udp_frame():
    """UDP datagram carrying b'BATCH1OK', 10.0.0.5:40000 -> 10.0.0.2:5353."""
    dst = bytes.fromhex('020000000002')
    src = bytes.fromhex('020000000001')
    ethertype = struct.pack('>H', 0x0800)

    src_ip, dst_ip = bytes([10, 0, 0, 5]), bytes([10, 0, 0, 2])
    udp_payload = b'BATCH1OK'
    src_port, dst_port = 40000, 5353
    udp_len = 8 + len(udp_payload)
    udp_cs = udp_checksum(src_ip, dst_ip,
                           struct.pack('>4H', src_port, dst_port, udp_len, 0) + udp_payload)
    udp_seg = struct.pack('>4H', src_port, dst_port, udp_len, udp_cs) + udp_payload

    total_length = 20 + len(udp_seg)
    ident, flags_frag, ttl, proto = 0x1234, 0x0000, 64, 17
    ip_no_cs = struct.pack('>BBHHHBBH4s4s', 0x45, 0x00, total_length, ident,
                            flags_frag, ttl, proto, 0, src_ip, dst_ip)
    ip_header = struct.pack('>BBHHHBBH4s4s', 0x45, 0x00, total_length, ident,
                             flags_frag, ttl, proto, ip_checksum(ip_no_cs), src_ip, dst_ip)
    assert verify_ip_checksum(ip_header), 'IPv4 header checksum self-check failed'
    assert verify_udp_checksum(src_ip, dst_ip, udp_seg), 'UDP checksum self-check failed'

    return dst + src + ethertype + ip_header + udp_seg, src_ip, dst_ip, udp_payload


def write_capture(path, frame_bytes):
    samples = nrzi_4b5b_samples(build_logical_bits(frame_bytes))
    with open(path, 'wb') as f:
        f.write(bytes(samples))
    return len(samples)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'

    arp_frame = build_arp_frame()
    n = write_capture(f'{outdir}/arp_capture.bin', arp_frame)
    print(f'arp_capture.bin: {len(arp_frame)} frame bytes, {n} samples')

    ip_frame, src_ip, dst_ip, payload = build_ipv4_udp_frame()
    n = write_capture(f'{outdir}/ipv4_udp_capture.bin', ip_frame)
    print(f'ipv4_udp_capture.bin: {len(ip_frame)} frame bytes, {n} samples, '
          f'payload={payload!r}, src={".".join(map(str, src_ip))}, '
          f'dst={".".join(map(str, dst_ip))}')


if __name__ == '__main__':
    main()

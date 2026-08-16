# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Find which analog-front-end relay bit lets a signal reach the ADC.

sub_10002320 in HTHardDLL.dll reads the current 16-bit relay word with 0x15,
then clocks the difference out one bit at a time with 0x12, addressing bit n
as (1 << (n + 3)) to set and its complement to clear, with a 20 ms settle
between writes. That gives a single-bit primitive, which is what this probes.

Relay switching is the instrument's ordinary operation and holds no persistent
state - the word is re-read at the start and restored at the end. Nothing here
touches calibration, flash or EEPROM.

Expects CH1 on the probe-compensation output (1 kHz square wave).
"""

from __future__ import annotations

import argparse
import sys
import time

import libusb_package
import usb.core
import usb.util

from read_capture import (
    CMD_FORCE_TRIGGER, CMD_GET_DATA, CMD_START_COLLECT, CMD_START_TRIGGER,
    PRODUCT_ID, RING_SIZE, VENDOR_ID, drain, get_address, get_state, read,
    send, set_dac, set_read_len, set_read_start, set_sample_rate,
)

RELAY_SETTLE = 0.02  # the DLL's Sleep(0x14) between bit writes


def read_relays(dev) -> int | None:
    """0x15 - returns the current 16-bit relay word."""
    send(dev, bytes([0x15, 0x00]))
    r = read(dev)
    if r is None or len(r) < 2:
        return None
    return r[0] | (r[1] << 8)


def write_relay_bit(dev, bit: int, on: bool, target: int) -> None:
    """0x12 - set or clear one relay bit."""
    v = (1 << (bit + 3)) if on else ~(1 << (bit + 3))
    v &= 0xFFFFFFFF
    send(dev, bytes([0x12, 0x00,
                     v & 0xFF, (v >> 8) & 0xFF,
                     v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF,
                     0x00, target & 0xFF, (target >> 8) & 0xFF]))
    time.sleep(RELAY_SETTLE)


def capture(dev, samples: int) -> bytes:
    send(dev, bytes([CMD_START_COLLECT, 0x00]))
    time.sleep(0.25)
    send(dev, bytes([CMD_START_TRIGGER, 0x00]))
    time.sleep(0.25)
    send(dev, bytes([CMD_FORCE_TRIGGER, 0x00]))
    time.sleep(0.25)

    deadline = time.time() + 2.0
    while time.time() < deadline:
        if get_state(dev) in (2, 3, 7):
            break
        time.sleep(0.02)
    else:
        return b""

    end = get_address(dev)
    if end is None:
        return b""
    start = (end - samples // 2) % RING_SIZE
    rem = start & 0x1FF
    words = 2 * samples + 0x800
    set_read_start(dev, start - rem)
    set_read_len(dev, words)
    send(dev, bytes([CMD_GET_DATA, 0x00]))
    data = drain(dev, words + 0x800)
    return data[(rem + 0x200) * 4:]


def span(data: bytes, ch: int) -> tuple[int, int, int]:
    s = data[ch::4]
    if not s:
        return 0, 0, 0
    return min(s), max(s), max(s) - min(s)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=2048)
    ap.add_argument("--ticks", type=int, default=999)
    ap.add_argument("--dac", type=int, default=512)
    args = ap.parse_args()

    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1
    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)

    try:
        original = read_relays(dev)
        print(f"0x15 relay word on entry: 0x{original:04x} "
              f"({original:016b})\n" if original is not None else "0x15 read failed\n")

        set_sample_rate(dev, args.ticks)
        set_dac(dev, 0, args.dac)
        time.sleep(0.05)

        base = capture(dev, args.samples)
        lo, hi, sp = span(base, 0)
        print(f"baseline           CH1 {lo:3d}..{hi:3d} span {sp:3d}")

        best = []
        for bit in range(16):
            for state in (True, False):
                write_relay_bit(dev, bit, state, original or 0)
                data = capture(dev, args.samples)
                lo, hi, sp = span(data, 0)
                flag = "  <-- SIGNAL" if sp > 20 else ""
                print(f"bit {bit:2d} -> {int(state)}    CH1 {lo:3d}..{hi:3d} "
                      f"span {sp:3d}{flag}")
                if sp > 20:
                    best.append((bit, state, sp))
                # put the bit back the way it was
                write_relay_bit(dev, bit, not state, original or 0)

        if best:
            print("\nbits that admit signal:")
            for bit, state, sp in best:
                print(f"  bit {bit} = {int(state)}  span {sp}")
        else:
            print("\nno single bit opened the input path")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

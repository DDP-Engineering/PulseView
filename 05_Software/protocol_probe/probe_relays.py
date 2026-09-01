# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE-PolyForm.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Map the DSO3062L analog-front-end relay bits to their functions.

sub_10002320 in HTHardDLL.dll reads the current 16-bit relay word with 0x15,
then clocks the difference out one bit at a time with 0x12, addressing bit n
as (1 << (n + 3)) to set and its complement to clear, with a 20 ms settle
between writes. That single-bit primitive is what this sweeps.

Each bit is set from a known-cleared baseline, a capture is taken, and the
effect is measured against the 1 kHz probe-compensation reference:

    span  - peak-to-peak in ADC counts, so attenuator and volts/div
    mean  - DC level, so coupling
    CH2   - whether the second channel comes alive, so channel enable

Relay switching is the instrument's ordinary operation and holds no persistent
state. Nothing here touches calibration, flash or EEPROM.

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
    send, set_dac, set_htrigger_length, set_read_len, set_read_start,
    set_sample_rate,
)

RELAY_SETTLE = 0.02  # the DLL's Sleep(0x14) between bit writes


def read_relays(dev) -> int | None:
    """0x15 - returns the current 16-bit relay word."""
    send(dev, bytes([0x15, 0x00]))
    r = read(dev)
    if r is None or len(r) < 2:
        return None
    return r[0] | (r[1] << 8)


def write_relay_bit(dev, bit: int, on: bool, target: int = 0) -> None:
    """0x12 - set or clear one relay bit."""
    v = ((1 << (bit + 3)) if on else ~(1 << (bit + 3))) & 0xFFFFFFFF
    send(dev, bytes([0x12, 0x00,
                     v & 0xFF, (v >> 8) & 0xFF,
                     v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF,
                     0x00, target & 0xFF, (target >> 8) & 0xFF]))
    time.sleep(RELAY_SETTLE)


def capture(dev, samples: int, timeout: float = 8.0) -> bytes:
    send(dev, bytes([CMD_START_COLLECT, 0x00]))
    time.sleep(0.25)
    send(dev, bytes([CMD_START_TRIGGER, 0x00]))
    time.sleep(0.25)
    send(dev, bytes([CMD_FORCE_TRIGGER, 0x00]))
    time.sleep(0.25)

    deadline = time.time() + timeout
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
    return drain(dev, words + 0x800)[(rem + 0x200) * 4:]


def measure(data: bytes, slot: int) -> tuple[int, float, int]:
    """Return (span, mean, edge count) for one interleaved ADC slot."""
    s = data[slot::4]
    if not s:
        return 0, 0.0, 0
    lo, hi = min(s), max(s)
    span = hi - lo
    edges = 0
    if span >= 8:
        loT, hiT = lo + 0.3 * span, lo + 0.7 * span
        state = s[0] > hiT
        for v in s:
            if state and v < loT:
                state = False
                edges += 1
            elif not state and v > hiT:
                state = True
                edges += 1
    return span, sum(s) / len(s), edges


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=20000)
    ap.add_argument("--ticks", type=int, default=999)
    ap.add_argument("--buflen", type=int, default=10240)
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
        entry = read_relays(dev)
        print(f"0x15 relay word on entry: 0x{entry:04x}\n"
              if entry is not None else "0x15 read failed\n")

        set_sample_rate(dev, args.ticks, 3)
        set_htrigger_length(dev, args.buflen, 50)
        for _ch in (1, 2, 3, 4):
            set_dac(dev, args.dac, _ch)
        time.sleep(0.05)

        # Known baseline: every bit cleared.
        for bit in range(16):
            write_relay_bit(dev, bit, False)

        base = capture(dev, args.samples)
        b1, m1, e1 = measure(base, 0)
        b2, m2, e2 = measure(base, 2)
        print(f"{'':>10}  {'CH1 span':>8} {'CH1 mean':>8} {'edges':>5}   "
              f"{'CH2 span':>8} {'CH2 mean':>8}")
        print(f"{'baseline':>10}  {b1:8d} {m1:8.1f} {e1:5d}   {b2:8d} {m2:8.1f}")

        for bit in range(16):
            # Clear every bit, not just the previous one. Relay state carries
            # across writes, so a partial reset contaminates the next reading -
            # that mistake produced a table where almost every bit looked
            # identical. With a full reset the per-bit result is repeatable.
            for other in range(16):
                write_relay_bit(dev, other, False)
            write_relay_bit(dev, bit, True)
            data = capture(dev, args.samples)
            s1, mm1, ee1 = measure(data, 0)
            s2, mm2, _ = measure(data, 2)
            notes = []
            if abs(s1 - b1) > 3:
                notes.append(f"CH1 span {b1}->{s1}")
            if abs(mm1 - m1) > 3:
                notes.append(f"CH1 dc {m1:.0f}->{mm1:.0f}")
            if s2 - b2 > 3:
                notes.append(f"CH2 alive {b2}->{s2}")
            print(f"{'bit ' + str(bit):>10}  {s1:8d} {mm1:8.1f} {ee1:5d}   "
                  f"{s2:8d} {mm2:8.1f}   {'; '.join(notes)}")

        # Leave the instrument as it was found.
        if entry:
            for bit in range(16):
                if entry & (1 << bit):
                    write_relay_bit(dev, bit, True, entry)
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Tell a bandwidth-limit relay apart from an attenuator by edge rise time.

Comparing relay bits at 1 kHz cannot distinguish the two: a 20 MHz limit is
invisible there, so two bits can look identical while doing entirely
different things. Bandwidth shows up in how fast an edge moves, not in its
amplitude.

A 20 MHz limit gives roughly 0.35/20MHz = 17.5 ns of 10-90 rise time; the
instrument's full 60 MHz gives about 5.8 ns. Sampled with both ADC cores
interleaved at 200 MS/s - 5 ns per sample - that is about 3.5 samples against
1.2, which is resolvable.

Mode 0 in the 0x0e command makes the divider be ignored and the instrument
stay at full rate, which is what this needs.

The generator's own edges set the floor. If they are slower than about 20 ns
both bits will measure the same and the result is inconclusive, not negative.

Acquisition control only. Nothing here writes calibration, flash or EEPROM.
"""

from __future__ import annotations

import argparse
import sys

import libusb_package
import usb.core
import usb.util

from read_capture import (
    PRODUCT_ID, VENDOR_ID, set_dac, set_htrigger_length, set_sample_rate,
)
from probe_relays import capture, write_relay_bit

SAMPLE_NS = 5.0  # both cores interleaved at full rate


def interleave(data: bytes) -> list[int]:
    """Slots 0 and 1 are CH1's two cores, so they alternate in time."""
    out = []
    for i in range(0, len(data) - 3, 4):
        out.append(data[i])
        out.append(data[i + 1])
    return out


def rise_times(v: list[int]) -> list[float]:
    """10-90 widths of every clean rising edge, in samples."""
    lo, hi = min(v), max(v)
    if hi - lo < 20:
        return []
    p10, p90 = lo + 0.1 * (hi - lo), lo + 0.9 * (hi - lo)
    out = []
    i = 1
    while i < len(v):
        # Find an upward crossing of the 10 percent level.
        if not (v[i - 1] <= p10 < v[i]):
            i += 1
            continue
        start = i - 1
        j = i
        # Walk to the 90 percent level, abandoning anything that dips back
        # below 10 percent - that is noise around the threshold, not an edge.
        while j < len(v) and v[j] < p90:
            if v[j] <= p10 and j > i:
                break
            j += 1
        if j < len(v) and v[j] >= p90:
            out.append(j - start)
        i = j + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=8000)
    ap.add_argument("--dac", type=int, default=512)
    ap.add_argument("--bits", type=str, default="11,12")
    args = ap.parse_args()

    bits = [int(b) for b in args.bits.split(",")]

    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID,
                        backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1
    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)

    try:
        # Mode 0: divider ignored, full rate.
        set_sample_rate(dev, 0, 0)
        set_htrigger_length(dev, 10240, 50)
        for c in (1, 2, 3, 4):
            set_dac(dev, args.dac, c)

        print(f"\nfull rate, {SAMPLE_NS:g} ns per sample")
        print(f"{'bit':>4} {'span':>5} {'edges':>6} {'median rise':>12} "
              f"{'ns':>7}")

        for bit in bits:
            for b in range(16):
                write_relay_bit(dev, b, False)
            write_relay_bit(dev, bit, True)
            data = capture(dev, args.samples)
            if not data:
                print(f"{bit:>4}  capture failed")
                continue
            v = interleave(data)
            r = sorted(rise_times(v))
            span = max(v) - min(v)
            if not r:
                print(f"{bit:>4} {span:>5} {0:>6}   no clean edges")
                continue
            med = r[len(r) // 2]
            print(f"{bit:>4} {span:>5} {len(r):>6} {med:>12} "
                  f"{med * SAMPLE_NS:>7.1f}")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

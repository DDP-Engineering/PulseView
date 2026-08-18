# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Measure the analog gain ladder against a known input amplitude.

The instrument's own 2 Vpp compensation output saturates every gain setting
except relay bits 11 and 12, so four of the five ladder steps have never been
measured - their spans are truncated by clipping rather than real. Given an
external generator with a settable amplitude, each step can be measured at a
level that fits inside the converter, which is what a genuine volts/div
control needs.

Each bit is applied from a fully cleared relay state, because relay state
persists and clearing only the previous bit contaminates the next reading.

Pass --amplitude with the generator's peak-to-peak setting to get volts per
count; without it the spans are still comparable to each other.

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

GAIN_BITS = (3, 4, 10, 11, 12)


def clear_relays(dev) -> None:
    for bit in range(16):
        write_relay_bit(dev, bit, False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=4000)
    ap.add_argument("--ticks", type=int, default=999)
    ap.add_argument("--dac", type=int, default=512)
    ap.add_argument("--amplitude", type=float,
                    help="generator output in volts peak-to-peak")
    ap.add_argument("--bits", type=str,
                    help="comma-separated relay bits, default 3,4,10,11,12")
    args = ap.parse_args()

    bits = ([int(b) for b in args.bits.split(",")] if args.bits
            else list(GAIN_BITS))

    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID,
                        backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1
    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)

    try:
        set_sample_rate(dev, args.ticks, 3)
        set_htrigger_length(dev, 10240, 50)
        for c in (1, 2, 3, 4):
            set_dac(dev, args.dac, c)

        head = f"{'bit':>4} {'min':>5} {'max':>5} {'span':>5} {'mid':>6}"
        if args.amplitude:
            head += f" {'mV/count':>9} {'full scale':>11}"
        print(f"\ninput {args.amplitude} Vpp\n" if args.amplitude else "")
        print(head)

        for bit in bits:
            clear_relays(dev)
            write_relay_bit(dev, bit, True)
            data = capture(dev, args.samples)
            if not data:
                print(f"{bit:>4}  capture failed")
                continue
            s = data[0::4]
            lo, hi = min(s), max(s)
            span = hi - lo
            row = f"{bit:>4} {lo:>5} {hi:>5} {span:>5} {(lo + hi) / 2:>6.1f}"
            if args.amplitude and span > 2:
                mv = args.amplitude * 1000.0 / span
                row += f" {mv:>9.2f} {mv * 256 / 1000:>10.2f}V"
            if lo == 0 or hi == 255:
                row += "   CLIPS"
            print(row)
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

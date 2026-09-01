# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE-PolyForm.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Read the DSO3062L's 16 logic-analyzer channels.

Bytes 2 and 3 of every four-byte group in the dsoHTGetData stream are the
logic channels - D0..D7 and D8..D15 - not a second analog channel. Proven
three ways:

  - they never respond to any of the four 0x16 offset DACs
  - they never respond to any of the 16 relay bits, even with CH2 driven
  - they flip together exactly as the 0x41 comparator threshold crosses 0 V,
    which is where 16 unconnected inputs sitting at ground would switch

0x41 carries two threshold DACs. They do not split by byte: one drives the
even-numbered logic channels and the other the odd, across both bytes. With
bank A high and bank B low every byte reads 0b01010101, and swapping them
gives 0b10101010.

Threshold DAC and volts are related by the constants at 0x100080d0/d8/e0:

    dac = 121.848 - 10.8696 * volts

Nothing here writes persistent state. laWriteEEROM, which does, is never
issued - only the volatile 0x41 threshold.
"""

from __future__ import annotations

import argparse
import sys
import time

import libusb_package
import usb.core
import usb.util

from read_capture import (
    PRODUCT_ID, VENDOR_ID, send, set_dac, set_htrigger_length, set_sample_rate,
)
from probe_relays import capture

LA_ZERO_DAC = 121.848
LA_VOLTS_PER_DAC = 10.8696


def volts_to_dac(volts: float) -> int:
    return max(0, min(255, round(LA_ZERO_DAC - LA_VOLTS_PER_DAC * volts)))


def dac_to_volts(dac: int) -> float:
    return (LA_ZERO_DAC - dac) / LA_VOLTS_PER_DAC


def set_logic_threshold(dev, volts: float, volts_odd: float | None = None) -> None:
    """0x41 - two comparator threshold DACs, even and odd logic channels."""
    a = volts_to_dac(volts)
    b = volts_to_dac(volts if volts_odd is None else volts_odd)
    send(dev, bytes([0x41, 0x00, a, b]))
    time.sleep(0.08)


def logic_channels(data: bytes) -> list[list[int]]:
    """Split the stream into 16 per-channel bit sequences, D0 first."""
    low, high = data[2::4], data[3::4]
    out = []
    for bit in range(8):
        out.append([(b >> bit) & 1 for b in low])
    for bit in range(8):
        out.append([(b >> bit) & 1 for b in high])
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=6000)
    ap.add_argument("--ticks", type=int, default=999)
    ap.add_argument("--threshold", type=float, default=1.4,
                    help="logic threshold in volts (default TTL-ish 1.4)")
    ap.add_argument("--sweep", action="store_true",
                    help="sweep the threshold instead of a single capture")
    args = ap.parse_args()

    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1
    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)

    try:
        set_sample_rate(dev, args.ticks, 3)
        set_htrigger_length(dev, 10240, 50)
        for ch in (1, 2, 3, 4):
            set_dac(dev, 512, ch)

        if args.sweep:
            print(f"{'dac':>4} {'volts':>7}  D0..D7    D8..D15")
            for dac in range(0, 256, 8):
                send(dev, bytes([0x41, 0x00, dac, dac]))
                time.sleep(0.08)
                data = capture(dev, args.samples)
                if not data:
                    continue
                lo = sorted(set(data[2::4]))
                hi = sorted(set(data[3::4]))
                print(f"{dac:4d} {dac_to_volts(dac):+7.2f}  {lo}  {hi}")
            return 0

        set_logic_threshold(dev, args.threshold)
        rate = 200e6 / (args.ticks + 1)
        print(f"threshold {args.threshold:+.2f} V, {rate / 1e3:g} kS/s per channel\n")
        data = capture(dev, args.samples)
        if not data:
            print("capture failed", file=sys.stderr)
            return 1

        chans = logic_channels(data)
        n = len(chans[0])
        print(f"{n} samples per logic channel\n")
        for i, bits in enumerate(chans):
            ones = sum(bits)
            edges = sum(1 for a, b in zip(bits, bits[1:]) if a != b)
            state = "high" if ones == n else "low" if ones == 0 else "toggling"
            bar = "".join("#" if b else "_" for b in bits[:60])
            print(f"  D{i:<2} {state:>8}  {edges:5d} edges  {bar}")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

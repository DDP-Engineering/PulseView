# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE-PolyForm.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Find out which 0x16 channel selector actually drives which stream slot.

Byte 5's high nibble is documented as choosing the DAC: 0x10, 0x50, 0x90 and
0xd0 for channels 1 to 4. That has never been tested one channel at a time.
It matters because every CH2 experiment depends on being able to move the two
analog channels independently - if all four selectors land on the same DAC,
the last write wins and no such experiment means anything.

Each selector is driven to a distinct offset in turn while the others are left
centred, and both analog slots are measured. A selector that moves a slot owns
it; one that moves nothing is either unused or aliased.

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
from probe_relays import capture

CENTRE = 512

# The second 0x12 form. Bytes 2 and 3 zero distinguish it from the bit-serial
# relay write; bytes 4-6 carry the 24-bit channel-enable word.
ENABLE_CH1 = 0x00C000
ENABLE_CH1_CH2 = 0x27C000


def set_enable_word(dev, word: int, settings: int = 0) -> None:
    from read_capture import send
    send(dev, bytes([0x12, 0x00, 0x00, 0x00,
                     word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF,
                     0x00, settings & 0xFF, (settings >> 8) & 0xFF]))


def stats(data: bytes, slot: int) -> tuple[int, int]:
    s = data[slot::4]
    return (min(s), max(s)) if s else (0, 0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=2000)
    ap.add_argument("--ticks", type=int, default=999)
    ap.add_argument("--value", type=int, default=300,
                    help="offset applied to the channel under test")
    ap.add_argument("--dual", action="store_true",
                    help="write the CH1+CH2 enable word before testing")
    args = ap.parse_args()

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
        word = ENABLE_CH1_CH2 if args.dual else ENABLE_CH1
        set_enable_word(dev, word)
        print(f"enable word 0x{word:06X}")

        print(f"all DACs {CENTRE}, then one at a time to {args.value}\n")
        print(f"{'under test':>10}  {'slot0 min..max':>16}  {'slot1 min..max':>16}")

        for ch in (0, 1, 2, 3, 4):
            for c in (1, 2, 3, 4):
                set_dac(dev, args.value if c == ch else CENTRE, c)
            data = capture(dev, args.samples)
            if not data:
                print(f"{ch or 'none':>10}  capture failed")
                continue
            a = stats(data, 0)
            b = stats(data, 1)
            label = "none" if ch == 0 else f"ch{ch}"
            print(f"{label:>10}  {a[0]:>7}..{a[1]:<7}  {b[0]:>7}..{b[1]:<7}")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

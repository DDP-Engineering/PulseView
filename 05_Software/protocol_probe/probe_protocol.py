# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE-PolyForm.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Test whether the DSO3062L answers libsigrok's hantek-dso protocol.

Status queries only. Nothing here arms a capture, writes calibration,
changes relays, or alters any persistent device setting. The escalation is
deliberate: the cheapest, least invasive request runs first, and each later
step only runs if the previous one succeeded.

  1. CTRL_GETSPEED       vendor control IN, reads the device speed byte
  2. CTRL_BEGINCOMMAND   vendor control OUT, the fixed 10-byte handshake
  3. CMD_GET_CAPTURESTATE  2-byte bulk command, then a 512-byte bulk read

A recognised capture-state byte in step 3 is strong evidence that the
DSO3062L speaks the same wire protocol as the DSO-2090 family.

Command values are taken from libsigrok src/hardware/hantek-dso at commit
0bc2487778e660f4d3116729b6f4aee2b1996bb0.
"""

from __future__ import annotations

import sys

import libusb_package
import usb.core
import usb.util

VENDOR_ID = 0x04B5
PRODUCT_ID = 0x3062

USB_CONFIGURATION = 1
USB_INTERFACE = 0
DSO_EP_OUT = 0x02
DSO_EP_IN = 0x86

CTRL_GETSPEED = 0xB2
CTRL_BEGINCOMMAND = 0xB3

CMD_GET_CAPTURESTATE = 0x06

BEGIN_PAYLOAD = bytes([0x0F, 0x03, 0x03, 0x03, 0x68, 0xAC, 0xFE, 0x00, 0x01, 0x00])

CAPTURE_STATES = {
    0: "CAPTURE_EMPTY",
    1: "CAPTURE_FILLING",
    2: "CAPTURE_READY_8BIT",
    3: "CAPTURE_READY_2250",
    7: "CAPTURE_READY_9BIT",
    127: "CAPTURE_TIMEOUT",
    255: "CAPTURE_UNKNOWN",
}

VENDOR_IN = usb.util.CTRL_IN | usb.util.CTRL_TYPE_VENDOR | usb.util.CTRL_RECIPIENT_DEVICE
VENDOR_OUT = usb.util.CTRL_OUT | usb.util.CTRL_TYPE_VENDOR | usb.util.CTRL_RECIPIENT_DEVICE


def step(number: int, title: str) -> None:
    print(f"\n[{number}] {title}")


def main() -> int:
    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("Device 04b5:3062 not found. Is WinUSB still bound?", file=sys.stderr)
        return 1

    print(f"Found {dev.product} ({VENDOR_ID:04x}:{PRODUCT_ID:04x})")

    dev.set_configuration(USB_CONFIGURATION)
    usb.util.claim_interface(dev, USB_INTERFACE)
    print(f"Claimed configuration {USB_CONFIGURATION}, interface {USB_INTERFACE}")

    try:
        step(1, "CTRL_GETSPEED (0xb2) - vendor control IN")
        try:
            speed = dev.ctrl_transfer(VENDOR_IN, CTRL_GETSPEED, 0, 0, 1, 200)
            print(f"    OK  -> {bytes(speed).hex()}  (0=full speed, 1=high speed)")
        except usb.core.USBError as exc:
            print(f"    FAILED: {exc}")
            print("    Device did not answer a hantek-dso vendor request.")
            return 3

        step(2, "CTRL_BEGINCOMMAND (0xb3) - vendor control OUT, 10-byte handshake")
        try:
            written = dev.ctrl_transfer(
                VENDOR_OUT, CTRL_BEGINCOMMAND, 0, 0, BEGIN_PAYLOAD, 200
            )
            print(f"    OK  -> accepted {written} of {len(BEGIN_PAYLOAD)} bytes")
        except usb.core.USBError as exc:
            print(f"    FAILED: {exc}")
            return 4

        step(3, f"CMD_GET_CAPTURESTATE (0x06) - bulk OUT 0x{DSO_EP_OUT:02x}")
        try:
            dev.write(DSO_EP_OUT, bytes([CMD_GET_CAPTURESTATE, 0x00]), 200)
            print("    OK  -> 2-byte command accepted")
        except usb.core.USBError as exc:
            print(f"    FAILED: {exc}")
            return 5

        step(4, f"read reply - bulk IN 0x{DSO_EP_IN:02x}, up to 512 bytes")
        try:
            reply = dev.read(DSO_EP_IN, 512, 300)
        except usb.core.USBError as exc:
            print(f"    FAILED: {exc}")
            return 6

        data = bytes(reply)
        print(f"    OK  -> {len(data)} bytes")
        print(f"    first 16 bytes: {data[:16].hex(' ')}")

        state = data[0]
        name = CAPTURE_STATES.get(state)
        if name:
            print(f"\n    capture state byte = {state} -> {name}")
            print("    RECOGNISED hantek-dso capture state.")
        else:
            print(f"\n    capture state byte = {state} -> not a known hantek-dso state")

        toff = (data[1] << 16) | (data[3] << 8) | data[2]
        print(f"    raw trigger offset field = 0x{toff:06x}")
        return 0

    finally:
        usb.util.release_interface(dev, USB_INTERFACE)
        usb.util.dispose_resources(dev)


if __name__ == "__main__":
    raise SystemExit(main())

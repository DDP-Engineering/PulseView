# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Validate the statically recovered DSO3062L opcodes against the device.

READ-ONLY BY CONSTRUCTION. Only opcodes on the allowlist below are ever sent,
and every one of them is a query recovered from HTHardDLL.dll. Opcodes that
write persistent state - dsoHTWriteCalibrationData, dsoWriteFlash,
laWriteEEROM - are deliberately absent and must never be added here. Nothing
in this script arms a capture or changes an instrument setting.

Each opcode is sent as the SDK builds it: a two-byte request, preceded by the
CTRL_BEGINCOMMAND handshake, with the reply read from the bulk IN endpoint.
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
EP_OUT = 0x02
EP_IN = 0x86

CTRL_BEGINCOMMAND = 0xB3
BEGIN_PAYLOAD = bytes([0x0F, 0x03, 0x03, 0x03, 0x68, 0xAC, 0xFE, 0x00, 0x01, 0x00])

VENDOR_OUT = usb.util.CTRL_OUT | usb.util.CTRL_TYPE_VENDOR | usb.util.CTRL_RECIPIENT_DEVICE

# (opcode, SDK export, what a plausible answer looks like)
READ_ONLY_OPCODES = [
    (0x06, "dsoHTGetState", "status byte; bits 0-2 = capture state, bit 3 = pack"),
    (0x09, "dsoGetHardVersion", "hardware version word"),
    (0x2B, "dsoGetFPGAVersion", "FPGA version word"),
    (0x0A, "dsoHTGetHardFC", "hardware frequency counter"),
]

CAPTURE_STATES = {
    0: "CAPTURE_EMPTY",
    1: "CAPTURE_FILLING",
    2: "CAPTURE_READY_8BIT",
    3: "CAPTURE_READY_2250",
    7: "CAPTURE_READY_9BIT",
}


def begin(dev: usb.core.Device) -> None:
    dev.ctrl_transfer(VENDOR_OUT, CTRL_BEGINCOMMAND, 0, 0, BEGIN_PAYLOAD, 200)


def query(dev: usb.core.Device, opcode: int) -> bytes | None:
    begin(dev)
    dev.write(EP_OUT, bytes([opcode, 0x00]), 200)
    try:
        return bytes(dev.read(EP_IN, 512, 300))
    except usb.core.USBError as exc:
        print(f"      read failed: {exc}")
        return None


def main() -> int:
    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1

    dev.set_configuration(USB_CONFIGURATION)
    usb.util.claim_interface(dev, USB_INTERFACE)
    print(f"{dev.product} @ {VENDOR_ID:04x}:{PRODUCT_ID:04x}\n")

    try:
        for opcode, name, expectation in READ_ONLY_OPCODES:
            print(f"opcode 0x{opcode:02x}  {name}")
            print(f"    expect: {expectation}")
            reply = query(dev, opcode)
            if reply is None:
                print()
                continue
            print(f"    got {len(reply)} bytes: {reply[:16].hex(' ')}")
            words = [
                int.from_bytes(reply[i : i + 2], "little") for i in range(0, 16, 2)
            ]
            print(f"    as LE words: {words}")
            if opcode == 0x06:
                state = reply[0] & 0x07
                pack = (reply[0] >> 3) & 1
                label = CAPTURE_STATES.get(state, f"unknown({state})")
                print(f"    masked: state={state} ({label})  pack={pack}")
            print()
    finally:
        usb.util.release_interface(dev, USB_INTERFACE)
        usb.util.dispose_resources(dev)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

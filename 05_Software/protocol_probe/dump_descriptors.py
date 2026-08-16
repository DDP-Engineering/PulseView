# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Dump the USB descriptor tree of the Hantek DSO3062L.

Read-only. Opens no data endpoints, sends no vendor commands, and changes
no device state. It answers one question: what does 04b5:3062 actually
present on the wire, and how does that compare with the endpoint layout
libsigrok's existing hantek-dso driver expects.

Requires WinUSB (or libusbK) bound to the device on Windows.
"""

from __future__ import annotations

import sys

import libusb_package
import usb.core
import usb.util

VENDOR_ID = 0x04B5
PRODUCT_ID = 0x3062

TRANSFER_TYPES = {0: "control", 1: "isochronous", 2: "bulk", 3: "interrupt"}


def describe_class(code: int) -> str:
    known = {
        0x00: "per-interface",
        0x03: "HID",
        0x08: "mass storage",
        0xFE: "application specific (USBTMC lives here)",
        0xFF: "vendor specific",
    }
    return known.get(code, "unassigned/other")


def string_or_none(dev: usb.core.Device, index: int) -> str:
    if not index:
        return "(none)"
    try:
        return usb.util.get_string(dev, index) or "(empty)"
    except Exception as exc:  # noqa: BLE001 - diagnostic tool, report anything
        return f"(unreadable: {exc.__class__.__name__})"


def dump(dev: usb.core.Device) -> None:
    print("=" * 68)
    print("DEVICE DESCRIPTOR")
    print("=" * 68)
    print(f"  idVendor           0x{dev.idVendor:04x}")
    print(f"  idProduct          0x{dev.idProduct:04x}")
    print(f"  bcdDevice          0x{dev.bcdDevice:04x}")
    print(f"  bcdUSB             0x{dev.bcdUSB:04x}")
    print(f"  bDeviceClass       0x{dev.bDeviceClass:02x}  ({describe_class(dev.bDeviceClass)})")
    print(f"  bDeviceSubClass    0x{dev.bDeviceSubClass:02x}")
    print(f"  bDeviceProtocol    0x{dev.bDeviceProtocol:02x}")
    print(f"  bMaxPacketSize0    {dev.bMaxPacketSize0}")
    print(f"  bNumConfigurations {dev.bNumConfigurations}")
    print(f"  manufacturer       {string_or_none(dev, dev.iManufacturer)}")
    print(f"  product            {string_or_none(dev, dev.iProduct)}")
    print(f"  serial             {string_or_none(dev, dev.iSerialNumber)}")

    for cfg in dev:
        print()
        print("=" * 68)
        print(f"CONFIGURATION {cfg.bConfigurationValue}")
        print("=" * 68)
        print(f"  bNumInterfaces     {cfg.bNumInterfaces}")
        print(f"  bmAttributes       0x{cfg.bmAttributes:02x}")
        print(f"  max power          {cfg.bMaxPower * 2} mA")

        for intf in cfg:
            print()
            print(f"  -- interface {intf.bInterfaceNumber} alt {intf.bAlternateSetting}")
            print(
                f"     class 0x{intf.bInterfaceClass:02x} "
                f"({describe_class(intf.bInterfaceClass)}) "
                f"subclass 0x{intf.bInterfaceSubClass:02x} "
                f"protocol 0x{intf.bInterfaceProtocol:02x}"
            )
            print(f"     endpoints: {intf.bNumEndpoints}")

            for ep in intf:
                direction = "IN " if usb.util.endpoint_direction(ep.bEndpointAddress) else "OUT"
                ttype = TRANSFER_TYPES.get(
                    usb.util.endpoint_type(ep.bmAttributes), "unknown"
                )
                print(
                    f"       EP 0x{ep.bEndpointAddress:02x}  {direction}  "
                    f"{ttype:<11} maxpacket={ep.wMaxPacketSize:<5} "
                    f"interval={ep.bInterval}"
                )


def main() -> int:
    backend = libusb_package.get_libusb1_backend()
    if backend is None:
        print("ERROR: no libusb backend available.", file=sys.stderr)
        return 2

    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print(
            f"Device {VENDOR_ID:04x}:{PRODUCT_ID:04x} not found by libusb.\n"
            "\n"
            "If Windows Device Manager shows the DSO-3062L, the device is on the\n"
            "bus but has no libusb-compatible driver bound. Bind WinUSB to it\n"
            "with Zadig, then re-run.",
            file=sys.stderr,
        )
        return 1

    try:
        dump(dev)
    except usb.core.USBError as exc:
        print(f"ERROR: USB access failed: {exc}", file=sys.stderr)
        print("This usually means the bound driver is not WinUSB/libusbK.", file=sys.stderr)
        return 3
    finally:
        usb.util.dispose_resources(dev)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

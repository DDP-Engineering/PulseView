# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Attempt a capture cycle on the DSO3062L using its current front-panel setup.

Deliberately configures nothing. The instrument already holds a valid timebase,
volts/div and trigger from its front panel, so this only drives the acquisition
state machine and reads the result. That keeps the test to opcodes whose effect
is volatile:

    0x03 StartCollectData -> 0x04 StartTrigger -> poll 0x06 -> 0x05 GetData

No opcode here writes calibration, flash or EEPROM. Worst case the acquisition
state is disturbed, which the front-panel Run/Stop key resets.

If the capture state ever advances past CAPTURE_EMPTY and 0x05 returns a large
payload, gate G2 steps 4 and 5 are met.
"""

from __future__ import annotations

import sys
import time

import libusb_package
import usb.core
import usb.util

VENDOR_ID, PRODUCT_ID = 0x04B5, 0x3062
EP_OUT, EP_IN = 0x02, 0x86
CTRL_BEGINCOMMAND = 0xB3
BEGIN_PAYLOAD = bytes([0x0F, 0x03, 0x03, 0x03, 0x68, 0xAC, 0xFE, 0x00, 0x01, 0x00])
VENDOR_OUT = usb.util.CTRL_OUT | usb.util.CTRL_TYPE_VENDOR | usb.util.CTRL_RECIPIENT_DEVICE

CMD_FORCE_TRIGGER = 0x02
CMD_START_COLLECT = 0x03
CMD_START_TRIGGER = 0x04
CMD_GET_DATA = 0x05
CMD_GET_STATE = 0x06

STATES = {
    0: "CAPTURE_EMPTY",
    1: "CAPTURE_FILLING",
    2: "CAPTURE_READY_8BIT",
    3: "CAPTURE_READY_2250",
    7: "CAPTURE_READY_9BIT",
}


def send(dev, opcode: int, payload: bytes = b"\x00") -> None:
    dev.ctrl_transfer(VENDOR_OUT, CTRL_BEGINCOMMAND, 0, 0, BEGIN_PAYLOAD, 200)
    dev.write(EP_OUT, bytes([opcode]) + payload, 300)


def read(dev, length: int = 512, timeout: int = 400) -> bytes | None:
    try:
        return bytes(dev.read(EP_IN, length, timeout))
    except usb.core.USBError:
        return None


def state(dev) -> tuple[int, bytes] | None:
    send(dev, CMD_GET_STATE)
    r = read(dev)
    if r is None:
        return None
    return r[0] & 7, r


def main() -> int:
    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1

    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)
    print(f"{dev.product}\n")

    try:
        s = state(dev)
        print(f"initial state: {s[0]} ({STATES.get(s[0], '?')})  raw={s[1][:8].hex(' ')}")

        print("\nsending 0x03 StartCollectData")
        send(dev, CMD_START_COLLECT)
        r = read(dev, 512, 300)
        print(f"  reply: {r[:8].hex(' ') if r else '(none)'}")

        print("sending 0x04 StartTrigger")
        send(dev, CMD_START_TRIGGER)
        r = read(dev, 512, 300)
        print(f"  reply: {r[:8].hex(' ') if r else '(none)'}")

        print("\nsending 0x02 ForceTrigger")
        # Nothing is connected to the probes, so no real trigger event will
        # ever arrive and the capture would sit in CAPTURE_FILLING forever.
        send(dev, CMD_FORCE_TRIGGER)
        r = read(dev, 512, 300)
        print(f"  reply: {r[:8].hex(' ') if r else '(none)'}")

        print("\npolling 0x06 for a ready state (5 s max)")
        seen = {}
        deadline = time.time() + 5.0
        while time.time() < deadline:
            s = state(dev)
            if s is None:
                break
            seen[s[0]] = seen.get(s[0], 0) + 1
            if s[0] in (2, 3, 7):
                print(f"  -> READY: state {s[0]} ({STATES.get(s[0], '?')})  raw={s[1][:8].hex(' ')}")
                break
            time.sleep(0.05)
        print(f"  states observed: { {k: v for k, v in seen.items()} }")

        print("\nsending 0x05 GetData")
        send(dev, CMD_GET_DATA)
        total = b""
        for _ in range(8):
            chunk = read(dev, 512, 400)
            if not chunk:
                break
            total += chunk
        print(f"  received {len(total)} bytes")
        if total:
            print(f"  head: {total[:32].hex(' ')}")
            print(f"  tail: {total[-16:].hex(' ')}")
            uniq = len(set(total))
            print(f"  distinct byte values: {uniq}")
            if uniq > 8:
                print("  -> looks like real sample data, not filler")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

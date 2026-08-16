# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Arm a capture on the DSO3062L and read the samples back.

Implements the full dsoHTGetData sequence recovered from HTHardDLL.dll:

    0x17  read the capture-end address in the 16 M-sample ring buffer
    0x13  set the read start address (512-aligned)
    0x1b  set the read length
    0x05  stream the samples off the bulk IN endpoint

Every opcode used here is volatile: acquisition control and transfer setup.
Nothing writes calibration, flash or EEPROM - those opcodes must never appear
in this file. The instrument's front-panel timebase, volts/div and trigger are
left untouched, so the capture reflects whatever the scope is already showing.

Expects CH1 on the probe-compensation output (1 kHz square wave).
"""

from __future__ import annotations

import argparse
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
CMD_GET_ADDRESS = 0x17
CMD_SET_READ_START = 0x13
CMD_SET_READ_LEN = 0x1B

RING_SIZE = 1 << 24  # the 16777216.0 constant at 0x10008098
STATES = {0: "EMPTY", 1: "FILLING", 2: "READY_8BIT", 3: "READY_2250", 7: "READY_9BIT"}


def send(dev, payload: bytes) -> None:
    dev.ctrl_transfer(VENDOR_OUT, CTRL_BEGINCOMMAND, 0, 0, BEGIN_PAYLOAD, 200)
    dev.write(EP_OUT, payload, 300)


def read(dev, length: int = 512, timeout: int = 500) -> bytes | None:
    try:
        return bytes(dev.read(EP_IN, length, timeout))
    except usb.core.USBError:
        return None


def get_state(dev) -> int | None:
    send(dev, bytes([CMD_GET_STATE, 0x00]))
    r = read(dev)
    return None if r is None else r[0] & 7


def get_address(dev) -> int | None:
    """0x17 - 24-bit little-endian ring-buffer address of the capture end."""
    send(dev, bytes([CMD_GET_ADDRESS, 0x00]))
    r = read(dev)
    if r is None or len(r) < 3:
        return None
    return r[0] | (r[1] << 8) | (r[2] << 16)


def _addr_cmd(opcode: int, value: int, last: int) -> bytes:
    """The 8-byte setup buffer shared by 0x13 and 0x1b.

    Byte 6 duplicates the low byte of the value. That is what the DLL emits -
    it computes `shr eax, 0x20`, which x86-32 masks to a shift of zero - so the
    firmware evidently tolerates it. Reproduced verbatim rather than corrected.
    """
    v = value & 0xFFFFFFFF
    return bytes(
        [opcode, 0x00, v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF,
         (v >> 24) & 0xFF, v & 0xFF, last]
    )


def set_read_start(dev, addr: int) -> None:
    send(dev, _addr_cmd(CMD_SET_READ_START, addr - 1, 0x80))


def set_read_len(dev, words: int) -> None:
    send(dev, _addr_cmd(CMD_SET_READ_LEN, words, 0x00))


def set_sample_rate(dev, ticks: int, mode: int = 0) -> None:
    """0x0e - 12-byte buffer. The divider goes on the wire as -(ticks).

    Sample rate is 250 MHz / (ticks + 1); the DLL's jump table holds the clean
    1-2-5 sequence 1, 4, 9, 19, 49, 99, 199, 499, 999, ...
    """
    v = (-ticks) & 0xFFFFFFFF
    send(dev, bytes([0x0E, 0x00, mode & 3, 0x00,
                     v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF,
                     0, 0, 0, 0]))


def set_buffer_size(dev, code: int) -> None:
    """0x0d - 4-byte buffer, second byte is a fixed 0x0f."""
    send(dev, bytes([0x0D, 0x0F, code & 7, 0x00]))


def set_dac(dev, selector: int, value: int) -> None:
    """0x16 - 8-byte buffer carrying a 12-bit DAC word.

    Byte 2 selects the target (0 = channel offset, 1 = trigger level per
    dsoHTSetVTriggerLevel). The high nibble of the DAC word is OR'd with 0x10.
    """
    v = value & 0xFFF
    send(dev, bytes([0x16, 0x00, selector & 0xFF, 0x00,
                     v & 0xFF, ((v >> 8) & 0x0F) | 0x10, 0x00, 0x00]))


def drain(dev, want: int) -> bytes:
    """Read in 512-byte packets, the way the DLL's loop does."""
    out = b""
    while len(out) < want:
        chunk = read(dev, 512, 800)
        if not chunk:
            break
        out += chunk
    return out


def describe(data: bytes, skip_points: int) -> None:
    """The stream is 4 bytes per sample point: CH1, CH2, CH3, CH4.

    sub_10003330 de-interleaves it with a stride of 4, widening each byte to a
    WORD, so one sample point costs four bytes on the wire regardless of how
    many channels are actually enabled.
    """
    print(f"\n  first 32 bytes: {data[:32].hex(' ')}")
    body = data[skip_points * 4:]
    print(f"  preamble {skip_points} points, payload {len(body) // 4} points")
    if not body:
        return
    for ch in range(4):
        stream = body[ch::4]
        if not stream:
            continue
        lo, hi = min(stream), max(stream)
        print(f"  CH{ch + 1}: min={lo:3d} max={hi:3d} span={hi - lo:3d} "
              f"distinct={len(set(stream))}")
        if hi - lo < 8:
            continue
        mid = (lo + hi) / 2
        edges = [
            i for i in range(1, len(stream))
            if (stream[i - 1] < mid) != (stream[i] < mid)
        ]
        if len(edges) >= 3:
            gaps = sorted(b - a for a, b in zip(edges, edges[1:]))
            print(f"      {len(edges)} crossings, median half-period "
                  f"{gaps[len(gaps) // 2]} samples")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=4096, help="nReadDataLen")
    ap.add_argument("--trigpos", type=int, default=50, help="nHTriggerPos, percent")
    ap.add_argument("--force", action="store_true", help="force the trigger")
    ap.add_argument("--save", help="write the raw payload to this file")
    ap.add_argument("--ticks", type=int, help="0x0e divider; rate = 250MHz/(ticks+1)")
    ap.add_argument("--mode", type=int, default=0, help="0x0e byte 2")
    ap.add_argument("--bufcode", type=int, help="0x0d buffer-size code, 0-7")
    ap.add_argument("--dac", type=int, help="0x16 DAC value, 0-4095")
    ap.add_argument("--dacsel", type=int, default=0, help="0x16 byte 2 selector")
    args = ap.parse_args()

    backend = libusb_package.get_libusb1_backend()
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID, backend=backend)
    if dev is None:
        print("04b5:3062 not found - is WinUSB bound?", file=sys.stderr)
        return 1

    dev.set_configuration(1)
    usb.util.claim_interface(dev, 0)
    print(f"{dev.product}\n")

    try:
        if args.bufcode is not None:
            print(f"0x0d buffer-size code {args.bufcode}")
            set_buffer_size(dev, args.bufcode)
            time.sleep(0.05)
        if args.ticks is not None:
            rate = 250e6 / (args.ticks + 1)
            print(f"0x0e ticks {args.ticks} mode {args.mode} -> {rate / 1e3:g} kS/s")
            set_sample_rate(dev, args.ticks, args.mode)
            time.sleep(0.05)

        if args.dac is not None:
            print(f"0x16 selector {args.dacsel} DAC 0x{args.dac:03x}")
            set_dac(dev, args.dacsel, args.dac)
            time.sleep(0.05)

        send(dev, bytes([CMD_START_COLLECT, 0x00]))
        time.sleep(0.3)
        send(dev, bytes([CMD_START_TRIGGER, 0x00]))
        # The pre-trigger half of the ring buffer has to fill before the scope
        # will accept a trigger; forcing one immediately is silently dropped.
        time.sleep(0.3)
        if args.force:
            send(dev, bytes([CMD_FORCE_TRIGGER, 0x00]))
            time.sleep(0.3)

        deadline = time.time() + 3.0
        state = None
        while time.time() < deadline:
            state = get_state(dev)
            if state in (2, 3, 7):
                break
            time.sleep(0.02)
        print(f"state {state} ({STATES.get(state, '?')})")
        if state not in (2, 3, 7):
            print("capture never became ready; retry with --force", file=sys.stderr)
            return 1

        end = get_address(dev)
        print(f"0x17 capture end address: 0x{end:06x}")

        # start = end - trigpos% of the record, wrapped in the ring buffer
        back = int(args.trigpos * args.samples * 0.01)
        start = (end - back) % RING_SIZE
        rem = start & 0x1FF
        aligned = start - rem
        words = 2 * args.samples + 0x800
        nbytes = 2 * words

        print(f"0x13 read start: 0x{aligned:06x}  (rem {rem})")
        print(f"0x1b read length: {words} words -> expecting {nbytes} bytes")
        set_read_start(dev, aligned)
        set_read_len(dev, words)

        send(dev, bytes([CMD_GET_DATA, 0x00]))
        data = drain(dev, nbytes)
        print(f"\n0x05 returned {len(data)} of {nbytes} bytes")
        if not data:
            return 1

        describe(data, rem + 0x200)
        if args.save:
            with open(args.save, "wb") as fh:
                fh.write(data)
            print(f"\nraw payload written to {args.save}")
    finally:
        usb.util.release_interface(dev, 0)
        usb.util.dispose_resources(dev)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

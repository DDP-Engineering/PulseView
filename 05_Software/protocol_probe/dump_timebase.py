# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Extract the nTimeDIV -> sample-rate divider table from HTHardDLL.dll.

Interoperability analysis. The DLL is parsed and disassembled, never loaded
or executed, and never redistributed.

dsoHTSetSampleRate switches on nTimeDIV through a 38-entry jump table. Each
arm loads the divider into ebx and two mode flags onto the stack, which the
tail packs into byte 2 of the 0x0e command. Reading 38 arms by hand invites
transcription errors, so they are decoded here instead.
"""

from __future__ import annotations

import sys

from map_commands import Image

TABLE_VA = 0x10002284
ENTRIES = 0x26
# Confirmed on hardware against the 1 kHz probe-compensation reference: the
# measured half-period scales as 50000/(ticks+1) samples per interleaved core
# across ticks 99..1999, which puts the per-channel base clock at 200 MHz.
BASE_CLOCK_HZ = 200_000_000


def arm(img: Image, addr: int) -> tuple[int | None, int | None, int | None]:
    """Decode one switch arm: (divider, flag_at_0x60, flag_at_0x58)."""
    div = f60 = f58 = None
    regs: dict[str, int] = {}
    off = addr - img.start
    for insn in img.md.disasm(img.code[off : off + 64], addr):
        if insn.mnemonic == "jmp":
            break
        m = [p.strip() for p in insn.op_str.split(",")]
        if len(m) != 2:
            continue
        # Several arms load the flag into eax first and store the register, so
        # immediates alone are not enough - track a little register state.
        if insn.mnemonic == "mov" and m[0] in ("eax", "ebx"):
            if m[1].startswith("0x"):
                regs[m[0]] = int(m[1], 16)
            elif m[1].isdigit():
                regs[m[0]] = int(m[1])
        if insn.mnemonic == "xor" and m[0] == m[1]:
            regs[m[0]] = 0

        if insn.mnemonic in ("mov", "or") and m[0] == "ebx" and m[1].startswith("0x"):
            v = int(m[1], 16)
            div = v - (1 << 32) if v >= 0x80000000 else v

        for slot, name in (("esp + 0x60", "f60"), ("esp + 0x58", "f58")):
            if insn.mnemonic == "mov" and slot in m[0]:
                val = regs.get(m[1]) if m[1] in regs else (
                    int(m[1], 0) if m[1].lstrip("-").isdigit() or
                    m[1].startswith("0x") else None
                )
                if val is not None:
                    if name == "f60":
                        f60 = val
                    else:
                        f58 = val
    return div, f60, f58


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    img = Image(sys.argv[1])

    print(f"{'idx':>4} {'target':>10} {'divider':>10} {'byte2':>6}  {'ticks':>8}  rate")
    for i in range(ENTRIES):
        raw = img.pe.get_data(TABLE_VA - img.base + i * 4, 4)
        target = int.from_bytes(raw, "little")
        div, f60, f58 = arm(img, target)
        if div is None:
            print(f"{i:4d} 0x{target:08x}  (no divider found)")
            continue
        # The arms store the divider as -(ticks); the tail sends it verbatim.
        ticks = -div
        byte2 = ((f60 or 0) & 1) << 1 | ((f58 or 0) & 1)
        rate = BASE_CLOCK_HZ / ticks if ticks > 0 else 0
        unit = f"{rate / 1e6:g} MS/s" if rate >= 1e6 else f"{rate / 1e3:g} kS/s"
        print(f"{i:4d} 0x{target:08x} {div:10d}  0b{byte2:02b}  {ticks:8d}  {unit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

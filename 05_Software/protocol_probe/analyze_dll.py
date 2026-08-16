# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Static analysis of HTHardDLL.dll to recover the device command vocabulary.

Interoperability analysis only: the DLL is never loaded or executed, and the
vendor binary is not redistributed. The goal is the IOCTL codes and command
constants the SDK hands to the vendor kernel driver, so an independent
libsigrok driver can be written against the same device.

Usage:
    uv run analyze_dll.py <path to HTHardDLL.dll>
"""

from __future__ import annotations

import sys
from collections import deque

import capstone
import pefile

# DeviceIoControl is __stdcall; arguments are pushed right to left, so the
# IOCTL code is the second-to-last push before the call.
DEVICE_IO_CONTROL = "DeviceIoControl"
WINDOW = 24


def iat_slots(pe: pefile.PE) -> dict[int, str]:
    slots: dict[int, str] = {}
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        for imp in entry.imports:
            if imp.name:
                slots[imp.address] = imp.name.decode()
    return slots


def export_map(pe: pefile.PE) -> dict[int, str]:
    base = pe.OPTIONAL_HEADER.ImageBase
    return {
        base + e.address: (e.name.decode() if e.name else f"ord{e.ordinal}")
        for e in pe.DIRECTORY_ENTRY_EXPORT.symbols
    }


def enclosing_export(addr: int, exports: dict[int, str]) -> str:
    candidates = [a for a in exports if a <= addr]
    if not candidates:
        return "(below first export)"
    return exports[max(candidates)]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    pe = pefile.PE(sys.argv[1])
    base = pe.OPTIONAL_HEADER.ImageBase
    text = next(s for s in pe.sections if s.Name.startswith(b".text"))
    code = text.get_data()
    start = base + text.VirtualAddress

    slots = iat_slots(pe)
    exports = export_map(pe)

    target = None
    for addr, name in slots.items():
        if name == DEVICE_IO_CONTROL:
            target = addr
    if target is None:
        print("DeviceIoControl not imported.")
        return 1

    print(f"DeviceIoControl IAT slot: 0x{target:08x}")
    print(f".text: 0x{start:08x} .. 0x{start + len(code):08x}\n")

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True

    window: deque = deque(maxlen=WINDOW)
    hits = 0

    for insn in md.disasm(code, start):
        is_call = insn.mnemonic == "call" and f"0x{target:x}" in insn.op_str
        if is_call:
            hits += 1
            print("=" * 70)
            print(f"call DeviceIoControl @ 0x{insn.address:08x}")
            print(f"  inside: {enclosing_export(insn.address, exports)}")
            print("-" * 70)
            pushes = [i for i in window if i.mnemonic == "push"]
            for i in window:
                mark = "  <<" if i.mnemonic == "push" else ""
                print(f"    0x{i.address:08x}  {i.mnemonic:<7} {i.op_str}{mark}")
            imms = [
                i.op_str
                for i in pushes
                if i.op_str.startswith("0x") or i.op_str.isdigit()
            ]
            if len(imms) >= 2:
                print(f"\n  push immediates (arg order reversed): {imms}")
                print(f"  --> likely IOCTL code: {imms[-2]}")
            print()
        window.append(insn)

    print(f"\nTotal DeviceIoControl call sites: {hits}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

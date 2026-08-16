# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Print the disassembly of one function in HTHardDLL.dll.

Interoperability analysis. The DLL is parsed and disassembled, never loaded
or executed, and never redistributed.

Reuses map_commands.Image so the same recursive-descent decoding applies; a
linear sweep desynchronises on the alignment padding between these functions.

Usage:
    uv run dump_func.py <dll> <export-name | 0xADDRESS> [more...]
"""

from __future__ import annotations

import sys

from map_commands import Image


def resolve(img: Image, token: str) -> int | None:
    if token.startswith("0x"):
        return int(token, 16)
    for addr, name in img.exports.items():
        if name == token:
            return addr
    return None


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    img = Image(sys.argv[1])
    for token in sys.argv[2:]:
        addr = resolve(img, token)
        if addr is None:
            print(f"{token}: not found")
            continue
        print("=" * 72)
        print(f"{img.label(addr)} @ 0x{addr:08x}  (rva 0x{addr - img.base:05x})")
        print("=" * 72)
        for i in img.body(addr):
            note = ""
            if i.mnemonic == "call" and i.op_str.startswith("0x"):
                note = f"    ; {img.label(int(i.op_str, 16))}"
            elif i.mnemonic == "call":
                for slot, name in img.iat.items():
                    if f"0x{slot:x}" in i.op_str:
                        note = f"    ; {name}"
                        break
            print(f"  0x{i.address:08x}  {i.mnemonic:<8} {i.op_str}{note}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

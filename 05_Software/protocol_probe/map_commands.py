# Copyright (c) 2026 DDP Engineering
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# Commercial use requires a separate commercial license.
# See the LICENSE-PolyForm.txt file for full license details.
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Recover the DSO3062L command vocabulary from HTHardDLL.dll.

Interoperability analysis. The DLL is parsed and disassembled, never loaded
or executed, and never redistributed.

Uses recursive-descent disassembly seeded from the export table. A linear
sweep desynchronises on the alignment padding between these functions and
silently loses most export entry points, so each function is decoded from its
own entry address instead.

For every exported SDK function it walks the call graph down to the code that
issues DeviceIoControl and reports the command bytes written into the request
buffer plus the in/out buffer sizes.

Usage:
    uv run map_commands.py <path to HTHardDLL.dll> [export-name]
"""

from __future__ import annotations

import sys

import capstone
import pefile

MAX_FUNC_BYTES = 0x2000
MAX_DEPTH = 5


class Image:
    def __init__(self, path: str) -> None:
        self.pe = pefile.PE(path)
        self.base = self.pe.OPTIONAL_HEADER.ImageBase
        text = next(s for s in self.pe.sections if s.Name.startswith(b".text"))
        self.start = self.base + text.VirtualAddress
        self.code = text.get_data()
        self.end = self.start + len(self.code)

        self.md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
        self.md.detail = True

        self.exports = {
            self.base + e.address: (e.name.decode() if e.name else f"ord{e.ordinal}")
            for e in self.pe.DIRECTORY_ENTRY_EXPORT.symbols
        }
        self.iat = {}
        for entry in self.pe.DIRECTORY_ENTRY_IMPORT:
            for imp in entry.imports:
                if imp.name:
                    self.iat[imp.address] = imp.name.decode()
        self.ioctl_slot = next(
            (a for a, n in self.iat.items() if n == "DeviceIoControl"), None
        )

        self._body: dict[int, list] = {}
        self.functions: set[int] = set(self.exports)
        self._discover()

    def _decode(self, addr: int) -> list:
        """Decode one function by recursive descent from its entry address."""
        if addr in self._body:
            return self._body[addr]
        if not (self.start <= addr < self.end):
            self._body[addr] = []
            return []

        off = addr - self.start
        chunk = self.code[off : off + MAX_FUNC_BYTES]
        out: list = []
        furthest_jump = addr
        for insn in self.md.disasm(chunk, addr):
            out.append(insn)
            if insn.mnemonic.startswith("j") and insn.op_str.startswith("0x"):
                tgt = int(insn.op_str, 16)
                if addr <= tgt < addr + MAX_FUNC_BYTES:
                    furthest_jump = max(furthest_jump, tgt)
            # A function ends at a ret once no forward branch still points past
            # this point; otherwise the ret is just an early-exit path.
            if insn.mnemonic.startswith("ret") and insn.address >= furthest_jump:
                break
        self._body[addr] = out
        return out

    def _discover(self) -> None:
        work = list(self.exports)
        seen = set()
        while work:
            addr = work.pop()
            if addr in seen:
                continue
            seen.add(addr)
            for insn in self._decode(addr):
                if insn.mnemonic == "call" and insn.op_str.startswith("0x"):
                    tgt = int(insn.op_str, 16)
                    if self.start <= tgt < self.end and tgt not in seen:
                        self.functions.add(tgt)
                        work.append(tgt)

    def body(self, addr: int) -> list:
        return self._decode(addr)

    def callees(self, addr: int) -> list[int]:
        out = []
        for insn in self.body(addr):
            if insn.mnemonic == "call" and insn.op_str.startswith("0x"):
                tgt = int(insn.op_str, 16)
                if self.start <= tgt < self.end:
                    out.append(tgt)
        return out

    def does_ioctl(self, addr: int) -> bool:
        slot = f"0x{self.ioctl_slot:x}"
        return any(
            i.mnemonic == "call" and slot in i.op_str for i in self.body(addr)
        )

    def label(self, addr: int) -> str:
        return self.exports.get(addr, f"sub_{addr:08x}")


def cmd_bytes(img: Image, addr: int) -> list[str]:
    """Immediate stores into the request buffer - the device opcodes."""
    out = []
    for i in img.body(addr):
        if i.mnemonic in ("mov", "or") and "ptr" in i.op_str and "," in i.op_str:
            dst, src = i.op_str.rsplit(",", 1)
            src = src.strip()
            if (src.startswith("0x") or src.isdigit()) and "byte" in dst:
                out.append(f"{dst.strip()} = {src}")
    return out


def io_sizes(img: Image, addr: int) -> list[str]:
    out = []
    for i in img.body(addr):
        if i.mnemonic == "push" and (i.op_str.startswith("0x") or i.op_str.isdigit()):
            out.append(i.op_str)
    return out


def walk(img: Image, addr: int, depth: int, seen: set) -> list[int]:
    if depth > MAX_DEPTH or addr in seen:
        return []
    seen.add(addr)
    hits = [addr] if img.does_ioctl(addr) else []
    for c in img.callees(addr):
        hits.extend(walk(img, c, depth + 1, seen))
    return hits


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    img = Image(sys.argv[1])
    only = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"image base 0x{img.base:08x}   .text 0x{img.start:08x}-0x{img.end:08x}")
    print(f"functions discovered: {len(img.functions)}   exports: {len(img.exports)}")
    print(f"DeviceIoControl slot: 0x{img.ioctl_slot:08x}")
    print(f"IOCTL issuers: {[img.label(f) for f in sorted(img.functions) if img.does_ioctl(f)]}\n")

    reported = 0
    for addr in sorted(img.exports):
        name = img.exports[addr]
        if only and only != name:
            continue
        workers = walk(img, addr, 0, set())
        if not workers:
            continue
        reported += 1
        print("=" * 72)
        print(f"{name}   (rva 0x{addr - img.base:05x})")
        for w in workers:
            print(f"  issuer {img.label(w)} @ 0x{w:08x}")
            for c in cmd_bytes(img, w):
                print(f"      store {c}")
            sz = io_sizes(img, w)
            if sz:
                print(f"      push imms: {sz}")
        print()

    print(f"exports reaching DeviceIoControl: {reported}/{len(img.exports)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

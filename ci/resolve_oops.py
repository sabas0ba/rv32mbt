#!/usr/bin/env python3
"""Resolve kernel addresses in a RISC-V oops dump against vmlinux.

Reads console output on stdin, extracts hex addresses from oops lines
(epc/ra/backtrace entries), and prints the nearest preceding symbol
from the vmlinux symbol table. Addresses outside the kernel image
(userspace, MMIO) are reported as such. Pure-python ELF32 reader: the
CI container has no llvm-nm for RISC-V.

Usage: resolve_oops.py vmlinux < console.log
"""
import bisect
import re
import struct
import sys


def read_symbols(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise SystemExit(f"{path}: not a little-endian ELF32")
    e_shoff, = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x2E)
    symtab = strtab = None
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", data, off + 4)
        if sh_type == 2:  # SHT_SYMTAB
            sh_offset, sh_size = struct.unpack_from("<II", data, off + 16)
            sh_link, = struct.unpack_from("<I", data, off + 24)
            symtab = (sh_offset, sh_size)
            loff = e_shoff + sh_link * e_shentsize
            l_offset, l_size = struct.unpack_from("<II", data, loff + 16)
            strtab = (l_offset, l_size)
    if symtab is None:
        raise SystemExit(f"{path}: no symtab")
    soff, ssize = symtab
    stroff, strsize = strtab
    syms = []
    for off in range(soff, soff + ssize, 16):
        name_off, value, _size, info = struct.unpack_from("<IIIB", data, off)
        if value == 0 or (info & 0xF) not in (1, 2):  # OBJECT or FUNC
            continue
        end = data.index(b"\0", stroff + name_off)
        name = data[stroff + name_off:end].decode("ascii", "replace")
        if name:
            syms.append((value, name))
    syms.sort()
    return syms


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    syms = read_symbols(sys.argv[1])
    addrs = [v for v, _ in syms]
    lo, hi = addrs[0], max(v for v, _ in syms)
    pat = re.compile(
        r"(?:epc\s*:\s*|ra\s*:\s*|badaddr:\s*|\[<)(?:0x)?([0-9a-f]{8})"
    )
    seen = []
    for line in sys.stdin:
        for m in pat.finditer(line):
            a = int(m.group(1), 16)
            if a not in seen:
                seen.append(a)
    if not seen:
        return
    print("--- oops address resolution (vmlinux symtab) ---")
    for a in seen:
        if a < lo or a > hi + 0x10000:
            where = "outside kernel image (userspace/MMIO?)"
        else:
            i = bisect.bisect_right(addrs, a) - 1
            v, name = syms[i]
            where = f"{name}+{a - v:#x}"
        print(f"  {a:08x}  {where}")


if __name__ == "__main__":
    main()

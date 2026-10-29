#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_rom.py : 用 tools/rvasm.py 汇编上板程序, 生成 prog.hex

用法:
    python3 make_rom.py                  # 生成同目录下的 prog.hex
    python3 make_rom.py -o /path/prog.hex

prog.hex 是 $readmemh 的初始化文件, 每段 256 字, 字地址用 @ 标记:
    @000 程序 0 累加和    @100 程序 1 斐波那契
    @200 程序 2 闰年判断  @300 程序 3 素数判断
不足 256 字的部分补 nop, 保证 1024 个单元都有确定值.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import rvasm  # noqa: E402

DEPTH = 256
NOP   = 0x00000013          # addi x0, x0, 0

PROGRAMS = [
    ("prog_sum.S",   "累加和 1+2+...+n"),
    ("prog_fib.S",   "斐波那契 F(n)"),
    ("prog_leap.S",  "闰年判断"),
    ("prog_prime.S", "素数判断"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output",
                    default=os.path.join(HERE, "prog.hex"))
    args = ap.parse_args()

    lines = []
    for idx, (fname, desc) in enumerate(PROGRAMS):
        path = os.path.join(HERE, fname)
        with open(path, encoding="utf-8") as f:
            words, _ = rvasm.assemble(f.read())
        if len(words) > DEPTH:
            sys.exit("%s: %d words, 超过 %d 字" % (fname, len(words), DEPTH))

        lines.append("@%03x" % (idx * DEPTH))
        lines.extend("%08x" % (w & 0xFFFFFFFF) for w in words)
        lines.extend("%08x" % NOP for _ in range(DEPTH - len(words)))
        print("  %d: %-12s %3d words  %s" % (idx, fname, len(words), desc))

    with open(args.output, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("已生成 %s: %d 段 x %d 字" % (args.output, len(PROGRAMS), DEPTH))
    return 0


if __name__ == "__main__":
    sys.exit(main())

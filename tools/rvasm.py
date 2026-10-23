#!/usr/bin/env python3
"""极简 RV32I 汇编器 (lab10/lab11 本地仿真用)。

用法:
    python3 tools/rvasm.py prog.S -o prog.hex          # $readmemh 用, 每行 8 位十六进制
    python3 tools/rvasm.py prog.S -o prog.hex --coe    # 额外生成 prog.coe

支持: RV32I 整数/跳转/访存指令 + nop/li/mv/j/beqz/bnez/jr/ret 伪指令,
      标签, 十进制/十六进制/负立即数, .word, 注释 (# 或 ;)。
"""
import argparse
import re
import sys

ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
    "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}


def parse_reg(tok):
    tok = tok.strip()
    m = re.fullmatch(r"x(\d+)", tok)
    if m:
        n = int(m.group(1))
        if not 0 <= n <= 31:
            raise ValueError("register out of range: " + tok)
        return n
    if tok in ABI:
        return ABI[tok]
    raise ValueError("unknown register: " + tok)


def parse_imm(tok, labels, pc):
    tok = tok.strip()
    if tok in labels:
        return labels[tok] - pc
    return int(tok, 0)


# name: (funct3, funct7, opcode)
R_TYPE = {
    "add": (0b000, 0b0000000, 0b0110011),
    "sub": (0b000, 0b0100000, 0b0110011),
    "sll": (0b001, 0b0000000, 0b0110011),
    "slt": (0b010, 0b0000000, 0b0110011),
    "sltu": (0b011, 0b0000000, 0b0110011),
    "xor": (0b100, 0b0000000, 0b0110011),
    "srl": (0b101, 0b0000000, 0b0110011),
    "sra": (0b101, 0b0100000, 0b0110011),
    "or": (0b110, 0b0000000, 0b0110011),
    "and": (0b111, 0b0000000, 0b0110011),
}
# name: (funct3, opcode)
I_TYPE = {
    "addi": (0b000, 0b0010011),
    "slti": (0b010, 0b0010011),
    "sltiu": (0b011, 0b0010011),
    "xori": (0b100, 0b0010011),
    "ori": (0b110, 0b0010011),
    "andi": (0b111, 0b0010011),
}
SHIFT_I = {  # name: (funct3, funct7)
    "slli": (0b001, 0b0000000),
    "srli": (0b101, 0b0000000),
    "srai": (0b101, 0b0100000),
}
LOADS = {  # name: (funct3, memop)
    "lb": (0b000, 0b000),
    "lh": (0b001, 0b001),
    "lw": (0b010, 0b010),
    "lbu": (0b100, 0b100),
    "lhu": (0b101, 0b101),
}
STORES = {
    "sb": (0b000, 0b000),
    "sh": (0b001, 0b001),
    "sw": (0b010, 0b010),
}
BRANCHES = {
    "beq": 0b000, "bne": 0b001, "blt": 0b100,
    "bge": 0b101, "bltu": 0b110, "bgeu": 0b111,
}


def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3, opcode):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(imm, rs2, rs1, funct3, opcode):
    imm &= 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) \
        | (b4_1 << 8) | (b11 << 7) | opcode


def enc_u(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm, rd, opcode):
    imm &= 0x1FFFFF
    b20 = (imm >> 20) & 1
    b19_12 = (imm >> 12) & 0xFF
    b11 = (imm >> 11) & 1
    b10_1 = (imm >> 1) & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode


def split_operands(s):
    return [p.strip() for p in s.split(",") if p.strip() != ""]


def encode(line, labels, pc):
    line = line.strip()
    parts = line.split(None, 1)
    op = parts[0].lower()
    ops = split_operands(parts[1]) if len(parts) > 1 else []

    if op == "nop":
        return [enc_i(0, 0, 0b000, 0, 0b0010011)]
    if op == "mv":
        return [enc_i(0, parse_reg(ops[1]), 0b000, parse_reg(ops[0]), 0b0010011)]
    if op == "li":
        rd = parse_reg(ops[0])
        imm = parse_imm(ops[1], labels, pc)
        if -2048 <= imm <= 2047:
            return [enc_i(imm, 0, 0b000, rd, 0b0010011)]
        hi = (imm + 0x800) >> 12
        lo = imm - (hi << 12)
        return [enc_u(hi, rd, 0b0110111), enc_i(lo, rd, 0b000, rd, 0b0010011)]
    if op in ("j",):
        off = parse_imm(ops[0], labels, pc)
        return [enc_j(off, 0, 0b1101111)]
    if op == "jr":
        return [enc_i(0, parse_reg(ops[0]), 0b000, 0, 0b1100111)]
    if op == "ret":
        return [enc_i(0, 1, 0b000, 0, 0b1100111)]
    if op in ("beqz", "bnez"):
        f3 = 0b000 if op == "beqz" else 0b001
        off = parse_imm(ops[1], labels, pc)
        return [enc_b(off, 0, parse_reg(ops[0]), f3, 0b1100011)]
    if op == "word":
        return [parse_imm(ops[0], labels, pc) & 0xFFFFFFFF]

    if op in R_TYPE:
        f3, f7, opc = R_TYPE[op]
        return [enc_r(f7, parse_reg(ops[2]), parse_reg(ops[1]), f3, parse_reg(ops[0]), opc)]
    if op in I_TYPE:
        f3, opc = I_TYPE[op]
        return [enc_i(parse_imm(ops[2], labels, pc), parse_reg(ops[1]), f3, parse_reg(ops[0]), opc)]
    if op in SHIFT_I:
        f3, f7 = SHIFT_I[op]
        sh = parse_imm(ops[2], labels, pc) & 0x1F
        return [enc_i((f7 << 5) | sh, parse_reg(ops[1]), f3, parse_reg(ops[0]), 0b0010011)]
    if op in LOADS:
        f3, _ = LOADS[op]
        m = re.fullmatch(r"(-?\w+)\s*\(\s*(\w+)\s*\)", "".join(ops[1:]))
        if not m:
            raise ValueError("bad load operand: " + line)
        return [enc_i(parse_imm(m.group(1), labels, pc), parse_reg(m.group(2)), f3,
                      parse_reg(ops[0]), 0b0000011)]
    if op in STORES:
        f3, _ = STORES[op]
        m = re.fullmatch(r"(-?\w+)\s*\(\s*(\w+)\s*\)", "".join(ops[1:]))
        if not m:
            raise ValueError("bad store operand: " + line)
        return [enc_s(parse_imm(m.group(1), labels, pc), parse_reg(ops[0]),
                      parse_reg(m.group(2)), f3, 0b0100011)]
    if op in BRANCHES:
        off = parse_imm(ops[2], labels, pc)
        return [enc_b(off, parse_reg(ops[1]), parse_reg(ops[0]), BRANCHES[op], 0b1100011)]
    if op == "jal":
        rd = parse_reg(ops[0])
        tgt = ops[1] if len(ops) > 1 else "0"
        off = parse_imm(tgt, labels, pc)
        return [enc_j(off, rd, 0b1101111)]
    if op == "jalr":
        rd = parse_reg(ops[0])
        m = re.fullmatch(r"(-?\w+)\s*\(\s*(\w+)\s*\)", "".join(ops[1:]))
        if not m:
            raise ValueError("bad jalr operand: " + line)
        return [enc_i(parse_imm(m.group(1), labels, pc), parse_reg(m.group(2)),
                      0b000, rd, 0b1100111)]
    if op == "lui":
        return [enc_u(parse_imm(ops[1], labels, pc), parse_reg(ops[0]), 0b0110111)]
    if op == "auipc":
        return [enc_u(parse_imm(ops[1], labels, pc), parse_reg(ops[0]), 0b0010111)]

    raise ValueError("unknown instruction: " + line)


def assemble(src):
    lines = []
    for raw in src.splitlines():
        line = raw.split("#", 1)[0].split(";", 1)[0].strip()
        if not line:
            continue
        # 忽略 .globl/.text 等汇编器指示, 只保留 .word
        if line.startswith("."):
            parts = line.split(None, 1)
            if parts[0].lower() == ".word":
                line = "word " + (parts[1] if len(parts) > 1 else "0")
            else:
                continue
        lines.append(line)

    # 第一遍: 收集标签地址
    labels = {}
    pc = 0
    for line in lines:
        while ":" in line:
            label, _, rest = line.partition(":")
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_.][\w.]*", label):
                break
            labels[label] = pc
            line = rest.strip()
            if not line:
                break
        if not line:
            continue
        op = line.split(None, 1)[0].lower()
        pc += 4 * (2 if op == "li" and not (-2048 <= _li_imm(line) <= 2047) else 1)

    # 第二遍: 编码
    words = []
    pc = 0
    for line in lines:
        while ":" in line:
            label, _, rest = line.partition(":")
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_.][\w.]*", label):
                break
            line = rest.strip()
            if not line:
                break
        if not line:
            continue
        enc = encode(line, labels, pc)
        words.extend(enc)
        pc += 4 * len(enc)
    return words, labels


def _li_imm(line):
    """pass1 估算 li 大小时使用; 标签未解析时按 12bit 以内处理。"""
    ops = split_operands(line.split(None, 1)[1])
    try:
        return int(ops[1], 0)
    except ValueError:
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--coe", action="store_true")
    ap.add_argument("--labels", action="store_true")
    args = ap.parse_args()

    with open(args.source) as f:
        src = f.read()
    words, labels = assemble(src)
    if not words:
        print("empty program", file=sys.stderr)
        return 1
    if args.labels:
        for name, addr in sorted(labels.items(), key=lambda kv: kv[1]):
            print("%04x %s" % (addr, name), file=sys.stderr)

    with open(args.output, "w") as f:
        for w in words:
            f.write("%08x\n" % (w & 0xFFFFFFFF))
    if args.coe:
        coe = args.output.rsplit(".", 1)[0] + ".coe"
        with open(coe, "w") as f:
            f.write("memory_initialization_radix=16;\n")
            f.write("memory_initialization_vector=\n")
            f.write(",\n".join("%08x" % (w & 0xFFFFFFFF) for w in words))
            f.write(";\n")
    print("assembled %d words -> %s" % (len(words), args.output))
    return 0


if __name__ == "__main__":
    sys.exit(main())

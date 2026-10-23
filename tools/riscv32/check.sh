#!/usr/bin/env bash
# 验证 tools/rvasm.py 的机器码编码, 并用 qemu-riscv32 做一次独立执行.
#
#   enc.S : 覆盖 RV32I 全部 37 条指令中的代表性编码 (含立即数边界与远跳转),
#           用 GNU as 汇编后与 tools/rvasm.py 的输出逐字比较.
#   run.S : 1+2+...+10 的循环, 通过 ecall(93) 把结果作为退出码返回,
#           qemu-riscv32 应返回 55.
#
# 首次使用先构建镜像:
#   docker build -t riscv32:12 tools/riscv32
set -euo pipefail

image="${RISCV_IMAGE:-riscv32:12}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

docker run --rm \
    -v "$root":/work \
    -v "$tmp":/out \
    -w /work/tools/riscv32/smoke \
    "$image" bash -lc '
set -e
riscv64-linux-gnu-as -march=rv32i -mabi=ilp32 -o /tmp/enc.o enc.S
riscv64-linux-gnu-ld -m elf32lriscv -Ttext=0 -o /tmp/enc.elf /tmp/enc.o
riscv64-linux-gnu-objdump -d /tmp/enc.elf \
    | sed -nE "s/^[[:space:]]+[0-9a-f]+:[[:space:]]+([0-9a-f]{8})[[:space:]].*/\1/p" \
    > /out/gnu.hex

riscv64-linux-gnu-as -march=rv32i -mabi=ilp32 -o /tmp/run.o run.S
riscv64-linux-gnu-ld -m elf32lriscv -Ttext=0x10000 -e _start -o /tmp/run.elf /tmp/run.o
qemu-riscv32 /tmp/run.elf || echo $? > /out/qemu_exit
'

python3 "$root/tools/rvasm.py" "$root/tools/riscv32/smoke/enc.S" -o "$tmp/rvasm.hex" >/dev/null

python3 - "$tmp/gnu.hex" "$tmp/rvasm.hex" <<'EOF'
import sys

gnu = [l.strip() for l in open(sys.argv[1]) if l.strip()]
rva = [l.strip() for l in open(sys.argv[2]) if l.strip()]
if len(gnu) != len(rva):
    sys.exit("instruction count mismatch: gnu=%d rvasm=%d" % (len(gnu), len(rva)))
bad = [(i, a, b) for i, (a, b) in enumerate(zip(gnu, rva), 1) if a != b]
for i, a, b in bad:
    print("MISMATCH line %d: gnu=%s rvasm=%s" % (i, a, b))
if bad:
    sys.exit(1)
print("encodings: %d/%d match" % (len(gnu), len(rva)))
EOF

code="$(cat "$tmp/qemu_exit" 2>/dev/null || echo 0)"
if [ "$code" != "55" ]; then
    echo "qemu exit code $code, expected 55" >&2
    exit 1
fi

echo "qemu-riscv32: exit 55 (1+2+...+10)"
echo "riscv32 smoke PASSED"

FROM ubuntu:22.04

# RISC-V 交叉工具链:
#   binutils-riscv64-linux-gnu : as/ld/objcopy/objdump, 支持 -march=rv32i -mabi=ilp32
#   gcc-riscv64-linux-gnu      : 交叉 C 编译器, 配合 -march=rv32i -mabi=ilp32 -nostdlib
#   gawk                       : lab12 的 Makefile 用 strtonum(), mawk 不支持
#   make                       : 软件工程的 Makefile
# qemu-riscv32 作为独立的 RV32I 指令级参考执行环境
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        binutils-riscv64-linux-gnu \
        gcc-riscv64-linux-gnu \
        gawk \
        make \
        qemu-user \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work

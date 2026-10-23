FROM ubuntu:22.04

# RISC-V 交叉工具链 (binutils 可用 -march=rv32i -mabi=ilp32 汇编/链接/反汇编)
# qemu-riscv32 作为独立的 RV32I 指令级参考执行环境
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        binutils-riscv64-linux-gnu \
        qemu-user \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work

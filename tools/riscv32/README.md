# riscv32 工具链容器

用于在没有本地 RISC-V 工具链时汇编、链接、反汇编和运行 RV32I 程序。

- `binutils-riscv64-linux-gnu`：用 `-march=rv32i -mabi=ilp32` 生成 32 位机器码，
  提供 `as`、`ld`、`objcopy`、`objdump`。
- `qemu-user`：提供 `qemu-riscv32`，可执行静态链接的 RV32 Linux ELF，
  用 `ecall` 的 `exit` 系统调用返回结果。

构建与自检：

```bash
docker build -t riscv32:12 tools/riscv32
tools/riscv32/check.sh
```

`check.sh` 会做两件事：把 `smoke/enc.S` 的 41 条指令编码与 `tools/rvasm.py`
的输出逐字比较；用 `qemu-riscv32` 执行 `smoke/run.S` 的求和循环，检查退出码为 55。

上板程序的完整汇编与 ROM 生成仍用 `tools/rvasm.py` 和
`lab09/exp2_board/make_rom.py`，不依赖这个容器。

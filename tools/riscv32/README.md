# riscv32 工具链容器

用于在没有本地 RISC-V 工具链时汇编、链接、反汇编、编译 RV32I C 程序和运行 RV32I 程序。

- `binutils-riscv64-linux-gnu`：用 `-march=rv32i -mabi=ilp32` 生成 32 位机器码，提供 `as`、`ld`、`objcopy`、`objdump`。
- `gcc-riscv64-linux-gnu`：交叉 C 编译器。配合 `-march=rv32i -mabi=ilp32 -nostdlib -nolibc` 可以直接编译裸机 C 程序。
- `gawk`：`lab12` 示例 Makefile 的 `awk` 脚本用了 `strtonum()`，Ubuntu 默认的 `mawk` 不支持。
- `qemu-user`：提供 `qemu-riscv32`，可执行静态链接的 RV32 Linux ELF，用 `ecall` 的 `exit` 系统调用返回结果。

构建与自检：

```bash
docker build -t riscv32:12 tools/riscv32
tools/riscv32/check.sh
```

`check.sh` 会做两件事：把 `smoke/enc.S` 的 41 条指令编码与 `tools/rvasm.py` 的输出逐字比较；用 `qemu-riscv32` 执行 `smoke/run.S` 的求和循环，检查退出码为 55。

## 编译裸机 C 程序

`gcc-riscv64-linux-gnu` 默认生成 RV64 代码，必须显式指定 RV32：

```bash
riscv64-linux-gnu-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -c main.c -o main.o
```

链接时建议加 `-Wl,--build-id=none`。Ubuntu 22.04 的交叉 GCC 默认生成 `.note.gnu.build-id`，它会被链接到地址 0，把 `.text` 挤到 `0x24`，导致 `objcopy -O verilog` 生成的第一个字不是入口指令。加上该选项后 `.text` 从 0 开始，与 lab12 的 `sections.ld` 和 reset 取指地址一致。

`lab12` 的 Makefile 默认前缀是 `riscv32-unknown-elf-`，用容器里的工具链时覆盖为 `riscv64-linux-gnu-`：

```bash
make RISCV_PREFIX=riscv64-linux-gnu- \
     RISCV_GCC_OPTS="-march=rv32i -mabi=ilp32 -static -mcmodel=medany \
     -fvisibility=hidden -Wl,--build-id=none -Tsections.ld \
     -nostdlib -nolibc -nostartfiles"
```

上板程序的完整汇编与 ROM 生成仍用 `tools/rvasm.py` 和 `lab09/exp2_board/make_rom.py`，不依赖这个容器。

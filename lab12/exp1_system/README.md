# exp1_system

lab12 计算机系统工程，目前尚未实现。总体设计、内存映射和分阶段计划见 `../PLAN.md`。

计划中的构建文件：

| 文件 | 作用 |
| :--- | :--- |
| `sys_top.v` | 顶层：CPU、总线译码、VGA、显存、键盘、定时器、数码管 |
| `rv32ip.v` | RV32I 流水线 CPU，从 `lab10/exp1_cpu/rv32ip.v` 复制 |
| `sys_top.xdc` | Nexys A7-100T 引脚约束，从仓库根目录 `ref.xdc` 复制 |
| `vga_font.txt` | 16×9 字模，从 `lab11/exp1_charterm/vga_font.txt` 复制 |
| `main.hex` | 指令存储器初始化，`sw/Makefile` 生成 |
| `main_d.hex` | 数据存储器初始化，`sw/Makefile` 生成 |
| `sw/` | C 软件工程：Makefile、链接脚本、`sys.c`、`main.c`、`mul.c` |
| `sys_mmio_tb.v` | 外设级自检 testbench |
| `sys_top_tb.v` | 全系统自检 testbench |

板上操作与验收项见 `../PLAN.md` 第 5、6 节，Docker 编译命令见 `../PLAN.md` 4.1。

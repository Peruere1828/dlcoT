# Lab12 计算机系统 — 实施计划

本文件是 lab12 的总入口，供人阅读和 Agent 检索。原始 PDF 保留在 `lab12/lab12.pdf` 和 `lab12/labextend.pdf`；原来的压缩包、docx 已整理成 `lab12/refs/` 下的 Markdown，删除原文件后仍可查。

## 实施状态

基本要求已实现，两个自检 testbench 在 iverilog 下均通过，2026-11-24 上板验收通过。同一天补完了终端的光标和按键：光标在滚屏后不再跑行，Tab、方向键、Home/End/Delete 都能用。

| 项目 | 状态 |
| :--- | :--- |
| 硬件 `exp1_system/sys_top.v`、`sys_top.xdc` | 已完成，含 128KB 数据存储器、4KB 显存、VGA、PS/2 键盘、定时器、数码管 |
| 软件 `exp1_system/sw/` | 已完成，`main.hex`、`main_d.hex` 已生成 |
| 硬件光标 | 已完成，寄存器存物理行，硬件减 `top_row` 换成屏幕行再比较 |
| Tab、方向键、Home/End/Delete | 已完成，硬件送控制字节，软件在 `readline` 里实现行编辑 |
| Ctrl 组合键 | 已完成，硬件送 `0x80` 加字母序号，软件实现行首、行尾、清屏、取消行、清空行 |
| 命令集 | hello / time / fib / calc / mem / echo / led / sw / mines / history / clear / help，开关和 LED 通过终端可用 |
| 小游戏 | `mines` 扫雷，9×9 / 10 雷，字符棋盘，方向键 + 回车 + F/R/Q，种子可复现 |
| `sys_mmio_tb.v` 外设级仿真 | `TEST PASSED`，含 Tab 与 `E0` 扩展键的字节映射 |
| `sys_top_tb.v` 全系统仿真 | `TEST PASSED`，覆盖 hello/time/fib/未知命令/退格/滚屏，以及左右键插入、Tab 补全、历史、滚屏后的光标 |
| 上板验收 | 已通过（2026-11-24 实测：终端命令、LED、Tab 补全、扫雷） |

构建清单、编译命令、内存映射与常见问题见 `exp1_system/README.md`。报告在 `lab12实验报告.md`，5.3 节上板结果待补。扩展项按第 7 节顺延。

## 0. 目录与资料状态

```
lab12/
├── lab12.pdf                 保留：实验十二指导书正文
├── labextend.pdf             保留：计算机系统扩展指导书
├── PLAN.md                   本文件：目标、设计决定、实施步骤
├── refs/                     从压缩包和 docx 提炼的 Markdown
│   ├── README.md             资料索引与出处
│   ├── 01_串口通信与加密解密.md
│   ├── 02_音频输出实验.md
│   ├── 03_参考板级设计与RTL.md
│   ├── 04_软件工具链与示例程序.md
│   ├── 05_系统扩展指导.md
│   ├── 06_lab12指导书要点.md
│   └── assets/               图：ASCII 表、UART 接线、PWM 波形、参考 Block Design
├── exp1_system/              基本要求工程：sys_top.v、rv32ip.v、sw/、两个 testbench、README
└── assets/                   报告用截图（仿真波形、综合图等）
```

已删除的原件及去向（压缩包和 docx 已删除，内容已整理到 refs）：

| 原件 | 内容 | 整理到 |
| :--- | :--- | :--- |
| `实验12 串口通信及加密解密.docx` | 串口原理、UART 收发设计、LFSR 加密实验 | `refs/01_串口通信与加密解密.md` |
| `uart_debug.zip` | `serial_tx.v`、`serial_rx.v`、`clkgen.v`、`uart_port.v` | `refs/01_串口通信与加密解密.md` 附录 A |
| `实验11音频输出实验.docx` | PWM 音频原理与实验要求 | `refs/02_音频输出实验.md` |
| `sound_source.zip` | PWM、正弦表、音调选择参考代码 | `refs/02_音频输出实验.md` 附录 A |
| `student-board-design-min.zip` | 旧 n4-riscv 板级 Block Design 与 AXI 外设 | `refs/03_参考板级设计与RTL.md` |
| `software.zip` | RISC-V C 工具链 Makefile、链接脚本、Hello World | `refs/04_软件工具链与示例程序.md` |
| `labextend-ai.zip` | 扩展指导书 Markdown 与 Block Design 图 | `refs/05_系统扩展指导.md`、`refs/assets/design_1.*` |

## 1. 实验目标与验收

在 Nexys A7-100T 上做出一个能跑 C 程序的 RV32I 计算机系统：CPU 通过内存映射访问字符显存和键盘，屏幕上出现可交互的终端。

`lab12.pdf` 第 12.5.1 节要求的必做功能：

1. 接受键盘输入并回显在屏幕上；
2. 支持换行、删除、滚屏；
3. 命令分析，按输入执行子程序并输出结果：
   - `hello` → 显示 `Hello World!`；
   - `time` → 显示时间；
   - `fib n` → 计算斐波那契数列并显示结果；
   - 未知命令 → 输出 `Unknown Command`。

本实验没有在线评测，验收方式为上板演示。扩展项见第 7 节。

**实施策略：先完成基本验收，再做扩展。** 在基本终端通过上板检查之前，不引入串口调试、音频、DDR、总线、中断等功能。基本要求跑通并保留备份后，再按第 7 节选做扩展。

## 2. 已有基础与前提

当前进度：lab01–lab10 均已上板通过，lab11 的字符终端也已上板验证，并在 2026-11-20 更新到支持 Tab、方向键和续行模型的版本。lab12 直接复用 lab09/lab10 的 CPU 和 lab11 的显示、键盘模块；阶段 0 只做一次回归确认，不重新验证 CPU 设计。

可复用的旧实验代码：

| 来源 | 可复用的部分 | 注意事项 |
| :--- | :--- | :--- |
| `lab10/exp2_board/cpu_top.v` | 100MHz 四分频、上电复位、`BTNC` 单步、PC 送 LED、八位数码管扫描 | 4KB dmem、4×256 字 ROM，容量要改 |
| `lab09/exp1_cpu/rv32is.v` | 单周期 RV32I CPU | 与 `rv32ip` 端口相同，可先用来跑通系统 |
| `lab10/exp1_cpu/rv32ip.v` | 五段流水线 RV32I CPU | 已上板，可直接复用 |
| `lab08/exp2_dmem/dmem_top.v` | 里面的 `dmem_128k`：32768×32、`addr[16:2]`、按 `memop` 译码字节使能，已上板 | 没有 `$readmemh` 初始化，要补数据段加载；也可以用下面更简单的读改写方案 |
| `lab09/exp2_board/board_dmem.v` | 4KB 的“上升沿读旧字、下降沿拼新字再写回”结构 | 扩到 32768 字并加 `$readmemh("main_d.hex")`，最省事 |
| `lab11/exp1_charterm/charterm_top.v` | `ps2_keyboard`、`vga_ctrl`、`ascii_of`、字模 ROM、光标、70 列行模型 | 终端状态机不用，换成 MMIO + C 软件；Tab 和方向键的按键解析方式可借鉴 |
| `lab11/exp1_charterm/vga_font.txt` | 256 字符×16 行字模，12 bit 一行 | `$readmemh` 要作为设计源文件加入工程；lab12 已复制现版本，lab11 再改字模时要同步 |
| `lab09/exp2_board/cpu_top.xdc`、`lab10/exp2_board/cpu_top.xdc` | 25MHz 生成时钟约束 `-edges {1 3 9}` | 改分频参数时要同步改 XDC；lab12 的 CPU 时钟和像素时钟各有一条生成时钟 |

- CPU：`lab10/exp1_cpu/rv32ip.v` 流水线 RV32I，端口与 lab09 单周期版一致（`imemaddr`、`dmemaddr`、`dmemop`、`dmemwe`、`dmemrdclk`、`dmemwrclk`、`dbgdata` 等）。也可退回 `lab09/exp1_cpu/rv32is.v` 单周期版，先跑通系统再换流水线。两个版本都已在 25MHz 下上板通过。
- 显示器与键盘：`lab11/exp1_charterm/charterm_top.v` 已验证 PS/2 键盘、640×480 VGA、16×9 字模、30 行×70 列字符显示和滚屏。2026-11-20 的版本又补了 Tab、方向键列号钳位、续行不打提示符、跨行退格，并换成修正后的字模。lab12 只复用 `ps2_keyboard`、`vga_ctrl`、`ascii_of` 和字模，终端逻辑改由 C 软件实现。
- 字模同步：`lab12/exp1_system/vga_font.txt` 与 `lab11/exp1_charterm/vga_font.txt` 目前内容相同，即林同学修正版，0xB0–0xDF 的块元素和制表符右移一像素并对齐，行尾为 LF。lab11 再改字模时要重新复制，否则显示效果会和 lab11 不一致。
- 板上引脚一律从仓库根目录 `ref.xdc` 复制，不自行猜引脚。
- 工具链全部通过 Docker 使用：`iverilog:12` 做编译和行为仿真；`riscv32:12` 提供 RV32 的汇编、链接、反汇编、C 编译和 `qemu-riscv32`，仓库里的 `tools/riscv32/check.sh` 可以自检。`refs/04` 里的 Makefile 与链接脚本可直接改用，编译参数见 4.1。

## 3. 系统总体设计

### 3.1 内存映射（已定稿）

CPU 数据地址 32 位，用高 12 位 `addr[31:20]` 选设备，设备内部再用 `addr[19:0]` 细分。显存和 `0x0021_0000` 的寄存器高 12 位相同，所以显存单独用 `addr[31:16]` 区分。这样译码简单，也不会和指令地址冲突。

| 地址范围 | 大小 | 设备 | CPU 访问 |
| :--- | ---: | :--- | :--- |
| `0x0000_0000`–`0x0000_FFFF` | 64 KiB | 指令存储器，16K 字 | 取指只读 |
| `0x0010_0000`–`0x0011_FFFF` | 128 KiB | 数据存储器，32K 字 | load/store |
| `0x0020_0000`–`0x0020_0FFF` | 4 KiB | 字符显存，32 行×128 列 | 按字节写，可读回调试 |
| `0x0021_0000` | 4 B | 显示起始行寄存器 | 写 |
| `0x0021_0004` | 4 B | 光标位置寄存器，可选 | 写 |
| `0x0030_0000` | 4 B | 键盘数据，低 8 位 ASCII | 读 |
| `0x0030_0004` | 4 B | 键盘状态：bit0 有数据，bit1 溢出 | 读 |
| `0x0030_0008` | 4 B | 键盘弹出，写任意值 | 写 |
| `0x0040_0000` | 4 B | 毫秒定时器，只读 | 读 |
| `0x0050_0000` | 4 B | 拨动开关 `SW[15:0]` | 读 |
| `0x0060_0000` | 4 B | LED `LED[15:0]` | 写 |
| `0x0060_0004` | 4 B | 七段数码管调试值，可选 | 写 |
| `0x0070_0000` 起 | — | 串口调试窗口，可选，见 3.7 | 读写 |

注意：

- 显示显存的行步长是 128，所以 C 里字符地址为 `(row << 7) + col`，和 `refs/04` 里 `sys.c` 的写法一致；屏幕只显示 30 行×70 列。
- `0x0020_0000` 和 `0x0021_0000` 的高 12 位相同。现实现对显存按 `addr[31:16] == 16'h0020` 译码，对起始行、光标等寄存器按整字地址精确比较，比只比较 `addr[31:20]` 再拆 `addr[16]` 更直接。
- 定时器、开关这些只读寄存器直接返回组合值即可；LED、起始行这类只写寄存器用 `always @(posedge clk)` 锁存。
- 数据存储器必须支持 `sb`、`sh`、`sw`；按 lab08 的教训，FPGA 上 32 位 BRAM 只能整字读写。现实现沿用 `lab09/exp2_board/board_dmem.v` 的“上升沿读旧字、下降沿按 `memop` 拼出新字再写回”，扩到 128KB：`DMEM_WORDS=32768`、`dst_idx=addr[16:2]`，并加 `$readmemh("main_d.hex", dmem)`。`lab08/exp2_dmem/dmem_top.v` 里的 `dmem_128k` 用四个 8 位字节通道实现，已经上板，也可以替换，但它没有 `$readmemh` 初始化，需要另外生成按字节拆分的初始化文件。

### 3.2 模块划分与文件规划

上板是多文件工程，和 lab09 exp2 一样，在 README 里写明完整构建清单：

```
lab12/exp1_system/
├── sys_top.v          顶层：CPU 例化、总线译码、显存、键盘、VGA、定时器、数码管
├── rv32ip.v           CPU，从 lab10 复制，改 CPU 时两边同步
├── sys_top.xdc        引脚约束，从 ref.xdc 复制
├── vga_font.txt       16×9 字模，从 lab11 复制
├── main.hex           指令存储器初始化文件，Makefile 生成
├── main_d.hex         数据存储器初始化文件，Makefile 生成
├── sw/                软件工程，见第 4 节
├── sys_mmio_tb.v      外设与总线的自检 testbench
├── sys_top_tb.v       全系统 testbench，装入真实 main.hex，用 PS/2 时序敲键
└── README.md          构建文件清单、板上操作、常见问题
```

Vivado 里加入 `sys_top.v`、`rv32ip.v`、`main.hex`、`main_d.hex`、`vga_font.txt`、`sys_top.xdc`，顶层设为 `sys_top`。`main.hex` 和 `main_d.hex` 要被 Vivado 当作设计源文件一起加入，否则 `$readmemh` 找不到文件。

`sys_top` 内部再分几个小模块，全部写在 `sys_top.v` 一个文件里，保持构建简单：

| 模块 | 作用 |
| :--- | :--- |
| `sys_top` | 时钟分频、复位、CPU 与各外设连线 |
| `imem` | 64 KiB 指令 BRAM，`$readmemh("main.hex")`，上升沿读，PC 在下降沿更新 |
| `dmem` | 128 KiB 数据 BRAM，上升沿读整字，下降沿按 `memop` 拼出新字写回，`$readmemh("main_d.hex")` |
| `vga_ctrl` | 640×480@60Hz 时序，25MHz 像素时钟，输出字符行列坐标，从 lab11 移植 |
| `charmem` | 4096×8 字符显存，CPU 写端口与 VGA 读端口分开 |
| `ps2_keyboard` | PS/2 同步、奇校验、扫描码 FIFO，从 lab11 移植 |
| `ascii_of` | 扫描码转 ASCII，处理 Shift、`F0` 断码、`E0` 扩展码 |
| `kbd_fifo` | 16 项 ASCII FIFO，供 CPU 通过 `0x0030_00xx` 读取 |
| `tick_ms` | 100MHz 分频出 1ms 脉冲，累加 32 位毫秒计数 |
| `seg7` | 八位数码管动态扫描，显示调试值或 PC |

### 3.3 时钟与复位

- `CLK100MHZ`（E3）是唯一输入时钟。
- CPU 时钟用 100MHz 四分频得到的 25MHz。`div_cnt` 每 10ns 加一，`div_cnt == 3` 时给出一个 10ns 高的脉冲，经 `BUFG` 送到 CPU，周期 40ns，和 lab09/lab10 的 `DIV_BITS=2` 一致。XDC 里对应 `-edges {1 3 9}`。
- VGA 像素时钟取 `div_cnt[1]`，也是 25MHz，但占空比 50%，经另一个 `BUFG` 输出，XDC 里对应 `-edges {5 9 13}`。两个时钟同源，显存用分布式 RAM 异步读，不需要跨时钟域处理。
- iverilog 没有 Xilinx 原语，`sys_top.v` 用 `ifdef __ICARUS__` 把两处 `BUFG` 换成直连，仿真和上板共用一份代码。
- 键盘同步、FIFO 都在 CPU 时钟域；PS/2 的 `PS2_CLK`、`PS2_DATA` 先打三拍再采样。
- 复位用 `CPU_RESETN`（C12，低有效），或用 `BTNC`（N17，高有效）加同步复位。上电复位计数器至少 2ms，保证 BRAM 初始化完成。
- 不要用门控时钟做“暂停 CPU”，本实验不需要串口在线调试；如果做，见 3.7 的注意事项。

### 3.4 字符显示

直接沿用 lab11 的结构：

- 640×480@60Hz，行时序 96/48/640/16，场时序 2/33/480/10，像素时钟 25MHz。
- 30 行×70 列字符，每个字符 16 行×9 列像素，字模取 `vga_font.txt` 的 12bit 行数据，bit0 是最左像素。
- 显存 32 行×128 列，多出的 2 行做环形缓冲。VGA 扫描第 `v_row` 行时，实际读 `(top_row + v_row) mod 32`。
- `top_row` 由 CPU 写 `0x0021_0000`，软件滚屏时加一，并负责把新的底行清空。硬件不自动清屏、不自动滚屏。
- 显存写端口由 CPU 的 `sb` 驱动：`addr = {row[4:0], col[6:0]}`，只取 `ddatain[7:0]`。
- 光标由硬件绘制，已实现：软件把 `{物理行[4:0], 列[6:0]}` 写到 `0x0021_0004`，硬件先做 `(物理行 - top_row) mod 32` 换成屏幕行，只在结果小于 30 时在对应字符格的最下面一行画一条 7 像素宽的横线，按约 1.5Hz 闪烁。少写这一步减法，滚屏后光标会整体下移 `top_row` 行，滚过几十行以后直接移出屏幕。

字模与 lab11 一致：地址是 `{chr, v_line}`，每行 12 bit，高 3 bit 为 0，bit0 是最左像素，`pix_col` 取 0 到 8，第 9 列留空。现用版本是 lab11 2026-11-20 的修正版，0xB0–0xDF 的块元素和制表符已经右移对齐。

行模型沿用 lab11 最近定下的约定：提示符只出现在按回车产生的逻辑行行首，行满 70 列自动换行产生的续行从第 0 列接着写，不再打印 `> `。C 软件里主循环在每条命令结束后输出提示符即可满足这一点，`putch` 处理行满换行时不要输出提示符。

显示调试顺序：先显示固定字符串，再验证 CPU 用 `sw`/`sb` 写显存，最后接 C 的 `putch`。

### 3.5 键盘

硬件沿用 lab11：PS/2 帧同步、奇校验、扫描码 FIFO，再用 `ascii_of` 转 ASCII。转换后的 ASCII 进入 16 项 FIFO，并把特殊键映射成控制字符：

| 按键 | 送入 FIFO 的值 |
| :--- | :--- |
| 可打印字符 | 对应 ASCII |
| Enter | `0x0A` |
| Backspace | `0x08` |
| Tab | `0x09` |
| Up / Down / Right / Left | `0x11` / `0x12` / `0x13` / `0x14` |
| Home / End / Delete | `0x01` / `0x05` / `0x7F` |
| Ctrl + 字母 | `0x80` 加字母序号，Ctrl+A 是 `0x81`，Ctrl+L 是 `0x8C` |
| 其它功能键 | 丢弃 |

现版本 `sys_top.v` 的 `ps2_ascii` 在按键解析状态机里先判断 Tab 的扫描码 `8'h0D`，不能靠 `ascii_of` 的输出区分，因为 Enter 的 ASCII 也是 `0x0D`。方向键、Home、End、Delete 在 `E0` 扩展码分支里解析，释放码 `E0 F0 xx` 不产生字节。这些控制字节都小于 `0x20`、等于 `0x7F`，或者最高位为 1，不会和可打印字符冲突，软件按值分派即可。Ctrl 组合键单独占 `0x81` 到 `0x9A` 这一段，避免和 Home、End 的 `0x01`、`0x05` 撞车。

CPU 侧接口：

- 读 `0x0030_0000` 取队首 ASCII，不出队；
- 读 `0x0030_0004` 看 `valid`、`overflow`；
- 写 `0x0030_0008` 任意值，队首出队。

**不要用“读数据寄存器即出队”的写法。** CPU 没有独立的 load 使能信号，`dmemaddr` 在 stall 和连续指令期间会保持多个周期，读副作用会导致一次按键被消费多次。用一次显式 store 出队最稳。

替代方案是 `lab12.pdf` 12.2.3 描述的环形缓冲区：显存之外再开 32 个扫描码槽位，CPU 写 `head`，键盘写 `tail` 和数据。这个方案更贴近指导书，但软件和总线译码都更复杂。第一版用 16 项硬件 FIFO。

### 3.6 定时器、开关、LED

- 定时器：100MHz 计数到 100000 产生 1ms 使能，32 位毫秒计数从 0 累加。`time` 命令把它换算成 `时:分:秒` 或直接显示秒数。
- 开关：`0x0050_0000` 返回 `{16'b0, SW[15:0]}`，可以留作调试选择项，例如选择启动程序。
- LED：`0x0060_0000` 锁存，低 16 位接 `LED[15:0]`。建议把 `LED[15:8]` 接调试状态，`LED[7:0]` 接最近一次键盘 ASCII，方便上板定位。
- 七段数码管：可选，用 lab09 的动态扫描模块显示 PC 或某个调试寄存器。若显示 PC，需要 CPU 输出 `pc` 调试端口，或者从 CPU 内部层次化引用，不建议为了显示 PC 改 CPU 端口。

### 3.7 串口调试（可选，最后做）

`lab12.pdf` 12.4 和 `refs/01` 给出了完整方案：`serial_tx`、`serial_rx`、`uart_port` 状态机，通过 `i`/`d`/`r`/`q` 命令加载 `main.hex`、`main_d.hex`，通过拉低 CPU 时钟暂停 CPU。

要点：

- 波特率 115200，8 位数据，奇校验，1 位停止位。`clkgen #(115200)` 产生 16 倍过采样时钟，收发都在位中间采样。
- `uart_port` 的 `clk` 用 CPU 时钟，`clk100m` 用 100MHz 给串口模块。
- 加载时用 `uart_halt` 停 CPU，并切换指令/数据存储器的地址、时钟、写使能；存储器时钟要和 UART 时钟错开半周期。
- 该功能不是验收必需项。实现前先把不带串口的系统跑通，否则调试工具本身会成为新的故障源。
- 若实现，注意 `lab12.pdf` 的提醒：Verilog 里的缓冲区不是 C 数组，不要在同一周期对同一缓冲区的多个位置读写；输出多个字符要分多个周期写。

## 4. 软件设计

### 4.1 工具链与编译

使用 `refs/04` 里的 Makefile 和 `sections.ld`。关键点：

- 编译器用 `riscv32:12` 镜像里的 `riscv64-linux-gnu-gcc`，用 `RISCV_PREFIX=riscv64-linux-gnu-` 覆盖 Makefile 的默认前缀。
- 编译参数显式带 `-march=rv32i -mabi=ilp32`。`riscv64-linux-gnu-gcc` 默认生成 RV64，不加这两个参数会得到 CPU 不支持的指令。
- 加 `-Wl,--build-id=none`。Ubuntu 22.04 的交叉 GCC 默认生成 `.note.gnu.build-id`，会被链接到地址 0，把 `.text` 推到 `0x24`，导致 ROM 的第一个字不是入口指令。`refs/04` 的示例 Makefile 没有这个选项，容器里要手动补。
- Makefile 的 hex 生成用了 `strtonum()`，需要 `gawk`。Ubuntu 默认的 `mawk` 会报 `function strtonum never defined`，`riscv32:12` 镜像里已经装了 `gawk`。
- `-static -mcmodel=medany -nostdlib -nolibc -nostartfiles -Tsections.ld`。
- 链接脚本把 `.text` 放在 `0x0000_0000`，`.rodata`、`.data`、`.bss` 放在 `0x0010_0000`，栈顶 `0x0011_fffc`，堆从 `ALIGN(1024)` 开始。
- `entry` 放在 `.text` 最前面，用内联汇编设置 `sp = 0x0011_fffc`，再调用 `main`。`main` 不允许返回，末尾死循环。
- Makefile 用 `objcopy -O verilog` 生成 `main.tmp`，再用两段 awk 分别生成 `main.hex`（代码段）和 `main_d.hex`（数据段），以及 Vivado 用的 `.coe`。
- 没有硬件乘除法时，把 `mul.c` 里的 `__mulsi3`、`__udivsi3`、`__umodsi3` 一起编译链接，否则 `*`、`/`、`%` 会链接失败。

在 `lab12/exp1_system` 目录下用容器编译：

```bash
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work/sw riscv32:12 bash -lc '
    make RISCV_PREFIX=riscv64-linux-gnu- \
         RISCV_GCC_OPTS="-march=rv32i -mabi=ilp32 -static -mcmodel=medany \
         -fvisibility=hidden -Wl,--build-id=none -Tsections.ld \
         -nostdlib -nolibc -nostartfiles"'
```

编译后用 `riscv64-linux-gnu-objdump` 检查 `main.dump`，重点看 `entry` 是否在 `0x0`、第一条是否是 `addi sp,sp,-16` 一类指令，以及 `main` 里是否有 `lui sp,0x120`。

### 4.2 地址与初始化文件的对齐

这是最容易出错的地方，写代码前先确认：

- `main.hex` 里的 `@` 地址是**字地址**，来自 `(byte_addr % 262144) / 4`。代码段从 `@00000000` 开始，正好对应 `imem[0]`。
- 数据段起始 `0x0010_0000` 经过 `% 262144` 后是 `@00000000`，不是 `@00004000`。`main_d.hex` 是一个从 0 开始的独立数据镜像，必须用 `$readmemh("main_d.hex", mem)` 装入 dmem 的 0 号单元。
- `dmem` 按 32768 字（128 KiB）定义，用 `addr[16:2]` 做索引：`0x0010_0000` 映射到 0，`0x0011_FFFC` 映射到 0x7FFF，正好覆盖 128 KiB。不要用 `addr[15:2]`，它会把 0x100000 和 0x110000 两段别名到同一片 64 KiB，数据段和栈会互相覆盖。
- `imem` 用 `addr[15:2]` 做索引，64 KiB 对应 16384 字。
- 每次改 C 代码后重新 `make`，并检查 `main.dump` 的前几条指令、`main.hex` 的 `@` 行、`main_d.hex` 是否非空。
- BRAM IP 如果用手写 `reg` 数组，综合时确认没有推断出 output register；用 IP 核时务必取消 “output register”，否则读数据晚一个周期（`lab00/实验问题指导.md`）。

### 4.3 软件结构

```
sw/
├── Makefile
├── sections.ld
├── sys.h        MMIO 地址、寄存器位定义、库函数声明
├── sys.c        putch/puts/put_dec/清屏/滚屏/getchar/时钟读取
├── main.c       entry、命令解析、hello/time/fib/help
└── mul.c        软件乘除法
```

已实现的库函数：

| 函数 | 作用 |
| :--- | :--- |
| `void vga_init(void)` | 清空 32×128 显存，起始行写 0，光标归零 |
| `void putch(char c)` | 处理 `\n`、`\b`、普通字符；行满 70 列自动换行；到底部滚屏 |
| `void puts(const char *s)` | 逐字符输出 |
| `void put_dec(int v)` | 十进制输出，支持负数 |
| `int getchar(void)` | 轮询键盘状态，有数据则读数据、写弹出寄存器、返回 ASCII；无数据返回 -1 |
| `int readline(char *buf, u32 max)` | 打印提示符，读入一行并做行编辑，返回字符数 |
| `void put_hex(u32 v, u32 digits)` | 十六进制输出，固定位数补 0 |
| `void history_dump(void)` / `history_clear(void)` | 打印、清空命令历史 |
| `u32 millis(void)` | 读毫秒定时器 |
| `int streq(const char *a, const char *b)` | 字符串比较，代替不存在的 `strcmp` |

`readline` 是命令行编辑的核心：

- 缓冲最多 79 个字符，另有一个插入位置。提示符占屏幕偏移 0 和 1，第 k 个字符占偏移 2+k，行号是偏移除以 70，列号是偏移对 70 取余。
- 编辑开始时记下提示符所在行的**物理行**，滚屏只改 `top_row`，物理行不变，所以按键触发的自动滚屏不会打乱重画。
- 在行尾追加、删除行尾字符时只重画一格；其余情况整行重画，重画时按行、列递推显存地址，不对每个字符做除法。
- 上下方向键在 8 条历史里翻找，回到第 0 层时恢复编辑到一半的内容；Tab 只补第一个词，唯一候选补全后加空格，多个候选补到公共前缀。

`scroll` 是 `sys.c` 里的静态函数，由 `newline` 和行满换行调用，不对外暴露。所有 MMIO 指针都加了 `volatile`，否则 `-O2` 下轮询循环会被优化掉。

命令解析的现实现：

1. `main` 循环用 `getchar()` 逐字符读入，遇 `\n` 结束；`\b` 删除缓冲区最后一个字符并回退屏幕光标；行满 70 列时由 `putch` 自动换行，续行不打印提示符。行缓冲 `LINE_MAX = 79`。
2. 去掉行首尾空格，按第一个空格拆成命令名和参数。
3. 分派：
   - `hello`：输出 `Hello World!`；
   - `time`：读毫秒计数，输出 `time: <秒> s`；
   - `fib n`：参数用十进制解析，迭代计算，`n > 46` 时输出 `fib: n too large, max 46`；
   - `help`：输出命令列表；
   - 其它：输出 `Unknown Command`。
4. 每条命令结束输出新的提示符 `> `。

### 4.4 板上交互约定

- `CPU_RESETN` 复位系统，屏幕清空并显示提示符。
- 键盘接开发板的 USB HID 口，PS/2 信号由该接口提供；串口调试用的 USB 口与下载线共用，两者是开发板上不同的 USB 接口，不要接错。
- VGA 接显示器，分辨率 640×480。
- 可选：`SW[0]` 选择启动后自动跑自检程序还是进入终端。

## 5. 分阶段实施计划

按顺序做，每一阶段都有独立可观察的结果。不要一次把软硬件全部接起来再上板。

### 阶段 0：确认 CPU 与工具链（已完成）

lab09 和 lab10 的 CPU 已在 25MHz 下上板复核，四个程序的结果与报告一致。lab10 自动模式下 LED 看到的是停机地址 `hang`、`hang+4`、`hang+8` 的按位或，单步模式才是单个地址，这是流水线在 EX 阶段确定跳转后冲刷的正常现象。

- 把要用的 `rv32ip.v` 复制进 `lab12/exp1_system`，保持时钟和存储器时序与 lab10 完全一致，不同时改 CPU 和总线。
- 用 Docker 的 `iverilog:12` 做仿真预检，用 `riscv32:12` 做 RV32 汇编、链接、反汇编和 C 编译；先运行 `tools/riscv32/check.sh`。
- Hello World 已编译出 `main.hex`、`main_d.hex`，`entry` 在 `0x0`，`sp` 初始化正确。
- 产出：CPU 副本、可复现的 Docker 编译命令。

### 阶段 1：显示通路（已完成，仿真通过）

- `sys_top.v` 的 VGA、字模、显存部分已写完，CPU 写显存后屏幕显示固定字符。
- 产出：`sys_top.v` 的显示部分、`sys_mmio_tb.v` 的显存读写用例。

### 阶段 2：键盘通路（已完成，仿真通过）

- 已接入 `ps2_keyboard`、`ascii_of`、16 项 FIFO 和 `0x0030_00xx` 寄存器。
- `sys_mmio_tb.v` 用 PS/2 时序发键，检查 FIFO 的 valid、ASCII 值、读不出队、写弹出寄存器后出队。
- 产出：键盘 FIFO、`sys_mmio_tb.v` 的键盘用例。

### 阶段 3：C 软件与完整终端（已完成，仿真通过）

- `sw/` 下的 `main.c`、`sys.c`、`sys.h`、`mul.c`、`Makefile`、`sections.ld` 已写完，`main.hex`、`main_d.hex` 已生成。
- `putch` 已实现换行、退格、行尾换行、滚屏；命令解析支持 `hello`、`time`、`fib n`、`help` 和未知命令。
- `sys_top_tb.v` 装入真实的 `main.hex`，用 PS/2 时序输入并检查屏幕内容，覆盖 hello、time、fib、未知命令、退格、滚屏，输出 `TEST PASSED`。
- 还需要在板上逐条验证：`hello`、`time`、`fib 10`、`fib 46`、乱输入、连续回车、退格到行首、输入超过 30 行触发滚屏。

### 阶段 4：稳定性与整理（待上板）

- 上板验收已完成，结果记录在报告 5.3 节；长时间运行和连续快速输入留作回归观察。
- 把 CPU 主频从 25MHz 试到 50MHz，记录是否稳定；不稳定就回到 25MHz。
- 清理综合警告，重点检查 `Synth 8-373`（锁存器）、`8-689`（位宽）、`8-6859`（多驱动）、`8-151`（不可达分支）。
- 核对 `README.md` 的构建文件清单、板上操作、编译命令、常见问题。
- 产出：可复现的最终工程。

### 阶段 5：可选扩展

按兴趣选做，不影响基本验收：

1. 串口调试下载（`uart_port`），见 3.7；
2. 硬件乘除法，升级到 RV32IM；
3. 定时器中断、键盘中断；
4. 控制 LED、七段数码管；
5. 简单图形界面或字符画；
6. 移植 PA 的 AM、跑 benchmark；
7. 电子琴：把 `refs/02` 的 PWM 音频接到键盘，做成键盘钢琴。

## 6. 验证计划

### 6.1 功能仿真

按 AGENTS.md 的要求，每个上板子实验都要有自检 testbench，只选代表性用例，不穷举。

**`sys_mmio_tb.v`（外设级，快）**

- 例化显存、键盘 FIFO、定时器与地址译码模块，用 TB 模拟 CPU 总线。
- 用例：
  1. 向显存写字符，读回检查；
  2. 写起始行寄存器，检查显示行计算；
  3. 用 PS/2 时序发 `a`，检查 FIFO `valid`、ASCII 值；
  4. 连续发两个字符，检查读不出队、写弹出寄存器后出队；
  5. 发 Tab、方向键、Home/End/Delete，检查送出的控制字节，并确认释放码不出队；
  6. 定时器在 1ms 后加一。
- 结束打印 `TEST PASSED` / `TEST FAILED`，`$finish`。

**`sys_top_tb.v`（全系统，慢）**

- 例化完整 `sys_top`，装入 `sw/Makefile` 生成的真实 `main.hex`、`main_d.hex`，不另写测试汇编。
- TB 按 PS/2 帧时序敲键，层次化读 `charmem` 逐行比对，覆盖：开机标题与提示符、`hello`、`fib 10`、`fib 46`、`fib 47`、`time`、未知命令、Shift 大小写、退格、行尾自动换行、滚屏。
- 行编辑部分另加：左右方向键在行内插入、Tab 补全、上下键翻历史、Home/Delete/End。
- 光标检查两项：把光标寄存器里的物理行减去 `top_row` 与当前行比较；等 VGA 扫描到光标格时，`cursor_here` 必须为 1。第二项能抓到"物理行直接和扫描行比较"的错误，滚屏后物理行是 30，屏幕上没有第 30 行，光标就画不出来。
- 第二阶段复位后单独测命令与 Ctrl 组合键，复位不会清数据段，历史命令要先 `history clear` 才能算准行号。
- 第三阶段用 `mi` + Tab 补全进入 `mines 7`，按固定种子逐格比对棋盘，覆盖翻开、洪泛、插旗、踩雷、重开、退出。
- 仿真时间约 65ms，Vivado 里不要用默认 1000ns。
- 先在本机用 iverilog 做语法和行为预检：

```bash
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work iverilog:12 \
  bash -lc "iverilog -g2012 -Wall -s sys_top_tb -o /tmp/sim.out \
            sys_top.v rv32ip.v sys_top_tb.v && vvp /tmp/sim.out"
```

  `$readmemh` 的文件要在工作目录里，仿真前把 `main.hex`、`main_d.hex`、`vga_font.txt` 拷过去。也可以用仓库的 `tools/iv.sh <相对目录> <顶层模块>`，它会挂载整个仓库并用容器里的 iverilog 编译该目录下的 `*.v`。testbench 会写 `*.vcd`，仓库根目录的 `.gitignore` 已经忽略这类文件，跑完可以删掉。

### 6.2 上板检查表

| 检查项 | 预期 |
| :--- | :--- |
| 上电/复位 | 屏幕清空，左上角显示 `> ` |
| 普通字符 | 按键立即回显，大小写和 Shift 正确 |
| 行尾 | 输入到第 70 列自动换行，续行不重复输出 `> ` |
| Enter | 光标移到下一行行首，显示新提示符 |
| Backspace | 删除前一个字符，光标回退；行首退格不越界 |
| 左右方向键 | 光标在行内移动，新字符插在光标处，右侧内容不丢 |
| Home / End / Delete | 光标跳到行首、行尾，Delete 删掉光标右边的字符 |
| Tab | `fi` 补全为 `fib `，`he` 只补到 `hel` |
| 上下方向键 | 取回上一条命令，再按下方向键恢复空行 |
| Ctrl+A / Ctrl+E / Ctrl+U | 光标跳到行首、行尾，清空当前行 |
| Ctrl+L / Ctrl+C | 清屏并保留输入；放弃当前行并显示 `^C`，跨两行的输入行也要打在对的行尾 |
| `echo` / `sw` / `led` / `history` / `clear` | 参数原样打印；开关值正确；LED 随 `led` 改变；历史带序号；清屏后只剩提示符 |
| 光标 | 紧跟最后一个字符，滚屏后仍贴着提示符，不跑行、不消失 |
| 滚屏 | 输入超过 30 行后整体上移，最下面一行清空 |
| `hello` | 输出 `Hello World!` |
| `calc 1+2*3` / `calc (1+2)*3` / `calc -7/2` | 输出 `7` / `9` / `-3` |
| `calc 10/0` | 输出 `calc: divide by zero` |
| `mem 0x300004 1` | 输出 `00300004: 00000000` |
| `mines 7` 后按回车 | 左上角洪泛出一片，第 0 行第 3 列是 `1`，第 4 列仍是 `#` |
| 扫雷踩雷 | (4,1) 是雷，翻开后显示 `*`，状态行显示 `BOOM!` |
| 扫雷 `R` / `Q` | 重开回到全 `#`，退出回到 `> ` 提示符 |
| `time` | 输出递增的时间 |
| `fib 10` | 输出 `55` |
| 未知命令 | 输出 `Unknown Command` |
| 连续快速输入 | 不丢字符，FIFO 不溢出 |
| 长时间运行 | 不花屏、不死机 |

### 6.3 常见故障定位

- **黑屏**：先确认 bitstream 下载后显示器是否闪一下；再检查 VGA 引脚、像素时钟、行场时序；把 RGB 在消隐期间清零。
- **有显示但字符错**：检查 `vga_font.txt` 的高低bit顺序、字符行列地址步长 128、字模地址 `{chr, v_line}`。
- **键盘无反应**：把 `PS2_DATA` 接 LED 看按键时是否闪烁；检查三拍同步和下降沿采样；检查 FIFO 指针。
- **按键一次出多个字符**：PS/2 采样沿或 FIFO 弹出逻辑有重复；确认读数据不出队，写寄存器才出队。
- **光标跑行或消失**：光标寄存器里是显存物理行，硬件要减 `top_row` 换成屏幕行再比较；滚屏后物理行会超过 29，直接比较就画到屏幕外了。
- **Tab、方向键没反应**：先看数码管显示的按键字节，Tab 应为 `09`，方向键应为 `11` 到 `14`；若是 `00`，说明扫描码没进 `ps2_ascii` 的对应分支。
- **程序不跑或跑飞**：看 `main.dump` 的入口地址和 `sp`；确认 `imem`/`dmem` 的 `$readmemh` 文件确实加载；确认复位后 PC 为 0。
- **板上有显示但 C 程序行为不对**：先只用汇编写显存和读键盘验证硬件，再逐步换 C；用 `main.dump` 反查编译器生成的 `sb`/`lbu` 地址。
- **综合时间长或失败**：检查可综合代码里是否误用了 `for`/`while` 循环或其它不可综合语句；检查是否把大数组写成了多驱动；确认 BRAM 没被推断成寄存器堆。

## 7. 扩展路线（摘自 labextend）

**这些内容全部放到基本要求上板检查通过、代码备份之后再做。** 优先级从低风险到高风险，具体内容见 `refs/05_系统扩展指导.md`。

1. CPU 乘法：用 FPGA DSP 实现 `mul`，除法多周期实现，升级 RV32IM。
2. 串口：115200 调试口，加载代码、查看 PC/寄存器/存储器。
3. 音频：PWM 输出、正弦表、键盘钢琴；参考 `refs/02`。
4. 图形：8 位索引色、直线/圆/矩形、加速度计控制旋转；显存放 BRAM 或 DDR。
5. 总线与存储：AXI Master、DDR2、QSPI Flash、Cache、boot loader。
6. 中断与 trap：CSR、`mret`、键盘中断、时钟中断。
7. AM 移植、xv6、PA 仙剑等极限挑战。

## 8. 实验报告计划

报告写在 `lab12/lab12实验报告.md`，按仓库模板：

1. 实验目的；
2. 实验原理：内存映射、外设读写类型、字符显存与字模、PS/2 键盘、UART 可选；
3. 实验设备；
4. 实验步骤：系统框图、内存映射表、模块划分、软件编译流程、上板步骤；
5. 实验结果：仿真波形截图（`assets/exp1_simulation.png`）、综合资源与层次图（`assets/exp1_schematic.png`）、上板终端照片或截图、每条命令的结果；
6. 思考题：只在手册明确要求时写；`lab12.pdf` 12.4.3 的调试问题可以作为思考题素材；
7. 个人思考：第一人称写踩坑和定位过程，不写套话。

写作规范按 AGENTS.md：中文全角标点、公式用 LaTeX、不在标题里写“OJ/上板”、尽量少用括号补充。

## 9. 参考资料索引

| 文件 | 内容 |
| :--- | :--- |
| `refs/README.md` | 资料出处、删除的原件、阅读顺序 |
| `refs/01_串口通信与加密解密.md` | UART 原理、帧格式、收发代码、`uart_port` 调试器、LFSR 加密实验 |
| `refs/02_音频输出实验.md` | PWM 音频原理、正弦表生成、音调步长、参考代码 |
| `refs/03_参考板级设计与RTL.md` | 旧 n4-riscv 的 AXI 拓扑、地址映射、时钟、DDR、键盘/VGA RTL、约束说明 |
| `refs/04_软件工具链与示例程序.md` | Makefile、`sections.ld`、`sys.h`/`sys.c`、`main.c`、`mul.c`、hex/coe 格式 |
| `refs/05_系统扩展指导.md` | `labextend.pdf` 的 Markdown 版：CPU、AM、音频、图形、总线、极限挑战 |
| `refs/06_lab12指导书要点.md` | `lab12.pdf` 的章节整理：外设映射、读写类型、显示与键盘、软件、UART、验收 |
| `lab12.pdf` | 实验十二原文：硬件部分、软件部分、调试工具、验收要求 |
| `ref.xdc` | Nexys A7-100T 引脚总表，XDC 只能从这里抄 |

## 10. 设计选择与遗留项

已经定稿并实现在 `exp1_system/` 里的选择：

| 项目 | 定稿 |
| :--- | :--- |
| CPU | 流水线 `rv32ip.v`，25MHz，与 lab10 相同 |
| 字符显存 | 32 行×128 列，屏幕显示 30 行×70 列，步长 128 |
| 键盘 | 硬件扫描码转 ASCII，16 项 FIFO，读数据不出队，写 `0x0030_0008` 出队 |
| 滚屏 | 硬件起始行寄存器 `top_row`，软件只清新的底行 |
| 提示符 | 只在按回车产生的逻辑行行首显示，自动换行的续行不打印 |
| 光标 | 硬件绘制，寄存器存物理行，硬件减 `top_row` 换成屏幕行 |
| 特殊键 | Tab 送 `0x09`，方向键送 `0x11` 到 `0x14`，Home/End/Delete 送 `0x01`、`0x05`、`0x7F` |
| 行编辑 | C 软件 `readline`：行内插入删除、历史、Tab 补全、Ctrl 组合键 |
| Ctrl 编码 | `0x80` 加字母序号，和 Home/End 等控制码分开 |
| 终端命令 | hello、time、fib、calc、mem、echo、led、sw、mines、history、clear、help |
| 扫雷 | 字符棋盘，LCG 种子，首翻 3×3 无雷，帧号写数码管供 testbench 同步 |
| 有符号除法 | `mul.c` 补 `__divsi3`、`__modsi3`，`calc` 的负数运算才能链接 |
| 工具链 | `riscv32:12` 容器，`riscv64-linux-gnu-gcc` 加 RV32 参数 |

还没有做、留待上板验收后再决定的项目：

1. 跨行退格：硬件版 lab11 支持，C 版 `readline` 目前退到第 0 列就停住。基本验收不要求，需要时在软件里补。
2. 主频 50MHz：先按 25MHz 验收，稳定后再试，同时改 `DIV_BITS` 和 XDC 的生成时钟 `-edges`。
3. 串口调试、中断、硬件乘除法等扩展：见第 7 节，全部放在基本要求上板通过之后。

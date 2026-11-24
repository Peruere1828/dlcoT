# exp1_system

lab12 计算机系统工程：RV32I CPU + 字符显存 + PS/2 键盘 + VGA 显示，跑 C 语言终端程序。总体设计见 `../PLAN.md`。

## 1. 构建文件清单

Vivado 工程只需要下面这些文件，顶层设为 `sys_top`：

| 文件 | 作用 |
| :--- | :--- |
| `sys_top.v` | 顶层与全部外设：时钟复位、总线译码、数据存储器、字符显存、VGA 时序、字模 ROM、PS/2 键盘、定时器、数码管 |
| `rv32ip.v` | RV32I 五段流水线 CPU，从 `lab10/exp1_cpu/rv32ip.v` 复制，内容相同 |
| `main.hex` | 指令存储器初始化，`sw/Makefile` 生成 |
| `main_d.hex` | 数据存储器初始化，`sw/Makefile` 生成，已补齐到 32768 字 |
| `vga_font.txt` | 256 字符 × 16 行字模，从 `lab11/exp1_charterm/vga_font.txt` 复制，即林同学修正过的版本 |
| `sys_top.xdc` | 引脚约束，引脚全部从仓库根目录 `ref.xdc` 复制 |

`main.hex`、`main_d.hex`、`vga_font.txt` 必须作为设计源文件一起加入工程。`$readmemh` 用的是相对路径，Vivado 在工程目录下查找这三个文件。

仿真用的 testbench 不需要加入工程：

| 文件 | 作用 |
| :--- | :--- |
| `sys_mmio_tb.v` | 外设级自检，不例化 CPU，直接模拟总线时序 |
| `sys_top_tb.v` | 全系统自检，装入真实的 `main.hex`，用 PS/2 时序敲键并检查屏幕内容 |
| `sw/` | C 软件工程 |

## 2. 板上操作

| 资源 | 用途 |
| :--- | :--- |
| `CPU_RESETN`、`BTNC` | 复位，松开后屏幕清空并显示提示符 |
| USB HID 口 | PS/2 键盘，接键盘后即可输入 |
| VGA 口 | 显示器，分辨率 640×480@60Hz |
| `LED[15]` | 约 1Hz 心跳，说明时钟与定时器在运行 |
| `LED[14:0]` | 软件写 `0x0060_0000` 的值 |
| 数码管 | 最近一次按键的 ASCII 码，软件写 `0x0060_0004`；`SW[15]` 置 1 时改为显示毫秒计数 |
| `SW[15:0]` | 软件读 `0x0050_0000` |

上电后屏幕显示：

```text
RV32I System  lab12
hello | time | fib n | help
> 
```

支持的命令：

| 命令 | 输出 |
| :--- | :--- |
| `hello` | `Hello World!` |
| `time` | `time: HH:MM:SS` |
| `fib n` | 第 n 项斐波那契数，n > 46 提示溢出 |
| `calc <表达式>` | 整数四则运算，支持括号、负号、`0x` 十六进制 |
| `mem <地址> [个数]` | 按字打印数据地址空间，默认 8 个字，最多 32 个 |
| `echo <文字>` | 原样打印参数 |
| `led <值>` | 写 `LED[14:0]`，`0x` 开头按十六进制，否则十进制 |
| `sw` | 打印拨动开关的值，如 `sw: 0xa55a` |
| `history` | 列出最近 8 条命令 |
| `history clear` | 清空历史 |
| `clear` | 清屏 |
| `help` | 命令列表 |
| 其它 | `Unknown Command` |

命令行编辑在软件里完成，按键的行为如下：

| 按键 | 作用 |
| :--- | :--- |
| 可打印字符 | 插在光标处，右侧内容右移 |
| Backspace | 删除光标左边的字符 |
| Delete | 删除光标右边的字符 |
| Left / Right | 光标在行内移动 |
| Home / End | 光标跳到行首、行尾 |
| Up / Down | 在最近 8 条命令历史里前翻、后翻，回到第 0 层恢复正在编辑的内容 |
| Tab | 补全命令名，唯一候选补全后加一个空格，多个候选补到公共前缀 |
| Ctrl+A / Ctrl+E | 光标跳到行首、行尾 |
| Ctrl+U | 清空当前行 |
| Ctrl+L | 清屏并把已经输入的内容重画在第一行 |
| Ctrl+C | 放弃当前行，显示 `^C` 并换行 |
| Enter | 执行命令 |

按住 Ctrl 再按字母时，硬件送出 `0x80 | 字母序号`，例如 Ctrl+L 是 `0x8C`、Ctrl+C 是 `0x83`。这样 Ctrl 组合键不会和 Home、End、方向键的控制码撞车，软件按值分派即可。

光标是硬件画的下划线，约 1.5Hz 闪烁。软件每次写完字符都会更新 `0x0021_0004`，硬件把寄存器里的物理行减去 `top_row` 得到屏幕行，所以滚屏之后光标仍然贴着提示符。

输入行最多 79 个字符。提示符占两列，超过 70 列的部分自动落到下一行，续行不重复打印提示符。行满或换行到了第 30 行会触发滚屏。

## 3. 内存映射

CPU 数据地址 32 位，`sys_bus` 按段译码：

| 地址 | 大小 | 设备 | 访问 |
| :--- | ---: | :--- | :--- |
| `0x0000_0000` | 64 KiB | 指令存储器 16K 字 | 取指，只读 |
| `0x0010_0000` | 128 KiB | 数据存储器 32K 字，索引 `addr[16:2]` | `lb/lbu/lh/lhu/lw`、`sb/sh/sw` |
| `0x0020_0000` | 4 KiB | 字符显存 32 行 × 128 列，按字节 | 写，读回用于调试 |
| `0x0021_0000` | 4 B | 显示起始行 `top_row` | 写 |
| `0x0021_0004` | 4 B | 光标 `{物理行[4:0], 列[6:0]}`，硬件换算成屏幕行 | 写 |
| `0x0030_0000` | 4 B | 键盘数据，低 8 位 ASCII | 读，不出队 |
| `0x0030_0004` | 4 B | 键盘状态：bit0 有数据，bit1 溢出 | 读 |
| `0x0030_0008` | 4 B | 键盘弹出 | 写任意值 |
| `0x0040_0000` | 4 B | 毫秒定时器 | 读 |
| `0x0050_0000` | 4 B | `SW[15:0]` | 读 |
| `0x0060_0000` | 4 B | `LED[14:0]` | 写 |
| `0x0060_0004` | 4 B | 数码管调试值 | 写 |

`0x0020_0000` 与 `0x0021_0000` 的高 12 位相同，所以显存按 `addr[31:16]` 译码，寄存器按整字地址精确比较。

读数据寄存器不会出队，必须再写一次 `0x0030_0008` 才弹出队首。这样处理是因为 CPU 没有独立的 load 使能，`dmemaddr` 在一次访存中会保持多个时钟周期，读副作用会导致一次按键被消费多次。

## 4. 编译软件

在 `exp1_system` 目录下运行：

```bash
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work/sw riscv32:12 \
  bash -lc 'make RISCV_PREFIX=riscv64-linux-gnu-'
```

产物 `main.hex`、`main_d.hex` 复制到上一级目录，直接加入 Vivado 工程。

清理与检查：

```bash
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work/sw riscv32:12 \
  bash -lc 'make clean RISCV_PREFIX=riscv64-linux-gnu- && make RISCV_PREFIX=riscv64-linux-gnu- && make check RISCV_PREFIX=riscv64-linux-gnu-'
```

`make check` 打印入口和两个 hex 的段地址，正常情况是：

- `main.dump` 的 `0x0` 处是 `entry`，第一条是 `addi sp,sp,-16`；
- `main.hex` 只有一个 `@00000000`；
- `main_d.hex` 只有一个 `@00000000`，后面是数据段的字。

编译参数里几个不能省：

| 参数 | 原因 |
| :--- | :--- |
| `-march=rv32i -mabi=ilp32` | 交叉 GCC 默认生成 RV64 |
| `-Wl,--build-id=none` | 否则 `.note.gnu.build-id` 落在地址 0，把 `entry` 挤到 `0x24` |
| `-fno-stack-protector` | Ubuntu 默认开 SSP，会引入 `__stack_chk_fail` |
| `-mno-relax` | 关闭链接松弛，反汇编与源程序对得上 |
| `-nostdlib -nolibc -nostartfiles` | 没有 C 库，`strcmp`、`puts` 自己实现 |

## 5. 仿真

两个 testbench 都可以先用 iverilog 预检，再在 Vivado 里跑行为仿真。

```bash
# 外设级
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work iverilog:12 \
  bash -lc "iverilog -g2012 -Wall -s sys_mmio_tb -o /tmp/sim.out sys_top.v sys_mmio_tb.v && vvp /tmp/sim.out"

# 全系统, 约 41ms 仿真时间, iverilog 约 60 秒
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work iverilog:12 \
  bash -lc "iverilog -g2012 -Wall -s sys_top_tb -o /tmp/sim.out sys_top.v rv32ip.v sys_top_tb.v && vvp /tmp/sim.out"
```

`sys_mmio_tb` 覆盖显存字节读写、起始行、光标、数据存储器 `sw/lw/sb/lbu/sh`、栈顶地址、LED 与开关、PS/2 收字符、FIFO 读出队语义、回车与断码、Tab 与 `E0` 扩展键的字节映射、Ctrl 组合键的 `0x80|序号` 编码、扩展键断码不出队、定时器递增。

`sys_top_tb` 分两个阶段。第一阶段装入真实的 C 程序，依次输入 `hello`、`fib 10`、`xyz`、按住 Shift 的 `Hello`、退格、`time`、`fib 46`、`fib 47`，连续输入 75 个字符验证行尾换行并在第二行行内改一个字符，再用左右方向键在行内插入、用 Tab 补全、用上下方向键翻历史、用 Home 和 Delete 改行，最后敲回车触发滚屏。第二阶段复位后测 `echo`、`sw`、`led`、`history`、`history clear`、`clear` 命令和 Ctrl+A/E/L/C/U 五个组合键，其中 Ctrl+C 另用一条跨两行的输入行验证，`^C` 必须打在第 2 行行尾；再测 `calc` 的四则运算、括号与除零、`mem` 读寄存器、`time` 的时:分:秒格式。命令之间逐字符比对显存内容；光标另外检查两项：读回光标的物理行并换算成屏幕行，以及等 VGA 扫描到光标格时 `cursor_here` 必须为 1。仿真时间约 41ms，Vivado 里要把默认的 1000ns 改掉。

## 6. 综合后要检查的警告

Vivado 不会因为警告停下来，综合日志里几百条警告要挑着看。下面四类必须处理干净，其余可以忽略：

| 警告码 | 含义 | 本设计的检查点 |
| :--- | :--- | :--- |
| `Synth 8-373` | 推断出锁存器 | 所有组合 `always` 块都先给默认值，`case` 都有 `default` |
| `Synth 8-689` | 位宽不匹配 | 拼接与赋值逐条对齐，`addr[16:2]` 为 15 位、`addr[15:2]` 为 14 位 |
| `Synth 8-6859` | 多驱动或组合环 | 每个 `reg` 只在一个 `always` 块里赋值 |
| `Synth 8-151` | 不可达 case 分支 | `case` 常量无重复，`ps2_ascii` 的扫描码表已逐项核对 |

综合完成后在日志里过滤：

```bash
grep -E '8-373|8-689|8-6859|8-151' vivado.log
```

同时确认 BRAM 数量：指令存储器 16K×32、数据存储器 32K×32 应当映射为 `RAMB36`，字符显存和字模 ROM 应当映射为 `RAMD32` 或 LUTRAM。如果数据存储器被拆成大量 `LUT`，说明 `ram_style` 属性没生效，需要检查读写在不在同一个时钟域。

## 7. 与 `../PLAN.md` 的差异

| PLAN 中的写法 | 实际实现 | 原因 |
| :--- | :--- | :--- |
| 全系统 testbench 用单独的 `test.hex` | 直接用 `main.hex` 跑真实 C 程序 | 少一份要维护的测试程序，覆盖范围更完整 |
| 25MHz/50MHz 可调 | 固定 25MHz | VGA 640×480@60Hz 需要 25MHz 像素时钟，CPU 用同一个分频，改主频要同时改分频参数和 XDC |
| 第一版不做光标 | 做了硬件光标 | 只加一个写寄存器和一次行号换算，终端更好用 |
| 键盘 16 项 FIFO | 同为 16 项 | 一致 |
| `0x0020_0000` 和 `0x0021_0000` 用 `addr[16]` 区分 | 显存按 `addr[31:16]`、寄存器按整字地址 | 两者高 12 位相同，整字比较更直接 |
| 键盘 Tab 与方向键可选 | 已实现，Tab 送 `0x09`、方向键送 `0x11` 到 `0x14`，Home/End/Delete 也一并支持 | Tab 的扫描码 `8'h0D` 在按键解析状态机里先判断，不能经 `ascii_of` 转换，因为 Enter 的 ASCII 也是 `0x0D` |
| 行编辑只做退格 | 左右方向键行内插入、Home/End/Delete、上下键历史、Tab 补全 | 核心是 `readline`，硬件的按键 FIFO 只负责送字节 |

## 8. 常见问题

| 现象 | 排查方向 |
| :--- | :--- |
| 黑屏 | 确认 bitstream 下载成功；查 VGA 引脚、`pclk` 的 BUFG、行场时序；消隐期间 RGB 已经是 0 |
| 有显示但字符错位 | 字模顺序、`{chr, v_line}` 地址、显存行步长 128 |
| 画面是乱码 | `main_d.hex` 没有加载或数据段地址不对；检查 `main_d.hex` 只有一个 `@00000000` |
| 键盘无反应 | `PS2_CLK`/`PS2_DATA` 接的是 USB HID 口；先看输入时数据线是否变化 |
| 一次按键出多个字符 | 读数据寄存器出队了；确认只有写 `0x0030_0008` 才弹出 |
| 光标跑行或消失 | 光标寄存器写的是显存物理行，硬件必须减去 `top_row` 再和扫描行比较；滚屏后物理行会超出 0 到 29 |
| 方向键、Tab 没反应 | 先看数码管上显示的按键字节：Tab 应为 `09`，方向键应为 `11` 到 `14`；如果是 `00`，说明扫描码没进 `ps2_ascii` 的扩展分支 |
| 程序不跑 | 看 `main.dump` 的 `entry` 是否在 `0x0`，`entry` 有没有 `lui sp,0x120`；确认 `main.hex` 已加入工程 |
| 综合或仿真报找不到 `main.hex` | `$readmemh` 用的是相对路径。行为仿真的工作目录在工程下的 `sim_1/behav/xsim`，找不到时把 6 个文件复制到该目录，或把 `sys_top.v` 里的文件名改成绝对路径 |
| 综合报锁存器 | 检查译码 `case` 有没有 `default`、读数据选择有没有默认值 |
| 仿真过了板上不对 | 先只看数码管和 LED：心跳 LED 在闪说明时钟与定时器正常，再查显存与键盘 |

# exp2_board — 单周期 CPU 上板工程

上板时把这 6 个文件加入工程，顶层设为 `cpu_top`：

| 文件 | 作用 |
| :--- | :--- |
| `cpu_top.v` | 顶层：复位、时钟选择、单步消抖、存储器映射 I/O、数码管 |
| `rv32is.v` | CPU，与 `../exp1_cpu/rv32is.v` 相同 |
| `prog_rom.v` | 4 × 256 字指令 ROM，同步读 |
| `board_dmem.v` | 4KB 数据存储器 |
| `prog.hex` | 指令 ROM 初始化文件，`make_rom.py` 生成 |
| `cpu_top.xdc` | Nexys A7-100T 引脚约束 |

## 指令 ROM 与 prog.hex

`prog_rom.v` 是同步读的块 RAM，用 `$readmemh("prog.hex", mem)` 初始化：

```verilog
(* rom_style = "block" *) reg [31:0] mem [0:1023];
initial $readmemh("prog.hex", mem);
always @(posedge clk) dout <= mem[{prog, addr}];
```

4 段程序各占 256 字，`prog.hex` 用 `@000`、`@100`、`@200`、`@300`
四个字地址分段，每段不足 256 字的部分补 `nop`，1024 个单元都有确定值。

`$readmemh` 的相对路径按工具的工作目录解析，不是按源文件所在目录，所以：

- 仿真：把 `prog.hex` 拷到 `工程名.sim/sim_1/behav/xsim/`。
- 综合：在 Add Sources 里把 `prog.hex` 一并加入工程；如果综合日志提示
  `File prog.hex ... cannot be opened`，再把它拷到 `工程名.runs/synth_1/`。

## 板上操作

- `SW[15:14]`：选择程序

| 值 | 程序 | 结果 |
| :---: | :--- | :--- |
| 00 | 累加和 $1+2+\cdots+n$ | $n(n+1)/2$ |
| 01 | 斐波那契 $F(n)$ | $F(0)=0$，$F(1)=1$ |
| 10 | 闰年判断 | 1 表示闰年，0 表示不是 |
| 11 | 素数判断 | 1 表示素数，0 表示不是 |

- `SW[13]`：1 为自动运行，约 780kHz；0 为 BTNC 单步。
- `SW[11:0]`：参数 n，三位十六进制，范围 `0x000` 到 `0xFFF`。`SW[12]` 未使用。
- `CPU_RESETN` 是板上红色 CPU RESET 按钮，低有效。上电时另有约 2.6ms 的上电复位；改参数或换程序时先设好开关，再按一下 `CPU_RESETN`，复位期间开关被锁存；`BTNC` 只用于单步，不是复位。
- `LED[15:0]` 显示 PC 低 16 位。
- 数码管以十六进制显示 32 位结果，程序把二进制结果写到 `0x2004`。

上板流程：先设好程序、模式和 n，按一下红色 `CPU_RESETN` 锁存并复位；`SW[13]=1` 时程序自动运行到停机，`SW[13]=0` 时用 `BTNC` 逐条执行；结果显示在数码管上。按住复位时 PC 和显示保持 0；松开后自动模式会马上重跑，所以显示很快恢复，想看复位过程请用单步模式。

闰年规则是能被 4 整除且不能被 100 整除，或者能被 400 整除。例如
2024 显示 `0x00000001`，1900 显示 `0x00000000`，2000 显示 `0x00000001`。
素数判断对 0 和 1 返回 `0x00000000`。

斐波那契用 8 位数码管显示 32 位十六进制，n 不超过 46 时结果在 32 位内；
n 更大时 32 位加法溢出。

## 修改程序

汇编源码是 `prog_sum.S`、`prog_fib.S`、`prog_leap.S`、`prog_prime.S`，
由 `tools/rvasm.py` 汇编。四个程序都只写二进制结果，数码管直接显示
32 位十六进制。改完后重新生成 `prog.hex`：

```bash
cd lab09/exp2_board
python3 make_rom.py
```

`rv32is.v` 是 `../exp1_cpu/rv32is.v` 的副本，改 CPU 后两边要同步：

```bash
cp ../exp1_cpu/rv32is.v rv32is.v
```

## 仿真

在 `exp2_board` 目录下运行，`prog.hex` 就在当前目录：

```bash
docker run --rm -v "$PWD":/work -w /work iverilog:12 \
  sh -c "iverilog -g2012 -o /tmp/t.out cpu_top.v rv32is.v prog_rom.v board_dmem.v cpu_top_tb.v && vvp /tmp/t.out"
```

自检覆盖 4 个程序的 21 组参数，检查结果寄存器、停机 PC、LED 和数码管段码。

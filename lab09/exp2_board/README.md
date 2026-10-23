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
| 10 | 素数判断 | 1 表示素数，0 表示不是 |
| 11 | 最大公约数 $\gcd(n,m)$ | 辗转相减 |

- `SW[13]`：1 为自动运行，约 12Hz；0 为 BTNC 单步。
- `SW[7:4]`：gcd 的第二个参数 m；`SW[3:0]`：参数 n。
- 开关在复位期间锁存，改参数或换程序后按一下 `CPU_RESETN`。
- `LED[15:0]` 显示 PC 低 16 位，数码管以十六进制显示 32 位结果。

## 修改程序

汇编源码是 `prog_sum.S`、`prog_fib.S`、`prog_prime.S`、`prog_gcd.S`，
由 `tools/rvasm.py` 汇编。改完后重新生成 `prog.hex`：

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

自检覆盖 4 个程序的 13 组参数，检查结果寄存器、停机 PC、LED 和数码管段码。

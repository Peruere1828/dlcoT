# Lab09 实验报告：RV32I 单周期 CPU

- **学号**：____________（dummy）
- **姓名**：____________（dummy）
- **日期**：2026 年 10 月

---

## 1. 实验目的

1. 理解 RV32I 六种指令格式与 37 条指令的编码方式和操作语义。
2. 掌握单周期 CPU 中控制通路与数据通路的划分方法，理解每条控制信号的作用。
3. 掌握单周期 CPU 的存储器时序设计，理解为什么指令存储器在下降沿取指、数据存储器在上升沿读、寄存器堆在下降沿写回。
4. 学会使用课程提供的单步 testbench 逐条指令检查 PC、寄存器和存储器。
5. 学会使用 RISC-V 官方测试集 rv32ui-p 对 CPU 做系统级功能验证。
6. 掌握用拨码开关输入参数、用数码管显示结果、用按钮单步执行的上板调试方法。

## 2. 实验原理

### 2.1 指令格式与立即数

RV32I 的指令长度固定为 32 位，opcode 固定在低 7 位，rd、rs1、rs2 也都在固定位置，因此译码可以直接从指令的对应位段取出：

```verilog
assign op    = instr[6:0];
assign rs1   = instr[19:15];
assign rs2   = instr[24:20];
assign rd    = instr[11:7];
assign func3 = instr[14:12];
assign func7 = instr[31:25];
```

六种格式的区别只在于立即数的切分方式。所有立即数都要符号扩展到 32 位，符号位都是 `instr[31]`：

```verilog
assign immI = {{20{instr[31]}}, instr[31:20]};
assign immU = {instr[31:12], 12'b0};
assign immS = {{20{instr[31]}}, instr[31:25], instr[11:7]};
assign immB = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
assign immJ = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
```

控制信号 `extop` 取值 `EXT_I`、`EXT_U`、`EXT_S`、`EXT_B`、`EXT_J`，分别选择 I、U、S、B、J 型立即数，再用一个多路选择器把选中的立即数送到 ALU 的 B 输入端和 PC 加法器。

### 2.2 控制通路

控制信号生成模块以 `op`、`func3`、`func7_5` 为输入，产生 `extop`、`regwr`、`alu_a_src`、`alu_b_src`、`aluctr`、`branch`、`memtoreg`、`memwr`、`memop` 九组信号，各指令对应的取值来自实验指导的表 9.10 和表 9.11。指令编码、ALU 操作和跳转类型都用 `localparam` 命名，代码里不再出现裸的二进制控制字。

`aluctr` 是一个 4 位枚举：

| ALU 控制 | 编码 | 操作 |
| :--- | :---: | :--- |
| `ALU_ADD` | 0000 | 加法 |
| `ALU_SUB` | 1000 | 减法 |
| `ALU_SLL` | 0001 | 逻辑左移 |
| `ALU_SLT` | 0010 | 带符号小于，结果置 0 或 1 |
| `ALU_SLTU` | 1010 | 无符号小于，结果置 0 或 1 |
| `ALU_XOR` | 0100 | 异或 |
| `ALU_SRL` | 0101 | 逻辑右移 |
| `ALU_SRA` | 1101 | 算术右移 |
| `ALU_OR` | 0110 | 或 |
| `ALU_AND` | 0111 | 与 |
| `ALU_LUI` | 0011 | 直接输出 B，用于 `lui` |

最高位是辅助位：加法和减法、带符号和无符号小于、逻辑右移和算术右移分别共用低 3 位，靠最高位区分。

组合逻辑的每个 `case` 都写了 `default`，每个 `if` 都有 `else`，默认值在 `always` 块开头统一赋值，避免推断出锁存器。

### 2.3 数据通路与跳转控制

数据通路以寄存器堆、ALU、数据存储器为核心。ALU 的 A 输入由 `alu_a_src` 在 `rs1` 和 `PC` 之间选择，B 输入由 `alu_b_src` 在 `rs2`、立即数和常数 4 之间选择。写回数据由 `memtoreg` 在 ALU 结果和存储器读出数据之间选择。

条件分支不另外做比较器，而是复用 ALU：`beq`、`bne`、`blt`、`bge` 令 `aluctr` 为 `ALU_SLT`，`bltu`、`bgeu` 令 `aluctr` 为 `ALU_SLTU`。`alu_zero` 在比较运算时表示两操作数相等，`alu_less` 在 `ALU_SLTU` 时取无符号小于，否则取带符号小于。

NextPC 由三条加法路径产生：`pc_plus4 = pc + 4`、`pc_plus_imm = pc + imm`、`rs1_imm = rs1 + imm`，再由跳转类型选择：

| Branch | 编码 | 含义 | 跳转条件 | NextPC |
| :--- | :---: | :--- | :--- | :--- |
| `BR_NONE` | 000 | 非跳转 | — | PC+4 |
| `BR_JAL` | 001 | `jal` | 无条件 | PC+imm |
| `BR_JALR` | 010 | `jalr` | 无条件 | rs1+imm，最低位清零 |
| `BR_BEQ` | 100 | `beq` | zero | 成立 PC+imm，否则 PC+4 |
| `BR_BNE` | 101 | `bne` | !zero | 成立 PC+imm，否则 PC+4 |
| `BR_LT` | 110 | `blt`、`bltu` | less | 成立 PC+imm，否则 PC+4 |
| `BR_GE` | 111 | `bge`、`bgeu` | !less | 成立 PC+imm，否则 PC+4 |

`jalr` 的目标地址要与 `0xfffffffe` 相与，清掉最低位：

```verilog
BR_JALR: nextpc = {rs1_imm[31:1], 1'b0};
```

### 2.4 单周期时序

上板的 CPU 只有一个时钟：100MHz 四分频出的 `cpu_clk`，周期 40ns，高电平 10ns，经 BUFG 送到全局时钟网。指令 ROM、数据存储器和 CPU 本体都挂在这根时钟上，没有反相时钟网，也没有第二个时钟域。一个 10ns 高电平执行一条指令，边沿分工如下：

| 时刻 | 动作 |
| :--- | :--- |
| 上升沿 $t=0$ | 数据存储器读出整字，锁进内部读寄存器 |
| 高电平 $0\sim10\mathrm{ns}$ | 读出的字经 `memop` 选择、符号扩展和写回选择器，送到寄存器堆的写数据端 |
| 下降沿 $t=10\mathrm{ns}$ | PC 装入 NextPC；指令 ROM 按 NextPC 读出 `mem[NextPC]`；寄存器堆写回上一条指令的结果；数据存储器按 `memop` 改写字节或半字；结果寄存器锁存写往 `0x2004` 的数据 |
| 低电平 $10\mathrm{ns}\sim40\mathrm{ns}$ | 取出的指令经译码、立即数生成、读寄存器堆、ALU 运算，得到访存地址，等下一个上升沿 |

三段路径的时间预算不同。上升沿到下降沿只有 10ns，里面只有“读出的字向下游走”这一段：`memop` 选择、符号扩展和写回选择器，没有取指也没有 ALU，这是余量最小的一段。下降沿到上升沿有 30ns，整条取指译码、读寄存器堆和 ALU 通路都在这段里，Load/Store 的访存地址也要在这 30ns 内算出来。下降沿到下降沿是一个完整周期 40ns，NextPC 的加法属于这一段。

寄存器堆的写和 PC 的装发生在同一个下降沿。寄存器堆的读是异步的，新值在同沿之后立刻可读，而它参与的 NextPC 要等下一个下降沿才被 PC 采样，中间隔了一整个周期，所以两个动作同沿并不冲突。指令存储器的地址则必须用 NextPC 而不是 PC：取指和 PC 更新在同一个下降沿，PC 的输出要等这个沿之后才更新，而存储器在沿上采样地址，只能拿到沿之前就稳定的 NextPC。

由此带来一个容易忽略的细节：testbench 在 reset 有效期间也要产生一个下降沿，让 NextPC 的 0 被送入指令存储器，把 0 地址的指令取出来。否则 reset 释放后的第一个下降沿会拿未初始化的指令去算 NextPC，PC 会变成不定值。实验指导中“nextPC 在 reset 有效时应保持为全零”说的就是这件事。

load 指令有两段路径要分开看。数据存储器在上升沿读出，读出的字要在同一个高电平的 10ns 内完成 `memop` 选择、符号扩展和写回选择，赶上下一个下降沿写进寄存器堆；这是 10ns 段。load/store 的访存地址要在低电平的 30ns 内由译码、寄存器读和 ALU 算出来，赶上下一个上升沿的存储器读取；这是 30ns 段，也是实验指导提到的 Load 地址生成关键路径。25MHz 下两段都要有正余量。

### 2.5 上板顶层与存储器映射

上板工程按功能拆成 `cpu_top.v`、`rv32is.v`、`prog_rom.v`、`board_dmem.v` 四个 Verilog 文件，顶层只负责时钟、复位、存储器映射和外设。为了用同一份 ROM 演示多个程序，4 段程序各占 256 字的 ROM 空间，由 `SW[15:14]` 选择。机器码由 `make_rom.py` 从 `prog_*.S` 汇编成 `prog.hex`，`prog_rom.v` 用 `$readmemh` 在 `initial` 中把 1024 个字装进 BRAM。

指令 ROM、数据存储器和 CPU 共用同一个 `cpu_clk`，取指的下降沿做在 `prog_rom` 内部，顶层不需要另外产生反相时钟。自动模式下 `cpu_clk` 连续运行，复位期间 PC 保持 0，ROM 已经在读 0 地址；单步模式下复位脉冲给出一个下降沿，也能把 0 地址的指令预先读出来。第一次取指不会拿到未初始化的数据。

CPU 的数据地址空间划分为：

| 地址 | 访问方式 | 功能 |
| :--- | :--- | :--- |
| `0x0000_0000` 起 4KB | 读写 | 数据 RAM |
| `0x0000_2000` | 只读 | `{16'b0, SW[15:0]}` |
| `0x0000_2004` | 只写 | 结果寄存器，二进制，送数码管以十六进制显示 |

程序用 `lw` 从 `0x2000` 读参数，用 `sw` 把二进制结果写到 `0x2004`，这样 CPU 不需要额外的端口，演示程序也保持了纯 RV32I 指令。顶层把 `result_reg` 的 8 个 nibble 轮流送到数码管，以十六进制显示。

## 3. 实验设备

- 电脑一台，安装 Xilinx Vivado 2022.1
- Digilent Nexys A7-100T 开发板一块
- USB 下载线一根

## 4. 实验步骤

### 4.1 CPU 模块

两个在线评测题目使用相同的端口定义，都提交 `lab09/exp1_cpu/rv32is.v` 这一个文件。模块端口与课程 testbench 一致：

```verilog
module rv32is(
    input  wire        clock,
    input  wire        reset,
    output wire [31:0] imemaddr,
    input  wire [31:0] imemdataout,
    output wire        imemclk,
    output wire [31:0] dmemaddr,
    input  wire [31:0] dmemdataout,
    output wire [31:0] dmemdatain,
    output wire        dmemrdclk,
    output wire        dmemwrclk,
    output wire [2:0]  dmemop,
    output wire        dmemwe,
    output wire [31:0] dbgdata
);
```

`dbgdata` 直接输出 PC，单步 testbench 用它检查跳转是否正确。寄存器堆单独写成 `rv32i_regfile` 子模块，实例名保持为 `myregfile`，数组名为 `regs`，这样 testbench 里的 `mycpu.myregfile.regs[10]` 可以直接访问。

时钟连接关系为：

```verilog
assign imemclk  = ~clock;   // 下降沿取指
assign dmemrdclk = clock;   // 上升沿读数据存储器
assign dmemwrclk = ~clock;  // 下降沿写数据存储器
```

寄存器堆的写时钟直接接 `clock`，其内部在 `negedge WrClk` 写入。

### 4.2 单步功能仿真

自检 testbench 写在 `lab09/exp1_cpu/rv32is_tb.v`，使用课程提供的 `add`、`alu`、`mem`、`branch` 四段小程序，逐条指令检查寄存器、存储器和 PC。每个检查点只在出错时打印 MISMATCH，最后输出 `TEST PASSED` 或 `TEST FAILED`。

`add` 验证三条基本运算指令；`alu` 覆盖加减、逻辑、移位、带符号与无符号比较；`mem` 覆盖 `lw`、`sw`、`lb`、`lbu`、`lh`、`lhu`、`sb`、`sh` 以及符号扩展；`branch` 覆盖六条条件分支和 `jal`、`jalr`。通过 `iverilog` 验证通过。

### 4.3 官方测试集

官方测试集 testbench 写在 `lab09/exp1_cpu/cpu_batch_tb.v`，按顺序运行 rv32ui-p 开头的 38 个用例。每个用例把指令文件装入指令存储器、把 `_d.hex` 装入数据存储器，然后单步运行到取指得到 `0xdead10cc` 为止。最后检查 `a0`：

- `0x00c0ffee` 表示通过；
- `0xdeaddead` 表示测试代码自己判错；
- 其他值或超过 10000 周期表示运行异常。

`dmem.v`、`testmem.v`、`testdmem.v` 是课程提供的存储器模型，只用于仿真，不参与在线评测提交。

### 4.4 上板顶层

上板文件为 `lab09/exp2_board/` 下的 `cpu_top.v`、`rv32is.v`、`prog_rom.v`、`board_dmem.v`、`prog.hex` 和 `cpu_top.xdc`。把这 6 个文件加入工程、把顶层设为 `cpu_top` 即可综合。`rv32is.v` 与在线评测提交的 CPU 文件相同，`prog_rom.v` 是同步读的指令 ROM，`prog.hex` 是它的初始化文件，`board_dmem.v` 是 4KB 数据存储器。

板上资源分配：

- `SW[15:14]` 选择程序，00 累加和、01 斐波那契、10 闰年判断、11 素数判断；
- `SW[13]` 为 1 时自动运行，25MHz，为 0 时用 `BTNC` 单步；
- `SW[11:0]` 是参数 n，范围 `0x000` 到 `0xFFF`，`SW[12]` 未使用；
- `CPU_RESETN` 是板上红色的 CPU RESET 按钮，低有效。上电时另有约 2.6ms 的上电复位；改参数或换程序时先设好开关，再按一下 `CPU_RESETN`，复位期间开关被锁存，运行中改开关不影响本次结果；`BTNC` 只用于单步，不是复位；
- 自动模式下 CPU 时钟是连续的 25MHz，复位在 `cpu_clk` 域同步释放；单步模式下没有运行时钟，复位时产生一个 10ns 脉冲，把 PC 和结果寄存器清 0；
- `LED[15:0]` 显示 PC 的低 16 位；
- 8 位数码管以十六进制显示 32 位结果。

上板操作顺序是：先用 `SW[15:14]` 选程序、`SW[13]` 选自动或单步、`SW[11:0]` 输入 n，再按一下红色 `CPU_RESETN`；`SW[13]=1` 时程序自动运行到停机，`SW[13]=0` 时每按一次 `BTNC` 执行一条指令；最后读数码管上的 8 位十六进制结果。25MHz 下程序在几百微秒内跑完，自动模式通常只能看到最终结果；按住复位时 PC 和显示保持 0，松开后自动模式会马上重跑；想看复位过程可以切到单步模式。

四段汇编程序分别是 `prog_sum.S`、`prog_fib.S`、`prog_leap.S`、`prog_prime.S`，由 `make_rom.py` 调用 `tools/rvasm.py` 汇编，生成 `prog.hex`。每段 256 字，用 `@000`、`@100`、`@200`、`@300` 分段，不足 256 字的部分补 nop。修改程序后执行：

```bash
cd lab09/exp2_board
python3 make_rom.py
```

四个程序都只把二进制结果写到 `0x2004`，顶层把 32 位结果按 4 位一组送到数码管，以十六进制显示。斐波那契在 n 不超过 46 时结果在 32 位内，8 位数码管可以完整显示；n 更大时 32 位加法溢出。闰年程序检查 n 能否被 4、100、400 整除：能被 4 整除且不能被 100 整除，或者能被 400 整除时结果为 1。素数判断没有除法指令，用重复减法求余数；闰年的 100 和 400 也用同样的方法。两段程序都处理了 0 和 1 的边界情况。

上板顶层自检写在 `cpu_top_tb.v`，把上电复位、自动运行分频、数码管扫描分频都通过参数缩小，逐个程序检查结果寄存器、停机 PC、LED 和数码管段码，共 21 个用例。

## 5. 实验结果

### 5.1 单步功能仿真

四个小程序全部通过，`TEST PASSED`。四段程序覆盖了整数运算、访存、条件分支和跳转的代表性指令，寄存器、存储器与 PC 的检查点均与预期一致。

### 5.2 官方测试集

38 个 rv32ui-p 用例全部通过：

```text
TEST PASSED: 38/38
```

全部用例合计 11390 个周期，批量 testbench 的仿真时间约 230us，在 Vivado 的行为仿真里可以直接运行。用例列表：

```text
simple  add    addi   and    andi   auipc  beq    bge    bgeu
blt     bltu   bne    jal    jalr   lb     lbu    lh     lhu
lui     lw     or     ori    sb     sh     sll    slli   slt
slti    sltiu  sltu   sra    srai   srl    srli   sub    sw
xor     xori
```

`exp2_board/rv32is.v` 与在线评测模块是同一份代码，也用同一套测试集跑过，结果同样是 38/38。

### 5.3 上板

`cpu_top_tb.v` 的 21 个用例全部通过。这组测试检查四个程序共 21 组参数的结果寄存器、停机 PC、LED 和数码管段码。整段仿真约 383us，仿真时长需要调到 1000us 才能完整观察。

![exp2 上板顶层行为仿真](assets/exp2_simulation.png)

四个程序和十六进制显示已在 25MHz 版本的实物上板验证。各程序的结果：

| 程序 | 参数 | 数码管显示 |
| :--- | :--- | :--- |
| 累加和 | n=0、10、2024 | 0x00000000、0x00000037、0x001F4514 |
| 斐波那契 | n=0、1、10、20、39、46 | 0x00000000、0x00000001、0x00000037、0x00001A6D、0x03C50EA2、0x6D73E55F |
| 闰年判断 | 2024、1900、2000、2023、400 | 0x00000001、0x00000000、0x00000001、0x00000000、0x00000001 |
| 素数判断 | 0、1、2、4、7、15、97 | 0x00000000、0x00000000、0x00000001、0x00000000、0x00000001、0x00000000、0x00000001 |

上板时按住红色 `CPU_RESETN`，PC 和结果寄存器立即清 0，数码管显示 `0x00000000`；松开后自动模式会马上重跑程序，所以显示很快回到计算结果，单步模式则停在 PC=0，等按 `BTNC` 才执行第一条指令。改参数或换程序后，先设好开关，再按一下 `CPU_RESETN` 重新锁存。自动运行结束后 `LED[15:0]` 稳定显示停机地址的低 16 位：累加和为 `0x0028`，斐波那契为 `0x0034`，闰年判断为 `0x0044`，素数判断为 `0x0048`。单步模式下每按一次 `BTNC` 执行一条指令，PC 一般加 4，遇到跳转时按程序给出的目标地址变化。以上结果已在 25MHz 版本上板复核，数码管显示和停机 PC 均与表中一致。

### 5.4 综合资源与时序

整个设计占 1305 个 LUT、144 个触发器、44 个 LUTRAM 和 2 个 Block RAM，IO 用了 51 个，占用 24.29%。LUT 占 2.06%，Block RAM 占 1.48%，LUTRAM 和触发器都在 0.3% 以下。

![exp2 资源占用](assets/exp2_utilization.png)

分层报告可以看出资源去向：CPU 本体占 267 个 LUT 和 32 个触发器，寄存器堆用掉了全部 44 个 LUTRAM；指令 ROM 占 995 个 LUT 和 1 个 Block RAM；数据存储器占 27 个 LUT 和 1 个 Block RAM。

![exp2 资源分层](assets/exp2_hierarchy.png)

时序报告里有两根时钟：100MHz 的系统时钟和顶层四分频得到的 `cpu_clk`。后者由逻辑产生，Vivado 不会自动把它当成时钟根，必须在 XDC 里用 `create_generated_clock` 按真实波形声明，周期 40ns、高电平 10ns，写成 `-edges {1 3 9}`。不声明的话 CPU 内部的寄存器全部记成 `no_clock`，时序报告里那点正余量只覆盖 100MHz 那一小块。

![exp2 时钟报告](assets/exp2_clock.png)

声明之后 931 个端点全部参与分析，两个域都没有违例：WNS 3.102ns、WHS 0.103ns、最差脉宽余量 4.500ns，TNS 和 THS 都是 0，工具结论是所有时序约束都已满足。

![exp2 时序报告](assets/exp2_timing.png)

Intra-Clock Paths 把两根时钟分开看：

| 时钟 | WNS | WHS | WPWS |
| :--- | ---: | ---: | ---: |
| `cpu_clk` | 3.102ns，上升沿到下降沿 | 0.323ns | 8.750ns |
| `sys_clk_pin` | 3.128ns，上升沿到上升沿 | 0.103ns | 4.500ns |

WNS 3.102ns 落在 `cpu_clk` 的上升沿到下降沿，也就是 2.4 节里的 10ns 高电平段：dmem 读出经 `memop` 选择、符号扩展和写回选择器，送到寄存器堆的写数据端。Load 地址生成属于下降沿到上升沿的 30ns 段，不是最差路径，余量更大；完整周期 40ns 的 NextPC 路径余量也更大。

整体 WHS 0.103ns 来自 100MHz 的 `sys_clk_pin` 域，`cpu_clk` 自己的 hold 余量是 0.323ns。两者都为正，但余量都不大，后面再改 RTL 或约束时要重新检查 hold。脉宽余量的整体最差值 4.500ns 也来自 100MHz 域，`cpu_clk` 的脉宽余量是 8.750ns。

![exp2 时钟路径](assets/exp2_clockpath.png)

## 6. 思考题

### 6.1 为什么有 S、B、U、J 这些不同的立即数编码

不同指令有不同的寄存器需求，因此有不同的立即数编码。奇怪的编码顺序是为了让 opcode/rs1/rs2/rd 的位置不变以便共享指令解码模块。

### 6.2 为什么代码段和数据段只取地址的低 18 位仍然正确

代码段和数据段都落在 `0x8000_0000` 开始的一个 256KB 区域内，程序不会对超过这段区域的地方进行读写，因此是正确的。

### 6.3 数据存储器用 4 片 8 位存储器实现时如何生成 4 个初始化文件

每个 32 位字按小端顺序拆成 4 个字节：`word[7:0]` 给第 0 片，`word[15:8]` 给第 1 片，`word[23:16]` 给第 2 片，`word[31:24]` 给第 3 片。生成时对原始 hex 文件逐字读取，把每个字的对应字节写到对应片的初始化文件，地址保持不变。这样 4 片存储器按字节写使能各自写入，拼起来就是一个完整的 32 位字。

### 6.4 为什么正常的 RV32I 指令序列中不会出现 0xdead10cc

`0xdead10cc` 的低 7 位是 `0x4c`，即 `1001100`，该 opcode 不存在，所以它不是一条合法指令。

## 个人思考

参考手册说的自己配了一个 riscv 的容器：

```Dockerfile
FROM ubuntu:22.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        binutils-riscv64-linux-gnu \
        qemu-user \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
```

方便之后测 CPU 了。

写 CPU 基本上就是按照原理接线，为了避免魔法数字可以用 `localparam`（类似 C 语言的 `enum`），增加一些易读性。然后几个时钟要仔细想一下是上升还是下降沿做动作。

这次比较麻烦的是时序报告。上板自己测没问题，不过 Vivado 一直报 `no_clock`，我一开始没注意，直到写实验报告才注意。后来才发现 CPU 的时钟是逻辑产生的，工具根本没分析它，~~请教神谕机后~~用生成时钟 `create_generated_clock` 把真实波形写进去之后，把 ROM 也挂到 CPU 时钟上，再让时钟走 BUFG，才把 `no_clock` 给解决掉。
`timescale 1ns / 1ps

// cpu_top.v : lab09 单周期 RV32I CPU 上板顶层
//
// 上板文件: cpu_top.v + rv32is.v + prog_rom.v + board_dmem.v + prog.hex
//           + cpu_top.xdc
//   rv32is.v     CPU (与 exp1_cpu/rv32is.v 相同)
//   prog_rom.v   4 x 256 字指令 ROM, 同步读, 由 prog.hex 初始化
//   board_dmem.v 4KB 数据存储器
//   prog.hex     由 make_rom.py 从 prog_*.S 生成
//
// 板上操作:
//   SW[15:14]  选择程序: 00 累加和 1..n / 01 斐波那契 F(n)
//                        10 闰年判断 / 11 素数判断
//   SW[13]     1 = 自动运行（约 780kHz），0 = BTNC 单步
//   SW[11:0]   参数 n（3 位十六进制，0x000~0xFFF）
//   SW[12]     未使用
//   开关在复位期间被锁存；改参数或换程序后按一下 CPU_RESETN
//   CPU_RESETN 低有效复位；BTNC 单步执行一条指令
//   LED[15:0]  显示当前 PC 的低 16 位
//   AN/HEX     8 位数码管以十六进制显示 32 位结果
//
// 存储器映射（CPU 的数据地址）:
//   0x0000_0000 起 4KB   数据 RAM
//   0x0000_2000          只读: {16'b0, 锁存的 SW[15:0]}
//   0x0000_2004          只写: 结果寄存器（二进制），送数码管以十六进制显示
//
// 时序设计:
//   CPU 侧只有一根时钟 cpu_clk: 由 100MHz 分频得到, 周期 1.28us, 高电平
//   10ns, 经 BUFG 送到全局时钟网. 指令 ROM、数据存储器和 CPU 本体都接这根
//   时钟, 没有反相时钟网, 也没有第二个时钟域. 一个 10ns 脉冲就是一条指令:
//
//     上升沿 t=0         数据存储器读出整字, 锁进内部读寄存器 rdword
//     高电平 0~10ns      rdword 经 memop 选择与符号扩展、写回选择器,
//                        送到寄存器堆的写数据端
//     下降沿 t=10ns      PC 装入 NextPC
//                        prog_rom 按 NextPC 读出 mem[NextPC]
//                        寄存器堆写回上一条指令的结果
//                        board_dmem 按 memop 改写字节或半字
//                        result_reg 锁存写往 0x2004 的数据
//     低电平 10ns~1.28us 取出的指令经译码、立即数、读寄存器堆、ALU 运算,
//                        得到访存地址, 等下一个上升沿
//
//   三段路径的时间预算不同. 上升沿到下降沿只有 10ns, 里面只有"读出的字向下
//   游走"这一段: memop 选择、符号扩展和写回选择器, 没有取指也没有 ALU, 这是
//   唯一受压的一段, 时序报告里的 WNS 就落在这里. 下降沿到上升沿有 1.27us,
//   整条取指译码和 ALU 通路都在这段里. 下降沿到下降沿是一个完整周期 1.28us,
//   NextPC 的加法属于这一段.
//
//   寄存器堆的写和 PC 的装发生在同一个下降沿. 寄存器堆的读是异步的, 新值
//   在同沿之后立刻可读, 而它参与的 NextPC 要等下一个下降沿才被 PC 采样,
//   所以两个动作同沿并不冲突. PC 采样地址, 只能用沿前就稳定的值, 这就是
//   指令 ROM 的地址必须接 NextPC 而不是 PC 的原因.
//
//   XDC 用 create_generated_clock -edges {1 3 257} 把这根逻辑时钟按真实
//   波形声明在 BUFG 的输出上. 不声明的话 Vivado 把它当成无时钟信号, CPU
//   内部寄存器全部记成 no_clock, 时序报告等于没做.

module cpu_top #(
    parameter integer POR_BITS  = 19,   // 上电复位计数位宽
    parameter integer DIV_BITS  = 7,    // 自动运行分频, 2^7 * 10ns ≈ 1.28us
    parameter integer DB_BITS   = 17,   // BTNC 消抖计数位宽
    parameter integer SCAN_BITS = 15    // 数码管扫描分频
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,
    input  wire [15:0] SW,
    output wire [7:0]  AN,
    output wire [7:0]  HEX,
    output wire [15:0] LED
);

    // 复位: 上电复位 + 按键复位, 复位期间锁存开关

    reg [POR_BITS-1:0] por_cnt;
    initial por_cnt = {POR_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        if (!por_cnt[POR_BITS-1])
            por_cnt <= por_cnt + 1'b1;

    wire reset_raw = (~CPU_RESETN) | (~por_cnt[POR_BITS-1]);

    // 同步复位, 并在复位开始时产生一个 10ns 的 CPU 复位脉冲.
    // 单步模式下 CPU 本身没有时钟沿, 必须靠这个脉冲把 PC 和结果寄存器清 0.
    reg reset_meta, reset_sync, reset_d;
    initial begin
        reset_meta = 1'b0;
        reset_sync = 1'b0;
        reset_d    = 1'b0;
    end
    always @(posedge CLK100MHZ) begin
        reset_meta <= reset_raw;
        reset_sync <= reset_meta;
        reset_d    <= reset_sync;
    end

    wire reset       = reset_sync;
    wire reset_pulse = reset & ~reset_d;

    reg [15:0] sw_r;
    initial sw_r = 16'b0;
    always @(posedge CLK100MHZ)
        if (reset)
            sw_r <= SW;

    wire [1:0] prog_sel = sw_r[15:14];

    // BTNC 消抖与单步脉冲

    reg [DB_BITS-1:0] db_cnt;
    reg btn_sync, btn_clean, btn_clean_d;
    initial begin
        db_cnt      = {DB_BITS{1'b0}};
        btn_sync    = 1'b0;
        btn_clean   = 1'b0;
        btn_clean_d = 1'b0;
    end

    always @(posedge CLK100MHZ) begin
        btn_sync <= BTNC;
        if (btn_sync != btn_clean) begin
            if (&db_cnt) begin
                btn_clean <= btn_sync;
                db_cnt    <= {DB_BITS{1'b0}};
            end else
                db_cnt <= db_cnt + 1'b1;
        end else
            db_cnt <= {DB_BITS{1'b0}};
        btn_clean_d <= btn_clean;
    end

    wire step_pulse = btn_clean & ~btn_clean_d;   // 按下一次, 一个时钟周期

    // 自动运行的慢速节拍

    reg [DIV_BITS-1:0] div_cnt;
    initial div_cnt = {DIV_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire auto_pulse = &div_cnt;

    // 一个脉冲就是一个完整的 CPU 周期: 上升沿读数据存储器, 下降沿写回.
    // 复位时改用 reset_pulse, 这样单步模式下按复位也能清 PC.
    //
    // 脉冲经过 BUFG 送到全局时钟网: 脉宽仍是 10ns, 时钟树从 BUFG 开始,
    // 不再是 LUT 直接驱动时钟脚. 周期 1.28us 在 XDC 里按生成时钟声明.
    wire run_pulse   = sw_r[13] ? auto_pulse : step_pulse;
    wire clk_pulse   = reset ? reset_pulse : run_pulse;

    wire cpu_clk;

`ifdef __ICARUS__
    // iverilog 没有 Xilinx 原语, 直接透传
    assign cpu_clk = clk_pulse;
`else
    BUFG u_bufg_cpu (
        .I (clk_pulse),
        .O (cpu_clk)
    );
`endif

    // CPU 与存储器

    wire [31:0] imemaddr, imemdataout;
    wire        imemclk;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire        dmemrdclk, dmemwrclk, dmemwe;
    wire [2:0]  dmemop;
    wire [31:0] dbgdata;

    rv32is u_cpu (
        .clock        (cpu_clk),
        .reset        (reset),
        .imemaddr     (imemaddr),
        .imemdataout  (imemdataout),
        .imemclk      (imemclk),
        .dmemaddr     (dmemaddr),
        .dmemdataout  (dmemdataout),
        .dmemdatain   (dmemdatain),
        .dmemrdclk    (dmemrdclk),
        .dmemwrclk    (dmemwrclk),
        .dmemop       (dmemop),
        .dmemwe       (dmemwe),
        .dbgdata      (dbgdata)
    );

    // 指令 ROM: 与 CPU 共用 cpu_clk, 在下降沿按 NextPC 取指
    // (实验指导 9.2.4 的方案: 存储器在下降沿读, 而 PC 的输出要等这个沿之后
    //  才更新, 所以地址必须用 PC 的输入 NextPC)
    prog_rom u_rom (
        .clk  (cpu_clk),
        .prog (prog_sel),
        .addr (imemaddr[9:2]),
        .dout (imemdataout)
    );

    // 数据存储器与存储器映射 I/O

    localparam [31:0] IO_BASE   = 32'h0000_2000;         // I/O 页起始地址
    localparam [31:0] IO_SW     = IO_BASE;               // 只读: 锁存的开关
    localparam [31:0] IO_RESULT = IO_BASE + 32'd4;       // 只写: 结果寄存器

    wire io_hit = (dmemaddr[31:12] == IO_BASE[31:12]);   // 0x2000 ~ 0x2FFF
    wire io_sw  = (dmemaddr == IO_SW);
    wire io_res = (dmemaddr == IO_RESULT);

    wire [31:0] ram_dataout;

    // 结果寄存器: 程序用 sw 指令写到 0x2004, 内容是二进制结果
    // 写入时刻与 CPU 的下降沿对齐, 和存储器写在同一个沿上
    reg [31:0] result_reg;
    initial result_reg = 32'b0;
    always @(negedge cpu_clk) begin
        if (reset)
            result_reg <= 32'b0;
        else if (dmemwe && io_res)
            result_reg <= dmemdatain;
    end

    // 数据存储器直接接 cpu_clk: 读在上升沿, 写在下降沿, 内部各自取一个沿,
    // 这样就不需要在顶层再反相出一个时钟网
    board_dmem u_dmem (
        .addr    (dmemaddr),
        .datain  (dmemdatain),
        .rdclk   (cpu_clk),
        .wrclk   (cpu_clk),
        .memop   (dmemop),
        .we      (dmemwe & ~io_hit),
        .dataout (ram_dataout)
    );

    assign dmemdataout = io_sw  ? {16'b0, sw_r} :
                         io_res ? result_reg   :
                                  ram_dataout;

    // 数码管动态扫描

    reg [SCAN_BITS+2:0] scan_cnt;
    initial scan_cnt = {(SCAN_BITS+3){1'b0}};
    always @(posedge CLK100MHZ)
        scan_cnt <= scan_cnt + 1'b1;

    wire [2:0] dig = scan_cnt[SCAN_BITS+2:SCAN_BITS];

    // 当前位的十六进制数字

    reg [3:0] nib;
    always @(*) begin
        case (dig)
            3'd0:    nib = result_reg[3:0];
            3'd1:    nib = result_reg[7:4];
            3'd2:    nib = result_reg[11:8];
            3'd3:    nib = result_reg[15:12];
            3'd4:    nib = result_reg[19:16];
            3'd5:    nib = result_reg[23:20];
            3'd6:    nib = result_reg[27:24];
            default: nib = result_reg[31:28];
        endcase
    end

    // AN[n] = 0 选中第 n 位数码管
    wire [7:0] an = ~(8'b0000_0001 << dig);

    // 共阳极段码 seg[6:0] = {G,F,E,D,C,B,A}, 低电平点亮
    localparam [6:0] SEG_0 = 7'b1000000,
                     SEG_1 = 7'b1111001,
                     SEG_2 = 7'b0100100,
                     SEG_3 = 7'b0110000,
                     SEG_4 = 7'b0011001,
                     SEG_5 = 7'b0010010,
                     SEG_6 = 7'b0000010,
                     SEG_7 = 7'b1111000,
                     SEG_8 = 7'b0000000,
                     SEG_9 = 7'b0010000,
                     SEG_A = 7'b0001000,
                     SEG_B = 7'b0000011,
                     SEG_C = 7'b1000110,
                     SEG_D = 7'b0100001,
                     SEG_E = 7'b0000110,
                     SEG_F = 7'b0001110;

    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'h0:    seg7 = SEG_0;
                4'h1:    seg7 = SEG_1;
                4'h2:    seg7 = SEG_2;
                4'h3:    seg7 = SEG_3;
                4'h4:    seg7 = SEG_4;
                4'h5:    seg7 = SEG_5;
                4'h6:    seg7 = SEG_6;
                4'h7:    seg7 = SEG_7;
                4'h8:    seg7 = SEG_8;
                4'h9:    seg7 = SEG_9;
                4'hA:    seg7 = SEG_A;
                4'hB:    seg7 = SEG_B;
                4'hC:    seg7 = SEG_C;
                4'hD:    seg7 = SEG_D;
                4'hE:    seg7 = SEG_E;
                default: seg7 = SEG_F;
            endcase
        end
    endfunction

    assign AN  = an;
    assign HEX = {seg7(nib), 1'b1};
    assign LED = dbgdata[15:0];

endmodule

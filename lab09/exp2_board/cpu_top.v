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
// 指令 ROM 是同步 BRAM, 用 100MHz 连续读 PC. 复位期间 PC 一直为 0,
// BRAM 已经在读 0 地址, 第一次取指不会拿到未初始化的输出. 地址用 PC
// 而不是 NextPC, 避免组合的 NextPC 在连续时钟下把取指地址越推越远.

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

    // 一个脉冲就是一个完整的 CPU 周期: 上升沿读数据存储器, 下降沿写回
    // 复位时改用 reset_pulse, 这样单步模式下按复位也能清 PC
    wire run_pulse = sw_r[13] ? auto_pulse : step_pulse;
    wire cpu_clk   = reset ? reset_pulse : run_pulse;

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

    // 指令 ROM: 100MHz 连续读, 地址用 PC(dbgdata) 的低 10 位
    prog_rom u_rom (
        .clk  (CLK100MHZ),
        .prog (prog_sel),
        .addr (dbgdata[9:2]),
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
    reg [31:0] result_reg;
    initial result_reg = 32'b0;
    always @(posedge dmemwrclk) begin
        if (reset)
            result_reg <= 32'b0;
        else if (dmemwe && io_res)
            result_reg <= dmemdatain;
    end

    board_dmem u_dmem (
        .addr    (dmemaddr),
        .datain  (dmemdatain),
        .rdclk   (dmemrdclk),
        .wrclk   (dmemwrclk),
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

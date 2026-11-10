`timescale 1ns / 1ps

// cpu_top.v : lab10 五段流水线 CPU 上板顶层
//
// 上板文件: cpu_top.v + rv32ip.v + prog_rom.v + board_dmem.v + prog.hex
//           + cpu_top.xdc
//   rv32ip.v     五段流水线 CPU (与 exp1_cpu/rv32ip.v 相同)
//   prog_rom.v   4 x 256 字指令 ROM, 同步读, 由 prog.hex 初始化
//   board_dmem.v 4KB 数据存储器
//   prog.hex     由 make_rom.py 从 prog_*.S 生成
//
// 板上操作:
//   SW[15:14]  选择程序: 00 累加和 1..n / 01 斐波那契 F(n)
//                        10 闰年判断 / 11 素数判断
//   SW[13]     1 = 自动运行（默认 25MHz，可改 50MHz），0 = BTNC 单步
//   SW[12]     显示选择: 0 显示程序结果, 1 显示已经执行的 CPU 周期数
//   SW[11:0]   参数 n（3 位十六进制，0x000~0xFFF）
//   开关在复位期间被锁存；改参数或换程序后按一下 CPU_RESETN
//   CPU_RESETN 低有效复位；BTNC 单步执行一个 CPU 周期
//   LED[15:0]  显示当前 PC 的低 16 位
//   AN/HEX     8 位数码管以十六进制显示结果或周期数
//
// 存储器映射（CPU 的数据地址）:
//   0x0000_0000 起 4KB   数据 RAM
//   0x0000_2000          只读: {16'b0, 锁存的 SW[15:0]}
//   0x0000_2004          只写: 结果寄存器，送数码管以十六进制显示
//
// 一个 CPU 周期由一对沿组成: 上升沿读指令/读数据存储器/写回寄存器,
// 下降沿更新 PC 和四个段寄存器. 单步时一个 BTNC 脉冲正好是一个完整周期,
// 所以每按一次流水线前进一段, 可以看到 PC 和结果一步步变化.
//
// 指令 ROM、数据存储器和 CPU 共用同一个 cpu_clk. 复位期间 PC 一直为 0,
// 复位脉冲的那个上升沿就把 0 地址的指令读出来了, 第一次取指不会拿到
// 未初始化的输出. ROM 的地址用 PC, 这个值在上一个下降沿就已经稳定,
// 上升沿读出后由下降沿的 IF/ID 采样, 不需要第二个时钟域.
//
// 频率配置:
//   25MHz: DIV_BITS=2, 100MHz 四分频, 周期 40ns, 10ns 高/30ns 低,
//          XDC 用 -edges {1 3 9}
//   50MHz: DIV_BITS=1, 100MHz 二分频, 周期 20ns, 10ns 高/10ns 低,
//          XDC 用 -edges {1 3 5}
//   两个参数必须同时改, 否则 Vivado 分析的时钟和板上实际时钟不一致.

module cpu_top #(
    parameter integer POR_BITS  = 19,   // 上电复位计数位宽
    parameter integer DIV_BITS  = 2,    // 25MHz: 2^2 * 10ns = 40ns; 50MHz 改成 1
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
    // 单步模式下 CPU 本身没有时钟沿, 必须靠这个脉冲把 PC 和段寄存器清 0.
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

    // 自动运行的 CPU 时钟: div_cnt 每 10ns 加一, 计满时输出一个 10ns
    // 高电平. DIV_BITS=2 时周期 40ns, 25MHz; DIV_BITS=1 时周期 20ns, 50MHz.

    reg [DIV_BITS-1:0] div_cnt;
    initial div_cnt = {DIV_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire auto_pulse = &div_cnt;

    // 自动模式: 连续时钟, 复位期间也持续运行, 由 CPU 内部的同步复位清状态.
    // 单步模式: 复位时给一个 10ns 脉冲, 之后每按一次 BTNC 给一个 10ns 脉冲.
    wire clk_pulse = sw_r[13] ? auto_pulse
                              : (reset ? reset_pulse : step_pulse);

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

    // 自动模式下复位释放与 cpu_clk 的下降沿对齐. 单步模式没有连续时钟,
    // 直接使用复位脉冲. cpu_reset 只送给 CPU 时钟域内的逻辑.
    reg [1:0] cpu_rst_sync;
    initial cpu_rst_sync = 2'b11;
    always @(negedge cpu_clk)
        cpu_rst_sync <= {cpu_rst_sync[0], reset};

    wire cpu_reset = reset | (sw_r[13] ? cpu_rst_sync[1] : 1'b0);

    // 周期计数: 数码管可以显示到目前为止执行了多少个 CPU 周期

    reg [31:0] cyc_cnt;
    initial cyc_cnt = 32'b0;
    always @(posedge cpu_clk) begin
        if (cpu_reset)
            cyc_cnt <= 32'b0;
        else
            cyc_cnt <= cyc_cnt + 1'b1;
    end

    // CPU 与存储器

    wire [31:0] imemaddr, imemdataout;
    wire        imemclk;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire        dmemrdclk, dmemwrclk, dmemwe;
    wire [2:0]  dmemop;
    wire [31:0] dbgdata;

    rv32ip u_cpu (
        .clock        (cpu_clk),
        .reset        (cpu_reset),
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

    // 指令 ROM: 与 CPU 共用 cpu_clk, 上升沿读 PC, 下降沿由 IF/ID 采样
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
        if (cpu_reset)
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

    // 数码管显示内容: SW[12] 选择结果或周期数

    wire [31:0] disp = sw_r[12] ? cyc_cnt : result_reg;

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
            3'd0:    nib = disp[3:0];
            3'd1:    nib = disp[7:4];
            3'd2:    nib = disp[11:8];
            3'd3:    nib = disp[15:12];
            3'd4:    nib = disp[19:16];
            3'd5:    nib = disp[23:20];
            3'd6:    nib = disp[27:24];
            default: nib = disp[31:28];
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

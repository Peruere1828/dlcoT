`timescale 1ns / 1ps
//==============================================================================
// cpu_top.v : lab09 单周期 RV32I CPU 上板顶层（自包含，单文件）
//
// 板上操作:
//   SW[15:14]  选择程序: 00 累加和 1..n / 01 斐波那契 F(n)
//                        10 素数判断 / 11 gcd(n, m)
//   SW[13]     1 = 自动运行（约 12Hz），0 = BTNC 单步
//   SW[7:4]    第二个参数 m（仅 gcd 使用）
//   SW[3:0]    参数 n
//   开关在复位期间被锁存；改参数或换程序后按一下 CPU_RESETN
//   CPU_RESETN 低有效复位；BTNC 单步执行一条指令
//   LED[15:0]  显示当前 PC 的低 16 位
//   AN/HEX     8 位数码管以十六进制显示结果
//
// 存储器映射（CPU 的数据地址）:
//   0x0000_0000 起 4KB   数据 RAM
//   0x0000_2000          只读: {16'b0, 锁存的 SW[15:0]}
//   0x0000_2004          只写: 结果寄存器，送数码管显示
//
// 指令 ROM 为组合读取，地址取 PC 而不是 NextPC。指令存储器若用同步
// BRAM，上电后到第一次取指之间输出是未初始化的，PC 可能被错误指令带跑；
// 组合 ROM 没有这个问题，慢速单步下时序也更容易满足。
//
// 文件内包含 rv32is / rv32i_regfile / prog_rom / board_dmem，单独这一个
// .v 加 cpu_top.xdc 即可综合上板。ROM 数据由 make_rom.py 生成。
//==============================================================================
module cpu_top #(
    parameter integer POR_BITS  = 19,   // 上电复位计数位宽
    parameter integer DIV_BITS  = 23,   // 自动运行分频, 2^23 * 10ns ≈ 84ms
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

    //--------------------------------------------------------------------------
    // 复位: 上电复位 + 按键复位, 复位期间锁存开关
    //--------------------------------------------------------------------------
    reg [POR_BITS-1:0] por_cnt;
    initial por_cnt = {POR_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        if (!por_cnt[POR_BITS-1])
            por_cnt <= por_cnt + 1'b1;

    wire reset = (~CPU_RESETN) | (~por_cnt[POR_BITS-1]);

    reg [15:0] sw_r;
    initial sw_r = 16'b0;
    always @(posedge CLK100MHZ)
        if (reset)
            sw_r <= SW;

    wire [1:0] prog_sel = sw_r[15:14];

    //--------------------------------------------------------------------------
    // BTNC 消抖与单步脉冲
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // 自动运行的慢速节拍
    //--------------------------------------------------------------------------
    reg [DIV_BITS-1:0] div_cnt;
    initial div_cnt = {DIV_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire auto_pulse = &div_cnt;

    // 一个脉冲就是一个完整的 CPU 周期: 上升沿读数据存储器, 下降沿写回
    wire cpu_clk = sw_r[13] ? auto_pulse : step_pulse;

    //--------------------------------------------------------------------------
    // CPU 与存储器
    //--------------------------------------------------------------------------
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

    // 指令 ROM: 组合读, 地址用 PC(dbgdata) 的低 10 位
    prog_rom u_rom (
        .prog (prog_sel),
        .addr (dbgdata[9:2]),
        .dout (imemdataout)
    );

    //--------------------------------------------------------------------------
    // 数据存储器与存储器映射 I/O
    //--------------------------------------------------------------------------
    wire io_hit = (dmemaddr[31:12] == 20'h00002);   // 0x0000_2000 ~ 0x0000_2FFF
    wire io_sw  = (dmemaddr == 32'h0000_2000);
    wire io_res = (dmemaddr == 32'h0000_2004);

    wire [31:0] ram_dataout;

    // 结果寄存器: 程序用 sw 指令写到 0x2004
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

    //--------------------------------------------------------------------------
    // 数码管动态扫描
    //--------------------------------------------------------------------------
    reg [SCAN_BITS+2:0] scan_cnt;
    initial scan_cnt = {(SCAN_BITS+3){1'b0}};
    always @(posedge CLK100MHZ)
        scan_cnt <= scan_cnt + 1'b1;

    wire [2:0] dig = scan_cnt[SCAN_BITS+2:SCAN_BITS];

    reg [3:0] nib;
    reg [7:0] an;
    always @(*) begin
        case (dig)
            3'd0: begin nib = result_reg[3:0];   an = 8'b1111_1110; end
            3'd1: begin nib = result_reg[7:4];   an = 8'b1111_1101; end
            3'd2: begin nib = result_reg[11:8];  an = 8'b1111_1011; end
            3'd3: begin nib = result_reg[15:12]; an = 8'b1111_0111; end
            3'd4: begin nib = result_reg[19:16]; an = 8'b1110_1111; end
            3'd5: begin nib = result_reg[23:20]; an = 8'b1101_1111; end
            3'd6: begin nib = result_reg[27:24]; an = 8'b1011_1111; end
            default: begin nib = result_reg[31:28]; an = 8'b0111_1111; end
        endcase
    end

    // 共阳极段码 seg[6:0] = {G,F,E,D,C,B,A}, 低电平点亮
    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'h0:    seg7 = 7'b1000000;
                4'h1:    seg7 = 7'b1111001;
                4'h2:    seg7 = 7'b0100100;
                4'h3:    seg7 = 7'b0110000;
                4'h4:    seg7 = 7'b0011001;
                4'h5:    seg7 = 7'b0010010;
                4'h6:    seg7 = 7'b0000010;
                4'h7:    seg7 = 7'b1111000;
                4'h8:    seg7 = 7'b0000000;
                4'h9:    seg7 = 7'b0010000;
                4'hA:    seg7 = 7'b0001000;
                4'hB:    seg7 = 7'b0000011;
                4'hC:    seg7 = 7'b1000110;
                4'hD:    seg7 = 7'b0100001;
                4'hE:    seg7 = 7'b0000110;
                default: seg7 = 7'b0001110;
            endcase
        end
    endfunction

    assign AN  = an;
    assign HEX = {seg7(nib), 1'b1};
    assign LED = dbgdata[15:0];

endmodule


//==============================================================================
// 指令 ROM: 4 个 256 字程序, 组合读
// 数据由 make_rom.py 从 prog_*.S 汇编生成
//==============================================================================
module prog_rom(
    input  wire [1:0] prog,
    input  wire [7:0] addr,
    output reg  [31:0] dout
);

    always @(*) begin
        case (prog)
            // ==== BEGIN ROM (generated by make_rom.py) ====
            2'd0: begin  // rom0: prog_sum.S, 累加和 1+2+...+n, 10 words
                case (addr)
                    8'd  0: dout = 32'h000022b7;
                    8'd  1: dout = 32'h0002a583;
                    8'd  2: dout = 32'h00f5f593;
                    8'd  3: dout = 32'h00000513;
                    8'd  4: dout = 32'h00058863;
                    8'd  5: dout = 32'h00b50533;
                    8'd  6: dout = 32'hfff58593;
                    8'd  7: dout = 32'hfe059ce3;
                    8'd  8: dout = 32'h00a2a223;
                    8'd  9: dout = 32'h0000006f;
                    default: dout = 32'h00000013;  // nop
                endcase
            end

            2'd1: begin  // rom1: prog_fib.S, 斐波那契 F(n), 13 words
                case (addr)
                    8'd  0: dout = 32'h000022b7;
                    8'd  1: dout = 32'h0002a583;
                    8'd  2: dout = 32'h00f5f593;
                    8'd  3: dout = 32'h00000513;
                    8'd  4: dout = 32'h00100613;
                    8'd  5: dout = 32'h00058c63;
                    8'd  6: dout = 32'h00c506b3;
                    8'd  7: dout = 32'h00060513;
                    8'd  8: dout = 32'h00068613;
                    8'd  9: dout = 32'hfff58593;
                    8'd 10: dout = 32'hfe0598e3;
                    8'd 11: dout = 32'h00a2a223;
                    8'd 12: dout = 32'h0000006f;
                    default: dout = 32'h00000013;  // nop
                endcase
            end

            2'd2: begin  // rom2: prog_prime.S, 素数判断, 18 words
                case (addr)
                    8'd  0: dout = 32'h000022b7;
                    8'd  1: dout = 32'h0002a583;
                    8'd  2: dout = 32'h00f5f593;
                    8'd  3: dout = 32'h00000513;
                    8'd  4: dout = 32'h00200313;
                    8'd  5: dout = 32'h0265c663;
                    8'd  6: dout = 32'h02658263;
                    8'd  7: dout = 32'h02b35063;
                    8'd  8: dout = 32'h00058393;
                    8'd  9: dout = 32'h00038e63;
                    8'd 10: dout = 32'h0063c663;
                    8'd 11: dout = 32'h406383b3;
                    8'd 12: dout = 32'hff5ff06f;
                    8'd 13: dout = 32'h00130313;
                    8'd 14: dout = 32'hfe5ff06f;
                    8'd 15: dout = 32'h00100513;
                    8'd 16: dout = 32'h00a2a223;
                    8'd 17: dout = 32'h0000006f;
                    default: dout = 32'h00000013;  // nop
                endcase
            end

            2'd3: begin  // rom3: prog_gcd.S, 最大公约数 gcd(a,b), 17 words
                case (addr)
                    8'd  0: dout = 32'h000022b7;
                    8'd  1: dout = 32'h0002a503;
                    8'd  2: dout = 32'h00f57513;
                    8'd  3: dout = 32'h0002a583;
                    8'd  4: dout = 32'h0045d593;
                    8'd  5: dout = 32'h00f5f593;
                    8'd  6: dout = 32'h02050063;
                    8'd  7: dout = 32'h02058063;
                    8'd  8: dout = 32'h00b50e63;
                    8'd  9: dout = 32'h00b54663;
                    8'd 10: dout = 32'h40b50533;
                    8'd 11: dout = 32'hff5ff06f;
                    8'd 12: dout = 32'h40a585b3;
                    8'd 13: dout = 32'hfedff06f;
                    8'd 14: dout = 32'h00058513;
                    8'd 15: dout = 32'h00a2a223;
                    8'd 16: dout = 32'h0000006f;
                    default: dout = 32'h00000013;  // nop
                endcase
            end
            // ==== END ROM ====
            default: dout = 32'h0000_0013;
        endcase
    end

endmodule


//==============================================================================
// 数据存储器: 4KB, 读时钟上升沿读整字, 写时钟上升沿按 memop 写
// 写字节/半字时用上升沿读出的旧字拼装, 先读后改再整字写
//==============================================================================
module board_dmem(
    input  wire [31:0] addr,
    input  wire [31:0] datain,
    input  wire        rdclk,
    input  wire        wrclk,
    input  wire [2:0]  memop,
    input  wire        we,
    output wire [31:0] dataout
);

    reg [31:0] mem [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'b0;
    end

    wire [9:0] idx = addr[11:2];
    wire [1:0] off = addr[1:0];

    reg [31:0] rdword;
    always @(posedge rdclk)
        rdword <= mem[idx];

    reg [31:0] rdata;
    always @(*) begin
        case (memop)
            3'b010:  rdata = rdword;
            3'b001:  rdata = off[1] ? {{16{rdword[31]}}, rdword[31:16]}
                                    : {{16{rdword[15]}}, rdword[15:0]};
            3'b101:  rdata = off[1] ? {16'b0, rdword[31:16]}
                                    : {16'b0, rdword[15:0]};
            3'b000:  rdata = (off == 2'b00) ? {{24{rdword[7]}},  rdword[7:0]}
                            : (off == 2'b01) ? {{24{rdword[15]}}, rdword[15:8]}
                            : (off == 2'b10) ? {{24{rdword[23]}}, rdword[23:16]}
                                             : {{24{rdword[31]}}, rdword[31:24]};
            3'b100:  rdata = (off == 2'b00) ? {24'b0, rdword[7:0]}
                            : (off == 2'b01) ? {24'b0, rdword[15:8]}
                            : (off == 2'b10) ? {24'b0, rdword[23:16]}
                                             : {24'b0, rdword[31:24]};
            default: rdata = rdword;
        endcase
    end

    assign dataout = rdata;

    reg [31:0] wdata;
    always @(*) begin
        case (memop)
            3'b010:  wdata = datain;
            3'b001, 3'b101:
                wdata = off[1] ? {datain[15:0], rdword[15:0]}
                               : {rdword[31:16], datain[15:0]};
            3'b000, 3'b100:
                wdata = (off == 2'b00) ? {rdword[31:8],   datain[7:0]}
                      : (off == 2'b01) ? {rdword[31:16],  datain[7:0], rdword[7:0]}
                      : (off == 2'b10) ? {rdword[31:24],  datain[7:0], rdword[15:0]}
                                       : {datain[7:0],    rdword[23:0]};
            default: wdata = datain;
        endcase
    end

    always @(posedge wrclk)
        if (we)
            mem[idx] <= wdata;

endmodule


//==============================================================================
// rv32is: RV32I 单周期 CPU
// 时序: 下降沿 PC <- NextPC / 指令存储器取指 / 寄存器堆写回 / 数据存储器写,
//       上升沿读数据存储器, 组合逻辑完成译码、立即数、寄存器读、ALU
//==============================================================================
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

    reg  [31:0] pc;
    initial pc = 32'b0;

    wire [31:0] instr   = imemdataout;
    wire [6:0]  op      = instr[6:0];
    wire [4:0]  rs1     = instr[19:15];
    wire [4:0]  rs2     = instr[24:20];
    wire [4:0]  rd      = instr[11:7];
    wire [2:0]  func3   = instr[14:12];
    wire        func7_5 = instr[30];

    wire [31:0] immI = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] immU = {instr[31:12], 12'b0};
    wire [31:0] immS = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] immB = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] immJ = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    reg  [2:0] extop;
    reg        regwr;
    reg        alua_src;
    reg  [1:0] alubsrc;
    reg  [3:0] aluctr;
    reg  [2:0] branch;
    reg        memtoreg;
    reg        memwr;
    reg  [2:0] memop;

    always @(*) begin
        extop    = 3'b000;
        regwr    = 1'b0;
        alua_src = 1'b0;
        alubsrc  = 2'b00;
        aluctr   = 4'b0000;
        branch   = 3'b000;
        memtoreg = 1'b0;
        memwr    = 1'b0;
        memop    = 3'b010;

        case (op)
            7'b0110111: begin                       // lui
                extop   = 3'b001;
                regwr   = 1'b1;
                alubsrc = 2'b01;
                aluctr  = 4'b0011;
            end
            7'b0010111: begin                       // auipc
                extop   = 3'b001;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b01;
                aluctr  = 4'b0000;
            end
            7'b0010011: begin                       // 立即数运算
                extop   = 3'b000;
                regwr   = 1'b1;
                alubsrc = 2'b01;
                case (func3)
                    3'b000: aluctr = 4'b0000;
                    3'b010: aluctr = 4'b0010;
                    3'b011: aluctr = 4'b1010;
                    3'b100: aluctr = 4'b0100;
                    3'b110: aluctr = 4'b0110;
                    3'b111: aluctr = 4'b0111;
                    3'b001: aluctr = 4'b0001;
                    3'b101: aluctr = func7_5 ? 4'b1101 : 4'b0101;
                    default: aluctr = 4'b0000;
                endcase
            end
            7'b0110011: begin                       // 寄存器运算
                regwr   = 1'b1;
                alubsrc = 2'b00;
                case (func3)
                    3'b000: aluctr = func7_5 ? 4'b1000 : 4'b0000;
                    3'b001: aluctr = 4'b0001;
                    3'b010: aluctr = 4'b0010;
                    3'b011: aluctr = 4'b1010;
                    3'b100: aluctr = 4'b0100;
                    3'b101: aluctr = func7_5 ? 4'b1101 : 4'b0101;
                    3'b110: aluctr = 4'b0110;
                    3'b111: aluctr = 4'b0111;
                    default: aluctr = 4'b0000;
                endcase
            end
            7'b1101111: begin                       // jal
                extop   = 3'b100;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b10;
                aluctr  = 4'b0000;
                branch  = 3'b001;
            end
            7'b1100111: begin                       // jalr
                extop   = 3'b000;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b10;
                aluctr  = 4'b0000;
                branch  = 3'b010;
            end
            7'b1100011: begin                       // 条件分支
                extop   = 3'b011;
                alubsrc = 2'b00;
                case (func3)
                    3'b000: begin aluctr = 4'b0010; branch = 3'b100; end
                    3'b001: begin aluctr = 4'b0010; branch = 3'b101; end
                    3'b100: begin aluctr = 4'b0010; branch = 3'b110; end
                    3'b101: begin aluctr = 4'b0010; branch = 3'b111; end
                    3'b110: begin aluctr = 4'b1010; branch = 3'b110; end
                    3'b111: begin aluctr = 4'b1010; branch = 3'b111; end
                    default: branch = 3'b000;
                endcase
            end
            7'b0000011: begin                       // 取数
                extop    = 3'b000;
                regwr    = 1'b1;
                alubsrc  = 2'b01;
                memtoreg = 1'b1;
                memop    = func3;
            end
            7'b0100011: begin                       // 存数
                extop   = 3'b010;
                alubsrc = 2'b01;
                memwr   = 1'b1;
                memop   = func3;
            end
            default: ;
        endcase
    end

    reg [31:0] imm;
    always @(*) begin
        case (extop)
            3'b000:  imm = immI;
            3'b001:  imm = immU;
            3'b010:  imm = immS;
            3'b011:  imm = immB;
            3'b100:  imm = immJ;
            default: imm = immI;
        endcase
    end

    wire [31:0] busA, busB, busW;

    rv32i_regfile myregfile(
        .WrClk (clock),
        .RegWr (regwr & ~reset),
        .Ra    (rs1),
        .Rb    (rs2),
        .Rw    (rd),
        .busW  (busW),
        .busA  (busA),
        .busB  (busB)
    );

    wire [31:0] alu_a = alua_src ? pc : busA;
    reg  [31:0] alu_b;

    always @(*) begin
        case (alubsrc)
            2'b00:   alu_b = busB;
            2'b01:   alu_b = imm;
            2'b10:   alu_b = 32'd4;
            default: alu_b = busB;
        endcase
    end

    wire [4:0]  shamt = alu_b[4:0];
    wire [31:0] sum   = alu_a + alu_b;
    wire [31:0] diff  = alu_a - alu_b;
    wire [31:0] shra  = $signed(alu_a) >>> shamt;
    wire        lt_s  = $signed(alu_a) < $signed(alu_b);
    wire        lt_u  = alu_a < alu_b;

    reg [31:0] alu_result;
    always @(*) begin
        case (aluctr[2:0])
            3'b000:  alu_result = aluctr[3] ? diff : sum;
            3'b001:  alu_result = alu_a << shamt;
            3'b010:  alu_result = aluctr[3] ? {31'b0, lt_u} : {31'b0, lt_s};
            3'b011:  alu_result = alu_b;
            3'b100:  alu_result = alu_a ^ alu_b;
            3'b101:  alu_result = aluctr[3] ? shra : (alu_a >> shamt);
            3'b110:  alu_result = alu_a | alu_b;
            3'b111:  alu_result = alu_a & alu_b;
            default: alu_result = 32'b0;
        endcase
    end

    wire alu_zero = (aluctr[2:0] == 3'b010) ? (alu_a == alu_b)
                                            : (alu_result == 32'b0);
    wire alu_less = aluctr[3] ? lt_u : lt_s;

    assign busW = memtoreg ? dmemdataout : alu_result;

    wire [31:0] pc_plus4    = pc + 32'd4;
    wire [31:0] pc_plus_imm = pc + imm;
    wire [31:0] rs1_imm     = busA + imm;

    reg [31:0] nextpc;
    always @(*) begin
        case (branch)
            3'b001:  nextpc = pc_plus_imm;
            3'b010:  nextpc = {rs1_imm[31:1], 1'b0};
            3'b100:  nextpc = alu_zero ? pc_plus_imm : pc_plus4;
            3'b101:  nextpc = alu_zero ? pc_plus4 : pc_plus_imm;
            3'b110:  nextpc = alu_less ? pc_plus_imm : pc_plus4;
            3'b111:  nextpc = alu_less ? pc_plus4 : pc_plus_imm;
            default: nextpc = pc_plus4;
        endcase
    end

    wire [31:0] nextpc_mux = reset ? 32'b0 : nextpc;

    assign imemaddr = nextpc_mux;
    assign imemclk  = ~clock;

    always @(negedge clock) begin
        if (reset)
            pc <= 32'b0;
        else
            pc <= nextpc_mux;
    end

    assign dmemaddr   = alu_result;
    assign dmemdatain = busB;
    assign dmemop     = memop;
    assign dmemwe     = memwr & ~reset;
    assign dmemrdclk  = clock;
    assign dmemwrclk  = ~clock;
    assign dbgdata    = pc;

endmodule


//==============================================================================
// 寄存器堆: 两读一写, x0 恒为 0, 下降沿写入
//==============================================================================
module rv32i_regfile(
    input  wire        WrClk,
    input  wire        RegWr,
    input  wire [4:0]  Ra,
    input  wire [4:0]  Rb,
    input  wire [4:0]  Rw,
    input  wire [31:0] busW,
    output wire [31:0] busA,
    output wire [31:0] busB
);

    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    assign busA = (Ra == 5'd0) ? 32'b0 : regs[Ra];
    assign busB = (Rb == 5'd0) ? 32'b0 : regs[Rb];

    always @(negedge WrClk) begin
        if (RegWr && (Rw != 5'd0))
            regs[Rw] <= busW;
    end

endmodule

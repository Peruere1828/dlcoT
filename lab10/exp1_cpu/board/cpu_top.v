//=======================================================================
// lab10 单周期 RV32I CPU
// 时序: 周期以时钟下降沿为起点 / 终点
//   - nextpc 为组合逻辑, 下降沿同时装入 PC 与指令存储器地址缓冲
//   - 指令存储器在下降沿读取 (地址用 nextpc, 不能用 PC)
//   - 数据存储器在上升沿读, 下降沿写
//   - 目的寄存器与数据存储器在下一个下降沿写入
// 端口与讲义 10.7 的 rv32is 一致
//=======================================================================
module rv32is(
    input         clock,
    input         reset,
    output [31:0] imemaddr,
    input  [31:0] imemdataout,
    output        imemclk,
    output [31:0] dmemaddr,
    input  [31:0] dmemdataout,
    output [31:0] dmemdatain,
    output        dmemrdclk,
    output        dmemwrclk,
    output [2:0]  dmemop,
    output        dmemwe,
    output [31:0] dbgdata
);

    wire [31:0] instr = imemdataout;

    //---------------- 控制信号 ----------------
    wire [2:0] extop;
    wire       regwr;
    wire       alu_asrc;
    wire [1:0] alu_bsrc;
    wire [3:0] aluctr;
    wire [2:0] branch;
    wire       memtoreg;
    wire       memwr;
    wire [2:0] memop;

    wire [31:0] imm;

    //---------------- 数据通路 ----------------
    reg  [31:0] PC;
    wire [31:0] rs1data, rs2data;
    wire [31:0] alu_result;
    wire        zero, less;
    wire [31:0] wb_data;

    // 立即数
    immgen u_immgen (.instr(instr), .extop(extop), .imm(imm));

    // 控制
    ctrl u_ctrl (
        .instr(instr),
        .extop(extop), .regwr(regwr),
        .alu_asrc(alu_asrc), .alu_bsrc(alu_bsrc), .aluctr(aluctr),
        .branch(branch), .memtoreg(memtoreg), .memwr(memwr), .memop(memop)
    );

    // 寄存器堆
    regfile u_regfile (
        .WrClk(clock), .RegWr(regwr),
        .Ra(instr[19:15]), .Rb(instr[24:20]), .Rw(instr[11:7]),
        .busW(wb_data),
        .busA(rs1data), .busB(rs2data)
    );

    // ALU 输入选择
    wire [31:0] alu_a = alu_asrc ? PC : rs1data;
    reg  [31:0] alu_b;
    always @(*) begin
        case (alu_bsrc)
            2'b00:   alu_b = rs2data;
            2'b01:   alu_b = imm;
            2'b10:   alu_b = 32'd4;
            default: alu_b = rs2data;
        endcase
    end

    alu u_alu (
        .A(alu_a), .B(alu_b), .ALUctr(aluctr),
        .Result(alu_result), .Zero(zero), .Less(less)
    );

    //---------------- 下一条 PC ----------------
    reg pc_asrc, pc_bsrc;
    always @(*) begin
        case (branch)
            3'b000:  begin pc_asrc = 1'b0; pc_bsrc = 1'b0; end
            3'b001:  begin pc_asrc = 1'b1; pc_bsrc = 1'b0; end
            3'b010:  begin pc_asrc = 1'b1; pc_bsrc = 1'b1; end
            3'b100:  begin pc_asrc = zero;        pc_bsrc = 1'b0; end
            3'b101:  begin pc_asrc = ~zero;       pc_bsrc = 1'b0; end
            3'b110:  begin pc_asrc = less;        pc_bsrc = 1'b0; end
            3'b111:  begin pc_asrc = ~less;       pc_bsrc = 1'b0; end
            default: begin pc_asrc = 1'b0; pc_bsrc = 1'b0; end
        endcase
    end

    wire [31:0] pc_a = pc_asrc ? imm : 32'd4;
    wire [31:0] pc_b = pc_bsrc ? rs1data : PC;
    wire [31:0] nextpc = pc_a + pc_b;

    always @(negedge clock) begin
        if (reset)
            PC <= 32'b0;
        else
            PC <= nextpc;
    end

    //---------------- 存储器接口 ----------------
    assign imemaddr  = reset ? 32'd0 : nextpc;
    assign imemclk   = clock;

    assign dmemaddr  = alu_result;
    assign dmemdatain= rs2data;
    assign dmemwe    = memwr;
    assign dmemop    = memop;
    assign dmemrdclk = clock;
    assign dmemwrclk = clock;

    assign wb_data   = memtoreg ? dmemdataout : alu_result;
    assign dbgdata   = PC;

endmodule


//-----------------------------------------------------------------------
module immgen(
    input  [31:0] instr,
    input  [2:0]  extop,
    output reg [31:0] imm
);
    always @(*) begin
        case (extop)
            3'b000:  imm = {{20{instr[31]}}, instr[31:20]};
            3'b001:  imm = {instr[31:12], 12'b0};
            3'b010:  imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            3'b011:  imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            3'b100:  imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm = 32'b0;
        endcase
    end
endmodule


//-----------------------------------------------------------------------
module ctrl(
    input  [31:0] instr,
    output reg [2:0] extop,
    output reg       regwr,
    output reg       alu_asrc,
    output reg [1:0] alu_bsrc,
    output reg [3:0] aluctr,
    output reg [2:0] branch,
    output reg       memtoreg,
    output reg       memwr,
    output reg [2:0] memop
);
    wire [6:0] op   = instr[6:0];
    wire [2:0] f3   = instr[14:12];
    wire       f7b5 = instr[30];

    always @(*) begin
        // 默认等价于空指令
        extop    = 3'b000;
        regwr    = 1'b0;
        alu_asrc = 1'b0;
        alu_bsrc = 2'b00;
        aluctr   = 4'b0000;
        branch   = 3'b000;
        memtoreg = 1'b0;
        memwr    = 1'b0;
        memop    = 3'b010;

        case (op)
            7'b0110111: begin // lui: imm 直通
                extop = 3'b001; regwr = 1'b1; alu_bsrc = 2'b01; aluctr = 4'b0011;
            end
            7'b0010111: begin // auipc: PC + imm
                extop = 3'b001; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b01; aluctr = 4'b0000;
            end
            7'b0010011: begin // op-imm
                extop = 3'b000; regwr = 1'b1; alu_bsrc = 2'b01;
                case (f3)
                    3'b000:  aluctr = 4'b0000;
                    3'b010:  aluctr = 4'b0010;
                    3'b011:  aluctr = 4'b1010;
                    3'b100:  aluctr = 4'b0100;
                    3'b110:  aluctr = 4'b0110;
                    3'b111:  aluctr = 4'b0111;
                    3'b001:  aluctr = 4'b0001;
                    3'b101:  aluctr = f7b5 ? 4'b1101 : 4'b0101;
                    default: aluctr = 4'b0000;
                endcase
            end
            7'b0110011: begin // R-type
                regwr = 1'b1; alu_bsrc = 2'b00;
                case (f3)
                    3'b000:  aluctr = f7b5 ? 4'b1000 : 4'b0000;
                    3'b001:  aluctr = 4'b0001;
                    3'b010:  aluctr = 4'b0010;
                    3'b011:  aluctr = 4'b1010;
                    3'b100:  aluctr = 4'b0100;
                    3'b101:  aluctr = f7b5 ? 4'b1101 : 4'b0101;
                    3'b110:  aluctr = 4'b0110;
                    3'b111:  aluctr = 4'b0111;
                    default: aluctr = 4'b0000;
                endcase
            end
            7'b1101111: begin // jal: PC+4 写回, 跳 PC+imm
                extop = 3'b100; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b10;
                aluctr = 4'b0000; branch = 3'b001;
            end
            7'b1100111: begin // jalr: PC+4 写回, 跳 rs1+imm
                extop = 3'b000; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b10;
                aluctr = 4'b0000; branch = 3'b010;
            end
            7'b1100011: begin // 条件分支
                extop = 3'b011; alu_bsrc = 2'b00; aluctr = 4'b0010;
                case (f3)
                    3'b000:  branch = 3'b100;
                    3'b001:  branch = 3'b101;
                    3'b100:  branch = 3'b110;
                    3'b101:  branch = 3'b111;
                    3'b110:  begin branch = 3'b110; aluctr = 4'b1010; end
                    3'b111:  begin branch = 3'b111; aluctr = 4'b1010; end
                    default: branch = 3'b000;
                endcase
            end
            7'b0000011: begin // 载入
                extop = 3'b000; regwr = 1'b1; alu_bsrc = 2'b01;
                aluctr = 4'b0000; memtoreg = 1'b1; memwr = 1'b0;
                case (f3)
                    3'b000:  memop = 3'b000;
                    3'b001:  memop = 3'b001;
                    3'b010:  memop = 3'b010;
                    3'b100:  memop = 3'b100;
                    3'b101:  memop = 3'b101;
                    default: memop = 3'b010;
                endcase
            end
            7'b0100011: begin // 存储
                extop = 3'b010; regwr = 1'b0; alu_bsrc = 2'b01;
                aluctr = 4'b0000; memwr = 1'b1; memtoreg = 1'b0;
                case (f3)
                    3'b000:  memop = 3'b000;
                    3'b001:  memop = 3'b001;
                    3'b010:  memop = 3'b010;
                    default: memop = 3'b010;
                endcase
            end
            default: begin
                // 全零指令 / 未实现指令 -> 空操作
            end
        endcase
    end
endmodule


//-----------------------------------------------------------------------
module alu(
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  ALUctr,
    output reg [31:0] Result,
    output Zero,
    output Less
);
    wire [31:0] sub_result = A - B;
    wire [31:0] shl        = A << B[4:0];
    wire [31:0] shrl       = A >> B[4:0];
    wire [31:0] shra       = $signed(A) >>> B[4:0];
    wire        slt_signed = ($signed(A) < $signed(B));
    wire        slt_unsign = (A < B);

    assign Zero = (A == B);
    assign Less = ALUctr[3] ? slt_unsign : slt_signed;

    always @(*) begin
        case (ALUctr[2:0])
            3'b000:  Result = ALUctr[3] ? sub_result : (A + B);
            3'b001:  Result = shl;
            3'b010:  Result = ALUctr[3] ? {31'b0, slt_unsign} : {31'b0, slt_signed};
            3'b011:  Result = B;
            3'b100:  Result = A ^ B;
            3'b101:  Result = ALUctr[3] ? shra : shrl;
            3'b110:  Result = A | B;
            3'b111:  Result = A & B;
            default: Result = 32'b0;
        endcase
    end
endmodule


//-----------------------------------------------------------------------
module regfile(
    input         WrClk,
    input         RegWr,
    input  [4:0]  Ra,
    input  [4:0]  Rb,
    input  [4:0]  Rw,
    input  [31:0] busW,
    output [31:0] busA,
    output [31:0] busB
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
module dmem #(
    parameter AW = 15              // 2^15 字 * 4B = 128KB
) (
    input         rdclk,
    input         wrclk,
    input         we,
    input  [2:0]  memop,
    input  [31:0] addr,
    input  [31:0] datain,
    output [31:0] dataout
);

    // MemOP: 010=字 001=半字带符号 000=字节带符号
    //        101=半字无符号 100=字节无符号
    localparam MEM_W = 3'b010;
    localparam MEM_H = 3'b001;
    localparam MEM_B = 3'b000;
    localparam MEM_HU= 3'b101;
    localparam MEM_BU= 3'b100;

    reg [31:0] mem [0:(1<<AW)-1];

    integer i;
    initial begin
        for (i = 0; i < (1 << AW); i = i + 1)
            mem[i] = 32'b0;
    end

    wire [AW-1:0] widx = addr[AW+1:2];
    wire [1:0]    off  = addr[1:0];

    // 上升沿: 读出整字, 同时锁存写侧信息(地址/数据/使能)
    // 这样下降沿写回时不再依赖可能在同一边沿变化的输入, 消除竞态
    reg [31:0]   rdword;
    reg [AW-1:0] widx_r;
    reg [1:0]    off_r;
    reg [2:0]    memop_r;
    reg [31:0]   datain_r;
    reg          we_r;

    always @(posedge rdclk) begin
        rdword   <= mem[widx];
        widx_r   <= widx;
        off_r    <= off;
        memop_r  <= memop;
        datain_r <= datain;
        we_r     <= we;
    end

    // 读数据选择与扩展 (组合)
    reg [31:0] rdata;
    always @(*) begin
        case (memop)
            MEM_W:  rdata = rdword;
            MEM_H:  rdata = off[1] ? {{16{rdword[31]}}, rdword[31:16]}
                                   : {{16{rdword[15]}}, rdword[15:0]};
            MEM_HU: rdata = off[1] ? {16'b0, rdword[31:16]}
                                   : {16'b0, rdword[15:0]};
            MEM_B:  case (off)
                        2'b00:   rdata = {{24{rdword[7]}},  rdword[7:0]};
                        2'b01:   rdata = {{24{rdword[15]}}, rdword[15:8]};
                        2'b10:   rdata = {{24{rdword[23]}}, rdword[23:16]};
                        default: rdata = {{24{rdword[31]}}, rdword[31:24]};
                    endcase
            MEM_BU: case (off)
                        2'b00:   rdata = {24'b0, rdword[7:0]};
                        2'b01:   rdata = {24'b0, rdword[15:8]};
                        2'b10:   rdata = {24'b0, rdword[23:16]};
                        default: rdata = {24'b0, rdword[31:24]};
                    endcase
            default: rdata = rdword;
        endcase
    end

    assign dataout = rdata;

    // 写数据组装: 用锁存后的信息, 保留未涉及的比特 (先读后改再整字写)
    reg [31:0] wdata;
    always @(*) begin
        case (memop_r)
            MEM_W:  wdata = datain_r;
            MEM_H, MEM_HU:
                wdata = off_r[1] ? {datain_r[15:0], rdword[15:0]}
                                 : {rdword[31:16], datain_r[15:0]};
            MEM_B, MEM_BU:
                if (off_r[1])
                    wdata = off_r[0] ? {datain_r[7:0], rdword[23:0]}
                                     : {rdword[31:24], datain_r[7:0], rdword[15:0]};
                else
                    wdata = off_r[0] ? {rdword[31:16], datain_r[7:0], rdword[7:0]}
                                     : {rdword[31:8], datain_r[7:0]};
            default: wdata = datain_r;
        endcase
    end

    always @(negedge wrclk) begin
        if (we_r)
            mem[widx_r] <= wdata;
    end

endmodule
//=======================================================================
// lab10 单周期 CPU 上板外壳 (与 cpu.v/dmem.v 拼接为自包含 cpu_top.v)
//   SW0 = 0: 自动运行(慢速, 约 2Hz 观察 PC)
//   SW0 = 1: BTNC 单步 (每按一次前进一个 CPU 周期)
//   CPU_RESETN: 低有效复位
//   数码管: 显示 32bit PC; LED[15:0]: 当前取到的指令低 16 位
//=======================================================================
module cpu_top #(
    parameter integer DIV_MAX = 25_000_000
) (
    input        CLK100MHZ,
    input        CPU_RESETN,
    input        BTNC,
    input        SW0,
    output [7:0] AN,
    output [7:0] HEX,
    output [15:0] LED
);

    //--- 上电复位 ---
    reg [3:0] por;
    initial por = 4'd0;
    always @(posedge CLK100MHZ)
        if (!por[3]) por <= por + 1'b1;
    wire rst = (~CPU_RESETN) | (~por[3]);

    //--- BTNC 消抖与单步脉冲 ---
    reg [19:0] dbnc;
    initial dbnc = 20'd0;
    always @(posedge CLK100MHZ) dbnc <= {dbnc[18:0], BTNC};
    wire btnc_clean = &dbnc;
    reg btnc_d;
    initial btnc_d = 1'b0;
    always @(posedge CLK100MHZ) btnc_d <= btnc_clean;
    wire step = btnc_clean & ~btnc_d;

    //--- 慢速节拍 ---
    reg [24:0] div;
    initial div = 25'd0;
    wire tick = (div == 25'd0);
    always @(posedge CLK100MHZ)
        div <= tick ? DIV_MAX[24:0] : (div - 1'b1);

    //--- CPU 时钟 ---
    reg cpu_clk;
    initial cpu_clk = 1'b0;
    always @(posedge CLK100MHZ)
        if (SW0) begin
            if (step) cpu_clk <= ~cpu_clk;      // 每按一次产生一个完整周期
        end else begin
            if (tick) cpu_clk <= ~cpu_clk;      // 慢速自动运行
        end

    //--- CPU + 存储器 ---
    wire [31:0] imemaddr, imemdataout;
    wire        imemclk;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire        dmemrdclk, dmemwrclk, dmemwe;
    wire [2:0]  dmemop;
    wire [31:0] dbgdata;

    rv32is u_cpu (
        .clock(cpu_clk), .reset(rst),
        .imemaddr(imemaddr), .imemdataout(imemdataout), .imemclk(imemclk),
        .dmemaddr(dmemaddr), .dmemdataout(dmemdataout), .dmemdatain(dmemdatain),
        .dmemrdclk(dmemrdclk), .dmemwrclk(dmemwrclk), .dmemop(dmemop),
        .dmemwe(dmemwe), .dbgdata(dbgdata)
    );

    imem_rom u_rom (.clk(~imemclk), .addr(imemaddr), .dout(imemdataout));

    dmem #(.AW(13)) u_dmem (
        .rdclk(dmemrdclk), .wrclk(dmemwrclk), .we(dmemwe), .memop(dmemop),
        .addr(dmemaddr), .datain(dmemdatain), .dataout(dmemdataout)
    );

    assign LED = imemdataout[15:0];

    //--- 数码管动态扫描: 显示 32bit PC ---
    reg [14:0] scan_cnt;
    reg [2:0]  sel;
    initial begin
        scan_cnt = 15'd0;
        sel      = 3'd0;
    end
    always @(posedge CLK100MHZ) begin
        if (scan_cnt == 15'd25000) begin
            scan_cnt <= 15'd0;
            sel      <= sel + 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    reg [3:0] nib;
    always @(*) begin
        case (sel)
            3'd0:    nib = dbgdata[3:0];
            3'd1:    nib = dbgdata[7:4];
            3'd2:    nib = dbgdata[11:8];
            3'd3:    nib = dbgdata[15:12];
            3'd4:    nib = dbgdata[19:16];
            3'd5:    nib = dbgdata[23:20];
            3'd6:    nib = dbgdata[27:24];
            default: nib = dbgdata[31:28];
        endcase
    end

    reg [7:0] an_r;
    always @(*) begin
        case (sel)
            3'd0:    an_r = 8'b11111110;
            3'd1:    an_r = 8'b11111101;
            3'd2:    an_r = 8'b11111011;
            3'd3:    an_r = 8'b11110111;
            3'd4:    an_r = 8'b11101111;
            3'd5:    an_r = 8'b11011111;
            3'd6:    an_r = 8'b10111111;
            default: an_r = 8'b01111111;
        endcase
    end
    assign AN = an_r;

    reg [6:0] seg;
    always @(*) begin
        case (nib)
            4'd0:    seg = 7'b1000000;
            4'd1:    seg = 7'b1111001;
            4'd2:    seg = 7'b0100100;
            4'd3:    seg = 7'b0110000;
            4'd4:    seg = 7'b0011001;
            4'd5:    seg = 7'b0010010;
            4'd6:    seg = 7'b0000010;
            4'd7:    seg = 7'b1111000;
            4'd8:    seg = 7'b0000000;
            4'd9:    seg = 7'b0010000;
            4'd10:   seg = 7'b0001000;
            4'd11:   seg = 7'b0000011;
            4'd12:   seg = 7'b1000110;
            4'd13:   seg = 7'b0100001;
            4'd14:   seg = 7'b0001100;
            4'd15:   seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end
    assign HEX = {seg, 1'b1};

endmodule


//-----------------------------------------------------------------------
// 板上指令 ROM: 8 条演示程序, 下降沿(接 ~imemclk)读取
//-----------------------------------------------------------------------
module imem_rom(
    input         clk,
    input  [31:0] addr,
    output reg [31:0] dout
);
    always @(posedge clk) begin
        case (addr[7:2])
            6'd0:    dout <= 32'h0010_0093;  // addi x1,x0,1
            6'd1:    dout <= 32'h0020_0113;  // addi x2,x0,2
            6'd2:    dout <= 32'h0030_0193;  // addi x3,x0,3
            6'd3:    dout <= 32'h0020_8233;  // add  x4,x1,x2
            6'd4:    dout <= 32'h0011_82b3;  // add  x5,x3,x1
            6'd5:    dout <= 32'h0040_2023;  // sw   x4,0(x0)
            6'd6:    dout <= 32'h0000_2303;  // lw   x6,0(x0)
            6'd7:    dout <= 32'hfe00_08e3;  // beq  x0,x0,loop
            default: dout <= 32'h0000_0013;  // nop
        endcase
    end
endmodule

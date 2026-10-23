`timescale 1ns / 1ps
//==============================================================================
// rv32is.v : RV32I 单周期 CPU
//
// 时序（与实验指导 9.2.4 一致，时钟周期以时钟下降沿为起点）:
//   下降沿:  PC <- NextPC, 指令存储器读 NextPC, 寄存器堆写回, 数据存储器写
//   上升沿:  数据存储器读 (读写地址已由组合逻辑准备好)
//   组合逻辑: 指令译码 -> 立即数 -> 寄存器读 -> ALU -> 访存地址/写回数据
//
// 因此 imemclk = ~clock, dmemrdclk = clock, dmemwrclk = ~clock,
// 寄存器堆写时钟直接用 clock (其内部在下降沿写入).
//==============================================================================

module rv32is(
    input  wire        clock,
    input  wire        reset,
    // 指令存储器接口
    output wire [31:0] imemaddr,
    input  wire [31:0] imemdataout,
    output wire        imemclk,
    // 数据存储器接口
    output wire [31:0] dmemaddr,
    input  wire [31:0] dmemdataout,
    output wire [31:0] dmemdatain,
    output wire        dmemrdclk,
    output wire        dmemwrclk,
    output wire [2:0]  dmemop,
    output wire        dmemwe,
    // 调试接口: 输出当前 PC
    output wire [31:0] dbgdata
);

    //--------------------------------------------------------------------------
    // 程序计数器
    //--------------------------------------------------------------------------
    reg  [31:0] pc;
    initial pc = 32'b0;

    //--------------------------------------------------------------------------
    // 指令字段
    //--------------------------------------------------------------------------
    wire [31:0] instr   = imemdataout;
    wire [6:0]  op      = instr[6:0];
    wire [4:0]  rs1     = instr[19:15];
    wire [4:0]  rs2     = instr[24:20];
    wire [4:0]  rd      = instr[11:7];
    wire [2:0]  func3   = instr[14:12];
    wire        func7_5 = instr[30];

    //--------------------------------------------------------------------------
    // 立即数生成 (所有立即数均符号扩展到 32 位, 符号位恒为 instr[31])
    //--------------------------------------------------------------------------
    wire [31:0] immI = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] immU = {instr[31:12], 12'b0};
    wire [31:0] immS = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] immB = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] immJ = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    //--------------------------------------------------------------------------
    // 控制信号
    //--------------------------------------------------------------------------
    reg  [2:0] extop;      // 立即数类型
    reg        regwr;      // 寄存器堆写使能
    reg        alua_src;   // 0: rs1, 1: PC
    reg  [1:0] alubsrc;    // 00: rs2, 01: imm, 10: 常数 4
    reg  [3:0] aluctr;     // ALU 控制字
    reg  [2:0] branch;     // 跳转类型
    reg        memtoreg;   // 0: ALU 结果, 1: 数据存储器输出
    reg        memwr;      // 数据存储器写使能
    reg  [2:0] memop;      // 访存宽度与符号扩展

    always @(*) begin
        // 默认值: 未定义指令一律按空操作处理, 避免组合逻辑推断出锁存器
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
            //------------------------------------------------------------------
            7'b0110111: begin                       // lui
                extop  = 3'b001;
                regwr  = 1'b1;
                alubsrc = 2'b01;
                aluctr = 4'b0011;                   // 直接输出 B (立即数)
            end
            //------------------------------------------------------------------
            7'b0010111: begin                       // auipc
                extop   = 3'b001;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b01;
                aluctr  = 4'b0000;                  // PC + 立即数
            end
            //------------------------------------------------------------------
            7'b0010011: begin                       // 立即数运算类
                extop   = 3'b000;
                regwr   = 1'b1;
                alubsrc = 2'b01;
                case (func3)
                    3'b000: aluctr = 4'b0000;       // addi
                    3'b010: aluctr = 4'b0010;       // slti
                    3'b011: aluctr = 4'b1010;       // sltiu
                    3'b100: aluctr = 4'b0100;       // xori
                    3'b110: aluctr = 4'b0110;       // ori
                    3'b111: aluctr = 4'b0111;       // andi
                    3'b001: aluctr = 4'b0001;       // slli
                    3'b101: aluctr = func7_5 ? 4'b1101 : 4'b0101;  // srai : srli
                    default: aluctr = 4'b0000;
                endcase
            end
            //------------------------------------------------------------------
            7'b0110011: begin                       // 寄存器运算类
                regwr   = 1'b1;
                alubsrc = 2'b00;
                case (func3)
                    3'b000: aluctr = func7_5 ? 4'b1000 : 4'b0000;  // sub : add
                    3'b001: aluctr = 4'b0001;       // sll
                    3'b010: aluctr = 4'b0010;       // slt
                    3'b011: aluctr = 4'b1010;       // sltu
                    3'b100: aluctr = 4'b0100;       // xor
                    3'b101: aluctr = func7_5 ? 4'b1101 : 4'b0101;  // sra : srl
                    3'b110: aluctr = 4'b0110;       // or
                    3'b111: aluctr = 4'b0111;       // and
                    default: aluctr = 4'b0000;
                endcase
            end
            //------------------------------------------------------------------
            7'b1101111: begin                       // jal
                extop   = 3'b100;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b10;
                aluctr  = 4'b0000;                  // 返回地址 PC+4
                branch  = 3'b001;
            end
            7'b1100111: begin                       // jalr
                extop   = 3'b000;
                regwr   = 1'b1;
                alua_src = 1'b1;
                alubsrc = 2'b10;
                aluctr  = 4'b0000;                  // 返回地址 PC+4
                branch  = 3'b010;
            end
            //------------------------------------------------------------------
            7'b1100011: begin                       // 条件分支
                extop   = 3'b011;
                alubsrc = 2'b00;
                case (func3)
                    3'b000: begin aluctr = 4'b0010; branch = 3'b100; end  // beq
                    3'b001: begin aluctr = 4'b0010; branch = 3'b101; end  // bne
                    3'b100: begin aluctr = 4'b0010; branch = 3'b110; end  // blt
                    3'b101: begin aluctr = 4'b0010; branch = 3'b111; end  // bge
                    3'b110: begin aluctr = 4'b1010; branch = 3'b110; end  // bltu
                    3'b111: begin aluctr = 4'b1010; branch = 3'b111; end  // bgeu
                    default: branch = 3'b000;
                endcase
            end
            //------------------------------------------------------------------
            7'b0000011: begin                       // 取数 lb/lh/lw/lbu/lhu
                extop    = 3'b000;
                regwr    = 1'b1;
                alubsrc  = 2'b01;
                memtoreg = 1'b1;
                memop    = func3;
            end
            7'b0100011: begin                       // 存数 sb/sh/sw
                extop   = 3'b010;
                alubsrc = 2'b01;
                memwr   = 1'b1;
                memop   = func3;
            end
            //------------------------------------------------------------------
            default: ;
        endcase
    end

    //--------------------------------------------------------------------------
    // 立即数选择
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // 寄存器堆
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // ALU
    //--------------------------------------------------------------------------
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

    wire [4:0]  shamt  = alu_b[4:0];
    wire [31:0] sum    = alu_a + alu_b;
    wire [31:0] diff   = alu_a - alu_b;
    wire [31:0] shra   = $signed(alu_a) >>> shamt;
    wire        lt_s   = $signed(alu_a) < $signed(alu_b);
    wire        lt_u   = alu_a < alu_b;

    reg  [31:0] alu_result;
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

    //--------------------------------------------------------------------------
    // 写回
    //--------------------------------------------------------------------------
    assign busW = memtoreg ? dmemdataout : alu_result;

    //--------------------------------------------------------------------------
    // PC 生成
    //--------------------------------------------------------------------------
    wire [31:0] pc_plus4    = pc + 32'd4;
    wire [31:0] pc_plus_imm = pc + imm;
    wire [31:0] rs1_imm     = busA + imm;

    reg [31:0] nextpc;
    always @(*) begin
        case (branch)
            3'b001:  nextpc = pc_plus_imm;                      // jal
            3'b010:  nextpc = {rs1_imm[31:1], 1'b0};            // jalr, 最低位清零
            3'b100:  nextpc = alu_zero ? pc_plus_imm : pc_plus4; // beq
            3'b101:  nextpc = alu_zero ? pc_plus4 : pc_plus_imm; // bne
            3'b110:  nextpc = alu_less ? pc_plus_imm : pc_plus4; // blt/bltu
            3'b111:  nextpc = alu_less ? pc_plus4 : pc_plus_imm; // bge/bgeu
            default: nextpc = pc_plus4;
        endcase
    end

    // reset 期间 NextPC 必须保持为 0, 保证 reset 后从 0 地址取指
    wire [31:0] nextpc_mux = reset ? 32'b0 : nextpc;

    // 指令存储器在下降沿按 NextPC 取指, 因此地址必须用 NextPC 而不是 PC
    assign imemaddr = nextpc_mux;
    assign imemclk  = ~clock;

    always @(negedge clock) begin
        if (reset)
            pc <= 32'b0;
        else
            pc <= nextpc_mux;
    end

    //--------------------------------------------------------------------------
    // 数据存储器接口
    //--------------------------------------------------------------------------
    assign dmemaddr   = alu_result;
    assign dmemdatain = busB;
    assign dmemop     = memop;
    assign dmemwe     = memwr & ~reset;
    assign dmemrdclk  = clock;      // 上升沿读
    assign dmemwrclk  = ~clock;     // 下降沿写

    assign dbgdata = pc;

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

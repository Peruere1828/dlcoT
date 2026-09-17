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

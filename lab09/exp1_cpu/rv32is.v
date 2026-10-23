`timescale 1ns / 1ps

// rv32is.v : RV32I 单周期 CPU
//
// 时序（与实验指导 9.2.4 一致，时钟周期以时钟下降沿为起点）:
//   下降沿:  PC <- NextPC, 指令存储器读 NextPC, 寄存器堆写回, 数据存储器写
//   上升沿:  数据存储器读 (读写地址已由组合逻辑准备好)
//   组合逻辑: 指令译码 -> 立即数 -> 寄存器读 -> ALU -> 访存地址/写回数据
//
// 因此 imemclk = ~clock, dmemrdclk = clock, dmemwrclk = ~clock,
// 寄存器堆写时钟直接用 clock (其内部在下降沿写入).

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

    // 程序计数器

    reg  [31:0] pc;
    initial pc = 32'b0;

    // 指令字段

    wire [31:0] instr   = imemdataout;
    wire [6:0]  op      = instr[6:0];
    wire [4:0]  rs1     = instr[19:15];
    wire [4:0]  rs2     = instr[24:20];
    wire [4:0]  rd      = instr[11:7];
    wire [2:0]  func3   = instr[14:12];
    wire        func7_5 = instr[30];

    // 立即数生成 (所有立即数均符号扩展到 32 位, 符号位恒为 instr[31])

    wire [31:0] immI = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] immU = {instr[31:12], 12'b0};
    wire [31:0] immS = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] immB = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] immJ = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    // 指令编码

    // 操作码 (instr[6:0])
    localparam [6:0] OP_LUI    = 7'b0110111,
                     OP_AUIPC  = 7'b0010111,
                     OP_JAL    = 7'b1101111,
                     OP_JALR   = 7'b1100111,
                     OP_BRANCH = 7'b1100011,
                     OP_LOAD   = 7'b0000011,
                     OP_STORE  = 7'b0100011,
                     OP_IMM    = 7'b0010011,
                     OP_REG    = 7'b0110011;

    // funct3 (instr[14:12]): 同一数值在不同指令类型下含义不同, 按助记符命名
    localparam [2:0] F3_ADDI  = 3'b000,   // I 型立即数运算
                     F3_SLLI  = 3'b001,
                     F3_SLTI  = 3'b010,
                     F3_SLTIU = 3'b011,
                     F3_XORI  = 3'b100,
                     F3_SRLI  = 3'b101,   // srai 同编码, 由 func7_5 区分
                     F3_ORI   = 3'b110,
                     F3_ANDI  = 3'b111,
                     F3_ADD   = 3'b000,   // R 型寄存器运算
                     F3_SLL   = 3'b001,
                     F3_SLT   = 3'b010,
                     F3_SLTU  = 3'b011,
                     F3_XOR   = 3'b100,
                     F3_SRL   = 3'b101,   // sra 同编码
                     F3_OR    = 3'b110,
                     F3_AND   = 3'b111,
                     F3_BEQ   = 3'b000,   // B 型条件分支
                     F3_BNE   = 3'b001,
                     F3_BLT   = 3'b100,
                     F3_BGE   = 3'b101,
                     F3_BLTU  = 3'b110,
                     F3_BGEU  = 3'b111;

    // 立即数类型
    localparam [2:0] EXT_I = 3'd0,        // I 型: addi/lw/jalr
                     EXT_U = 3'd1,        // U 型: lui/auipc
                     EXT_S = 3'd2,        // S 型: sw
                     EXT_B = 3'd3,        // B 型: beq/bne/blt
                     EXT_J = 3'd4;        // J 型: jal

    // ALU A 端口来源
    localparam       ALU_A_RS1 = 1'b0,
                     ALU_A_PC  = 1'b1;

    // ALU B 端口来源
    localparam [1:0] ALU_B_RS2  = 2'd0,
                     ALU_B_IMM  = 2'd1,
                     ALU_B_FOUR = 2'd2;

    // ALU 控制字, 编码与实验指导的表 9.10 一致
    // 最高位是辅助位: 加减、有无符号、逻辑/算术右移靠它区分
    localparam [3:0] ALU_ADD  = 4'b0000,
                     ALU_SUB  = 4'b1000,
                     ALU_SLL  = 4'b0001,
                     ALU_SLT  = 4'b0010,
                     ALU_SLTU = 4'b1010,
                     ALU_LUI  = 4'b0011,   // 直接输出 B
                     ALU_XOR  = 4'b0100,
                     ALU_SRL  = 4'b0101,
                     ALU_SRA  = 4'b1101,
                     ALU_OR   = 4'b0110,
                     ALU_AND  = 4'b0111;

    // 跳转类型, 编码与实验指导的表 9.11 一致
    localparam [2:0] BR_NONE = 3'b000,
                     BR_JAL  = 3'b001,
                     BR_JALR = 3'b010,
                     BR_BEQ  = 3'b100,
                     BR_BNE  = 3'b101,
                     BR_LT   = 3'b110,     // blt/bltu
                     BR_GE   = 3'b111;     // bge/bgeu

    // 访存宽度, 编码与 load/store 的 funct3 相同
    localparam [2:0] MEM_WORD = 3'b010;

    // 每条指令前进 4 字节
    localparam [31:0] PC_STEP = 32'd4;

    reg  [2:0] extop;      // 立即数类型, 取值 EXT_*
    reg        regwr;      // 寄存器堆写使能
    reg        alu_a_src;  // ALU_A_RS1 / ALU_A_PC
    reg  [1:0] alu_b_src;  // ALU_B_RS2 / ALU_B_IMM / ALU_B_FOUR
    reg  [3:0] aluctr;     // ALU 控制字, 取值 ALU_*
    reg  [2:0] branch;     // 跳转类型, 取值 BR_*
    reg        memtoreg;   // 0: ALU 结果, 1: 数据存储器输出
    reg        memwr;      // 数据存储器写使能
    reg  [2:0] memop;      // 访存宽度, 取值 MEM_*

    always @(*) begin
        // 默认值: 未定义指令一律按空操作处理, 避免组合逻辑推断出锁存器
        extop     = EXT_I;
        regwr     = 1'b0;
        alu_a_src = ALU_A_RS1;
        alu_b_src = ALU_B_RS2;
        aluctr    = ALU_ADD;
        branch    = BR_NONE;
        memtoreg  = 1'b0;
        memwr     = 1'b0;
        memop     = MEM_WORD;

        case (op)
            OP_LUI: begin
                extop     = EXT_U;
                regwr     = 1'b1;
                alu_b_src = ALU_B_IMM;
                aluctr    = ALU_LUI;            // 直接输出 B
            end

            OP_AUIPC: begin
                extop     = EXT_U;
                regwr     = 1'b1;
                alu_a_src = ALU_A_PC;
                alu_b_src = ALU_B_IMM;
                aluctr    = ALU_ADD;            // PC + 立即数
            end

            OP_IMM: begin
                extop     = EXT_I;
                regwr     = 1'b1;
                alu_b_src = ALU_B_IMM;
                case (func3)
                    F3_ADDI:  aluctr = ALU_ADD;
                    F3_SLTI:  aluctr = ALU_SLT;
                    F3_SLTIU: aluctr = ALU_SLTU;
                    F3_XORI:  aluctr = ALU_XOR;
                    F3_ORI:   aluctr = ALU_OR;
                    F3_ANDI:  aluctr = ALU_AND;
                    F3_SLLI:  aluctr = ALU_SLL;
                    F3_SRLI:  aluctr = func7_5 ? ALU_SRA : ALU_SRL;
                    default:  aluctr = ALU_ADD;
                endcase
            end

            OP_REG: begin
                regwr     = 1'b1;
                alu_b_src = ALU_B_RS2;
                case (func3)
                    F3_ADD:  aluctr = func7_5 ? ALU_SUB : ALU_ADD;
                    F3_SLL:  aluctr = ALU_SLL;
                    F3_SLT:  aluctr = ALU_SLT;
                    F3_SLTU: aluctr = ALU_SLTU;
                    F3_XOR:  aluctr = ALU_XOR;
                    F3_SRL:  aluctr = func7_5 ? ALU_SRA : ALU_SRL;
                    F3_OR:   aluctr = ALU_OR;
                    F3_AND:  aluctr = ALU_AND;
                    default: aluctr = ALU_ADD;
                endcase
            end

            OP_JAL: begin
                extop     = EXT_J;
                regwr     = 1'b1;
                alu_a_src = ALU_A_PC;
                alu_b_src = ALU_B_FOUR;
                aluctr    = ALU_ADD;            // 返回地址 PC+4
                branch    = BR_JAL;
            end
            OP_JALR: begin
                extop     = EXT_I;
                regwr     = 1'b1;
                alu_a_src = ALU_A_PC;
                alu_b_src = ALU_B_FOUR;
                aluctr    = ALU_ADD;            // 返回地址 PC+4
                branch    = BR_JALR;
            end

            OP_BRANCH: begin
                extop     = EXT_B;
                alu_b_src = ALU_B_RS2;
                case (func3)
                    F3_BEQ:  begin aluctr = ALU_SLT;  branch = BR_BEQ; end
                    F3_BNE:  begin aluctr = ALU_SLT;  branch = BR_BNE; end
                    F3_BLT:  begin aluctr = ALU_SLT;  branch = BR_LT;  end
                    F3_BGE:  begin aluctr = ALU_SLT;  branch = BR_GE;  end
                    F3_BLTU: begin aluctr = ALU_SLTU; branch = BR_LT;  end
                    F3_BGEU: begin aluctr = ALU_SLTU; branch = BR_GE;  end
                    default: branch = BR_NONE;
                endcase
            end

            OP_LOAD: begin
                extop     = EXT_I;
                regwr     = 1'b1;
                alu_b_src = ALU_B_IMM;
                memtoreg  = 1'b1;
                memop     = func3;
            end
            OP_STORE: begin
                extop     = EXT_S;
                alu_b_src = ALU_B_IMM;
                memwr     = 1'b1;
                memop     = func3;
            end

            default: ;
        endcase
    end

    // 立即数选择

    reg [31:0] imm;
    always @(*) begin
        case (extop)
            EXT_I:   imm = immI;
            EXT_U:   imm = immU;
            EXT_S:   imm = immS;
            EXT_B:   imm = immB;
            EXT_J:   imm = immJ;
            default: imm = immI;
        endcase
    end

    // 寄存器堆

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

    // ALU

    wire [31:0] alu_a = alu_a_src ? pc : busA;
    reg  [31:0] alu_b;

    always @(*) begin
        case (alu_b_src)
            ALU_B_RS2:  alu_b = busB;
            ALU_B_IMM:  alu_b = imm;
            ALU_B_FOUR: alu_b = PC_STEP;
            default:    alu_b = busB;
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
        case (aluctr)
            ALU_ADD:  alu_result = sum;
            ALU_SUB:  alu_result = diff;
            ALU_SLL:  alu_result = alu_a << shamt;
            ALU_SLT:  alu_result = {31'b0, lt_s};
            ALU_SLTU: alu_result = {31'b0, lt_u};
            ALU_XOR:  alu_result = alu_a ^ alu_b;
            ALU_SRL:  alu_result = alu_a >> shamt;
            ALU_SRA:  alu_result = shra;
            ALU_OR:   alu_result = alu_a | alu_b;
            ALU_AND:  alu_result = alu_a & alu_b;
            ALU_LUI:  alu_result = alu_b;
            default:  alu_result = 32'b0;
        endcase
    end

    // 分支比较: 相等用 a == b, 大小用 slt/sltu 的结果
    wire alu_cmp  = (aluctr == ALU_SLT) || (aluctr == ALU_SLTU);
    wire alu_zero = alu_cmp ? (alu_a == alu_b) : (alu_result == 32'b0);
    wire alu_less = (aluctr == ALU_SLTU) ? lt_u : lt_s;

    // 写回

    assign busW = memtoreg ? dmemdataout : alu_result;

    // PC 生成

    wire [31:0] pc_plus4    = pc + PC_STEP;
    wire [31:0] pc_plus_imm = pc + imm;
    wire [31:0] rs1_imm     = busA + imm;

    reg [31:0] nextpc;
    always @(*) begin
        case (branch)
            BR_JAL:  nextpc = pc_plus_imm;                       // jal
            BR_JALR: nextpc = {rs1_imm[31:1], 1'b0};             // jalr, 最低位清零
            BR_BEQ:  nextpc = alu_zero ? pc_plus_imm : pc_plus4; // beq
            BR_BNE:  nextpc = alu_zero ? pc_plus4 : pc_plus_imm; // bne
            BR_LT:   nextpc = alu_less ? pc_plus_imm : pc_plus4; // blt/bltu
            BR_GE:   nextpc = alu_less ? pc_plus4 : pc_plus_imm; // bge/bgeu
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

    // 数据存储器接口

    assign dmemaddr   = alu_result;
    assign dmemdatain = busB;
    assign dmemop     = memop;
    assign dmemwe     = memwr & ~reset;
    assign dmemrdclk  = clock;      // 上升沿读
    assign dmemwrclk  = ~clock;     // 下降沿写

    assign dbgdata = pc;

endmodule

// 寄存器堆: 两读一写, x0 恒为 0, 下降沿写入

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

`timescale 1ns / 1ps

// rv32ip.v : RV32I 五段流水线 CPU
//
// 流水段: IF -> ID -> EX -> MEM -> WB, 段寄存器 IF/ID, ID/EX, EX/MEM, MEM/WB
//
// 时序与实验指导 10.2 一致, 周期以时钟下降沿为起点和终点:
//   下降沿: PC 更新; 四个段寄存器更新; 数据存储器写入 (用更新前的 MEM 级数据)
//   上升沿: 读指令存储器; 读数据存储器; 寄存器堆写回
//   组合逻辑: 译码、立即数、寄存器读、ALU、前转、跳转判断
//
// 冒险处理:
//   数据冒险  WB->ID 由"上升沿写寄存器 + 组合读"天然完成
//             WB->EX、MEM->EX 两级前转, MEM 的优先级高
//             Load-use 冒险阻塞一个周期: stallIF/stallID/stallEX 有效, flushEX 插气泡
//   控制冒险  跳转统一在 EX 阶段确定, 冲刷 IF/ID 与 ID/EX 中的两条错误指令
//
// 全零指令 (flush 后段寄存器的内容) 在译码时落到 default 分支,
// 所有控制信号取默认值, 等价于 NOP.

module rv32ip(
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
    // 调试接口: 当前 PC
    output wire [31:0] dbgdata
);

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

    // ------------------------------------------------------------------
    // 流水段寄存器
    // ------------------------------------------------------------------

    // IF/ID: 指令与它的 PC
    reg [31:0] IF_ID_pc;
    reg [31:0] IF_ID_instr;

    // ID/EX: ID 阶段交给 EX 阶段的全部数据和向后传递的控制信号
    reg [31:0] EX_pc;        // 本指令的 PC, auipc/jal/jalr 和分支目标要用
    reg [31:0] EX_imm;
    reg [31:0] EX_rs1data;
    reg [31:0] EX_rs2data;
    reg [4:0]  EX_rs1;
    reg [4:0]  EX_rs2;
    reg [4:0]  EX_rd;
    reg [2:0]  EX_branch;
    reg        EX_aluasrc;
    reg [1:0]  EX_alubsrc;
    reg [3:0]  EX_aluctr;
    reg        EX_memwr;
    reg [2:0]  EX_memop;
    reg        EX_regwr;
    reg        EX_memtoreg;

    // EX/MEM: MEM 阶段使用的数据和信号
    reg [31:0] MEM_alu_result;
    reg [31:0] MEM_rs2data;
    reg [4:0]  MEM_rd;
    reg        MEM_memwr;
    reg [2:0]  MEM_memop;
    reg        MEM_regwr;
    reg        MEM_memtoreg;

    // MEM/WB: WB 阶段使用的数据和信号
    reg [31:0] WB_alu_result;
    reg [31:0] WB_memout;
    reg [4:0]  WB_rd;
    reg        WB_regwr;
    reg        WB_memtoreg;

    // 仿真初值, 保证复位前所有信号有确定值
    initial begin
        IF_ID_pc       = 32'b0;
        IF_ID_instr    = 32'b0;
        EX_pc          = 32'b0;
        EX_imm         = 32'b0;
        EX_rs1data     = 32'b0;
        EX_rs2data     = 32'b0;
        EX_rs1         = 5'b0;
        EX_rs2         = 5'b0;
        EX_rd          = 5'b0;
        EX_branch      = BR_NONE;
        EX_aluasrc     = ALU_A_RS1;
        EX_alubsrc     = ALU_B_RS2;
        EX_aluctr      = ALU_ADD;
        EX_memwr       = 1'b0;
        EX_memop       = MEM_WORD;
        EX_regwr       = 1'b0;
        EX_memtoreg    = 1'b0;
        MEM_alu_result = 32'b0;
        MEM_rs2data    = 32'b0;
        MEM_rd         = 5'b0;
        MEM_memwr      = 1'b0;
        MEM_memop      = MEM_WORD;
        MEM_regwr      = 1'b0;
        MEM_memtoreg   = 1'b0;
        WB_alu_result  = 32'b0;
        WB_memout      = 32'b0;
        WB_rd          = 5'b0;
        WB_regwr       = 1'b0;
        WB_memtoreg    = 1'b0;
    end

    // ------------------------------------------------------------------
    // IF 阶段: PC 与取指
    // ------------------------------------------------------------------

    reg  [31:0] pc;
    initial pc = 32'b0;

    wire [31:0] pc_plus4 = pc + 32'd4;

    // 指令存储器在上升沿按当前 PC 取指
    assign imemaddr = pc;
    assign imemclk  = clock;

    // ------------------------------------------------------------------
    // ID 阶段: 译码、立即数、读寄存器
    // ------------------------------------------------------------------

    wire [31:0] instr   = IF_ID_instr;
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

    reg  [2:0]  id_extop;    // 立即数类型, 取值 EXT_*
    reg         id_regwr;    // 寄存器堆写使能
    reg         id_aluasrc;  // ALU_A_RS1 / ALU_A_PC
    reg  [1:0]  id_alubsrc;  // ALU_B_RS2 / ALU_B_IMM / ALU_B_FOUR
    reg  [3:0]  id_aluctr;   // ALU 控制字, 取值 ALU_*
    reg  [2:0]  id_branch;   // 跳转类型, 取值 BR_*
    reg         id_memtoreg; // 0: ALU 结果, 1: 数据存储器输出
    reg         id_memwr;    // 数据存储器写使能
    reg  [2:0]  id_memop;    // 访存宽度, 取值 MEM_*

    always @(*) begin
        // 默认值: 未定义指令 (含全零指令) 一律按空操作处理, 避免推断出锁存器
        id_extop    = EXT_I;
        id_regwr    = 1'b0;
        id_aluasrc  = ALU_A_RS1;
        id_alubsrc  = ALU_B_RS2;
        id_aluctr   = ALU_ADD;
        id_branch   = BR_NONE;
        id_memtoreg = 1'b0;
        id_memwr    = 1'b0;
        id_memop    = MEM_WORD;

        case (op)
            OP_LUI: begin
                id_extop    = EXT_U;
                id_regwr    = 1'b1;
                id_alubsrc  = ALU_B_IMM;
                id_aluctr   = ALU_LUI;          // 直接输出 B
            end

            OP_AUIPC: begin
                id_extop    = EXT_U;
                id_regwr    = 1'b1;
                id_aluasrc  = ALU_A_PC;
                id_alubsrc  = ALU_B_IMM;
                id_aluctr   = ALU_ADD;          // PC + 立即数
            end

            OP_IMM: begin
                id_extop    = EXT_I;
                id_regwr    = 1'b1;
                id_alubsrc  = ALU_B_IMM;
                case (func3)
                    F3_ADDI:  id_aluctr = ALU_ADD;
                    F3_SLTI:  id_aluctr = ALU_SLT;
                    F3_SLTIU: id_aluctr = ALU_SLTU;
                    F3_XORI:  id_aluctr = ALU_XOR;
                    F3_ORI:   id_aluctr = ALU_OR;
                    F3_ANDI:  id_aluctr = ALU_AND;
                    F3_SLLI:  id_aluctr = ALU_SLL;
                    F3_SRLI:  id_aluctr = func7_5 ? ALU_SRA : ALU_SRL;
                    default:  id_aluctr = ALU_ADD;
                endcase
            end

            OP_REG: begin
                id_regwr    = 1'b1;
                id_alubsrc  = ALU_B_RS2;
                case (func3)
                    F3_ADD:  id_aluctr = func7_5 ? ALU_SUB : ALU_ADD;
                    F3_SLL:  id_aluctr = ALU_SLL;
                    F3_SLT:  id_aluctr = ALU_SLT;
                    F3_SLTU: id_aluctr = ALU_SLTU;
                    F3_XOR:  id_aluctr = ALU_XOR;
                    F3_SRL:  id_aluctr = func7_5 ? ALU_SRA : ALU_SRL;
                    F3_OR:   id_aluctr = ALU_OR;
                    F3_AND:  id_aluctr = ALU_AND;
                    default: id_aluctr = ALU_ADD;
                endcase
            end

            OP_JAL: begin
                id_extop    = EXT_J;
                id_regwr    = 1'b1;
                id_aluasrc  = ALU_A_PC;
                id_alubsrc  = ALU_B_FOUR;
                id_aluctr   = ALU_ADD;          // 返回地址 PC+4
                id_branch   = BR_JAL;
            end
            OP_JALR: begin
                id_extop    = EXT_I;
                id_regwr    = 1'b1;
                id_aluasrc  = ALU_A_PC;
                id_alubsrc  = ALU_B_FOUR;
                id_aluctr   = ALU_ADD;          // 返回地址 PC+4
                id_branch   = BR_JALR;
            end

            OP_BRANCH: begin
                id_extop    = EXT_B;
                id_alubsrc  = ALU_B_RS2;
                case (func3)
                    F3_BEQ:  begin id_aluctr = ALU_SLT;  id_branch = BR_BEQ; end
                    F3_BNE:  begin id_aluctr = ALU_SLT;  id_branch = BR_BNE; end
                    F3_BLT:  begin id_aluctr = ALU_SLT;  id_branch = BR_LT;  end
                    F3_BGE:  begin id_aluctr = ALU_SLT;  id_branch = BR_GE;  end
                    F3_BLTU: begin id_aluctr = ALU_SLTU; id_branch = BR_LT;  end
                    F3_BGEU: begin id_aluctr = ALU_SLTU; id_branch = BR_GE;  end
                    default: id_branch = BR_NONE;
                endcase
            end

            OP_LOAD: begin
                id_extop    = EXT_I;
                id_regwr    = 1'b1;
                id_alubsrc  = ALU_B_IMM;
                id_memtoreg = 1'b1;
                id_memop    = func3;
            end
            OP_STORE: begin
                id_extop    = EXT_S;
                id_alubsrc  = ALU_B_IMM;
                id_memwr    = 1'b1;
                id_memop    = func3;
            end

            default: ;
        endcase
    end

    // 立即数选择

    reg [31:0] id_imm;
    always @(*) begin
        case (id_extop)
            EXT_I:   id_imm = immI;
            EXT_U:   id_imm = immU;
            EXT_S:   id_imm = immS;
            EXT_B:   id_imm = immB;
            EXT_J:   id_imm = immJ;
            default: id_imm = immI;
        endcase
    end

    // 寄存器堆读端口 (组合读) 与写回数据

    wire [31:0] id_busA, id_busB, wb_data;

    // ------------------------------------------------------------------
    // EX 阶段: 前转、ALU、分支判断
    // ------------------------------------------------------------------

    // 前转来源: MEM 级 ALU 结果优先于 WB 级写回数据.
    // MEM 级如果是 load, 它的数据还没准备好, 由 Load-use 阻塞处理, 不参与前转.
    wire mem_fwd_rs1 = MEM_regwr & (MEM_rd != 5'd0) & (MEM_rd == EX_rs1) & ~MEM_memtoreg;
    wire mem_fwd_rs2 = MEM_regwr & (MEM_rd != 5'd0) & (MEM_rd == EX_rs2) & ~MEM_memtoreg;
    wire wb_fwd_rs1  = WB_regwr  & (WB_rd  != 5'd0) & (WB_rd  == EX_rs1);
    wire wb_fwd_rs2  = WB_regwr  & (WB_rd  != 5'd0) & (WB_rd  == EX_rs2);

    wire [31:0] ex_rs1data = mem_fwd_rs1 ? MEM_alu_result :
                             wb_fwd_rs1  ? wb_data        : EX_rs1data;
    wire [31:0] ex_rs2data = mem_fwd_rs2 ? MEM_alu_result :
                             wb_fwd_rs2  ? wb_data        : EX_rs2data;

    // ALU 输入选择
    wire [31:0] ex_alu_a = EX_aluasrc ? EX_pc : ex_rs1data;
    reg  [31:0] ex_alu_b;

    always @(*) begin
        case (EX_alubsrc)
            ALU_B_RS2:  ex_alu_b = ex_rs2data;
            ALU_B_IMM:  ex_alu_b = EX_imm;
            ALU_B_FOUR: ex_alu_b = 32'd4;
            default:    ex_alu_b = ex_rs2data;
        endcase
    end

    wire [4:0]  ex_shamt = ex_alu_b[4:0];
    wire [31:0] ex_sum   = ex_alu_a + ex_alu_b;
    wire [31:0] ex_diff  = ex_alu_a - ex_alu_b;
    wire [31:0] ex_shra  = $signed(ex_alu_a) >>> ex_shamt;
    wire        ex_lt_s  = $signed(ex_alu_a) < $signed(ex_alu_b);
    wire        ex_lt_u  = ex_alu_a < ex_alu_b;

    reg [31:0] ex_alu_result;
    always @(*) begin
        case (EX_aluctr)
            ALU_ADD:  ex_alu_result = ex_sum;
            ALU_SUB:  ex_alu_result = ex_diff;
            ALU_SLL:  ex_alu_result = ex_alu_a << ex_shamt;
            ALU_SLT:  ex_alu_result = {31'b0, ex_lt_s};
            ALU_SLTU: ex_alu_result = {31'b0, ex_lt_u};
            ALU_XOR:  ex_alu_result = ex_alu_a ^ ex_alu_b;
            ALU_SRL:  ex_alu_result = ex_alu_a >> ex_shamt;
            ALU_SRA:  ex_alu_result = ex_shra;
            ALU_OR:   ex_alu_result = ex_alu_a | ex_alu_b;
            ALU_AND:  ex_alu_result = ex_alu_a & ex_alu_b;
            ALU_LUI:  ex_alu_result = ex_alu_b;
            default:  ex_alu_result = 32'b0;
        endcase
    end

    // 分支判断: 相等直接比较两个源操作数, 大小用 ALU 的 SLT/SLTU 结果
    wire ex_equal = (ex_alu_a == ex_alu_b);
    wire ex_less  = (EX_aluctr == ALU_SLTU) ? ex_lt_u : ex_lt_s;

    reg ex_branch_taken;
    always @(*) begin
        case (EX_branch)
            BR_JAL:  ex_branch_taken = 1'b1;
            BR_JALR: ex_branch_taken = 1'b1;
            BR_BEQ:  ex_branch_taken = ex_equal;
            BR_BNE:  ex_branch_taken = ~ex_equal;
            BR_LT:   ex_branch_taken = ex_less;
            BR_GE:   ex_branch_taken = ~ex_less;
            default: ex_branch_taken = 1'b0;
        endcase
    end

    // 跳转目标: 分支/jal 用 PC+imm, jalr 用 rs1+imm
    wire [31:0] ex_pc_imm       = EX_pc + EX_imm;
    wire [31:0] ex_rs1_imm      = ex_rs1data + EX_imm;
    wire [31:0] ex_rs1_imm_al   = {ex_rs1_imm[31:1], 1'b0};
    wire [31:0] ex_branch_target = (EX_branch == BR_JALR) ? ex_rs1_imm_al : ex_pc_imm;

    // ------------------------------------------------------------------
    // 冒险控制
    // ------------------------------------------------------------------

    // Load-use: EX 阶段的指令要用 MEM 阶段 load 的结果
    wire load_use = MEM_regwr & MEM_memtoreg & (MEM_rd != 5'd0) &
                    ((MEM_rd == EX_rs1) | (MEM_rd == EX_rs2));

    wire stallIF = load_use;    // PC 保持
    wire stallID = load_use;    // IF/ID 保持
    wire stallEX = load_use;    // ID/EX 保持
    wire flushEX = load_use;    // EX/MEM 清零, 插入气泡

    // 跳转在 EX 阶段解决, 冲刷 IF/ID 和 ID/EX.
    // 阻塞的周期里跳转结果是用旧数据算的, 必须屏蔽冲刷
    wire flushIF = ex_branch_taken & ~stallID;   // 清 IF/ID
    wire flushID = ex_branch_taken & ~stallEX;   // 清 ID/EX

    // ------------------------------------------------------------------
    // WB 阶段: 选择写回数据
    // ------------------------------------------------------------------

    assign wb_data = WB_memtoreg ? WB_memout : WB_alu_result;

    // ------------------------------------------------------------------
    // MEM 阶段: 读数据存储器 (上升沿), 写数据存储器 (下降沿)
    // ------------------------------------------------------------------

    assign dmemaddr   = MEM_alu_result;
    assign dmemdatain = MEM_rs2data;
    assign dmemop     = MEM_memop;
    assign dmemwe     = MEM_memwr & ~reset;
    assign dmemrdclk  = clock;      // 上升沿读
    assign dmemwrclk  = ~clock;     // 下降沿写

    // ------------------------------------------------------------------
    // 时序: 全部在时钟下降沿更新
    // ------------------------------------------------------------------

    // PC: 阻塞优先级最高, 其次是跳转
    always @(negedge clock) begin
        if (reset)
            pc <= 32'b0;
        else if (stallIF)
            pc <= pc;
        else if (ex_branch_taken)
            pc <= ex_branch_target;
        else
            pc <= pc_plus4;
    end

    always @(negedge clock) begin
        if (reset) begin
            IF_ID_pc    <= 32'b0;
            IF_ID_instr <= 32'b0;
        end else if (flushIF) begin
            IF_ID_pc    <= 32'b0;
            IF_ID_instr <= 32'b0;
        end else if (stallID) begin
            IF_ID_pc    <= IF_ID_pc;
            IF_ID_instr <= IF_ID_instr;
        end else begin
            IF_ID_pc    <= pc;
            IF_ID_instr <= imemdataout;
        end
    end

    always @(negedge clock) begin
        if (reset) begin
            EX_pc       <= 32'b0;
            EX_imm      <= 32'b0;
            EX_rs1data  <= 32'b0;
            EX_rs2data  <= 32'b0;
            EX_rs1      <= 5'b0;
            EX_rs2      <= 5'b0;
            EX_rd       <= 5'b0;
            EX_branch   <= BR_NONE;
            EX_aluasrc  <= ALU_A_RS1;
            EX_alubsrc  <= ALU_B_RS2;
            EX_aluctr   <= ALU_ADD;
            EX_memwr    <= 1'b0;
            EX_memop    <= MEM_WORD;
            EX_regwr    <= 1'b0;
            EX_memtoreg <= 1'b0;
        end else if (flushID) begin
            EX_pc       <= 32'b0;
            EX_imm      <= 32'b0;
            EX_rs1data  <= 32'b0;
            EX_rs2data  <= 32'b0;
            EX_rs1      <= 5'b0;
            EX_rs2      <= 5'b0;
            EX_rd       <= 5'b0;
            EX_branch   <= BR_NONE;
            EX_aluasrc  <= ALU_A_RS1;
            EX_alubsrc  <= ALU_B_RS2;
            EX_aluctr   <= ALU_ADD;
            EX_memwr    <= 1'b0;
            EX_memop    <= MEM_WORD;
            EX_regwr    <= 1'b0;
            EX_memtoreg <= 1'b0;
        end else if (stallEX) begin
            // 阻塞期间 EX 用旧数据算出的结果会被丢弃, 但 WB->EX 前转得到的新数据
            // 必须留在段寄存器里, 否则重新执行 EX 时旧指令已经离开 WB, 数据就丢了
            if (wb_fwd_rs1)
                EX_rs1data <= wb_data;
            if (wb_fwd_rs2)
                EX_rs2data <= wb_data;
        end else begin
            EX_pc       <= IF_ID_pc;
            EX_imm      <= id_imm;
            EX_rs1data  <= id_busA;
            EX_rs2data  <= id_busB;
            EX_rs1      <= rs1;
            EX_rs2      <= rs2;
            EX_rd       <= rd;
            EX_branch   <= id_branch;
            EX_aluasrc  <= id_aluasrc;
            EX_alubsrc  <= id_alubsrc;
            EX_aluctr   <= id_aluctr;
            EX_memwr    <= id_memwr;
            EX_memop    <= id_memop;
            EX_regwr    <= id_regwr;
            EX_memtoreg <= id_memtoreg;
        end
    end

    always @(negedge clock) begin
        if (reset | flushEX) begin
            MEM_alu_result <= 32'b0;
            MEM_rs2data    <= 32'b0;
            MEM_rd         <= 5'b0;
            MEM_memwr      <= 1'b0;
            MEM_memop      <= MEM_WORD;
            MEM_regwr      <= 1'b0;
            MEM_memtoreg   <= 1'b0;
        end else begin
            MEM_alu_result <= ex_alu_result;
            MEM_rs2data    <= ex_rs2data;
            MEM_rd         <= EX_rd;
            MEM_memwr      <= EX_memwr;
            MEM_memop      <= EX_memop;
            MEM_regwr      <= EX_regwr;
            MEM_memtoreg   <= EX_memtoreg;
        end
    end

    always @(negedge clock) begin
        if (reset) begin
            WB_alu_result <= 32'b0;
            WB_memout     <= 32'b0;
            WB_rd         <= 5'b0;
            WB_regwr      <= 1'b0;
            WB_memtoreg   <= 1'b0;
        end else begin
            WB_alu_result <= MEM_alu_result;
            WB_memout     <= dmemdataout;
            WB_rd         <= MEM_rd;
            WB_regwr      <= MEM_regwr;
            WB_memtoreg   <= MEM_memtoreg;
        end
    end

    // ------------------------------------------------------------------
    // 寄存器堆: 上升沿写回, 组合读.
    // WB 阶段的数据因此可以在同一个周期里被 ID 阶段读到, 这就是 WB->ID 前转
    // ------------------------------------------------------------------

    rv32i_regfile myregfile(
        .WrClk (clock),
        .RegWr (WB_regwr & ~reset),
        .Ra    (rs1),
        .Rb    (rs2),
        .Rw    (WB_rd),
        .busW  (wb_data),
        .busA  (id_busA),
        .busB  (id_busB)
    );

    // ------------------------------------------------------------------
    // 调试接口
    // ------------------------------------------------------------------

    assign dbgdata = pc;

endmodule

// 寄存器堆: 两读一写, x0 恒为 0, 上升沿写入

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

    always @(posedge WrClk) begin
        if (RegWr && (Rw != 5'd0))
            regs[Rw] <= busW;
    end

endmodule

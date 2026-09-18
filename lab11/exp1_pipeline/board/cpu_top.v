//=======================================================================
// lab11 五段流水线 RV32I CPU (IF / ID / EX / MEM / WB)
// 时钟约定: 所有段寄存器与 PC 在时钟下降沿更新
//   - 指令存储器上升沿读取(地址=PC), 下降沿写入 IF/ID
//   - 寄存器堆读组合, 写上升沿(支持 WB->ID 前转)
//   - 数据存储器上升沿读, 下降沿写
// 冒险处理:
//   - 数据: WB->ID(隐式) / MEM->EX / WB->EX 前转; load-use 阻塞 1 周期
//   - 控制: 跳转统一在 EX 解决, 冲刷 IF/ID 与 ID/EX 两条指令
// 端口与讲义一致, 顶层名 rv32ip
//=======================================================================
module rv32ip(
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

    localparam [31:0] NOP = 32'h0000_0013;   // addi x0,x0,0

    //---------------------------------------------------------------
    // IF: PC
    //---------------------------------------------------------------
    reg  [31:0] PC;

    //---------------------------------------------------------------
    // IF/ID
    //---------------------------------------------------------------
    reg  [31:0] ifid_pc;
    reg  [31:0] ifid_instr;

    wire [4:0] ifid_rs1 = ifid_instr[19:15];
    wire [4:0] ifid_rs2 = ifid_instr[24:20];
    wire [4:0] ifid_rd  = ifid_instr[11:7];

    //---------------------------------------------------------------
    // ID: 译码 / 寄存器读
    //---------------------------------------------------------------
    wire [2:0] id_extop;
    wire       id_regwr, id_alu_asrc, id_memtoreg, id_memwr;
    wire [1:0] id_alu_bsrc;
    wire [3:0] id_aluctr;
    wire [2:0] id_branch, id_memop;
    wire       id_uses_rs1, id_uses_rs2;
    wire [31:0] id_imm;

    immgen u_immgen (.instr(ifid_instr), .extop(id_extop), .imm(id_imm));

    ctrl u_ctrl (
        .instr(ifid_instr),
        .extop(id_extop), .regwr(id_regwr),
        .alu_asrc(id_alu_asrc), .alu_bsrc(id_alu_bsrc), .aluctr(id_aluctr),
        .branch(id_branch), .memtoreg(id_memtoreg), .memwr(id_memwr),
        .memop(id_memop), .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2)
    );

    wire [31:0] id_rs1data, id_rs2data;

    //---------------------------------------------------------------
    // ID/EX
    //---------------------------------------------------------------
    reg  [31:0] idex_pc, idex_imm, idex_rs1data, idex_rs2data;
    reg  [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg  [9:0]  idex_ex;                 // {branch, alu_asrc, alu_bsrc, aluctr}
    reg  [3:0]  idex_mem;                // {memop, memwr}
    reg  [1:0]  idex_wb;                 // {regwr, memtoreg}

    //---------------------------------------------------------------
    // EX: 前转 / ALU / 分支判断
    //---------------------------------------------------------------
    wire [31:0] wb_data = memwb_wb[0] ? memwb_mem : memwb_alu;

    wire exmem_regwr    = exmem_wb[1];
    wire exmem_memtoreg = exmem_wb[0];
    wire memwb_regwr    = memwb_wb[1];
    wire memwb_memtoreg = memwb_wb[0];

    wire [31:0] fwd_rs1 =
        (exmem_regwr && !exmem_memtoreg && (exmem_rd != 5'd0) && (exmem_rd == idex_rs1))
            ? exmem_alu :
        (memwb_regwr && (memwb_rd != 5'd0) && (memwb_rd == idex_rs1))
            ? wb_data : idex_rs1data;

    wire [31:0] fwd_rs2 =
        (exmem_regwr && !exmem_memtoreg && (exmem_rd != 5'd0) && (exmem_rd == idex_rs2))
            ? exmem_alu :
        (memwb_regwr && (memwb_rd != 5'd0) && (memwb_rd == idex_rs2))
            ? wb_data : idex_rs2data;

    wire        ex_alu_asrc = idex_ex[6];
    wire [1:0]  ex_alu_bsrc = idex_ex[5:4];
    wire [3:0]  ex_aluctr   = idex_ex[3:0];
    wire [2:0]  ex_branch   = idex_ex[9:7];

    wire [31:0] ex_alu_a = ex_alu_asrc ? idex_pc : fwd_rs1;

    reg  [31:0] ex_alu_b;
    always @(*) begin
        case (ex_alu_bsrc)
            2'b00:   ex_alu_b = fwd_rs2;
            2'b01:   ex_alu_b = idex_imm;
            2'b10:   ex_alu_b = 32'd4;
            default: ex_alu_b = fwd_rs2;
        endcase
    end

    wire [31:0] ex_alu_result;
    wire        ex_zero, ex_less;

    alu u_alu (
        .A(ex_alu_a), .B(ex_alu_b), .ALUctr(ex_aluctr),
        .Result(ex_alu_result), .Zero(ex_zero), .Less(ex_less)
    );

    reg         ex_branch_taken;
    reg  [31:0] ex_branch_target;
    always @(*) begin
        case (ex_branch)
            3'b001:  begin ex_branch_taken = 1'b1;                 ex_branch_target = idex_pc + idex_imm; end
            3'b010:  begin ex_branch_taken = 1'b1;                 ex_branch_target = fwd_rs1 + idex_imm; end
            3'b100:  begin ex_branch_taken = ex_zero;              ex_branch_target = idex_pc + idex_imm; end
            3'b101:  begin ex_branch_taken = ~ex_zero;             ex_branch_target = idex_pc + idex_imm; end
            3'b110:  begin ex_branch_taken = ex_less;              ex_branch_target = idex_pc + idex_imm; end
            3'b111:  begin ex_branch_taken = ~ex_less;             ex_branch_target = idex_pc + idex_imm; end
            default: begin ex_branch_taken = 1'b0;                 ex_branch_target = 32'b0; end
        endcase
    end

    //---------------------------------------------------------------
    // EX/MEM
    //---------------------------------------------------------------
    reg  [31:0] exmem_alu, exmem_rs2;
    reg  [4:0]  exmem_rd;
    reg  [3:0]  exmem_mem;
    reg  [1:0]  exmem_wb;

    //---------------------------------------------------------------
    // MEM
    //---------------------------------------------------------------
    wire exmem_memwr   = exmem_mem[0];
    wire [2:0] exmem_memop = exmem_mem[3:1];

    assign dmemaddr   = exmem_alu;
    assign dmemdatain = exmem_rs2;
    assign dmemwe     = exmem_memwr;
    assign dmemop     = exmem_memop;
    assign dmemrdclk  = clock;
    assign dmemwrclk  = clock;

    //---------------------------------------------------------------
    // MEM/WB
    //---------------------------------------------------------------
    reg  [31:0] memwb_alu, memwb_mem;
    reg  [4:0]  memwb_rd;
    reg  [1:0]  memwb_wb;

    //---------------------------------------------------------------
    // 寄存器堆: 写上升沿, 读组合 (WB->ID 前转)
    //---------------------------------------------------------------
    regfile u_regfile (
        .WrClk(~clock), .RegWr(memwb_regwr),
        .Ra(ifid_rs1), .Rb(ifid_rs2), .Rw(memwb_rd),
        .busW(wb_data),
        .busA(id_rs1data), .busB(id_rs2data)
    );

    //---------------------------------------------------------------
    // 冒险检测
    //---------------------------------------------------------------
    wire idex_is_load = idex_wb[1] && idex_wb[0];   // regwr && memtoreg

    wire stall = idex_is_load && (idex_rd != 5'd0) &&
                 ((id_uses_rs1 && (idex_rd == ifid_rs1)) ||
                  (id_uses_rs2 && (idex_rd == ifid_rs2)));

    wire flush = ex_branch_taken;                    // EX 阶段解决跳转

    //---------------------------------------------------------------
    // PC 与段寄存器更新 (下降沿)
    //---------------------------------------------------------------
    assign imemaddr = PC;
    assign imemclk  = clock;

    wire [31:0] nextpc = PC + 32'd4;

    always @(negedge clock) begin
        if (reset) begin
            PC         <= 32'b0;
            ifid_pc    <= 32'b0;    ifid_instr <= NOP;
            idex_pc    <= 32'b0;    idex_imm <= 32'b0;
            idex_rs1data <= 32'b0;  idex_rs2data <= 32'b0;
            idex_rs1   <= 5'd0;     idex_rs2 <= 5'd0;   idex_rd <= 5'd0;
            idex_ex    <= 10'd0;    idex_mem <= 4'd0;   idex_wb <= 2'd0;
            exmem_alu  <= 32'b0;    exmem_rs2 <= 32'b0;
            exmem_rd   <= 5'd0;     exmem_mem <= 4'd0;  exmem_wb <= 2'd0;
            memwb_alu  <= 32'b0;    memwb_mem <= 32'b0;
            memwb_rd   <= 5'd0;     memwb_wb <= 2'd0;
        end else if (stall) begin
            // load-use: 冻结 PC 与 IF/ID, 向 EX 插气泡
            PC         <= PC;
            ifid_pc    <= ifid_pc;  ifid_instr <= ifid_instr;
            idex_pc    <= 32'b0;    idex_imm <= 32'b0;
            idex_rs1data <= 32'b0;  idex_rs2data <= 32'b0;
            idex_rs1   <= 5'd0;     idex_rs2 <= 5'd0;   idex_rd <= 5'd0;
            idex_ex    <= 10'd0;    idex_mem <= 4'd0;   idex_wb <= 2'd0;
            exmem_alu  <= ex_alu_result; exmem_rs2 <= fwd_rs2;
            exmem_rd   <= idex_rd;  exmem_mem <= idex_mem; exmem_wb <= idex_wb;
            memwb_alu  <= exmem_alu; memwb_mem <= dmemdataout;
            memwb_rd   <= exmem_rd; memwb_wb <= exmem_wb;
        end else if (flush) begin
            // 跳转: 冲刷 IF/ID 与 ID/EX, PC 取分支目标
            PC         <= ex_branch_target;
            ifid_pc    <= 32'b0;    ifid_instr <= NOP;
            idex_pc    <= 32'b0;    idex_imm <= 32'b0;
            idex_rs1data <= 32'b0;  idex_rs2data <= 32'b0;
            idex_rs1   <= 5'd0;     idex_rs2 <= 5'd0;   idex_rd <= 5'd0;
            idex_ex    <= 10'd0;    idex_mem <= 4'd0;   idex_wb <= 2'd0;
            exmem_alu  <= ex_alu_result; exmem_rs2 <= fwd_rs2;
            exmem_rd   <= idex_rd;  exmem_mem <= idex_mem; exmem_wb <= idex_wb;
            memwb_alu  <= exmem_alu; memwb_mem <= dmemdataout;
            memwb_rd   <= exmem_rd; memwb_wb <= exmem_wb;
        end else begin
            PC         <= nextpc;
            ifid_pc    <= PC;       ifid_instr <= imemdataout;
            idex_pc    <= ifid_pc;  idex_imm <= id_imm;
            idex_rs1data <= id_rs1data; idex_rs2data <= id_rs2data;
            idex_rs1   <= ifid_rs1; idex_rs2 <= ifid_rs2;  idex_rd <= ifid_rd;
            idex_ex    <= {id_branch, id_alu_asrc, id_alu_bsrc, id_aluctr};
            idex_mem   <= {id_memop, id_memwr};
            idex_wb    <= {id_regwr, id_memtoreg};
            exmem_alu  <= ex_alu_result; exmem_rs2 <= fwd_rs2;
            exmem_rd   <= idex_rd;  exmem_mem <= idex_mem; exmem_wb <= idex_wb;
            memwb_alu  <= exmem_alu; memwb_mem <= dmemdataout;
            memwb_rd   <= exmem_rd; memwb_wb <= exmem_wb;
        end
    end

    assign dbgdata = PC;

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
    output reg [2:0] memop,
    output reg       uses_rs1,
    output reg       uses_rs2
);
    wire [6:0] op   = instr[6:0];
    wire [2:0] f3   = instr[14:12];
    wire       f7b5 = instr[30];

    always @(*) begin
        extop    = 3'b000;
        regwr    = 1'b0;
        alu_asrc = 1'b0;
        alu_bsrc = 2'b00;
        aluctr   = 4'b0000;
        branch   = 3'b000;
        memtoreg = 1'b0;
        memwr    = 1'b0;
        memop    = 3'b010;
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;

        case (op)
            7'b0110111: begin // lui
                extop = 3'b001; regwr = 1'b1; alu_bsrc = 2'b01; aluctr = 4'b0011;
            end
            7'b0010111: begin // auipc
                extop = 3'b001; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b01; aluctr = 4'b0000;
            end
            7'b0010011: begin // op-imm
                extop = 3'b000; regwr = 1'b1; alu_bsrc = 2'b01; uses_rs1 = 1'b1;
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
                regwr = 1'b1; alu_bsrc = 2'b00; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
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
            7'b1101111: begin // jal
                extop = 3'b100; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b10;
                aluctr = 4'b0000; branch = 3'b001;
            end
            7'b1100111: begin // jalr
                extop = 3'b000; regwr = 1'b1; alu_asrc = 1'b1; alu_bsrc = 2'b10;
                aluctr = 4'b0000; branch = 3'b010; uses_rs1 = 1'b1;
            end
            7'b1100011: begin // 条件分支
                extop = 3'b011; alu_bsrc = 2'b00; aluctr = 4'b0010;
                uses_rs1 = 1'b1; uses_rs2 = 1'b1;
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
                aluctr = 4'b0000; memtoreg = 1'b1; memwr = 1'b0; uses_rs1 = 1'b1;
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
                uses_rs1 = 1'b1; uses_rs2 = 1'b1;
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
// lab11 五段流水线上板外壳 (与 pipeline.v/dmem.v 拼接为自包含 cpu_top.v)
//   SW0 = 0: 自动运行(慢速), SW0 = 1: BTNC 单步
//   CPU_RESETN: 低有效复位
//   数码管: 32bit PC; LED[15:0]: 当前取指低 16 位
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
            if (step) cpu_clk <= ~cpu_clk;
        end else begin
            if (tick) cpu_clk <= ~cpu_clk;
        end

    //--- CPU + 存储器 ---
    wire [31:0] imemaddr, imemdataout;
    wire        imemclk;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire        dmemrdclk, dmemwrclk, dmemwe;
    wire [2:0]  dmemop;
    wire [31:0] dbgdata;

    rv32ip u_cpu (
        .clock(cpu_clk), .reset(rst),
        .imemaddr(imemaddr), .imemdataout(imemdataout), .imemclk(imemclk),
        .dmemaddr(dmemaddr), .dmemdataout(dmemdataout), .dmemdatain(dmemdatain),
        .dmemrdclk(dmemrdclk), .dmemwrclk(dmemwrclk), .dmemop(dmemop),
        .dmemwe(dmemwe), .dbgdata(dbgdata)
    );

    // 流水线: 指令存储器上升沿读取, 地址为 PC
    imem_rom u_rom (.clk(imemclk), .addr(imemaddr), .dout(imemdataout));

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
            4'd14:   seg = 7'b0000110;
            4'd15:   seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end
    assign HEX = {seg, 1'b1};

endmodule


//-----------------------------------------------------------------------
// 板上指令 ROM: 上升沿读取
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

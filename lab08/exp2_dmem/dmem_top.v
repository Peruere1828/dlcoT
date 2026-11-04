`timescale 1ns / 1ps

//-----------------------------------------------------------------------
// 上板数据存储器 128 KiB: 32768 字 x 32 bit, 手动实现, 不使用 IP 核
// 4 个 8 位字节通道, 按 MemOP 译码写使能, 支持 1/2/4 字节读写
// 独立读时钟/写时钟: 读在上升沿, 写在下降沿
// 上板文件: dmem_top.v + dmem_top.xdc
//-----------------------------------------------------------------------
module dmem_128k(
    input  [31:0] addr,
    output reg [31:0] dataout,
    input  [31:0] datain,
    input  rdclk,
    input  wrclk,
    input  [2:0] memop,
    input  we
);

    localparam WORDS = 32768;              // 128 KiB / 4 B

    // 手动实现的存储器: 把 32 位字拆成 4 个 8 位字节通道.
    // 每个通道各是一块 32768 x 8 的双端口 RAM, 只做整字节写入,
    // 避免对同一个存储单元的部分 bit 做写操作.
    (* ram_style = "block" *) reg [7:0] mem_b0 [0:WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem_b1 [0:WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem_b2 [0:WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem_b3 [0:WORDS-1];

    wire [14:0] idx = addr[16:2];
    wire [1:0]  off = addr[1:0];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem_b0[i] = 8'b0;
            mem_b1[i] = 8'b0;
            mem_b2[i] = 8'b0;
            mem_b3[i] = 8'b0;
        end
    end

    // 按 MemOP 和地址低两位译码字节写使能:
    //   字   be = 1111
    //   半字 be = 0011 / 1100
    //   字节 be = 0001 / 0010 / 0100 / 1000
    // 手册不要求处理未对齐访问, 半字只按 addr[1] 选择低半字或高半字
    reg [3:0] be;
    always @(*) begin
        be = 4'b0000;
        if (we) begin
            case (memop)
                3'b010: be = 4'b1111;
                3'b001, 3'b101:
                    be = off[1] ? 4'b1100 : 4'b0011;
                3'b000, 3'b100: begin
                    case (off)
                        2'b00: be = 4'b0001;
                        2'b01: be = 4'b0010;
                        2'b10: be = 4'b0100;
                        default: be = 4'b1000;
                    endcase
                end
                default: be = 4'b0000;
            endcase
        end
    end

    // 写数据按 MemOP 放到对应字节通道:
    //   字写:   b3..b0 = datain[31:24], [23:16], [15:8], [7:0]
    //   半字写: 低半字用 datain[15:0], 高半字也用 datain[15:0]
    //   字节写: 四个通道都准备 datain[7:0], 由 be 选其中一个
    reg [7:0] wb0, wb1, wb2, wb3;
    always @(*) begin
        case (memop)
            3'b010: begin
                wb0 = datain[7:0];
                wb1 = datain[15:8];
                wb2 = datain[23:16];
                wb3 = datain[31:24];
            end
            3'b001, 3'b101: begin
                wb0 = datain[7:0];
                wb1 = datain[15:8];
                wb2 = datain[7:0];
                wb3 = datain[15:8];
            end
            default: begin
                wb0 = datain[7:0];
                wb1 = datain[7:0];
                wb2 = datain[7:0];
                wb3 = datain[7:0];
            end
        endcase
    end

    // 写时钟上升沿只写入 be 选中的字节通道, 其余通道保持不变
    always @(posedge wrclk) begin
        if (be[0]) mem_b0[idx] <= wb0;
        if (be[1]) mem_b1[idx] <= wb1;
        if (be[2]) mem_b2[idx] <= wb2;
        if (be[3]) mem_b3[idx] <= wb3;
    end

    // 读时钟上升沿同时读出四个字节通道并拼成 32 位字,
    // 地址低两位也一并锁存, 保证扩展用的是这次读出对应的偏移
    reg [31:0] rdword;
    reg [1:0]  rd_off;
    always @(posedge rdclk) begin
        rdword <= {mem_b3[idx], mem_b2[idx], mem_b1[idx], mem_b0[idx]};
        rd_off <= off;
    end

    // 按 MemOP 从 32 位字中选择 8/16/32 位并做符号或零扩展
    always @(*) begin
        case (memop)
            3'b010:  dataout = rdword;
            3'b001:  dataout = rd_off[1] ? {{16{rdword[31]}}, rdword[31:16]}
                                         : {{16{rdword[15]}}, rdword[15:0]};
            3'b101:  dataout = rd_off[1] ? {16'b0, rdword[31:16]}
                                         : {16'b0, rdword[15:0]};
            3'b000:  dataout = (rd_off == 2'b00) ? {{24{rdword[7]}},  rdword[7:0]}
                             : (rd_off == 2'b01) ? {{24{rdword[15]}}, rdword[15:8]}
                             : (rd_off == 2'b10) ? {{24{rdword[23]}}, rdword[23:16]}
                                                 : {{24{rdword[31]}}, rdword[31:24]};
            3'b100:  dataout = (rd_off == 2'b00) ? {24'b0, rdword[7:0]}
                             : (rd_off == 2'b01) ? {24'b0, rdword[15:8]}
                             : (rd_off == 2'b10) ? {24'b0, rdword[23:16]}
                                                 : {24'b0, rdword[31:24]};
            default: dataout = rdword;
        endcase
    end

endmodule


module dmem_top(
    input         CLK100MHZ,
    input  [15:0] SW,
    output [7:0]  AN,
    output [7:0]  HEX
);

    parameter SCAN_DIV = 16;

    // SW[2:0]=memop, SW[3]=we, SW[7:4]=地址低4位, SW[15:8]=写数据(重复4次)
    wire [2:0]  memop  = SW[2:0];
    wire        we     = SW[3];
    wire [31:0] addr   = {28'b0, SW[7:4]};
    wire [31:0] datain = {4{SW[15:8]}};
    wire [31:0] dataout;

    // 读时钟上升沿, 写时钟取反 -> 写发生在系统时钟下降沿
    dmem_128k u_dmem(
        .addr(addr),
        .dataout(dataout),
        .datain(datain),
        .rdclk(CLK100MHZ),
        .wrclk(~CLK100MHZ),
        .memop(memop),
        .we(we)
    );

    reg [SCAN_DIV+2:0] scan_cnt;
    initial scan_cnt = 0;
    always @(posedge CLK100MHZ)
        scan_cnt <= scan_cnt + 1'b1;
    wire [2:0] dig = scan_cnt[SCAN_DIV+2:SCAN_DIV];

    // 位选(低有效)与当前数码管对应的 4bit
    reg [7:0] an;
    reg [3:0] nib;
    always @(*) begin
        case (dig)
            3'd0: begin nib = dataout[3:0];   an = 8'b1111_1110; end
            3'd1: begin nib = dataout[7:4];   an = 8'b1111_1101; end
            3'd2: begin nib = dataout[11:8];  an = 8'b1111_1011; end
            3'd3: begin nib = dataout[15:12]; an = 8'b1111_0111; end
            3'd4: begin nib = dataout[19:16]; an = 8'b1110_1111; end
            3'd5: begin nib = dataout[23:20]; an = 8'b1101_1111; end
            3'd6: begin nib = dataout[27:24]; an = 8'b1011_1111; end
            default: begin nib = dataout[31:28]; an = 8'b0111_1111; end
        endcase
    end

    // 共阳极段码 seg[6:0] = {G,F,E,D,C,B,A}, 低电平点亮
    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'h0: seg7 = 7'b1000000;
                4'h1: seg7 = 7'b1111001;
                4'h2: seg7 = 7'b0100100;
                4'h3: seg7 = 7'b0110000;
                4'h4: seg7 = 7'b0011001;
                4'h5: seg7 = 7'b0010010;
                4'h6: seg7 = 7'b0000010;
                4'h7: seg7 = 7'b1111000;
                4'h8: seg7 = 7'b0000000;
                4'h9: seg7 = 7'b0010000;
                4'hA: seg7 = 7'b0001000;
                4'hB: seg7 = 7'b0000011;
                4'hC: seg7 = 7'b1000110;
                4'hD: seg7 = 7'b0100001;
                4'hE: seg7 = 7'b0000110;
                default: seg7 = 7'b0001110;
            endcase
        end
    endfunction

    wire [6:0] seg = seg7(nib);

    assign AN  = an;
    assign HEX = {seg, 1'b1};

endmodule

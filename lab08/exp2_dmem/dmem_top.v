//-----------------------------------------------------------------------
// 上板数据存储器 128KB: 32768 字 x 32bit, 独立读时钟/写时钟
// 先读后改再整字写, 支持字/半字/字节读写与符号、零扩展
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

    (* ram_style = "block" *)
    reg [31:0] mem [0:32767];

    wire [14:0] idx = addr[16:2];
    wire [1:0]  off = addr[1:0];

    integer i;
    initial begin
        for (i = 0; i < 32768; i = i + 1)
            mem[i] = 32'b0;
    end

    // 读时钟上升沿读整字, 读出数据按 memop 与地址低位扩展
    reg [31:0] rdword;
    always @(posedge rdclk)
        rdword <= mem[idx];

    always @(*) begin
        case (memop)
            3'b010:  dataout = rdword;
            3'b001:  dataout = off[1] ? {{16{rdword[31]}}, rdword[31:16]}
                                      : {{16{rdword[15]}}, rdword[15:0]};
            3'b101:  dataout = off[1] ? {16'b0, rdword[31:16]}
                                      : {16'b0, rdword[15:0]};
            3'b000:  dataout = (off == 2'b00) ? {{24{rdword[7]}},  rdword[7:0]}
                             : (off == 2'b01) ? {{24{rdword[15]}}, rdword[15:8]}
                             : (off == 2'b10) ? {{24{rdword[23]}}, rdword[23:16]}
                                              : {{24{rdword[31]}}, rdword[31:24]};
            3'b100:  dataout = (off == 2'b00) ? {24'b0, rdword[7:0]}
                             : (off == 2'b01) ? {24'b0, rdword[15:8]}
                             : (off == 2'b10) ? {24'b0, rdword[23:16]}
                                              : {24'b0, rdword[31:24]};
            default: dataout = rdword;
        endcase
    end

    // 写数据组装: 只替换对应字节/半字, 其余位保留
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

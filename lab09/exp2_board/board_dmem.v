`timescale 1ns / 1ps
//==============================================================================
// board_dmem.v : 上板数据存储器, 4KB
// 读时钟上升沿读整字, 写时钟上升沿按 memop 改写对应字节/半字
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

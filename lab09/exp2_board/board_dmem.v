`timescale 1ns / 1ps

// board_dmem.v : 上板数据存储器, 4KB
// 读在 rdclk 的上升沿读整字, 写在 wrclk 的下降沿按 memop 改写对应字节/半字
// 两个端口都接 CPU 时钟: 上升沿先读出旧字, 下降沿再用它拼出按字节/半字写入的新字

module board_dmem(
    input  wire [31:0] addr,
    input  wire [31:0] datain,
    input  wire        rdclk,
    input  wire        wrclk,
    input  wire [2:0]  memop,
    input  wire        we,
    output wire [31:0] dataout
);

    // memop 编码与 load/store 的 funct3 相同
    localparam [2:0] MEM_BYTE   = 3'b000,
                     MEM_HALF   = 3'b001,
                     MEM_WORD   = 3'b010,
                     MEM_BYTE_U = 3'b100,
                     MEM_HALF_U = 3'b101;

    // 地址最低两位, 即字节在字内的位置
    localparam [1:0] OFF_B0 = 2'd0,
                     OFF_B1 = 2'd1,
                     OFF_B2 = 2'd2;

    localparam integer MEM_WORDS = 1024;   // 4KB / 4B
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
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
            MEM_WORD:   rdata = rdword;
            MEM_HALF:   rdata = off[1] ? {{16{rdword[31]}}, rdword[31:16]}
                                      : {{16{rdword[15]}}, rdword[15:0]};
            MEM_HALF_U: rdata = off[1] ? {16'b0, rdword[31:16]}
                                      : {16'b0, rdword[15:0]};
            MEM_BYTE:   rdata = (off == OFF_B0) ? {{24{rdword[7]}},  rdword[7:0]}
                              : (off == OFF_B1) ? {{24{rdword[15]}}, rdword[15:8]}
                              : (off == OFF_B2) ? {{24{rdword[23]}}, rdword[23:16]}
                                                : {{24{rdword[31]}}, rdword[31:24]};
            MEM_BYTE_U: rdata = (off == OFF_B0) ? {24'b0, rdword[7:0]}
                              : (off == OFF_B1) ? {24'b0, rdword[15:8]}
                              : (off == OFF_B2) ? {24'b0, rdword[23:16]}
                                                : {24'b0, rdword[31:24]};
            default: rdata = rdword;
        endcase
    end

    assign dataout = rdata;

    reg [31:0] wdata;
    always @(*) begin
        case (memop)
            MEM_WORD:   wdata = datain;
            MEM_HALF, MEM_HALF_U:
                wdata = off[1] ? {datain[15:0], rdword[15:0]}
                               : {rdword[31:16], datain[15:0]};
            MEM_BYTE, MEM_BYTE_U:
                wdata = (off == OFF_B0) ? {rdword[31:8],   datain[7:0]}
                      : (off == OFF_B1) ? {rdword[31:16],  datain[7:0], rdword[7:0]}
                      : (off == OFF_B2) ? {rdword[31:24],  datain[7:0], rdword[15:0]}
                                       : {datain[7:0],    rdword[23:0]};
            default: wdata = datain;
        endcase
    end

    always @(negedge wrclk)
        if (we)
            mem[idx] <= wdata;

endmodule

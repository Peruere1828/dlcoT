module dmem(
    input  [31:0] addr,
    output reg [31:0] dataout,
    input  [31:0] datain,
    input  rdclk,
    input  wrclk,
    input  [2:0] memop,
    input  we
);

    localparam WORDS = 4096;              // 16KB, 满足至少 4k 字节的容量要求

    reg [31:0] mem [0:WORDS-1];
    reg [31:0] rdword;

    wire [11:0] idx = addr[13:2];
    wire [1:0]  off = addr[1:0];

    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'b0;
    end

    // 读: rdclk 上升沿读整字, 按 memop 与地址低位选择并扩展
    always @(posedge rdclk) begin
        rdword <= mem[idx];
        case (memop)
            3'b010:  dataout <= mem[idx];
            3'b001:  dataout <= off[1] ? {{16{mem[idx][31]}}, mem[idx][31:16]}
                                       : {{16{mem[idx][15]}}, mem[idx][15:0]};
            3'b101:  dataout <= off[1] ? {16'b0, mem[idx][31:16]}
                                       : {16'b0, mem[idx][15:0]};
            3'b000:  dataout <= (off == 2'b00) ? {{24{mem[idx][7]}},  mem[idx][7:0]}
                              : (off == 2'b01) ? {{24{mem[idx][15]}}, mem[idx][15:8]}
                              : (off == 2'b10) ? {{24{mem[idx][23]}}, mem[idx][23:16]}
                                               : {{24{mem[idx][31]}}, mem[idx][31:24]};
            3'b100:  dataout <= (off == 2'b00) ? {24'b0, mem[idx][7:0]}
                              : (off == 2'b01) ? {24'b0, mem[idx][15:8]}
                              : (off == 2'b10) ? {24'b0, mem[idx][23:16]}
                                               : {24'b0, mem[idx][31:24]};
            default: dataout <= mem[idx];
        endcase
    end

    // 写: rdclk 上升沿已读出旧字 rdword, 按 memop 只替换对应字节/半字,
    //     其余位保留, 在 wrclk 上升沿整字写回 (先读后改再写)
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

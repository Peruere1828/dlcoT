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

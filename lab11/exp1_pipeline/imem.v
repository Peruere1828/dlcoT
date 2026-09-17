// 指令存储器仿真模型: 上升沿读取 (对应流水线的 IF 阶段)
module imem #(
    parameter AW = 10
) (
    input         clk,
    input  [31:0] addr,
    output reg [31:0] dout
);

    reg [31:0] mem [0:(1<<AW)-1];

    integer i;
    initial begin
        for (i = 0; i < (1 << AW); i = i + 1)
            mem[i] = 32'h0000_0013;
        $readmemh("prog11.hex", mem);
    end

    always @(posedge clk)
        dout <= mem[addr[AW+1:2]];

endmodule

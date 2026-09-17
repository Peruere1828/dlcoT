// 指令存储器仿真模型: 下降沿读取 (与 CPU 的 imemclk 一致)
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
            mem[i] = 32'h0000_0013;      // 默认空操作 addi x0,x0,0
        $readmemh("prog10.hex", mem);
    end

    always @(negedge clk)
        dout <= mem[addr[AW+1:2]];

endmodule

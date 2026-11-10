`timescale 1ns / 1ps

// prog_rom.v : 上板指令 ROM, 4 x 256 字, 同步读
//
// 内容来自 prog.hex, 由 make_rom.py 从 prog_*.S 生成:
//   @000 程序 0 累加和    @100 程序 1 斐波那契
//   @200 程序 2 闰年判断  @300 程序 3 素数判断
// 每段 256 字, 不足处补 nop (0x00000013).
//
// 读时钟用 cpu_clk: 自动模式下是连续的 25/50MHz 时钟, 单步模式下是
// reset_pulse 或 BTNC 的单次脉冲. 地址用 PC, PC 在上一个下降沿稳定,
// 上升沿读出, 再由下降沿的 IF/ID 采样.

module prog_rom(
    input  wire        clk,      // cpu_clk, 上升沿读
    input  wire [1:0]  prog,     // 程序选择 SW[15:14]
    input  wire [7:0]  addr,     // PC 的字地址 PC[9:2]
    output reg  [31:0] dout
);

    localparam integer ROM_WORDS = 1024;   // 4 段 x 256 字
    (* rom_style = "block" *) reg [31:0] mem [0:ROM_WORDS-1];

    initial begin
        $readmemh("prog.hex", mem);
    end

    always @(posedge clk)
        dout <= mem[{prog, addr}];

endmodule

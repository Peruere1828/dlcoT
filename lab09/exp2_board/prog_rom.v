`timescale 1ns / 1ps

// prog_rom.v : 上板指令 ROM, 4 x 256 字, 同步读
//
// 内容来自 prog.hex, 由 make_rom.py 从 prog_*.S 生成:
//   @000 程序 0 累加和    @100 程序 1 斐波那契
//   @200 程序 2 闰年判断  @300 程序 3 素数判断
// 每段 256 字, 不足处补 nop (0x00000013).
//
// 读沿取时钟的下降沿, 和 CPU 更新 PC 的时刻对齐: 顶层直接把 cpu_clk 接进来,
// 不另外产生反相时钟. 地址由顶层接 NextPC, 于是这个下降沿同时完成
// "PC 装入 NextPC" 和 "读出 NextPC 处的指令", 与实验指导 9.2.4 的方案一致.
// 复位脉冲也会给出一个下降沿, 把 0 地址的指令预先读出来.

module prog_rom(
    input  wire        clk,      // CPU 时钟, 下降沿取指
    input  wire [1:0]  prog,     // 程序选择 SW[15:14]
    input  wire [7:0]  addr,     // NextPC 的字地址 NextPC[9:2]
    output reg  [31:0] dout
);

    localparam integer ROM_WORDS = 1024;   // 4 段 x 256 字
    (* rom_style = "block" *) reg [31:0] mem [0:ROM_WORDS-1];

    initial begin
        $readmemh("prog.hex", mem);
    end

    always @(negedge clk)
        dout <= mem[{prog, addr}];

endmodule

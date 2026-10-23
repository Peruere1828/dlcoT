`timescale 1ns / 1ps
//==============================================================================
// prog_rom.v : 上板指令 ROM, 4 x 256 字, 同步读
//
// 内容来自 prog.hex, 由 make_rom.py 从 prog_*.S 生成:
//   @000 程序 0 累加和    @100 程序 1 斐波那契
//   @200 程序 2 素数判断  @300 程序 3 最大公约数
// 每段 256 字, 不足处补 nop (0x00000013).
//
// 读时钟用 100MHz 而不是 CPU 的步进时钟: 复位期间 PC 一直是 0,
// ROM 已经在连续读 0 地址, 第一次取指不会拿到未初始化数据;
// CPU 进入一步之后, 下一个 100MHz 沿就能把新 PC 的指令读出来.
//==============================================================================
module prog_rom(
    input  wire        clk,      // 100MHz, 连续读
    input  wire [1:0]  prog,     // 程序选择 SW[15:14]
    input  wire [7:0]  addr,     // PC 的字地址 PC[9:2]
    output reg  [31:0] dout
);

    (* rom_style = "block" *) reg [31:0] mem [0:1023];

    initial begin
        $readmemh("prog.hex", mem);
    end

    always @(posedge clk)
        dout <= mem[{prog, addr}];

endmodule

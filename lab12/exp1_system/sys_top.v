`timescale 1ns / 1ps

// sys_top.v : lab12 计算机系统上板顶层
//
// 上板文件: sys_top.v + rv32ip.v + main.hex + main_d.hex + vga_font.txt
//           + sys_top.xdc
//   rv32ip.v      RV32I 五段流水线 CPU (与 lab10 相同)
//   main.hex      指令存储器初始化, sw/Makefile 生成
//   main_d.hex    数据存储器初始化, sw/Makefile 生成
//   vga_font.txt  256 字符 x 16 行字模, 从 lab11 复制
// 四个文件都要加入 Vivado 工程, 顶层设为 sys_top, $readmemh 才能找到数据.
//
// 板上操作:
//   CPU_RESETN 或 BTNC 复位, 复位后屏幕清空并显示提示符
//   键盘接 USB HID 口, VGA 接显示器, 分辨率 640x480@60Hz
//   LED[15]    系统心跳, 约 1Hz 闪烁; LED[14:0] 为软件写 0x0060_0000 的值
//   AN/HEX     八位数码管显示调试寄存器 0x0060_0004; SW[15]=1 时显示毫秒计数
//
// 内存映射 (CPU 数据地址):
//   0x0001_0000  16KB   指令存储器, 16K 字, 只读
//   0x0010_0000  128KB  数据存储器, 32K 字, 支持 sb/sh/sw
//   0x0020_0000  4KB    字符显存, 32 行 x 128 列, 按字节写
//   0x0021_0000         显示起始行 top_row, 写
//   0x0021_0004         光标位置 {物理行[4:0], 列[6:0]}, 写; 行号是 32 行环形缓冲里的
//                       物理行, 硬件减去 top_row 换成屏幕行再比较
//   0x0030_0000         键盘数据, 低 8 位 ASCII, 读不出队
//   0x0030_0004         键盘状态: bit0 有数据, bit1 溢出
//   0x0030_0008         键盘弹出, 写任意值出队
//   0x0040_0000         毫秒定时器, 只读
//   0x0050_0000         拨动开关 SW[15:0], 只读
//   0x0060_0000         LED[14:0], 写
//   0x0060_0004         数码管调试值, 写
//
// 时钟: 100MHz 四分频, CPU 与 VGA 都用 25MHz. CPU 时钟为 10ns 高的脉冲,
// VGA 像素时钟为 50% 占空比, 两者同源, 显存按异步读处理, 不需要跨时钟域.
//
// 时序约定与 lab10 相同: CPU 在时钟上升沿读指令/读数据存储器/写寄存器堆,
// 下降沿更新 PC 和段寄存器并写数据存储器. 外设寄存器写在下降沿, 读是组合的.

module sys_top #(
    parameter integer POR_BITS  = 19,   // 上电复位计数位宽, 计数到 2^18 约 2.6ms
    parameter integer SCAN_BITS = 15    // 数码管扫描分频
) (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNC,
    input  wire [15:0] SW,
    input  wire        PS2_CLK,
    input  wire        PS2_DATA,
    output wire [7:0]  AN,
    output wire [7:0]  HEX,
    output wire [15:0] LED,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B
);

    // ------------------------------------------------------------------
    // 时钟与复位
    // ------------------------------------------------------------------

    // div_cnt 每 10ns 加一. div_cnt[1] 是 25MHz 方波, 作像素时钟;
    // div_cnt == 3 时给出一个 10ns 高的脉冲, 作 CPU 时钟.
    reg [1:0] div_cnt;
    initial div_cnt = 2'd0;
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire pclk_raw   = div_cnt[1];
    wire cpu_pulse  = (div_cnt == 2'd3);

    wire pclk;

`ifdef __ICARUS__
    assign pclk = pclk_raw;
`else
    // 像素时钟要驱动整片 VGA 逻辑, 走全局时钟网络
    BUFG u_bufg_pclk (
        .I (pclk_raw),
        .O (pclk)
    );
`endif

    // 上电复位与按键复位. CPU_RESETN 低有效, BTNC 高有效.
    reg [POR_BITS-1:0] por_cnt;
    initial por_cnt = {POR_BITS{1'b0}};
    always @(posedge CLK100MHZ)
        if (!por_cnt[POR_BITS-1])
            por_cnt <= por_cnt + 1'b1;

    wire reset_raw = (~CPU_RESETN) | BTNC | (~por_cnt[POR_BITS-1]);

    wire cpu_clk;

`ifdef __ICARUS__
    // iverilog 没有 Xilinx 原语, 直接透传
    assign cpu_clk = cpu_pulse;
`else
    BUFG u_bufg_cpu (
        .I (cpu_pulse),
        .O (cpu_clk)
    );
`endif

    // 复位释放与 cpu_clk 的下降沿对齐, 避免在 CPU 时钟沿附近撤销复位
    reg [1:0] cpu_rst_sync;
    initial cpu_rst_sync = 2'b11;
    always @(negedge cpu_clk)
        cpu_rst_sync <= {cpu_rst_sync[0], reset_raw};

    wire cpu_reset = cpu_rst_sync[1];

    // 像素时钟域的复位
    reg [1:0] pclk_rst_sync;
    initial pclk_rst_sync = 2'b11;
    always @(posedge pclk)
        pclk_rst_sync <= {pclk_rst_sync[0], reset_raw};

    wire vga_reset = pclk_rst_sync[1];

    // ------------------------------------------------------------------
    // CPU 与总线
    // ------------------------------------------------------------------

    wire [31:0] imemaddr, imemdataout;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire [2:0]  dmemop;
    wire        dmemwe;

    rv32ip u_cpu (
        .clock        (cpu_clk),
        .reset        (cpu_reset),
        .imemaddr     (imemaddr),
        .imemdataout  (imemdataout),
        .imemclk      (),
        .dmemaddr     (dmemaddr),
        .dmemdataout  (dmemdataout),
        .dmemdatain   (dmemdatain),
        .dmemrdclk    (),
        .dmemwrclk    (),
        .dmemop       (dmemop),
        .dmemwe       (dmemwe),
        .dbgdata      ()
    );

    // 指令存储器: 与 CPU 共用 cpu_clk, 上升沿按 PC 读出, 下降沿由 IF/ID 采样
    sys_imem u_imem (
        .clk  (cpu_clk),
        .addr (imemaddr),
        .dout (imemdataout)
    );

    // 毫秒定时器在 100MHz 时钟域
    wire [31:0] ms_cnt;
    tick_ms u_tick (
        .clk   (CLK100MHZ),
        .reset (reset_raw),
        .ms    (ms_cnt)
    );

    // 键盘: PS/2 帧接收 + 扫描码转 ASCII
    wire [7:0] kbd_ch;
    wire       kbd_push;
    wire       kbd_shift, kbd_ready, kbd_ovf;

    ps2_ascii u_ps2 (
        .clk      (cpu_clk),
        .reset    (cpu_reset),
        .ps2_clk  (PS2_CLK),
        .ps2_data (PS2_DATA),
        .push     (kbd_push),
        .ch       (kbd_ch),
        .shift    (kbd_shift),
        .ready    (kbd_ready),
        .overflow (kbd_ovf)
    );

    // 外设与总线译码
    wire [4:0]  top_row;
    wire [11:0] cursor;
    wire [15:0] led_reg;
    wire [31:0] dbg_value;
    wire [11:0] vga_char_addr;
    wire [7:0]  vga_char;

    sys_bus u_bus (
        .clk        (cpu_clk),
        .reset      (cpu_reset),
        .addr       (dmemaddr),
        .datain     (dmemdatain),
        .we         (dmemwe),
        .memop      (dmemop),
        .dataout    (dmemdataout),
        .vga_addr   (vga_char_addr),
        .vga_char   (vga_char),
        .kbd_ch     (kbd_ch),
        .kbd_push   (kbd_push),
        .ms_cnt     (ms_cnt),
        .sw         (SW),
        .top_row    (top_row),
        .cursor     (cursor),
        .led        (led_reg),
        .dbg        (dbg_value)
    );

    // ------------------------------------------------------------------
    // VGA 字符显示
    // ------------------------------------------------------------------

    wire [9:0] h_addr, v_addr;
    wire [6:0] char_col;
    wire [3:0] pix_col;
    wire       hsync, vsync, valid;

    vga_ctrl u_vga (
        .pclk     (pclk),
        .reset    (vga_reset),
        .h_addr   (h_addr),
        .v_addr   (v_addr),
        .char_col (char_col),
        .pix_col  (pix_col),
        .hsync    (hsync),
        .vsync    (vsync),
        .valid    (valid)
    );

    wire [4:0] v_row  = v_addr[8:4];     // 0~29
    wire [3:0] v_line = v_addr[3:0];     // 字符内行号 0~15

    // 起始行寄存器把 32 行显存当作环形缓冲
    wire [5:0] row_sum   = {1'b0, top_row} + {1'b0, v_row};
    wire [4:0] disp_phys = row_sum[4:0];

    assign vga_char_addr = {disp_phys, char_col};

    // 字模 ROM: 地址 {ASCII, 行号}, 每行 12 bit, bit0 为最左侧点
    reg [11:0] font_rom [0:4095];
    initial $readmemh("vga_font.txt", font_rom);

    wire [11:0] font_row = font_rom[{vga_char, v_line}];
    wire        font_bit = font_row[pix_col];

    // 光标: 约 1.5Hz 闪烁的下划线
    reg [25:0] blink_cnt;
    initial blink_cnt = 26'd0;
    always @(posedge CLK100MHZ)
        blink_cnt <= blink_cnt + 1'b1;

    // 光标寄存器里的行号是显存的物理行, 屏幕行 = 物理行 - top_row, 6 位减法超出范围时变负
    wire [4:0]  cur_row_phys = cursor[11:7];
    wire [6:0]  cur_col      = cursor[6:0];
    wire [5:0]  cur_row_diff = {1'b0, cur_row_phys} - {1'b0, top_row};
    wire [4:0]  cur_disp_row = cur_row_diff[4:0];
    wire        cur_row_vis  = (cur_row_diff[5] == 1'b0) && (cur_disp_row < 5'd30);
    wire        cursor_here  = valid && cur_row_vis &&
                               (v_row == cur_disp_row) && (char_col == cur_col);
    wire        cursor_pix  = cursor_here && blink_cnt[25] &&
                              (v_line == 4'd14) && (pix_col <= 4'd6);

    wire pixel_on = valid && (char_col < 7'd70) && (font_bit || cursor_pix);

    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_R  = pixel_on ? 4'hF : 4'h0;
    assign VGA_G  = pixel_on ? 4'hF : 4'h0;
    assign VGA_B  = pixel_on ? 4'hF : 4'h0;

    // ------------------------------------------------------------------
    // LED 与数码管
    // ------------------------------------------------------------------

    // LED[15] 是心跳, 说明时钟和定时器在运行; 低 15 位由软件写
    assign LED = {ms_cnt[9], led_reg[14:0]};

    // 数码管显示调试值; SW[15] 置 1 时改显示毫秒计数, 便于观察系统是否在跑
    wire [31:0] disp = SW[15] ? ms_cnt : dbg_value;

    reg [SCAN_BITS+2:0] scan_cnt;
    initial scan_cnt = {(SCAN_BITS+3){1'b0}};
    always @(posedge CLK100MHZ)
        scan_cnt <= scan_cnt + 1'b1;

    wire [2:0] dig = scan_cnt[SCAN_BITS+2:SCAN_BITS];

    reg [3:0] nib;
    always @(*) begin
        case (dig)
            3'd0:    nib = disp[3:0];
            3'd1:    nib = disp[7:4];
            3'd2:    nib = disp[11:8];
            3'd3:    nib = disp[15:12];
            3'd4:    nib = disp[19:16];
            3'd5:    nib = disp[23:20];
            3'd6:    nib = disp[27:24];
            default: nib = disp[31:28];
        endcase
    end

    // AN[n] = 0 选中第 n 位数码管
    wire [7:0] an = ~(8'b0000_0001 << dig);

    // 共阳极段码 seg[6:0] = {G,F,E,D,C,B,A}, 低电平点亮
    localparam [6:0] SEG_0 = 7'b1000000,
                     SEG_1 = 7'b1111001,
                     SEG_2 = 7'b0100100,
                     SEG_3 = 7'b0110000,
                     SEG_4 = 7'b0011001,
                     SEG_5 = 7'b0010010,
                     SEG_6 = 7'b0000010,
                     SEG_7 = 7'b1111000,
                     SEG_8 = 7'b0000000,
                     SEG_9 = 7'b0010000,
                     SEG_A = 7'b0001000,
                     SEG_B = 7'b0000011,
                     SEG_C = 7'b1000110,
                     SEG_D = 7'b0100001,
                     SEG_E = 7'b0000110,
                     SEG_F = 7'b0001110;

    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'h0:    seg7 = SEG_0;
                4'h1:    seg7 = SEG_1;
                4'h2:    seg7 = SEG_2;
                4'h3:    seg7 = SEG_3;
                4'h4:    seg7 = SEG_4;
                4'h5:    seg7 = SEG_5;
                4'h6:    seg7 = SEG_6;
                4'h7:    seg7 = SEG_7;
                4'h8:    seg7 = SEG_8;
                4'h9:    seg7 = SEG_9;
                4'hA:    seg7 = SEG_A;
                4'hB:    seg7 = SEG_B;
                4'hC:    seg7 = SEG_C;
                4'hD:    seg7 = SEG_D;
                4'hE:    seg7 = SEG_E;
                default: seg7 = SEG_F;
            endcase
        end
    endfunction

    assign AN  = an;
    assign HEX = {seg7(nib), 1'b1};

endmodule


// ----------------------------------------------------------------------
// 指令存储器: 64KB, 16K 字, 同步读
// 读沿取上升沿: PC 在上一个下降沿稳定, 上升沿读出, 再由下降沿的 IF/ID 采样
// ----------------------------------------------------------------------
module sys_imem(
    input  wire        clk,
    input  wire [31:0] addr,
    output reg  [31:0] dout
);

    localparam integer IMEM_WORDS = 16384;   // 64KB / 4B

    (* rom_style = "block" *) reg [31:0] mem [0:IMEM_WORDS-1];

    initial begin
        $readmemh("main.hex", mem);
    end

    always @(posedge clk)
        dout <= mem[addr[15:2]];

endmodule


// ----------------------------------------------------------------------
// 毫秒定时器: 100MHz 计数到 DIV 产生 1ms, 32 位毫秒计数
// ----------------------------------------------------------------------
module tick_ms #(
    parameter integer DIV = 100000
) (
    input  wire        clk,
    input  wire        reset,
    output reg  [31:0] ms
);

    reg [16:0] cnt;

    initial begin
        cnt = 17'd0;
        ms  = 32'd0;
    end

    always @(posedge clk) begin
        if (reset) begin
            cnt <= 17'd0;
            ms  <= 32'd0;
        end else if (cnt == DIV - 1) begin
            cnt <= 17'd0;
            ms  <= ms + 1'b1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule


// ----------------------------------------------------------------------
// 数据存储器 + 外设总线译码
//
// 寄存器写在时钟下降沿, 与 CPU 写数据存储器的时刻一致;
// 读是组合逻辑, 由 MEM 级的 dmemaddr 直接译码, 下一个下降沿被 WB 采样.
// ----------------------------------------------------------------------
module sys_bus(
    input  wire        clk,
    input  wire        reset,
    // CPU 数据总线
    input  wire [31:0] addr,
    input  wire [31:0] datain,
    input  wire        we,
    input  wire [2:0]  memop,
    output reg  [31:0] dataout,
    // 字符显存的 VGA 读端口
    input  wire [11:0] vga_addr,
    output wire [7:0]  vga_char,
    // 键盘
    input  wire [7:0]  kbd_ch,
    input  wire        kbd_push,
    // 定时器
    input  wire [31:0] ms_cnt,
    // 板上 I/O
    input  wire [15:0] sw,
    output wire [4:0]  top_row,
    output wire [11:0] cursor,
    output wire [15:0] led,
    output wire [31:0] dbg
);

    localparam [31:0] ADDR_VGA_TOP = 32'h0021_0000,
                      ADDR_CURSOR  = 32'h0021_0004,
                      ADDR_KBD_DAT = 32'h0030_0000,
                      ADDR_KBD_ST  = 32'h0030_0004,
                      ADDR_KBD_POP = 32'h0030_0008,
                      ADDR_TIMER   = 32'h0040_0000,
                      ADDR_SW      = 32'h0050_0000,
                      ADDR_LED     = 32'h0060_0000,
                      ADDR_DBG     = 32'h0060_0004;

    localparam integer DMEM_WORDS = 32768;   // 128KB / 4B

    // ------------------------------------------------------------------
    // 设备选择
    // 0x0020_0000 和 0x0021_0000 的高 12 位相同, 所以显存按 addr[31:16] 区分,
    // 寄存器再按整字地址精确比较
    // ------------------------------------------------------------------

    wire sel_dmem = (addr[31:20] == 12'h001);      // 0x0010_0000 起 128KB
    wire sel_char = (addr[31:16] == 16'h0020);     // 0x0020_0000 起 4KB

    wire wr_top  = we & (addr == ADDR_VGA_TOP);
    wire wr_cur  = we & (addr == ADDR_CURSOR);
    wire wr_led  = we & (addr == ADDR_LED);
    wire wr_dbg  = we & (addr == ADDR_DBG);
    wire kbd_pop = we & (addr == ADDR_KBD_POP);

    // ------------------------------------------------------------------
    // 数据存储器: 上升沿读整字, 下降沿按 memop 读改写
    // ------------------------------------------------------------------

    (* ram_style = "block" *) reg [31:0] dmem [0:DMEM_WORDS-1];

    initial begin
        $readmemh("main_d.hex", dmem);
    end

    wire [14:0] dst_idx = addr[16:2];
    wire [1:0]  dst_off = addr[1:0];

    reg [31:0] dmem_rdword;
    always @(posedge clk)
        dmem_rdword <= dmem[dst_idx];

    // 按 memop 从整字中取出要读的字节/半字
    reg [31:0] dmem_rdata;
    always @(*) begin
        case (memop)
            3'b001:  dmem_rdata = dst_off[1] ? {{16{dmem_rdword[31]}}, dmem_rdword[31:16]}
                                            : {{16{dmem_rdword[15]}}, dmem_rdword[15:0]};
            3'b101:  dmem_rdata = dst_off[1] ? {16'b0, dmem_rdword[31:16]}
                                            : {16'b0, dmem_rdword[15:0]};
            3'b000:  dmem_rdata = (dst_off == 2'd0) ? {{24{dmem_rdword[7]}},  dmem_rdword[7:0]}
                                : (dst_off == 2'd1) ? {{24{dmem_rdword[15]}}, dmem_rdword[15:8]}
                                : (dst_off == 2'd2) ? {{24{dmem_rdword[23]}}, dmem_rdword[23:16]}
                                                    : {{24{dmem_rdword[31]}}, dmem_rdword[31:24]};
            3'b100:  dmem_rdata = (dst_off == 2'd0) ? {24'b0, dmem_rdword[7:0]}
                                : (dst_off == 2'd1) ? {24'b0, dmem_rdword[15:8]}
                                : (dst_off == 2'd2) ? {24'b0, dmem_rdword[23:16]}
                                                    : {24'b0, dmem_rdword[31:24]};
            default: dmem_rdata = dmem_rdword;
        endcase
    end

    // 把新数据拼进整字
    reg [31:0] dmem_wdata;
    always @(*) begin
        case (memop)
            3'b001, 3'b101:
                dmem_wdata = dst_off[1] ? {datain[15:0], dmem_rdword[15:0]}
                                        : {dmem_rdword[31:16], datain[15:0]};
            3'b000, 3'b100:
                dmem_wdata = (dst_off == 2'd0) ? {dmem_rdword[31:8],  datain[7:0]}
                           : (dst_off == 2'd1) ? {dmem_rdword[31:16], datain[7:0], dmem_rdword[7:0]}
                           : (dst_off == 2'd2) ? {dmem_rdword[31:24], datain[7:0], dmem_rdword[15:0]}
                                               : {datain[7:0], dmem_rdword[23:0]};
            default: dmem_wdata = datain;
        endcase
    end

    always @(negedge clk)
        if (we && sel_dmem)
            dmem[dst_idx] <= dmem_wdata;

    // ------------------------------------------------------------------
    // 字符显存: 32 行 x 128 列, CPU 按字节写, VGA 异步读
    // ------------------------------------------------------------------

    (* ram_style = "distributed" *) reg [7:0] charmem [0:4095];

    // 上电后显存为空白字符(0 的字模是空), 软件再按需要清屏
    integer ci;
    initial begin
        for (ci = 0; ci < 4096; ci = ci + 1)
            charmem[ci] = 8'h00;
    end

    always @(negedge clk)
        if (we && sel_char)
            charmem[addr[11:0]] <= datain[7:0];

    assign vga_char = charmem[vga_addr];

    // ------------------------------------------------------------------
    // 外设寄存器
    // ------------------------------------------------------------------

    reg [4:0]  top_row_r;
    reg [11:0] cursor_r;
    reg [14:0] led_r;
    reg [31:0] dbg_r;

    // 键盘 FIFO: 16 项, 队首不出队, 写弹出寄存器才出队
    localparam integer KFIFO_DEPTH = 16;
    reg [7:0]  kfifo [0:KFIFO_DEPTH-1];
    reg [3:0]  kfifo_wptr, kfifo_rptr;
    reg        kbd_overflow;

    wire kbd_valid = (kfifo_wptr != kfifo_rptr);
    wire kbd_full  = ((kfifo_wptr + 4'd1) == kfifo_rptr);
    wire kbd_accept = kbd_push && (~kbd_full | kbd_pop);

    initial begin
        top_row_r    = 5'd0;
        cursor_r     = 12'd0;
        led_r        = 15'd0;
        dbg_r        = 32'd0;
        kfifo_wptr   = 4'd0;
        kfifo_rptr   = 4'd0;
        kbd_overflow = 1'b0;
    end

    always @(negedge clk) begin
        if (reset) begin
            top_row_r    <= 5'd0;
            cursor_r     <= 12'd0;
            led_r        <= 15'd0;
            dbg_r        <= 32'd0;
            kfifo_wptr   <= 4'd0;
            kfifo_rptr   <= 4'd0;
            kbd_overflow <= 1'b0;
        end else begin
            if (wr_top) top_row_r <= datain[4:0];
            if (wr_cur) cursor_r  <= datain[11:0];
            if (wr_led) led_r     <= datain[14:0];
            if (wr_dbg) dbg_r     <= datain;

            if (kbd_accept) begin
                kfifo[kfifo_wptr] <= kbd_ch;
                kfifo_wptr        <= kfifo_wptr + 1'b1;
            end

            if (kbd_push && kbd_full && ~kbd_pop)
                kbd_overflow <= 1'b1;

            if (kbd_pop && kbd_valid)
                kfifo_rptr <= kfifo_rptr + 1'b1;
        end
    end

    assign top_row = top_row_r;
    assign cursor  = cursor_r;
    assign led     = led_r;
    assign dbg     = dbg_r;

    // ------------------------------------------------------------------
    // 读数据选择
    // ------------------------------------------------------------------

    always @(*) begin
        dataout = 32'b0;
        if (sel_dmem)
            dataout = dmem_rdata;
        else if (sel_char)
            dataout = {24'b0, charmem[addr[11:0]]};
        else begin
            case (addr)
                ADDR_VGA_TOP: dataout = {27'b0, top_row_r};
                ADDR_CURSOR:  dataout = {20'b0, cursor_r};
                ADDR_KBD_DAT: dataout = {24'b0, kfifo[kfifo_rptr]};
                ADDR_KBD_ST:  dataout = {30'b0, kbd_overflow, kbd_valid};
                ADDR_TIMER:   dataout = ms_cnt;
                ADDR_SW:      dataout = {16'b0, sw};
                ADDR_DBG:     dataout = dbg_r;
                default:      dataout = 32'b0;
            endcase
        end
    end

endmodule


// ----------------------------------------------------------------------
// PS/2 键盘接收: 11 位帧同步, 奇校验, 8 项扫描码 FIFO
// 帧格式: 起始位 0, 8 位数据 LSB 在前, 奇校验位, 停止位 1
// ----------------------------------------------------------------------
module ps2_keyboard(
    input  wire        clk,
    input  wire        clrn,
    input  wire        ps2_clk,
    input  wire        ps2_data,
    input  wire        nextdata_n,   // 低电平弹出队首
    output wire [7:0]  data,
    output reg         ready,
    output reg         overflow
);

    reg [9:0] buffer;
    reg [7:0] fifo [7:0];
    reg [2:0] w_ptr, r_ptr;
    reg [3:0] count;
    reg [2:0] ps2_clk_sync;

    always @(posedge clk)
        ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};

    // PS/2 时钟的下降沿采样数据
    wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

    initial begin
        buffer   = 10'd0;
        w_ptr    = 3'd0;
        r_ptr    = 3'd0;
        count    = 4'd0;
        ready    = 1'b0;
        overflow = 1'b0;
    end

    always @(posedge clk) begin
        if (clrn == 0) begin
            count    <= 0;
            w_ptr    <= 0;
            r_ptr    <= 0;
            overflow <= 0;
            ready    <= 0;
        end else begin
            if (ready) begin
                if (nextdata_n == 1'b0) begin
                    r_ptr <= r_ptr + 3'b1;
                    if (w_ptr == (r_ptr + 1'b1))
                        ready <= 1'b0;
                end
            end
            if (sampling) begin
                if (count == 4'd10) begin
                    if ((buffer[0] == 0) && (ps2_data) && (^buffer[9:1])) begin
                        fifo[w_ptr] <= buffer[8:1];
                        w_ptr <= w_ptr + 3'b1;
                        ready <= 1'b1;
                        overflow <= overflow | (r_ptr == (w_ptr + 3'b1));
                    end
                    count <= 0;
                end else begin
                    buffer[count] <= ps2_data;
                    count <= count + 3'b1;
                end
            end
        end
    end

    assign data = fifo[r_ptr];

endmodule


// ----------------------------------------------------------------------
// 扫描码解析: 处理 F0 断码与 E0 扩展码, Shift 大小写, 输出 ASCII
// Enter -> 0x0A, Backspace -> 0x08, Tab -> 0x09
// 扩展键送出控制码: Up 0x11, Down 0x12, Right 0x13, Left 0x14,
//                   Home 0x01, End 0x05, Delete 0x7F; 其它功能键丢弃
// push 为单周期脉冲, ch 同时有效
// ----------------------------------------------------------------------
module ps2_ascii(
    input  wire       clk,
    input  wire       reset,
    input  wire       ps2_clk,
    input  wire       ps2_data,
    output reg        push,
    output reg  [7:0] ch,
    output wire       shift,
    output wire       ready,
    output wire       overflow
);

    // 扫描码转 ASCII, 带 Shift 大小写与符号变体
    function [7:0] ascii_of;
        input [7:0] code;
        input       sh;
        begin
            case (code)
                8'h1C: ascii_of = sh ? 8'h41 : 8'h61; // a A
                8'h32: ascii_of = sh ? 8'h42 : 8'h62; // b B
                8'h21: ascii_of = sh ? 8'h43 : 8'h63; // c C
                8'h23: ascii_of = sh ? 8'h44 : 8'h64; // d D
                8'h24: ascii_of = sh ? 8'h45 : 8'h65; // e E
                8'h2B: ascii_of = sh ? 8'h46 : 8'h66; // f F
                8'h34: ascii_of = sh ? 8'h47 : 8'h67; // g G
                8'h33: ascii_of = sh ? 8'h48 : 8'h68; // h H
                8'h43: ascii_of = sh ? 8'h49 : 8'h69; // i I
                8'h3B: ascii_of = sh ? 8'h4A : 8'h6A; // j J
                8'h42: ascii_of = sh ? 8'h4B : 8'h6B; // k K
                8'h4B: ascii_of = sh ? 8'h4C : 8'h6C; // l L
                8'h3A: ascii_of = sh ? 8'h4D : 8'h6D; // m M
                8'h31: ascii_of = sh ? 8'h4E : 8'h6E; // n N
                8'h44: ascii_of = sh ? 8'h4F : 8'h6F; // o O
                8'h4D: ascii_of = sh ? 8'h50 : 8'h70; // p P
                8'h15: ascii_of = sh ? 8'h51 : 8'h71; // q Q
                8'h2D: ascii_of = sh ? 8'h52 : 8'h72; // r R
                8'h1B: ascii_of = sh ? 8'h53 : 8'h73; // s S
                8'h2C: ascii_of = sh ? 8'h54 : 8'h74; // t T
                8'h3C: ascii_of = sh ? 8'h55 : 8'h75; // u U
                8'h2A: ascii_of = sh ? 8'h56 : 8'h76; // v V
                8'h1D: ascii_of = sh ? 8'h57 : 8'h77; // w W
                8'h22: ascii_of = sh ? 8'h58 : 8'h78; // x X
                8'h35: ascii_of = sh ? 8'h59 : 8'h79; // y Y
                8'h1A: ascii_of = sh ? 8'h5A : 8'h7A; // z Z
                8'h16: ascii_of = sh ? 8'h21 : 8'h31; // 1 !
                8'h1E: ascii_of = sh ? 8'h40 : 8'h32; // 2 @
                8'h26: ascii_of = sh ? 8'h23 : 8'h33; // 3 #
                8'h25: ascii_of = sh ? 8'h24 : 8'h34; // 4 $
                8'h2E: ascii_of = sh ? 8'h25 : 8'h35; // 5 %
                8'h36: ascii_of = sh ? 8'h5E : 8'h36; // 6 ^
                8'h3D: ascii_of = sh ? 8'h26 : 8'h37; // 7 &
                8'h3E: ascii_of = sh ? 8'h2A : 8'h38; // 8 *
                8'h46: ascii_of = sh ? 8'h28 : 8'h39; // 9 (
                8'h45: ascii_of = sh ? 8'h29 : 8'h30; // 0 )
                8'h0E: ascii_of = sh ? 8'h7E : 8'h60; // ` ~
                8'h4E: ascii_of = sh ? 8'h5F : 8'h2D; // - _
                8'h55: ascii_of = sh ? 8'h2B : 8'h3D; // = +
                8'h54: ascii_of = sh ? 8'h7B : 8'h5B; // [ {
                8'h5B: ascii_of = sh ? 8'h7D : 8'h5D; // ] }
                8'h5D: ascii_of = sh ? 8'h7C : 8'h5C; // \ |
                8'h4C: ascii_of = sh ? 8'h3A : 8'h3B; // ; :
                8'h52: ascii_of = sh ? 8'h22 : 8'h27; // ' "
                8'h41: ascii_of = sh ? 8'h3C : 8'h2C; // , <
                8'h49: ascii_of = sh ? 8'h3E : 8'h2E; // . >
                8'h4A: ascii_of = sh ? 8'h3F : 8'h2F; // / ?
                8'h29: ascii_of = 8'h20;              // space
                8'h5A: ascii_of = 8'h0A;              // Enter
                8'h66: ascii_of = 8'h08;              // BackSpace
                default: ascii_of = 8'h00;
            endcase
        end
    endfunction

    reg       shift_l, shift_r;
    reg [1:0] kstate;
    reg       nextdata_n;
    wire [7:0] rx;

    assign shift = shift_l | shift_r;

    ps2_keyboard u_kbd (
        .clk       (clk),
        .clrn      (~reset),
        .ps2_clk   (ps2_clk),
        .ps2_data  (ps2_data),
        .nextdata_n(nextdata_n),
        .data      (rx),
        .ready     (ready),
        .overflow  (overflow)
    );

    wire [7:0] rx_ascii = ascii_of(rx, shift);

    initial begin
        push       = 1'b0;
        ch         = 8'h00;
        shift_l    = 1'b0;
        shift_r    = 1'b0;
        kstate     = 2'd0;
        nextdata_n = 1'b1;
    end

    always @(posedge clk) begin
        push       <= 1'b0;
        nextdata_n <= 1'b1;
        if (reset) begin
            kstate  <= 2'd0;
            shift_l <= 1'b0;
            shift_r <= 1'b0;
        end else if (ready && nextdata_n) begin
            nextdata_n <= 1'b0;
            case (kstate)
            2'd0: begin
                case (rx)
                    8'hF0: kstate  <= 2'd1;   // 断码前缀
                    8'hE0: kstate  <= 2'd2;   // 扩展码前缀
                    8'h12: shift_l <= 1'b1;
                    8'h59: shift_r <= 1'b1;
                    8'h0D: begin ch <= 8'h09; push <= 1'b1; end  // Tab
                    default: begin
                        if (rx_ascii == 8'h0A) begin
                            ch <= 8'h0A; push <= 1'b1;
                        end else if (rx_ascii == 8'h08) begin
                            ch <= 8'h08; push <= 1'b1;
                        end else if (rx_ascii != 8'h00) begin
                            ch <= rx_ascii; push <= 1'b1;
                        end
                    end
                endcase
            end
            2'd1: begin
                // 通码的断码: 只处理 Shift 释放
                if (rx == 8'h12)      shift_l <= 1'b0;
                else if (rx == 8'h59) shift_r <= 1'b0;
                kstate <= 2'd0;
            end
            2'd2: begin
                if (rx == 8'hF0)
                    kstate <= 2'd3;
                else begin
                    case (rx)
                        8'h59: shift_r <= 1'b1;
                        8'h5A: begin ch <= 8'h0A; push <= 1'b1; end  // 小键盘 Enter
                        8'h75: begin ch <= 8'h11; push <= 1'b1; end  // Up
                        8'h72: begin ch <= 8'h12; push <= 1'b1; end  // Down
                        8'h74: begin ch <= 8'h13; push <= 1'b1; end  // Right
                        8'h6B: begin ch <= 8'h14; push <= 1'b1; end  // Left
                        8'h6C: begin ch <= 8'h01; push <= 1'b1; end  // Home
                        8'h69: begin ch <= 8'h05; push <= 1'b1; end  // End
                        8'h71: begin ch <= 8'h7F; push <= 1'b1; end  // Delete
                        default: ;
                    endcase
                    kstate <= 2'd0;
                end
            end
            2'd3: begin
                if (rx == 8'h59) shift_r <= 1'b0;
                kstate <= 2'd0;
            end
            endcase
        end
    end

endmodule


// ----------------------------------------------------------------------
// VGA 640x480@60Hz 时序, 同时输出字符列号与字符内列号
// 行时序 96/48/640/16, 场时序 2/33/480/10
// ----------------------------------------------------------------------
module vga_ctrl(
    input  wire       pclk,
    input  wire       reset,
    output wire [9:0] h_addr,
    output wire [9:0] v_addr,
    output wire [6:0] char_col,
    output wire [3:0] pix_col,
    output wire       hsync,
    output wire       vsync,
    output wire       valid
);

    parameter h_frontporch = 96;
    parameter h_active     = 144;
    parameter h_backporch  = 784;
    parameter h_total      = 800;

    parameter v_frontporch = 2;
    parameter v_active     = 35;
    parameter v_backporch  = 515;
    parameter v_total      = 525;

    reg [9:0] x_cnt;
    reg [9:0] y_cnt;
    reg [6:0] ccol;
    reg [3:0] cpix;

    initial begin
        x_cnt = 10'd1;
        y_cnt = 10'd1;
        ccol  = 7'd0;
        cpix  = 4'd0;
    end

    always @(posedge pclk) begin
        if (reset) begin
            x_cnt <= 10'd1;
            ccol  <= 7'd0;
            cpix  <= 4'd0;
        end else if (x_cnt == h_total) begin
            x_cnt <= 10'd1;
            ccol  <= 7'd0;
            cpix  <= 4'd0;
        end else begin
            x_cnt <= x_cnt + 10'd1;
            if ((x_cnt > h_active) && (x_cnt <= h_backporch)) begin
                if (cpix == 4'd8) begin
                    cpix <= 4'd0;
                    ccol <= ccol + 1'b1;
                end else begin
                    cpix <= cpix + 1'b1;
                end
            end else begin
                cpix <= 4'd0;
                ccol <= 7'd0;
            end
        end
    end

    always @(posedge pclk) begin
        if (reset)
            y_cnt <= 10'd1;
        else if (x_cnt == h_total) begin
            if (y_cnt == v_total)
                y_cnt <= 10'd1;
            else
                y_cnt <= y_cnt + 10'd1;
        end
    end

    wire h_valid = (x_cnt > h_active) && (x_cnt <= h_backporch);
    wire v_valid = (y_cnt > v_active) && (y_cnt <= v_backporch);

    assign hsync = (x_cnt > h_frontporch);
    assign vsync = (y_cnt > v_frontporch);
    assign valid = h_valid & v_valid;

    assign h_addr   = h_valid ? (x_cnt - 10'd145) : 10'd0;
    assign v_addr   = v_valid ? (y_cnt - 10'd36)  : 10'd0;
    assign char_col = ccol;
    assign pix_col  = cpix;

endmodule

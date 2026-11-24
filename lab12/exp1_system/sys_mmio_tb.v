`timescale 1ns / 1ps

// sys_mmio_tb.v : 外设与总线译码的自检 testbench
//
// 不例化 CPU, 由 testbench 直接模拟 MEM 级的总线时序 (上升沿给地址,
// 下降沿写外设). 覆盖:
//   1. 字符显存按字节读改写, VGA 读端口看到同一内容
//   2. 起始行 top_row 与光标寄存器
//   3. 数据存储器 sw/lw/sb/lbu, 以及 0x0011_FFFC 栈顶
//   4. PS/2 键盘收一个字符, ASCII 正确 (含 Enter 与断码)
//   5. Tab 键产生 0x09, 且只入队一次
//   6. 扩展键 E0 + 通码: Up 0x11, Down 0x12, Right 0x13, Left 0x14,
//      Home 0x01, End 0x05, Delete 0x7F; E0 F0 + 通码不产生字符
//   7. 键盘 FIFO: 读数据不出队, 写弹出寄存器才出队
//   8. 毫秒定时器递增
//   9. Ctrl 组合键: Ctrl+A 0x81, Ctrl+C 0x83, Ctrl+L 0x8C, Ctrl+U 0x95,
//      松开 Ctrl 后小写字母恢复正常
// 定时器分频用参数 DIV=100 缩短仿真时间, 逻辑与上板的 100000 相同.

module sys_mmio_tb;

    localparam integer PS2_HALF = 2000;   // PS/2 时钟半周期 2us

    reg  clk   = 1'b0;
    reg  rst   = 1'b1;
    reg  ps2_clk  = 1'b1;
    reg  ps2_data = 1'b1;
    reg  [15:0] sw = 16'hA55A;

    always #20 clk = ~clk;   // 40ns 周期, 25MHz

    // 模拟 CPU 的总线
    reg  [31:0] addr = 32'b0;
    reg  [31:0] datain = 32'b0;
    reg         we = 1'b0;
    reg  [2:0]  memop = 3'b010;
    wire [31:0] dataout;

    // 显存 VGA 读端口
    reg  [11:0] vga_addr = 12'd0;
    wire [7:0]  vga_char;

    // 键盘
    wire        kbd_push;
    wire [7:0]  kbd_ch;
    wire        kbd_shift, kbd_ready, kbd_ovf;

    wire [31:0] ms_cnt;

    // 外设
    wire [4:0]  top_row;
    wire [11:0] cursor;
    wire [15:0] led;
    wire [31:0] dbg;

    integer errors = 0;

    // --------------------------------------------------------------
    // 被测试模块
    // --------------------------------------------------------------

    sys_bus u_bus (
        .clk      (clk),
        .reset    (rst),
        .addr     (addr),
        .datain   (datain),
        .we       (we),
        .memop    (memop),
        .dataout  (dataout),
        .vga_addr (vga_addr),
        .vga_char (vga_char),
        .kbd_ch   (kbd_ch),
        .kbd_push (kbd_push),
        .ms_cnt   (ms_cnt),
        .sw       (sw),
        .top_row  (top_row),
        .cursor   (cursor),
        .led      (led),
        .dbg      (dbg)
    );

    ps2_ascii u_ps2 (
        .clk      (clk),
        .reset    (rst),
        .ps2_clk  (ps2_clk),
        .ps2_data (ps2_data),
        .push     (kbd_push),
        .ch       (kbd_ch),
        .shift    (kbd_shift),
        .ready    (kbd_ready),
        .overflow (kbd_ovf)
    );

    tick_ms #(.DIV(100)) u_tick (
        .clk   (clk),
        .reset (rst),
        .ms    (ms_cnt)
    );

    // --------------------------------------------------------------
    // 总线时序
    // --------------------------------------------------------------

    task bus_write;
        input [31:0] a;
        input [31:0] d;
        input [2:0]  op;
        begin
            // 与 CPU 时序一致: 下降沿给出地址, 中间经过一个上升沿读旧字,
            // 下一个下降沿写入
            @(negedge clk); #1;
            addr = a; datain = d; memop = op; we = 1'b1;
            @(negedge clk);            // 外设在这一刻写入
            #1 we = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task bus_read;
        input  [31:0] a;
        input  [2:0]  op;
        output [31:0] d;
        begin
            @(posedge clk); #1;
            addr = a; memop = op; we = 1'b0;
            @(posedge clk); #1;        // 同步读在上升沿取数
            d = dataout;
        end
    endtask

    task check;
        input [31:0] got;
        input [31:0] exp;
        input [255:0] name;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("MISMATCH %0s: got %08h, expected %08h", name, got, exp);
            end
        end
    endtask

    // --------------------------------------------------------------
    // PS/2 发送一个字节
    // --------------------------------------------------------------

    task ps2_pulse;
        begin
            #(PS2_HALF);
            ps2_clk = 1'b0;
            #(PS2_HALF);
            ps2_clk = 1'b1;
        end
    endtask

    task ps2_send;
        input [7:0] code;
        integer i;
        begin
            ps2_data = 1'b0;                       // 起始位
            ps2_pulse;
            for (i = 0; i < 8; i = i + 1) begin    // 8 位数据, LSB 在前
                ps2_data = code[i];
                ps2_pulse;
            end
            ps2_data = ~(^code);                   // 奇校验
            ps2_pulse;
            ps2_data = 1'b1;                       // 停止位
            ps2_pulse;
        end
    endtask

    // --------------------------------------------------------------
    // 测试
    // --------------------------------------------------------------

    reg [31:0] rd;
    reg [31:0] ms1, ms2;

    initial begin
        $dumpfile("sys_mmio_tb.vcd");
        $dumpvars(0, sys_mmio_tb);

        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);

        // ---------------- 1. 字符显存 ----------------
        bus_write(32'h0020_0005, 32'h0000_0041, 3'b000);   // sb 'A'
        bus_write(32'h0020_0006, 32'h0000_0042, 3'b000);   // sb 'B'
        bus_read (32'h0020_0005, 3'b100, rd);
        check(rd, 32'h0000_0041, "vga mem read A");
        bus_read (32'h0020_0006, 3'b100, rd);
        check(rd, 32'h0000_0042, "vga mem read B");

        vga_addr = 12'd5;
        #10;
        check({24'b0, vga_char}, 32'h0000_0041, "vga port col 5");
        vga_addr = 12'd6;
        #10;
        check({24'b0, vga_char}, 32'h0000_0042, "vga port col 6");

        // 相邻字节不能被覆盖
        bus_read (32'h0020_0000, 3'b100, rd);
        check(rd, 32'h0000_0000, "vga mem col 0 blank");

        // ---------------- 2. 起始行与光标 ----------------
        bus_write(32'h0021_0000, 32'd3, 3'b010);
        bus_read (32'h0021_0000, 3'b010, rd);
        check(rd, 32'd3, "top row");
        check({27'b0, top_row}, 32'd3, "top row port");

        bus_write(32'h0021_0004, 32'h0000_0A5C, 3'b010);
        bus_read (32'h0021_0004, 3'b010, rd);
        check(rd, 32'h0000_0A5C, "cursor");
        check({20'b0, cursor}, 32'h0000_0A5C, "cursor port");

        // ---------------- 3. 数据存储器 ----------------
        bus_write(32'h0010_0000, 32'h1234_5678, 3'b010);   // sw
        bus_read (32'h0010_0000, 3'b010, rd);
        check(rd, 32'h1234_5678, "dmem word");

        bus_write(32'h0010_0001, 32'h0000_00AA, 3'b000);   // sb, 只改第 1 字节
        bus_read (32'h0010_0000, 3'b010, rd);
        check(rd, 32'h1234_AA78, "dmem byte merge");
        bus_read (32'h0010_0001, 3'b100, rd);
        check(rd, 32'h0000_00AA, "dmem lbu");

        // 栈顶 0x0011_FFFC
        bus_write(32'h0011_FFFC, 32'hDEAD_BEEF, 3'b010);
        bus_read (32'h0011_FFFC, 3'b010, rd);
        check(rd, 32'hDEAD_BEEF, "dmem stack top");

        // 半字写
        bus_write(32'h0010_0000, 32'h0000_BEEF, 3'b001);   // sh, 只改低半字
        bus_read (32'h0010_0000, 3'b010, rd);
        check(rd, 32'h1234_BEEF, "dmem half merge");

        // ---------------- 4. LED 与开关 ----------------
        bus_write(32'h0060_0000, 32'h0000_1234, 3'b010);
        check({16'b0, led}, 32'h0000_1234, "led reg");
        bus_read (32'h0050_0000, 3'b010, rd);
        check(rd, 32'h0000_A55A, "sw reg");

        // ---------------- 5. 键盘: 收到 'a' ----------------
        ps2_send(8'h1C);                     // 'a' 的通码
        repeat (6) @(posedge clk);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0001, "kbd valid");
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0061, "kbd ascii a");

        // 再发 'b', 读数据寄存器不出队
        ps2_send(8'h32);
        repeat (6) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0061, "kbd read no pop");
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0061, "kbd read still no pop");

        // 写弹出寄存器后队首变成 'b'
        bus_write(32'h0030_0008, 32'd0, 3'b010);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0062, "kbd ascii b after pop");

        // 再弹一次, FIFO 空
        bus_write(32'h0030_0008, 32'd0, 3'b010);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd empty");

        // 回车键送 0x0A
        ps2_send(8'h5A);
        repeat (6) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_000A, "kbd enter ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // 断码不能被当成字符: F0 1C
        ps2_send(8'hF0);
        ps2_send(8'h1C);
        repeat (6) @(posedge clk);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd release ignored");

        // ---------------- 5.1 键盘: Tab 与扩展键 ----------------
        // Tab 通码 0D 送 0x09
        ps2_send(8'h0D);
        repeat (6) @(posedge clk);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0001, "kbd tab valid");
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0009, "kbd tab ascii");

        // 读数据不出队, 弹出后 FIFO 空: Tab 只入队一次
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0009, "kbd tab read no pop");
        bus_write(32'h0030_0008, 32'd0, 3'b010);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd tab only once");

        // 扩展键: E0 前缀 + 通码, 解析需要两次 ready 握手
        ps2_send(8'hE0);                     // Up
        ps2_send(8'h75);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0011, "kbd up ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // Down
        ps2_send(8'h72);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0012, "kbd down ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // Left
        ps2_send(8'h6B);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0014, "kbd left ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // Right
        ps2_send(8'h74);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0013, "kbd right ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // Home
        ps2_send(8'h6C);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0001, "kbd home ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // End
        ps2_send(8'h69);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0005, "kbd end ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        ps2_send(8'hE0);                     // Delete
        ps2_send(8'h71);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_007F, "kbd delete ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // 扩展键断码 E0 F0 6B (Left 释放) 不产生字符
        ps2_send(8'hE0);
        ps2_send(8'hF0);
        ps2_send(8'h6B);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd left release ignored");

        // 扩展键断码 E0 F0 75 (Up 释放) 不产生字符
        ps2_send(8'hE0);
        ps2_send(8'hF0);
        ps2_send(8'h75);
        repeat (12) @(posedge clk);
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd up release ignored");

        // ---------------- 5.2 键盘: Ctrl 组合键 ----------------
        // Ctrl 按住时字母送 0x80 | 字母序号: a=1 ... z=26
        // 断码顺序固定为 通码, 断码前缀 F0, 通码, 再松开 Ctrl 的 F0 14

        // Ctrl + A: 14 1C F0 1C F0 14 -> 0x81
        ps2_send(8'h14);
        ps2_send(8'h1C);
        ps2_send(8'hF0);
        ps2_send(8'h1C);
        ps2_send(8'hF0);
        ps2_send(8'h14);
        repeat (24) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0081, "kbd ctrl a ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // Ctrl + C: 14 21 F0 21 F0 14 -> 0x83
        ps2_send(8'h14);
        ps2_send(8'h21);
        ps2_send(8'hF0);
        ps2_send(8'h21);
        ps2_send(8'hF0);
        ps2_send(8'h14);
        repeat (24) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0083, "kbd ctrl c ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // Ctrl + L: 14 4B F0 4B F0 14 -> 0x8C
        ps2_send(8'h14);
        ps2_send(8'h4B);
        ps2_send(8'hF0);
        ps2_send(8'h4B);
        ps2_send(8'hF0);
        ps2_send(8'h14);
        repeat (24) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_008C, "kbd ctrl l ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // Ctrl + U: 14 3C F0 3C F0 14 -> 0x95
        // 注意: u 的扫描码是 3C, 16 是数字 1
        ps2_send(8'h14);
        ps2_send(8'h3C);
        ps2_send(8'hF0);
        ps2_send(8'h3C);
        ps2_send(8'hF0);
        ps2_send(8'h14);
        repeat (24) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_0095, "kbd ctrl u ascii");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // Ctrl 已经放开, 小写 l 正常送 0x6C: 4B F0 4B -> 0x6C
        ps2_send(8'h4B);
        ps2_send(8'hF0);
        ps2_send(8'h4B);
        repeat (8) @(posedge clk);
        bus_read (32'h0030_0000, 3'b010, rd);
        check(rd, 32'h0000_006C, "kbd plain l after ctrl");
        bus_write(32'h0030_0008, 32'd0, 3'b010);

        // 断码与组合键都不额外入队, FIFO 应为空
        bus_read (32'h0030_0004, 3'b010, rd);
        check(rd, 32'h0000_0000, "kbd ctrl combo no extra");

        // ---------------- 6. 定时器 ----------------
        bus_read (32'h0040_0000, 3'b010, ms1);
        repeat (400) @(posedge clk);          // 400 * 40ns = 16us, DIV=100
        bus_read (32'h0040_0000, 3'b010, ms2);
        if (ms2 <= ms1) begin
            errors = errors + 1;
            $display("MISMATCH timer: %0d -> %0d", ms1, ms2);
        end

        // ---------------- 结果 ----------------
        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);

        $finish;
    end

    // 超时保护
    initial begin
        #5_000_000;
        $display("TEST FAILED: timeout");
        $finish;
    end

endmodule

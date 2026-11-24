`timescale 1ns / 1ps

// sys_top_tb.v : 全系统自检 testbench
//
// 例化完整的 sys_top, 装入 sw/Makefile 生成的 main.hex / main_d.hex,
// 用 PS/2 时序敲键, 直接读字符显存和光标寄存器检查屏幕内容与光标位置.
// 覆盖: 开机提示符, 字符回显, Enter, Backspace, hello / fib / time / 未知命令,
//       行尾自动换行, 左右方向键在行内插入, Home/Delete/End, Tab 补全,
//       上下方向键调历史, 滚屏, 滚屏后的光标位置;
//       复位后再测 echo / sw / led / history / clear 命令和 Ctrl+A/E/L/C/U.
//
// 仿真时间约 35ms, Vivado 里不要用默认的 1000ns, 需要手动修改仿真时长.
// 用 iverilog 跑:
//   iverilog -g2012 -Wall -s sys_top_tb -o /tmp/sim.out \
//       sys_top.v rv32ip.v sys_top_tb.v && vvp /tmp/sim.out

module sys_top_tb;

    localparam integer PS2_HALF = 1000;   // PS/2 时钟半周期 1us, 只为缩短仿真时间

    reg  clk100 = 1'b0;
    reg  cpu_resetn = 1'b0;
    reg  btnc = 1'b0;
    reg  [15:0] sw = 16'h0000;
    reg  ps2_clk  = 1'b1;
    reg  ps2_data = 1'b1;

    wire [7:0]  AN, HEX;
    wire [15:0] LED;
    wire        VGA_HS, VGA_VS;
    wire [3:0]  VGA_R, VGA_G, VGA_B;

    integer errors = 0;

    always #5 clk100 = ~clk100;   // 100MHz

    sys_top u_dut (
        .CLK100MHZ (clk100),
        .CPU_RESETN(cpu_resetn),
        .BTNC      (btnc),
        .SW        (sw),
        .PS2_CLK   (ps2_clk),
        .PS2_DATA  (ps2_data),
        .AN        (AN),
        .HEX       (HEX),
        .LED       (LED),
        .VGA_HS    (VGA_HS),
        .VGA_VS    (VGA_VS),
        .VGA_R     (VGA_R),
        .VGA_G     (VGA_G),
        .VGA_B     (VGA_B)
    );

    // ------------------------------------------------------------------
    // 显存读取: 把逻辑行换算成环形缓冲里的物理行
    // ------------------------------------------------------------------

    function [7:0] scr;
        input integer row;
        input integer col;
        integer phys;
        begin
            phys = (u_dut.u_bus.top_row_r + row) & 5'h1F;
            scr  = u_dut.u_bus.charmem[phys * 128 + col];
        end
    endfunction

    task expect_row;
        input integer row;
        input integer len;
        input [8*96-1:0] text;
        integer i, base;
        reg [7:0] got;
        begin
            for (i = 0; i < len; i = i + 1) begin
                base = (len - 1 - i) * 8;
                got  = scr(row, i);
                if (got !== text[base +: 8]) begin
                    errors = errors + 1;
                    $display("MISMATCH row %0d col %0d: got %02h, expected %02h",
                             row, i, got, text[base +: 8]);
                end
            end
        end
    endtask

    task check_byte;
        input integer row;
        input integer col;
        input [7:0] exp;
        input [255:0] name;
        reg [7:0] got;
        begin
            got = scr(row, col);
            if (got !== exp) begin
                errors = errors + 1;
                $display("MISMATCH %0s (row %0d col %0d): got %02h, expected %02h",
                         name, row, col, got, exp);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // PS/2 发送
    // ------------------------------------------------------------------

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
            ps2_data = 1'b0;
            ps2_pulse;
            for (i = 0; i < 8; i = i + 1) begin
                ps2_data = code[i];
                ps2_pulse;
            end
            ps2_data = ~(^code);
            ps2_pulse;
            ps2_data = 1'b1;
            ps2_pulse;
        end
    endtask

    function [7:0] scan_of;
        input [7:0] c;
        begin
            case (c)
                8'h61: scan_of = 8'h1C; // a
                8'h62: scan_of = 8'h32; // b
                8'h63: scan_of = 8'h21; // c
                8'h64: scan_of = 8'h23; // d
                8'h65: scan_of = 8'h24; // e
                8'h66: scan_of = 8'h2B; // f
                8'h67: scan_of = 8'h34; // g
                8'h48: scan_of = 8'h33; // H
                8'h68: scan_of = 8'h33; // h
                8'h69: scan_of = 8'h43; // i
                8'h6A: scan_of = 8'h3B; // j
                8'h6B: scan_of = 8'h42; // k
                8'h6C: scan_of = 8'h4B; // l
                8'h6D: scan_of = 8'h3A; // m
                8'h6E: scan_of = 8'h31; // n
                8'h6F: scan_of = 8'h44; // o
                8'h70: scan_of = 8'h4D; // p
                8'h71: scan_of = 8'h15; // q
                8'h72: scan_of = 8'h2D; // r
                8'h73: scan_of = 8'h1B; // s
                8'h74: scan_of = 8'h2C; // t
                8'h75: scan_of = 8'h3C; // u
                8'h76: scan_of = 8'h2A; // v
                8'h77: scan_of = 8'h1D; // w
                8'h78: scan_of = 8'h22; // x
                8'h79: scan_of = 8'h35; // y
                8'h7A: scan_of = 8'h1A; // z
                8'h30: scan_of = 8'h45; // 0
                8'h31: scan_of = 8'h16; // 1
                8'h32: scan_of = 8'h1E; // 2
                8'h33: scan_of = 8'h26; // 3
                8'h34: scan_of = 8'h25; // 4
                8'h35: scan_of = 8'h2E; // 5
                8'h36: scan_of = 8'h36; // 6
                8'h37: scan_of = 8'h3D; // 7
                8'h38: scan_of = 8'h3E; // 8
                8'h39: scan_of = 8'h46; // 9
                8'h28: scan_of = 8'h46; // ( 需要按 Shift
                8'h29: scan_of = 8'h45; // ) 需要按 Shift
                8'h2D: scan_of = 8'h4E; // -
                8'h2B: scan_of = 8'h55; // +
                8'h2A: scan_of = 8'h3E; // *
                8'h2F: scan_of = 8'h4A; // /
                8'h20: scan_of = 8'h29; // space
                8'h0A: scan_of = 8'h5A; // Enter
                8'h08: scan_of = 8'h66; // BackSpace
                default: scan_of = 8'h00;
            endcase
        end
    endfunction

    // 按住 Shift 敲一个字符
    task type_shift_char;
        input [7:0] c;
        reg [7:0] code;
        begin
            code = scan_of(c);
            ps2_send(8'h12);            // 左 Shift 通码
            ps2_send(code);
            ps2_send(8'hF0); ps2_send(code);
            ps2_send(8'hF0); ps2_send(8'h12);
            repeat (5) @(posedge clk100);
        end
    endtask

    // 敲一个普通键: 通码 + 断码, 和真实键盘一致
    task type_key;
        input [7:0] code;
        begin
            ps2_send(code);
            ps2_send(8'hF0);
            ps2_send(code);
            repeat (5) @(posedge clk100);
        end
    endtask

    // 敲一个 E0 扩展键: E0 通码, E0 F0 断码
    task type_ext;
        input [7:0] code;
        begin
            ps2_send(8'hE0); ps2_send(code);
            ps2_send(8'hE0); ps2_send(8'hF0); ps2_send(code);
            repeat (5) @(posedge clk100);
        end
    endtask

    task type_char;
        input [7:0] c;
        begin
            type_key(scan_of(c));
        end
    endtask

    task key_up;    begin type_ext(8'h75); end endtask
    task key_down;  begin type_ext(8'h72); end endtask
    task key_left;  begin type_ext(8'h6B); end endtask
    task key_right; begin type_ext(8'h74); end endtask
    task key_home;  begin type_ext(8'h6C); end endtask
    task key_end;   begin type_ext(8'h69); end endtask
    task key_del;   begin type_ext(8'h71); end endtask
    task key_tab;   begin type_key(8'h0D); end endtask
    task key_enter; begin type_key(8'h5A); end endtask
    task key_bs;    begin type_key(8'h66); end endtask

    // Ctrl + 字母: 左 Ctrl 按下, 敲字母, 再依次放开
    task key_ctrl;
        input [7:0] c;
        reg [7:0] code;
        begin
            code = scan_of(c);
            ps2_send(8'h14);            // 左 Ctrl 通码
            ps2_send(code);
            ps2_send(8'hF0); ps2_send(code);
            ps2_send(8'hF0); ps2_send(8'h14);
            repeat (5) @(posedge clk100);
        end
    endtask

    // ------------------------------------------------------------------
    // 测试流程
    // ------------------------------------------------------------------

    integer i;

    // 等待某一行出现完整提示符 "> " 的第 1 列, 说明该条命令已经处理完
    task wait_prompt;
        input integer row;
        integer guard;
        begin
            guard = 0;
            // 只等"行首是 >"还不够, 空格要下一个周期才写进去
            while (((scr(row, 0) !== 8'h3E) || (scr(row, 1) !== 8'h20)) &&
                   (guard < 20_000_000)) begin
                @(posedge clk100);
                guard = guard + 1;
            end
            if (guard >= 20_000_000) begin
                errors = errors + 1;
                $display("MISMATCH: 第 %0d 行没有出现提示符, got %02h %02h",
                         row, scr(row, 0), scr(row, 1));
            end
        end
    endtask

    // 等屏幕上某一格变成指定字符, 用来等软件把一行重画完
    task wait_byte;
        input integer row;
        input integer col;
        input [7:0] exp;
        integer guard;
        begin
            guard = 0;
            while ((scr(row, col) !== exp) && (guard < 5_000_000)) begin
                @(posedge clk100);
                guard = guard + 1;
            end
            if (guard >= 5_000_000) begin
                errors = errors + 1;
                $display("MISMATCH: 等 row %0d col %0d 变成 %02h 超时, got %02h",
                         row, col, exp, scr(row, col));
            end
        end
    endtask

    // 等光标落到屏幕 (row, col), 再检查物理行与硬件换算出的屏幕行
    task check_cursor;
        input integer row;
        input integer col;
        input integer phys_exp;
        integer guard;
        begin
            guard = 0;
            while (((u_dut.cur_disp_row !== row[4:0]) ||
                    (u_dut.u_bus.cursor_r[6:0] !== col[6:0])) &&
                   (guard < 2_000_000)) begin
                @(posedge clk100);
                guard = guard + 1;
            end
            if (guard >= 2_000_000) begin
                errors = errors + 1;
                $display("MISMATCH cursor: 等 screen (%0d,%0d) 超时, 现在 screen row %0d col %0d",
                         row, col, u_dut.cur_disp_row, u_dut.u_bus.cursor_r[6:0]);
            end
            if (u_dut.u_bus.cursor_r[11:7] !== phys_exp[4:0]) begin
                errors = errors + 1;
                $display("MISMATCH cursor: 物理行 got %0d, expected %0d",
                         u_dut.u_bus.cursor_r[11:7], phys_exp);
            end
            if (u_dut.cur_row_vis !== 1'b1) begin
                errors = errors + 1;
                $display("MISMATCH cursor: 硬件认为光标行不可见 (top_row=%0d, phys=%0d)",
                         u_dut.u_bus.top_row_r, u_dut.u_bus.cursor_r[11:7]);
            end
        end
    endtask

    // 等 VGA 扫描到某一格, 检查硬件的光标比较真的落在这一格上.
    // 这一条能抓到"拿物理行和屏幕行比较"的错: 滚屏后两者不同, 比较永远不成立,
    // 光标就画不出来, 或者画到别的行上.
    task check_cursor_cell;
        input integer row;
        input integer col;
        input [255:0] name;
        integer guard;
        begin
            guard = 0;
            while ((!(u_dut.valid && (u_dut.v_row == row[4:0]) &&
                      (u_dut.char_col == col[6:0]))) && (guard < 600_000)) begin
                @(negedge u_dut.pclk);
                guard = guard + 1;
            end
            if (guard >= 600_000) begin
                errors = errors + 1;
                $display("MISMATCH %0s: VGA 一直没扫到 (%0d,%0d)", name, row, col);
            end else if (u_dut.cursor_here !== 1'b1) begin
                errors = errors + 1;
                $display("MISMATCH %0s: VGA 扫到 (%0d,%0d) 时 cursor_here=0, 光标没有画在这一格",
                         name, row, col);
            end
        end
    endtask

    // 敲一串字符, 字符串右对齐, 前面的 0 跳过
    task type_line;
        input [8*40-1:0] s;
        integer k;
        reg [7:0] ch;
        begin
            for (k = 39; k >= 0; k = k - 1) begin
                ch = s[8*k +: 8];
                if (ch != 8'h00)
                    type_char(ch);
            end
        end
    endtask

    initial begin
        $dumpfile("sys_top_tb.vcd");
        $dumpvars(1, sys_top_tb);

        repeat (200) @(posedge clk100);   // 1us
        cpu_resetn = 1'b1;

        // 等待程序跑完 vga_init 并显示提示符
        wait_prompt(2);

        $display("[%0t] 提示符已显示", $time);
        expect_row(0, 19, "RV32I System  lab12");
        expect_row(1, 27, "hello | time | fib n | help");
        expect_row(2, 2,  "> ");

        // ---------------- hello ----------------
        type_char("h"); type_char("e"); type_char("l");
        type_char("l"); type_char("o");
        key_enter;
        $display("[%0t] 已输入 hello", $time);
        wait_prompt(4);

        expect_row(2, 7, "> hello");
        expect_row(3, 12, "Hello World!");
        expect_row(4, 2, "> ");

        // ---------------- fib 10 ----------------
        type_char("f"); type_char("i"); type_char("b");
        type_char(" "); type_char("1"); type_char("0");
        key_enter;
        wait_prompt(6);

        expect_row(4, 8, "> fib 10");
        expect_row(5, 2, "55");
        expect_row(6, 2, "> ");

        // ---------------- 未知命令 ----------------
        type_char("x"); type_char("y"); type_char("z");
        key_enter;
        wait_prompt(8);

        expect_row(6, 5, "> xyz");
        expect_row(7, 15, "Unknown Command");
        expect_row(8, 2, "> ");

        // ---------------- Shift 大小写 ----------------
        type_shift_char("H"); type_char("e"); type_char("l");
        type_char("l"); type_char("o");
        key_enter;
        wait_prompt(10);

        expect_row(8, 7, "> Hello");
        expect_row(9, 15, "Unknown Command");
        expect_row(10, 2, "> ");

        // ---------------- 退格 ----------------
        type_char("h"); type_char("e"); type_char("l");
        type_char("l"); type_char("p");
        key_bs;                    // 删掉 p
        type_char("o");
        key_enter;
        wait_prompt(12);

        expect_row(10, 7, "> hello");
        expect_row(11, 12, "Hello World!");
        expect_row(12, 2, "> ");

        // ---------------- time ----------------
        type_char("t"); type_char("i"); type_char("m");
        type_char("e");
        key_enter;
        wait_prompt(14);

        expect_row(12, 6, "> time");
        expect_row(13, 6, "time: ");
        if ((scr(13, 6) < 8'h30) || (scr(13, 6) > 8'h39)) begin
            errors = errors + 1;
            $display("MISMATCH time: 第 6 列不是数字, got %02h", scr(13, 6));
        end
        expect_row(14, 2, "> ");

        // ---------------- fib 46 / fib 47 ----------------
        type_char("f"); type_char("i"); type_char("b");
        type_char(" "); type_char("4"); type_char("6");
        key_enter;
        wait_prompt(16);
        expect_row(14, 8, "> fib 46");
        expect_row(15, 10, "1836311903");
        expect_row(16, 2, "> ");

        type_char("f"); type_char("i"); type_char("b");
        type_char(" "); type_char("4"); type_char("7");
        key_enter;
        wait_prompt(18);
        expect_row(17, 24, "fib: n too large, max 46");
        expect_row(18, 2, "> ");

        // ---------------- 行尾自动换行 ----------------
        // 光标在第 18 行第 2 列, 输入 75 个 z: 前 68 个填满到第 69 列,
        // 第 69 个触发换行, 剩下 7 个落在第 19 行.
        // 再左移两格、退格、插入 y, 验证跨两行的行内修改: 第 19 行第 4 列变成 y.
        for (i = 0; i < 75; i = i + 1)
            type_char("z");
        key_left;
        key_left;
        key_bs;
        type_char("y");
        key_enter;
        wait_prompt(21);

        for (i = 2; i < 70; i = i + 1)
            check_byte(18, i, "z", "wrap row 18");
        expect_row(19, 7, "zzzzyzz");
        check_byte(19, 7, 8'h00, "wrap row 19 end");
        expect_row(20, 15, "Unknown Command");
        expect_row(21, 2, "> ");

        // ---------------- 左右方向键在行内插入 ----------------
        // abc -> 左 左 -> x -> 右 -> z, 期望 "axbzc"
        type_char("a"); type_char("b"); type_char("c");
        key_left; key_left;
        type_char("x");
        key_right;
        type_char("z");
        wait_byte(21, 6, "c");
        wait_byte(21, 5, "z");       // 插入的 z 落在第 5 列
        expect_row(21, 7, "> axbzc");
        check_byte(21, 7, 8'h00, "arrow insert no leftover");
        check_cursor(21, 6, 21);
        key_enter;
        wait_prompt(23);

        expect_row(22, 15, "Unknown Command");
        expect_row(23, 2, "> ");

        // ---------------- Tab 补全 ----------------
        // fi + Tab -> "fib " (唯一候选补一个空格), 再打 10 回车
        type_char("f"); type_char("i");
        key_tab;
        wait_byte(23, 5, " ");
        expect_row(23, 5, "> fib");
        type_char("1"); type_char("0");
        key_enter;
        wait_prompt(25);

        expect_row(23, 8, "> fib 10");
        expect_row(24, 2, "55");
        expect_row(25, 2, "> ");

        // he + Tab -> 两个候选取公共前缀 "hel", 再补 p 变成 help
        type_char("h"); type_char("e");
        key_tab;
        wait_byte(25, 4, "l");
        expect_row(25, 5, "> hel");
        check_byte(25, 5, 8'h00, "tab prefix no leftover");
        key_tab;                       // 有歧义, 不应再变化
        expect_row(25, 5, "> hel");
        type_char("p");
        key_enter;
        wait_prompt(28);

        expect_row(25, 6, "> help");
        expect_row(26, 66, "commands: hello,time,fib n,echo,led,sw,mem,calc,history,clear,help");
        expect_row(27, 52, "keys: Left/Right move, Up/Down history, Tab complete");
        expect_row(28, 2, "> ");

        // ---------------- 上下方向键调历史 ----------------
        key_up;                        // 上一条命令是 help
        wait_byte(28, 4, "l");
        expect_row(28, 6, "> help");
        key_down;                      // 回到正在编辑的空行
        wait_byte(28, 2, 8'h00);
        expect_row(28, 2, "> ");
        check_byte(28, 2, 8'h00, "history down clears line");
        check_cursor(28, 2, 28);

        key_enter;                     // 空行回车, 只换行
        wait_prompt(29);
        expect_row(29, 2, "> ");
        check_cursor(29, 2, 29);

        // ---------------- 滚屏后的光标 ----------------
        // 再来一次空行回车: 已经在最后一行, 触发滚屏
        key_enter;
        i = 0;
        while ((u_dut.u_bus.top_row_r === 5'd0) && (i < 2_000_000)) begin
            @(posedge clk100);
            i = i + 1;
        end
        if (u_dut.u_bus.top_row_r === 5'd0) begin
            errors = errors + 1;
            $display("MISMATCH scroll: top_row 仍为 0");
        end

        // 滚屏后提示符在最底行; 光标的物理行是 30, 屏幕行必须还是 29.
        // 老实现直接拿物理行和 v_row 比较, 光标会画到屏幕外, 也就是"光标消失".
        wait_prompt(29);
        check_cursor(29, 2, (u_dut.u_bus.top_row_r + 29) & 31);
        if (u_dut.u_bus.cursor_r[11:7] === 5'd29) begin
            errors = errors + 1;
            $display("MISMATCH scroll: 物理行没有随滚屏前移, 光标会画错行");
        end
        expect_row(29, 2, "> ");
        check_byte(29, 2, 8'h00, "scroll bottom cleared");

        // 硬件真的把光标画在 (29,2): 等 VGA 扫到这一格, cursor_here 必须为 1.
        // 老实现比较的是物理行 30, 屏幕上没有第 30 行, 光标就消失了.
        check_cursor_cell(29, 2, "cursor after scroll");

        // ================= 第二阶段: 复位后测控制键与新命令 =================
        // 复位会清屏并重新跑 vga_init, 用干净的屏幕重新摆用例, 行号简单.
        sw = 16'hA55A;
        cpu_resetn = 1'b0;
        repeat (50) @(posedge clk100);
        cpu_resetn = 1'b1;

        // 等标题重新出现, 避免读到上一阶段的残留内容
        i = 0;
        while ((!(scr(0, 0) === 8'h52 && scr(0, 1) === 8'h56)) && (i < 5_000_000)) begin
            @(posedge clk100);
            i = i + 1;
        end
        if (!(scr(0, 0) === 8'h52 && scr(0, 1) === 8'h56)) begin
            errors = errors + 1;
            $display("MISMATCH: 复位后没有重新打印标题");
        end
        expect_row(0, 19, "RV32I System  lab12");
        expect_row(1, 27, "hello | time | fib n | help");
        wait_prompt(2);

        // ---------------- echo ----------------
        type_line("echo hi there");
        key_enter;
        wait_prompt(4);
        expect_row(2, 15, "> echo hi there");
        expect_row(3, 8, "hi there");
        expect_row(4, 2, "> ");

        // ---------------- sw ----------------
        type_line("sw");
        key_enter;
        wait_prompt(6);
        expect_row(4, 4, "> sw");
        expect_row(5, 10, "sw: 0xa55a");
        expect_row(6, 2, "> ");

        // ---------------- led ----------------
        type_line("led 0x0f0f");
        key_enter;
        wait_prompt(8);
        expect_row(6, 12, "> led 0x0f0f");
        expect_row(7, 11, "led: 0x0f0f");
        if (u_dut.LED[14:0] !== 15'h0F0F) begin
            errors = errors + 1;
            $display("MISMATCH led: LED[14:0] got %04h, expected 0f0f", u_dut.LED[14:0]);
        end
        expect_row(8, 2, "> ");

        // ---------------- history ----------------
        // 先把历史清空, 后面的行号才好算; 复位不会清 dmem, 上一阶段的命令还在里面
        type_line("history clear");
        key_enter;
        wait_prompt(10);
        expect_row(8, 15, "> history clear");
        expect_row(9, 16, "history: cleared");
        expect_row(10, 2, "> ");

        type_line("echo again");
        key_enter;
        wait_prompt(12);
        expect_row(11, 5, "again");
        expect_row(12, 2, "> ");

        type_line("history");
        key_enter;
        wait_prompt(16);
        expect_row(12, 9, "> history");
        expect_row(13, 8, "history:");
        expect_row(14, 14, "  1 echo again");
        expect_row(15, 11, "  2 history");
        expect_row(16, 2, "> ");

        // ---------------- Ctrl+L 清屏, 已输入的内容保留并重画 ----------------
        type_line("ab");
        wait_byte(16, 3, "b");
        key_ctrl("l");
        wait_byte(0, 3, "b");
        expect_row(0, 4, "> ab");
        check_byte(0, 4, 8'h00, "ctrl-l tail cleared");
        check_byte(1, 0, 8'h00, "ctrl-l screen cleared");
        check_cursor(0, 4, 0);

        // ---------------- Ctrl+U 清空当前行 ----------------
        key_ctrl("u");
        wait_byte(0, 2, 8'h00);
        expect_row(0, 2, "> ");
        check_cursor(0, 2, 0);

        // ---------------- Ctrl+A / Ctrl+E / Ctrl+C ----------------
        type_line("xyz");
        wait_byte(0, 4, "z");
        key_ctrl("a");
        check_cursor(0, 2, 0);
        key_ctrl("e");
        check_cursor(0, 5, 0);
        key_ctrl("c");
        wait_prompt(1);
        expect_row(0, 7, "> xyz^C");
        expect_row(1, 2, "> ");
        check_cursor(1, 2, 1);

        // ---------------- clear 命令 ----------------
        type_line("clear");
        key_enter;
        // 清屏是逐字节清显存, 要等它清完并把新提示符写回第 0 行
        i = 0;
        while ((!(scr(0, 0) === 8'h3E && scr(0, 1) === 8'h20 &&
                  scr(0, 2) === 8'h00 && scr(1, 0) === 8'h00)) && (i < 2_000_000)) begin
            @(posedge clk100);
            i = i + 1;
        end
        check_byte(0, 0, 8'h3E, "clear prompt >");
        check_byte(0, 1, 8'h20, "clear prompt space");
        check_byte(1, 0, 8'h00, "clear row 1 blank");
        check_cursor(0, 2, 0);

        // ---------------- 跨两行的输入行上按 Ctrl+C ----------------
        // 70 个 z 填满第 0 行并续到第 1 行, ^C 要打在第 1 行行尾, 提示符落在第 2 行
        for (i = 0; i < 70; i = i + 1)
            type_char("z");
        wait_byte(1, 1, "z");
        key_ctrl("c");
        wait_prompt(2);
        for (i = 2; i < 70; i = i + 1)
            check_byte(0, i, "z", "ctrl-c wrapped row 0");
        check_byte(1, 0, "z", "ctrl-c wrapped row 1");
        check_byte(1, 1, "z", "ctrl-c wrapped row 1 tail");
        check_byte(1, 2, "^", "ctrl-c caret");
        check_byte(1, 3, "C", "ctrl-c C");
        check_byte(1, 4, 8'h00, "ctrl-c end");
        check_cursor(2, 2, 2);

        // ---------------- calc: 优先级、负号、括号、除零 ----------------
        // + 和 * 是上档字符, 要按住 Shift 敲
        type_line("calc 1");
        type_shift_char("+");
        type_char("2");
        type_shift_char("*");
        type_char("3");
        key_enter;
        wait_prompt(4);
        expect_row(2, 12, "> calc 1+2*3");
        expect_row(3, 1, "7");
        expect_row(4, 2, "> ");

        type_line("calc -7/2");
        key_enter;
        wait_prompt(6);
        expect_row(5, 2, "-3");

        type_line("calc ");
        type_shift_char("(");
        type_char("1");
        type_shift_char("+");
        type_char("2");
        type_shift_char(")");
        type_shift_char("*");
        type_char("3");
        key_enter;
        wait_prompt(8);
        expect_row(7, 1, "9");
        expect_row(8, 2, "> ");

        type_line("calc 10/0");
        key_enter;
        wait_prompt(10);
        expect_row(9, 20, "calc: divide by zero");
        expect_row(10, 2, "> ");

        // ---------------- mem: 读键盘状态寄存器 ----------------
        type_line("mem 0x300004 1");
        key_enter;
        wait_prompt(12);
        expect_row(11, 18, "00300004: 00000000");
        expect_row(12, 2, "> ");

        // ---------------- time: 时:分:秒 ----------------
        type_line("time");
        key_enter;
        wait_prompt(14);
        expect_row(13, 6, "time: ");
        for (i = 6; i <= 13; i = i + 1) begin
            if ((i == 8) || (i == 11)) begin
                if (scr(13, i) !== ":") begin
                    errors = errors + 1;
                    $display("MISMATCH time 格式: 第 %0d 列应为冒号, got %02h", i, scr(13, i));
                end
            end else if ((scr(13, i) < 8'h30) || (scr(13, i) > 8'h39)) begin
                errors = errors + 1;
                $display("MISMATCH time 格式: 第 %0d 列应为数字, got %02h", i, scr(13, i));
            end
        end

        // 键盘 FIFO 不能溢出, 否则说明软件处理按键比敲键慢, 有键被丢掉
        if (u_dut.u_bus.kbd_overflow !== 1'b0) begin
            errors = errors + 1;
            $display("MISMATCH: 键盘 FIFO 溢出, 有按键被丢弃");
        end

        // ---------------- 结果 ----------------
        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);

        $display("[%0t] 仿真结束", $time);
        $finish;
    end

    // 超时保护
    initial begin
        #60_000_000;
        $display("TEST FAILED: timeout");
        $finish;
    end

endmodule

`timescale 1ns / 1ps
// charterm_top 自检: 键盘模型发扫描码, 比对显存与光标, 约 90us 跑完

module ps2_keyboard_model(
    output reg ps2_clk,
    output reg ps2_data
);
    parameter [31:0] kbd_clk_period = 80;
    initial ps2_clk = 1'b1;

    task kbd_sendcode;
        input [7:0] code;
        integer i;
        reg [10:0] send_buffer;
        begin
            send_buffer[0]    = 1'b0;
            send_buffer[8:1]  = code;
            send_buffer[9]    = ~(^code);
            send_buffer[10]   = 1'b1;
            i = 0;
            while (i < 11) begin
                ps2_data = send_buffer[i];
                #(kbd_clk_period/2) ps2_clk = 1'b0;
                #(kbd_clk_period/2) ps2_clk = 1'b1;
                i = i + 1;
            end
        end
    endtask
endmodule


module charterm_top_tb;

    reg         CLK100MHZ;
    reg         BTNC;
    wire        PS2_CLK, PS2_DATA;
    wire        VGA_HS, VGA_VS;
    wire [3:0]  VGA_R, VGA_G, VGA_B;
    wire [3:0]  LED;

    charterm_top uut (
        .CLK100MHZ(CLK100MHZ),
        .PS2_CLK(PS2_CLK),
        .PS2_DATA(PS2_DATA),
        .BTNC(BTNC),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .LED(LED)
    );

    ps2_keyboard_model model (
        .ps2_clk(PS2_CLK),
        .ps2_data(PS2_DATA)
    );

    initial CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    integer errors;

    localparam [7:0] SP = 8'h20;
    localparam [3:0] T_IDLE = 4'd2;

    // 字符显存地址: {row[4:0], col[6:0]} = row*128 + col
    function [11:0] cell_idx;
        input [4:0] row;
        input [6:0] col;
        begin
            cell_idx = {row, col};
        end
    endfunction

    task send;
        input [7:0] b;
        begin
            model.kbd_sendcode(b);
            #200;
        end
    endtask

    task settle;
        begin
            #400;
            wait (uut.tstate == T_IDLE);
            #100;
        end
    endtask

    task chk_byte;
        input [11:0] addr;
        input [7:0]  exp;
        input [7:0]  tag;
        begin
            if (uut.charmem[addr] !== exp) begin
                $display("MISMATCH[%0d]: charmem[%0d]=0x%02h expected 0x%02h",
                         tag, addr, uut.charmem[addr], exp);
                errors = errors + 1;
            end
        end
    endtask

    task chk_cur;
        input [4:0] erow;
        input [6:0] ecol;
        input [4:0] etop;
        begin
            if (uut.cur_row !== erow) begin
                $display("MISMATCH: cur_row=%0d expected %0d", uut.cur_row, erow);
                errors = errors + 1;
            end
            if (uut.cur_col !== ecol) begin
                $display("MISMATCH: cur_col=%0d expected %0d", uut.cur_col, ecol);
                errors = errors + 1;
            end
            if (uut.top_row !== etop) begin
                $display("MISMATCH: top_row=%0d expected %0d", uut.top_row, etop);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        CLK100MHZ = 1'b0;
        BTNC      = 1'b1;
        errors    = 0;

        #200;
        BTNC = 1'b0;
        wait (uut.tstate == T_IDLE);
        #100;

        // 1. 复位后: 清屏 + 行首提示符 "> " , 光标在 col2
        chk_byte(cell_idx(5'd0, 7'd0), 8'h3E, 8'd1);
        chk_byte(cell_idx(5'd0, 7'd1), SP,     8'd2);
        chk_byte(cell_idx(5'd0, 7'd2), SP,     8'd3);
        chk_byte(cell_idx(5'd29, 7'd69), SP,   8'd4);
        chk_cur(5'd0, 7'd2, 5'd0);

        // 2. 回显普通字符 h i
        send(8'h33); settle;                 // h
        chk_byte(cell_idx(5'd0, 7'd2), 8'h68, 8'd5);
        chk_cur(5'd0, 7'd3, 5'd0);
        send(8'h43); settle;                 // i
        chk_byte(cell_idx(5'd0, 7'd3), 8'h69, 8'd6);
        chk_cur(5'd0, 7'd4, 5'd0);

        // 3. Shift + i => 'I'
        send(8'h12);                         // left shift make
        #200;
        if (LED[0] !== 1'b1) begin
            $display("MISMATCH: LED[0] shift indicator not set");
            errors = errors + 1;
        end
        send(8'h43); settle;                 // shift+i => I
        chk_byte(cell_idx(5'd0, 7'd4), 8'h49, 8'd7);
        chk_cur(5'd0, 7'd5, 5'd0);
        send(8'hF0); send(8'h43);            // release i
        send(8'hF0); send(8'h12);            // release shift
        #200;
        if (LED[0] !== 1'b0) begin
            $display("MISMATCH: LED[0] shift indicator stuck");
            errors = errors + 1;
        end

        // 4. 回车换行 -> 新行提示符
        send(8'h5A); settle;                 // Enter
        chk_byte(cell_idx(5'd1, 7'd0), 8'h3E, 8'd8);
        chk_byte(cell_idx(5'd1, 7'd1), SP,     8'd9);
        chk_cur(5'd1, 7'd2, 5'd0);

        // 5. 输入 a b 再退格
        send(8'h1C); settle;                 // a
        send(8'h32); settle;                 // b
        chk_byte(cell_idx(5'd1, 7'd2), 8'h61, 8'd10);
        chk_byte(cell_idx(5'd1, 7'd3), 8'h62, 8'd11);
        chk_cur(5'd1, 7'd4, 5'd0);

        send(8'h66); settle;                 // BackSpace 删 b
        chk_byte(cell_idx(5'd1, 7'd3), SP, 8'd12);
        chk_cur(5'd1, 7'd3, 5'd0);

        send(8'h66); settle;                 // BackSpace 删 a
        chk_byte(cell_idx(5'd1, 7'd2), SP, 8'd13);
        chk_cur(5'd1, 7'd2, 5'd0);

        // 6. 行首再退格 -> 删除回车, 光标回到上一行末尾非空字符后
        send(8'h66); settle;                 // 上一行 col4 'I' 之后 => col5
        chk_cur(5'd0, 7'd5, 5'd0);
        chk_byte(cell_idx(5'd1, 7'd0), SP, 8'd14); // 当前行的提示符被清除
        chk_byte(cell_idx(5'd1, 7'd1), SP, 8'd15);

        // 7. Shift + 1 => '!'
        send(8'h12); send(8'h16); settle;    // shift+1 => !
        chk_byte(cell_idx(5'd0, 7'd5), 8'h21, 8'd14);
        send(8'hF0); send(8'h16);
        send(8'hF0); send(8'h12);
        settle;
        chk_cur(5'd0, 7'd6, 5'd0);

        // 8. 方向键: 上下移动时列号钳位到目标行行末, 不落到空白区域
        send(8'hE0); send(8'h6B); settle;    // Left
        chk_cur(5'd0, 7'd5, 5'd0);
        send(8'hE0); send(8'h74); settle;    // Right
        chk_cur(5'd0, 7'd6, 5'd0);
        send(8'hE0); send(8'h75); settle;    // Up 在首行不动
        chk_cur(5'd0, 7'd6, 5'd0);
        send(8'hE0); send(8'h72); settle;    // Down 到空白行, 列号收到 0
        chk_cur(5'd1, 7'd0, 5'd0);
        uut.cur_col = 7'd40;                 // 强行把光标放到空白区域
        #100;
        send(8'hE0); send(8'h75); settle;    // Up 落在 '!' 之后
        chk_cur(5'd0, 7'd6, 5'd0);

        // 9. Tab: 补空格到下一个 4 列制表位
        send(8'h0D); settle;                 // 已在 col6 -> 补 col6,col7, 停在 col8
        chk_byte(cell_idx(5'd0, 7'd6), SP,  8'd16);
        chk_byte(cell_idx(5'd0, 7'd7), SP,  8'd17);
        chk_cur(5'd0, 7'd8, 5'd0);
        send(8'h0D); settle;                 // 已在制表位 -> 补 4 个空格到 col12
        chk_byte(cell_idx(5'd0, 7'd11), SP, 8'd18);
        chk_cur(5'd0, 7'd12, 5'd0);

        // 10. 行尾自动换行: 续行不打印提示符
        uut.cur_col = 7'd69;
        #100;
        send(8'h22); settle;                 // x -> 写在 col69 后换行
        chk_byte(cell_idx(5'd0, 7'd69), 8'h78, 8'd19);
        chk_byte(cell_idx(5'd1, 7'd0),  SP,    8'd20);
        chk_cur(5'd1, 7'd0, 5'd0);

        // 11. 续行输入; 续行行首退格应删掉上一行写满时最后一个字符
        send(8'h35); settle;                 // y -> 写在续行 col0
        chk_byte(cell_idx(5'd1, 7'd0), 8'h79, 8'd21);
        chk_cur(5'd1, 7'd1, 5'd0);
        send(8'h66); settle;                 // BackSpace 删 y
        chk_byte(cell_idx(5'd1, 7'd0), SP, 8'd22);
        chk_cur(5'd1, 7'd0, 5'd0);
        send(8'h66); settle;                 // 续行行首退格 -> 删掉上一行 col69
        chk_byte(cell_idx(5'd0, 7'd69), SP, 8'd23);
        chk_cur(5'd0, 7'd69, 5'd0);

        // 12. 末行回车 -> 滚屏
        uut.cur_row = 5'd29;
        uut.cur_col = 7'd2;
        #100;
        send(8'h5A); settle;                 // Enter on last row
        chk_cur(5'd29, 7'd2, 5'd1);          // top_row 加 1
        chk_byte(cell_idx(5'd30, 7'd0), 8'h3E, 8'd24);
        chk_byte(cell_idx(5'd30, 7'd1), SP,   8'd25);
        chk_byte(cell_idx(5'd30, 7'd69), SP,  8'd26);

        // 13. 数字与不用 Shift 的符号
        send(8'h16); settle;                 // 1
        send(8'h4E); settle;                 // -
        send(8'h45); settle;                 // 0
        chk_byte(cell_idx(5'd30, 7'd2), 8'h31, 8'd27);
        chk_byte(cell_idx(5'd30, 7'd3), 8'h2D, 8'd28);
        chk_byte(cell_idx(5'd30, 7'd4), 8'h30, 8'd29);
        chk_cur(5'd29, 7'd5, 5'd1);

        // 14. 按住不放时键盘重复发送 make 码, 应重复回显
        send(8'h1C); send(8'h1C); settle;    // a a
        chk_byte(cell_idx(5'd30, 7'd5), 8'h61, 8'd30);
        chk_byte(cell_idx(5'd30, 7'd6), 8'h61, 8'd31);
        chk_cur(5'd29, 7'd7, 5'd1);

        // 15. 右 Shift 也能输入大写
        send(8'hE0); send(8'h59); settle;    // right shift make
        if (LED[0] !== 1'b1) begin
            $display("MISMATCH: right shift indicator not set");
            errors = errors + 1;
        end
        send(8'h43); settle;                 // shift+i => I
        chk_byte(cell_idx(5'd30, 7'd7), 8'h49, 8'd32);
        chk_cur(5'd29, 7'd8, 5'd1);
        send(8'hE0); send(8'hF0); send(8'h59); // right shift release
        send(8'hF0); send(8'h43);            // release i
        settle;
        if (LED[0] !== 1'b0) begin
            $display("MISMATCH: right shift indicator stuck");
            errors = errors + 1;
        end

        // 14. 点阵 ROM 查表: 'A' 第 4 行应为 038h, '>' 第 4 行应为 00Ch
        if (uut.font_rom[16*8'h41 + 3] !== 12'h038) begin
            $display("MISMATCH: font ROM 'A' row3 = %h", uut.font_rom[16*8'h41 + 3]);
            errors = errors + 1;
        end
        if (uut.font_rom[16*8'h3E + 3] !== 12'h00C) begin
            $display("MISMATCH: font ROM '>' row3 = %h", uut.font_rom[16*8'h3E + 3]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

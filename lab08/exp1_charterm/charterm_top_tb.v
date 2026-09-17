`timescale 1ns / 1ps
//=======================================================================
// lab08 exp1_charterm self-checking testbench
//
// 覆盖: 复位清屏 + 提示符, 普通按键回显, Shift 大写/符号, 回车换行,
//       BackSpace 删字符并跨行回到上一行末尾, 方向键, 行尾自动换行(滚屏),
//       点阵 ROM 查表。
// 说明: 键盘每个字节约 440ns, 建议 Vivado 仿真时间设为 1ms 级。
//       波形上可看 VGA 输出; 逻辑正确性以 charterm_top 内部寄存器为准。
//=======================================================================

module ps2_keyboard_model(
    output reg ps2_clk,
    output reg ps2_data
);
    parameter [31:0] kbd_clk_period = 400;
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
            #500;
        end
    endtask

    task settle;
        begin
            #1500;
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

        //--- 1. 复位后: 清屏 + 行首提示符 "> " , 光标在 col2 --------
        chk_byte(cell_idx(5'd0, 7'd0), 8'h3E, 8'd1);
        chk_byte(cell_idx(5'd0, 7'd1), SP,     8'd2);
        chk_byte(cell_idx(5'd0, 7'd2), SP,     8'd3);
        chk_byte(cell_idx(5'd29, 7'd69), SP,   8'd4);
        chk_cur(5'd0, 7'd2, 5'd0);

        //--- 2. 回显普通字符 h i ------------------------------------
        send(8'h33); settle;                 // h
        chk_byte(cell_idx(5'd0, 7'd2), 8'h68, 8'd5);
        chk_cur(5'd0, 7'd3, 5'd0);
        send(8'h43); settle;                 // i
        chk_byte(cell_idx(5'd0, 7'd3), 8'h69, 8'd6);
        chk_cur(5'd0, 7'd4, 5'd0);

        //--- 3. Shift + i => 'I' -----------------------------------
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

        //--- 4. 回车换行 -> 新行提示符 ------------------------------
        send(8'h5A); settle;                 // Enter
        chk_byte(cell_idx(5'd1, 7'd0), 8'h3E, 8'd8);
        chk_byte(cell_idx(5'd1, 7'd1), SP,     8'd9);
        chk_cur(5'd1, 7'd2, 5'd0);

        //--- 5. 输入 a b 再退格 ------------------------------------
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

        //--- 6. 行首再退格 -> 回到上一行末尾非空字符后 --------------
        send(8'h66); settle;                 // 上一行 col4 'I' 之后 => col5
        chk_cur(5'd0, 7'd5, 5'd0);

        //--- 7. Shift + 1 => '!' -----------------------------------
        send(8'h12); send(8'h16); settle;    // shift+1 => !
        chk_byte(cell_idx(5'd0, 7'd5), 8'h21, 8'd14);
        send(8'hF0); send(8'h16);
        send(8'hF0); send(8'h12);
        settle;
        chk_cur(5'd0, 7'd6, 5'd0);

        //--- 8. 方向键 ---------------------------------------------
        send(8'hE0); send(8'h6B); settle;    // Left
        chk_cur(5'd0, 7'd5, 5'd0);
        send(8'hE0); send(8'h74); settle;    // Right
        chk_cur(5'd0, 7'd6, 5'd0);
        send(8'hE0); send(8'h75); settle;    // Up
        chk_cur(5'd0, 7'd6, 5'd0);
        send(8'hE0); send(8'h72); settle;    // Down
        chk_cur(5'd1, 7'd6, 5'd0);
        send(8'hE0); send(8'h75); settle;    // Up
        chk_cur(5'd0, 7'd6, 5'd0);

        //--- 9. 行尾自动换行 ---------------------------------------
        uut.cur_col = 7'd69;
        #100;
        send(8'h22); settle;                 // x -> 写在 col69 后换行
        chk_byte(cell_idx(5'd0, 7'd69), 8'h78, 8'd15);
        chk_byte(cell_idx(5'd1, 7'd0), 8'h3E, 8'd16);
        chk_cur(5'd1, 7'd2, 5'd0);

        //--- 10. 末行回车 -> 滚屏 ----------------------------------
        uut.cur_row = 5'd29;
        uut.cur_col = 7'd2;
        #100;
        send(8'h5A); settle;                 // Enter on last row
        chk_cur(5'd29, 7'd2, 5'd1);          // top_row 加 1
        chk_byte(cell_idx(5'd30, 7'd0), 8'h3E, 8'd17);
        chk_byte(cell_idx(5'd30, 7'd1), SP,   8'd18);
        chk_byte(cell_idx(5'd30, 7'd69), SP,  8'd19);

        //--- 11. 点阵 ROM 查表 -------------------------------------
        force uut.chr = 8'h41;               // 'A'
        #10;
        if (uut.font_pack !== 144'h000000000E3B198CFE771B0D87C3E0E07000) begin
            $display("MISMATCH: font ROM for 'A' = %h", uut.font_pack);
            errors = errors + 1;
        end
        release uut.chr;

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

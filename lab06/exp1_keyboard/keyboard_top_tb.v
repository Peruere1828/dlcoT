`timescale 1ns / 1ps

module ps2_keyboard_model(
    output reg ps2_clk,
    output reg ps2_data
);
    parameter [31:0] kbd_clk_period = 60;
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


module keyboard_top_tb;

    reg        CLK100MHZ;
    reg        BTNC;
    wire       PS2_CLK, PS2_DATA;
    wire [7:0] AN, HEX;
    wire [3:0] LED;

    keyboard_top #(
        .SCAN_MAX(1)
    ) uut (
        .CLK100MHZ(CLK100MHZ),
        .PS2_CLK(PS2_CLK),
        .PS2_DATA(PS2_DATA),
        .BTNC(BTNC),
        .AN(AN),
        .HEX(HEX),
        .LED(LED)
    );

    ps2_keyboard_model model(
        .ps2_clk(PS2_CLK),
        .ps2_data(PS2_DATA)
    );

    initial CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    integer errors;

    function [6:0] hex2seg;
        input [3:0] d;
        case (d)
            4'd0:  hex2seg = 7'b1000000;
            4'd1:  hex2seg = 7'b1111001;
            4'd2:  hex2seg = 7'b0100100;
            4'd3:  hex2seg = 7'b0110000;
            4'd4:  hex2seg = 7'b0011001;
            4'd5:  hex2seg = 7'b0010010;
            4'd6:  hex2seg = 7'b0000010;
            4'd7:  hex2seg = 7'b1111000;
            4'd8:  hex2seg = 7'b0000000;
            4'd9:  hex2seg = 7'b0010000;
            4'd10: hex2seg = 7'b0001000;
            4'd11: hex2seg = 7'b0000011;
            4'd12: hex2seg = 7'b1000110;
            4'd13: hex2seg = 7'b0100001;
            4'd14: hex2seg = 7'b0000110;
            4'd15: hex2seg = 7'b0001110;
            default: hex2seg = 7'b1111111;
        endcase
    endfunction

    task check_digit;
        input [7:0] an_sel;
        input [6:0] exp_seg;
        integer guard;
        begin
            guard = 0;
            while (AN !== an_sel && guard < 1000) begin
                @(posedge CLK100MHZ);
                guard = guard + 1;
            end
            if (guard >= 1000) begin
                $display("MISMATCH: digit AN=%b never enabled", an_sel);
                errors = errors + 1;
            end else if (HEX !== {exp_seg, 1'b1}) begin
                $display("MISMATCH: AN=%b HEX=%b expected %b", AN, HEX, {exp_seg, 1'b1});
                errors = errors + 1;
            end
        end
    endtask

    task expect_led;
        input exp_shift;
        input exp_ctrl;
        begin
            if (LED[0] !== exp_shift) begin
                $display("MISMATCH: LED0(shift)=%b expected %b", LED[0], exp_shift);
                errors = errors + 1;
            end
            if (LED[1] !== exp_ctrl) begin
                $display("MISMATCH: LED1(ctrl)=%b expected %b", LED[1], exp_ctrl);
                errors = errors + 1;
            end
        end
    endtask

    task expect_state;
        input        exp_held;
        input [7:0]  exp_key;
        input [7:0]  exp_ascii;
        input        exp_blank;
        begin
            if (uut.held !== exp_held) begin
                $display("MISMATCH: held=%b expected %b", uut.held, exp_held);
                errors = errors + 1;
            end
            if (uut.keycode !== exp_key) begin
                $display("MISMATCH: keycode=0x%02h expected 0x%02h", uut.keycode, exp_key);
                errors = errors + 1;
            end
            if (uut.ascii !== exp_ascii) begin
                $display("MISMATCH: ascii=0x%02h expected 0x%02h", uut.ascii, exp_ascii);
                errors = errors + 1;
            end
            if (exp_blank) begin
                check_digit(8'b11111110, 7'b1111111);
                check_digit(8'b11111101, 7'b1111111);
                check_digit(8'b11111011, 7'b1111111);
                check_digit(8'b11110111, 7'b1111111);
            end else begin
                check_digit(8'b11111110, hex2seg(exp_key[3:0]));
                check_digit(8'b11111101, hex2seg(exp_key[7:4]));
                check_digit(8'b11111011, hex2seg(exp_ascii[3:0]));
                check_digit(8'b11110111, hex2seg(exp_ascii[7:4]));
            end
        end
    endtask

    task check_count;
        input [3:0] exp_u;
        input [3:0] exp_t;
        begin
            if (uut.bcd_u !== exp_u || uut.bcd_t !== exp_t) begin
                $display("MISMATCH: count=%d%d expected %d%d", uut.bcd_t, uut.bcd_u, exp_t, exp_u);
                errors = errors + 1;
            end
            check_digit(8'b10111111, hex2seg(exp_u));
            check_digit(8'b01111111, hex2seg(exp_t));
        end
    endtask

    task send;
        input [7:0] code;
        begin
            model.kbd_sendcode(code);
            #200;
        end
    endtask

    initial begin
        CLK100MHZ = 1'b0;
        BTNC = 1'b1;
        errors = 0;
        #100;
        BTNC = 1'b0;
        #100;

        // 复位后：无按键，数码管全灭，修饰键 LED 全灭
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        expect_led(1'b0, 1'b0);
        check_count(4'd0, 4'd0);

        // 左 Shift 按下：只亮 LED0，不算按键，不计入总数
        send(8'h12);
        expect_led(1'b1, 1'b0);
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        check_count(4'd0, 4'd0);

        // Shift + 1 -> '!' (0x21)
        send(8'h16);
        expect_state(1'b1, 8'h16, 8'h21, 1'b0);
        expect_led(1'b1, 1'b0);
        check_count(4'd1, 4'd0);

        // 松开 1：键码与 ASCII 归零，Shift 仍按住
        send(8'hf0);
        send(8'h16);
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        expect_led(1'b1, 1'b0);
        check_count(4'd1, 4'd0);

        // Shift + a -> 'A' (0x41)
        send(8'h1c);
        expect_state(1'b1, 8'h1c, 8'h41, 1'b0);
        check_count(4'd2, 4'd0);

        // 松开 a，再松开左 Shift
        send(8'hf0);
        send(8'h1c);
        send(8'hf0);
        send(8'h12);
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        expect_led(1'b0, 1'b0);

        // 无 Shift 时 2 -> '2' (0x32)
        send(8'h1e);
        expect_state(1'b1, 8'h1e, 8'h32, 1'b0);
        check_count(4'd3, 4'd0);

        // 按住 2 期间再按 Shift：ASCII 立即变为 '@' (0x40)
        send(8'h12);
        expect_state(1'b1, 8'h1e, 8'h40, 1'b0);
        expect_led(1'b1, 1'b0);

        // 松开 Shift：ASCII 变回 '2'
        send(8'hf0);
        send(8'h12);
        expect_state(1'b1, 8'h1e, 8'h32, 1'b0);
        expect_led(1'b0, 1'b0);

        // 松开 2
        send(8'hf0);
        send(8'h1e);
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        check_count(4'd3, 4'd0);

        // 左 Ctrl 按下/松开：只亮 LED1，不计数
        send(8'h14);
        expect_led(1'b0, 1'b1);
        expect_state(1'b0, 8'h00, 8'h00, 1'b1);
        check_count(4'd3, 4'd0);
        send(8'hf0);
        send(8'h14);
        expect_led(1'b0, 1'b0);

        // 右 Shift (0x59) + ; -> ':' (0x3a)
        send(8'h59);
        expect_led(1'b1, 1'b0);
        send(8'h4c);
        expect_state(1'b1, 8'h4c, 8'h3a, 1'b0);
        check_count(4'd4, 4'd0);
        send(8'hf0);
        send(8'h4c);
        send(8'hf0);
        send(8'h59);
        expect_led(1'b0, 1'b0);

        // 无 Shift 的普通按键仍按原表转换：s -> 0x73
        send(8'h1b);
        expect_state(1'b1, 8'h1b, 8'h73, 1'b0);
        check_count(4'd5, 4'd0);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

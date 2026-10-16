module keyboard_top #(
    parameter integer SCAN_MAX = 25000
)(
    input        CLK100MHZ,
    input        PS2_CLK,
    input        PS2_DATA,
    input        BTNC,
    output [7:0] AN,
    output [7:0] HEX,
    output [3:0] LED
);

    wire        ready;
    wire        overflow;
    wire [7:0]  rx;
    reg         nextdata_n;

    ps2_keyboard u_kbd (
        .clk(CLK100MHZ),
        .clrn(~BTNC),
        .ps2_clk(PS2_CLK),
        .ps2_data(PS2_DATA),
        .data(rx),
        .ready(ready),
        .nextdata_n(nextdata_n),
        .overflow(overflow)
    );

    //---- 修饰键状态 ----------------------------------------------------
    // 只识别左 Shift(12)、右 Shift(59)、左 Ctrl(14)，三者都是单个字节；
    // 键码为 E0 xx 的扩展键（右 Alt、右 Ctrl 等）不作处理
    reg  sh_l, sh_r;   // 左/右 Shift
    reg  ct_l;         // 左 Ctrl
    wire shift_down = sh_l | sh_r;
    wire ctrl_down  = ct_l;

    // LED0 = Shift 按住, LED1 = Ctrl 按住, LED2 = ready, LED3 = overflow
    assign LED[0] = shift_down;
    assign LED[1] = ctrl_down;
    assign LED[2] = ready;
    assign LED[3] = overflow;

    //---- 扫描码 -> ASCII 查找表 ----------------------------------------
    function [7:0] ascii_base;
        input [7:0] code;
        begin
            case (code)
                8'h45: ascii_base = 8'h30; // 0
                8'h16: ascii_base = 8'h31; // 1
                8'h1e: ascii_base = 8'h32; // 2
                8'h26: ascii_base = 8'h33; // 3
                8'h25: ascii_base = 8'h34; // 4
                8'h2e: ascii_base = 8'h35; // 5
                8'h36: ascii_base = 8'h36; // 6
                8'h3d: ascii_base = 8'h37; // 7
                8'h3e: ascii_base = 8'h38; // 8
                8'h46: ascii_base = 8'h39; // 9
                8'h1c: ascii_base = 8'h61; // a
                8'h32: ascii_base = 8'h62; // b
                8'h21: ascii_base = 8'h63; // c
                8'h23: ascii_base = 8'h64; // d
                8'h24: ascii_base = 8'h65; // e
                8'h2b: ascii_base = 8'h66; // f
                8'h34: ascii_base = 8'h67; // g
                8'h33: ascii_base = 8'h68; // h
                8'h43: ascii_base = 8'h69; // i
                8'h3b: ascii_base = 8'h6a; // j
                8'h42: ascii_base = 8'h6b; // k
                8'h4b: ascii_base = 8'h6c; // l
                8'h3a: ascii_base = 8'h6d; // m
                8'h31: ascii_base = 8'h6e; // n
                8'h44: ascii_base = 8'h6f; // o
                8'h4d: ascii_base = 8'h70; // p
                8'h15: ascii_base = 8'h71; // q
                8'h2d: ascii_base = 8'h72; // r
                8'h1b: ascii_base = 8'h73; // s
                8'h2c: ascii_base = 8'h74; // t
                8'h3c: ascii_base = 8'h75; // u
                8'h2a: ascii_base = 8'h76; // v
                8'h1d: ascii_base = 8'h77; // w
                8'h22: ascii_base = 8'h78; // x
                8'h35: ascii_base = 8'h79; // y
                8'h1a: ascii_base = 8'h7a; // z
                8'h29: ascii_base = 8'h20; // space
                8'h0d: ascii_base = 8'h20; // tab
                8'h5a: ascii_base = 8'h0d; // enter
                8'h66: ascii_base = 8'h08; // backspace
                8'h0e: ascii_base = 8'h60; // `
                8'h4e: ascii_base = 8'h2d; // -
                8'h55: ascii_base = 8'h3d; // =
                8'h54: ascii_base = 8'h5b; // [
                8'h5b: ascii_base = 8'h5d; // ]
                8'h5d: ascii_base = 8'h5c; // \
                8'h4c: ascii_base = 8'h3b; // ;
                8'h52: ascii_base = 8'h27; // '
                8'h41: ascii_base = 8'h2c; // ,
                8'h49: ascii_base = 8'h2e; // .
                8'h4a: ascii_base = 8'h2f; // /
                default: ascii_base = 8'h00;
            endcase
        end
    endfunction

    // 按住 Shift 时的 ASCII：字母转大写，数字与符号键转为上档字符
    function [7:0] ascii_shift;
        input [7:0] code;
        begin
            case (code)
                8'h16: ascii_shift = 8'h21; // 1 -> !
                8'h1e: ascii_shift = 8'h40; // 2 -> @
                8'h26: ascii_shift = 8'h23; // 3 -> #
                8'h25: ascii_shift = 8'h24; // 4 -> $
                8'h2e: ascii_shift = 8'h25; // 5 -> %
                8'h36: ascii_shift = 8'h5e; // 6 -> ^
                8'h3d: ascii_shift = 8'h26; // 7 -> &
                8'h3e: ascii_shift = 8'h2a; // 8 -> *
                8'h46: ascii_shift = 8'h28; // 9 -> (
                8'h45: ascii_shift = 8'h29; // 0 -> )
                8'h0e: ascii_shift = 8'h7e; // ` -> ~
                8'h4e: ascii_shift = 8'h5f; // - -> _
                8'h55: ascii_shift = 8'h2b; // = -> +
                8'h54: ascii_shift = 8'h7b; // [ -> {
                8'h5b: ascii_shift = 8'h7d; // ] -> }
                8'h5d: ascii_shift = 8'h7c; // \ -> |
                8'h4c: ascii_shift = 8'h3a; // ; -> :
                8'h52: ascii_shift = 8'h22; // ' -> "
                8'h41: ascii_shift = 8'h3c; // , -> <
                8'h49: ascii_shift = 8'h3e; // . -> >
                8'h4a: ascii_shift = 8'h3f; // / -> ?
                // a~z 的小写 ASCII 减 0x20 即大写
                8'h1c, 8'h32, 8'h21, 8'h23, 8'h24, 8'h2b, 8'h34, 8'h33,
                8'h43, 8'h3b, 8'h42, 8'h4b, 8'h3a, 8'h31, 8'h44, 8'h4d,
                8'h15, 8'h2d, 8'h1b, 8'h2c, 8'h3c, 8'h2a, 8'h1d, 8'h22,
                8'h35, 8'h1a:
                    ascii_shift = ascii_base(code) - 8'h20;
                default: ascii_shift = ascii_base(code);
            endcase
        end
    endfunction

    function [7:0] ascii_of;
        input [7:0] code;
        input       shifted;
        begin
            if (shifted)
                ascii_of = ascii_shift(code);
            else
                ascii_of = ascii_base(code);
        end
    endfunction

    //---- 扫描码解析状态机 ----------------------------------------------
    localparam S_IDLE  = 1'b0;  // 等待通码
    localparam S_BREAK = 1'b1;  // 刚收到 F0，下一字节为断码

    reg        held;
    reg [7:0]  keycode;
    reg        state;
    reg [3:0]  bcd_u, bcd_t;

    always @(posedge CLK100MHZ) begin
        nextdata_n <= 1'b1;
        if (BTNC) begin
            state     <= S_IDLE;
            held      <= 1'b0;
            keycode   <= 8'h00;
            sh_l      <= 1'b0;
            sh_r      <= 1'b0;
            ct_l      <= 1'b0;
            bcd_u     <= 4'd0;
            bcd_t     <= 4'd0;
        end else if (ready && nextdata_n) begin
            nextdata_n <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (rx == 8'hf0) begin
                        state <= S_BREAK;
                    end else if (rx == 8'h12) begin
                        sh_l <= 1'b1;
                    end else if (rx == 8'h59) begin
                        sh_r <= 1'b1;
                    end else if (rx == 8'h14) begin
                        ct_l <= 1'b1;
                    end else if (!held) begin
                        keycode <= rx;
                        held    <= 1'b1;
                        if (bcd_u == 4'd9) begin
                            bcd_u <= 4'd0;
                            if (bcd_t == 4'd9)
                                bcd_t <= 4'd0;
                            else
                                bcd_t <= bcd_t + 1'b1;
                        end else begin
                            bcd_u <= bcd_u + 1'b1;
                        end
                    end
                end

                S_BREAK: begin
                    state <= S_IDLE;
                    if (rx == 8'h12)
                        sh_l <= 1'b0;
                    else if (rx == 8'h59)
                        sh_r <= 1'b0;
                    else if (rx == 8'h14)
                        ct_l <= 1'b0;
                    else begin
                        // 普通按键松开
                        held    <= 1'b0;
                        keycode <= 8'h00;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ASCII 随键码与 Shift 状态实时变化
    wire [7:0] ascii = ascii_of(keycode, shift_down);

    reg [14:0] scan_cnt;
    reg [2:0]  sel;
    initial begin
        scan_cnt = 15'd0;
        sel      = 3'd0;
    end
    always @(posedge CLK100MHZ) begin
        if (scan_cnt == SCAN_MAX) begin
            scan_cnt <= 15'd0;
            sel      <= sel + 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    reg [3:0] digit;
    reg       blank;
    always @(*) begin
        blank = 1'b0;
        case (sel)
            3'd0: digit = keycode[3:0];
            3'd1: digit = keycode[7:4];
            3'd2: digit = ascii[3:0];
            3'd3: digit = ascii[7:4];
            3'd4: begin digit = 4'h0; blank = 1'b1; end
            3'd5: begin digit = 4'h0; blank = 1'b1; end
            3'd6: digit = bcd_u;
            3'd7: digit = bcd_t;
            default: begin digit = 4'h0; blank = 1'b1; end
        endcase
    end

    reg [7:0] an_sel;
    always @(*) begin
        case (sel)
            3'd0: an_sel = 8'b11111110;
            3'd1: an_sel = 8'b11111101;
            3'd2: an_sel = 8'b11111011;
            3'd3: an_sel = 8'b11110111;
            3'd4: an_sel = 8'b11101111;
            3'd5: an_sel = 8'b11011111;
            3'd6: an_sel = 8'b10111111;
            3'd7: an_sel = 8'b01111111;
            default: an_sel = 8'b11111111;
        endcase
    end
    assign AN = an_sel;

    reg [6:0] seg;
    always @(*) begin
        if (blank || ((sel <= 3'd3) && !held))
            seg = 7'b1111111;
        else begin
            case (digit)
                4'd0:  seg = 7'b1000000;
                4'd1:  seg = 7'b1111001;
                4'd2:  seg = 7'b0100100;
                4'd3:  seg = 7'b0110000;
                4'd4:  seg = 7'b0011001;
                4'd5:  seg = 7'b0010010;
                4'd6:  seg = 7'b0000010;
                4'd7:  seg = 7'b1111000;
                4'd8:  seg = 7'b0000000;
                4'd9:  seg = 7'b0010000;
                4'd10: seg = 7'b0001000;
                4'd11: seg = 7'b0000011;
                4'd12: seg = 7'b1000110;
                4'd13: seg = 7'b0100001;
                4'd14: seg = 7'b0000110;
                4'd15: seg = 7'b0001110;
                default: seg = 7'b1111111;
            endcase
        end
    end

    assign HEX = {seg, 1'b1};

endmodule


module ps2_keyboard(
    input        clk,
    input        clrn,
    input        ps2_clk,
    input        ps2_data,
    input        nextdata_n,
    output [7:0] data,
    output reg   ready,
    output reg   overflow
);

    reg [9:0] buffer;
    reg [7:0] fifo[7:0];
    reg [2:0] w_ptr, r_ptr;
    reg [3:0] count;
    reg [2:0] ps2_clk_sync;

    always @(posedge clk)
        ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};

    wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

    always @(posedge clk) begin
        if (clrn == 0) begin
            count <= 0;
            w_ptr <= 0;
            r_ptr <= 0;
            overflow <= 0;
            ready <= 0;
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

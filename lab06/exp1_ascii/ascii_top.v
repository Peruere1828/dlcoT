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


module ascii_top #(
    parameter integer SCAN_MAX = 25000
)(
    input        CLK100MHZ,
    input        PS2_CLK,
    input        PS2_DATA,
    input        BTNC,
    output [7:0] AN,
    output [7:0] HEX,
    output [1:0] LED
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

    assign LED[0] = ready;
    assign LED[1] = overflow;

    function [7:0] ascii_of;
        input [7:0] code;
        begin
            case (code)
                8'h45: ascii_of = 8'h30;
                8'h16: ascii_of = 8'h31;
                8'h1e: ascii_of = 8'h32;
                8'h26: ascii_of = 8'h33;
                8'h25: ascii_of = 8'h34;
                8'h2e: ascii_of = 8'h35;
                8'h36: ascii_of = 8'h36;
                8'h3d: ascii_of = 8'h37;
                8'h3e: ascii_of = 8'h38;
                8'h46: ascii_of = 8'h39;
                8'h1c: ascii_of = 8'h41;
                8'h32: ascii_of = 8'h42;
                8'h21: ascii_of = 8'h43;
                8'h23: ascii_of = 8'h44;
                8'h24: ascii_of = 8'h45;
                8'h2b: ascii_of = 8'h46;
                8'h34: ascii_of = 8'h47;
                8'h33: ascii_of = 8'h48;
                8'h43: ascii_of = 8'h49;
                8'h3b: ascii_of = 8'h4a;
                8'h42: ascii_of = 8'h4b;
                8'h4b: ascii_of = 8'h4c;
                8'h3a: ascii_of = 8'h4d;
                8'h31: ascii_of = 8'h4e;
                8'h44: ascii_of = 8'h4f;
                8'h4d: ascii_of = 8'h50;
                8'h15: ascii_of = 8'h51;
                8'h2d: ascii_of = 8'h52;
                8'h1b: ascii_of = 8'h53;
                8'h2c: ascii_of = 8'h54;
                8'h3c: ascii_of = 8'h55;
                8'h2a: ascii_of = 8'h56;
                8'h1d: ascii_of = 8'h57;
                8'h22: ascii_of = 8'h58;
                8'h35: ascii_of = 8'h59;
                8'h1a: ascii_of = 8'h5a;
                8'h29: ascii_of = 8'h20;
                8'h4e: ascii_of = 8'h2d;
                8'h55: ascii_of = 8'h3d;
                8'h54: ascii_of = 8'h5b;
                8'h5b: ascii_of = 8'h5d;
                8'h5d: ascii_of = 8'h5c;
                8'h4c: ascii_of = 8'h3b;
                8'h52: ascii_of = 8'h27;
                8'h0e: ascii_of = 8'h60;
                8'h41: ascii_of = 8'h2c;
                8'h49: ascii_of = 8'h2e;
                8'h4a: ascii_of = 8'h2f;
                8'h5a: ascii_of = 8'h0d;
                8'h66: ascii_of = 8'h08;
                8'h0d: ascii_of = 8'h09;
                8'h76: ascii_of = 8'h1b;
                default: ascii_of = 8'h00;
            endcase
        end
    endfunction

    localparam S_IDLE  = 1'b0;
    localparam S_BREAK = 1'b1;

    reg        state;
    reg        held;
    reg [7:0]  keycode;
    reg [7:0]  ascii;
    reg [3:0]  bcd_u, bcd_t;

    always @(posedge CLK100MHZ) begin
        nextdata_n <= 1'b1;
        if (BTNC) begin
            state     <= S_IDLE;
            held      <= 1'b0;
            keycode   <= 8'h00;
            ascii     <= 8'h00;
            bcd_u     <= 4'd0;
            bcd_t     <= 4'd0;
            nextdata_n <= 1'b1;
        end else if (ready && nextdata_n) begin
            nextdata_n <= 1'b0;
            if (rx == 8'hf0) begin
                state <= S_BREAK;
            end else if (state == S_BREAK) begin
                state <= S_IDLE;
                held  <= 1'b0;
            end else begin
                if (!held) begin
                    keycode <= rx;
                    ascii   <= ascii_of(rx);
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
        end
    end

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

    reg [7:0] AN;
    always @(*) begin
        case (sel)
            3'd0: AN = 8'b11111110;
            3'd1: AN = 8'b11111101;
            3'd2: AN = 8'b11111011;
            3'd3: AN = 8'b11110111;
            3'd4: AN = 8'b11101111;
            3'd5: AN = 8'b11011111;
            3'd6: AN = 8'b10111111;
            3'd7: AN = 8'b01111111;
            default: AN = 8'b11111111;
        endcase
    end

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

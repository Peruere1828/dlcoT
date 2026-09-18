module lfsr_top #(
    parameter integer DB_MAX   = 100000,
    parameter integer SCAN_MAX = 25000
)(
    input        CLK100MHZ,
    input        SW0,
    input        BTNC,
    output [7:0] AN,
    output [7:0] HEX,
    output [7:0] LED
);

    reg [25:0] db_cnt;
    reg [1:0]  db_sample;
    reg        btn_d;
    reg        btn_clk;
    reg        btn_clk_d;
    initial begin
        db_cnt    = 26'd0;
        db_sample = 2'b00;
        btn_d     = 1'b0;
        btn_clk   = 1'b0;
        btn_clk_d = 1'b0;
    end

    always @(posedge CLK100MHZ) begin
        btn_d <= BTNC;
        if (db_cnt == DB_MAX) begin
            db_cnt    <= 26'd0;
            db_sample <= {db_sample[0], btn_d};
            if (db_sample == 2'b11)
                btn_clk <= 1'b1;
            else if (db_sample == 2'b00)
                btn_clk <= 1'b0;
        end else begin
            db_cnt <= db_cnt + 1'b1;
        end
    end

    always @(posedge CLK100MHZ)
        btn_clk_d <= btn_clk;
    wire lfsr_en = btn_clk & ~btn_clk_d;

    reg  [7:0] state;
    wire       feedback = state[4] ^ state[3] ^ state[2] ^ state[0];
    initial state = 8'h01;
    always @(posedge CLK100MHZ) begin
        if (SW0)
            state <= 8'h01;
        else if (lfsr_en) begin
            if (state == 8'h00)
                state <= 8'h01;
            else
                state <= {feedback, state[7:1]};
        end
    end

    assign LED = state;

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
    always @(*) begin
        case (sel)
            3'd0: digit = state[3:0];
            3'd1: digit = state[7:4];
            default: digit = 4'hf;
        endcase
    end

    reg [7:0] AN;
    always @(*) begin
        case (sel)
            3'd0: AN = 8'b11111110;
            3'd1: AN = 8'b11111101;
            default: AN = 8'b11111111;
        endcase
    end

    reg [6:0] seg;
    always @(*) begin
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

    assign HEX = {seg, 1'b1};

endmodule

module timer_top #(
    parameter integer CNT_HALF = 49999999,
    parameter integer DB_MAX   = 100000,
    parameter integer SCAN_MAX = 500
)(
    input  CLK100MHZ,
    input  BTNC,
    input  BTNL,
    output LED0,
    output [7:0] AN,
    output [7:0] HEX
);

    wire btnc_press, btnl_press;

    debounce_pulse #(DB_MAX) u_db_c(
        .clk(CLK100MHZ),
        .btn(BTNC),
        .pulse(btnc_press)
    );

    debounce_pulse #(DB_MAX) u_db_l(
        .clk(CLK100MHZ),
        .btn(BTNL),
        .pulse(btnl_press)
    );

    reg [25:0] clk_cnt;
    reg        clk_1s;
    initial begin
        clk_cnt = 26'd0;
        clk_1s  = 1'b0;
    end
    always @(posedge CLK100MHZ) begin
        if (clk_cnt == CNT_HALF) begin
            clk_cnt <= 26'd0;
            clk_1s  <= ~clk_1s;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end

    reg  clk_1s_d;
    wire tick = clk_1s & ~clk_1s_d;
    initial clk_1s_d = 1'b0;
    always @(posedge CLK100MHZ)
    clk_1s_d <= clk_1s;

    reg        running;
    reg [3:0]  sec_ones;
    reg [3:0]  sec_tens;
    reg        done;
    initial begin
        running  = 1'b0;
        sec_ones = 4'd0;
        sec_tens = 4'd0;
        done     = 1'b0;
    end
    always @(posedge CLK100MHZ) begin
        if (btnl_press) begin
            running  <= 1'b0;
            sec_ones <= 4'd0;
            sec_tens <= 4'd0;
            done     <= 1'b0;
        end else if (btnc_press) begin
            running  <= ~running;
        end else if (running & tick) begin
            if (sec_ones == 4'd9) begin
                sec_ones <= 4'd0;
                if (sec_tens == 4'd5) begin
                    sec_tens <= 4'd0;
                    done     <= 1'b1;
                end else begin
                    sec_tens <= sec_tens + 1'b1;
                    done     <= 1'b0;
                end
            end else begin
                sec_ones <= sec_ones + 1'b1;
                done     <= 1'b0;
            end
        end
    end

    assign LED0 = done;

    reg [9:0] scan_cnt;
    reg       sel;
    initial begin
        scan_cnt = 10'd0;
        sel      = 1'b0;
    end
    always @(posedge CLK100MHZ) begin
        if (scan_cnt == SCAN_MAX) begin
            scan_cnt <= 10'd0;
            sel      <= ~sel;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    reg [7:0] AN;
    reg [6:0] seg;

    always @(*) begin
        if (sel) begin
            AN = 8'b1111_1101;
            case (sec_tens)
                4'd0: seg = 7'b1000000;
                4'd1: seg = 7'b1111001;
                4'd2: seg = 7'b0100100;
                4'd3: seg = 7'b0110000;
                4'd4: seg = 7'b0011001;
                4'd5: seg = 7'b0010010;
                4'd6: seg = 7'b0000010;
                4'd7: seg = 7'b1111000;
                4'd8: seg = 7'b0000000;
                4'd9: seg = 7'b0010000;
                default: seg = 7'b1111111;
            endcase
        end else begin
            AN = 8'b1111_1110;
            case (sec_ones)
                4'd0: seg = 7'b1000000;
                4'd1: seg = 7'b1111001;
                4'd2: seg = 7'b0100100;
                4'd3: seg = 7'b0110000;
                4'd4: seg = 7'b0011001;
                4'd5: seg = 7'b0010010;
                4'd6: seg = 7'b0000010;
                4'd7: seg = 7'b1111000;
                4'd8: seg = 7'b0000000;
                4'd9: seg = 7'b0010000;
                default: seg = 7'b1111111;
            endcase
        end
    end

    assign HEX = {seg, 1'b1};

endmodule

module debounce_pulse #(
    parameter integer DB_MAX = 100000
)(
    input  clk,
    input  btn,
    output reg pulse
);

    reg [25:0] cnt;
    reg [1:0]  sample;
    reg        stable;
    reg        stable_d;
    initial begin
        cnt      = 26'd0;
        sample   = 2'b00;
        stable   = 1'b0;
        stable_d = 1'b0;
    end

    always @(posedge clk) begin
        if (cnt == DB_MAX) begin
            cnt    <= 26'd0;
            sample <= {sample[0], btn};
            if (sample == 2'b11)
                stable <= 1'b1;
            else if (sample == 2'b00)
                stable <= 1'b0;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        stable_d <= stable;
        pulse    <= stable & ~stable_d;
    end

endmodule
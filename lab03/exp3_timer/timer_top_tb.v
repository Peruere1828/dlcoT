`timescale 1ns / 1ps

module timer_top_tb;

    reg  clk = 0;
    reg  BTNC = 0;
    reg  BTNL = 0;
    wire LED0;
    wire [7:0] AN;
    wire [7:0] HEX;

    integer err_cnt = 0;
    integer hi_cnt;
    reg [3:0] d;

    timer_top #(
    .CNT_HALF(1),
    .DB_MAX(4),
    .SCAN_MAX(1)
    ) u_dut(
        .CLK100MHZ(clk),
        .BTNC(BTNC),
        .BTNL(BTNL),
        .LED0(LED0),
        .AN(AN),
        .HEX(HEX)
    );

    always #5 clk = ~clk;

    task seg_to_digit;
        input [6:0] seg;
        output reg [3:0] digit;
        begin
            case (seg)
                7'b1000000: digit = 4'd0;
                7'b1111001: digit = 4'd1;
                7'b0100100: digit = 4'd2;
                7'b0110000: digit = 4'd3;
                7'b0011001: digit = 4'd4;
                7'b0010010: digit = 4'd5;
                7'b0000010: digit = 4'd6;
                7'b1111000: digit = 4'd7;
                7'b0000000: digit = 4'd8;
                7'b0010000: digit = 4'd9;
                default:    digit = 4'hF;
            endcase
        end
    endtask

    task press;
        input [1:0] btn;
        begin
            if (btn == 2'd0)
                BTNC = 1;
            else
                BTNL = 1;
            #250;
            if (btn == 2'd0)
                BTNC = 0;
            else
                BTNL = 0;
            #250;
        end
    endtask

    task check_disp;
        input [3:0] exp_tens;
        input [3:0] exp_ones;
        input integer ncyc;
        integer i;
        reg [3:0] d;
        begin
            for (i = 0; i < ncyc; i = i + 1) begin
                @(posedge clk);
                #1;
                if (AN === 8'b1111_1110) begin
                    seg_to_digit(HEX[7:1], d);
                    if (d !== exp_ones) begin
                        err_cnt = err_cnt + 1;
                        $display("FAIL: ones phase shows %d (expected %d) at %0t", d, exp_ones, $time);
                    end
                end else if (AN === 8'b1111_1101) begin
                    seg_to_digit(HEX[7:1], d);
                    if (d !== exp_tens) begin
                        err_cnt = err_cnt + 1;
                        $display("FAIL: tens phase shows %d (expected %d) at %0t", d, exp_tens, $time);
                    end
                end else begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL: unexpected AN=%b at %0t", AN, $time);
                end
            end
        end
    endtask

    task check_counting;
        input integer ncyc;
        integer i;
        reg [3:0] d;
        reg started;
        reg [3:0] prev;
        begin
            started = 1'b0;
            for (i = 0; i < ncyc; i = i + 1) begin
                @(posedge clk);
                #1;
                if (AN === 8'b1111_1110) begin
                    seg_to_digit(HEX[7:1], d);
                    if (started == 1'b0) begin
                        started = 1'b1;
                        prev = d;
                    end else if (d !== prev) begin
                        if (d == ((prev + 1) % 10)) begin
                            prev = d;
                        end else begin
                            err_cnt = err_cnt + 1;
                            $display("FAIL: ones digit jumped %d -> %d at %0t", prev, d, $time);
                            prev = d;
                        end
                    end
                end
            end
        end
    endtask

    task check_stable;
        input integer ncyc;
        integer i;
        reg [3:0] d;
        reg seen_ones, seen_tens;
        reg [3:0] last_ones, last_tens;
        begin
            seen_ones = 1'b0;
            seen_tens = 1'b0;
            for (i = 0; i < ncyc; i = i + 1) begin
                @(posedge clk);
                #1;
                if (AN === 8'b1111_1110) begin
                    seg_to_digit(HEX[7:1], d);
                    if (seen_ones == 1'b0) begin
                        seen_ones = 1'b1;
                        last_ones = d;
                    end else if (d !== last_ones) begin
                        err_cnt = err_cnt + 1;
                        $display("FAIL: ones changed %d -> %d while paused at %0t", last_ones, d, $time);
                        last_ones = d;
                    end
                end else if (AN === 8'b1111_1101) begin
                    seg_to_digit(HEX[7:1], d);
                    if (seen_tens == 1'b0) begin
                        seen_tens = 1'b1;
                        last_tens = d;
                    end else if (d !== last_tens) begin
                        err_cnt = err_cnt + 1;
                        $display("FAIL: tens changed %d -> %d while paused at %0t", last_tens, d, $time);
                        last_tens = d;
                    end
                end
            end
        end
    endtask

    initial begin
        err_cnt = 0;

        press(2'd1);
        if (LED0 !== 1'b0) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: LED0 not 0 after clear at %0t", $time);
        end
        check_disp(4'd0, 4'd0, 6);

        press(2'd0);
        check_counting(40);
        if (LED0 !== 1'b0) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: LED0 high during counting at %0t", $time);
        end

        press(2'd0);
        check_stable(24);

        press(2'd0);
        check_counting(24);

        wait (LED0 === 1'b1);
        hi_cnt = 0;
        while (LED0 === 1'b1) begin
            hi_cnt = hi_cnt + 1;
            @(posedge clk);
            #1;
            if (LED0 === 1'b1) begin
                seg_to_digit(HEX[7:1], d);
                if (AN === 8'b1111_1110 || AN === 8'b1111_1101) begin
                    if (d !== 4'd0) begin
                        err_cnt = err_cnt + 1;
                        $display("FAIL: wrap display shows %d (expected 0) at %0t", d, $time);
                    end
                end
            end
        end
        if (hi_cnt !== 4) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: LED0 high for %0d cycles (expected 4)", hi_cnt);
        end

        press(2'd1);
        if (LED0 !== 1'b0) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: LED0 not 0 after second clear at %0t", $time);
        end
        check_disp(4'd0, 4'd0, 6);

        if (err_cnt == 0)
            $display("TEST PASSED: timer_top");
        else
            $display("TEST FAILED: %0d errors", err_cnt);
        $finish;
    end

endmodule
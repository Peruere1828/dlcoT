`timescale 1ns / 1ps

module alu_top_tb;

    reg  [10:0] SW;
    wire [2:0]  LED;
    wire [7:0]  AN;
    wire [7:0]  HEX;

    integer err_cnt;
    reg [6:0] exp_seg;
    reg exp_cf, exp_of, exp_zero;

    lab02_top u_dut(
        .SW(SW),
        .LED(LED),
        .AN(AN),
        .HEX(HEX)
    );

    task run_case;
        input [10:0] sw;
        input [3:0]  f;
        input        exp_cf_i, exp_of_i, exp_zero_i;
        begin
            SW = sw;
            case (f)
                4'h0: exp_seg = 7'b1000000;
                4'h1: exp_seg = 7'b1111001;
                4'h2: exp_seg = 7'b0100100;
                4'h3: exp_seg = 7'b0110000;
                4'h4: exp_seg = 7'b0011001;
                4'h5: exp_seg = 7'b0010010;
                4'h6: exp_seg = 7'b0000010;
                4'h7: exp_seg = 7'b1111000;
                4'h8: exp_seg = 7'b0000000;
                4'h9: exp_seg = 7'b0010000;
                4'hA: exp_seg = 7'b0001000;
                4'hB: exp_seg = 7'b0000011;
                4'hC: exp_seg = 7'b1000110;
                4'hD: exp_seg = 7'b0100001;
                4'hE: exp_seg = 7'b0000110;
                default: exp_seg = 7'b0001110;
            endcase
            exp_cf   = exp_cf_i;
            exp_of   = exp_of_i;
            exp_zero = exp_zero_i;
            #10;
            if ((AN !== 8'b11111110) ||
                (HEX !== {exp_seg, 1'b1}) ||
                (LED[0] !== exp_cf) || (LED[1] !== exp_of) || (LED[2] !== exp_zero)) begin
                err_cnt = err_cnt + 1;
                $display("FAIL: SW=%b LED=%b AN=%b HEX=%b (expected LED=%b HEX=%b)",
                         SW, LED, AN, HEX, {exp_zero, exp_of, exp_cf}, {exp_seg, 1'b1});
            end
        end
    endtask

    initial begin
        err_cnt = 0;

        run_case({3'b000, 4'd5, 4'd3}, 4'h8, 0, 1, 0);
        run_case({3'b000, 4'd1, 4'd7}, 4'h8, 0, 1, 0);
        run_case({3'b000, 4'd8, 4'd8}, 4'h0, 1, 1, 1);
        run_case({3'b001, 4'd5, 4'd5}, 4'h0, 0, 0, 1);
        run_case({3'b001, 4'd7, 4'd8}, 4'h1, 0, 1, 0);
        run_case({3'b001, 4'd8, 4'd8}, 4'h0, 0, 0, 1);
        run_case({3'b010, 4'd0, 4'd5}, 4'hA, 0, 0, 0);
        run_case({3'b011, 4'd3, 4'd10}, 4'h2, 0, 0, 0);
        run_case({3'b100, 4'd3, 4'd10}, 4'hB, 0, 0, 0);
        run_case({3'b101, 4'd3, 4'd10}, 4'h9, 0, 0, 0);
        run_case({3'b110, 4'd5, 4'd2}, 4'h1, 0, 0, 0);
        run_case({3'b110, 4'd2, 4'd5}, 4'h0, 0, 0, 1);
        run_case({3'b110, 4'd7, 4'd8}, 4'h1, 0, 0, 0);
        run_case({3'b111, 4'd5, 4'd5}, 4'h1, 0, 0, 0);
        run_case({3'b111, 4'd6, 4'd5}, 4'h0, 0, 0, 1);

        if (err_cnt == 0)
            $display("TEST PASSED: lab02_top");
        else
            $display("TEST FAILED: %0d errors", err_cnt);
        $finish;
    end

endmodule

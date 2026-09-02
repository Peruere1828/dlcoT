`timescale 1ns / 1ps

module exp2_priority83_top_tb;

    reg  [8:0] SW;
    wire [4:0] LED;
    wire [7:0] AN;
    wire [7:0] HEX;

    integer err_cnt;
    reg exp_valid;
    reg [2:0] exp_code;
    reg [6:0] exp_seg;

    exp2_priority83_top u_dut(
        .SW(SW),
        .LED(LED),
        .AN(AN),
        .HEX(HEX)
    );

    task check;
        begin
            #10;
            case (exp_code)
                3'd0: exp_seg = 7'b1000000;
                3'd1: exp_seg = 7'b1111001;
                3'd2: exp_seg = 7'b0100100;
                3'd3: exp_seg = 7'b0110000;
                3'd4: exp_seg = 7'b0011001;
                3'd5: exp_seg = 7'b0010010;
                3'd6: exp_seg = 7'b0000010;
                default: exp_seg = 7'b1111000;
            endcase
            if (AN !== 8'b11111110) begin
                err_cnt = err_cnt + 1;
                $display("FAIL: AN=%b expected 8'b11111110", AN);
            end
            if ((LED[2:0] !== exp_code) || (LED[3] !== 1'b0) || (LED[4] !== exp_valid) ||
                (HEX !== {exp_seg, 1'b1})) begin
                err_cnt = err_cnt + 1;
                $display("FAIL: SW=%b LED=%b HEX=%b (expected code=%b valid=%b HEX=%b)",
                         SW, LED, HEX, exp_code, exp_valid, {exp_seg, 1'b1});
            end
        end
    endtask

    initial begin
        err_cnt = 0;

        SW = 9'b0_1111_1111; exp_code = 3'b000; exp_valid = 1'b0; check;
        SW = 9'b1_0000_0000; exp_code = 3'b000; exp_valid = 1'b0; check;

        SW = 9'b1_0000_0001; exp_code = 3'd0; exp_valid = 1'b1; check;
        SW = 9'b1_0001_0000; exp_code = 3'd4; exp_valid = 1'b1; check;
        SW = 9'b1_0100_0000; exp_code = 3'd6; exp_valid = 1'b1; check;
        SW = 9'b1_1000_0000; exp_code = 3'd7; exp_valid = 1'b1; check;

        SW = 9'b1_0000_1110; exp_code = 3'd3; exp_valid = 1'b1; check;
        SW = 9'b1_1000_0101; exp_code = 3'd7; exp_valid = 1'b1; check;
        SW = 9'b1_0010_0010; exp_code = 3'd5; exp_valid = 1'b1; check;

        if (err_cnt == 0)
            $display("TEST PASSED: exp2_priority83_top");
        else
            $display("TEST FAILED: %0d errors", err_cnt);
        $finish;
    end

endmodule

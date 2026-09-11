`timescale 1ns / 1ps

module mem_top_tb;

    reg        CLK100MHZ;
    reg  [9:0] SW;
    reg        BTNC;
    wire       LED0, LED1;
    wire [7:0] AN, HEX;

    mem_top #(
    .DB_MAX(2),
    .SCAN_MAX(1)
    ) uut (
        .CLK100MHZ(CLK100MHZ),
        .SW(SW),
        .BTNC(BTNC),
        .LED0(LED0),
        .LED1(LED1),
        .AN(AN),
        .HEX(HEX)
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
            4'd14: hex2seg = 7'b0001100;
            4'd15: hex2seg = 7'b0001110;
            default: hex2seg = 7'b1111111;
        endcase
    endfunction

    task clk_pulse;
        begin
            BTNC = 1'b1;
            repeat (30) @(posedge CLK100MHZ);
            BTNC = 1'b0;
            repeat (30) @(posedge CLK100MHZ);
        end
    endtask

    task check_digit;
        input [7:0] an_sel;
        input [3:0] val;
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
            end else if (HEX !== {hex2seg(val), 1'b1}) begin
                $display("MISMATCH: AN=%b HEX=%b expected %b", AN, HEX, {hex2seg(val), 1'b1});
                errors = errors + 1;
            end
        end
    endtask

    task check_all;
        input [3:0] rf_lo;
        input [3:0] rf_hi;
        input [3:0] ram_lo;
        input [3:0] ram_hi;
        begin
            check_digit(8'b11111110, rf_lo);
            check_digit(8'b11111101, rf_hi);
            check_digit(8'b11111011, ram_lo);
            check_digit(8'b11110111, ram_hi);
        end
    endtask

    initial begin
        CLK100MHZ = 1'b0;
        SW   = 10'b0;
        BTNC = 1'b0;
        errors = 0;
        #20;

        SW[3:0] = 4'h0;
        clk_pulse;
        check_all(4'h0, 4'h0, 4'h0, 4'hf);

        SW[3:0] = 4'h5;
        clk_pulse;
        check_all(4'h5, 4'h0, 4'h5, 4'hf);

        SW[3:0] = 4'h7;
        SW[7:4] = 4'h3;
        SW[8]   = 1'b1;
        clk_pulse;
        SW[8]   = 1'b0;
        clk_pulse;
        check_all(4'h3, 4'h0, 4'h7, 4'hf);

        SW[9]   = 1'b1;
        SW[7:4] = 4'ha;
        clk_pulse;
        SW[9]   = 1'b0;
        clk_pulse;
        check_all(4'h3, 4'h0, 4'ha, 4'h0);

        SW[3:0] = 4'ha;
        SW[7:4] = 4'h0;
        clk_pulse;
        check_all(4'ha, 4'h0, 4'ha, 4'hf);

        SW[3:0] = 4'h7;
        clk_pulse;
        check_all(4'h3, 4'h0, 4'ha, 4'h0);

        SW[3:0] = 4'hf;
        clk_pulse;
        check_all(4'hf, 4'h0, 4'hf, 4'hf);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

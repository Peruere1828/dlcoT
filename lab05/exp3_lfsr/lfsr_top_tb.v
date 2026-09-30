`timescale 1ns / 1ps

module lfsr_top_tb;

    reg        CLK100MHZ;
    reg        SW0;
    reg        BTNC;
    wire [7:0] AN, HEX;

    lfsr_top #(
        .DB_MAX(2),
        .SCAN_MAX(1)
    ) uut (
        .CLK100MHZ(CLK100MHZ),
        .SW0(SW0),
        .BTNC(BTNC),
        .AN(AN),
        .HEX(HEX)
    );

    initial CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    integer errors;

    function [7:0] lfsr_next;
        input [7:0] s;
        begin
            lfsr_next = { s[4] ^ s[3] ^ s[2] ^ s[0], s[7:1] };
        end
    endfunction

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

    task press_btn;
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

    task check_value;
        input [7:0] exp;
        begin
            check_digit(8'b11111110, exp[3:0]);
            check_digit(8'b11111101, exp[7:4]);
        end
    endtask

    integer i;
    reg [7:0] ref;

    initial begin
        CLK100MHZ = 1'b0;
        SW0  = 1'b0;
        BTNC = 1'b0;
        errors = 0;
        #20;

        SW0 = 1'b1;
        repeat (5) @(posedge CLK100MHZ);
        SW0 = 1'b0;
        ref = 8'h01;
        check_value(ref);

        for (i = 0; i < 12; i = i + 1) begin
            press_btn;
            ref = lfsr_next(ref);
            check_value(ref);
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

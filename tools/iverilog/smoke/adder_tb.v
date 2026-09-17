`timescale 1ns / 1ps
// 冒烟测试: 验证 docker+iverilog 链路可用
module adder_tb;
    reg  [3:0] a, b;
    reg        cin;
    wire [3:0] sum;
    wire       cout;

    integer errors;

    adder uut (
        .a(a), .b(b), .cin(cin),
        .sum(sum), .cout(cout)
    );

    task check;
        input [3:0] ea;
        input [3:0] eb;
        input       ecin;
        input [4:0] expected;
        begin
            a = ea; b = eb; cin = ecin;
            #1;
            if ({cout, sum} !== expected) begin
                $display("MISMATCH: %0d+%0d+%0d = %0d expected %0d",
                         ea, eb, ecin, {cout, sum}, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check(4'd0,  4'd0,  1'b0, 5'd0);
        check(4'd3,  4'd4,  1'b0, 5'd7);
        check(4'd15, 4'd1,  1'b0, 5'd16);
        check(4'd15, 4'd15, 1'b1, 5'd31);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end
endmodule

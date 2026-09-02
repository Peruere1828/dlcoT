`timescale 1ns / 1ps

module exp1_mux4to1_tb;

    reg  [1:0] X0, X1, X2, X3;
    reg  [1:0] Y;
    wire [1:0] F;

    reg  [1:0] data [0:3];
    reg  [1:0] exp;
    integer i, j, err_cnt;

    mux4to1 u_dut(
        .X0(X0), .X1(X1), .X2(X2), .X3(X3),
        .Y(Y),
        .F(F)
    );

    task check;
        begin
            #10;
            case (Y)
                2'b00:   exp = X0;
                2'b01:   exp = X1;
                2'b10:   exp = X2;
                default: exp = X3;
            endcase
            if (F !== exp) begin
                err_cnt = err_cnt + 1;
                $display("FAIL: Y=%b F=%b expected=%b", Y, F, exp);
            end
        end
    endtask

    initial begin
        err_cnt = 0;

        for (j = 0; j < 2; j = j + 1) begin
            case (j)
                0:      begin data[0] = 2'b00; data[1] = 2'b01; data[2] = 2'b10; data[3] = 2'b11; end
                default: begin data[0] = 2'b11; data[1] = 2'b10; data[2] = 2'b01; data[3] = 2'b00; end
            endcase
            X0 = data[0]; X1 = data[1]; X2 = data[2]; X3 = data[3];
            for (i = 0; i < 4; i = i + 1) begin
                Y = i[1:0];
                check;
            end
        end

        if (err_cnt == 0)
            $display("TEST PASSED: mux4to1");
        else
            $display("TEST FAILED: %0d errors", err_cnt);
        $finish;
    end

endmodule

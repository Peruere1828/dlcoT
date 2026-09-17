`timescale 1ns / 1ps
//=======================================================================
// lab09 exp2_alu 自检 testbench
// 覆盖 ALUctr 全表: 加减/左移/带符号与无符号小于/B直通/异或/
//                    逻辑与算术右移/或/与
// 以及 Zero / Less 标志
//=======================================================================
module alu_tb;

    reg  [31:0] A, B;
    reg  [3:0]  ALUctr;

    wire [31:0] Result;
    wire        Zero, Less;

    integer errors;

    alu uut (
        .A(A), .B(B), .ALUctr(ALUctr),
        .Result(Result), .Zero(Zero), .Less(Less)
    );

    task check;
        input [31:0] ea;
        input [31:0] eb;
        input [3:0]  ectr;
        input [31:0] exp_result;
        begin
            A = ea; B = eb; ALUctr = ectr;
            #1;
            if (Result !== exp_result) begin
                $display("MISMATCH: ctr=%b A=0x%08h B=0x%08h -> 0x%08h expected 0x%08h",
                         ectr, ea, eb, Result, exp_result);
                errors = errors + 1;
            end
        end
    endtask

    task check_flags;
        input [31:0] ea;
        input [31:0] eb;
        input [3:0]  ectr;
        input        exp_zero;
        input        exp_less;
        begin
            A = ea; B = eb; ALUctr = ectr;
            #1;
            if (Zero !== exp_zero) begin
                $display("MISMATCH: Zero A=0x%08h B=0x%08h = %b expected %b",
                         ea, eb, Zero, exp_zero);
                errors = errors + 1;
            end
            if (Less !== exp_less) begin
                $display("MISMATCH: Less ctr=%b A=0x%08h B=0x%08h = %b expected %b",
                         ectr, ea, eb, Less, exp_less);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        A = 32'b0; B = 32'b0; ALUctr = 4'b0;
        #1;

        //--- 加减 ---------------------------------------------------
        check(32'd5,  32'd3,  4'b0000, 32'd8);            // add
        check(32'd5,  32'd3,  4'b1000, 32'd2);            // sub
        check(32'd3,  32'd5,  4'b1000, 32'hffff_fffe);    // sub 借位 -2

        //--- 左移 (移位量取 B[4:0]) ---------------------------------
        check(32'h0000_0001, 32'd4,  4'b0001, 32'h0000_0010);
        check(32'h0000_0001, 32'd33, 4'b0001, 32'h0000_0002); // 33 -> 1
        check(32'h8000_0000, 32'd1,  4'b0001, 32'h0000_0000); // 移出

        //--- 带符号/无符号小于 --------------------------------------
        check(32'hffff_ffff, 32'h0000_0000, 4'b0010, 32'h0000_0001); // -1 < 0
        check(32'hffff_ffff, 32'h0000_0000, 4'b1010, 32'h0000_0000); // 0xFFFFFFFF < 0 无符号=0
        check(32'h0000_0002, 32'h0000_0001, 4'b0010, 32'h0000_0000); // 2 < 1 = 0
        check(32'h0000_0001, 32'h0000_0002, 4'b1010, 32'h0000_0001); // 1 < 2 无符号=1

        //--- B 直通 -------------------------------------------------
        check(32'h1234_5678, 32'h89ab_cdef, 4'b0011, 32'h89ab_cdef);

        //--- 异或/或/与 ---------------------------------------------
        check(32'hff00_ff00, 32'h0ff0_0ff0, 4'b0100, 32'hf0f0_f0f0);
        check(32'hff00_0000, 32'h00ff_0000, 4'b0110, 32'hffff_0000);
        check(32'hff00_ff00, 32'h0ff0_0ff0, 4'b0111, 32'h0f00_0f00);

        //--- 逻辑/算术右移 ------------------------------------------
        check(32'h8000_0000, 32'h0000_0004, 4'b0101, 32'h0800_0000);
        check(32'h8000_0000, 32'h0000_0004, 4'b1101, 32'hf800_0000);
        check(32'h7fff_ffff, 32'h0000_0004, 4'b1101, 32'h07ff_ffff);

        //--- Zero / Less 标志 ---------------------------------------
        check_flags(32'h0000_1234, 32'h0000_1234, 4'b0010, 1'b1, 1'b0); // 相等
        check_flags(32'h0000_0001, 32'h0000_0002, 4'b0010, 1'b0, 1'b1); // 有符号 1<2
        check_flags(32'hffff_fffe, 32'h0000_0001, 4'b0010, 1'b0, 1'b1); // -2<1
        check_flags(32'h0000_0001, 32'hffff_fffe, 4'b0010, 1'b0, 1'b0); // 1<-2 假
        check_flags(32'hffff_ffff, 32'h0000_0001, 4'b1010, 1'b0, 1'b0); // 无符号 max<1 假
        check_flags(32'h0000_0001, 32'hffff_ffff, 4'b1010, 1'b0, 1'b1); // 无符号 1<max

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

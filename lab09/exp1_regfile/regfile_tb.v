`timescale 1ns / 1ps
//=======================================================================
// lab09 exp1_regfile 自检 testbench
// 覆盖: 下降沿写入 / 非同步读出 / 双读端口 / RegWr 无效不写 /
//       x0 恒为 0 (即使被写)
//=======================================================================
module regfile_tb;

    reg         WrClk;
    reg         RegWr;
    reg  [4:0]  Ra, Rb, Rw;
    reg  [31:0] busW;

    wire [31:0] busA, busB;

    integer errors;

    regfile uut (
        .WrClk(WrClk),
        .RegWr(RegWr),
        .Ra(Ra), .Rb(Rb), .Rw(Rw),
        .busW(busW),
        .busA(busA), .busB(busB)
    );

    always #5 WrClk = ~WrClk;

    task write_reg;
        input [4:0]  r;
        input [31:0] w;
        input        en;
        begin
            Rw = r; busW = w; RegWr = en;
            // 写使能及数据在下降沿前稳定 -> 下降沿写入
            @(negedge WrClk);
            #1;
            RegWr = 1'b0;
        end
    endtask

    task check_read;
        input [4:0]  a;
        input [4:0]  b;
        input [31:0] exp_a;
        input [31:0] exp_b;
        begin
            Ra = a; Rb = b;
            #1;
            if (busA !== exp_a) begin
                $display("MISMATCH: busA(Ra=%0d)=0x%08h expected 0x%08h", a, busA, exp_a);
                errors = errors + 1;
            end
            if (busB !== exp_b) begin
                $display("MISMATCH: busB(Rb=%0d)=0x%08h expected 0x%08h", b, busB, exp_b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        WrClk = 1'b0;
        RegWr = 1'b0;
        Ra = 5'd0; Rb = 5'd0; Rw = 5'd0; busW = 32'b0;
        #2;

        //--- 初始全零 ------------------------------------------------
        check_read(5'd1, 5'd31, 32'h0, 32'h0);

        //--- 写入 x5, x7 并读回 -------------------------------------
        write_reg(5'd5, 32'h1234_5678, 1'b1);
        write_reg(5'd7, 32'hdead_beef, 1'b1);
        check_read(5'd5,  5'd7,  32'h1234_5678, 32'hdead_beef);
        check_read(5'd7,  5'd5,  32'hdead_beef, 32'h1234_5678);

        //--- RegWr=0 时不应写入 -------------------------------------
        write_reg(5'd5, 32'hffff_ffff, 1'b0);
        check_read(5'd5, 5'd0, 32'h1234_5678, 32'h0);

        //--- x0 写入无效, 读取恒零 ----------------------------------
        write_reg(5'd0, 32'hffff_ffff, 1'b1);
        check_read(5'd0, 5'd0, 32'h0, 32'h0);
        // x0 作目标寄存器, 源一样读零
        check_read(5'd0, 5'd5, 32'h0, 32'h1234_5678);

        //--- 覆盖写同一寄存器 ---------------------------------------
        write_reg(5'd7, 32'h0000_0001, 1'b1);
        check_read(5'd7, 5'd7, 32'h0000_0001, 32'h0000_0001);

        //--- 最高位寄存器 -------------------------------------------
        write_reg(5'd31, 32'h8000_0000, 1'b1);
        check_read(5'd31, 5'd7, 32'h8000_0000, 32'h0000_0001);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

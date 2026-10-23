`timescale 1ns / 1ps
//==============================================================================
// cpu_top_tb.v : lab09 上板顶层自检
//   把上电复位/自动运行分频/数码管扫描分频都缩小, 逐个程序跑完并检查结果.
//   期望值用公式即时计算, 与 CPU 的 RTL 实现无关.
//==============================================================================
module cpu_top_tb;

    reg         CLK100MHZ;
    reg         CPU_RESETN;
    reg         BTNC;
    reg  [15:0] SW;
    wire [7:0]  AN;
    wire [7:0]  HEX;
    wire [15:0] LED;

    integer errors;

    // 缩小各计数器, 让仿真在几十微秒内跑完
    cpu_top #(
        .POR_BITS (3),
        .DIV_BITS (1),
        .DB_BITS  (2),
        .SCAN_BITS(2)
    ) uut (
        .CLK100MHZ (CLK100MHZ),
        .CPU_RESETN(CPU_RESETN),
        .BTNC      (BTNC),
        .SW        (SW),
        .AN        (AN),
        .HEX       (HEX),
        .LED       (LED)
    );

    initial CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    //--------------------------------------------------------------------------
    // 期望值
    //--------------------------------------------------------------------------
    function [31:0] f_sum;
        input integer n;
        integer i;
        begin
            f_sum = 0;
            for (i = 1; i <= n; i = i + 1)
                f_sum = f_sum + i;
        end
    endfunction

    function [31:0] f_fib;
        input integer n;
        integer i;
        reg [31:0] a, b, c;
        begin
            a = 0;
            b = 1;
            for (i = 0; i < n; i = i + 1) begin
                c = a + b;
                a = b;
                b = c;
            end
            f_fib = a;
        end
    endfunction

    function [31:0] f_prime;
        input integer n;
        integer i;
        begin
            f_prime = 0;
            if (n >= 2) begin
                f_prime = 1;
                for (i = 2; i < n; i = i + 1)
                    if ((n % i) == 0)
                        f_prime = 0;
            end
        end
    endfunction

    function integer gcd_sub;
        input integer a;
        input integer b;
        begin
            if (a == 0)
                gcd_sub = b;
            else if (b == 0)
                gcd_sub = a;
            else begin
                while (a != b) begin
                    if (a > b) a = a - b;
                    else       b = b - a;
                end
                gcd_sub = a;
            end
        end
    endfunction

    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'h0:    seg7 = 7'b1000000;
                4'h1:    seg7 = 7'b1111001;
                4'h2:    seg7 = 7'b0100100;
                4'h3:    seg7 = 7'b0110000;
                4'h4:    seg7 = 7'b0011001;
                4'h5:    seg7 = 7'b0010010;
                4'h6:    seg7 = 7'b0000010;
                4'h7:    seg7 = 7'b1111000;
                4'h8:    seg7 = 7'b0000000;
                4'h9:    seg7 = 7'b0010000;
                4'hA:    seg7 = 7'b0001000;
                4'hB:    seg7 = 7'b0000011;
                4'hC:    seg7 = 7'b1000110;
                4'hD:    seg7 = 7'b0100001;
                4'hE:    seg7 = 7'b0000110;
                default: seg7 = 7'b0001110;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // 跑一个程序并检查
    //   prog: SW[15:14], n: SW[3:0], m: SW[7:4]
    //   exp : 期望的结果, exp_pc: 停机时 PC 低 16 位
    //--------------------------------------------------------------------------
    task run_case;
        input [1:0]  prog;
        input [3:0]  n;
        input [3:0]  m;
        input [31:0] exp;
        input [15:0] exp_pc;
        begin
            SW = {prog, 1'b1, 5'b0, m, n};
            CPU_RESETN = 1'b0;
            repeat (10) @(posedge CLK100MHZ);
            CPU_RESETN = 1'b1;

            repeat (600) @(posedge CLK100MHZ);
            #1;

            if (uut.result_reg !== exp) begin
                $display("MISMATCH: prog=%0d n=%0d m=%0d result=0x%08h expected 0x%08h",
                         prog, n, m, uut.result_reg, exp);
                errors = errors + 1;
            end else begin
                $display("ok: prog=%0d n=%0d m=%0d result=0x%08h pc=0x%04h",
                         prog, n, m, uut.result_reg, uut.dbgdata[15:0]);
            end

            if (uut.dbgdata[15:0] !== exp_pc) begin
                $display("MISMATCH: prog=%0d pc=0x%04h expected 0x%04h",
                         prog, uut.dbgdata[15:0], exp_pc);
                errors = errors + 1;
            end

            if (LED !== exp_pc) begin
                $display("MISMATCH: LED=0x%04h expected PC 0x%04h", LED, exp_pc);
                errors = errors + 1;
            end

            // 数码管最低位
            while (uut.dig != 3'd0) @(posedge CLK100MHZ);
            #1;
            if (HEX !== {seg7(exp[3:0]), 1'b1}) begin
                $display("MISMATCH: HEX=0x%02h expected 0x%02h (nibble 0x%h)",
                         HEX, {seg7(exp[3:0]), 1'b1}, exp[3:0]);
                errors = errors + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    initial begin
        CLK100MHZ  = 1'b0;
        CPU_RESETN = 1'b0;
        BTNC       = 1'b0;
        SW         = 16'b0;
        errors     = 0;

        #100;   // 等上电复位结束

        // 程序 0: 累加和, 停机 PC = 4*(10-1) = 36
        run_case(2'd0, 4'd0,  4'd0, f_sum(0),   16'd36);
        run_case(2'd0, 4'd10, 4'd0, f_sum(10),  16'd36);
        run_case(2'd0, 4'd15, 4'd0, f_sum(15),  16'd36);

        // 程序 1: 斐波那契, 停机 PC = 4*(13-1) = 48
        run_case(2'd1, 4'd0,  4'd0, f_fib(0),   16'd48);
        run_case(2'd1, 4'd1,  4'd0, f_fib(1),   16'd48);
        run_case(2'd1, 4'd10, 4'd0, f_fib(10),  16'd48);
        run_case(2'd1, 4'd15, 4'd0, f_fib(15),  16'd48);

        // 程序 2: 素数判断, 停机 PC = 4*(18-1) = 68
        run_case(2'd2, 4'd2,  4'd0, f_prime(2),  16'd68);
        run_case(2'd2, 4'd4,  4'd0, f_prime(4),  16'd68);
        run_case(2'd2, 4'd7,  4'd0, f_prime(7),  16'd68);
        run_case(2'd2, 4'd15, 4'd0, f_prime(15), 16'd68);

        // 程序 3: 最大公约数, 停机 PC = 4*(17-1) = 64
        run_case(2'd3, 4'd12, 4'd8, gcd_sub(12, 8), 16'd64);
        run_case(2'd3, 4'd0,  4'd9, gcd_sub(0, 9),  16'd64);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);

        $finish;
    end

endmodule

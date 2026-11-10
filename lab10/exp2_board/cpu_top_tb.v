`timescale 1ns / 1ps

// cpu_top_tb.v : lab10 上板顶层自检
//   把上电复位/自动运行分频/数码管扫描分频都缩小, 逐个程序跑完并检查结果,
//   另外检查数码管的"周期数"显示模式和单步执行.

module cpu_top_tb;

    reg         CLK100MHZ;
    reg         CPU_RESETN;
    reg         BTNC;
    reg  [15:0] SW;
    wire [7:0]  AN;
    wire [7:0]  HEX;
    wire [15:0] LED;

    integer errors;

    // 缩小各计数器, 让仿真在几百微秒内跑完
    cpu_top #(
        .POR_BITS (3),
        .DIV_BITS (2),        // 25MHz, 10ns 高 / 30ns 低; 试 50MHz 改成 1
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

    // 期望值

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

    function [31:0] f_leap;
        input integer y;
        begin
            if (((y % 4) == 0) && (((y % 100) != 0) || ((y % 400) == 0)))
                f_leap = 1;
            else
                f_leap = 0;
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

    // 检查 8 位数码管是否逐位显示 value
    task check_disp;
        input [31:0] value;
        integer k;
        reg [3:0] exp_nib;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                while (uut.dig != k) @(posedge CLK100MHZ);
                #1;
                exp_nib = (value >> (4 * k));
                if (HEX !== {seg7(exp_nib), 1'b1}) begin
                    $display("MISMATCH: HEX=0x%02h expected 0x%02h (digit %0d = 0x%h)",
                             HEX, {seg7(exp_nib), 1'b1}, k, exp_nib);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // 跑一个程序并检查
    //   prog: SW[15:14], n: SW[11:0]
    //   exp : 期望的二进制结果, exp_pc: 停机时 PC 低 16 位

    task run_case;
        input [1:0]  prog;
        input [11:0] n;
        input [31:0] exp;
        input [15:0] exp_pc;
        integer timeout;
        integer halted;
        integer halt_cycles;
        begin
            SW = {prog, 1'b1, 1'b0, n};   // SW[13]=1 自动运行, SW[12]=0 显示结果
            CPU_RESETN = 1'b0;
            repeat (10) @(posedge CLK100MHZ);
            CPU_RESETN = 1'b1;

            // 等停机指令 j hang 在 EX 阶段确定跳转到自己.
            // 流水线会顺序预取 PC+4, 直接看 PC 会在循环里误判, 必须看 EX 阶段的结果.
            timeout = 0;
            halted  = 0;
            while (!halted && (timeout < 200000)) begin
                @(posedge CLK100MHZ);
                timeout = timeout + 1;
                if ((uut.u_cpu.EX_pc == exp_pc) && uut.u_cpu.ex_branch_taken) begin
                    halted      = 1;
                    halt_cycles = uut.cyc_cnt;
                end
            end

            // 再等一会, 让停机前的 store 写完数据存储器
            repeat (200) @(posedge CLK100MHZ);
            #1;

            if (!halted) begin
                $display("MISMATCH: prog=%0d n=%0d 未停机, pc=0x%04h",
                         prog, n, uut.dbgdata[15:0]);
                errors = errors + 1;
            end

            if (uut.result_reg !== exp) begin
                $display("MISMATCH: prog=%0d n=%0d result=0x%08h expected 0x%08h",
                         prog, n, uut.result_reg, exp);
                errors = errors + 1;
            end else begin
                $display("ok: prog=%0d n=%0d result=0x%08h halt_pc=0x%04h cycles=%0d",
                         prog, n, exp, exp_pc, halt_cycles);
            end

            // 停机后 CPU 一直执行 j hang, 预取的 PC 只会在这三个地址之间变化
            if ((uut.dbgdata[15:0] !== exp_pc) &&
                (uut.dbgdata[15:0] !== (exp_pc + 16'd4)) &&
                (uut.dbgdata[15:0] !== (exp_pc + 16'd8))) begin
                $display("MISMATCH: prog=%0d pc=0x%04h 不在停机循环里",
                         prog, uut.dbgdata[15:0]);
                errors = errors + 1;
            end

            if (LED !== uut.dbgdata[15:0]) begin
                $display("MISMATCH: LED=0x%04h 与 PC 0x%04h 不一致",
                         LED, uut.dbgdata[15:0]);
                errors = errors + 1;
            end

            check_disp(exp);
        end
    endtask

    // 单步: 按一次 BTNC 执行一个 CPU 周期, PC 应该一步步前进

    task step_once;
        begin
            BTNC = 1'b1;
            repeat (6) @(posedge CLK100MHZ);
            BTNC = 1'b0;
            repeat (6) @(posedge CLK100MHZ);
        end
    endtask

    initial begin
        CLK100MHZ  = 1'b0;
        CPU_RESETN = 1'b0;
        BTNC       = 1'b0;
        SW         = 16'b0;
        errors     = 0;

        #100;   // 等上电复位结束

        // 程序 0: 累加和, 停机 PC = 40
        run_case(2'd0, 12'd0,    f_sum(0),    16'd40);
        run_case(2'd0, 12'd10,   f_sum(10),   16'd40);
        run_case(2'd0, 12'd2024, f_sum(2024), 16'd40);

        // 程序 1: 斐波那契, 停机 PC = 52
        run_case(2'd1, 12'd0,  f_fib(0),  16'd52);
        run_case(2'd1, 12'd1,  f_fib(1),  16'd52);
        run_case(2'd1, 12'd10, f_fib(10), 16'd52);
        run_case(2'd1, 12'd20, f_fib(20), 16'd52);
        run_case(2'd1, 12'd39, f_fib(39), 16'd52);
        run_case(2'd1, 12'd46, f_fib(46), 16'd52);

        // 程序 2: 闰年判断, 停机 PC = 68
        run_case(2'd2, 12'd2024, f_leap(2024), 16'd68);
        run_case(2'd2, 12'd1900, f_leap(1900), 16'd68);
        run_case(2'd2, 12'd2000, f_leap(2000), 16'd68);
        run_case(2'd2, 12'd2023, f_leap(2023), 16'd68);
        run_case(2'd2, 12'd400,  f_leap(400),  16'd68);

        // 程序 3: 素数判断, 停机 PC = 72
        run_case(2'd3, 12'd0,  f_prime(0),  16'd72);
        run_case(2'd3, 12'd1,  f_prime(1),  16'd72);
        run_case(2'd3, 12'd2,  f_prime(2),  16'd72);
        run_case(2'd3, 12'd4,  f_prime(4),  16'd72);
        run_case(2'd3, 12'd7,  f_prime(7),  16'd72);
        run_case(2'd3, 12'd15, f_prime(15), 16'd72);
        run_case(2'd3, 12'd97, f_prime(97), 16'd72);

        // 单步模式: 每按一次 BTNC 走一个流水线周期

        SW = {2'd0, 1'b0, 1'b0, 12'd0};   // 程序 0, 单步, 显示结果, n=0
        CPU_RESETN = 1'b0;
        repeat (10) @(posedge CLK100MHZ);
        CPU_RESETN = 1'b1;
        repeat (10) @(posedge CLK100MHZ);
        #1;
        if (uut.dbgdata[15:0] !== 16'd0) begin
            $display("MISMATCH: reset pc=0x%04h", uut.dbgdata[15:0]);
            errors = errors + 1;
        end
        if (uut.result_reg !== 32'd0) begin
            $display("MISMATCH: reset result=0x%08h", uut.result_reg);
            errors = errors + 1;
        end
        check_disp(32'd0);

        // 按三下, PC 依次是 4、8、12, 说明每个周期只前进一段
        step_once();
        if (uut.dbgdata[15:0] !== 16'd4) begin
            $display("MISMATCH: 单步 1 次后 pc=0x%04h expected 0x0004", uut.dbgdata[15:0]);
            errors = errors + 1;
        end
        step_once();
        if (uut.dbgdata[15:0] !== 16'd8) begin
            $display("MISMATCH: 单步 2 次后 pc=0x%04h expected 0x0008", uut.dbgdata[15:0]);
            errors = errors + 1;
        end
        step_once();
        if (uut.dbgdata[15:0] !== 16'd12) begin
            $display("MISMATCH: 单步 3 次后 pc=0x%04h expected 0x000c", uut.dbgdata[15:0]);
            errors = errors + 1;
        end

        // SW[12]=1: 数码管改为显示已经执行的 CPU 周期数
        // 单步模式下周期数只在按键时变化, 可以逐位检查
        SW = {2'd0, 1'b0, 1'b1, 12'd0};
        CPU_RESETN = 1'b0;
        repeat (10) @(posedge CLK100MHZ);
        CPU_RESETN = 1'b1;
        repeat (10) @(posedge CLK100MHZ);
        #1;
        if (uut.cyc_cnt !== 32'd0) begin
            $display("MISMATCH: reset cyc_cnt=%0d expected 0", uut.cyc_cnt);
            errors = errors + 1;
        end
        check_disp(32'd0);

        step_once();
        step_once();
        #1;
        if (uut.cyc_cnt !== 32'd2) begin
            $display("MISMATCH: 单步 2 次后 cyc_cnt=%0d expected 2", uut.cyc_cnt);
            errors = errors + 1;
        end
        check_disp(uut.cyc_cnt);
        $display("ok: 周期数显示模式 cyc_cnt=%0d", uut.cyc_cnt);

        $display("simulation time: %0t (%0d ns)", $time, $time);
        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);

        $finish;
    end

endmodule

`timescale 1 ns / 10 ps

// rv32ip_hazard_tb.v : 流水线冒险的边界情况自检
//
// 程序见 tests/hazard.S, 机器码 tests/hazard.hex 由 tools/rvasm.py 汇编:
//   cd lab10/exp1_cpu && python3 ../../tools/rvasm.py tests/hazard.S > tests/hazard.hex
//
// 覆盖 load-use 阻塞、MEM->EX 与 WB->EX 前转、"load 后紧跟分支" 这类
// 容易出错但普通测试集不一定覆盖的组合.

module rv32ip_hazard_tb;

    integer numcycles;
    integer errors;

    reg clk, reset;

    wire [31:0] iaddr, idataout;
    wire        iclk;
    wire [31:0] daddr, ddataout, ddatain;
    wire        drdclk, dwrclk, dwe;
    wire [2:0]  dop;
    wire [31:0] cpudbgdata;

    rv32ip mycpu(
        .clock       (clk),
        .reset       (reset),
        .imemaddr    (iaddr),
        .imemdataout (idataout),
        .imemclk     (iclk),
        .dmemaddr    (daddr),
        .dmemdataout (ddataout),
        .dmemdatain  (ddatain),
        .dmemrdclk   (drdclk),
        .dmemwrclk   (dwrclk),
        .dmemop      (dop),
        .dmemwe      (dwe),
        .dbgdata     (cpudbgdata)
    );

    testmem instructions(
        .address (iaddr[17:2]),
        .clock   (iclk),
        .data    (32'b0),
        .wren    (1'b0),
        .q       (idataout)
    );

    dmem datamem(
        .addr    (daddr),
        .dataout (ddataout),
        .datain  (ddatain),
        .rdclk   (drdclk),
        .wrclk   (dwrclk),
        .memop   (dop),
        .we      (dwe)
    );

    task step;
        begin
            #9  clk = 1'b1;
            #10 clk = 1'b0;
            numcycles = numcycles + 1;
            #1;
        end
    endtask

    task checkreg;
        input [4:0]  regid;
        input [31:0] results;
        begin
            if (mycpu.myregfile.regs[regid] !== results) begin
                $display("MISMATCH: cycle %0d reg x%0d = %h, expected %h",
                         numcycles, regid, mycpu.myregfile.regs[regid], results);
                errors = errors + 1;
            end
        end
    endtask

    task checkmem;
        input [31:0] inputaddr;
        input [31:0] results;
        begin
            if (datamem.mymem.ram[inputaddr[16:2]] !== results) begin
                $display("MISMATCH: cycle %0d mem[%h] = %h, expected %h",
                         numcycles, inputaddr, datamem.mymem.ram[inputaddr[16:2]], results);
                errors = errors + 1;
            end
        end
    endtask

    initial begin: TestBench
        errors    = 0;
        numcycles = 0;
        clk       = 1'b0;
        reset     = 1'b1;

        $readmemh("tests/hazard.hex", instructions.ram);

        step();
        step();
        #5 reset = 1'b0;
        numcycles = 0;

        repeat (40) step();

        checkreg(4, 32'd32);      // add x4 = 32, load-use 后用上了 load 的结果
        checkreg(5, 32'd2);       // bne 跳转成功, 没有执行 x5 = 1
        checkreg(6, 32'd16);      // lw 结果
        checkreg(7, 32'd7);       // beq 用旧数据会误跳, 结果不能跳
        checkreg(8, 32'd8);
        checkreg(10, 32'h123);    // jalr 前转成功, 跳过了 0xBAD 区
        checkmem(32'h100, 32'd16);
        checkmem(32'h104, 32'h123);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

`timescale 1 ns / 10 ps

// rv32ip_tb.v : RV32I 五段流水线 CPU 单步自检
//
// 由课程提供的 cpu_step.v 改写: 检查序列与课程 testbench 完全一致,
// 但把每条检查变成出错时打印 MISMATCH 并计数, 最后给出 TEST PASSED/FAILED.
//
// 覆盖 add / alu / mem / branch 四段程序, 其中
//   mem    检查 load-use 冒险要阻塞一个周期
//   branch 检查跳转在 EX 阶段解决, 每次冲刷两条指令
//
// 仿真前把 tests/ 目录拷到 Vivado 的仿真工作目录
// (工程名.sim/sim_1/behav/xsim), 或把下面的 tests/ 改成绝对路径.

module rv32ip_tb;

    integer numcycles;   // 已经执行的周期数
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

    // 一个周期: 上升沿读存储器/写寄存器, 下降沿更新 PC 和段寄存器,
    // 检查点在下降沿之后 1ns

    task step;
        begin
            #9  clk = 1'b1;
            #10 clk = 1'b0;
            numcycles = numcycles + 1;
            #1;
        end
    endtask

    task resetcpu;
        begin
            reset = 1'b1;
            step();
            step();
            #5 reset = 1'b0;
            numcycles = 0;
        end
    endtask

    // 需要带引号调用: `LOAD("add")
    `define LOAD(name) \
        begin \
            $readmemh({"tests/", name, ".hex"}, instructions.ram); \
            $display("~~~ Begin test case %0s ~~~", name); \
        end

    // 检查任务

    task checkreg;
        input [4:0]  regid;
        input [31:0] results;
        reg   [31:0] debugdata;
        begin
            debugdata = mycpu.myregfile.regs[regid];
            if (debugdata !== results) begin
                $display("MISMATCH: cycle %0d reg x%0d = %h, expected %h",
                         numcycles, regid, debugdata, results);
                errors = errors + 1;
            end
        end
    endtask

    task checkmem;
        input [31:0] inputaddr;
        input [31:0] results;
        reg   [31:0] debugdata;
        begin
            debugdata = datamem.mymem.ram[inputaddr[16:2]];
            if (debugdata !== results) begin
                $display("MISMATCH: cycle %0d mem[%h] = %h, expected %h",
                         numcycles, inputaddr, debugdata, results);
                errors = errors + 1;
            end
        end
    endtask

    task checkpc;
        input [31:0] results;
        begin
            if (cpudbgdata !== results) begin
                $display("MISMATCH: cycle %0d PC = %h, expected %h",
                         numcycles, cpudbgdata, results);
                errors = errors + 1;
            end
        end
    endtask

    initial begin: TestBench
        errors = 0;
        clk    = 1'b0;
        reset  = 1'b0;

        #80;

        // add: 三条指令依次流过流水线, 第 5 个周期写回第一条

        `LOAD("add")
        resetcpu();
        step(); checkpc(32'h4);
        step(); checkpc(32'h8);
        step();
        step();
        step(); checkreg(6, 32'd100);
        step(); checkreg(7, 32'd20);
        step(); checkreg(28, 32'd120);

        // alu: 算术逻辑指令, 每条前一条的结果都会被后一条用到, 走前转通路

        `LOAD("alu")
        resetcpu();
        step();
        step();
        step();
        step();
        step(); checkreg(6, 79);              // addi t1,zero,79
        step(); checkreg(7, 3);               // addi t2,zero,3
        step(); checkreg(28, 76);             // sub
        step(); checkreg(28, 3);              // and
        step(); checkreg(28, 632);            // sll
        step(); checkreg(28, 0);              // slt
        step(); checkreg(28, 1);              // slt
        step(); checkreg(28, 76);             // xor
        step(); checkreg(28, 9);              // srl
        step(); checkreg(28, 79);             // or
        step(); checkreg(6, -79);             // addi t1,zero,-3
        step(); checkreg(28, -76);            // add
        step(); checkreg(28, 32'hfffffff6);   // sra
        step(); checkreg(28, 32'h1ffffff6);   // srl
        step(); checkreg(28, 1);              // slt  -79 < 3
        step(); checkreg(28, 0);              // sltu

        // mem: 字节/半字/字访存, 最后三条是 load-use 冒险

        `LOAD("mem")
        resetcpu();
        step();
        step();
        step();
        step();
        step(); checkreg(10, 32'h8000);       // lui a0,0x8
        step(); checkreg(10, 32'h8010);       // addi a0,a0,16
        step(); checkreg(6, 32'd1234);        // addi t1,zero,1234
        step(); checkmem(32'h8014, 32'd1234); // sw
        step(); checkreg(7, 32'd1234);        // lw
        step(); checkmem(32'h8018, 32'd0);    // sw zero
        step(); checkreg(6, 32'd255);
        step(); checkmem(32'h8018, 32'hff);   // sb
        step(); checkreg(7, 32'hffffffff);    // lb
        step(); checkreg(7, 32'hff);          // lbu
        step(); checkmem(32'h8018, 32'hffff); // sh
        step(); checkreg(7, 32'hffffffff);    // lh
        step(); checkreg(7, 32'hffff);        // lhu
        step(); checkreg(7, 32'hffffffff);    // lb
        step(); checkreg(7, 32'h0);           // lb
        step(); checkmem(32'h801c, 32'h0);    // sw zero,12(a0)
        step(); checkreg(6, 32'h78);
        step(); checkmem(32'h801c, 32'h78);   // sb
        step(); checkreg(6, 32'h56);
        step(); checkmem(32'h801c, 32'h5678);
        step(); checkreg(6, 32'h34);
        step(); checkmem(32'h801c, 32'h345678);
        step(); checkreg(6, 32'h12);
        step(); checkmem(32'h801c, 32'h12345678);
        step(); checkreg(7, 32'h12345678);    // lw
        step(); checkreg(28, 32'h00000034);   // lbu t3,14(a0), 下一条 sw 要 t3
        step();                               // load-use 阻塞一个周期
        step();
        step(); checkmem(32'h8024, 32'h00000034);
        step(); checkreg(11, 32'h00008020);   // addi a1,a0,16
        step(); checkreg(28, 32'h00000012);   // lbu t3,15(a0)
        step(); checkmem(32'h8024, 32'h00000012);

        // branch: 条件分支与 jal/jalr, 跳转在 EX 阶段确定, 每个跳转两个气泡

        `LOAD("branch")
        resetcpu();
        step(); checkpc(32'h4);
        step(); checkpc(32'h8);
        step(); checkpc(32'hc);
        step(); checkpc(32'h10);
        step(); checkreg(5, 32'd100); checkpc(32'h14);
        step(); checkreg(6, 32'hfffffffe); checkpc(32'h14);
        step(); checkpc(32'h18);
        step(); checkpc(32'h1C);
        step(); checkpc(32'h20);
        step(); checkpc(32'h24);
        step(); checkpc(32'h24);
        step(); checkpc(32'h28);
        step(); checkpc(32'h2C);
        step(); checkpc(32'h30);
        step(); checkpc(32'h44);
        step(); checkpc(32'h48);
        step(); checkreg(1, 32'h2c); checkpc(32'h4C);
        step(); checkpc(32'h50);
        step(); checkpc(32'h38);
        step(); checkreg(5, 32'd123); checkpc(32'h3C);
        step(); checkpc(32'h40);
        step(); checkpc(32'h44);
        step(); checkpc(32'h48);
        step(); checkpc(32'h4C);
        step(); checkpc(32'h50); checkreg(10, 32'hc0ffee);
        step(); checkpc(32'h54);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

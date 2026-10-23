`timescale 1 ns / 10 ps
//==============================================================================
// rv32is_tb.v : RV32I 单周期 CPU 单步自检
//
// 用课程提供的 add / alu / mem / branch 四个小程序逐条指令检查寄存器、
// 存储器与 PC. 每个检查点打印 OK 或 MISMATCH, 最后给出 TEST PASSED/FAILED.
//
// 仿真前把 tests/ 目录拷到 Vivado 的仿真工作目录
// (工程名.sim/sim_1/behav/xsim), 或把下面的 HEXDIR 改成绝对路径.
//==============================================================================
module rv32is_tb;

    integer numcycles;
    integer errors;

    reg clk, reset;

    wire [31:0] iaddr, idataout;
    wire        iclk;
    wire [31:0] daddr, ddataout, ddatain;
    wire        drdclk, dwrclk, dwe;
    wire [2:0]  dop;
    wire [31:0] cpudbgdata;

    rv32is mycpu(
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

    //--------------------------------------------------------------------------
    // 单步: 一个时钟周期, 检查点在上升沿之后 1ns
    //--------------------------------------------------------------------------
    task step;
        begin
            #9  clk = 1'b0;
            #10 clk = 1'b1;
            numcycles = numcycles + 1;
            #1;
        end
    endtask

    task resetcpu;
        begin
            reset = 1'b1;
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

    //--------------------------------------------------------------------------
    // 检查任务
    //--------------------------------------------------------------------------
    task checkreg;
        input [4:0]  regid;
        input [31:0] results;
        reg [31:0] debugdata;
        begin
            debugdata = mycpu.myregfile.regs[regid];
            if (debugdata !== results) begin
                $display("MISMATCH: cycle %0d reg x%0d = %h, expected %h",
                         numcycles - 1, regid, debugdata, results);
                errors = errors + 1;
            end
        end
    endtask

    task checkmem;
        input [31:0] inputaddr;
        input [31:0] results;
        reg [31:0] debugdata;
        begin
            debugdata = datamem.mymem.ram[inputaddr[16:2]];
            if (debugdata !== results) begin
                $display("MISMATCH: cycle %0d mem[%h] = %h, expected %h",
                         numcycles - 1, inputaddr, debugdata, results);
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

    //--------------------------------------------------------------------------
    initial begin: TestBench
        errors = 0;
        clk    = 1'b1;   // 先为高, 让 resetcpu 的第一次 #9 产生下降沿, 完成首次取指
        reset  = 1'b0;

        #80;

        //----------------------------------------------------------------------
        // add: addi t1,zero,100 / addi t2,zero,20 / add t3,t1,t2
        //----------------------------------------------------------------------
        `LOAD("add")
        resetcpu();
        step(); checkreg(6, 32'd100); checkpc(32'h4);
        step(); checkreg(7, 32'd20);  checkpc(32'h8);
        step(); checkreg(28, 32'd120);

        //----------------------------------------------------------------------
        // alu: 加减、逻辑、移位、比较
        //----------------------------------------------------------------------
        `LOAD("alu")
        resetcpu();
        step(); checkreg(6, 79);
        step(); checkreg(7, 3);
        step(); checkreg(28, 76);              // sub
        step(); checkreg(28, 3);               // and
        step(); checkreg(28, 632);             // sll
        step(); checkreg(28, 0);               // slt
        step(); checkreg(28, 1);               // slt
        step(); checkreg(28, 76);              // xor
        step(); checkreg(28, 9);               // srl
        step(); checkreg(28, 79);              // or
        step(); checkreg(6, -79);
        step(); checkreg(28, -76);             // add
        step(); checkreg(28, 32'hfffffff6);    // sra
        step(); checkreg(28, 32'h1ffffff6);    // srl
        step(); checkreg(28, 1);               // slt  -79 < 3
        step(); checkreg(28, 0);               // sltu

        //----------------------------------------------------------------------
        // mem: lw/sw/lb/lbu/lh/lhu/sb/sh 与符号扩展
        //----------------------------------------------------------------------
        `LOAD("mem")
        resetcpu();
        step(); checkreg(10, 32'h8000);
        step(); checkreg(10, 32'h8010);
        step(); checkreg(6, 32'd1234);
        step(); checkmem(32'h8014, 32'd1234);  // sw
        step(); checkreg(7, 32'd1234);         // lw
        step(); checkmem(32'h8018, 32'd0);
        step(); checkreg(6, 32'd255);
        step(); checkmem(32'h8018, 32'hff);    // sb
        step(); checkreg(7, 32'hffffffff);     // lb
        step(); checkreg(7, 32'hff);           // lbu
        step(); checkmem(32'h8018, 32'hffff);  // sh
        step(); checkreg(7, 32'hffffffff);     // lh
        step(); checkreg(7, 32'hffff);         // lhu
        step(); checkreg(7, 32'hffffffff);
        step(); checkreg(7, 32'h0);
        step(); checkmem(32'h801c, 32'h0);
        step(); checkreg(6, 32'h78);
        step(); checkmem(32'h801c, 32'h78);
        step(); checkreg(6, 32'h56);
        step(); checkmem(32'h801c, 32'h5678);
        step(); checkreg(6, 32'h34);
        step(); checkmem(32'h801c, 32'h345678);
        step(); checkreg(6, 32'h12);
        step(); checkmem(32'h801c, 32'h12345678);
        step(); checkreg(7, 32'h12345678);     // lw

        //----------------------------------------------------------------------
        // branch: beq/bne/blt/bge/bltu/bgeu/jal/jalr
        //----------------------------------------------------------------------
        `LOAD("branch")
        resetcpu();
        step(); checkreg(5, 32'd100);
        step(); checkreg(6, 32'hfffffffe);
        step(); checkpc(32'hc);
        step(); checkpc(32'h14);
        step(); checkpc(32'h18);
        step(); checkpc(32'h1c);
        step(); checkpc(32'h24);
        step(); checkpc(32'h28);
        step(); checkpc(32'h44); checkreg(1, 32'h2c);
        step(); checkpc(32'h48); checkreg(5, 32'd123);
        step(); checkpc(32'h38);
        step(); checkpc(32'h3c);
        step(); checkreg(10, 32'hc0ffee);
        step(); checkpc(32'h4c);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

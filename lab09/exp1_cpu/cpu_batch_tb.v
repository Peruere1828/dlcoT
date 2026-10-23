`timescale 1 ns / 10 ps

// cpu_batch_tb.v : 用 RISC-V 官方测试集 rv32ui-p-* 批量验证 rv32is
//
// 每个用例从 tests/ 载入指令与数据, 运行到取到 32'hdead10cc 为止,
// 根据 a0(x10) 是 0xc0ffee / 0xdeaddead 判断通过或失败.
//
// 仿真前把 tests/ 目录拷到 Vivado 的仿真工作目录
// (工程名.sim/sim_1/behav/xsim), 或把下面的 tests/ 改成绝对路径.
//
// 全部 38 个用例在 iverilog 下约需 10 秒, 仿真时间约 230us.

module cpu_batch_tb;

    integer numcycles;
    integer passcnt, failcnt;
    integer maxcycles = 10000;

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

    task run;
        integer i;
        begin
            i = 0;
            while ((idataout != 32'hdead10cc) && (i < maxcycles)) begin
                step();
                i = i + 1;
            end
        end
    endtask

    task checkmagnum;
        input [8*17:1] name;
        begin
            if (numcycles >= maxcycles) begin
                $display("ERROR: %0s does not terminate!", name);
                failcnt = failcnt + 1;
            end else if (mycpu.myregfile.regs[10] == 32'h00c0ffee) begin
                $display("OK: %0s finished at cycle %0d", name, numcycles - 1);
                passcnt = passcnt + 1;
            end else if (mycpu.myregfile.regs[10] == 32'hdeaddead) begin
                $display("ERROR: %0s failed at cycle %0d", name, numcycles - 1);
                failcnt = failcnt + 1;
            end else begin
                $display("ERROR: %0s unknown result a0=%h at cycle %0d",
                         name, mycpu.myregfile.regs[10], numcycles - 1);
                failcnt = failcnt + 1;
            end
        end
    endtask

    // 载入一个用例并运行

    `define RUN_TEST(name) \
        begin \
            $readmemh({"tests/", name, ".hex"},   instructions.ram); \
            $readmemh({"tests/", name, "_d.hex"}, datamem.mymem.ram); \
            $display("~~~ Begin test case %0s ~~~", name); \
            resetcpu(); \
            run(); \
            checkmagnum(name); \
        end

    initial begin: TestBench
        integer i;
        clk     = 1'b1;   // 先为高, 让 resetcpu 的第一次 #9 产生下降沿, 完成首次取指
        reset   = 1'b0;
        passcnt = 0;
        failcnt = 0;

        #80;

        `RUN_TEST("rv32ui-p-simple")
        `RUN_TEST("rv32ui-p-add")
        `RUN_TEST("rv32ui-p-addi")
        `RUN_TEST("rv32ui-p-and")
        `RUN_TEST("rv32ui-p-andi")
        `RUN_TEST("rv32ui-p-auipc")
        `RUN_TEST("rv32ui-p-beq")
        `RUN_TEST("rv32ui-p-bge")
        `RUN_TEST("rv32ui-p-bgeu")
        `RUN_TEST("rv32ui-p-blt")
        `RUN_TEST("rv32ui-p-bltu")
        `RUN_TEST("rv32ui-p-bne")
        `RUN_TEST("rv32ui-p-jal")
        `RUN_TEST("rv32ui-p-jalr")
        `RUN_TEST("rv32ui-p-lb")
        `RUN_TEST("rv32ui-p-lbu")
        `RUN_TEST("rv32ui-p-lh")
        `RUN_TEST("rv32ui-p-lhu")
        `RUN_TEST("rv32ui-p-lui")
        `RUN_TEST("rv32ui-p-lw")
        `RUN_TEST("rv32ui-p-or")
        `RUN_TEST("rv32ui-p-ori")
        `RUN_TEST("rv32ui-p-sb")
        `RUN_TEST("rv32ui-p-sh")
        `RUN_TEST("rv32ui-p-sll")
        `RUN_TEST("rv32ui-p-slli")
        `RUN_TEST("rv32ui-p-slt")
        `RUN_TEST("rv32ui-p-slti")
        `RUN_TEST("rv32ui-p-sltiu")
        `RUN_TEST("rv32ui-p-sltu")
        `RUN_TEST("rv32ui-p-sra")
        `RUN_TEST("rv32ui-p-srai")
        `RUN_TEST("rv32ui-p-srl")
        `RUN_TEST("rv32ui-p-srli")
        `RUN_TEST("rv32ui-p-sub")
        `RUN_TEST("rv32ui-p-sw")
        `RUN_TEST("rv32ui-p-xor")
        `RUN_TEST("rv32ui-p-xori")

        if (failcnt == 0)
            $display("TEST PASSED: %0d/%0d", passcnt, passcnt + failcnt);
        else
            $display("TEST FAILED: %0d passed, %0d failed", passcnt, failcnt);

        $finish;
    end

endmodule

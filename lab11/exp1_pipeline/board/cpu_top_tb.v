`timescale 1ns / 1ps
//=======================================================================
// lab11 上板外壳自检: 缩短分频, 自动运行, 核对结果与 dmem
//=======================================================================
module cpu_top_tb;

    reg         CLK100MHZ;
    reg         CPU_RESETN;
    reg         BTNC;
    reg         SW0;
    wire [7:0]  AN, HEX;
    wire [15:0] LED;

    integer errors;

    cpu_top #(.DIV_MAX(1)) uut (
        .CLK100MHZ(CLK100MHZ),
        .CPU_RESETN(CPU_RESETN),
        .BTNC(BTNC),
        .SW0(SW0),
        .AN(AN), .HEX(HEX), .LED(LED)
    );

    always #5 CLK100MHZ = ~CLK100MHZ;

    initial begin
        errors = 0;
        CLK100MHZ  = 1'b0;
        CPU_RESETN = 1'b0;
        BTNC       = 1'b0;
        SW0        = 1'b0;

        #200;
        CPU_RESETN = 1'b1;
        #200000;

        if (uut.u_cpu.u_regfile.regs[4] !== 32'd3) begin
            $display("MISMATCH: x4=0x%08h expected 3", uut.u_cpu.u_regfile.regs[4]);
            errors = errors + 1;
        end
        if (uut.u_cpu.u_regfile.regs[5] !== 32'd4) begin
            $display("MISMATCH: x5=0x%08h expected 4", uut.u_cpu.u_regfile.regs[5]);
            errors = errors + 1;
        end
        if (uut.u_cpu.u_regfile.regs[6] !== 32'd3) begin
            $display("MISMATCH: x6=0x%08h expected 3", uut.u_cpu.u_regfile.regs[6]);
            errors = errors + 1;
        end
        if (uut.u_dmem.mem[0] !== 32'd3) begin
            $display("MISMATCH: dmem[0]=0x%08h expected 3", uut.u_dmem.mem[0]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

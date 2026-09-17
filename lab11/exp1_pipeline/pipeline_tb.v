`timescale 1ns / 1ps
//=======================================================================
// lab11 五段流水线自检 testbench
// 载入 prog11.hex, 跑到 j . 停机, 核对寄存器/存储器并统计周期数
//=======================================================================
module pipeline_tb;

    reg         clock;
    reg         reset;

    wire [31:0] imemaddr, imemdataout;
    wire        imemclk;
    wire [31:0] dmemaddr, dmemdataout, dmemdatain;
    wire        dmemrdclk, dmemwrclk, dmemwe;
    wire [2:0]  dmemop;
    wire [31:0] dbgdata;

    integer errors;
    integer cycles;

    rv32ip uut (
        .clock(clock), .reset(reset),
        .imemaddr(imemaddr), .imemdataout(imemdataout), .imemclk(imemclk),
        .dmemaddr(dmemaddr), .dmemdataout(dmemdataout), .dmemdatain(dmemdatain),
        .dmemrdclk(dmemrdclk), .dmemwrclk(dmemwrclk), .dmemop(dmemop),
        .dmemwe(dmemwe), .dbgdata(dbgdata)
    );

    imem u_imem (.clk(imemclk), .addr(imemaddr), .dout(imemdataout));

    dmem #(.AW(10)) u_dmem (
        .rdclk(dmemrdclk), .wrclk(dmemwrclk), .we(dmemwe), .memop(dmemop),
        .addr(dmemaddr), .datain(dmemdatain), .dataout(dmemdataout)
    );

    always #5 clock = ~clock;

    task expect_reg;
        input [4:0]  r;
        input [31:0] v;
        begin
            if (uut.u_regfile.regs[r] !== v) begin
                $display("MISMATCH: x%0d = 0x%08h expected 0x%08h",
                         r, uut.u_regfile.regs[r], v);
                errors = errors + 1;
            end
        end
    endtask

    task expect_mem;
        input [9:0]  w;
        input [31:0] v;
        begin
            if (u_dmem.mem[w] !== v) begin
                $display("MISMATCH: dmem[%0d] = 0x%08h expected 0x%08h",
                         w, u_dmem.mem[w], v);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        clock  = 1'b0;
        reset  = 1'b1;

        repeat (3) @(negedge clock);
        reset = 1'b0;

        cycles = 0;
        while ((uut.u_regfile.regs[31] !== 32'h0000_05a5) && (cycles < 400)) begin
            @(negedge clock);
            cycles = cycles + 1;
        end
        repeat (2) @(negedge clock);

        if (uut.u_regfile.regs[31] !== 32'h0000_05a5) begin
            $display("MISMATCH: 未看到停机哨兵 (cycles=%0d, PC=0x%08h)", cycles, uut.PC);
            errors = errors + 1;
        end
        $display("INFO: halt after %0d cycles", cycles);

        //---- RAW 前转 ----
        expect_reg(5'd1,  32'd5);
        expect_reg(5'd2,  32'd10);
        expect_reg(5'd3,  32'd5);
        expect_reg(5'd4,  32'd7);
        expect_reg(5'd5,  32'd0);
        expect_reg(5'd6,  32'd7);

        //---- load-use ----
        expect_reg(5'd7,  32'd64);
        expect_reg(5'd8,  32'd42);
        expect_reg(5'd9,  32'd42);
        expect_reg(5'd10, 32'd84);

        //---- addi/lw/sw 特殊坑 ----
        expect_reg(5'd11, 32'd16);
        expect_reg(5'd12, 32'd42);
        expect_reg(5'd13, 32'd42);

        //---- store 数据前转 ----
        expect_reg(5'd14, 32'h0000_0055);
        expect_reg(5'd15, 32'h0000_0055);

        //---- 分支冲刷 ----
        expect_reg(5'd16, 32'd3);
        expect_reg(5'd17, 32'd102);
        expect_reg(5'd18, 32'd42);

        //---- 其它 ----
        expect_reg(5'd19, 32'h1234_5000);
        expect_reg(5'd20, 32'd80);
        expect_reg(5'd21, 32'h0000_00fa);
        expect_reg(5'd23, 32'd7);

        //---- 存储器 ----
        expect_mem(10'd16, 32'h0000_002a);
        expect_mem(10'd17, 32'h0000_0055);
        expect_mem(10'd4,  32'h0000_002a);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

`timescale 1ns / 1ps
//=======================================================================
// lab10 单周期 CPU 程序级自检 testbench
// 载入 prog10.hex, 运行到 j . 停机, 逐条核对寄存器与数据存储器
//=======================================================================
module cpu_tb;

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

    rv32is uut (
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
        while ((imemdataout !== 32'h0000_006f) && (cycles < 500)) begin
            @(negedge clock);
            cycles = cycles + 1;
        end
        repeat (2) @(negedge clock);

        if (imemdataout !== 32'h0000_006f) begin
            $display("MISMATCH: 未到达停机指令 (cycles=%0d, PC=0x%08h)", cycles, uut.PC);
            errors = errors + 1;
        end

        //---- 算术 / 逻辑 ----
        expect_reg(5'd1,  32'd10);
        expect_reg(5'd2,  32'hffff_fffd);
        expect_reg(5'd3,  32'd7);
        expect_reg(5'd4,  32'd13);
        expect_reg(5'd5,  32'h0000_0008);
        expect_reg(5'd6,  32'hffff_ffff);
        expect_reg(5'd7,  32'hffff_fff7);
        expect_reg(5'd8,  32'h0000_0000);
        expect_reg(5'd9,  32'h0000_0001);
        expect_reg(5'd10, 32'h0000_0001);
        expect_reg(5'd11, 32'h0000_0000);
        expect_reg(5'd12, 32'd40);
        expect_reg(5'd13, 32'h7fff_fffe);
        expect_reg(5'd14, 32'hffff_fffe);
        expect_reg(5'd16, 32'd20);
        expect_reg(5'd17, 32'h7fff_fffe);
        expect_reg(5'd18, 32'hffff_fffe);
        expect_reg(5'd19, 32'h0000_0001);
        expect_reg(5'd20, 32'h0000_0005);
        expect_reg(5'd21, 32'h0000_00fa);
        expect_reg(5'd22, 32'h1234_5000);

        // auipc 相对差
        if ((uut.u_regfile.regs[24] - uut.u_regfile.regs[23]) !== 32'h0000_1004) begin
            $display("MISMATCH: auipc diff = 0x%08h expected 0x00001004",
                     uut.u_regfile.regs[24] - uut.u_regfile.regs[23]);
            errors = errors + 1;
        end

        //---- 访存 ----
        expect_reg(5'd26, 32'd10);
        expect_reg(5'd27, 32'd253);
        expect_reg(5'd28, 32'hffff_fffd);
        expect_reg(5'd29, 32'd10);
        expect_reg(5'd15, 32'd10);
        expect_mem(10'd25, 32'h0000_000a);
        expect_mem(10'd26, 32'h0000_00fd);
        expect_mem(10'd27, 32'h0000_000a);

        //---- 分支 / 跳转 ----
        expect_reg(5'd30, 32'd116);
        expect_reg(5'd31, 32'h0000_00d4);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

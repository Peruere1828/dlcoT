`timescale 1ns / 1ps
// dmem_top 自检: 拨码开关驱动 1/2/4 字节读写, 数码管十六进制显示
module dmem_top_tb;

    reg         CLK100MHZ;
    reg  [15:0] SW;
    wire [7:0]  AN;
    wire [7:0]  HEX;

    integer errors;

    dmem_top #(.SCAN_DIV(0)) uut(
        .CLK100MHZ(CLK100MHZ),
        .SW(SW),
        .AN(AN),
        .HEX(HEX)
    );

    initial CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;

    function [15:0] sw;
        input [7:0] data;
        input [3:0] a;
        input       w;
        input [2:0] op;
        begin
            sw = {data, a, w, op};
        end
    endfunction

    // 在写时钟边沿之后改变 SW, 避免与时钟边沿竞争
    task apply;
        input [7:0] data;
        input [3:0] a;
        input       w;
        input [2:0] op;
        begin
            @(negedge CLK100MHZ);
            #2;
            SW = sw(data, a, w, op);
        end
    endtask

    // 直接检查四个字节通道拼成的 32 位字
    task chk_mem;
        input [3:0]  a;
        input [31:0] exp;
        reg   [31:0] got;
        begin
            got = {uut.u_dmem.mem_b3[a[3:2]],
                   uut.u_dmem.mem_b2[a[3:2]],
                   uut.u_dmem.mem_b1[a[3:2]],
                   uut.u_dmem.mem_b0[a[3:2]]};
            if (got !== exp) begin
                $display("MISMATCH: mem[%0d]=0x%08h expected 0x%08h",
                         a[3:2], got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task chk_read;
        input [3:0]  a;
        input [2:0]  op;
        input [31:0] exp;
        begin
            apply(8'h00, a, 1'b0, op);
            @(posedge CLK100MHZ);
            @(posedge CLK100MHZ);
            #1;
            if (uut.dataout !== exp) begin
                $display("MISMATCH: read addr=%0d op=%b -> 0x%08h expected 0x%08h",
                         a, op, uut.dataout, exp);
                errors = errors + 1;
            end
        end
    endtask

    task do_write;
        input [7:0] data;
        input [3:0] a;
        input [2:0] op;
        begin
            apply(data, a, 1'b1, op);
            repeat (4) @(posedge CLK100MHZ);
            apply(data, a, 1'b0, op);
            @(posedge CLK100MHZ);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        SW = 16'b0;
        #20;

        // 4 字节写 addr0 <- 0xABABABAB
        do_write(8'hAB, 4'h0, 3'b010);
        chk_mem(4'h0, 32'hABABABAB);

        // 读整字 / 读字节带符号扩展
        chk_read(4'h0, 3'b010, 32'hABABABAB);
        chk_read(4'h0, 3'b000, 32'hFFFFFFAB);

        // 2 字节写 addr2 <- 0xCDCD, 低半字保留
        do_write(8'hCD, 4'h2, 3'b001);
        chk_mem(4'h0, 32'hCDCDABAB);

        // 1 字节写 addr1 <- 0x11
        do_write(8'h11, 4'h1, 3'b000);
        chk_mem(4'h0, 32'hCDCD11AB);

        // 1 字节写 addr0 <- 0x22
        do_write(8'h22, 4'h0, 3'b000);
        chk_mem(4'h0, 32'hCDCD1122);

        // 1 字节写 addr3 <- 0x33, 四个字节都被独立改过
        do_write(8'h33, 4'h3, 3'b000);
        chk_mem(4'h0, 32'h33CD1122);

        // 读整字, 以及字节/半字的符号扩展与零扩展
        chk_read(4'h0, 3'b010, 32'h33CD1122);
        chk_read(4'h2, 3'b000, 32'hFFFFFFCD);
        chk_read(4'h2, 3'b100, 32'h000000CD);
        chk_read(4'h0, 3'b001, 32'h00001122);
        chk_read(4'h2, 3'b001, 32'h000033CD);
        chk_read(4'h2, 3'b101, 32'h000033CD);
        chk_read(4'h1, 3'b000, 32'h00000011);
        chk_read(4'h3, 3'b000, 32'h00000033);

        // 负半字 0x8000: 符号扩展与零扩展
        do_write(8'h80, 4'h5, 3'b000);
        chk_mem(4'h4, 32'h00008000);
        chk_read(4'h4, 3'b001, 32'hFFFF8000);
        chk_read(4'h4, 3'b101, 32'h00008000);

        // 低半字写: 只改 addr4 的低 2 字节, 高半字保持 0
        do_write(8'h77, 4'h4, 3'b001);
        chk_mem(4'h4, 32'h00007777);
        chk_read(4'h4, 3'b001, 32'h00007777);

        // 显示: 读回 addr0, 扫描到第 0 位时比较低 4 位与段码
        chk_read(4'h0, 3'b010, 32'h33CD1122);
        wait (uut.dig === 3'd0);
        #1;
        if (uut.nib !== uut.dataout[3:0]) begin
            $display("MISMATCH: nib=%h dataout[3:0]=%h", uut.nib, uut.dataout[3:0]);
            errors = errors + 1;
        end
        if (uut.seg !== 7'b0100100) begin
            $display("MISMATCH: seg=%b expected 0100100", uut.seg);
            errors = errors + 1;
        end
        if (uut.AN !== 8'b1111_1110) begin
            $display("MISMATCH: AN=%b expected 11111110", uut.AN);
            errors = errors + 1;
        end
        if (uut.HEX !== {uut.seg, 1'b1}) begin
            $display("MISMATCH: HEX=%b does not match {seg,1'b1}", uut.HEX);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

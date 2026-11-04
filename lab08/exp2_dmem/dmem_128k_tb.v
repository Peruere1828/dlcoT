`timescale 1ns / 1ps
// dmem_128k 单元自检: 直接用非重复的 32 位 datain 验证四个字节通道,
// 覆盖 1/2/4 字节写的数据映射与读出的符号/零扩展
module dmem_128k_tb;

    reg         clk;
    reg  [31:0] addr;
    reg  [31:0] datain;
    reg  [2:0]  memop;
    reg         we;
    wire [31:0] dataout;

    integer errors;

    dmem_128k uut(
        .addr(addr),
        .dataout(dataout),
        .datain(datain),
        .rdclk(clk),
        .wrclk(~clk),
        .memop(memop),
        .we(we)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task do_write;
        input [31:0] a;
        input [31:0] d;
        input [2:0]  op;
        begin
            @(negedge clk);
            #2;
            addr = a; datain = d; memop = op; we = 1'b1;
            repeat (4) @(posedge clk);
            @(negedge clk);
            #2;
            we = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task chk_read;
        input [31:0] a;
        input [2:0]  op;
        input [31:0] exp;
        begin
            @(negedge clk);
            #2;
            addr = a; memop = op; we = 1'b0;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (dataout !== exp) begin
                $display("MISMATCH: addr=%0d op=%b got=0x%08h exp=0x%08h",
                         a, op, dataout, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        addr = 0; datain = 0; memop = 0; we = 0;
        #20;

        // 4 字节写: 四个字节各不相同
        do_write(32'd0, 32'h11223344, 3'b010);
        chk_read(32'd0, 3'b010, 32'h11223344);

        // 1 字节写: 只改 addr1, 其余字节保留
        do_write(32'd1, 32'h000000AA, 3'b000);
        chk_read(32'd0, 3'b010, 32'h1122AA44);

        // 2 字节写高半字: 应写 datain[15:0], 而不是 datain[31:16]
        do_write(32'd2, 32'h0000BEEF, 3'b001);
        chk_read(32'd0, 3'b010, 32'hBEEFAA44);

        // 2 字节写低半字: 应写 datain[15:0]
        do_write(32'd0, 32'h0000CAFE, 3'b001);
        chk_read(32'd0, 3'b010, 32'hBEEFCAFE);

        // 读字节: 符号扩展与零扩展
        chk_read(32'd2, 3'b000, 32'hFFFFFFEF);
        chk_read(32'd2, 3'b100, 32'h000000EF);
        chk_read(32'd3, 3'b000, 32'hFFFFFFBE);
        chk_read(32'd3, 3'b100, 32'h000000BE);

        // 读半字: 符号扩展与零扩展
        chk_read(32'd0, 3'b001, 32'hFFFFCAFE);
        chk_read(32'd0, 3'b101, 32'h0000CAFE);

        // 另一个整字, 逐字节检查四个通道
        do_write(32'd4, 32'hDEADBEEF, 3'b010);
        chk_read(32'd4, 3'b010, 32'hDEADBEEF);
        chk_read(32'd4, 3'b000, 32'hFFFFFFEF);
        chk_read(32'd5, 3'b000, 32'hFFFFFFBE);
        chk_read(32'd6, 3'b000, 32'hFFFFFFAD);
        chk_read(32'd7, 3'b000, 32'hFFFFFFDE);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

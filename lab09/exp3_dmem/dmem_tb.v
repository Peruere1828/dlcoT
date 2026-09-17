`timescale 1ns / 1ps
//=======================================================================
// lab09 exp3_dmem 自检 testbench
// 覆盖: 字/半字/字节读写, 带符号与无符号扩展, 先读后改字节写,
//       上升沿读 / 下降沿写
//=======================================================================
module dmem_tb;

    reg         clk;
    reg         we;
    reg  [2:0]  memop;
    reg  [31:0] addr;
    reg  [31:0] datain;

    wire [31:0] dataout;

    integer errors;

    dmem #(.AW(8)) uut (
        .rdclk(clk),
        .wrclk(clk),
        .we(we),
        .memop(memop),
        .addr(addr),
        .datain(datain),
        .dataout(dataout)
    );

    always #5 clk = ~clk;

    task mem_write;
        input [31:0] a;
        input [31:0] d;
        input [2:0]  op;
        begin
            addr = a; datain = d; memop = op; we = 1'b1;
            @(posedge clk);       // 先读旧字
            @(negedge clk);       // 下降沿整字写回
            #1;
            we = 1'b0;
        end
    endtask

    task mem_read;
        input [31:0] a;
        input [2:0]  op;
        input [31:0] exp;
        begin
            addr = a; memop = op; we = 1'b0;
            @(posedge clk);       // 上升沿读
            #1;
            if (dataout !== exp) begin
                $display("MISMATCH: addr=0x%08h op=%b read=0x%08h expected 0x%08h",
                         a, op, dataout, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 1'b0;
        we = 1'b0; memop = 3'b010; addr = 32'b0; datain = 32'b0;
        #2;

        //--- 字读写 -------------------------------------------------
        mem_write(32'h0000_0010, 32'h1122_3344, 3'b010);
        mem_read (32'h0000_0010, 3'b010, 32'h1122_3344);

        //--- 四次字节写, 逐个保留其他字节 ---------------------------
        mem_write(32'h0000_0010, 32'h0000_00aa, 3'b000); // -> 1122 33AA
        mem_read (32'h0000_0010, 3'b010, 32'h1122_33aa);
        mem_write(32'h0000_0011, 32'h0000_00bb, 3'b000); // -> 1122 BBAA
        mem_read (32'h0000_0010, 3'b010, 32'h1122_bbaa);
        mem_write(32'h0000_0012, 32'h0000_00cc, 3'b000); // -> 11CC BBAA
        mem_read (32'h0000_0010, 3'b010, 32'h11cc_bbaa);
        mem_write(32'h0000_0013, 32'h0000_00dd, 3'b000); // -> DDCC BBAA
        mem_read (32'h0000_0010, 3'b010, 32'hddcc_bbaa);

        //--- 字节读扩展 ---------------------------------------------
        mem_read (32'h0000_0013, 3'b000, 32'hffff_ffdd); // lb
        mem_read (32'h0000_0013, 3'b100, 32'h0000_00dd); // lbu
        mem_read (32'h0000_0010, 3'b000, 32'hffff_ffaa); // lb
        mem_read (32'h0000_0011, 3'b100, 32'h0000_00bb); // lbu

        //--- 半字写保留另一半 ---------------------------------------
        mem_write(32'h0000_0010, 32'h0000_1234, 3'b001); // -> DDCC 1234
        mem_read (32'h0000_0010, 3'b010, 32'hddcc_1234);
        mem_write(32'h0000_0012, 32'h0000_8001, 3'b001); // -> 8001 1234
        mem_read (32'h0000_0010, 3'b010, 32'h8001_1234);

        //--- 半字读扩展 ---------------------------------------------
        mem_read (32'h0000_0010, 3'b001, 32'h0000_1234); // lh
        mem_read (32'h0000_0012, 3'b001, 32'hffff_8001); // lh 负
        mem_read (32'h0000_0012, 3'b101, 32'h0000_8001); // lhu

        //--- 负字节符号扩展 -----------------------------------------
        mem_write(32'h0000_0020, 32'h0000_0080, 3'b010);
        mem_read (32'h0000_0020, 3'b000, 32'hffff_ff80); // lb
        mem_read (32'h0000_0020, 3'b100, 32'h0000_0080); // lbu

        //--- 半字写在高位, 低位不变 ---------------------------------
        mem_write(32'h0000_0030, 32'hcafe_0000, 3'b010);
        mem_write(32'h0000_0030, 32'h0000_beef, 3'b101); // 无符号半字写
        mem_read (32'h0000_0030, 3'b010, 32'hcafe_beef);
        mem_read (32'h0000_0030, 3'b101, 32'h0000_beef); // lhu

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED: %0d errors", errors);
        $finish;
    end

endmodule

`timescale 1ns / 1ps

module vga_top_tb;

    reg pclk;
    reg reset;

    wire [9:0] h_addr;
    wire [9:0] v_addr;
    wire       hsync;
    wire       vsync;
    wire       valid;

    vga_ctrl uut (
        .pclk(pclk),
        .reset(reset),
        .h_addr(h_addr),
        .v_addr(v_addr),
        .hsync(hsync),
        .vsync(vsync),
        .valid(valid)
    );

    initial pclk = 1'b0;
    always #5 pclk = ~pclk;

    reg [9:0] gx, gy;
    initial begin
        gx = 10'd1;
        gy = 10'd1;
    end

    always @(posedge pclk) begin
        if (reset) begin
            gx <= 10'd1;
            gy <= 10'd1;
        end else begin
            if (gx == 10'd800)
                gx <= 10'd1;
            else
                gx <= gx + 10'd1;
            if (gx == 10'd800) begin
                if (gy == 10'd525)
                    gy <= 10'd1;
                else
                    gy <= gy + 10'd1;
            end
        end
    end

    integer errors;
    integer cycles;

    wire g_h_valid = (gx > 10'd144) && (gx <= 10'd784);
    wire g_v_valid = (gy > 10'd35)  && (gy <= 10'd515);
    wire g_hsync   = (gx > 10'd96);
    wire g_vsync   = (gy > 10'd2);
    wire g_valid   = g_h_valid & g_v_valid;
    wire [9:0] g_h_addr = g_h_valid ? (gx - 10'd145) : 10'd0;
    wire [9:0] g_v_addr = g_v_valid ? (gy - 10'd36)  : 10'd0;

    always @(negedge pclk) begin
        if (!reset) begin
            if (hsync !== g_hsync) begin
                $display("MISMATCH: hsync=%b expected %b at x=%0d", hsync, g_hsync, gx);
                errors = errors + 1;
            end
            if (vsync !== g_vsync) begin
                $display("MISMATCH: vsync=%b expected %b at y=%0d", vsync, g_vsync, gy);
                errors = errors + 1;
            end
            if (valid !== g_valid) begin
                $display("MISMATCH: valid=%b expected %b at x=%0d y=%0d", valid, g_valid, gx, gy);
                errors = errors + 1;
            end
            if (h_addr !== g_h_addr) begin
                $display("MISMATCH: h_addr=%0d expected %0d at x=%0d", h_addr, g_h_addr, gx);
                errors = errors + 1;
            end
            if (v_addr !== g_v_addr) begin
                $display("MISMATCH: v_addr=%0d expected %0d at y=%0d", v_addr, g_v_addr, gy);
                errors = errors + 1;
            end
        end
    end

    initial begin
        reset  = 1'b1;
        errors = 0;
        cycles = 0;
        #100;
        reset = 1'b0;

        while (gy < 10'd45) begin
            @(posedge pclk);
            cycles = cycles + 1;
            if (cycles > 100000) begin
                $display("MISMATCH: timeout waiting for vertical scan");
                errors = errors + 1;
                gy = 10'd45;
            end
        end

        if (h_addr > 10'd639) begin
            $display("MISMATCH: h_addr out of range");
            errors = errors + 1;
        end
        if (v_addr > 10'd479) begin
            $display("MISMATCH: v_addr out of range");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

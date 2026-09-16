module vga_ctrl(
    input        pclk,
    input        reset,
    output [9:0] h_addr,
    output [9:0] v_addr,
    output       hsync,
    output       vsync,
    output       valid
);

    parameter h_frontporch = 96;
    parameter h_active     = 144;
    parameter h_backporch  = 784;
    parameter h_total      = 800;

    parameter v_frontporch = 2;
    parameter v_active     = 35;
    parameter v_backporch  = 515;
    parameter v_total      = 525;

    reg [9:0] x_cnt;
    reg [9:0] y_cnt;
    initial begin
        x_cnt = 10'd1;
        y_cnt = 10'd1;
    end

    always @(posedge pclk) begin
        if (reset)
            x_cnt <= 10'd1;
        else if (x_cnt == h_total)
            x_cnt <= 10'd1;
        else
            x_cnt <= x_cnt + 10'd1;
    end

    always @(posedge pclk) begin
        if (reset)
            y_cnt <= 10'd1;
        else if (x_cnt == h_total) begin
            if (y_cnt == v_total)
                y_cnt <= 10'd1;
            else
                y_cnt <= y_cnt + 10'd1;
        end
    end

    wire h_valid = (x_cnt > h_active) && (x_cnt <= h_backporch);
    wire v_valid = (y_cnt > v_active) && (y_cnt <= v_backporch);

    assign hsync = (x_cnt > h_frontporch);
    assign vsync = (y_cnt > v_frontporch);
    assign valid = h_valid & v_valid;

    assign h_addr = h_valid ? (x_cnt - 10'd145) : 10'd0;
    assign v_addr = v_valid ? (y_cnt - 10'd36)  : 10'd0;

endmodule


module vga_top(
    input        CLK100MHZ,
    input        SW0,
    output       VGA_HS,
    output       VGA_VS,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B
);

    reg [1:0] div_cnt;
    initial div_cnt = 2'd0;
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire pclk = div_cnt[1];

    wire [9:0]  h_addr;
    wire [9:0]  v_addr;
    wire        hsync;
    wire        vsync;
    wire        valid;

    vga_ctrl u_ctrl (
        .pclk(pclk),
        .reset(SW0),
        .h_addr(h_addr),
        .v_addr(v_addr),
        .hsync(hsync),
        .vsync(vsync),
        .valid(valid)
    );

    wire [18:0] mem_addr = {h_addr, v_addr[8:0]};
    wire [11:0] mem_dout;

    blk_mem_gen_0 u_mem (
        .clka(pclk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(mem_addr),
        .dina(12'h000),
        .douta(mem_dout)
    );

    reg valid_d;
    initial valid_d = 1'b0;
    always @(posedge pclk)
        valid_d <= valid;

    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_R  = valid_d ? mem_dout[11:8] : 4'h0;
    assign VGA_G  = valid_d ? mem_dout[7:4]  : 4'h0;
    assign VGA_B  = valid_d ? mem_dout[3:0]  : 4'h0;

endmodule

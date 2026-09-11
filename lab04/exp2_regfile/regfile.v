module regfile(
    input  [4:0]  ra,
    input  [4:0]  rb,
    input  [4:0]  rw,
    input  [31:0] wrdata,
    input         regwr,
    input         wrclk,
    output [31:0] outa,
    output [31:0] outb
);

    reg [31:0] regs[31:0];

    always @(posedge wrclk) begin
        if (regwr && rw != 5'd0)
            regs[rw] <= wrdata;
    end

    assign outa = (ra == 5'd0) ? 32'd0 : regs[ra];
    assign outb = (rb == 5'd0) ? 32'd0 : regs[rb];

endmodule

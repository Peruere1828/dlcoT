module regfile(
    input         WrClk,
    input         RegWr,
    input  [4:0]  Ra,
    input  [4:0]  Rb,
    input  [4:0]  Rw,
    input  [31:0] busW,
    output [31:0] busA,
    output [31:0] busB
);

    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    assign busA = (Ra == 5'd0) ? 32'b0 : regs[Ra];
    assign busB = (Rb == 5'd0) ? 32'b0 : regs[Rb];

    always @(negedge WrClk) begin
        if (RegWr && (Rw != 5'd0))
            regs[Rw] <= busW;
    end

endmodule

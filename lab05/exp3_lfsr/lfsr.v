module lfsr(
    input      [63:0] seed,
    input             clk,
    input             load,
    output reg [63:0] dout
);

    wire feedback = dout[4] ^ dout[3] ^ dout[1] ^ dout[0];

    always @(posedge clk) begin
        if (load)
            dout <= seed;
        else
            dout <= {feedback, dout[63:1]};
    end

endmodule

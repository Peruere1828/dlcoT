module dfa(
    input        clk,
    input  [7:0] data,
    input        reset,
    output reg   result
);

    reg n_parity;
    reg other_parity;

    always @(posedge clk) begin
        if (reset) begin
            n_parity     <= 1'b0;
            other_parity <= 1'b0;
            result       <= 1'b0;
        end else if (data == 8'h00) begin
            result <= n_parity & ~other_parity;
        end else if (data == 8'h6E || data == 8'h4E) begin
            n_parity <= ~n_parity;
        end else begin
            other_parity <= ~other_parity;
        end
    end

endmodule

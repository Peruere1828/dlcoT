module encryption(
    input  [63:0] seed,
    input         clk,
    input         load,
    input  [7:0]  datain,
    output reg    ready,
    output [7:0]  dataout
);

    reg [63:0] lfsr;
    reg [2:0]  cnt;

    wire feedback = lfsr[4] ^ lfsr[3] ^ lfsr[1] ^ lfsr[0];

    always @(posedge clk) begin
        if (load) begin
            lfsr  <= seed;
            cnt   <= 3'd0;
            ready <= 1'b0;
        end else begin
            lfsr <= {feedback, lfsr[63:1]};
            if (cnt == 3'd5) begin
                cnt   <= 3'd0;
                ready <= 1'b1;
            end else begin
                cnt   <= cnt + 3'd1;
                ready <= 1'b0;
            end
        end
    end

    assign dataout = {datain[7:6], datain[5:0] ^ lfsr[63:58]};

endmodule

module attendance(
    input  [127:0] name,
    input          clk,
    input          rst,
    input  [1:0]   cmd,
    output reg [127:0] dataout
);

    reg [127:0] acc;

    always @(posedge clk) begin
        if (rst) begin
            acc     <= 128'b0;
            dataout <= 128'b0;
        end else if (cmd == 2'd1 || cmd == 2'd2) begin
            acc <= acc ^ name;
        end else if (cmd == 2'd0) begin
            dataout <= acc;
        end
    end

endmodule

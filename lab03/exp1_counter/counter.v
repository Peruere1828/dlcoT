module counter(
	input  clk,
	input  en,
	input  rst,
	input  [3:0] cnt_limit,
	output reg [3:0] Q,
	output reg rco
);

	always @(posedge clk) begin
		if (!en) begin
			Q   <= Q;
			rco <= 1'b0;
		end else if (rst) begin
			Q   <= 4'd0;
			rco <= 1'b0;
		end else if (Q == cnt_limit - 4'd1) begin
			Q   <= 4'd0;
			rco <= 1'b1;
		end else begin
			Q   <= Q + 1'b1;
			rco <= 1'b0;
		end
	end

endmodule
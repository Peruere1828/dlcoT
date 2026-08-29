module adder(
	input  [3:0] A,
	input  [3:0] B,
	input  addsub,
	output [3:0] F,
	output cf,
	output zero,
	output of
);

	wire [3:0] bsel;
	wire [3:0] sum;
	wire c4;

	assign bsel        = B ^ {4{addsub}};
	assign {c4, sum}   = A + bsel + addsub;

	assign F    = sum;
	assign cf   = c4 ^ addsub;
	assign of   = (A[3] & bsel[3] & ~sum[3]) | (~A[3] & ~bsel[3] & sum[3]);
	assign zero = ~(|sum);

endmodule

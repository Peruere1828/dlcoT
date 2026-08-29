module alu_s(
	input  [3:0] A,
	input  [3:0] B,
	input  [2:0] ALUctr,
	output reg [3:0] F,
	output reg cf,
	output reg zero,
	output reg of
);

	wire [3:0] bsel;
	wire [3:0] sum_add;
	wire [3:0] sum_sub;
	wire c4_add, c4_sub;
	wire of_add, of_sub;
	wire lt;

	assign bsel          = B ^ 4'hF;
	assign {c4_add, sum_add} = A + B;
	assign {c4_sub, sum_sub} = A + bsel + 1'b1;

	assign of_add = (A[3] & B[3] & ~sum_add[3]) | (~A[3] & ~B[3] & sum_add[3]);
	assign of_sub = (A[3] & bsel[3] & ~sum_sub[3]) | (~A[3] & ~bsel[3] & sum_sub[3]);
	assign lt     = (A[3] != B[3]) ? A[3] : sum_sub[3];

	always @(*) begin
		case (ALUctr)
			3'b000: begin F = sum_add; cf = c4_add;        of = of_add; end
			3'b001: begin F = sum_sub; cf = c4_sub ^ 1'b1; of = of_sub; end
			3'b010: begin F = ~A;      cf = 1'b0;          of = 1'b0;  end
			3'b011: begin F = A & B;   cf = 1'b0;          of = 1'b0;  end
			3'b100: begin F = A | B;   cf = 1'b0;          of = 1'b0;  end
			3'b101: begin F = A ^ B;   cf = 1'b0;          of = 1'b0;  end
			3'b110: begin F = {3'b000, lt}; cf = 1'b0;     of = 1'b0;  end
			default: begin F = (A == B) ? 4'b0001 : 4'b0000; cf = 1'b0; of = 1'b0; end
		endcase
		zero = (F == 4'b0000);
	end

endmodule

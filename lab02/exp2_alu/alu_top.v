module lab02_top(
	input  [10:0] SW,
	output [2:0]  LED,
	output [7:0]  AN,
	output [7:0]  HEX
);

	wire [3:0] F;
	wire cf, of, zero;
	reg  [6:0] seg;

	alu_s u_alu(
		.A(SW[3:0]),
		.B(SW[7:4]),
		.ALUctr(SW[10:8]),
		.F(F),
		.cf(cf),
		.zero(zero),
		.of(of)
	);

	always @(*) begin
		case (F)
			4'h0: seg = 7'b1000000;
			4'h1: seg = 7'b1111001;
			4'h2: seg = 7'b0100100;
			4'h3: seg = 7'b0110000;
			4'h4: seg = 7'b0011001;
			4'h5: seg = 7'b0010010;
			4'h6: seg = 7'b0000010;
			4'h7: seg = 7'b1111000;
			4'h8: seg = 7'b0000000;
			4'h9: seg = 7'b0010000;
			4'hA: seg = 7'b0001000;
			4'hB: seg = 7'b0000011;
			4'hC: seg = 7'b1000110;
			4'hD: seg = 7'b0100001;
			4'hE: seg = 7'b0000110;
			default: seg = 7'b0001110;
		endcase
	end

	assign LED[0] = cf;
	assign LED[1] = of;
	assign LED[2] = zero;

	assign AN  = 8'b11111110;
	assign HEX = {seg, 1'b1};

endmodule


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

	assign bsel            = B ^ 4'hF;
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

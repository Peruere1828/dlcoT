module exp2(
	input  [7:0] X,
	input  en,
	output reg valid,
	output [6:0] F
	);

    //add your code here
    reg [2:0] code;
    wire [6:0] out;
    always @(*) begin
        if (!en) begin
            valid = 1'b0;
            code  = 3'b000;
        end else if (X[7]) begin
            valid = 1'b1;
            code  = 3'd7;
        end else if (X[6]) begin
            valid = 1'b1;
            code  = 3'd6;
        end else if (X[5]) begin
            valid = 1'b1;
            code  = 3'd5;
        end else if (X[4]) begin
            valid = 1'b1;
            code  = 3'd4;
        end else if (X[3]) begin
            valid = 1'b1;
            code  = 3'd3;
        end else if (X[2]) begin
            valid = 1'b1;
            code  = 3'd2;
        end else if (X[1]) begin
            valid = 1'b1;
            code  = 3'd1;
        end else if (X[0]) begin
            valid = 1'b1;
            code  = 3'd0;
        end else begin
            valid = 1'b0;
            code  = 3'b000;
        end
    end

    bcd7seg u_bcd7seg(
        .b({1'b0, code}),
        .h(out)
    );

    assign F = valid ? out : 7'b1111111;

endmodule


module bcd7seg(
	 input  [3:0] b,
	 output reg [6:0] h
	 );

   //add your code here
	always @(*) begin
        case (b)
            4'd0: h = 7'b1000000;
            4'd1: h = 7'b1111001;
            4'd2: h = 7'b0100100;
            4'd3: h = 7'b0110000;
            4'd4: h = 7'b0011001;
            4'd5: h = 7'b0010010;
            4'd6: h = 7'b0000010;
            4'd7: h = 7'b1111000;
            default: h = 7'b1111111;
        endcase
    end

endmodule
module alu(
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  ALUctr,
    output reg [31:0] Result,
    output Zero,
    output Less
);

    // ALUctr[3] 决定: 加减选择 / 比较符号 / 逻辑或算术右移
    wire [31:0] sub_result = A - B;
    wire [31:0] shl        = A << B[4:0];
    wire [31:0] shrl       = A >> B[4:0];
    wire [31:0] shra       = $signed(A) >>> B[4:0];
    wire        slt_signed = ($signed(A) < $signed(B));
    wire        slt_unsign = (A < B);

    assign Zero = (A == B);
    assign Less = ALUctr[3] ? slt_unsign : slt_signed;

    always @(*) begin
        case (ALUctr[2:0])
            3'b000:  Result = ALUctr[3] ? sub_result : (A + B);
            3'b001:  Result = shl;
            3'b010:  Result = ALUctr[3] ? {31'b0, slt_unsign}
                                        : {31'b0, slt_signed};
            3'b011:  Result = B;
            3'b100:  Result = A ^ B;
            3'b101:  Result = ALUctr[3] ? shra : shrl;
            3'b110:  Result = A | B;
            3'b111:  Result = A & B;
            default: Result = 32'b0;
        endcase
    end

endmodule

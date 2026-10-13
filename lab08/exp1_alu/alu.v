module alu(
    input  [31:0] dataa,
    input  [31:0] datab,
    input  [3:0]  ALUctr,
    output        less,
    output        zero,
    output reg [31:0] aluresult
);

    wire [4:0]  shamt  = datab[4:0];
    wire [31:0] sum    = dataa + datab;
    wire [31:0] diff   = dataa - datab;
    wire [31:0] shra   = $signed(dataa) >>> shamt;
    wire        lt_s   = $signed(dataa) < $signed(datab);
    wire        lt_u   = dataa < datab;

    always @(*) begin
        case (ALUctr[2:0])
            3'b000:  aluresult = ALUctr[3] ? diff : sum;
            3'b001:  aluresult = dataa << shamt;
            3'b010:  aluresult = ALUctr[3] ? {31'b0, lt_u} : {31'b0, lt_s};
            3'b011:  aluresult = datab;
            3'b100:  aluresult = dataa ^ datab;
            3'b101:  aluresult = ALUctr[3] ? shra : (dataa >> shamt);
            3'b110:  aluresult = dataa | datab;
            3'b111:  aluresult = dataa & datab;
            default: aluresult = 32'b0;
        endcase
    end

    assign less = ALUctr[3] ? lt_u : lt_s;
    assign zero = (ALUctr[2:0] == 3'b010) ? (dataa == datab)
                                          : (aluresult == 32'b0);

endmodule

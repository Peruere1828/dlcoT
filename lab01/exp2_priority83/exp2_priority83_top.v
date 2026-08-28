module exp2_priority83_top(
    input  [8:0] SW,
    output [4:0] LED,
    output [7:0] AN,
    output [7:0] HEX
);

    reg  [2:0] code;
    reg        valid;
    reg  [6:0] seg;

    always @(*) begin
        if (!SW[8]) begin
            valid = 1'b0;
            code  = 3'b000;
        end else if (SW[7]) begin
            valid = 1'b1;
            code  = 3'd7;
        end else if (SW[6]) begin
            valid = 1'b1;
            code  = 3'd6;
        end else if (SW[5]) begin
            valid = 1'b1;
            code  = 3'd5;
        end else if (SW[4]) begin
            valid = 1'b1;
            code  = 3'd4;
        end else if (SW[3]) begin
            valid = 1'b1;
            code  = 3'd3;
        end else if (SW[2]) begin
            valid = 1'b1;
            code  = 3'd2;
        end else if (SW[1]) begin
            valid = 1'b1;
            code  = 3'd1;
        end else if (SW[0]) begin
            valid = 1'b1;
            code  = 3'd0;
        end else begin
            valid = 1'b0;
            code  = 3'b000;
        end
    end

    always @(*) begin
        case (code)
            3'd0: seg = 7'b1000000;
            3'd1: seg = 7'b1111001;
            3'd2: seg = 7'b0100100;
            3'd3: seg = 7'b0110000;
            3'd4: seg = 7'b0011001;
            3'd5: seg = 7'b0010010;
            3'd6: seg = 7'b0000010;
            3'd7: seg = 7'b1111000;
            default: seg = 7'b1111111;
        endcase
    end

    assign LED[2:0] = code;
    assign LED[3]   = 1'b0;
    assign LED[4]   = valid;

    assign AN  = 8'b11111110;
    assign HEX = {seg, 1'b1};

endmodule
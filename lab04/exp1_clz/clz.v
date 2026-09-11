module clz(
    input  [31:0] in,
    output [4:0]  out,
    output zero
);

    reg [4:0]  result;
    reg [31:0] tmp;

    always @(*) begin
        result = 5'd0;
        tmp    = in;
        if (tmp[31:16] == 16'd0) begin
            result = result + 5'd16;
            tmp    = {16'd0, tmp[15:0]};
        end else begin
            tmp    = {16'd0, tmp[31:16]};
        end
        if (tmp[15:8] == 8'd0) begin
            result = result + 5'd8;
            tmp    = {8'd0, tmp[7:0]};
        end else begin
            tmp    = {8'd0, tmp[15:8]};
        end
        if (tmp[7:4] == 4'd0) begin
            result = result + 5'd4;
            tmp    = {4'd0, tmp[3:0]};
        end else begin
            tmp    = {4'd0, tmp[7:4]};
        end
        if (tmp[3:2] == 2'd0) begin
            result = result + 5'd2;
            tmp    = {2'd0, tmp[1:0]};
        end else begin
            tmp    = {2'd0, tmp[3:2]};
        end
        if (tmp[1] == 1'b0)
            result = result + 5'd1;
    end

    assign zero = ~|in;
    assign out  = zero ? 5'b11111 : result;

endmodule

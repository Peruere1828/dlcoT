module barrel(
    input      [31:0] indata,
    input      [4:0]  shamt,
    input             lr,
    input             al,
    output reg [31:0] outdata
);

    reg [31:0] t;

    always @(*) begin
        t = indata;
        if (lr) begin
            if (shamt[0]) t = {t[30:0], 1'b0};
            if (shamt[1]) t = {t[29:0], 2'b00};
            if (shamt[2]) t = {t[27:0], 4'b0000};
            if (shamt[3]) t = {t[23:0], 8'b00000000};
            if (shamt[4]) t = {t[15:0], 16'b0000000000000000};
        end else if (al) begin
            if (shamt[0]) t = {indata[31], t[31:1]};
            if (shamt[1]) t = {{2{indata[31]}}, t[31:2]};
            if (shamt[2]) t = {{4{indata[31]}}, t[31:4]};
            if (shamt[3]) t = {{8{indata[31]}}, t[31:8]};
            if (shamt[4]) t = {{16{indata[31]}}, t[31:16]};
        end else begin
            if (shamt[0]) t = {1'b0, t[31:1]};
            if (shamt[1]) t = {2'b00, t[31:2]};
            if (shamt[2]) t = {4'b0000, t[31:4]};
            if (shamt[3]) t = {8'b00000000, t[31:8]};
            if (shamt[4]) t = {16'b0000000000000000, t[31:16]};
        end
        outdata = t;
    end

endmodule

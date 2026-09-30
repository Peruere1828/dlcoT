`timescale 1ns / 1ps

module encryption_tb;

    reg        clk;
    reg        load;
    reg [63:0] seed;
    reg [7:0]  datain;
    wire       ready;
    wire [7:0] dataout;

    encryption uut(
        .seed(seed),
        .clk(clk),
        .load(load),
        .datain(datain),
        .ready(ready),
        .dataout(dataout)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer   errors;
    integer   i;
    reg [7:0] msg [0:10];
    reg [7:0] enc [0:10];

    initial begin
        errors = 0;
        seed = 64'ha845fd7183ad75c4;

        msg[0]  = 8'h4e; // N
        msg[1]  = 8'h61; // a
        msg[2]  = 8'h6e; // n
        msg[3]  = 8'h6a; // j
        msg[4]  = 8'h69; // i
        msg[5]  = 8'h6e; // n
        msg[6]  = 8'h67; // g
        msg[7]  = 8'h5f; // _
        msg[8]  = 8'h55; // U
        msg[9]  = 8'h6e; // n
        msg[10] = 8'h69; // i

        enc[0]  = 8'h4c;
        enc[1]  = 8'h7a;
        enc[2]  = 8'h65;
        enc[3]  = 8'h67;
        enc[4]  = 8'h43;
        enc[5]  = 8'h6f;
        enc[6]  = 8'h5c;
        enc[7]  = 8'h67;
        enc[8]  = 8'h7e;
        enc[9]  = 8'h61;
        enc[10] = 8'h51;

        load   = 1'b1;
        datain = 8'h00;
        @(posedge clk);
        @(posedge clk);
        load = 1'b0;
        datain = msg[0];

        for (i = 0; i < 11; i = i + 1) begin
            @(posedge clk);
            while (ready !== 1'b1)
                @(posedge clk);
            if (dataout !== enc[i]) begin
                $display("MISMATCH: char %0d dataout=0x%02h expected 0x%02h", i, dataout, enc[i]);
                errors = errors + 1;
            end else begin
                $display("OK: char %0d dataout=0x%02h", i, dataout);
            end
            if (i < 10)
                datain = msg[i+1];
        end

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

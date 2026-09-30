module keyboard(
    input             clk,
    input             clrn,
    input             ps2_clk,
    input             ps2_data,
    output reg [7:0]  key_count,
    output reg [7:0]  cur_key,
    output     [7:0]  ascii_key
);

    wire [7:0] keydata;
    wire       ready;
    wire       overflow;
    reg        nextdata_n;
    reg        break_flag;
    reg        held;

    //----DO NOT CHANGE BEGIN----
    //scancode to ascii conversion, will be initialized by the testbench
    scancode_ram myram(clk, cur_key, ascii_key);
    //PS2 interface, you may need to specify the inputs and outputs
    ps2_keyboard mykey(clk, clrn, ps2_clk, ps2_data, keydata, ready, nextdata_n, overflow);
    //---DO NOT CHANGE END-----

    always @(posedge clk) begin
        if (clrn == 1'b0) begin
            key_count  <= 8'd0;
            cur_key    <= 8'd0;
            nextdata_n <= 1'b1;
            break_flag <= 1'b0;
            held       <= 1'b0;
        end else begin
            nextdata_n <= 1'b1;
            if ((ready == 1'b1) && (nextdata_n == 1'b1)) begin
                nextdata_n <= 1'b0;
                if (keydata == 8'hf0) begin
                    break_flag <= 1'b1;
                end else if (break_flag == 1'b1) begin
                    break_flag <= 1'b0;
                    held       <= 1'b0;
                    cur_key    <= 8'h00;
                end else if (held == 1'b0) begin
                    held      <= 1'b1;
                    cur_key   <= keydata;
                    key_count <= key_count + 8'd1;
                end
            end
        end
    end

endmodule


//standard ps2 interface, you can keep this
module ps2_keyboard(clk, clrn, ps2_clk, ps2_data, data, ready, nextdata_n, overflow);
    input        clk, clrn, ps2_clk, ps2_data;
    input        nextdata_n;
    output [7:0] data;
    output reg   ready;
    output reg   overflow;
    reg [9:0] buffer;
    reg [7:0] fifo[7:0];
    reg [2:0] w_ptr, r_ptr;
    reg [3:0] count;
    reg [2:0] ps2_clk_sync;

    always @(posedge clk) begin
        ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
    end
    wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

    always @(posedge clk) begin
        if (clrn == 0) begin
            count <= 0; w_ptr <= 0; r_ptr <= 0; overflow <= 0; ready <= 0;
        end else begin
            if (ready) begin
                if (nextdata_n == 1'b0) begin
                    r_ptr <= r_ptr + 3'b1;
                    if (w_ptr == (r_ptr + 1'b1))
                        ready <= 1'b0;
                end
            end
            if (sampling) begin
                if (count == 4'd10) begin
                    if ((buffer[0] == 0) && (ps2_data) && (^buffer[9:1])) begin
                        fifo[w_ptr] <= buffer[8:1];
                        w_ptr <= w_ptr + 3'b1;
                        ready <= 1'b1;
                        overflow <= overflow | (r_ptr == (w_ptr + 3'b1));
                    end
                    count <= 0;
                end else begin
                    buffer[count] <= ps2_data;
                    count <= count + 3'b1;
                end
            end
        end
    end
    assign data = fifo[r_ptr];
endmodule


//simple scancode converter
module scancode_ram(clk, addr, outdata);
    input        clk;
    input [7:0]  addr;
    output reg [7:0] outdata;
    reg [7:0] ascii_tab[255:0];
    always @(posedge clk) begin
        outdata <= ascii_tab[addr];
    end
endmodule

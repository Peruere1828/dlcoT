`timescale 1ns / 1ps
module keyboard_tb();

    reg        clk, clrn;
    reg        kbd_clk, kbd_data;
    wire [7:0] key_count;
    wire [7:0] cur_key;
    wire [7:0] ascii_key;

    integer errors;

    keyboard inst(
        .clk(clk),
        .clrn(clrn),
        .ps2_clk(kbd_clk),
        .ps2_data(kbd_data),
        .key_count(key_count),
        .cur_key(cur_key),
        .ascii_key(ascii_key)
    );

    task tick;
        begin
            clk = 1'b0; #5;
            clk = 1'b1; #5;
        end
    endtask

    task kbd_sendcode;
        input [7:0] code;
        integer i;
        reg [10:0] send_buffer;
        begin
            send_buffer[0]   = 1'b0;
            send_buffer[8:1] = code;
            send_buffer[9]   = ~(^code);
            send_buffer[10]  = 1'b1;
            i = 0;
            while (i < 11) begin
                kbd_data = send_buffer[i];
                tick(); tick(); tick(); kbd_clk = 1'b0;
                tick(); tick(); tick(); kbd_clk = 1'b1;
                i = i + 1;
            end
        end
    endtask

    task check;
        input [7:0] count;
        input [7:0] result_cur;
        input [7:0] result_ascii;
        begin
            if ((result_cur == cur_key) && (count == key_count) && (result_ascii == ascii_key))
                $display("~~~ OK    count=%1d scancode=%2h ascii=%2h", key_count, cur_key, ascii_key);
            else begin
                $display("~~~ ERROR count=%1d scancode=%2h ascii=%2h (expected %1d %2h %2h)",
                         key_count, cur_key, ascii_key, count, result_cur, result_ascii);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh("scancode.hex", inst.myram.ascii_tab);
        clk      = 1'b0;
        kbd_clk  = 1'b1;
        kbd_data = 1'b1;
        errors   = 0;
        clrn = 1'b0;  tick();
        clrn = 1'b1;  tick(); tick();
        check(8'd0, 8'd0, 8'd0);

        kbd_sendcode(8'h1C); // press 'a'
        tick(); tick(); tick();
        check(8'd1, 8'h1C, 8'h61);

        tick(); tick(); tick(); tick();
        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h1C); // release 'a'
        tick(); tick(); tick(); tick();
        check(8'd1, 8'h0, 8'h0);

        kbd_sendcode(8'h1B); // press 's'
        tick(); tick(); tick();
        check(8'd2, 8'h1B, 8'h73);

        kbd_sendcode(8'h1B); // keep 's'
        tick(); tick(); tick();
        check(8'd2, 8'h1B, 8'h73);

        kbd_sendcode(8'h1B); // keep 's'
        tick(); tick(); tick();
        check(8'd2, 8'h1B, 8'h73);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h1B); // release 's'
        tick(); tick(); tick();
        check(8'd2, 8'h0, 8'h0);

        kbd_sendcode(8'h3A); // press 'm'
        tick(); tick(); tick();
        check(8'd3, 8'h3A, 8'h6D);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h3A); // release 'm'
        tick(); tick(); tick();
        check(8'd3, 8'h0, 8'h0);

        kbd_sendcode(8'h29); // press ' '
        tick(); tick(); tick();
        check(8'd4, 8'h29, 8'h20);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h29); // release ' '
        tick(); tick(); tick();
        check(8'd4, 8'h0, 8'h0);

        tick(); tick(); tick();
        kbd_sendcode(8'h1C); // press 'a'
        tick(); tick(); tick();
        check(8'd5, 8'h1C, 8'h61);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h1C); // release 'a'
        tick(); tick(); tick();
        check(8'd5, 8'h0, 8'h0);

        kbd_sendcode(8'h23); // press 'd'
        tick(); tick(); tick();
        check(8'd6, 8'h23, 8'h64);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h23); // release 'd'
        tick(); tick(); tick();
        check(8'd6, 8'h0, 8'h0);

        kbd_sendcode(8'h23); // press 'd'
        tick(); tick(); tick();
        check(8'd7, 8'h23, 8'h64);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h23); // release 'd'
        tick(); tick(); tick();
        check(8'd7, 8'h0, 8'h0);

        kbd_sendcode(8'h29); // press ' '
        tick(); tick(); tick();
        check(8'd8, 8'h29, 8'h20);

        kbd_sendcode(8'hF0);
        kbd_sendcode(8'h29); // release ' '
        tick(); tick(); tick();
        check(8'd8, 8'h0, 8'h0);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule

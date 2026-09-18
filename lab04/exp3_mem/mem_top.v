module mem_top #(
    parameter integer DB_MAX   = 100000,
    parameter integer SCAN_MAX = 25000
)(
    input        CLK100MHZ,
    input  [9:0] SW,
    input        BTNC,
    output       LED0,
    output       LED1,
    output [7:0] AN,
    output [7:0] HEX
);

    reg [25:0] db_cnt;
    reg [1:0]  db_sample;
    reg        btn_d;
    reg        mem_clk;
    initial begin
        db_cnt    = 26'd0;
        db_sample = 2'b00;
        btn_d     = 1'b0;
        mem_clk   = 1'b0;
    end

    always @(posedge CLK100MHZ) begin
        btn_d <= BTNC;
        if (db_cnt == DB_MAX) begin
            db_cnt    <= 26'd0;
            db_sample <= {db_sample[0], btn_d};
            if (db_sample == 2'b11)
                mem_clk <= 1'b1;
            else if (db_sample == 2'b00)
                mem_clk <= 1'b0;
        end else begin
            db_cnt <= db_cnt + 1'b1;
        end
    end

    wire [3:0] addr   = SW[3:0];
    wire [7:0] wrdata = {4'b0000, SW[7:4]};

    reg [7:0] ram [15:0];
    initial begin
        $readmemh("D:/mem1.txt", ram, 0, 15);
    end
    always @(posedge mem_clk) begin
        if (SW[8])
            ram[addr] <= wrdata;
    end
    wire [7:0] rf_out = ram[addr];

    wire [7:0] ram_out;
    blk_mem_gen_0 myram(
        .addra(addr),
        .clka(mem_clk),
        .dina(wrdata),
        .douta(ram_out),
        .ena(1'b1),
        .wea(SW[9])
    );

    assign LED0 = SW[8];
    assign LED1 = SW[9];

    reg [14:0] scan_cnt;
    reg [1:0]  sel;
    initial begin
        scan_cnt = 15'd0;
        sel      = 2'd0;
    end
    always @(posedge CLK100MHZ) begin
        if (scan_cnt == SCAN_MAX) begin
            scan_cnt <= 15'd0;
            sel      <= sel + 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    reg [3:0] digit;
    always @(*) begin
        case (sel)
            2'd0: digit = rf_out[3:0];
            2'd1: digit = rf_out[7:4];
            2'd2: digit = ram_out[3:0];
            2'd3: digit = ram_out[7:4];
            default: digit = 4'h0;
        endcase
    end

    reg [7:0] AN;
    reg [6:0] seg;

    always @(*) begin
        case (sel)
            2'd0: AN = 8'b11111110;
            2'd1: AN = 8'b11111101;
            2'd2: AN = 8'b11111011;
            2'd3: AN = 8'b11110111;
            default: AN = 8'b11111111;
        endcase
    end

    always @(*) begin
        case (digit)
            4'd0:  seg = 7'b1000000;
            4'd1:  seg = 7'b1111001;
            4'd2:  seg = 7'b0100100;
            4'd3:  seg = 7'b0110000;
            4'd4:  seg = 7'b0011001;
            4'd5:  seg = 7'b0010010;
            4'd6:  seg = 7'b0000010;
            4'd7:  seg = 7'b1111000;
            4'd8:  seg = 7'b0000000;
            4'd9:  seg = 7'b0010000;
            4'd10: seg = 7'b0001000;
            4'd11: seg = 7'b0000011;
            4'd12: seg = 7'b1000110;
            4'd13: seg = 7'b0100001;
            4'd14: seg = 7'b0000110;
            4'd15: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

    assign HEX = {seg, 1'b1};

endmodule

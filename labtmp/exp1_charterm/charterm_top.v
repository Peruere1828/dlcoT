module ps2_keyboard(
    input        clk,
    input        clrn,
    input        ps2_clk,
    input        ps2_data,
    input        nextdata_n,
    output [7:0] data,
    output reg   ready,
    output reg   overflow
);

    reg [9:0] buffer;
    reg [7:0] fifo[7:0];
    reg [2:0] w_ptr, r_ptr;
    reg [3:0] count;
    reg [2:0] ps2_clk_sync;

    always @(posedge clk)
        ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};

    wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

    always @(posedge clk) begin
        if (clrn == 0) begin
            count <= 0;
            w_ptr <= 0;
            r_ptr <= 0;
            overflow <= 0;
            ready <= 0;
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


// VGA 640x480 时序, 同时输出字符列号 char_col 与字符内列号 pix_col
module vga_ctrl(
    input        pclk,
    input        reset,
    output [9:0] h_addr,
    output [9:0] v_addr,
    output [6:0] char_col,
    output [3:0] pix_col,
    output       hsync,
    output       vsync,
    output       valid
);

    parameter h_frontporch = 96;
    parameter h_active     = 144;
    parameter h_backporch  = 784;
    parameter h_total      = 800;

    parameter v_frontporch = 2;
    parameter v_active     = 35;
    parameter v_backporch  = 515;
    parameter v_total      = 525;

    reg [9:0] x_cnt;
    reg [9:0] y_cnt;
    reg [6:0] ccol;
    reg [3:0] cpix;

    always @(posedge pclk) begin
        if (reset) begin
            x_cnt <= 10'd1;
            ccol  <= 7'd0;
            cpix  <= 4'd0;
        end else if (x_cnt == h_total) begin
            x_cnt <= 10'd1;
            ccol  <= 7'd0;
            cpix  <= 4'd0;
        end else begin
            x_cnt <= x_cnt + 10'd1;
            if ((x_cnt > h_active) && (x_cnt <= h_backporch)) begin
                if (cpix == 4'd8) begin
                    cpix <= 4'd0;
                    ccol <= ccol + 1'b1;
                end else begin
                    cpix <= cpix + 1'b1;
                end
            end else begin
                cpix <= 4'd0;
                ccol <= 7'd0;
            end
        end
    end

    always @(posedge pclk) begin
        if (reset)
            y_cnt <= 10'd1;
        else if (x_cnt == h_total) begin
            if (y_cnt == v_total)
                y_cnt <= 10'd1;
            else
                y_cnt <= y_cnt + 10'd1;
        end
    end

    wire h_valid = (x_cnt > h_active) && (x_cnt <= h_backporch);
    wire v_valid = (y_cnt > v_active) && (y_cnt <= v_backporch);

    assign hsync = (x_cnt > h_frontporch);
    assign vsync = (y_cnt > v_frontporch);
    assign valid = h_valid & v_valid;

    assign h_addr   = h_valid ? (x_cnt - 10'd145) : 10'd0;
    assign v_addr   = v_valid ? (y_cnt - 10'd36)  : 10'd0;
    assign char_col = ccol;
    assign pix_col  = cpix;

endmodule


// 字符终端顶层
module charterm_top(
    input        CLK100MHZ,
    input        PS2_CLK,
    input        PS2_DATA,
    input        BTNC,
    output       VGA_HS,
    output       VGA_VS,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,
    output [3:0] LED
);

    localparam [7:0] SP    = 8'h20;
    localparam [7:0] CH_GT = 8'h3E;
    localparam [6:0] PROMPT_COLS = 7'd2;

    localparam [3:0] T_CLEAR       = 4'd0;
    localparam [3:0] T_PROMPT      = 4'd1;
    localparam [3:0] T_IDLE        = 4'd2;
    localparam [3:0] T_PRINT       = 4'd3;
    localparam [3:0] T_SCROLL_INIT = 4'd4;
    localparam [3:0] T_SCROLL      = 4'd5;
    localparam [3:0] T_BS          = 4'd6;
    localparam [3:0] T_BSCAN       = 4'd7;

    localparam [2:0] EV_PRINT = 3'd1;
    localparam [2:0] EV_ENTER = 3'd2;
    localparam [2:0] EV_BS    = 3'd3;
    localparam [2:0] EV_LEFT  = 3'd4;
    localparam [2:0] EV_RIGHT = 3'd5;
    localparam [2:0] EV_UP    = 3'd6;
    localparam [2:0] EV_DOWN  = 3'd7;

    // 25MHz 像素时钟
    reg [1:0] div_cnt;
    initial div_cnt = 2'd0;
    always @(posedge CLK100MHZ)
        div_cnt <= div_cnt + 1'b1;

    wire pclk = div_cnt[1];

    wire [9:0] h_addr;
    wire [9:0] v_addr;
    wire [6:0] char_col;
    wire [3:0] pix_col;
    wire       hsync, vsync, valid;

    vga_ctrl u_vga (
        .pclk(pclk),
        .reset(1'b0),
        .h_addr(h_addr),
        .v_addr(v_addr),
        .char_col(char_col),
        .pix_col(pix_col),
        .hsync(hsync),
        .vsync(vsync),
        .valid(valid)
    );

    wire [4:0] v_row  = v_addr[8:4];
    wire [3:0] v_line = v_addr[3:0];

    // 键盘控制器
    wire       kbd_ready;
    wire       kbd_overflow;
    wire [7:0] rx;
    reg        nextdata_n;

    ps2_keyboard u_kbd (
        .clk(CLK100MHZ),
        .clrn(~BTNC),
        .ps2_clk(PS2_CLK),
        .ps2_data(PS2_DATA),
        .data(rx),
        .ready(kbd_ready),
        .nextdata_n(nextdata_n),
        .overflow(kbd_overflow)
    );

    // 扫描码转 ASCII, 带 Shift 大小写/符号变体
    function [7:0] ascii_of;
        input [7:0] code;
        input       sh;
        begin
            case (code)
                8'h1C: ascii_of = sh ? 8'h41 : 8'h61; // a A
                8'h32: ascii_of = sh ? 8'h42 : 8'h62; // b B
                8'h21: ascii_of = sh ? 8'h43 : 8'h63; // c C
                8'h23: ascii_of = sh ? 8'h44 : 8'h64; // d D
                8'h24: ascii_of = sh ? 8'h45 : 8'h65; // e E
                8'h2B: ascii_of = sh ? 8'h46 : 8'h66; // f F
                8'h34: ascii_of = sh ? 8'h47 : 8'h67; // g G
                8'h33: ascii_of = sh ? 8'h48 : 8'h68; // h H
                8'h43: ascii_of = sh ? 8'h49 : 8'h69; // i I
                8'h3B: ascii_of = sh ? 8'h4A : 8'h6A; // j J
                8'h42: ascii_of = sh ? 8'h4B : 8'h6B; // k K
                8'h4B: ascii_of = sh ? 8'h4C : 8'h6C; // l L
                8'h3A: ascii_of = sh ? 8'h4D : 8'h6D; // m M
                8'h31: ascii_of = sh ? 8'h4E : 8'h6E; // n N
                8'h44: ascii_of = sh ? 8'h4F : 8'h6F; // o O
                8'h4D: ascii_of = sh ? 8'h50 : 8'h70; // p P
                8'h15: ascii_of = sh ? 8'h51 : 8'h71; // q Q
                8'h2D: ascii_of = sh ? 8'h52 : 8'h72; // r R
                8'h1B: ascii_of = sh ? 8'h53 : 8'h73; // s S
                8'h2C: ascii_of = sh ? 8'h54 : 8'h74; // t T
                8'h3C: ascii_of = sh ? 8'h55 : 8'h75; // u U
                8'h2A: ascii_of = sh ? 8'h56 : 8'h76; // v V
                8'h1D: ascii_of = sh ? 8'h57 : 8'h77; // w W
                8'h22: ascii_of = sh ? 8'h58 : 8'h78; // x X
                8'h35: ascii_of = sh ? 8'h59 : 8'h79; // y Y
                8'h1A: ascii_of = sh ? 8'h5A : 8'h7A; // z Z
                8'h16: ascii_of = sh ? 8'h21 : 8'h31; // 1 !
                8'h1E: ascii_of = sh ? 8'h40 : 8'h32; // 2 @
                8'h26: ascii_of = sh ? 8'h23 : 8'h33; // 3 #
                8'h25: ascii_of = sh ? 8'h24 : 8'h34; // 4 $
                8'h2E: ascii_of = sh ? 8'h25 : 8'h35; // 5 %
                8'h36: ascii_of = sh ? 8'h5E : 8'h36; // 6 ^
                8'h3D: ascii_of = sh ? 8'h26 : 8'h37; // 7 &
                8'h3E: ascii_of = sh ? 8'h2A : 8'h38; // 8 *
                8'h46: ascii_of = sh ? 8'h28 : 8'h39; // 9 (
                8'h45: ascii_of = sh ? 8'h29 : 8'h30; // 0 )
                8'h0E: ascii_of = sh ? 8'h7E : 8'h60; // ` ~
                8'h4E: ascii_of = sh ? 8'h5F : 8'h2D; // - _
                8'h55: ascii_of = sh ? 8'h2B : 8'h3D; // = +
                8'h54: ascii_of = sh ? 8'h7B : 8'h5B; // [ {
                8'h5B: ascii_of = sh ? 8'h7D : 8'h5D; // ] }
                8'h5D: ascii_of = sh ? 8'h7C : 8'h5C; // \ |
                8'h4C: ascii_of = sh ? 8'h3A : 8'h3B; // ; :
                8'h52: ascii_of = sh ? 8'h22 : 8'h27; // ' "
                8'h41: ascii_of = sh ? 8'h3C : 8'h2C; // , <
                8'h49: ascii_of = sh ? 8'h3E : 8'h2E; // . >
                8'h4A: ascii_of = sh ? 8'h3F : 8'h2F; // / ?
                8'h29: ascii_of = 8'h20;              // space
                8'h5A: ascii_of = 8'h0D;              // Enter
                8'h66: ascii_of = 8'h08;              // BackSpace
                default: ascii_of = 8'h00;
            endcase
        end
    endfunction

    // 键盘字节解析: 处理 F0 断码/E0 扩展码, 产生单周期事件
    reg       shift_l, shift_r, ctrl_l, ctrl_r;
    wire      shift = shift_l | shift_r;
    wire      ctrl  = ctrl_l | ctrl_r;

    reg [1:0] kstate;
    reg       ev_valid;
    reg [2:0] ev_type;
    reg [7:0] ev_ascii;

    wire [7:0] rx_ascii = ascii_of(rx, shift);

    always @(posedge CLK100MHZ) begin
        nextdata_n <= 1'b1;
        ev_valid   <= 1'b0;
        if (BTNC) begin
            kstate  <= 2'd0;
            shift_l <= 1'b0;
            shift_r <= 1'b0;
            ctrl_l  <= 1'b0;
            ctrl_r  <= 1'b0;
        end else if (kbd_ready && nextdata_n) begin
            nextdata_n <= 1'b0;
            case (kstate)
            2'd0: begin
                case (rx)
                    8'hF0:   kstate  <= 2'd1;
                    8'hE0:   kstate  <= 2'd2;
                    8'h12:   shift_l <= 1'b1;
                    8'h59:   shift_r <= 1'b1;
                    8'h14:   ctrl_l  <= 1'b1;
                    default: begin
                        if (rx_ascii == 8'h0D) begin
                            ev_type <= EV_ENTER; ev_valid <= 1'b1;
                        end else if (rx_ascii == 8'h08) begin
                            ev_type <= EV_BS;    ev_valid <= 1'b1;
                        end else if (rx_ascii != 8'h00) begin
                            ev_type  <= EV_PRINT;
                            ev_ascii <= rx_ascii;
                            ev_valid <= 1'b1;
                        end
                    end
                endcase
            end
            2'd1: begin
                if (rx == 8'h12)      shift_l <= 1'b0;
                else if (rx == 8'h59) shift_r <= 1'b0;
                else if (rx == 8'h14) ctrl_l  <= 1'b0;
                kstate <= 2'd0;
            end
            2'd2: begin
                if (rx == 8'hF0)
                    kstate <= 2'd3;
                else begin
                    case (rx)
                        8'h14: ctrl_r <= 1'b1;
                        8'h75: begin ev_type <= EV_UP;    ev_valid <= 1'b1; end
                        8'h6B: begin ev_type <= EV_LEFT;  ev_valid <= 1'b1; end
                        8'h72: begin ev_type <= EV_DOWN;  ev_valid <= 1'b1; end
                        8'h74: begin ev_type <= EV_RIGHT; ev_valid <= 1'b1; end
                        default: ;
                    endcase
                    kstate <= 2'd0;
                end
            end
            2'd3: begin
                if (rx == 8'h14) ctrl_r <= 1'b0;
                kstate <= 2'd0;
            end
            endcase
        end
    end

    // 字符显存: 32 行 x 128 列, 异步读 + 键盘写
    reg [7:0] charmem [0:4095];
    reg        wr_en;
    reg [11:0] wr_addr;
    reg [7:0]  wr_data;

    always @(posedge CLK100MHZ)
        if (wr_en)
            charmem[wr_addr] <= wr_data;

    // 光标与滚屏状态
    reg [3:0]  tstate;
    reg [4:0]  top_row;
    reg [4:0]  cur_row;
    reg [6:0]  cur_col;
    reg [4:0]  cr;
    reg [6:0]  cc;
    reg [6:0]  sc;
    reg [6:0]  scan_col;
    reg [4:0]  row_clear;
    reg [1:0]  prompt_i;
    reg [7:0]  pending_ch;

    wire [5:0] disp_row_sum = {1'b0, top_row} + {1'b0, v_row};
    wire [4:0] disp_phys    = disp_row_sum[4:0];
    wire [5:0] cur_row_sum  = {1'b0, top_row} + {1'b0, cur_row};
    wire [4:0] curs_phys    = cur_row_sum[4:0];
    wire [5:0] bottom_row   = {1'b0, top_row} + 6'd29;
    wire [6:0] scan_next    = scan_col + 7'd1;

    // 写端口: 由状态机组合译码出地址/数据
    always @(*) begin
        wr_en   = 1'b0;
        wr_addr = 12'd0;
        wr_data = SP;
        case (tstate)
            T_CLEAR:  begin wr_en = 1'b1; wr_addr = {cr, cc};                       wr_data = SP; end
            T_PRINT:  begin wr_en = 1'b1; wr_addr = {curs_phys, cur_col};          wr_data = pending_ch; end
            T_PROMPT: begin wr_en = 1'b1; wr_addr = {curs_phys, prompt_i ? 7'd1 : 7'd0};
                          wr_data = prompt_i ? SP : CH_GT; end
            T_SCROLL: begin wr_en = 1'b1; wr_addr = {row_clear, sc};               wr_data = SP; end
            T_BS:     begin wr_en = 1'b1; wr_addr = {curs_phys, cur_col - 7'd1};   wr_data = SP; end
            default: ;
        endcase
    end

    always @(posedge CLK100MHZ) begin
        if (BTNC) begin
            tstate     <= T_CLEAR;
            cr         <= 5'd0;
            cc         <= 7'd0;
            top_row    <= 5'd0;
            cur_row    <= 5'd0;
            cur_col    <= 7'd0;
            sc         <= 7'd0;
            scan_col   <= 7'd0;
            row_clear  <= 5'd0;
            prompt_i   <= 2'd0;
            pending_ch <= SP;
        end else begin
            case (tstate)
            T_IDLE: begin
                if (ev_valid) begin
                    case (ev_type)
                    EV_PRINT: begin
                        pending_ch <= ev_ascii;
                        tstate     <= T_PRINT;
                    end
                    EV_ENTER: begin
                        if (cur_row == 5'd29) begin
                            top_row <= top_row + 1'b1;
                            tstate  <= T_SCROLL_INIT;
                        end else begin
                            cur_row <= cur_row + 1'b1;
                            tstate  <= T_PROMPT;
                        end
                    end
                    EV_BS: begin
                        if (cur_col > PROMPT_COLS)
                            tstate <= T_BS;
                        else if (cur_row != 5'd0) begin
                            cur_row  <= cur_row - 1'b1;
                            scan_col <= 7'd69;
                            tstate   <= T_BSCAN;
                        end
                    end
                    EV_LEFT:  if (cur_col != 7'd0)  cur_col <= cur_col - 1'b1;
                    EV_RIGHT: if (cur_col != 7'd69) cur_col <= cur_col + 1'b1;
                    EV_UP:    if (cur_row != 5'd0)  cur_row <= cur_row - 1'b1;
                    EV_DOWN:  if (cur_row != 5'd29) cur_row <= cur_row + 1'b1;
                    default: ;
                    endcase
                end
            end
            T_CLEAR: begin
                if (cc == 7'd69) begin
                    cc <= 7'd0;
                    if (cr == 5'd29) begin
                        cr       <= 5'd0;
                        cur_row  <= 5'd0;
                        cur_col  <= 7'd0;
                        prompt_i <= 2'd0;
                        tstate   <= T_PROMPT;
                    end else begin
                        cr <= cr + 1'b1;
                    end
                end else begin
                    cc <= cc + 1'b1;
                end
            end
            T_PRINT: begin
                if (cur_col == 7'd69) begin
                    cur_col <= 7'd0;
                    if (cur_row == 5'd29) begin
                        top_row <= top_row + 1'b1;
                        tstate  <= T_SCROLL_INIT;
                    end else begin
                        cur_row <= cur_row + 1'b1;
                        tstate  <= T_PROMPT;
                    end
                end else begin
                    cur_col <= cur_col + 1'b1;
                    tstate  <= T_IDLE;
                end
            end
            T_PROMPT: begin
                if (prompt_i == 2'd0) begin
                    prompt_i <= 2'd1;
                end else begin
                    prompt_i <= 2'd0;
                    cur_col  <= PROMPT_COLS;
                    tstate   <= T_IDLE;
                end
            end
            T_SCROLL_INIT: begin
                row_clear <= bottom_row[4:0];
                sc        <= 7'd0;
                tstate    <= T_SCROLL;
            end
            T_SCROLL: begin
                if (sc == 7'd69) begin
                    sc       <= 7'd0;
                    cur_row  <= 5'd29;
                    cur_col  <= 7'd0;
                    prompt_i <= 2'd0;
                    tstate   <= T_PROMPT;
                end else begin
                    sc <= sc + 1'b1;
                end
            end
            T_BS: begin
                cur_col <= cur_col - 1'b1;
                tstate  <= T_IDLE;
            end
            T_BSCAN: begin
                if ((chr != SP) && (scan_col > PROMPT_COLS)) begin
                    cur_col <= (scan_col == 7'd69) ? 7'd69 : scan_next;
                    tstate  <= T_IDLE;
                end else if (scan_col == 7'd0) begin
                    cur_col <= PROMPT_COLS;
                    tstate  <= T_IDLE;
                end else begin
                    scan_col <= scan_col - 1'b1;
                end
            end
            default: tstate <= T_IDLE;
            endcase
        end
    end

    // 点阵 ROM: font.mem 提供 0x20~0x7F 共 96 字符, 每字符 16 行 x 9bit
    wire [11:0] char_addr = {disp_phys, char_col};
    // 单异步读口: 显示扫描用 char_addr, 退格扫描时临时改读上一行
    wire [11:0] rd_addr   = (tstate == T_BSCAN) ? {curs_phys, scan_col} : char_addr;
    reg  [7:0]  chr;
    always @(*) chr = charmem[rd_addr];
    wire [7:0] cidx_full = chr - 8'h20;
    wire [6:0] cidx      = cidx_full[6:0];
    wire       in_font   = (chr >= 8'h20) && (chr <= 8'h7F);
    wire [7:0] fbase     = {v_line, 3'b0} + {4'b0, v_line};

    reg [143:0] font_rom [0:95];
    initial $readmemh("font.mem", font_rom);
    wire [143:0] font_pack = (cidx < 7'd96) ? font_rom[cidx] : 144'h0;

    wire [8:0]  frow      = font_pack[fbase +: 9];
    wire        font_bit  = in_font ? frow[pix_col] : 1'b0;

    // 光标闪烁, 约 1.5Hz
    reg [25:0] blink_cnt;
    initial blink_cnt = 26'd0;
    always @(posedge CLK100MHZ)
        blink_cnt <= blink_cnt + 1'b1;

    wire cursor_here = (v_row == cur_row) && (char_col == cur_col);
    wire cursor_pix  = cursor_here && blink_cnt[25] && (pix_col == 4'd0);
    wire pixel_on    = valid && (char_col < 7'd70) && (font_bit || cursor_pix);

    assign VGA_HS = hsync;
    assign VGA_VS = vsync;
    assign VGA_R  = pixel_on ? 4'hF : 4'h0;
    assign VGA_G  = pixel_on ? 4'hF : 4'h0;
    assign VGA_B  = pixel_on ? 4'hF : 4'h0;

    assign LED[0] = shift;
    assign LED[1] = ctrl;
    assign LED[2] = kbd_ready;
    assign LED[3] = kbd_overflow;

endmodule

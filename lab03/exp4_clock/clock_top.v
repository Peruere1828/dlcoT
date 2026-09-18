module clock_top #(
    parameter [26:0] CNT1S   = 27'd99_999_999, // 1Hz 节拍: 每 100M 周期一拍
    parameter [19:0] CNT100  = 20'd999_999, // 100Hz 节拍 (秒表百分之一秒)
    parameter [16:0] CNTSCAN = 17'd999, // 100kHz 数码管扫描节拍 (每 10us 换一位)
    parameter [16:0] DBN     = 17'd100_000, // 按键消抖采样间隔 (~1ms)
    parameter integer ALARM_BLINK_BIT = 25 // 闹铃 LED 闪烁相位取自 cnt_1s 的哪一位
)(
    input  CLK100MHZ,
    input  [1:0] SW, // 模式: 00 时钟 / 01 校时 / 10 闹铃设置 / 11 秒表
    input  [1:0] SW_F, // 字段: 00 秒 / 01 分 / 10 时 (校时、闹铃设置用)
    input  SW_AL, // 闹铃开关
    input  BTNC, // 校时/闹铃: 选中字段 +1 ; 秒表: 开始/暂停
    input  BTNL, // 秒表: 清零
    output [3:0] LED, // LED0 闹铃闪烁, LED1 闹铃使能, LED[3:2] 当前模式
    output [7:0] AN,
    output [7:0] HEX
);

    // ---- 按键消抖 → 单周期脉冲 ----
    wire btnc_press, btnl_press;
    debounce_pulse #(DBN) u_db_c(
        .clk(CLK100MHZ),
        .btn(BTNC),
        .pulse(btnc_press)
    );
    debounce_pulse #(DBN) u_db_l(
        .clk(CLK100MHZ),
        .btn(BTNL),
        .pulse(btnl_press)
    );

    // 两片 BCD 加一(带回绕), limit 为满值: 时 8'h23, 分/秒 8'h59, 百分秒 8'h99
    function [7:0] bcd_inc;
        input [7:0] cur;
        input [7:0] limit;
        begin
            if (cur == limit)
                bcd_inc = 8'h00;
            else if (cur[3:0] == 4'd9)
                bcd_inc = {cur[7:4] + 1'b1, 4'd0};
            else
                bcd_inc = {cur[7:4], cur[3:0] + 1'b1};
        end
    endfunction

    // ---- 分频: 1Hz / 100Hz / 100kHz 扫描节拍 ----
    reg [26:0] cnt_1s;
    reg [19:0] cnt_100hz;
    reg [16:0] cnt_scan;
    reg [2:0]  scan_pos;

    wire tick_1hz   = (cnt_1s   == CNT1S);
    wire tick_100hz = (cnt_100hz == CNT100);
    wire tick_scan  = (cnt_scan  == CNTSCAN);

    initial begin
        cnt_1s    = 27'd0;
        cnt_100hz = 20'd0;
        cnt_scan  = 17'd0;
        scan_pos  = 3'd0;
    end
    always @(posedge CLK100MHZ) begin
        if (tick_1hz) cnt_1s <= 27'd0;
        else          cnt_1s <= cnt_1s + 1'b1;
    end
    always @(posedge CLK100MHZ) begin
        if (tick_100hz) cnt_100hz <= 20'd0;
        else            cnt_100hz <= cnt_100hz + 1'b1;
    end
    always @(posedge CLK100MHZ) begin
        if (tick_scan) cnt_scan <= 17'd0;
        else           cnt_scan <= cnt_scan + 1'b1;
    end
    always @(posedge CLK100MHZ)
    if (tick_scan) scan_pos <= scan_pos + 1'b1;

    // 闪烁相位: 板上用 cnt_1s 高位 (~0.33s 亮灭); 仿真中该位恒 0
    wire blink_phase = cnt_1s[25];
    // 闹铃 LED 闪烁相位: 仿真可覆盖 ALARM_BLINK_BIT 取低位以便观测翻转
    wire alarm_blink = cnt_1s[ALARM_BLINK_BIT];

    // ---- 时钟 时:分:秒 (BCD) ----
    wire [1:0] mode = SW;
    wire clock_run  = (mode != 2'b01); // 校时期间暂停走时

    wire adj_inc_sec = btnc_press & (mode == 2'b01) & (SW_F == 2'b00);
    wire adj_inc_min = btnc_press & (mode == 2'b01) & (SW_F == 2'b01);
    wire adj_inc_hr  = btnc_press & (mode == 2'b01) & (SW_F == 2'b10);

    reg [3:0] sec_o, sec_t, min_o, min_t, hr_o, hr_t;
    initial begin
        sec_o = 4'd0; sec_t = 4'd0; min_o = 4'd0; min_t = 4'd0; hr_o = 4'd0; hr_t = 4'd0;
    end

    wire inc_sec = (tick_1hz & clock_run) | adj_inc_sec;
    wire sec_wrap = inc_sec & ({sec_t, sec_o} == 8'h59);
    always @(posedge CLK100MHZ)
        if (inc_sec)
            {sec_t, sec_o} <= bcd_inc({sec_t, sec_o}, 8'h59);

    wire inc_min = sec_wrap | adj_inc_min;
    wire min_wrap = inc_min & ({min_t, min_o} == 8'h59);
    always @(posedge CLK100MHZ)
        if (inc_min)
            {min_t, min_o} <= bcd_inc({min_t, min_o}, 8'h59);

    wire inc_hr = min_wrap | adj_inc_hr;
    always @(posedge CLK100MHZ)
        if (inc_hr)
            {hr_t, hr_o} <= bcd_inc({hr_t, hr_o}, 8'h23);

    // ---- 闹铃时间 (BCD), 与时钟并行 ----
    reg [3:0] al_sec_o, al_sec_t, al_min_o, al_min_t, al_hr_o, al_hr_t;
    initial begin
        al_sec_o = 4'd0; al_sec_t = 4'd0; al_min_o = 4'd0; al_min_t = 4'd0; al_hr_o = 4'd0; al_hr_t = 4'd0;
    end
    always @(posedge CLK100MHZ) begin
        if (btnc_press & (mode == 2'b10) & (SW_F == 2'b00))
            {al_sec_t, al_sec_o} <= bcd_inc({al_sec_t, al_sec_o}, 8'h59);
        if (btnc_press & (mode == 2'b10) & (SW_F == 2'b01))
            {al_min_t, al_min_o} <= bcd_inc({al_min_t, al_min_o}, 8'h59);
        if (btnc_press & (mode == 2'b10) & (SW_F == 2'b10))
            {al_hr_t, al_hr_o} <= bcd_inc({al_hr_t, al_hr_o}, 8'h23);
    end

    // 闹铃匹配到时:分:秒完全一致: 到达该时刻 LED0 闪烁约 1 秒
    wire alarm_match = (hr_t == al_hr_t) & (hr_o == al_hr_o)
    & (min_t == al_min_t) & (min_o == al_min_o)
    & (sec_t == al_sec_t) & (sec_o == al_sec_o);

    // ---- 秒表 (百分之一秒, 可停止/重启) ----
    reg st_run;
    reg [3:0] st_cs_o, st_cs_t, st_sec_o, st_sec_t, st_min_o, st_min_t;
    initial begin
        st_run   = 1'b0;
        st_cs_o  = 4'd0; st_cs_t  = 4'd0;
        st_sec_o = 4'd0; st_sec_t = 4'd0;
        st_min_o = 4'd0; st_min_t = 4'd0;
    end
    wire st_cs_wrap  = ({st_cs_t,  st_cs_o}  == 8'h99);
    wire st_sec_wrap = ({st_sec_t, st_sec_o} == 8'h59);

    always @(posedge CLK100MHZ) begin
        if (btnl_press & (mode == 2'b11)) begin
            st_run <= 1'b0;
            st_cs_o <= 4'd0; st_cs_t <= 4'd0;
            st_sec_o <= 4'd0; st_sec_t <= 4'd0;
            st_min_o <= 4'd0; st_min_t <= 4'd0;
        end else if (btnc_press & (mode == 2'b11)) begin
            st_run <= ~st_run;
        end else if (st_run & tick_100hz) begin
            {st_cs_t, st_cs_o} <= bcd_inc({st_cs_t, st_cs_o}, 8'h99);
            if (st_cs_wrap)
                {st_sec_t, st_sec_o} <= bcd_inc({st_sec_t, st_sec_o}, 8'h59);
            if (st_cs_wrap & st_sec_wrap)
                {st_min_t, st_min_o} <= bcd_inc({st_min_t, st_min_o}, 8'h59);
        end
    end

    // ---- LED ----
    // 到达设定时刻 LED0 随 blink 闪烁 (与当前显示模式无关)
    assign LED[0]   = SW_AL & alarm_match & alarm_blink;
    assign LED[1]   = SW_AL;
    assign LED[3:2] = mode;

    // ---- 显示 ----
    // 模式 10 显示闹铃时间, 其余时间模式显示时钟时间
    wire [3:0] disp_hr_t  = (mode == 2'b10) ? al_hr_t  : hr_t;
    wire [3:0] disp_hr_o  = (mode == 2'b10) ? al_hr_o  : hr_o;
    wire [3:0] disp_min_t = (mode == 2'b10) ? al_min_t : min_t;
    wire [3:0] disp_min_o = (mode == 2'b10) ? al_min_o : min_o;
    wire [3:0] disp_sec_t = (mode == 2'b10) ? al_sec_t : sec_t;
    wire [3:0] disp_sec_o = (mode == 2'b10) ? al_sec_o : sec_o;

    reg [3:0] bcd;
    always @(*) begin
        if (mode == 2'b11) begin
            case (scan_pos)
                3'd0: bcd = st_cs_o;
                3'd1: bcd = st_cs_t;
                3'd2: bcd = st_sec_o;
                3'd3: bcd = st_sec_t;
                3'd4: bcd = st_min_o;
                3'd5: bcd = st_min_t;
                default: bcd = 4'd0;
            endcase
        end else begin
            case (scan_pos)
                3'd0: bcd = disp_sec_o;
                3'd1: bcd = disp_sec_t;
                3'd2: bcd = disp_min_o;
                3'd3: bcd = disp_min_t;
                3'd4: bcd = disp_hr_o;
                3'd5: bcd = disp_hr_t;
                default: bcd = 4'd0;
            endcase
        end
    end

    // 校时/闹铃设置时, 被选中字段按闪烁相位熄灭
    wire adj_mode  = (mode == 2'b01) | (mode == 2'b10);
    wire sel_sec   = (SW_F == 2'b00);
    wire sel_min   = (SW_F == 2'b01);
    wire sel_hr    = (SW_F == 2'b10);
    wire field_digit = (sel_sec & (scan_pos <= 3'd1))
    | (sel_min & (scan_pos >= 3'd2) & (scan_pos <= 3'd3))
    | (sel_hr  & (scan_pos >= 3'd4) & (scan_pos <= 3'd5));
    wire blank = (scan_pos >= 3'd6) | (adj_mode & blink_phase & field_digit);

    reg [6:0] seg;
    always @(*) begin
        if (blank) begin
            seg = 7'b1111111;
        end else begin
            case (bcd)
                4'h0: seg = 7'b1000000;
                4'h1: seg = 7'b1111001;
                4'h2: seg = 7'b0100100;
                4'h3: seg = 7'b0110000;
                4'h4: seg = 7'b0011001;
                4'h5: seg = 7'b0010010;
                4'h6: seg = 7'b0000010;
                4'h7: seg = 7'b1111000;
                4'h8: seg = 7'b0000000;
                4'h9: seg = 7'b0010000;
                default: seg = 7'b0001110;
            endcase
        end
    end

    // 小数点在 AN2/AN4 处点亮, 充当时/分/秒 之间的冒号 (blank 时熄灭)
    wire dp = blank | ~((scan_pos == 3'd2) | (scan_pos == 3'd4));
    // XDC: HEX[7:1]={cg..ca}, HEX[0]=dp, 故为 {seg, dp}
    assign HEX = {seg, dp};
    // 只用 AN5:AN0; scan_pos=6/7 时全部阳极关闭, 避免未用数码管切换发光
    assign AN  = (scan_pos >= 3'd6) ? 8'hFF : ~(8'b0000_0001 << scan_pos);

endmodule

module debounce_pulse #(
    parameter [16:0] DB_MAX = 17'd100000
)(
    input  clk,
    input  btn,
    output reg pulse
);

    reg [16:0] cnt;
    reg [1:0]  sample;
    reg        stable;
    reg        stable_d;
    initial begin
        cnt      = 17'd0;
        sample   = 2'b00;
        stable   = 1'b0;
        stable_d = 1'b0;
    end

    always @(posedge clk) begin
        if (cnt == DB_MAX) begin
            cnt    <= 17'd0;
            sample <= {sample[0], btn};
            if (sample == 2'b11)
                stable <= 1'b1;
            else if (sample == 2'b00)
                stable <= 1'b0;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        stable_d <= stable;
        pulse    <= stable & ~stable_d;
    end

endmodule
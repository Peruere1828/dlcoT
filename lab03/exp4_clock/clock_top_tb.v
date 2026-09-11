`timescale 1ns / 1ps

// 电子时钟 clock_top 自检功能仿真
// 参数覆盖: CNT1S=99(1s=100周期) CNT100=4(100Hz=5周期) CNTSCAN=2(3周期) DBN=4
// 仿真时长需设置约 100us

module clock_top_tb;

	reg CLK100MHZ;
	reg [1:0] SW, SW_F;
	reg SW_AL;
	reg BTNC, BTNL;
	wire [3:0] LED;
	wire [7:0] AN, HEX;

	integer err_cnt;

	clock_top #(
		.CNT1S(27'd99),
		.CNT100(20'd4),
		.CNTSCAN(17'd2),
		.DBN(17'd4)
	) u_dut(
		.CLK100MHZ(CLK100MHZ),
		.SW(SW), .SW_F(SW_F), .SW_AL(SW_AL),
		.BTNC(BTNC), .BTNL(BTNL),
		.LED(LED), .AN(AN), .HEX(HEX)
	);

	always #5 CLK100MHZ = ~CLK100MHZ;

	// ---------- 按键模拟 ----------
	task press_c;
		begin
			BTNC = 1'b1;
			repeat (15) @(posedge CLK100MHZ);
			BTNC = 1'b0;
			repeat (15) @(posedge CLK100MHZ);
		end
	endtask

	task press_l;
		begin
			BTNL = 1'b1;
			repeat (15) @(posedge CLK100MHZ);
			BTNL = 1'b0;
			repeat (15) @(posedge CLK100MHZ);
		end
	endtask

	// ---------- 段码 <-> 数字 ----------
	function [6:0] seg_of;
		input [3:0] v;
		begin
			case (v)
				4'h0: seg_of = 7'b1000000;
				4'h1: seg_of = 7'b1111001;
				4'h2: seg_of = 7'b0100100;
				4'h3: seg_of = 7'b0110000;
				4'h4: seg_of = 7'b0011001;
				4'h5: seg_of = 7'b0010010;
				4'h6: seg_of = 7'b0000010;
				4'h7: seg_of = 7'b1111000;
				4'h8: seg_of = 7'b0000000;
				4'h9: seg_of = 7'b0010000;
				default: seg_of = 7'b0001110;
			endcase
		end
	endfunction

	function [3:0] dig_of;
		input [6:0] s;
		begin
			case (s)
				7'b1000000: dig_of = 4'h0;
				7'b1111001: dig_of = 4'h1;
				7'b0100100: dig_of = 4'h2;
				7'b0110000: dig_of = 4'h3;
				7'b0011001: dig_of = 4'h4;
				7'b0010010: dig_of = 4'h5;
				7'b0000010: dig_of = 4'h6;
				7'b1111000: dig_of = 4'h7;
				7'b0000000: dig_of = 4'h8;
				7'b0010000: dig_of = 4'h9;
				default:    dig_of = 4'hF;
			endcase
		end
	endfunction

	// ---------- 显示采样 ----------
	reg [7:0] got_hex [0:7];

	task sample_disp;
		integer i;
		begin
			for (i = 0; i < 8; i = i + 1) begin
				while (AN !== ~(8'b0000_0001 << i)) @(posedge CLK100MHZ);
				got_hex[i] = HEX;
			end
		end
	endtask

	task check_digits; // pos0..7 期望段码; 小数点在 pos2/4 亮
		input [6:0] d0, d1, d2, d3, d4, d5, d6, d7;
		integer i;
		reg [6:0] exp_seg [0:7];
		reg [7:0] exp_hex;
		begin
			exp_seg[0] = d0; exp_seg[1] = d1; exp_seg[2] = d2; exp_seg[3] = d3;
			exp_seg[4] = d4; exp_seg[5] = d5; exp_seg[6] = d6; exp_seg[7] = d7;
			sample_disp();
			for (i = 0; i < 8; i = i + 1) begin
				exp_hex = { (i == 2 || i == 4) ? 1'b0 : 1'b1, exp_seg[i] };
				if (got_hex[i] !== exp_hex) begin
					err_cnt = err_cnt + 1;
					$display("FAIL: pos %0d got %b exp %b", i, got_hex[i], exp_hex);
				end
			end
		end
	endtask

	// 时钟/闹铃显示: AN5:AN4=时, AN3:AN2=分, AN1:AN0=秒
	task check_clock;
		input [3:0] h_t, h_o, m_t, m_o, s_t, s_o;
		begin
			check_digits(seg_of(s_o), seg_of(s_t), seg_of(m_o), seg_of(m_t),
			             seg_of(h_o), seg_of(h_t), 7'b1111111, 7'b1111111);
		end
	endtask

	// 秒表显示: AN5:AN4=分, AN3:AN2=秒, AN1:AN0=百分之一秒
	task check_sw;
		input [3:0] m_t, m_o, s_t, s_o, c_t, c_o;
		begin
			check_digits(seg_of(c_o), seg_of(c_t), seg_of(s_o), seg_of(s_t),
			             seg_of(m_o), seg_of(m_t), 7'b1111111, 7'b1111111);
		end
	endtask

	task read_sw;
		output [3:0] mo, mt, so, st, co, ct;
		begin
			sample_disp();
			co = dig_of(got_hex[0][6:0]);
			ct = dig_of(got_hex[1][6:0]);
			so = dig_of(got_hex[2][6:0]);
			st = dig_of(got_hex[3][6:0]);
			mo = dig_of(got_hex[4][6:0]);
			mt = dig_of(got_hex[5][6:0]);
		end
	endtask

	task check_led;
		input [1:0] m;
		begin
			if (LED[3:2] !== m) begin
				err_cnt = err_cnt + 1;
				$display("FAIL: LED[3:2]=%b expected %b", LED[3:2], m);
			end
			if (LED[1] !== SW_AL) begin
				err_cnt = err_cnt + 1;
				$display("FAIL: LED1=%b expected %b", LED[1], SW_AL);
			end
		end
	endtask

	// ---------- 主流程 ----------
	initial begin
		CLK100MHZ = 1'b0;
		SW = 2'b00; SW_F = 2'b00; SW_AL = 1'b0;
		BTNC = 1'b0; BTNL = 1'b0;
		err_cnt = 0;

		repeat (4) @(posedge CLK100MHZ);

		// 1) 初始 00:00:00
		check_clock(0,0,0,0,0,0);
		check_led(2'b00);

		// 2) 走 2 秒 (CNT1S=99, 周期100) -> 00:00:02
		repeat (200) @(posedge CLK100MHZ);
		check_clock(0,0,0,0,0,2);

		// 3) 校时: 时=23, 分=59, 秒=59
		SW = 2'b01;
		SW_F = 2'b10;
		repeat (23) press_c();
		SW_F = 2'b01;
		repeat (59) press_c();
		SW_F = 2'b00;
		repeat (59) press_c();
		check_clock(2,3,5,9,5,9);
		check_led(2'b01);

		// 4) 回时钟模式, 走 3 秒 -> 23:59:59 + 3s = 00:00:02 (23->00 回绕)
		SW = 2'b00;
		repeat (300) @(posedge CLK100MHZ);
		check_clock(0,0,0,0,0,2);

		// 5) 闹铃设置: 默认 00:00:00, 秒设为 07
		SW = 2'b10;
		check_clock(0,0,0,0,0,0);
		SW_F = 2'b00;
		repeat (7) press_c();
		check_clock(0,0,0,0,0,7);
		check_led(2'b10);
		SW_AL = 1'b1;
		check_led(2'b10);
		// 仿真中 blink 位恒 0, LED0 必为 0; 闹铃闪烁在板上验证
		if (LED[0] !== 1'b0) begin
			err_cnt = err_cnt + 1;
			$display("FAIL: LED0 must be 0 in sim (blink off) got %b", LED[0]);
		end

		// 6) 秒表: 开始 -> 计时 -> 暂停保持 -> 清零
		SW = 2'b11;
		check_led(2'b11);
		check_sw(0,0,0,0,0,0);
		press_c();                        // 开始
		repeat (100) @(posedge CLK100MHZ);
		press_c();                        // 暂停
		begin
			reg [3:0] mo, mt, so, st, co, ct;
			integer cs1;
			read_sw(mo, mt, so, st, co, ct);
			cs1 = ct * 10 + co;
			if (mo !== 4'd0 || mt !== 4'd0 || so !== 4'd0 || st !== 4'd0) begin
				err_cnt = err_cnt + 1;
				$display("FAIL: stopwatch min/sec %0d%0d:%0d%0d expected 00:00", mt, mo, st, so);
			end
			if (cs1 < 20 || cs1 > 30) begin
				err_cnt = err_cnt + 1;
				$display("FAIL: stopwatch cs=%0d out of [20,30]", cs1);
			end
			// 暂停后应保持不动
			repeat (30) @(posedge CLK100MHZ);
			read_sw(mo, mt, so, st, co, ct);
			if (ct * 10 + co !== cs1) begin
				err_cnt = err_cnt + 1;
				$display("FAIL: stopwatch not paused (cs changed)");
			end
			// 清零
			press_l();
			check_sw(0,0,0,0,0,0);
			// 清零后应停止
			repeat (30) @(posedge CLK100MHZ);
			check_sw(0,0,0,0,0,0);
		end

		if (err_cnt == 0)
			$display("TEST PASSED: clock_top");
		else
			$display("TEST FAILED: %0d errors", err_cnt);
		$finish;
	end

endmodule
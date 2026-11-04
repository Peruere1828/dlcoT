// 实验十一 在线测试选做: 简单图灵机
// 纸带字符: 8'h00 空白, 8'h28 '(', 8'h29 ')', 8'h54 'T', 8'h46 'F'
// 状态 0~4 对应参考设计中的第 1~5 步, 状态 7 为停机状态。
//
// 状态转移表 (本模块实现):
//   状态 0: 空白 -> 7/T/R, '(' -> 1/空白/R, ')' -> 7/F/R
//   状态 1: 空白 -> 7/F/R, '(' -> 1/'('/R,  ')' -> 2/')'/R
//   状态 2: 空白 -> 3/空白/L, '(' -> 7/F/R, ')' -> 2/')'/R
//   状态 3: ')'  -> 4/空白/L
//   状态 4: 空白 -> 0/空白/R, '(' -> 4/'('/L, ')' -> 4/')'/L
//   状态 7: 保持停机
//
// 输出在时钟上升沿更新, 与状态寄存器同步。进入状态 7 的同一拍 dataout
// 给出 T/F 并拉高 halt, 评测端先应用这一步的写入和移动再停机。

module tm(
    input        clk,
    input  [7:0] datain,
    input        reset,
    output reg [7:0] dataout,
    output reg       move,
    output reg       halt
);

    localparam [2:0] S0 = 3'd0;
    localparam [2:0] S1 = 3'd1;
    localparam [2:0] S2 = 3'd2;
    localparam [2:0] S3 = 3'd3;
    localparam [2:0] S4 = 3'd4;
    localparam [2:0] S7 = 3'd7;

    localparam [7:0] BLANK = 8'h00;
    localparam [7:0] LP    = 8'h28; // '('
    localparam [7:0] RP    = 8'h29; // ')'
    localparam [7:0] TRUE  = 8'h54; // 'T'
    localparam [7:0] FALSE = 8'h46; // 'F'

    reg [2:0] state;

    always @(posedge clk) begin
        if (reset) begin
            state   <= S0;
            dataout <= BLANK;
            move    <= 1'b0;
            halt    <= 1'b0;
        end else begin
            case (state)
            S0: begin
                case (datain)
                BLANK: begin state <= S7; dataout <= TRUE;  move <= 1'b0; halt <= 1'b1; end
                LP:    begin state <= S1; dataout <= BLANK; move <= 1'b0; halt <= 1'b0; end
                RP:    begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                default: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                endcase
            end
            S1: begin
                case (datain)
                BLANK: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                LP:    begin state <= S1; dataout <= LP;    move <= 1'b0; halt <= 1'b0; end
                RP:    begin state <= S2; dataout <= RP;    move <= 1'b0; halt <= 1'b0; end
                default: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                endcase
            end
            S2: begin
                case (datain)
                BLANK: begin state <= S3; dataout <= BLANK; move <= 1'b1; halt <= 1'b0; end
                LP:    begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                RP:    begin state <= S2; dataout <= RP;    move <= 1'b0; halt <= 1'b0; end
                default: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                endcase
            end
            S3: begin
                case (datain)
                RP:    begin state <= S4; dataout <= BLANK; move <= 1'b1; halt <= 1'b0; end
                default: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                endcase
            end
            S4: begin
                case (datain)
                BLANK: begin state <= S0; dataout <= BLANK; move <= 1'b0; halt <= 1'b0; end
                LP:    begin state <= S4; dataout <= LP;    move <= 1'b1; halt <= 1'b0; end
                RP:    begin state <= S4; dataout <= RP;    move <= 1'b1; halt <= 1'b0; end
                default: begin state <= S7; dataout <= FALSE; move <= 1'b0; halt <= 1'b1; end
                endcase
            end
            S7: begin
                // 已经停机; 若评测端仍在时钟沿执行动作, 只写空白并左移,
                // 不会覆盖上一步写入的 T/F, 也不会继续向右越界。
                state   <= S7;
                dataout <= BLANK;
                move    <= 1'b1;
                halt    <= 1'b1;
            end
            default: begin
                state   <= S7;
                dataout <= FALSE;
                move    <= 1'b0;
                halt    <= 1'b1;
            end
            endcase
        end
    end

endmodule

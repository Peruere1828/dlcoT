# hazard.S : 流水线冒险的边界情况, 由 rv32ip_hazard_tb.v 检查
#
# 覆盖四类前转与阻塞的组合:
#   1. load-use: lw 后面紧跟使用结果的 ALU 指令, 阻塞一个周期
#   2. bne 紧跟在 ALU 结果之后, 走 MEM->EX 前转
#   3. load-use 与分支同时发生: 分支用旧数据算出的结果不能生效
#   4. jalr 的 rs1 与上一条指令相隔 1 条, 走 WB->EX 前转
#   5. sw 的数据来源相隔 1 条指令, 走 MEM->EX 前转
#
# 期望结果由 rv32ip_hazard_tb.v 逐项检查, 最后停在 hang 循环.

    addi x1, x0, 16
    addi x2, x0, 0x100
    sw   x1, 0(x2)          # mem[0x100] = 16
    lw   x3, 0(x2)          # x3 = 16
    add  x4, x3, x3         # load-use, x4 = 32
    bne  x4, x0, L1         # 分支紧跟 ALU 结果, 必须跳转
    addi x5, x0, 1          # 不应该执行
L1:
    addi x5, x0, 2
    lw   x6, 0(x2)          # x6 = 16
    beq  x6, x0, L2         # load-use + 分支, 旧数据会让它误跳
    addi x7, x0, 7          # 必须执行
L2:
    addi x8, x0, 8
    addi x9, x0, 0x58
    jalr x0, 0(x9)          # rs1 只隔一条指令, 走 WB->EX 前转
    addi x10, x0, 0xBAD     # 不应该执行
    addi x11, x0, 0xBAD
    addi x12, x0, 0xBAD
    addi x13, x0, 0xBAD
    addi x14, x0, 0xBAD
    addi x15, x0, 0xBAD
    addi x16, x0, 0xBAD
    addi x17, x0, 0xBAD
target:
    addi x10, x0, 0x123
    sw   x10, 4(x2)         # mem[0x104] = 0x123
hang:
    j    hang

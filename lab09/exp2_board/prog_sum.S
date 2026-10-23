# prog_sum.S : 程序 0, 求 1+2+...+n
# n = SW[11:0] (0x000~0xFFF), 二进制结果写到 0x2004
    lui  s0, 0x2            # s0 = 0x2000, 开关和显示端口
    lw   a1, 0(s0)          # a1 = SW
    slli a1, a1, 20
    srli a1, a1, 20         # n = SW[11:0]
    li   a0, 0              # sum = 0
    beq  a1, x0, sum_done   # n == 0 时直接结束
sum_loop:
    add  a0, a0, a1         # sum += n
    addi a1, a1, -1         # n--
    bne  a1, x0, sum_loop
sum_done:
    sw   a0, 4(s0)          # 结果送到显示端口, 数码管以十六进制显示
hang:
    j    hang               # 停机

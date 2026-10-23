# prog_fib.S : 程序 1, 斐波那契数列第 n 项
# F(0)=0, F(1)=1, F(n)=F(n-1)+F(n-2)
# n = SW[11:0], 二进制结果写到 0x2004
    lui  s0, 0x2
    lw   a1, 0(s0)
    slli a1, a1, 20
    srli a1, a1, 20         # n = SW[11:0]
    li   a0, 0              # f0 = 0
    li   a2, 1              # f1 = 1
    beq  a1, x0, fib_done   # n == 0 时结果为 0
fib_loop:
    add  a3, a0, a2         # f2 = f0 + f1
    mv   a0, a2             # f0 = f1
    mv   a2, a3             # f1 = f2
    addi a1, a1, -1
    bne  a1, x0, fib_loop
fib_done:
    sw   a0, 4(s0)          # 结果送到显示端口, 数码管以十六进制显示
hang:
    j    hang

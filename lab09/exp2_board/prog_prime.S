#=======================================================================
# prog_prime.S : 上板程序 2, 判断 n 是否为素数
#   n 从 0x2000 读取, 结果 1/0 写到 0x2004
#   没有除法指令, 用重复减法求余数
#=======================================================================
    lui  t0, 0x2
    lw   a1, 0(t0)
    andi a1, a1, 15         # n = SW[3:0]
    addi a0, x0, 0          # 结果先置 0
    addi t1, x0, 2          # i = 2
    blt  a1, t1, done       # n < 2, 不是素数
    beq  a1, t1, prime      # n == 2, 是素数
check:
    bge  t1, a1, prime      # i >= n, 没有找到因子
    mv   t2, a1             # t2 = n, 用减法求 n mod i
modloop:
    beq  t2, x0, done       # 余数为 0, 有因子
    blt  t2, t1, next       # 余数小于 i, 换下一个 i
    sub  t2, t2, t1
    j    modloop
next:
    addi t1, t1, 1
    j    check
prime:
    addi a0, x0, 1
done:
    sw   a0, 4(t0)
hang:
    j    hang

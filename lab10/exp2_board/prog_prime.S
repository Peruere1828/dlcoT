# prog_prime.S : 程序 3, 判断 n 是否素数
# n = SW[11:0], 结果 1/0 写到 0x2004
# 没有除法指令, 用重复减法求余数
    lui  s0, 0x2
    lw   a1, 0(s0)
    slli a1, a1, 20
    srli a1, a1, 20         # n = SW[11:0]
    li   a0, 0              # 结果先置 0
    li   t1, 2              # i = 2
    blt  a1, t1, prime_done # n < 2, 不是素数
    beq  a1, t1, prime_yes  # n == 2, 是素数
check:
    bge  t1, a1, prime_yes  # i >= n, 没有找到因子
    mv   t2, a1             # t2 = n, 用减法求 n mod i
mod_loop:
    beq  t2, x0, prime_done # 余数为 0, 有因子
    blt  t2, t1, next_i     # 余数小于 i, 换下一个 i
    sub  t2, t2, t1
    j    mod_loop
next_i:
    addi t1, t1, 1
    j    check
prime_yes:
    li   a0, 1
prime_done:
    sw   a0, 4(s0)
hang:
    j    hang

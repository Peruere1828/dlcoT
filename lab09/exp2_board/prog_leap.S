# prog_leap.S : 程序 2, 判断年份 n 是否闰年
# 能被 4 整除且不能被 100 整除, 或者能被 400 整除
# n = SW[11:0], 结果 1/0 写到 0x2004
    lui  s0, 0x2
    lw   a1, 0(s0)
    slli a1, a1, 20
    srli a1, a1, 20         # n = SW[11:0]
    li   a0, 0              # 先假设不是闰年
    andi t0, a1, 3
    bne  t0, x0, leap_done  # n 不能被 4 整除
    mv   t0, a1
    li   t1, 100
    jal  ra, mod_sub        # t0 = n mod 100
    bne  t0, x0, leap_yes   # 不能被 100 整除, 是闰年
    mv   t0, a1
    li   t1, 400
    jal  ra, mod_sub        # t0 = n mod 400
    bne  t0, x0, leap_done  # 能被 100 整除但不能被 400 整除
leap_yes:
    li   a0, 1
leap_done:
    sw   a0, 4(s0)
hang:
    j    hang

# mod_sub: t0 = t0 mod t1, 用重复减法
mod_sub:
mod_loop:
    blt  t0, t1, mod_ret
    sub  t0, t0, t1
    j    mod_loop
mod_ret:
    ret

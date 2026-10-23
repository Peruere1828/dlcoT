#=======================================================================
# prog_gcd.S : 上板程序 3, 求最大公约数 gcd(a,b)
#   a = SW[3:0], b = SW[7:4], 结果写到 0x2004
#   辗转相减
#=======================================================================
    lui  t0, 0x2
    lw   a0, 0(t0)
    andi a0, a0, 15         # a = SW[3:0]
    lw   a1, 0(t0)
    srli a1, a1, 4
    andi a1, a1, 15         # b = SW[7:4]
    beq  a0, x0, azero      # a == 0 时 gcd = b
    beq  a1, x0, done       # b == 0 时 gcd = a
loop:
    beq  a0, a1, done
    blt  a0, a1, less
    sub  a0, a0, a1
    j    loop
less:
    sub  a1, a1, a0
    j    loop
azero:
    mv   a0, a1
done:
    sw   a0, 4(t0)
hang:
    j    hang

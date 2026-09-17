#=======================================================================
# lab10 单周期 CPU 程序级自检程序 (tools/rvasm.py 汇编)
# 覆盖 RV32I 37 条中的代表性子集, 结果由 cpu_tb.v 逐条核对
# 寄存器分配见报告/README, 最终值在 cpu_tb.v 中列出
#=======================================================================

#---- 算术 / 逻辑 ----
    addi  x1, x0, 10
    addi  x2, x0, -3
    add   x3, x1, x2        # 7
    sub   x4, x1, x2        # 13
    and   x5, x1, x2        # 8
    or    x6, x1, x2        # 0xFFFFFFFF
    xor   x7, x1, x2        # 0xFFFFFFF7
    slt   x8, x1, x2        # 0
    slt   x9, x2, x1        # 1
    sltu  x10, x1, x2       # 1
    sltu  x11, x2, x1       # 0
    slli  x12, x1, 2        # 40
    srli  x13, x2, 1        # 0x7FFFFFFE
    srai  x14, x2, 1        # 0xFFFFFFFE
    addi  x15, x0, 1
    sll   x16, x1, x15      # 20
    srl   x17, x2, x15      # 0x7FFFFFFE
    sra   x18, x2, x15      # 0xFFFFFFFE
    slti  x19, x2, 0        # 1
    xori  x20, x1, 0xF      # 5
    ori   x21, x1, 0xF0     # 250
    lui   x22, 0x12345      # 0x12345000
    auipc x23, 0
    auipc x24, 1            # x24 - x23 = 0x1004

#---- 访存 ----
    addi  x25, x0, 100
    sw    x1, 0(x25)
    lw    x26, 0(x25)       # 10
    sb    x2, 4(x25)
    lbu   x27, 4(x25)       # 253
    lb    x28, 4(x25)       # 0xFFFFFFFD
    sh    x1, 8(x25)
    lhu   x29, 8(x25)       # 10
    lh    x15, 8(x25)       # 10 (x15 作为移位量已用完)

#---- 条件分支 ----
    addi  x30, x0, 0
    beq   x1, x1, b1
    addi  x30, x0, 99
b1: addi  x30, x30, 1
    bne   x1, x2, b2
    addi  x30, x0, 99
b2: addi  x30, x30, 1
    blt   x2, x1, b3
    addi  x30, x0, 99
b3: addi  x30, x30, 1
    bge   x1, x2, b4
    addi  x30, x0, 99
b4: addi  x30, x30, 1
    bltu  x1, x2, b5
    addi  x30, x0, 99
b5: addi  x30, x30, 1
    bgeu  x2, x1, b6
    addi  x30, x0, 99
b6: addi  x30, x30, 1

#---- jal / jalr ----
    jal   x31, sub1
ret1: addi  x30, x30, 10
    j     done
sub1: addi  x30, x30, 100
    jalr  x0, 0(x31)

done:
    j     done

#=======================================================================
# lab11 五段流水线自检程序 (tools/rvasm.py 汇编)
# 重点: RAW 前转 (MEM->EX / WB->EX), load-use 阻塞,
#       特殊坑 addi/lw/sw, store 数据前转, 分支冲刷
#=======================================================================

#---- RAW MEM->EX (背靠背) ----
    addi x1, x0, 5          # x1=5
    add  x2, x1, x1         # x2=10
    sub  x3, x2, x1         # x3=5

#---- RAW WB->EX (间隔 2) ----
    addi x4, x0, 7          # x4=7
    addi x5, x0, 0          # x5=0
    add  x6, x4, x5         # x6=7

#---- load-use 阻塞 ----
    addi x7, x0, 64         # x7=64
    addi x8, x0, 42         # x8=42
    sw   x8, 0(x7)          # mem[64]=42
    lw   x9, 0(x7)          # x9=42
    add  x10, x9, x9        # x10=84

#---- 特殊坑: 地址来源 addi + 数据来源 load 的 sw ----
    addi x11, x0, 16        # x11=16
    lw   x12, 0(x7)         # x12=42
    sw   x12, 0(x11)        # mem[16]=42
    lw   x13, 0(x11)        # x13=42

#---- store 数据前转 ----
    addi x14, x0, 0x55      # x14=85
    sw   x14, 4(x7)         # mem[68]=85
    lw   x15, 4(x7)         # x15=85

#---- 分支冲刷两条指令 ----
    addi x16, x0, 3         # x16=3
    addi x17, x0, 0         # x17=0
    beq  x16, x16, br1      # taken
    addi x17, x0, 99
    addi x17, x0, 99
br1: addi x17, x17, 1       # x17=1

#---- 分支依赖 load 结果 ----
    lw   x18, 0(x7)         # x18=42
    bne  x18, x0, br2       # taken
    addi x17, x0, 99
br2: addi x17, x17, 1       # x17=2

#---- 其它指令覆盖 ----
    lui  x19, 0x12345       # 0x12345000
    slli x20, x1, 4         # 80
    xori x21, x1, 0xFF      # 250
    jal  x22, sub1
ret1: addi x23, x0, 7       # x23=7
    j    done
sub1: addi x17, x17, 100    # x17=102
    jalr x0, 0(x22)

done:
    addi x31, x0, 0x5A5     # 哨兵: 提交后 TB 判停机
hang:
    j    hang

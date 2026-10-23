    .globl _start
_start:
    addi t0, x0, 10
    addi t1, x0, 0
loop:
    add  t1, t1, t0
    addi t0, t0, -1
    bne  t0, x0, loop
    mv   a0, t1
    li   a7, 93
    ecall

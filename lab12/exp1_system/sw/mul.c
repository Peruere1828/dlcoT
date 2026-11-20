/* mul.c : 软件乘除法
 * 本 CPU 只有 RV32I, 没有 mul/div 指令. GCC 把 * / % 降级成对这些函数的调用,
 * 必须一起编译链接, 否则链接报 undefined reference.
 */

unsigned int __mulsi3(unsigned int a, unsigned int b)
{
    unsigned int res = 0;

    while (a) {
        if (a & 1u)
            res += b;
        a >>= 1;
        b <<= 1;
    }
    return res;
}

unsigned int __umodsi3(unsigned int a, unsigned int b)
{
    unsigned int bit = 1;
    unsigned int res = 0;

    while (b < a && bit && !(b & (1UL << 31))) {
        b <<= 1;
        bit <<= 1;
    }
    while (bit) {
        if (a >= b) {
            a -= b;
            res |= bit;
        }
        bit >>= 1;
        b >>= 1;
    }
    return a;
}

unsigned int __udivsi3(unsigned int a, unsigned int b)
{
    unsigned int bit = 1;
    unsigned int res = 0;

    while (b < a && bit && !(b & (1UL << 31))) {
        b <<= 1;
        bit <<= 1;
    }
    while (bit) {
        if (a >= b) {
            a -= b;
            res |= bit;
        }
        bit >>= 1;
        b >>= 1;
    }
    return res;
}

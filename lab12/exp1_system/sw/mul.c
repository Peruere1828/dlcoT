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

/* 有符号除法与取余: C 语言的 / 和 % 对 int 会调用这两个函数,
 * 实现方式是按符号转成无符号再调上面的 __udivsi3 / __umodsi3.
 */
int __divsi3(int a, int b)
{
    int neg = ((a < 0) ^ (b < 0)) ? 1 : 0;
    unsigned int ua = (a < 0) ? (unsigned int)(-a) : (unsigned int)a;
    unsigned int ub = (b < 0) ? (unsigned int)(-b) : (unsigned int)b;
    unsigned int q  = __udivsi3(ua, ub);

    return neg ? -(int)q : (int)q;
}

int __modsi3(int a, int b)
{
    int neg = (a < 0) ? 1 : 0;
    unsigned int ua = (a < 0) ? (unsigned int)(-a) : (unsigned int)a;
    unsigned int ub = (b < 0) ? (unsigned int)(-b) : (unsigned int)b;
    unsigned int r  = __umodsi3(ua, ub);

    return neg ? -(int)r : (int)r;
}

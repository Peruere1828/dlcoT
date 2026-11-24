/* main.c : 终端主程序
 * 用 readline 读入一行命令, 按命令分派:
 *   hello         显示 Hello World!
 *   time          显示上电以来的时间, 时:分:秒
 *   fib n         显示斐波那契数列第 n 项
 *   calc <表达式>  整数四则运算, 支持括号和 0x 十六进制
 *   mem <地址> [n] 按字打印数据地址空间的内容, 默认 8 个字
 *   echo <文字>   原样打印参数
 *   led <值>      写 LED, 支持 0x 前缀的十六进制
 *   sw            显示拨动开关的值
 *   mines [种子]  扫雷小游戏, 不带种子就用毫秒计数
 *   history       列出最近 8 条命令
 *   clear         清屏
 *   help          显示命令列表
 *   其它          显示 Unknown Command
 *
 * 行编辑由 sys.c 的 readline 负责: 左右键移动光标, 上下键调历史,
 * Home/End/Delete 改行, Tab 补全命令名, Ctrl+A/E/L/C/U 是行首、行尾、
 * 清屏、取消当前行、清空当前行.
 */
#include "sys.h"

#define FIB_MAX  46u        /* fib(46) = 1836311903, fib(47) 超出 32 位有符号范围 */

static char line[LINE_MAX + 1u];

void entry(void);
int  main(void);

/* 程序入口: 设置栈指针后进入 main, main 不会返回 */
void entry(void)
{
    __asm__ volatile ("lui sp, 0x120");
    __asm__ volatile ("addi sp, sp, -4");
    main();
}

static char *skip_space(char *p)
{
    while (*p == ' ')
        p++;
    return p;
}

/* 解析无符号十进制数, 成功返回 1 */
static int parse_uint(const char *s, u32 *out)
{
    u32 v = 0;

    if (*s == '\0')
        return 0;

    while (*s != '\0') {
        if (*s < '0' || *s > '9')
            return 0;
        v = v * 10u + (u32)(*s - '0');
        s++;
    }

    *out = v;
    return 1;
}

/* 解析数字: 以 0x 开头按十六进制, 否则按十进制 */
static int parse_num(const char *s, u32 *out)
{
    u32 v = 0;
    u32 d;
    int hex = 0;

    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        hex = 1;
        s += 2;
    }
    if (*s == '\0')
        return 0;

    while (*s != '\0') {
        if (*s >= '0' && *s <= '9')
            d = (u32)(*s - '0');
        else if (hex && *s >= 'a' && *s <= 'f')
            d = (u32)(*s - 'a') + 10u;
        else if (hex && *s >= 'A' && *s <= 'F')
            d = (u32)(*s - 'A') + 10u;
        else
            return 0;
        v = hex ? (v << 4) | d : v * 10u + d;
        s++;
    }

    *out = v;
    return 1;
}

static u32 fib(u32 n)
{
    u32 a = 0;
    u32 b = 1;
    u32 t;
    u32 i;

    if (n == 0)
        return 0;

    for (i = 1; i < n; i++) {
        t = a + b;
        a = b;
        b = t;
    }
    return b;
}

/* 两位十进制, 不足两位补 0 */
/* 命令表: Tab 补全查这张表, 加新命令时只改这里和 run_command 的分派 */
static const char *const g_cmds[] = {
    "hello", "help", "time", "fib", "calc", "mem",
    "echo", "led", "sw", "mines", "history", "clear"
};

u32 cmd_count(void)
{
    return (u32)(sizeof(g_cmds) / sizeof(g_cmds[0]));
}

const char *cmd_name(u32 i)
{
    return (i < cmd_count()) ? g_cmds[i] : 0;
}

static void put_2d(u32 v)
{
    putch((char)('0' + (v / 10u) % 10u));
    putch((char)('0' + v % 10u));
}

/* ================= 整数表达式计算 =================
 * 文法: expr := term {(+|-) term};  term := unary {(*|/|%) unary};
 *       unary := ('+'|'-') unary | primary;  primary := 数字 | '(' expr ')'
 * 数字支持十进制和 0x 十六进制, 32 位补码运算.
 */

static const char *calc_p;

static void calc_skip(void)
{
    while (*calc_p == ' ')
        calc_p++;
}

static int calc_expr(int *v, int *err);

/* 读一个数字, 成功返回 1 */
static int calc_number(int *v)
{
    u32 x = 0;
    u32 d;
    int hex = 0;
    int nd = 0;
    char c;

    if (calc_p[0] == '0' && (calc_p[1] == 'x' || calc_p[1] == 'X')) {
        hex = 1;
        calc_p += 2;
    }

    for (;;) {
        c = *calc_p;
        if (c >= '0' && c <= '9')
            d = (u32)(c - '0');
        else if (hex && c >= 'a' && c <= 'f')
            d = (u32)(c - 'a') + 10u;
        else if (hex && c >= 'A' && c <= 'F')
            d = (u32)(c - 'A') + 10u;
        else
            break;
        x = hex ? ((x << 4) | d) : (x * 10u + d);
        calc_p++;
        nd++;
    }

    if (nd == 0)
        return 0;
    *v = (int)x;
    return 1;
}

static int calc_primary(int *v, int *err)
{
    calc_skip();

    if (*calc_p == '(') {
        calc_p++;
        if (!calc_expr(v, err))
            return 0;
        calc_skip();
        if (*calc_p != ')')
            return 0;
        calc_p++;
        return 1;
    }

    return calc_number(v);
}

static int calc_unary(int *v, int *err)
{
    calc_skip();

    if (*calc_p == '-') {
        calc_p++;
        if (!calc_unary(v, err))
            return 0;
        *v = (int)(0u - (u32)*v);
        return 1;
    }
    if (*calc_p == '+') {
        calc_p++;
        return calc_unary(v, err);
    }

    return calc_primary(v, err);
}

static int calc_term(int *v, int *err)
{
    int rhs;
    char op;

    if (!calc_unary(v, err))
        return 0;

    for (;;) {
        calc_skip();
        op = *calc_p;
        if (op != '*' && op != '/' && op != '%')
            return 1;
        calc_p++;
        if (!calc_unary(&rhs, err))
            return 0;
        if (op == '*') {
            *v = (int)((u32)*v * (u32)rhs);
        } else if (rhs == 0) {
            *err = 2;
            return 0;
        } else if (op == '/') {
            *v = *v / rhs;
        } else {
            *v = *v % rhs;
        }
    }
}

static int calc_expr(int *v, int *err)
{
    int rhs;
    char op;

    if (!calc_term(v, err))
        return 0;

    for (;;) {
        calc_skip();
        op = *calc_p;
        if (op != '+' && op != '-')
            return 1;
        calc_p++;
        if (!calc_term(&rhs, err))
            return 0;
        if (op == '+')
            *v = (int)((u32)*v + (u32)rhs);
        else
            *v = (int)((u32)*v - (u32)rhs);
    }
}

/* 计算整个表达式, 成功返回 1 */
static int eval_calc(const char *s, int *v, int *err)
{
    calc_p = s;
    *err = 0;

    if (!calc_expr(v, err))
        return 0;
    calc_skip();
    return (*calc_p == '\0') ? 1 : 0;
}

/* 把命令行拆成命令名与参数, 去掉首尾空格 */
static void run_command(char *s)
{
    char *name;
    char *arg;
    char *p;
    char *end;
    u32  n;

    name = skip_space(s);

    p = name;
    while (*p != '\0' && *p != ' ')
        p++;
    if (*p == ' ') {
        *p = '\0';
        arg = skip_space(p + 1);
    } else {
        arg = p;
    }

    end = arg;
    while (*end != '\0')
        end++;
    while (end > arg && end[-1] == ' ')
        end--;
    *end = '\0';

    if (*name == '\0')
        return;

    if (streq(name, "hello")) {
        puts("Hello World!\n");
    } else if (streq(name, "time")) {
        u32 sec = millis() / 1000u;
        puts("time: ");
        put_2d((sec / 3600u) % 100u);
        putch(':');
        put_2d((sec / 60u) % 60u);
        putch(':');
        put_2d(sec % 60u);
        putch('\n');
    } else if (streq(name, "calc")) {
        int v;
        int err;

        if (*arg == '\0') {
            puts("calc: missing expression\n");
        } else if (!eval_calc(arg, &v, &err)) {
            if (err == 2)
                puts("calc: divide by zero\n");
            else
                puts("calc: syntax error\n");
        } else {
            put_dec(v);
            putch('\n');
        }
    } else if (streq(name, "mem")) {
        char *p2 = arg;
        char *cs;
        u32 addr;
        u32 cnt;
        u32 i;
        u32 j;

        while (*p2 != '\0' && *p2 != ' ')
            p2++;
        if (*p2 == ' ') {
            *p2 = '\0';
            cs = skip_space(p2 + 1);
        } else {
            cs = p2;
        }

        if (*arg == '\0') {
            puts("mem: missing address\n");
        } else if (!parse_num(arg, &addr)) {
            puts("mem: bad address\n");
        } else if ((*cs != '\0') && !parse_num(cs, &cnt)) {
            puts("mem: bad count\n");
        } else {
            if (*cs == '\0')
                cnt = 8u;
            if (cnt > 32u)
                cnt = 32u;
            addr &= 0xfffffffcu;
            for (i = 0; i < cnt; i += 4u) {
                put_hex(addr + i * 4u, 8);
                putch(':');
                for (j = 0; (j < 4u) && ((i + j) < cnt); j++) {
                    putch(' ');
                    put_hex(*(volatile u32 *)(addr + (i + j) * 4u), 8);
                }
                putch('\n');
            }
        }
    } else if (streq(name, "fib")) {
        if (*arg == '\0') {
            puts("fib: missing n\n");
        } else if (!parse_uint(arg, &n)) {
            puts("fib: bad number\n");
        } else if (n > FIB_MAX) {
            puts("fib: n too large, max 46\n");
        } else {
            put_dec((int)fib(n));
            putch('\n');
        }
    } else if (streq(name, "help")) {
        puts("cmds: hello time fib calc mem echo led sw mines history clear help\n");
        puts("keys: Left/Right move, Up/Down history, Tab complete\n");
    } else if (streq(name, "echo")) {
        puts(arg);
        putch('\n');
    } else if (streq(name, "sw")) {
        puts("sw: 0x");
        put_hex((u32)(REG32(SW_REG) & 0xffffu), 4);
        putch('\n');
    } else if (streq(name, "led")) {
        if (*arg == '\0') {
            puts("led: missing value\n");
        } else if (!parse_num(arg, &n)) {
            puts("led: bad value\n");
        } else {
            n &= 0x7fffu;                       /* LED[14:0] */
            REG32(LED_REG) = n;
            puts("led: 0x");
            put_hex(n, 4);
            putch('\n');
        }
    } else if (streq(name, "history")) {
        if (streq(arg, "clear"))
            history_clear();
        else
            history_dump();
    } else if (streq(name, "mines")) {
        u32 sd = millis() | 1u;

        if ((*arg != '\0') && !parse_num(arg, &sd))
            puts("mines: bad seed\n");
        else
            mines_run(sd);
    } else if (streq(name, "clear")) {
        vga_init();
    } else {
        puts("Unknown Command\n");
    }
}

int main(void)
{
    int n;

    vga_init();

    REG32(LED_REG) = 0x0001u;
    puts("RV32I System  lab12\n");
    puts("hello | time | fib n | help\n");

    for (;;) {
        n = readline(line, LINE_MAX);
        line[n] = '\0';
        run_command(line);
    }

    return 0;
}

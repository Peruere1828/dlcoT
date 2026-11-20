/* main.c : 终端主程序
 * 用 readline 读入一行命令, 按命令分派:
 *   hello       显示 Hello World!
 *   time        显示上电以来的秒数
 *   fib n       显示斐波那契数列第 n 项
 *   help        显示命令列表
 *   其它        显示 Unknown Command
 *
 * 行编辑由 sys.c 的 readline 负责: 左右键移动光标, 上下键调历史,
 * Home/End/Delete 改行, Tab 补全命令名.
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
        puts("time: ");
        put_dec((int)(millis() / 1000u));
        puts(" s\n");
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
        puts("commands: hello, time, fib n, help\n");
        puts("keys: Left/Right move, Up/Down history, Tab complete\n");
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

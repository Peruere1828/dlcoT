/* sys.c : 字符终端库函数
 * 显存 32 行 x 128 列, 屏幕只显示 30 行 x 70 列, 多出的 2 行用于滚屏.
 * 命令行的编辑在软件里完成: 光标位置写硬件寄存器, 左右移动、行内插入删除、
 * 上下键调历史、Tab 补全都在 readline 里处理, 硬件只负责按键和画光标.
 */
#include "sys.h"

#define CHAR_BASE ((volatile unsigned char *)VGA_MEM)

static u32 g_row = 0;   /* 光标所在行, 0~29, 相对屏幕顶部 */
static u32 g_col = 0;   /* 光标所在列, 0~69 */
static u32 g_top = 0;   /* 显示起始行, 0~31, 即环形缓冲的物理行 */

/* 把光标写到硬件寄存器, 行号要换算成显存里的物理行.
 * 硬件用物理行减 top_row 得到屏幕行, 滚屏后光标不会跑偏.
 */
static void set_cursor(void)
{
    u32 phys = (g_top + g_row) & (VGA_ROWS - 1u);
    u32 col  = g_col;

    if (col >= VGA_MAXCOL)      /* 行满时光标停在最后一列, 不越界 */
        col = VGA_MAXCOL - 1u;
    REG32(VGA_CURSOR) = (phys << 7) | col;
}

/* 清空整个环形缓冲, 起始行归零 */
void vga_init(void)
{
    u32 i;

    REG32(VGA_TOP) = 0;
    for (i = 0; i < VGA_ROWS * VGA_STRIDE; i++)
        CHAR_BASE[i] = 0;

    g_row = 0;
    g_col = 0;
    g_top = 0;
    set_cursor();
}

/* 滚屏: 起始行加一, 清空新的最底行, 光标跟着文字上移一行 */
static void scroll(void)
{
    u32 i;
    u32 phys;

    g_top = (g_top + 1u) & (VGA_ROWS - 1u);
    REG32(VGA_TOP) = g_top;

    phys = (g_top + (VGA_MAXROW - 1u)) & (VGA_ROWS - 1u);
    for (i = 0; i < VGA_MAXCOL; i++)
        CHAR_BASE[(phys << 7) + i] = 0;

    if (g_row > 0u)
        g_row--;
}

/* 回车换行, 已在最后一行则滚屏 */
static void newline(void)
{
    g_col = 0;
    if (g_row >= VGA_MAXROW - 1u) {
        scroll();
        g_row = VGA_MAXROW - 1u;
    } else {
        g_row++;
    }
    set_cursor();
}

/* 退格: 擦掉前一个字符并回退; 行首退格不越过上一行 */
static void backspace(void)
{
    u32 phys;

    if (g_col == 0u)
        return;

    g_col--;
    phys = (g_top + g_row) & (VGA_ROWS - 1u);
    CHAR_BASE[(phys << 7) + g_col] = 0;
    set_cursor();
}

void putch(char c)
{
    u32 phys;

    if (c == '\r')
        return;
    if (c == '\n') {
        newline();
        return;
    }
    if (c == '\b') {
        backspace();
        return;
    }
    if ((unsigned char)c < 0x20u || (unsigned char)c > 0x7eu)
        return;

    if (g_col >= VGA_MAXCOL)
        newline();

    phys = (g_top + g_row) & (VGA_ROWS - 1u);
    CHAR_BASE[(phys << 7) + g_col] = (unsigned char)c;
    g_col++;
    set_cursor();
}

void puts(const char *s)
{
    while (*s != '\0')
        putch(*s++);
}

/* 十六进制输出, 固定打印低 digits 位, 前面补 0 */
void put_hex(u32 v, u32 digits)
{
    char buf[8];
    u32 i;
    u32 d;

    if (digits > 8u)
        digits = 8u;

    for (i = 0; i < digits; i++) {
        d = v & 0xFu;
        buf[digits - 1u - i] = (d < 10u) ? (char)('0' + d)
                                         : (char)('a' + d - 10u);
        v >>= 4;
    }

    for (i = 0; i < digits; i++)
        putch(buf[i]);
}

/* 十进制输出, 支持负数 */
void put_dec(int v)
{
    char buf[12];
    int i = 0;
    u32 u;

    if (v < 0) {
        putch('-');
        u = (u32)(-v);
    } else {
        u = (u32)v;
    }

    do {
        buf[i++] = (char)('0' + (u % 10u));
        u /= 10u;
    } while (u != 0u);

    while (i > 0)
        putch(buf[--i]);
}

/* 轮询键盘, 有数据则读数据寄存器并写弹出寄存器, 无数据返回 -1 */
int getchar(void)
{
    u32 status;
    char c;

    status = REG32(KBD_STATUS);
    if ((status & KBD_VALID) == 0u)
        return -1;

    c = (char)(REG32(KBD_DATA) & 0xffu);
    REG32(KBD_POP) = 0;
    return (int)(unsigned char)c;
}

u32 millis(void)
{
    return REG32(TIMER_MS);
}

int streq(const char *a, const char *b)
{
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return (*a == *b) ? 1 : 0;
}

/* ==================================================================
 * 命令行编辑
 *
 * 输入行从提示符 "> " 开始, 提示符占偏移 0 和 1, 第 k 个字符占偏移 2+k.
 * 偏移换算成屏幕位置: 行 = 偏移 / 70, 列 = 偏移 % 70, 70 列以外的部分
 * 自动落到下一行, 和 lab11 的续行模型一致.
 * 显示用 ed_phys 记物理行, 滚屏只改 top_row, 物理行不变.
 * ================================================================== */

#define ED_STRIDE    VGA_MAXCOL
#define ED_PROMPT    2u
#define HIST_N       8u
#define NCMD         4u

static u32  ed_phys;             /* 本轮输入行在显存里的物理起始行 */
static u32  ed_high;             /* 已经写过的最远偏移, 用来擦掉行尾残留 */
static u32  ed_shown;            /* 屏上已经画出的字符数 */

static char hist[HIST_N][LINE_MAX + 1u];
static u32  hist_len[HIST_N];
static u32  hist_n;              /* 有效条数, 最多 HIST_N */
static u32  hist_next;           /* 下一条写入的槽位 */
static char hist_save[LINE_MAX + 1u];
static u32  hist_save_len;
static u32  hist_back;           /* 0 表示正在编辑新行, k 表示回看第 k 条 */

static const char *const cmds[NCMD] = { "hello", "help", "time", "fib" };

static u32 slen(const char *s)
{
    u32 n = 0;

    while (s[n] != '\0')
        n++;
    return n;
}

/* p 的前 n 个字符是否等于 s 的开头 */
static int sprefix(const char *s, const char *p, u32 n)
{
    u32 i;

    for (i = 0; i < n; i++)
        if (s[i] != p[i])
            return 0;
    return 1;
}

/* 输入行偏移处对应的屏幕行 */
static u32 ed_screen_row(void)
{
    return (ed_phys + VGA_ROWS - g_top) & (VGA_ROWS - 1u);
}

/* 保证偏移 off 所在的屏幕行可见, 不够就滚屏 */
static void ed_ensure(u32 off)
{
    u32 need = off / ED_STRIDE + 1u;

    while (ed_screen_row() + need > VGA_MAXROW)
        scroll();
}

/* 把光标移到输入行的偏移 off 处 */
static void ed_place(u32 off)
{
    u32 row = off / ED_STRIDE;

    ed_ensure(off);
    g_row = ed_screen_row() + row;
    g_col = off - row * ED_STRIDE;
    set_cursor();
}

/* 画输入行里的一格 */
static void ed_draw_cell(u32 off, char ch)
{
    u32 row  = off / ED_STRIDE;
    u32 phys = (ed_phys + row) & (VGA_ROWS - 1u);
    u32 col  = off - row * ED_STRIDE;

    CHAR_BASE[(phys << 7) + col] = (unsigned char)ch;
}

/* 整行重画: 提示符 + 缓冲区, 再擦掉比现在长的残留.
 * 行尾追加和行尾退格只重画一格, 打长行时每次按键的代价是常数.
 */
static void ed_render(const char *buf, u32 len, u32 pos)
{
    u32 off;
    u32 total;
    u32 phys;
    u32 col;
    char ch;

    if (len == ed_shown + 1u && pos == len) {           /* 行尾追加 */
        ed_ensure(ED_PROMPT + pos);
        ed_draw_cell(ED_PROMPT + len - 1u, buf[len - 1u]);
        ed_shown = len;
        ed_high  = ED_PROMPT + len;
        ed_place(ED_PROMPT + pos);
        return;
    }
    if (len + 1u == ed_shown && pos == len) {           /* 行尾退格 */
        ed_draw_cell(ED_PROMPT + len, 0);
        ed_shown = len;
        ed_high  = ED_PROMPT + len;
        ed_place(ED_PROMPT + pos);
        return;
    }

    total = ED_PROMPT + len;
    if (ed_high > total)
        total = ed_high;
    ed_high  = ED_PROMPT + len;
    ed_shown = len;

    ed_ensure(total - 1u);      /* 要擦到的那一格也得在屏幕上 */

    phys = ed_phys;
    col  = 0;

    /* 显存地址按行、列递推, 不在每个字符上做除法 */
    for (off = 0; off < total; off++) {
        if (off == 0u)
            ch = '>';
        else if (off == 1u)
            ch = ' ';
        else if (off - ED_PROMPT < len)
            ch = buf[off - ED_PROMPT];
        else
            ch = 0;

        CHAR_BASE[(phys << 7) + col] = (unsigned char)ch;

        if (col == ED_STRIDE - 1u) {
            col  = 0;
            phys = (phys + 1u) & (VGA_ROWS - 1u);
        } else {
            col++;
        }
    }

    ed_place(ED_PROMPT + pos);
}

/* 提示符放在当前行行首; 光标不在行首时先换行 */
static void ed_begin(void)
{
    if (g_col != 0u)
        newline();

    g_col   = 0;
    ed_phys = (g_top + g_row) & (VGA_ROWS - 1u);
    ed_high = ED_PROMPT;
    ed_shown = 0;
}

/* Ctrl+L: 清屏后把已经输入的内容重画在第一行, 输入不丢 */
static void ed_clear(const char *buf, u32 len, u32 pos)
{
    vga_init();
    ed_phys  = 0;
    ed_high  = ED_PROMPT;
    ed_shown = 0;
    ed_render(buf, len, pos);
}

static void hist_push(const char *buf, u32 len)
{
    u32 slot;
    u32 i;

    if (len == 0u || len > LINE_MAX)
        return;

    if (hist_n > 0u) {          /* 连续输入同一条命令不重复记 */
        slot = (hist_next + HIST_N - 1u) % HIST_N;
        if (hist_len[slot] == len) {
            for (i = 0; i < len; i++)
                if (hist[slot][i] != buf[i])
                    break;
            if (i == len)
                return;
        }
    }

    slot = hist_next;
    for (i = 0; i < len; i++)
        hist[slot][i] = buf[i];
    hist[slot][len] = '\0';
    hist_len[slot]  = len;

    hist_next = (hist_next + 1u) % HIST_N;
    if (hist_n < HIST_N)
        hist_n++;
}

/* 取回倒数第 back 条历史, 返回长度 */
static u32 hist_get(u32 back, char *dst)
{
    u32 slot = (hist_next + HIST_N - back) % HIST_N;
    u32 i;

    for (i = 0; i < hist_len[slot]; i++)
        dst[i] = hist[slot][i];
    return hist_len[slot];
}

/* 打印历史, 旧的在前, 带序号 */
void history_dump(void)
{
    u32 i;
    u32 k;
    u32 slot;

    if (hist_n == 0u) {
        puts("history: empty\n");
        return;
    }

    puts("history:\n");
    for (i = hist_n; i > 0u; i--) {
        slot = (hist_next + HIST_N - i) % HIST_N;
        putch(' ');
        putch(' ');
        put_dec((int)(hist_n - i + 1u));
        putch(' ');
        for (k = 0; k < hist_len[slot]; k++)
            putch(hist[slot][k]);
        putch('\n');
    }
}

/* 清空历史 */
void history_clear(void)
{
    hist_n    = 0;
    hist_next = 0;
    hist_back = 0;
    puts("history: cleared\n");
}

/* Tab 补全命令名. 只补第一个词, 多个候选补到公共前缀, 唯一候选补全后加空格 */
static u32 complete(char *buf, u32 len, u32 *pos)
{
    const char *cand = 0;
    u32 plen = 0;
    u32 match = 0;
    u32 n;
    u32 i;

    if (len != *pos || len == 0u || len >= LINE_MAX)
        return len;

    for (i = 0; i < len; i++)           /* 已经有空格说明在输参数, 不补全 */
        if (buf[i] == ' ')
            return len;

    for (i = 0; i < NCMD; i++) {
        if (!sprefix(cmds[i], buf, len))
            continue;
        if (match == 0u) {
            cand = cmds[i];
            plen = slen(cand);
        } else {
            n = (plen < slen(cmds[i])) ? plen : slen(cmds[i]);
            plen = 0;
            while (plen < n && cand[plen] == cmds[i][plen])
                plen++;
        }
        match++;
    }

    if (match == 0u || plen <= len)
        return len;

    for (i = len; i < plen; i++)
        buf[i] = cand[i];
    len  = plen;
    *pos = plen;

    if (match == 1u) {                  /* 唯一候选, 顺手补一个空格 */
        buf[len] = ' ';
        len++;
        *pos = len;
    }
    return len;
}

int readline(char *buf, u32 max)
{
    u32 len = 0;
    u32 pos = 0;
    u32 i;
    int c;
    int cancelled = 0;

    if (max > LINE_MAX)
        max = LINE_MAX;
    if (max == 0u)
        return 0;

    ed_begin();
    hist_back     = 0;
    hist_save_len = 0;
    ed_render(buf, len, pos);

    for (;;) {
        c = getchar();
        if (c < 0)
            continue;

        /* 数码管显示最近一次按键的编码, 显示器没接时也能看出键盘是否工作 */
        REG32(DBG_REG) = (u32)(unsigned char)c;

        if (c == K_ENTER) {
            break;
        } else if (c == K_BS) {
            if (pos > 0u) {
                for (i = pos - 1u; i + 1u < len; i++)
                    buf[i] = buf[i + 1u];
                len--;
                pos--;
                ed_render(buf, len, pos);
            }
        } else if (c == K_DEL) {
            if (pos < len) {
                for (i = pos; i + 1u < len; i++)
                    buf[i] = buf[i + 1u];
                len--;
                ed_render(buf, len, pos);
            }
        } else if (c == K_LEFT) {
            if (pos > 0u) {
                pos--;
                ed_render(buf, len, pos);
            }
        } else if (c == K_RIGHT) {
            if (pos < len) {
                pos++;
                ed_render(buf, len, pos);
            }
        } else if (c == K_HOME) {
            if (pos != 0u) {
                pos = 0;
                ed_render(buf, len, pos);
            }
        } else if (c == K_END) {
            if (pos != len) {
                pos = len;
                ed_render(buf, len, pos);
            }
        } else if (c == K_CTRL_A) {
            if (pos != 0u) {
                pos = 0;
                ed_render(buf, len, pos);
            }
        } else if (c == K_CTRL_E) {
            if (pos != len) {
                pos = len;
                ed_render(buf, len, pos);
            }
        } else if (c == K_CTRL_U) {
            len = 0;
            pos = 0;
            ed_render(buf, len, pos);
        } else if (c == K_CTRL_L) {
            ed_clear(buf, len, pos);
        } else if (c == K_CTRL_C) {
            /* 光标移到行尾, 打印 ^C 换行, 这一行作废; 光标留在新行行首 */
            ed_place(ED_PROMPT + len);
            puts("^C\n");
            len = 0;
            pos = 0;
            cancelled = 1;
            break;
        } else if (c == K_UP) {            if (hist_back < hist_n) {
                if (hist_back == 0u) {
                    hist_save_len = len;
                    for (i = 0; i < len; i++)
                        hist_save[i] = buf[i];
                }
                hist_back++;
                len = hist_get(hist_back, buf);
                pos = len;
                ed_render(buf, len, pos);
            }
        } else if (c == K_DOWN) {
            if (hist_back > 0u) {
                hist_back--;
                if (hist_back == 0u) {
                    len = hist_save_len;
                    for (i = 0; i < len; i++)
                        buf[i] = hist_save[i];
                } else {
                    len = hist_get(hist_back, buf);
                }
                pos = len;
                ed_render(buf, len, pos);
            }
        } else if (c == K_TAB) {
            len = complete(buf, len, &pos);
            ed_render(buf, len, pos);
        } else if (c >= 0x20 && c < 0x7f) {
            if (len < max) {
                for (i = len; i > pos; i--)
                    buf[i] = buf[i - 1u];
                buf[pos] = (char)c;
                len++;
                pos++;
                ed_render(buf, len, pos);
            }
        } else {
            /* 其它控制字符忽略 */
        }
    }

    if (!cancelled) {
        hist_push(buf, len);

        /* 光标移到输入行末尾, 行尾正好落在下一行行首时不用再换行 */
        ed_place(ED_PROMPT + len);
        if (g_col != 0u)
            newline();
    }

    buf[len] = '\0';
    return (int)len;
}

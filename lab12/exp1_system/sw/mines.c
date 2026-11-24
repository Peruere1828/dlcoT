/* mines.c : 字符终端版扫雷
 *
 * 灵感来自 Simon Tatham's Portable Puzzle Collection 里的 mines:
 * 第一次翻开的位置和它周围的 8 格保证没有雷, 选雷时先把可用格列成表,
 * 每次从表里随机取一个再和表尾交换, 不会重复也不会死循环.
 *
 * 棋盘 9x9, 10 颗雷. 方向键移动, 回车或空格翻开, F 插旗, R 重开, Q 退出.
 * 第一次翻开之前雷还没有布, 所以同一颗种子 + 同一个首翻位置一定得到同一张图,
 * testbench 靠这一点做确定性检查.
 */
#include "sys.h"

#define BW      9u
#define BH      9u
#define NCELL   (BW * BH)
#define BMINE   10u

#define C_MINE  0x01u
#define C_OPEN  0x02u
#define C_FLAG  0x04u
#define CNT(v)  ((u32)(v) >> 3)

#define ROW_TOP 3u
#define COL_TOP 3u

static u8  g_cell[NCELL];
static u32 g_seed;
static u32 g_rng;
static u32 g_sel;
static u32 g_moves;
static u32 g_placed;
static u32 g_dead;
static u32 g_won;
static u32 g_frames;     /* 重画计数, 写到数码管寄存器, testbench 用它判断一帧画完 */

/* 线性同余, 只用来选雷, 够随机也容易在 testbench 里复现 */
static u32 mines_rnd(void)
{
    g_rng = g_rng * 1103515245u + 12345u;
    return (g_rng >> 16) & 0x7fffu;
}

static void mines_new(void)
{
    u32 i;

    for (i = 0; i < NCELL; i++)
        g_cell[i] = 0;
    g_rng    = g_seed;
    g_sel    = 0;
    g_moves  = 0;
    g_placed = 0;
    g_dead   = 0;
    g_won    = 0;
}

/* 格 idx 与首翻位置 first 是否相邻或重合 */
static u32 mines_near(u32 idx, u32 first)
{
    u32 r  = idx / BW;
    u32 c  = idx % BW;
    u32 fr = first / BW;
    u32 fc = first % BW;
    u32 dr = (r > fr) ? (r - fr) : (fr - r);
    u32 dc = (c > fc) ? (c - fc) : (fc - c);

    return ((dr <= 1u) && (dc <= 1u)) ? 1u : 0u;
}

/* 周围 8 格的雷数 */
static u32 mines_cnt(u32 idx)
{
    u32 r  = idx / BW;
    u32 c  = idx % BW;
    u32 rr, cc;
    u32 n  = 0;

    for (rr = (r == 0u) ? 0u : (r - 1u);
         rr <= ((r + 1u < BH) ? (r + 1u) : (BH - 1u)); rr++)
        for (cc = (c == 0u) ? 0u : (c - 1u);
             cc <= ((c + 1u < BW) ? (c + 1u) : (BW - 1u)); cc++)
            if (((rr != r) || (cc != c)) && (g_cell[rr * BW + cc] & C_MINE))
                n++;

    return n;
}

static void mines_place(u32 first)
{
    u32 tmp[NCELL];
    u32 i;
    u32 k = 0;
    u32 n = BMINE;
    u32 j;
    u32 idx;

    for (i = 0; i < NCELL; i++) {
        g_cell[i] = 0;
        if (!mines_near(i, first))
            tmp[k++] = i;
    }

    while (n > 0u) {
        j = mines_rnd() % k;
        idx = tmp[j];
        g_cell[idx] |= C_MINE;
        tmp[j] = tmp[--k];
        n--;
    }

    /* 把周围雷数左移 3 位存进同一字节, 画图和洪泛都直接取 */
    for (i = 0; i < NCELL; i++)
        if (!(g_cell[i] & C_MINE))
            g_cell[i] |= (u8)(mines_cnt(i) << 3);

    g_placed = 1u;
}

static void mines_check_win(void)
{
    u32 i;
    u32 opened = 0;

    for (i = 0; i < NCELL; i++)
        if ((g_cell[i] & C_OPEN) && !(g_cell[i] & C_MINE))
            opened++;

    if (opened == NCELL - BMINE)
        g_won = 1u;
}

/* 翻开一格: 是雷就结束, 是 0 就按 8 邻接洪泛 */
static void mines_open(u32 idx)
{
    u32 stack[NCELL];
    u32 sp = 0;
    u32 k, r, c, rr, cc, nb;

    if (g_cell[idx] & (C_OPEN | C_FLAG))
        return;
    if (!g_placed)
        mines_place(idx);

    if (g_cell[idx] & C_MINE) {
        for (k = 0; k < NCELL; k++)
            if (g_cell[k] & C_MINE)
                g_cell[k] |= C_OPEN;
        g_dead = 1u;
        return;
    }

    g_cell[idx] |= C_OPEN;
    stack[sp++] = idx;

    while (sp > 0u) {
        k = stack[--sp];
        if (CNT(g_cell[k]) != 0u)
            continue;

        r = k / BW;
        c = k % BW;
        for (rr = (r == 0u) ? 0u : (r - 1u);
             rr <= ((r + 1u < BH) ? (r + 1u) : (BH - 1u)); rr++)
            for (cc = (c == 0u) ? 0u : (c - 1u);
                 cc <= ((c + 1u < BW) ? (c + 1u) : (BW - 1u)); cc++) {
                nb = rr * BW + cc;
                if (nb == k)
                    continue;
                if (g_cell[nb] & (C_OPEN | C_FLAG))
                    continue;
                g_cell[nb] |= C_OPEN;
                stack[sp++] = nb;
            }
    }

    mines_check_win();
}

static void mines_puts_at(u32 row, u32 col, const char *s)
{
    while (*s != '\0') {
        vga_put(row, col, *s);
        col++;
        s++;
    }
}

static void mines_draw(void)
{
    u32 r, c, i, flags = 0;
    char a;

    mines_puts_at(0, 0, "MINES  9x9  10 mines");
    mines_puts_at(1, 0, "arrows move  ENTER open  F flag  R new  Q quit");
    mines_puts_at(2, 3, "0 1 2 3 4 5 6 7 8");

    for (r = 0; r < BH; r++) {
        vga_put(ROW_TOP + r, 0, (char)('0' + r));
        for (c = 0; c < BW; c++) {
            i = r * BW + c;
            if (g_cell[i] & C_FLAG) {
                a = 'F';
            } else if (!(g_cell[i] & C_OPEN)) {
                a = '#';
            } else if (g_cell[i] & C_MINE) {
                a = '*';
            } else if (CNT(g_cell[i]) == 0u) {
                a = ' ';
            } else {
                a = (char)('0' + CNT(g_cell[i]));
            }
            vga_put(ROW_TOP + r, COL_TOP + c * 2u, a);
            vga_put(ROW_TOP + r, COL_TOP + c * 2u + 1u, ' ');
        }
        if (g_cell[r * BW] & C_FLAG)
            flags++;
    }

    for (i = 0; i < NCELL; i++)
        if (g_cell[i] & C_FLAG)
            flags++;

    vga_set_cursor(13, 0);
    puts("moves: ");
    put_dec((int)g_moves);
    puts("   flags: ");
    put_dec((int)flags);
    puts("/10     ");

    vga_set_cursor(14, 0);
    if (g_dead)
        puts("BOOM!  R to restart     ");
    else if (g_won)
        puts("You win!  R to restart  ");
    else
        puts("                        ");

    vga_set_cursor(ROW_TOP + (g_sel / BW), COL_TOP + (g_sel % BW) * 2u);

    g_frames++;
    REG32(DBG_REG) = g_frames;
}

static u32 mines_wait_key(void)
{
    int c;

    for (;;) {
        c = getchar();
        if (c >= 0)
            return (u32)c;
    }
}

void mines_run(u32 seed)
{
    u32 key;

    g_seed   = (seed == 0u) ? 1u : seed;
    g_frames = 0u;
    vga_init();
    mines_new();

    for (;;) {
        mines_draw();
        key = mines_wait_key();

        if ((key == (u32)'q') || (key == (u32)'Q') || (key == K_CTRL_C))
            break;
        if ((key == (u32)'r') || (key == (u32)'R')) {
            mines_new();
            continue;
        }
        if (g_dead || g_won)
            continue;

        if (key == K_UP) {
            if (g_sel >= BW)
                g_sel -= BW;
        } else if (key == K_DOWN) {
            if ((g_sel + BW) < NCELL)
                g_sel += BW;
        } else if (key == K_LEFT) {
            if ((g_sel % BW) != 0u)
                g_sel--;
        } else if (key == K_RIGHT) {
            if ((g_sel % BW) != (BW - 1u))
                g_sel++;
        } else if ((key == K_ENTER) || (key == (u32)' ')) {
            mines_open(g_sel);
            g_moves++;
        } else if ((key == (u32)'f') || (key == (u32)'F')) {
            if (!(g_cell[g_sel] & C_OPEN))
                g_cell[g_sel] ^= C_FLAG;
            g_moves++;
        }
    }

    vga_init();
}

/* sys.h : MMIO 地址与终端库函数声明
 * 地址与 sys_top.v 中 sys_bus 的译码一一对应
 */
#ifndef SYS_H
#define SYS_H

/* 内存映射外设 */
#define VGA_MEM     0x00200000u   /* 字符显存 32 行 x 128 列, 按字节访问 */
#define VGA_TOP     0x00210000u   /* 显示起始行 top_row */
#define VGA_CURSOR  0x00210004u   /* 光标 {物理行[4:0], 列[6:0]}, 硬件再换算成屏幕行 */
#define KBD_DATA    0x00300000u   /* 键盘数据, 低 8 位 ASCII, 读不出队 */
#define KBD_STATUS  0x00300004u   /* bit0 有数据, bit1 溢出 */
#define KBD_POP     0x00300008u   /* 写任意值弹出队首 */
#define TIMER_MS    0x00400000u   /* 毫秒计数 */
#define SW_REG      0x00500000u   /* SW[15:0] */
#define LED_REG     0x00600000u   /* LED[14:0] */
#define DBG_REG     0x00600004u   /* 数码管调试值 */

#define KBD_VALID   0x1u
#define KBD_OVF     0x2u

/* 键盘送来的特殊键: 硬件在 ps2_ascii 里把扫描码映射成这些控制字节.
 * 取值都小于 0x20 或等于 0x7F, 不会和可打印字符冲突.
 */
#define K_HOME      0x01          /* Home,   E0 6C */
#define K_END       0x05          /* End,    E0 69 */
#define K_BS        0x08          /* 退格,   66 */
#define K_TAB       0x09          /* Tab,    0D */
#define K_ENTER     0x0A          /* 回车,   5A */
#define K_UP        0x11          /* 上,     E0 75 */
#define K_DOWN      0x12          /* 下,     E0 72 */
#define K_RIGHT     0x13          /* 右,     E0 74 */
#define K_LEFT      0x14          /* 左,     E0 6B */
#define K_DEL       0x7F          /* Delete, E0 71 */

/* Ctrl + 字母: 硬件送 0x80 | 字母序号, a 是 1, z 是 26 */
#define K_CTRL_A    0x81          /* 行首 */
#define K_CTRL_C    0x83          /* 取消当前行 */
#define K_CTRL_E    0x85          /* 行尾 */
#define K_CTRL_L    0x8C          /* 清屏 */
#define K_CTRL_U    0x95          /* 清空当前行 */

/* 字符屏幕参数 */
#define VGA_MAXROW  30u           /* 屏幕显示 30 行 */
#define VGA_MAXCOL  70u           /* 屏幕显示 70 列 */
#define VGA_STRIDE  128u          /* 显存行步长 */
#define VGA_ROWS    32u           /* 显存环形缓冲 32 行 */

/* 命令行最大字符数, 屏上一行 70 列减去提示符 2 列后最多两行 */
#define LINE_MAX    79u

typedef unsigned int u32;

/* 所有 MMIO 访问必须经过 volatile, 否则 -O2 下轮询会被优化掉 */
#define REG32(addr) (*(volatile unsigned int *)(addr))

void vga_init(void);
void putch(char c);
void puts(const char *s);
void put_dec(int v);
void put_hex(u32 v, u32 digits);

/* 打印最近 8 条历史命令, 以及清空历史 */
void history_dump(void);
void history_clear(void);

/* 读入一行命令, 返回字符数. 自己打印提示符 "> ", 支持左右方向键、
 * 上下方向键调历史、Home/End/Delete 和 Tab 补全.
 * buf 至少要有 LINE_MAX + 1 字节.
 */
int  readline(char *buf, u32 max);

int  getchar(void);
u32  millis(void);
int  streq(const char *a, const char *b);

#endif

#!/usr/bin/env python3
"""mines_ref.py : 扫雷的参考模型, 用来算 testbench 的期望值

和 sw/mines.c 用同一套算法:
  - 线性同余 rnd(): state = state * 1103515245 + 12345, 取 (state >> 16) & 0x7fff
  - 第一次翻开的位置和周围 8 格不放雷
  - 可用格先列成表, 每次随机取一个, 和表尾交换, 取 BMINE 次

用法:
  python3 mines_ref.py [seed] [first]
默认 seed=7, first=0 (左上角), first 是 0..80 的格子编号.
"""

BW = BH = 9
BMINE = 10
NCELL = BW * BH


def rnd(state):
    state = (state * 1103515245 + 12345) & 0xFFFFFFFF
    return state, (state >> 16) & 0x7FFF


def place(seed, first):
    cells = [0] * NCELL
    fr, fc = divmod(first, BW)
    free = []
    for i in range(NCELL):
        r, c = divmod(i, BW)
        if abs(r - fr) > 1 or abs(c - fc) > 1:
            free.append(i)

    state = seed
    k = len(free)
    for _ in range(BMINE):
        state, r = rnd(state)
        j = r % k
        cells[free[j]] = 1
        free[j] = free[k - 1]
        k -= 1

    cnt = [0] * NCELL
    for i in range(NCELL):
        if cells[i]:
            continue
        r, c = divmod(i, BW)
        n = 0
        for rr in range(max(0, r - 1), min(BH - 1, r + 1) + 1):
            for cc in range(max(0, c - 1), min(BW - 1, c + 1) + 1):
                if (rr, cc) != (r, c) and cells[rr * BW + cc]:
                    n += 1
        cnt[i] = n
    return cells, cnt


def reveal(seed, first):
    """第一次翻开 first 之后的棋盘, opened[i] 为真表示已翻开"""
    cells, cnt = place(seed, first)
    opened = [False] * NCELL
    if not cells[first]:
        stack = [first]
        opened[first] = True
        while stack:
            k = stack.pop()
            if cnt[k]:
                continue
            r, c = divmod(k, BW)
            for rr in range(max(0, r - 1), min(BH - 1, r + 1) + 1):
                for cc in range(max(0, c - 1), min(BW - 1, c + 1) + 1):
                    nb = rr * BW + cc
                    if nb != k and not opened[nb]:
                        opened[nb] = True
                        stack.append(nb)
    return cells, cnt, opened


def render(seed, first):
    cells, cnt, opened = reveal(seed, first)
    rows = []
    for r in range(BH):
        line = ""
        for c in range(BW):
            i = r * BW + c
            if not opened[i]:
                ch = "#"
            elif cells[i]:
                ch = "*"
            elif cnt[i] == 0:
                ch = " "
            else:
                ch = str(cnt[i])
            line += ch + " "
        rows.append(line)
    return cells, cnt, opened, rows


if __name__ == "__main__":
    import sys

    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    cells, cnt, opened, rows = render(seed, first)
    print("seed=%d first=%d" % (seed, first))
    for r in range(BH):
        print("%d |%s|" % (r, rows[r]))
    mines = [divmod(i, BW) for i in range(NCELL) if cells[i]]
    print("mines(row,col):", mines)
    print("opened:", sum(opened), "of", NCELL)

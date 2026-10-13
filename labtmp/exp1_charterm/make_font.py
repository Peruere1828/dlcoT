#!/usr/bin/env python3
# ======================================================================
# make_font.py --- lab08 字符终端点阵字模生成器
#
# 把 DejaVuSansMono-Bold 的 ASCII 0x20~0x7F 共 96 个字符二值化为
# 9 列 x 16 行 的点阵, 并导出为 charterm_top.v 可用的字模文件。
#
# 存储约定 (与 charterm_top.v 一致):
#   - 每个字符一个 144bit 字, 第 l 行占 font_pack[l*9 +: 9]
#   - 每行 bit0 = 最左边一个点, 为 1 表示该点显示白色
#   - 字符 c 的字模位于 font_rom[c - 0x20]
#
# 默认输出 font.mem: 96 行, 每行一个 36 位十六进制数 (144bit),
# 由 charterm_top.v 用 $readmemh("font.mem", font_rom) 载入。
# 加 --verilog 则改写为单文件用的 case 常量块, 便于仍想保持
# 单文件上板的场景。
#
# 依赖: Pillow (pip install pillow)
# ======================================================================

import argparse
import os
import sys

CELL_W = 9          # 字宽, 列
CELL_H = 16         # 字高, 行
BASE = 0x20         # 字模起始 ASCII
COUNT = 96          # 0x20 ~ 0x7F

# 渲染参数。size=15 / threshold=111 是对着仓库里已有的 96 个字模
# 反推出来的: 用系统 DejaVuSansMono-Bold 渲染后, 这两个参数能让
# 96 个字符逐位与 charterm_top.v 中内嵌的常量完全一致。
DEFAULT_SIZE = 15
DEFAULT_THRESHOLD = 111

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf",
    os.path.expanduser("~/.fonts/DejaVuSansMono-Bold.ttf"),
]


def find_font(explicit=None):
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit("字体文件不存在: {}".format(explicit))
        return explicit
    for p in FONT_CANDIDATES:
        if os.path.isfile(p):
            return p
    # 退而求其次, 在 matplotlib 自带的字体里找
    try:
        import matplotlib
        p = os.path.join(os.path.dirname(matplotlib.__file__),
                         "mpl-data", "fonts", "ttf",
                         "DejaVuSansMono-Bold.ttf")
        if os.path.isfile(p):
            return p
    except Exception:
        pass
    sys.exit("找不到 DejaVuSansMono-Bold.ttf, 请用 --font 指定路径")


def render_glyph(ch, font_path, size, threshold):
    """渲染单个字符, 返回 144bit 整数 (第 l 行占 bit [l*9 +: 9])."""
    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype(font_path, size)
    # 画布留出余量, 字模窗口固定在 (0, 2) 处截取 9x16。
    img = Image.new("L", (CELL_W + 8, CELL_H + 8), 0)
    ImageDraw.Draw(img).text((0, 0), ch, fill=255, font=font)

    value = 0
    for r in range(CELL_H):
        for c in range(CELL_W):
            if img.getpixel((c, 2 + r)) >= threshold:
                value |= 1 << (r * CELL_W + c)
    return value


def build_table(font_path, size, threshold):
    table = []
    for code in range(BASE, BASE + COUNT):
        table.append(render_glyph(chr(code), font_path, size, threshold))
    return table


def write_mem(table, path):
    with open(path, "w") as f:
        for value in table:
            f.write("{:036X}\n".format(value))


def write_verilog(table, path):
    lines = []
    for i, value in enumerate(table):
        code = BASE + i
        ch = chr(code)
        shown = ch if (0x21 <= code <= 0x7E) else ("SP" if code == 0x20 else "")
        lines.append("            7'd{}: font_pack = 144'h{:036X};  // 0x{:02X} {}".format(
            i, value, code, shown))
    text = ("// --- 由 make_font.py 生成, 勿手改 ---\n"
            "    reg [143:0] font_pack;\n"
            "    always @(*) begin\n"
            "        case (cidx)\n"
            + "\n".join(lines) + "\n"
            "            default: font_pack = 144'h0;\n"
            "        endcase\n"
            "    end\n")
    if path:
        with open(path, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


def preview(table):
    for i, value in enumerate(table):
        code = BASE + i
        if code in (0x20, 0x7F):
            continue
        print("'{}' 0x{:02X}".format(chr(code), code))
        for r in range(CELL_H):
            row = (value >> (r * CELL_W)) & 0x1FF
            print("   " + "".join("#" if (row >> b) & 1 else "." for b in range(CELL_W)))


def check(table, verilog_path):
    """与已有 verilog 中内嵌的 font_pack 常量逐个比对。"""
    import re
    text = open(verilog_path).read()
    pairs = re.findall(r"7'd(\d+): font_pack = 144'h([0-9A-Fa-f]+);", text)
    if len(pairs) != COUNT:
        print("参考文件里解析出 {} 个字符, 期望 {}".format(len(pairs), COUNT))
        return False
    ok = True
    for i, h in pairs:
        if table[int(i)] != int(h, 16):
            print("MISMATCH cidx {}: gen {:036X} != ref {}".format(i, table[int(i)], h))
            ok = False
    print("CHECK PASSED: {}/{} 一致".format(COUNT, COUNT) if ok else "CHECK FAILED")
    return ok


def main():
    ap = argparse.ArgumentParser(description="lab08 点阵字模生成器")
    ap.add_argument("--font", help="DejaVuSansMono-Bold.ttf 路径")
    ap.add_argument("--size", type=int, default=DEFAULT_SIZE, help="字号, 默认 15")
    ap.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD,
                    help="二值化阈值 0~255, 默认 111")
    ap.add_argument("-o", "--output", default="font.mem",
                    help="输出文件, 默认 font.mem")
    ap.add_argument("--verilog", nargs="?", const="-", metavar="PATH",
                    help="输出单文件用的 case 常量块; 省略 PATH 时打印到 stdout")
    ap.add_argument("--preview", action="store_true", help="打印全部字模预览")
    ap.add_argument("--check", metavar="VERILOG",
                    help="与指定 .v 中内嵌的 font_pack 常量比对")
    args = ap.parse_args()

    font_path = find_font(args.font)
    table = build_table(font_path, args.size, args.threshold)

    if args.check:
        sys.exit(0 if check(table, args.check) else 1)

    if args.verilog is not None:
        write_verilog(table, None if args.verilog == "-" else args.verilog)
        if args.verilog != "-":
            print("已写入 Verilog: {}".format(args.verilog))
    else:
        write_mem(table, args.output)
        print("已写入 {} ({} 字符, 每行 144bit)".format(args.output, COUNT))

    if args.preview:
        preview(table)


if __name__ == "__main__":
    main()

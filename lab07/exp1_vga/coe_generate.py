#!/usr/bin/env python3
"""Convert an image to a VGA display-memory .coe file for lab07.

This is the course-provided reference converter (`lab7/coe_generate.py`) after
being adapted so it can actually be used with the lab07 display memory.  The
original version scans the image line by line, does not resize the picture and
does not pad the columns, so it neither matches the {h_addr, v_addr[8:0]}
address mapping nor produces the required 640 x 512 x 12 bit memory.

Fixes applied here:
  * resize the picture to 640 x 480;
  * write the pixels column-major, i.e. outer loop over the column x and
    inner loop over the row y, so that a column of 512 words is contiguous;
  * pad every column to 512 rows, giving 640*512 = 327680 words of 12 bits
    {R[3:0], G[3:0], B[3:0]}; the 32 padding rows are never scanned, and they
    are filled with 0xFFF to match the course sample coe file;
  * when the picture has an alpha channel, crop away the transparent border
    before resizing (this is what the course sample picture needs).

Usage:
    python coe_generate.py path-to-picture-file [out.coe]

The output is written to out.coe, or to the file given as the second argument.
"""

import sys
from PIL import Image

WIDTH = 640
HEIGHT = 480
ROWS = 512


def load_image(path):
    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bbox = im.split()[-1].getbbox()
        if bbox and bbox != (0, 0, im.size[0], im.size[1]):
            im = im.crop(bbox)
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im)
    im = im.convert("RGB")
    if im.size != (WIDTH, HEIGHT):
        im = im.resize((WIDTH, HEIGHT))
    return im


def generate(pic_path, coe_path):
    im = load_image(pic_path)
    pix = im.load()
    print("image width=%d,height=%d" % (WIDTH, HEIGHT))

    total = WIDTH * ROWS
    idx = 0
    with open(coe_path, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for x in range(WIDTH):
            for y in range(ROWS):
                if y < HEIGHT:
                    r, g, b = pix[x, y]
                else:
                    r = g = b = 0xF0
                r = (r & 0xF0) >> 4
                g = (g & 0xF0) >> 4
                b = (b & 0xF0) >> 4
                idx += 1
                f.write("%X%X%X" % (r, g, b))
                f.write(";\n" if idx == total else ",\n")
    print("finish successful!! total %d words" % total)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python coe_generate.py path-to-picture-file [out.coe]")
        sys.exit(1)
    out = sys.argv[2] if len(sys.argv) >= 3 else "out.coe"
    generate(sys.argv[1], out)

#!/usr/bin/env python3
"""Convert an image to a VGA display-memory .coe file for lab07.

Memory layout follows the lab manual: the display memory holds
640 x 512 words of 12 bits ({R[3:0], G[3:0], B[3:0]}) and the address is
{h_addr[9:0], v_addr[8:0]}, so the pixels of one column are stored
contiguously, i.e. the data is column-major.

Usage:
    python img2coe.py [input_image] [output_coe]

Without arguments a colourful 640x480 test pattern is generated and written
to vga_image.coe.  Any image format Pillow can read works; if the picture has
an alpha channel its transparent border is cropped away first, then the image
is resized to 640x480 and each colour channel is truncated to 4 bits.  This
matches the course sample picture, whose transparent frame surrounds the real
640x480 content.
"""

import sys
from PIL import Image, ImageDraw, ImageFont

WIDTH = 640
HEIGHT = 480
ROWS = 512
BAR_H = 60


def default_image():
    img = Image.new("RGB", (WIDTH, HEIGHT))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            img.putpixel((x, y), (x * 255 // (WIDTH - 1), 40,
                                  y * 255 // (HEIGHT - 1)))

    d = ImageDraw.Draw(img)
    bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
            (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
    bw = WIDTH // len(bars)
    for i, c in enumerate(bars):
        d.rectangle([i * bw, 0, (i + 1) * bw - 1, BAR_H], fill=c)

    d.rectangle([0, 0, 40, 40], fill=(255, 0, 0))
    d.rectangle([WIDTH - 41, 0, WIDTH - 1, 40], fill=(0, 255, 0))
    d.rectangle([0, HEIGHT - 41, 40, HEIGHT - 1], fill=(0, 0, 255))
    d.rectangle([WIDTH - 41, HEIGHT - 41, WIDTH - 1, HEIGHT - 1], fill=(255, 255, 0))
    d.rectangle([0, 0, WIDTH - 1, HEIGHT - 1], outline=(255, 255, 255), width=2)

    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 72)
    except Exception:
        font = ImageFont.load_default()
    text = "NEXYS A7"
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((WIDTH - tw) // 2 - bbox[0], (HEIGHT - th) // 2 - bbox[1] - 40),
           text, fill=(255, 255, 255), font=font)
    return img


def load_image(path):
    img = Image.open(path)
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        bbox = img.split()[-1].getbbox()
        if bbox and bbox != (0, 0, img.size[0], img.size[1]):
            img = img.crop(bbox)
        bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img = Image.alpha_composite(bg, img)
    img = img.convert("RGB")
    if img.size != (WIDTH, HEIGHT):
        img = img.resize((WIDTH, HEIGHT))
    return img


def word_at(img, x, y):
    r, g, b = img.getpixel((x, y))
    return ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)


def write_coe(img, path):
    words = []
    for x in range(WIDTH):
        for y in range(ROWS):
            if y < HEIGHT:
                words.append(word_at(img, x, y))
            else:
                words.append(0xFFF)

    with open(path, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, w in enumerate(words):
            sep = "," if i != len(words) - 1 else ";"
            f.write("%03X%s\n" % (w, sep))
    return len(words)


def main():
    if len(sys.argv) >= 2:
        img = load_image(sys.argv[1])
    else:
        img = default_image()
    out = sys.argv[2] if len(sys.argv) >= 3 else "vga_image.coe"
    n = write_coe(img, out)
    print("wrote %s with %d words (%d x %d)" % (out, n, WIDTH, ROWS))


if __name__ == "__main__":
    main()

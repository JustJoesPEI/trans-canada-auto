#!/usr/bin/env python3
"""Draws the flags flown in town: textures/flags/canada.png and pei.png.

Both are 2:1 images (256 x 128) drawn from simple shapes, readable at the
distance you see a flag from a street, not exact heraldry. Run from the repo
root:  python3 tools/make_flags.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 512, 256
OUT = Path(__file__).resolve().parent.parent / "textures" / "flags"

RED = (213, 43, 30)
WHITE = (250, 250, 248)
GOLD = (236, 184, 40)
GREEN = (40, 120, 50)

# The Canadian maple leaf, right half from the top point down to the stem,
# on a 100 x 100 box (x right, y down). Mirrored for the left half.
LEAF_RIGHT = [(50, 0), (57, 13), (65, 9), (62, 36), (74, 22), (77, 30), (90, 27), (86, 41),
              (93, 45), (72, 62), (75, 71), (53, 68), (54, 92)]


def canada() -> Image.Image:
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    # Red, white, red: the bands a quarter of the length each.
    d.rectangle([0, 0, W // 4 - 1, H], fill=RED)
    d.rectangle([W * 3 // 4, 0, W, H], fill=RED)
    pts = LEAF_RIGHT + [(100 - x, y) for x, y in reversed(LEAF_RIGHT)]
    size = H * 0.78
    ox, oy = W / 2 - size / 2, H * 0.1
    d.polygon([(ox + x / 100 * size, oy + y / 100 * size) for x, y in pts], fill=RED)
    return img


def pei() -> Image.Image:
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    # A red-and-white border on the three sides away from the pole.
    b = 16
    step = 24
    for x in range(0, W, step):
        for y in (0, H - b):
            if (x // step) % 2 == 0:
                d.rectangle([x, y, x + step - 1, y + b - 1], fill=RED)
    for y in range(0, H, step):
        if (y // step) % 2 == 0:
            d.rectangle([W - b, y, W - 1, y + step - 1], fill=RED)
    inner_w = W - b
    # The top third: red, with the gold lion walking toward the pole.
    top = b + (H - 2 * b) // 3
    d.rectangle([0, b, inner_w - 1, top], fill=RED)
    cx, cy = inner_w * 0.5, (b + top) / 2
    s = (top - b) / 60.0
    d.ellipse([cx - 40 * s, cy - 10 * s, cx + 30 * s, cy + 14 * s], fill=GOLD)          # body
    d.ellipse([cx - 58 * s, cy - 24 * s, cx - 30 * s, cy + 4 * s], fill=GOLD)           # head and mane
    for lx in (-34, -20, 12, 24):                                                       # legs
        d.rectangle([cx + lx * s, cy + 6 * s, cx + (lx + 6) * s, cy + 24 * s], fill=GOLD)
    d.line([(cx + 28 * s, cy), (cx + 42 * s, cy - 18 * s), (cx + 36 * s, cy - 26 * s)], fill=GOLD, width=max(2, int(4 * s)))
    # Below: an island of green with a big oak and three saplings.
    ground = H - b - 22
    d.rectangle([24, ground, inner_w - 24, ground + 8], fill=GREEN)
    ox = inner_w * 0.7
    d.rectangle([ox - 6, ground - 60, ox + 6, ground], fill=(90, 70, 40))
    d.ellipse([ox - 52, ground - 118, ox + 52, ground - 40], fill=GREEN)
    for k in range(3):
        sx = inner_w * 0.18 + k * 42
        d.rectangle([sx - 3, ground - 26, sx + 3, ground], fill=(90, 70, 40))
        d.ellipse([sx - 16, ground - 58, sx + 16, ground - 20], fill=GREEN)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    canada().save(OUT / "canada.png")
    pei().save(OUT / "pei.png")
    print("wrote", OUT / "canada.png", "and", OUT / "pei.png")


if __name__ == "__main__":
    main()

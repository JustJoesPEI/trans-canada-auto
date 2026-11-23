#!/usr/bin/env python3
"""Draws the crosswalk signs: textures/signs/crosswalk_overhead.png (the red
board that hangs over the street, "CROSS X WALK") and crosswalk_side.png
(the white square sign with a walking figure on the posts each side).

Plain shapes and the built-in font, sized to read from a car. Run from the
repo root:  python3 tools/make_crosswalk_signs.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "textures" / "signs"
RED = (205, 58, 40)
WHITE = (248, 248, 244)
BLACK = (20, 20, 20)


def overhead() -> Image.Image:
    # 4:1, like a 3 m x 0.75 m board.
    w, h = 1024, 256
    img = Image.new("RGB", (w, h), RED)
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, w - 7, h - 7], outline=WHITE, width=8)
    font = ImageFont.load_default(size=112)
    for text, cx in (("CROSS", w * 0.215), ("WALK", w * 0.79)):
        box = d.textbbox((0, 0), text, font=font)
        tw, th = box[2] - box[0], box[3] - box[1]
        d.text((cx - tw / 2 - box[0], h / 2 - th / 2 - box[1]), text, font=font, fill=WHITE)
    # The X between the words, on a white square.
    s = h * 0.36
    cx, cy = w / 2, h / 2
    d.rectangle([cx - s, cy - s, cx + s, cy + s], fill=WHITE)
    k = s * 0.72
    d.line([(cx - k, cy - k), (cx + k, cy + k)], fill=BLACK, width=26)
    d.line([(cx - k, cy + k), (cx + k, cy - k)], fill=BLACK, width=26)
    return img


def side() -> Image.Image:
    n = 256
    img = Image.new("RGB", (n, n), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([4, 4, n - 5, n - 5], outline=BLACK, width=8)
    # A walking figure, striding to the right.
    d.ellipse([118, 34, 150, 66], fill=BLACK)                        # head
    d.line([(132, 74), (118, 150)], fill=BLACK, width=22)            # body
    d.line([(118, 150), (86, 222)], fill=BLACK, width=18)            # back leg
    d.line([(118, 150), (150, 186), (168, 224)], fill=BLACK, width=18, joint="curve")  # front leg
    d.line([(128, 92), (96, 128)], fill=BLACK, width=14)             # back arm
    d.line([(128, 92), (160, 116), (176, 136)], fill=BLACK, width=14, joint="curve")   # front arm
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    overhead().save(OUT / "crosswalk_overhead.png")
    side().save(OUT / "crosswalk_side.png")
    print("wrote", OUT / "crosswalk_overhead.png", "and", OUT / "crosswalk_side.png")


if __name__ == "__main__":
    main()

"""Draws textures/foliage/needle_branch.png: one spruce branch seen from
above, running left (trunk end) to right (tip), with side shoots covered in
short needles, on a transparent background. The spruce cards use it.

Run: python3 tools/make_needle_branch.py   (needs Pillow)
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 1024, 512
OUT = Path(__file__).resolve().parent.parent / "textures" / "foliage" / "needle_branch.png"


def shoot(d, x0, y0, x1, y1, rnd, needle_len, depth):
    d.line([(x0, y0), (x1, y1)], fill=(70, 55, 40, 255), width=4 if depth == 0 else 2)
    n = int(math.hypot(x1 - x0, y1 - y0) / 3)
    ang = math.atan2(y1 - y0, x1 - x0)
    for i in range(n):
        t = i / max(1, n - 1)
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for side in (-1, 1):
            a = ang + side * rnd.uniform(0.6, 1.2)
            ln = needle_len * rnd.uniform(0.7, 1.1) * (0.6 + 0.4 * (1 - abs(t - 0.5) * 2) if depth else 1.0)
            g = rnd.uniform(0.8, 1.15)
            tipward = t
            col = (int((28 + 22 * tipward) * g), int((52 + 34 * tipward) * g), int((36 + 18 * tipward) * g), 255)
            d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=col, width=3)


def main():
    rnd = random.Random(55)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = H / 2
    # Side shoots, longest in the middle of the branch.
    for i in range(34):
        t = 0.05 + 0.9 * i / 33
        x = W * t
        span = math.sin(math.pi * min(1.0, t * 1.1)) * H * 0.42
        for side in (-1, 1):
            a = side * rnd.uniform(0.5, 0.9)
            ln = span * rnd.uniform(0.75, 1.0)
            shoot(d, x, cy, x + math.cos(a) * ln * 0.8, cy + math.sin(a) * ln, rnd, 22, 1)
    shoot(d, 0, cy, W * 0.97, cy + rnd.uniform(-10, 10), rnd, 18, 0)
    rgb = img.convert("RGB")
    alpha = img.getchannel("A")
    bled = rgb
    for _ in range(6):
        bled = bled.filter(ImageFilter.MaxFilter(5))
    out = Image.composite(rgb, bled, alpha)
    out.putalpha(alpha)
    out.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

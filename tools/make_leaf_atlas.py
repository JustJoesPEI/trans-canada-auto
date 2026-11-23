"""Draws textures/foliage/leaf_cluster.png: a clump of broadleaf leaves on
thin twigs, with a transparent background, for the tree crown cards.

Run: python3 tools/make_leaf_atlas.py   (needs Pillow and numpy)
Every leaf is a pointed oval with a midrib, in a range of greens (lighter and
yellower on top, darker underneath), packed densely in the middle and thinning
toward a ragged edge, so a crown made of these cards has gaps and a leafy
outline. Seeded, so it draws the same every time.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = Path(__file__).resolve().parent.parent / "textures" / "foliage" / "leaf_cluster.png"


def leaf(draw, cx, cy, length, width, angle, colour, rib):
    pts = []
    for i in range(24):
        t = i / 23.0
        # Pointed at both ends, widest just below the middle.
        w = width * math.sin(math.pi * t) ** 0.8 * (1.0 - 0.25 * t)
        pts.append((t * length - length * 0.5, w))
    outline = pts + [(x, -y) for x, y in reversed(pts)]
    ca, sa = math.cos(angle), math.sin(angle)
    poly = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in outline]
    draw.polygon(poly, fill=colour)
    draw.line([(cx - length * 0.45 * ca, cy - length * 0.45 * sa), (cx + length * 0.45 * ca, cy + length * 0.45 * sa)], fill=rib, width=2)


def main():
    rnd = random.Random(1867)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Twigs radiating from the bottom middle.
    twig_tips = []
    for _ in range(9):
        a = rnd.uniform(-2.6, -0.5)
        x0, y0 = S * 0.5 + rnd.uniform(-60, 60), S * 0.9
        ln = rnd.uniform(S * 0.5, S * 0.8)
        x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
        d.line([(x0, y0), (x1, y1)], fill=(70, 55, 40, 255), width=6)
        twig_tips.append((x0, y0, x1, y1))
    # Leaves, back (darker) to front (lighter).
    n = 1100
    for i in range(n):
        if rnd.random() < 0.55:
            x0, y0, x1, y1 = rnd.choice(twig_tips)
            t = rnd.uniform(0.3, 1.0)
            bx, by = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        else:
            a, rr = rnd.uniform(0, math.tau), S * 0.4 * math.sqrt(rnd.random())
            bx, by = S / 2 + math.cos(a) * rr, S * 0.48 + math.sin(a) * rr
        r = rnd.gauss(0, S * 0.06)
        cx = bx + rnd.uniform(-1, 1) * abs(r)
        cy = by + rnd.uniform(-1, 1) * abs(r)
        # Keep inside a rough circle so the card's edge never shows.
        dx, dy = cx - S / 2, cy - S * 0.48
        if math.hypot(dx, dy) > S * 0.46:
            continue
        depth = i / n
        g = rnd.uniform(0.85, 1.15)
        base = (42 + 48 * depth, 66 + 52 * depth, 30 + 20 * depth)
        yellow = rnd.random() < 0.12
        col = (int(min(255, base[0] * g * (1.25 if yellow else 1.0))), int(min(255, base[1] * g)), int(min(255, base[2] * g * (0.8 if yellow else 1.0))), 255)
        rib = (int(col[0] * 1.15), int(min(255, col[1] * 1.12)), int(col[2] * 1.05), 255)
        length = rnd.uniform(40, 68)
        leaf(d, cx, cy, length, length * rnd.uniform(0.28, 0.4), rnd.uniform(0, math.tau), col, rib)
    # Bleed colour into the transparent pixels round the leaves, so mipmaps
    # don't pull dark fringes in from the empty background.
    rgb = img.convert("RGB")
    alpha = img.getchannel("A")
    bled = rgb
    for _ in range(6):
        bled = bled.filter(ImageFilter.MaxFilter(5))
    out = Image.composite(rgb, bled, alpha)
    out.putalpha(alpha)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

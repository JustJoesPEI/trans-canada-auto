"""Draws textures/foliage/leaf_cluster.png: four clumps of broadleaf leaves
(a 2x2 atlas) with a transparent background, for the tree crown cards.

Run: python3 tools/make_leaf_atlas.py   (needs Pillow)
Each clump is a ragged, roughly round spray of small pointed leaves on thin
twigs: dense in the middle, thinning to single leaves at the edge, so a
crown built from these cards has a leafy outline and gaps. Leaves are drawn
back to front, darker behind, lighter and yellower in front, with the odd
leaf turned to show its paler underside. Seeded, so it draws the same every
time.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CELL = 512
S = CELL * 2
OUT = Path(__file__).resolve().parent.parent / "textures" / "foliage" / "leaf_cluster.png"


def leaf(draw, cx, cy, length, width, angle, colour, rib):
    ca, sa = math.cos(angle), math.sin(angle)
    # Two halves either side of the midrib, one a shade darker, as a leaf
    # folds slightly along it and catches the light on one side.
    for side, k in ((1, 1.0), (-1, 0.82)):
        pts = [(-length * 0.5, 0.0)]
        for i in range(1, 15):
            t = i / 15.0
            w = width * math.sin(math.pi * t) ** 0.75 * (1.0 - 0.3 * t)
            pts.append((t * length - length * 0.5, w * side))
        pts.append((length * 0.5, 0.0))
        col = tuple(int(c * k) for c in colour[:3]) + (255,)
        draw.polygon([(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts], fill=col)
    draw.line([(cx - length * 0.5 * ca, cy - length * 0.5 * sa), (cx + length * 0.4 * ca, cy + length * 0.4 * sa)], fill=rib, width=1)


def clump(img, ox, oy, rnd):
    d = ImageDraw.Draw(img)
    c = (ox + CELL / 2, oy + CELL / 2)
    # A ragged outline: radius varies round the clump.
    lobes = [rnd.uniform(0.7, 1.0) for _ in range(9)]

    def edge(a):
        f = a / math.tau * 9
        i = int(f) % 9
        t = f - int(f)
        return (lobes[i] * (1 - t) + lobes[(i + 1) % 9] * t) * CELL * 0.45

    # Twigs from the middle outward.
    for _ in range(7):
        a = rnd.uniform(0, math.tau)
        r = edge(a) * 0.85
        d.line([c, (c[0] + math.cos(a) * r, c[1] + math.sin(a) * r)], fill=(72, 58, 44, 255), width=3)
    n = 620
    for i in range(n):
        a = rnd.uniform(0, math.tau)
        r = edge(a) * math.sqrt(rnd.random())
        x, y = c[0] + math.cos(a) * r, c[1] + math.sin(a) * r
        depth = i / n
        under = rnd.random() < 0.08
        g = rnd.uniform(0.82, 1.18)
        base = (52 + 46 * depth, 74 + 50 * depth, 38 + 18 * depth)
        if under:
            base = (base[0] * 1.25, base[1] * 1.2, base[2] * 1.3)
        yellow = rnd.random() < 0.05
        col = (int(min(255, base[0] * g * (1.2 if yellow else 1.0))), int(min(255, base[1] * g)), int(min(255, base[2] * g * (0.8 if yellow else 1.0))), 255)
        rib = (int(min(255, col[0] * 1.15)), int(min(255, col[1] * 1.1)), int(min(255, col[2] * 1.05)), 255)
        ln = rnd.uniform(20, 32)
        # Leaves hang outward from the middle, give or take.
        ang = a + rnd.uniform(-0.9, 0.9)
        leaf(d, x, y, ln, ln * rnd.uniform(0.3, 0.42), ang, col, rib)


def main():
    rnd = random.Random(1867)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for cy in range(2):
        for cx in range(2):
            clump(img, cx * CELL, cy * CELL, rnd)
    # Bleed colour into the empty pixels so mipmaps don't pull in dark fringes.
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

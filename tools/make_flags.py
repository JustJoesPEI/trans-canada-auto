#!/usr/bin/env python3
"""Draws the flags flown in town.

textures/flags/canada.png and pei.png fly on their own poles (the war
memorial). textures/flags/atlas.png holds every flag in the row at the city
entrance (Riverside Drive at the Hillsborough Bridge): Canada, the city, and
every province and territory, one 512 x 256 cell each, with atlas.json
saying which cell is which (Monuments reads it).

All are 2:1 images drawn from simple shapes, readable at the distance you
see a flag from a street, not exact heraldry. Run from the repo root:
python3 tools/make_flags.py
"""
import json
import math
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


BLUE = (0, 40, 120)
NAVY = (10, 30, 90)
SKY = (0, 90, 180)
YELLOW = (250, 205, 30)
BLACK = (20, 20, 20)
BROWN = (120, 80, 40)


def union_jack(d: ImageDraw.ImageDraw, x0: float, y0: float, x1: float, y1: float) -> None:
    """The Union flag filling a box."""
    w, h = x1 - x0, y1 - y0
    d.rectangle([x0, y0, x1, y1], fill=NAVY)
    t = h * 0.2
    d.line([(x0, y0), (x1, y1)], fill=WHITE, width=int(t))
    d.line([(x0, y1), (x1, y0)], fill=WHITE, width=int(t))
    d.line([(x0, y0), (x1, y1)], fill=RED, width=int(t * 0.4))
    d.line([(x0, y1), (x1, y0)], fill=RED, width=int(t * 0.4))
    cx, cy = x0 + w / 2, y0 + h / 2
    d.rectangle([cx - h * 0.17, y0, cx + h * 0.17, y1], fill=WHITE)
    d.rectangle([x0, cy - h * 0.17, x1, cy + h * 0.17], fill=WHITE)
    d.rectangle([cx - h * 0.1, y0, cx + h * 0.1, y1], fill=RED)
    d.rectangle([x0, cy - h * 0.1, x1, cy + h * 0.1], fill=RED)


def shield(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, top, bottom) -> None:
    """A plain heater shield: `top` chief over a `bottom` field, gold edge."""
    w, h = s, s * 1.2
    pts = [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h * 0.1),
           (cx, cy + h / 2), (cx - w / 2, cy + h * 0.1)]
    d.polygon(pts, fill=bottom, outline=GOLD, width=max(2, int(s * 0.04)))
    d.rectangle([cx - w / 2 + 3, cy - h / 2 + 3, cx + w / 2 - 3, cy - h * 0.18], fill=top)


def lion(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, colour) -> None:
    """A lion walking left, made of blobs (PEI's, smaller)."""
    d.ellipse([cx - 40 * s, cy - 10 * s, cx + 30 * s, cy + 14 * s], fill=colour)
    d.ellipse([cx - 58 * s, cy - 24 * s, cx - 30 * s, cy + 4 * s], fill=colour)
    for lx in (-34, -20, 12, 24):
        d.rectangle([cx + lx * s, cy + 6 * s, cx + (lx + 6) * s, cy + 24 * s], fill=colour)
    d.line([(cx + 28 * s, cy), (cx + 42 * s, cy - 18 * s)], fill=colour, width=max(2, int(4 * s)))


def star(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, colour, points: int = 5) -> None:
    pts = []
    for i in range(points * 2):
        a = -math.pi / 2 + i * math.pi / points
        rr = r if i % 2 == 0 else r * 0.42
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=colour)


def fleur(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, colour) -> None:
    """A fleur-de-lis, simplified: a tall petal, two curls, a band."""
    d.polygon([(cx, cy - 22 * s), (cx + 7 * s, cy - 4 * s), (cx, cy + 6 * s), (cx - 7 * s, cy - 4 * s)], fill=colour)
    d.ellipse([cx - 22 * s, cy - 12 * s, cx - 8 * s, cy + 4 * s], fill=colour)
    d.ellipse([cx + 8 * s, cy - 12 * s, cx + 22 * s, cy + 4 * s], fill=colour)
    d.rectangle([cx - 14 * s, cy + 2 * s, cx + 14 * s, cy + 7 * s], fill=colour)
    d.polygon([(cx - 4 * s, cy + 7 * s), (cx + 4 * s, cy + 7 * s), (cx, cy + 20 * s)], fill=colour)


def _new(colour=WHITE):
    img = Image.new("RGB", (W, H), colour)
    return img, ImageDraw.Draw(img)


def red_ensign(field_shield) -> Image.Image:
    """Ontario and Manitoba: the red ensign with the province's shield on the fly."""
    img, d = _new(RED)
    union_jack(d, 0, 0, W / 2, H / 2)
    field_shield(d, W * 0.75, H * 0.5, H * 0.42)
    return img


def ontario() -> Image.Image:
    return red_ensign(lambda d, x, y, s: (shield(d, x, y, s, RED, GREEN), _maples(d, x, y + s * 0.15, s)))


def _maples(d, x, y, s):
    for k in (-1, 0, 1):
        star(d, x + k * s * 0.25, y, s * 0.1, GOLD, 7)


def manitoba() -> Image.Image:
    def bison(d, x, y, s):
        shield(d, x, y, s, WHITE, GREEN)
        d.rectangle([x - s * 0.5 + 4, y - s * 0.6 + 4, x + s * 0.5 - 4, y - s * 0.3], fill=WHITE)
        d.line([(x - s * 0.5 + 4, y - s * 0.38), (x + s * 0.5 - 4, y - s * 0.52)], fill=RED, width=int(s * 0.12))
        d.ellipse([x - s * 0.3, y - s * 0.12, x + s * 0.25, y + s * 0.22], fill=BROWN)
        d.ellipse([x - s * 0.4, y - s * 0.12, x - s * 0.15, y + s * 0.12], fill=BROWN)
    return red_ensign(bison)


def quebec() -> Image.Image:
    img, d = _new(SKY)
    t = H * 0.2
    d.rectangle([W / 2 - t / 2, 0, W / 2 + t / 2, H], fill=WHITE)
    d.rectangle([0, H / 2 - t / 2, W, H / 2 + t / 2], fill=WHITE)
    for fx in (W * 0.25, W * 0.75):
        for fy in (H * 0.25, H * 0.75):
            fleur(d, fx, fy, H / 110, WHITE)
    return img


def nova_scotia() -> Image.Image:
    img, d = _new(WHITE)
    t = H * 0.22
    d.line([(0, 0), (W, H)], fill=SKY, width=int(t))
    d.line([(0, H), (W, 0)], fill=SKY, width=int(t))
    s = H * 0.32
    d.rectangle([W / 2 - s / 2, H / 2 - s / 2, W / 2 + s / 2, H / 2 + s / 2], fill=GOLD)
    d.rectangle([W / 2 - s / 2 + 8, H / 2 - s / 2 + 8, W / 2 + s / 2 - 8, H / 2 + s / 2 - 8], outline=RED, width=5)
    lion(d, W / 2 + 4, H / 2, s / 140, RED)
    return img


def new_brunswick() -> Image.Image:
    img, d = _new(GOLD)
    d.rectangle([0, 0, W, H * 0.3], fill=RED)
    lion(d, W / 2, H * 0.14, H / 380, GOLD)
    # The galley on the waves.
    y = H * 0.62
    d.polygon([(W * 0.22, y), (W * 0.78, y), (W * 0.7, y + H * 0.12), (W * 0.3, y + H * 0.12)], fill=BLACK)
    d.rectangle([W * 0.49, y - H * 0.28, W * 0.51, y], fill=BLACK)
    d.rectangle([W * 0.4, y - H * 0.24, W * 0.6, y - H * 0.08], fill=BLACK)
    for k in range(3):
        yy = y + H * 0.17 + k * H * 0.07
        for x in range(0, W, 48):
            d.arc([x, yy - 10, x + 48, yy + 10], 180, 360, fill=SKY, width=7)
    return img


def british_columbia() -> Image.Image:
    img, d = _new(WHITE)
    union_jack(d, 0, 0, W, H * 0.4)
    for k in range(4):
        y0 = H * 0.55 + k * H * 0.12
        for x in range(0, W, 64):
            d.arc([x, y0 - 14, x + 64, y0 + 14], 180, 360, fill=SKY, width=14)
    d.rectangle([0, H * 0.92, W, H], fill=SKY)
    d.pieslice([W * 0.3, H * 0.33, W * 0.7, H * 0.95], 180, 360, fill=GOLD)
    for a in range(190, 360, 18):
        r = math.radians(a)
        cx, cy = W * 0.5, H * 0.64
        d.line([(cx + math.cos(r) * W * 0.2, cy + math.sin(r) * H * 0.3),
                (cx + math.cos(r) * W * 0.26, cy + math.sin(r) * H * 0.42)], fill=GOLD, width=5)
    return img


def saskatchewan() -> Image.Image:
    img, d = _new(GREEN)
    d.rectangle([0, H / 2, W, H], fill=GOLD)
    shield(d, W * 0.2, H * 0.27, H * 0.3, RED, GREEN)
    # The western red lily on the fly.
    cx, cy = W * 0.8, H * 0.35
    for k in range(6):
        a = math.radians(k * 60 - 90)
        d.ellipse([cx + math.cos(a) * 22 - 14, cy + math.sin(a) * 22 - 14, cx + math.cos(a) * 22 + 14, cy + math.sin(a) * 22 + 14], fill=(220, 70, 20))
    d.line([(cx, cy), (cx, H * 0.85)], fill=(30, 90, 30), width=6)
    return img


def alberta() -> Image.Image:
    img, d = _new(BLUE)
    cx, cy, s = W / 2, H * 0.5, H * 0.55
    shield(d, cx, cy, s, (200, 30, 30), GOLD)
    d.rectangle([cx - s / 2 + 3, cy - s * 0.38, cx + s / 2 - 3, cy - s * 0.05], fill=SKY)
    d.polygon([(cx - s / 2 + 3, cy - s * 0.05), (cx - s * 0.2, cy - s * 0.32), (cx, cy - s * 0.1), (cx + s * 0.22, cy - s * 0.35), (cx + s / 2 - 3, cy - s * 0.05)], fill=WHITE)
    d.rectangle([cx - s / 2 + 3, cy - s * 0.05, cx + s / 2 - 3, cy + s * 0.08], fill=GREEN)
    return img


def newfoundland() -> Image.Image:
    img, d = _new(WHITE)
    d.polygon([(0, 0), (W * 0.35, H / 2), (0, H)], fill=SKY)
    d.polygon([(0, 0), (W * 0.3, 0), (W * 0.42, H / 2)], fill=SKY)
    d.polygon([(0, H), (W * 0.3, H), (W * 0.42, H / 2)], fill=SKY)
    d.polygon([(W * 0.55, H / 2), (W, H * 0.12), (W, H * 0.88)], fill=RED)
    d.polygon([(W * 0.6, H / 2), (W * 0.95, H * 0.3), (W * 0.95, H * 0.7)], fill=GOLD)
    d.polygon([(W * 0.68, H / 2), (W * 0.92, H * 0.38), (W * 0.92, H * 0.62)], fill=WHITE)
    return img


def yukon() -> Image.Image:
    img, d = _new(WHITE)
    d.rectangle([0, 0, W * 0.27, H], fill=(0, 100, 60))
    d.rectangle([W * 0.73, 0, W, H], fill=SKY)
    d.ellipse([W * 0.38, H * 0.6, W * 0.62, H * 0.85], fill=(170, 200, 80))  # fireweed wreath
    shield(d, W / 2, H * 0.42, H * 0.3, WHITE, SKY)
    d.polygon([(W * 0.43, H * 0.52), (W / 2, H * 0.33), (W * 0.57, H * 0.52)], fill=RED)
    return img


def northwest_territories() -> Image.Image:
    img, d = _new(WHITE)
    d.rectangle([0, 0, W / 4, H], fill=SKY)
    d.rectangle([W * 3 / 4, 0, W, H], fill=SKY)
    shield(d, W / 2, H / 2, H * 0.4, WHITE, (40, 120, 60))
    d.line([(W / 2 - H * 0.2, H * 0.6), (W / 2 + H * 0.2, H * 0.45)], fill=WHITE, width=8)
    return img


def nunavut() -> Image.Image:
    img, d = _new(YELLOW)
    d.rectangle([W / 2, 0, W, H], fill=WHITE)
    star(d, W * 0.82, H * 0.2, H * 0.1, SKY)
    # The inuksuk.
    c = (200, 20, 30)
    cx = W * 0.47
    d.rectangle([cx - 14, H * 0.12, cx + 14, H * 0.24], fill=c)
    d.rectangle([cx - 70, H * 0.27, cx + 70, H * 0.36], fill=c)
    d.rectangle([cx - 30, H * 0.38, cx + 30, H * 0.55], fill=c)
    d.rectangle([cx - 44, H * 0.58, cx - 14, H * 0.9], fill=c)
    d.rectangle([cx + 14, H * 0.58, cx + 44, H * 0.9], fill=c)
    d.rectangle([cx - 44, H * 0.56, cx + 44, H * 0.64], fill=c)
    return img


def charlatown() -> Image.Image:
    """The white flag with the red cross flown first in the row at the
    entrance (Joe's photos): a red cross on white, with a gold crown in the
    first quarter standing in for the city's arms."""
    img, d = _new(WHITE)
    t = H * 0.18
    d.rectangle([W * 0.4 - t / 2, 0, W * 0.4 + t / 2, H], fill=RED)
    d.rectangle([0, H / 2 - t / 2, W, H / 2 + t / 2], fill=RED)
    x, y = W * 0.18, H * 0.2
    d.polygon([(x - 30, y + 18), (x - 30, y - 10), (x - 15, y + 4), (x, y - 16), (x + 15, y + 4), (x + 30, y - 10), (x + 30, y + 18)], fill=GOLD)
    return img


# The row at the city entrance, in the order the cells are laid out.
ATLAS = [
    ("canada", lambda: canada()), ("charlatown", charlatown), ("ontario", ontario), ("quebec", quebec),
    ("nova_scotia", nova_scotia), ("new_brunswick", new_brunswick), ("manitoba", manitoba),
    ("british_columbia", british_columbia), ("pei", lambda: pei()), ("saskatchewan", saskatchewan),
    ("alberta", alberta), ("newfoundland", newfoundland), ("yukon", yukon),
    ("northwest_territories", northwest_territories), ("nunavut", nunavut),
]
ATLAS_COLS = 4


def atlas() -> tuple[Image.Image, dict]:
    rows = math.ceil(len(ATLAS) / ATLAS_COLS)
    img = Image.new("RGB", (W * ATLAS_COLS, H * rows), WHITE)
    names = []
    for i, (name, make) in enumerate(ATLAS):
        img.paste(make(), ((i % ATLAS_COLS) * W, (i // ATLAS_COLS) * H))
        names.append(name)
    return img, {"_comment": "Written by tools/make_flags.py: which cell of atlas.png holds which flag, row by row.", "cols": ATLAS_COLS, "rows": rows, "flags": names}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    canada().save(OUT / "canada.png")
    pei().save(OUT / "pei.png")
    img, layout = atlas()
    img.save(OUT / "atlas.png")
    (OUT / "atlas.json").write_text(json.dumps(layout, indent=1) + "\n")
    print("wrote", OUT / "canada.png", OUT / "pei.png", "and", OUT / "atlas.png")


if __name__ == "__main__":
    main()

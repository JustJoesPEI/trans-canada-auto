#!/usr/bin/env python3
"""Draw the lettering and patches on uniforms (police officers, and room for
the other crews): a small sheet of 4 x 4 tiles the person shader prints from
for print names in UNIFORM_PRINTS (scripts/characters/outfit.gd), kept apart
from the clothing sheet so that one stays as it is.

Every name and crest is our own: the Charlatown Police Services and the
Federal Island Patrol (PIF FIP, dressed after the RCMP).

Run from the repository root:

    python3 tools/make_uniform_prints.py

Needs Pillow. Writes textures/clothing/uniform_prints.png (1024 x 1024,
transparent). The tile order must match UNIFORM_PRINTS.
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_clothing_prints as mcp  # noqa: E402  (the lettering helpers)

ROOT = mcp.ROOT
OUT = os.path.join(ROOT, "textures", "clothing", "uniform_prints.png")
T = 256  # tile size
S = T / 512.0  # the helpers' sizes were set for 512 tiles

WHITE = (240, 240, 236, 255)
GOLD = (236, 184, 52, 255)
NAVY = (22, 32, 70, 255)
DARK = (14, 18, 34, 255)
CLEAR = (0, 0, 0, 0)


def big(tile, s, face, size, fill, cy, max_w, tracking=0.04):
    mcp.place(tile, mcp.word(s, face, size * S, fill, tracking=tracking), T / 2, cy, max_w=max_w)


def police_back(t, d):
    """POLICE across the back of a city officer's vest."""
    big(t, "POLICE", "anton", 170, WHITE, T * 0.5, T * 0.96, tracking=0.06)


def fip_back(t, d):
    """The FIP's back, after the RCMP's: POLICE, and the bilingual initials
    under it."""
    big(t, "POLICE", "anton", 170, WHITE, T * 0.43, T * 0.96, tracking=0.06)
    big(t, "PIF  FIP", "bebas", 90, GOLD, T * 0.7, T * 0.6, tracking=0.12)


def cps_patch(t, d):
    """The city's shoulder patch, after the crest on its cars: a green
    shield edged in gold, CHARLATOWN over a lighthouse on blue waves,
    POLICE under it."""
    w, h = T * 0.86, T * 0.94
    x0, y0 = (T - w) / 2, (T - h) / 2
    shield = [(x0, y0), (x0 + w, y0), (x0 + w, y0 + h * 0.62), (T / 2, y0 + h), (x0, y0 + h * 0.62)]
    d.polygon(shield, fill=GOLD)
    inset = 8 * S * 2
    inner = [(x0 + inset, y0 + inset), (x0 + w - inset, y0 + inset), (x0 + w - inset, y0 + h * 0.62 - inset * 0.3),
             (T / 2, y0 + h - inset * 1.6), (x0 + inset, y0 + h * 0.62 - inset * 0.3)]
    d.polygon(inner, fill=(30, 104, 58, 255))
    for k in range(2):
        yy = y0 + h * (0.6 + k * 0.06)
        d.rectangle((T / 2 - 40, yy, T / 2 + 40, yy + 6), fill=(40, 90, 190, 255))
    big(t, "CHARLATOWN", "bebas", 74, WHITE, y0 + h * 0.14, w * 0.8, tracking=0.08)
    # The lighthouse: a tapered white tower, a red band, the lamp.
    cx, base, top = T / 2, y0 + h * 0.66, y0 + h * 0.3
    d.polygon([(cx - 18, base), (cx + 18, base), (cx + 10, top), (cx - 10, top)], fill=WHITE)
    d.rectangle((cx - 15, (base + top) / 2 - 6, cx + 15, (base + top) / 2 + 6), fill=(190, 36, 36, 255))
    d.rectangle((cx - 9, top - 14, cx + 9, top), fill=GOLD)
    d.polygon([(cx - 12, top - 14), (cx + 12, top - 14), (cx, top - 26)], fill=WHITE)
    big(t, "POLICE", "anton", 70, WHITE, y0 + h * 0.78, w * 0.46, tracking=0.06)


def fip_patch(t, d):
    """The FIP's shoulder flash, after the RCMP's: an arch-topped dark blue
    patch edged in gold, a crown, FIP over PIF, a potato where the buffalo
    would be."""
    w, h = T * 0.8, T * 0.94
    x0, y0 = (T - w) / 2, (T - h) / 2
    r = w / 2
    d.pieslice((x0, y0, x0 + w, y0 + w), 180, 360, fill=GOLD)
    d.rectangle((x0, y0 + r, x0 + w, y0 + h), fill=GOLD)
    e = 10
    d.pieslice((x0 + e, y0 + e, x0 + w - e, y0 + w - e), 180, 360, fill=DARK)
    d.rectangle((x0 + e, y0 + r, x0 + w - e, y0 + h - e), fill=DARK)
    # The crown.
    cx, cy = T / 2, y0 + h * 0.17
    d.rectangle((cx - 30, cy, cx + 30, cy + 12), fill=GOLD)
    for k in (-24, 0, 24):
        d.polygon([(cx + k - 9, cy), (cx + k + 9, cy), (cx + k, cy - 20)], fill=GOLD)
    mcp.potato(d, cx, y0 + h * 0.42, 34, 24, (176, 120, 64, 255), seed=5, eyes=(90, 56, 26, 255))
    big(t, "FIP", "anton", 120, GOLD, y0 + h * 0.66, w * 0.6, tracking=0.1)
    big(t, "PIF", "bebas", 80, WHITE, y0 + h * 0.85, w * 0.4, tracking=0.12)


LIME = (200, 224, 40, 255)
FIRE_RED = (170, 24, 18, 255)
BLUE = (24, 70, 170, 255)
GREEN = (14, 70, 40, 255)


def iwwb_back(t, d):
    """Across a turnout coat's back, in reflective lime: IWWB, and the
    Brigade's name under it."""
    big(t, "IWWB", "anton", 170, LIME, T * 0.42, T * 0.9, tracking=0.08)
    big(t, "WEE-WOO BRIGADE", "bebas", 60, LIME, T * 0.74, T * 0.9, tracking=0.08)


def paramedic_back(t, d):
    """Across a paramedic's back: PARAMEDIC, and the service under it."""
    big(t, "PARAMEDIC", "anton", 120, WHITE, T * 0.42, T * 0.96, tracking=0.04)
    big(t, "ISLAND BOO-BOO BUS", "bebas", 56, LIME, T * 0.7, T * 0.9, tracking=0.08)


def ibbb_patch(t, d):
    """The Boo-Boo Bus's shoulder patch: a dark green roundel edged in
    lime, a blue Star of Life, IBBB under it."""
    c, r = T / 2, T * 0.46
    d.ellipse((c - r, c - r, c + r, c + r), fill=LIME)
    r2 = r - 12
    d.ellipse((c - r2, c - r2, c + r2, c + r2), fill=GREEN)
    import math
    for k in range(3):
        a = math.pi / 2 + k * math.pi / 3
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy * 13, dx * 13
        L = r * 0.55
        cy = c - 14
        d.polygon([(c - dx * L - px, cy - dy * L - py), (c - dx * L + px, cy - dy * L + py),
                   (c + dx * L + px, cy + dy * L + py), (c + dx * L - px, cy + dy * L - py)], fill=BLUE)
    d.rectangle((c - 3, c - 14 - r * 0.4, c + 3, c - 14 + r * 0.4), fill=WHITE)
    big(t, "IBBB", "anton", 80, WHITE, c + r * 0.62, r * 0.9, tracking=0.08)


def iwwb_patch(t, d):
    """The Wee-Woo Brigade's shoulder patch: a red shield edged in gold, a
    gold Maltese cross, IWWB under it."""
    w, h = T * 0.8, T * 0.92
    x0, y0 = (T - w) / 2, (T - h) / 2
    d.polygon([(x0, y0), (x0 + w, y0), (x0 + w, y0 + h * 0.62), (T / 2, y0 + h), (x0, y0 + h * 0.62)], fill=GOLD)
    e = 12
    d.polygon([(x0 + e, y0 + e), (x0 + w - e, y0 + e), (x0 + w - e, y0 + h * 0.62 - e * 0.4),
               (T / 2, y0 + h - e * 1.8), (x0 + e, y0 + h * 0.62 - e * 0.4)], fill=FIRE_RED)
    cx, cy, R = T / 2, y0 + h * 0.36, w * 0.28
    for k in range(4):
        import math
        a = k * math.pi / 2
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        pts = [(cx + px * R * 0.12, cy + py * R * 0.12), (cx + dx * R + px * R * 0.55, cy + dy * R + py * R * 0.55),
               (cx + dx * R * 0.8, cy + dy * R * 0.8), (cx + dx * R - px * R * 0.55, cy + dy * R - py * R * 0.55),
               (cx - px * R * 0.12, cy - py * R * 0.12)]
        d.polygon(pts, fill=GOLD)
    big(t, "IWWB", "anton", 64, GOLD, y0 + h * 0.74, w * 0.5, tracking=0.08)


# In tile order; must match UNIFORM_PRINTS in scripts/characters/outfit.gd.
PRINTS = [police_back, fip_back, cps_patch, fip_patch, iwwb_back, paramedic_back, ibbb_patch, iwwb_patch]


def main():
    sheet = Image.new("RGBA", (T * 4, T * 4), CLEAR)
    for i, fn in enumerate(PRINTS):
        tile = Image.new("RGBA", (T, T), CLEAR)
        fn(tile, ImageDraw.Draw(tile))
        sheet.alpha_composite(tile, ((i % 4) * T, (i // 4) * T))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

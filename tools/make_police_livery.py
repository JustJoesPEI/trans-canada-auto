#!/usr/bin/env python3
"""Draw the lettering and crests that go on the police vehicles, on one
sheet the car builder wraps onto the body (CarBuilder._lay_word), so the
words follow the panels like vinyl instead of standing off them.

Every name and crest is our own: the Charlatown Police Services (dressed
after Charlottetown's 2023 cruisers) and the Federal Island Patrol, PIF FIP
(after the RCMP's).

Run from the repository root:

    python3 tools/make_police_livery.py

Needs Pillow. Writes textures/vehicles/police_livery.png (2048 x 1024,
transparent; words are white, for the builder to tint) and
police_livery.json (each entry's UV rectangle and width over height).
"""

import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_clothing_prints as mcp  # noqa: E402  (fonts and shapes)

ROOT = mcp.ROOT
OUT = os.path.join(ROOT, "textures", "vehicles", "police_livery.png")
SIZE = 2048
ROW = 128  # word rows from the top
HEIGHT = 1024
SQ = 384  # squares (crests, the flag) along the bottom
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

# name: (text, face, tracking)
WORDS = [
    ("police", "POLICE", "sans", 0.02),
    ("charlatown", "CHARLATOWN", "sans", 0.04),
    ("pif_fip", "PIF  FIP", "sans", 0.06),
    ("n911", "911", "sans", 0.02),
    ("tactical", "TACTICAL UNIT", "sans", 0.06),
]


def sans_word(s, tracking):
    """Heavy sans capitals cropped tight to the letters."""
    from PIL import ImageFont
    f = ImageFont.truetype(os.path.join(ROOT, "tools", "fonts", "LiberationSans-Bold.ttf"), 400)
    widths = [f.getlength(c) for c in s]
    w = int(sum(widths) + tracking * 400 * (len(s) - 1) + 40)
    img = Image.new("RGBA", (w, 520), CLEAR)
    d = ImageDraw.Draw(img)
    x = 20
    for c, cw in zip(s, widths):
        d.text((x, 20), c, font=f, fill=WHITE)
        x += cw + tracking * 400
    return img.crop(img.getbbox())


def cps_crest(t, d):
    """The town's crest, our own: a green shield edged in gold, a white
    lighthouse on blue waves, a gold crown over it."""
    S = SQ
    d = ImageDraw.Draw(t)
    gold, green, blue = (226, 176, 52, 255), (34, 110, 62, 255), (30, 80, 170, 255)
    w, h = S * 0.62, S * 0.72
    x0, y0 = (S - w) / 2, S * 0.2
    shield = [(x0, y0), (x0 + w, y0), (x0 + w, y0 + h * 0.6), (S / 2, y0 + h), (x0, y0 + h * 0.6)]
    d.polygon(shield, fill=gold)
    e = int(S * 0.03)
    inner = [(x0 + e, y0 + e), (x0 + w - e, y0 + e), (x0 + w - e, y0 + h * 0.6 - e * 0.4),
             (S / 2, y0 + h - e * 1.8), (x0 + e, y0 + h * 0.6 - e * 0.4)]
    d.polygon(inner, fill=green)
    # Waves across the bottom of the field, kept inside it.
    waves = Image.new("RGBA", (S, S), CLEAR)
    wd = ImageDraw.Draw(waves)
    for k in range(3):
        yy = y0 + h * (0.58 + k * 0.09)
        wd.rectangle((x0 + e, yy, x0 + w - e, yy + h * 0.045), fill=blue)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(inner, fill=255)
    t.paste(waves, (0, 0), Image.composite(waves.getchannel("A"), Image.new("L", (S, S), 0), mask))
    cx, base, top = S / 2, y0 + h * 0.6, y0 + h * 0.16
    k = S / 512.0
    d.polygon([(cx - 38 * k, base), (cx + 38 * k, base), (cx + 22 * k, top), (cx - 22 * k, top)], fill=(245, 245, 240, 255))
    d.rectangle((cx - 32 * k, (base + top) / 2 - 12 * k, cx + 32 * k, (base + top) / 2 + 12 * k), fill=(190, 36, 36, 255))
    d.rectangle((cx - 18 * k, top - 30 * k, cx + 18 * k, top), fill=gold)
    d.polygon([(cx - 26 * k, top - 30 * k), (cx + 26 * k, top - 30 * k), (cx, top - 58 * k)], fill=(245, 245, 240, 255))
    # The crown.
    cy = y0 - 24 * k
    d.rectangle((cx - 70 * k, cy, cx + 70 * k, cy + 22 * k), fill=gold)
    for p in (-56, -28, 0, 28, 56):
        d.polygon([(cx + (p - 14) * k, cy), (cx + (p + 14) * k, cy), (cx + p * k, cy - 44 * k)], fill=gold)


def flag(t, d):
    """The national flag, as on the real cruisers' back windows."""
    S = SQ
    red, white = (214, 32, 40, 255), (250, 250, 250, 255)
    w, h = S * 0.9, S * 0.45
    x0, y0 = (S - w) / 2, (S - h) / 2
    d.rectangle((x0, y0, x0 + w, y0 + h), fill=red)
    d.rectangle((x0 + w / 4, y0, x0 + w * 3 / 4, y0 + h), fill=white)
    # A plain maple leaf.
    cx, cy, r = S / 2, S / 2, h * 0.36
    pts = [(0, -1), (0.18, -0.62), (0.36, -0.72), (0.3, -0.26), (0.62, -0.5), (0.56, -0.32), (0.86, -0.36),
           (0.74, -0.08), (0.92, 0.0), (0.5, 0.36), (0.58, 0.52), (0.06, 0.44), (0.06, 0.9),
           (-0.06, 0.9), (-0.06, 0.44), (-0.58, 0.52), (-0.5, 0.36), (-0.92, 0.0), (-0.74, -0.08),
           (-0.86, -0.36), (-0.56, -0.32), (-0.62, -0.5), (-0.3, -0.26), (-0.36, -0.72), (-0.18, -0.62)]
    d.polygon([(cx + x * r, cy + y * r) for x, y in pts], fill=red)


SQUARES = [("cps_crest", cps_crest), ("flag", flag)]


def main():
    sheet = Image.new("RGBA", (SIZE, HEIGHT), CLEAR)
    index = {}
    for i, (name, text, face, tracking) in enumerate(WORDS):
        img = sans_word(text, tracking)
        pad = 6
        hh = ROW - pad * 2
        ww = int(img.width * hh / img.height)
        if ww > SIZE - pad * 2:
            ww = SIZE - pad * 2
        img = img.resize((ww, hh), Image.LANCZOS)
        y = i * ROW + pad
        sheet.alpha_composite(img, (pad, y))
        index[name] = {"rect": [pad / SIZE, y / HEIGHT, (pad + ww) / SIZE, (y + hh) / HEIGHT], "aspect": ww / hh}
    for i, (name, fn) in enumerate(SQUARES):
        tile = Image.new("RGBA", (SQ, SQ), CLEAR)
        fn(tile, ImageDraw.Draw(tile))
        x, y = i * SQ, HEIGHT - SQ
        sheet.alpha_composite(tile, (x, y))
        index[name] = {"rect": [x / SIZE, y / HEIGHT, (x + SQ) / SIZE, (y + SQ) / HEIGHT], "aspect": 1.0}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    with open(OUT.replace(".png", ".json"), "w") as f:
        json.dump(index, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

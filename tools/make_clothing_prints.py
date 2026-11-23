#!/usr/bin/env python3
"""Draw the graphics printed on clothes: the game's spoof Island brands and
sayings, on one sheet of 4 x 4 tiles that the person shader prints from.

Each print is designed like real merch: its own lettering (fonts in
tools/fonts/, see the README there), one or two inks the way a screen
print would be, and a short, deadpan line rather than a joke with an
explanation. Every brand is made up, a send-up of life on Prince Edward
Island and in Charlottetown.

Run from the repository root:

    python3 tools/make_clothing_prints.py

Needs Pillow and NumPy. Writes textures/clothing/prints.png (2048 x 2048,
transparent). The tile order must match PRINTS in
scripts/characters/outfit.gd.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures", "clothing", "prints.png")
FONTS = os.path.join(ROOT, "tools", "fonts")
T = 512  # tile size

# Inks.
CLAY = (176, 64, 38, 255)
CREAM = (244, 236, 216, 255)
INK = (22, 24, 28, 255)
NAVY = (26, 40, 76, 255)
GOLD = (226, 172, 50, 255)
RED = (196, 34, 38, 255)
ORANGE = (232, 120, 40, 255)
CLEAR = (0, 0, 0, 0)

FACES = {
    "anton": "Anton-Regular.ttf", "slab": "AlfaSlabOne-Regular.ttf", "college": "Graduate-Regular.ttf",
    "script": "Pacifico-Regular.ttf", "marker": "PermanentMarker-Regular.ttf", "western": "Rye-Regular.ttf",
    "bebas": "BebasNeue-Regular.ttf", "stencil": "BlackOpsOne-Regular.ttf", "block": "Bungee-Regular.ttf",
    "typewriter": "SpecialElite-Regular.ttf",
}


def font(face, size):
    return ImageFont.truetype(os.path.join(FONTS, FACES[face]), int(size))


# --- lettering ---------------------------------------------------------------------------

def word(s, face, size, fill, tracking=0.0, squeeze=1.0, shear=0.0):
    """Text as its own transparent image: letter-spaced (tracking, in ems),
    squeezed narrower (squeeze < 1) and slanted (shear > 0 leans right)."""
    f = font(face, size)
    widths = [f.getlength(c) for c in s]
    w = int(sum(widths) + tracking * size * max(0, len(s) - 1) + size)
    asc, desc = f.getmetrics()
    img = Image.new("RGBA", (w, asc + desc + int(size * 0.3)), CLEAR)
    d = ImageDraw.Draw(img)
    x = size * 0.1
    for c, cw in zip(s, widths):
        d.text((x, size * 0.1), c, font=f, fill=fill)
        x += cw + tracking * size
    img = img.crop(img.getbbox())
    if squeeze != 1.0:
        img = img.resize((max(1, int(img.width * squeeze)), img.height), Image.LANCZOS)
    if shear:
        extra = int(abs(shear) * img.height)
        img = img.transform((img.width + extra, img.height), Image.AFFINE,
                            (1, shear, -extra if shear > 0 else 0, 0, 1, 0), Image.BICUBIC)
    return img


def place(tile, img, cx, cy, max_w=None, anchor="c"):
    """Paste an image centred at (cx, cy) (or left-aligned with anchor 'l'),
    shrunk to max_w if needed."""
    if max_w and img.width > max_w:
        img = img.resize((int(max_w), int(img.height * max_w / img.width)), Image.LANCZOS)
    x = int(cx - img.width / 2) if anchor == "c" else int(cx)
    tile.alpha_composite(img, (x, int(cy - img.height / 2)))
    return img.size


def arc(tile, s, face, size, fill, cx, cy, r, top=True, tracking=0.08):
    """Text around a circle: over the top reading clockwise, or along the
    bottom reading left to right, letters upright."""
    f = font(face, size)
    widths = [f.getlength(c) + tracking * size for c in s]
    total = sum(widths) - tracking * size
    ang = -total / 2.0 / r
    for c, w in zip(s, widths):
        mid = ang + (w - tracking * size) / 2.0 / r
        g = Image.new("RGBA", (int(size * 1.6), int(size * 1.6)), CLEAR)
        ImageDraw.Draw(g).text((g.width / 2, g.height / 2), c, font=f, fill=fill, anchor="mm")
        if top:
            a = -math.pi / 2 + mid
            g = g.rotate(-math.degrees(mid), resample=Image.BICUBIC)
        else:
            a = math.pi / 2 - mid
            g = g.rotate(math.degrees(mid), resample=Image.BICUBIC)
        x = cx + math.cos(a) * r
        y = cy + math.sin(a) * r
        tile.alpha_composite(g, (int(x - g.width / 2), int(y - g.height / 2)))
        ang += w / r


def rotated(layer, degrees):
    return layer.rotate(degrees, resample=Image.BICUBIC)


# --- shapes ------------------------------------------------------------------------------

def potato(d, cx, cy, rx, ry, fill, seed=3, eyes=CLEAR):
    """A lumpy potato; `eyes` knocks out its eyes (None for none)."""
    rng = np.random.default_rng(seed)
    pts = []
    bumps = rng.uniform(0.9, 1.08, 9)
    for i in range(72):
        a = i / 72.0 * math.tau
        b = np.interp(a, np.linspace(0, math.tau, 10), np.append(bumps, bumps[0]))
        pts.append((cx + math.cos(a) * rx * b, cy + math.sin(a) * ry * b))
    d.polygon(pts, fill=fill)
    if eyes is None:
        return
    for ex, ey in ((-0.6, 0.15), (0.12, -0.45), (0.55, 0.32)):  # scattered, so it isn't a face
        x, y = cx + ex * rx, cy + ey * ry
        d.ellipse((x - rx * 0.06, y - ry * 0.04, x + rx * 0.06, y + ry * 0.04), fill=eyes)


def gull(d, cx, cy, s, fill):
    """A gull gliding head-on: a solid M of wings."""
    pts = [(-1.0, -0.08), (-0.62, -0.42), (-0.28, -0.3), (-0.07, 0.0), (0.07, 0.0), (0.28, -0.3), (0.62, -0.42),
           (1.0, -0.08), (0.58, -0.24), (0.3, -0.12), (0.1, 0.16), (0.0, 0.24), (-0.1, 0.16), (-0.3, -0.12), (-0.58, -0.24)]
    d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=fill)


def lobster(d, cx, cy, s, fill):
    """A lobster in one ink, claws up."""
    d.ellipse((cx - 0.24 * s, cy - 0.5 * s, cx + 0.24 * s, cy + 0.15 * s), fill=fill)
    for i in range(4):
        y = cy + 0.15 * s + i * 0.14 * s
        w = 0.21 * s - i * 0.025 * s
        d.ellipse((cx - w, y - 0.06 * s, cx + w, y + 0.09 * s), fill=fill)
    d.polygon([(cx, cy + 0.66 * s), (cx - 0.28 * s, cy + 0.86 * s), (cx + 0.28 * s, cy + 0.86 * s)], fill=fill)
    for side in (-1, 1):
        d.line([(cx + side * 0.18 * s, cy - 0.35 * s), (cx + side * 0.45 * s, cy - 0.62 * s)], fill=fill, width=int(0.08 * s))
        x, y = cx + side * 0.52 * s, cy - 0.85 * s
        d.ellipse((x - 0.17 * s, y - 0.26 * s, x + 0.17 * s, y + 0.2 * s), fill=fill)
        d.polygon([(x - side * 0.02 * s, y - 0.3 * s), (x + side * 0.05 * s, y - 0.02 * s), (x - side * 0.1 * s, y - 0.3 * s)], fill=CLEAR)
        for k in range(3):
            ly = cy - 0.15 * s + k * 0.12 * s
            d.line([(cx + side * 0.2 * s, ly), (cx + side * 0.44 * s, ly + 0.1 * s)], fill=fill, width=int(0.035 * s))
        d.line([(cx + side * 0.06 * s, cy - 0.5 * s), (cx + side * 0.28 * s, cy - 1.05 * s)], fill=fill, width=int(0.02 * s))


# --- the prints, in tile order ---------------------------------------------------------

def spud_co(t, d):
    # Red Clay Spud Co.: field workwear. One ink, details knocked out.
    d.ellipse((24, 24, T - 24, T - 24), outline=CLAY, width=10)
    d.ellipse((44, 44, T - 44, T - 44), outline=CLAY, width=4)
    arc(t, "RED CLAY", "slab", 62, CLAY, T / 2, T / 2, 172, top=True, tracking=0.06)
    arc(t, "SPUD CO.", "slab", 62, CLAY, T / 2, T / 2, 178, top=False, tracking=0.06)
    d.line([(196, 330), (316, 196)], fill=CLAY, width=11)  # a fork, stuck in it
    d.line([(300, 184), (334, 214)], fill=CLAY, width=9)
    for k in (-1, 0, 1):
        dx, dy = k * 12, k * 11
        d.line([(317 + dx, 199 + dy), (340 + dx, 172 + dy)], fill=CLAY, width=7)
    potato(d, T / 2 - 10, T / 2 + 30, 82, 56, CLAY)
    place(t, word("EST.", "bebas", 34, CLAY, tracking=0.15), 112, T / 2)
    place(t, word("1873", "bebas", 34, CLAY, tracking=0.15), T - 112, T / 2)


def canada_gull(t, d):
    # Canada Gull: the patch. Red, navy and cream, like the real thing isn't.
    d.ellipse((20, 20, T - 20, T - 20), fill=NAVY)
    d.ellipse((96, 96, T - 96, T - 96), fill=RED)
    d.ellipse((96, 96, T - 96, T - 96), outline=CREAM, width=5)
    gull(d, T / 2, T / 2 + 10, 128, CREAM)
    arc(t, "CANADA GULL", "bebas", 64, CREAM, T / 2, T / 2, 200, top=True, tracking=0.12)
    arc(t, "ARCTIC-ISH PROGRAM", "bebas", 40, CREAM, T / 2, T / 2, 196, top=False, tracking=0.14)


def gentle_island(t, d):
    # The tourism slogan, corrected by hand.
    place(t, word("THE", "western", 42, CREAM, tracking=0.3), T / 2, 110)
    place(t, word("GENTLE", "western", 96, CREAM), T / 2, 245, max_w=430)
    place(t, word("ISLAND", "western", 96, CREAM), T / 2, 350, max_w=430)
    scrawl = Image.new("RGBA", (T, T), CLEAR)
    s = ImageDraw.Draw(scrawl)
    s.line([(60, 258), (180, 238), (300, 252), (455, 228)], fill=RED, width=14, joint="curve")
    s.line([(70, 236), (230, 256), (440, 248)], fill=RED, width=9, joint="curve")
    place(scrawl, word("ROWDY", "marker", 84, RED), T / 2 + 60, 182)
    t.alpha_composite(rotated(scrawl, 6))


def from_away(t, d):
    # Inspected at the bridge.
    stamp = Image.new("RGBA", (T, T), CLEAR)
    s = ImageDraw.Draw(stamp)
    s.rectangle((36, 130, T - 36, 382), outline=RED, width=12)
    s.rectangle((54, 148, T - 54, 364), outline=RED, width=4)
    place(stamp, word("INSPECTED - P.E.I.", "typewriter", 30, RED, tracking=0.08), T / 2, 190)
    place(stamp, word("FROM AWAY", "typewriter", 84, RED), T / 2, 258, max_w=360)
    place(stamp, word("No. 004127", "typewriter", 30, RED), T / 2, 322)
    t.alpha_composite(rotated(stamp, 9))


def whos_your_father(t, d):
    # Every first conversation on the Island.
    y = 105
    for line, size in (("WHO'S", 150), ("YOUR", 150), ("FATHER?", 150)):
        w = word(line, "anton", size, CREAM, squeeze=0.92)
        place(t, w, 56, y, max_w=400, anchor="l")
        y += 145
    v = word("P.E.I. EDITION", "bebas", 34, CREAM, tracking=0.25).rotate(90, expand=True)
    place(t, v, T - 46, T / 2)


def pay_to_leave(t, d):
    # The bridge toll is only charged going off the Island.
    place(t, word("FREE TO COME", "bebas", 70, CREAM, tracking=0.12), T / 2, 92)
    deck = [(28, 250), (190, 250), (256, 222), (322, 250), (484, 250)]
    d.line(deck, fill=CREAM, width=10, joint="curve")
    for i in range(12):
        x = 40 + i * 39
        top = 250 if abs(x - 256) > 66 else 250 - (66 - abs(x - 256)) * 0.42
        d.line([(x, top), (x, 300)], fill=CREAM, width=7)
    d.line([(20, 302), (492, 302)], fill=CREAM, width=3)
    place(t, word("PAY TO LEAVE", "anton", 120, CREAM), T / 2, 400, max_w=460)


def spud_kings(t, d):
    # The Charlottetown Spud Kings, junior hockey.
    d.ellipse((20, 20, T - 20, T - 20), fill=NAVY)
    d.ellipse((34, 34, T - 34, T - 34), outline=GOLD, width=8)
    d.ellipse((118, 118, T - 118, T - 118), outline=GOLD, width=5)
    potato(d, T / 2, T / 2 + 22, 84, 60, GOLD, seed=7, eyes=None)
    crown = [(T / 2 - 62, 230), (T / 2 - 70, 160), (T / 2 - 32, 196), (T / 2, 146), (T / 2 + 32, 196), (T / 2 + 70, 160), (T / 2 + 62, 230)]
    d.polygon(crown, fill=GOLD)
    arc(t, "SPUD KINGS", "college", 58, CREAM, T / 2, T / 2, 180, top=True, tracking=0.1)
    arc(t, "CHARLOTTETOWN", "college", 38, GOLD, T / 2, T / 2, 186, top=False, tracking=0.14)


def varsity_s(t, d):
    # The chenille letter for the Spud Kings varsity jacket.
    back = word("S", "college", 470, CREAM)
    front = word("S", "college", 430, GOLD)
    place(t, back.filter(ImageFilter.MaxFilter(25)), T / 2, T / 2)
    place(t, front, T / 2, T / 2)


def mussel_beach(t, d):
    # The gym out on the North Shore. One ink.
    arc(t, "MUSSEL BEACH", "block", 56, CREAM, T / 2, T / 2, 170, top=True, tracking=0.04)
    arc(t, "GYM - RUSTICO", "bebas", 50, CREAM, T / 2, T / 2, 178, top=False, tracking=0.18)
    d.rectangle((160, 248, 352, 268), fill=CREAM)  # dumbbell
    for x in (130, 352):
        d.rounded_rectangle((x, 205, x + 30, 311), radius=6, fill=CREAM)
    for x in (108, 382):
        d.rounded_rectangle((x, 222, x + 22, 294), radius=6, fill=CREAM)
    place(t, word("EST. 1987", "bebas", 30, CREAM, tracking=0.25), T / 2, 350)


def potholes(t, d):
    # A club nobody joins on purpose.
    place(t, word("UNIVERSITY AVE.", "typewriter", 40, CREAM), T / 2, 90)
    place(t, word("POTHOLE", "anton", 150, CREAM), T / 2, 205, max_w=440)
    place(t, word("SOCIETY", "anton", 150, CREAM), T / 2, 345, max_w=440)
    d.line([(70, 430), (T - 70, 430)], fill=CREAM, width=4)
    place(t, word("MEMBER SINCE MARCH", "bebas", 44, CREAM, tracking=0.2), T / 2, 465)


def tim_wrongtons(t, d):
    # The coffee and doughnut place on every corner, where you never get
    # what you ordered.
    d.rounded_rectangle((26, 116, T - 26, 380), radius=132, fill=RED)
    d.rounded_rectangle((42, 132, T - 42, 364), radius=116, outline=CREAM, width=4)
    place(t, word("Tim Wrongtons", "script", 92, CREAM), T / 2, 222, max_w=390)
    d.line([(170, 284), (342, 284)], fill=CREAM, width=4)
    place(t, word("ALWAYS WRONG", "bebas", 40, CREAM, tracking=0.25), T / 2, 314)


def lobster_supper(t, d):
    # Church-basement lobster suppers, every summer.
    lobster(d, T / 2, 210, 120, RED)
    place(t, word("LOBSTER", "western", 104, CREAM), T / 2, 375, max_w=440)
    place(t, word("SUPPER", "bebas", 64, CREAM, tracking=0.45), T / 2, 448)


def island_time(t, d):
    # Seventies souvenir.
    cx, cy, r = T / 2, 300, 190
    for i, col in enumerate((GOLD, ORANGE, RED)):
        layer = Image.new("RGBA", (T, T), CLEAR)
        ImageDraw.Draw(layer).pieslice((cx - r + i * 30, cy - r + i * 30, cx + r - i * 30, cy + r - i * 30), 180, 360, fill=col)
        t.alpha_composite(layer)
    for k in range(4):  # the gaps of the sunset stripes
        y = cy - 30 - k * 34
        d.rectangle((0, y, T, y + 7 + k * 2), fill=CLEAR)
    d.rectangle((0, cy, T, T), fill=CLEAR)
    shadow = word("Island Time", "script", 112, INK, shear=0.0)
    place(t, shadow, T / 2 + 6, 318 + 6, max_w=470)
    place(t, word("Island Time", "script", 112, CREAM), T / 2, 318, max_w=470)


def mainlanders(t, d):
    place(t, word("MAINLANDERS", "stencil", 80, RED), T / 2, 200, max_w=460)
    place(t, word("GO HOME", "stencil", 128, RED), T / 2, 318, max_w=460)


def red_mud(t, d):
    # Dirt roads, no brakes.
    for i in range(5):  # speed lines
        y = 190 + i * 22
        d.line([(24, y), (120 - i * 10, y)], fill=CLAY, width=8)
    place(t, word("RED MUD", "anton", 170, CLAY, shear=0.22), T / 2 + 30, 230, max_w=400)
    place(t, word("RACING", "bebas", 74, CREAM, tracking=0.5, shear=0.22), T / 2 + 20, 345, max_w=380)
    sq = 22
    for i in range(8):
        for j in range(2):
            if (i + j) % 2 == 0:
                d.rectangle((168 + i * sq, 400 + j * sq, 168 + (i + 1) * sq, 400 + (j + 1) * sq), fill=CREAM)


def tca(t, d):
    # The game's own merch: the TCA shield from branding/.
    logo = Image.open(os.path.join(ROOT, "branding", "logo.png")).convert("RGBA")
    logo.thumbnail((T - 80, T - 80), Image.LANCZOS)
    t.alpha_composite(logo, ((T - logo.width) // 2, (T - logo.height) // 2))


# In tile order; must match PRINTS in scripts/characters/outfit.gd. The
# second value is how worn the print is (0 new, about 0.3 well washed).
PRINTS = [(spud_co, 0.18), (canada_gull, 0.06), (gentle_island, 0.16), (from_away, 0.3),
          (whos_your_father, 0.16), (pay_to_leave, 0.14), (spud_kings, 0.1), (varsity_s, 0.04),
          (mussel_beach, 0.2), (potholes, 0.2), (tim_wrongtons, 0.12), (lobster_supper, 0.16),
          (island_time, 0.2), (mainlanders, 0.22), (red_mud, 0.2), (tca, 0.06)]


def distress(tile, amount, seed):
    """Screen print that's been through the wash: worn patches and specks."""
    rng = np.random.default_rng(seed)
    coarse = Image.fromarray((rng.random((T // 24, T // 24)) * 255).astype(np.uint8)).resize((T, T), Image.BICUBIC)
    coarse = np.asarray(coarse.filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255.0
    fine = rng.random((T, T)).astype(np.float32)
    wear = coarse * 0.7 + fine * 0.3
    keep = np.clip((wear - amount) * 12.0, 0.0, 1.0)
    a = np.asarray(tile, dtype=np.float32).copy()
    a[..., 3] *= keep
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def main():
    sheet = Image.new("RGBA", (T * 4, T * 4), CLEAR)
    for i, (fn, wear) in enumerate(PRINTS):
        tile = Image.new("RGBA", (T, T), CLEAR)
        fn(tile, ImageDraw.Draw(tile))
        sheet.alpha_composite(distress(tile, wear, i), ((i % 4) * T, (i // 4) * T))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

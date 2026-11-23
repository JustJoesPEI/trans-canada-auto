#!/usr/bin/env python3
"""Draw the graphics printed on clothes: the game's spoof Island brands and
sayings, on one sheet of 4 x 4 tiles that the person shader prints from.

Everything is drawn here from shapes and the free DejaVu fonts, so it can be
changed and redrawn any time. Run from the repository root:

    python3 tools/make_clothing_prints.py

Needs Pillow, NumPy and the DejaVu fonts (on Ubuntu: fonts-dejavu-core). Writes
textures/clothing/prints.png (2048 x 2048, transparent). The tile order must
match PRINTS in scripts/characters/outfit.gd.

Every brand here is made up: a send-up of life on Prince Edward Island and
in Charlottetown, with the edge of the parody brands in open-world crime
games. Prints are distressed like a well-washed screen print.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures", "clothing", "prints.png")
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"
T = 512  # tile size

CLAY = (178, 66, 40)
CREAM = (246, 238, 220)
INK = (24, 26, 30)
NAVY = (28, 44, 82)
GOLD = (222, 170, 54)
SEA = (40, 120, 150)
GREEN = (46, 110, 62)
RED = (190, 36, 40)
SPUD = (196, 150, 92)


def font(size, kind="sans"):
    name = {"sans": "DejaVuSans-Bold.ttf", "serif": "DejaVuSerif-Bold.ttf",
            "mono": "DejaVuSansMono-Bold.ttf", "light": "DejaVuSans.ttf",
            "serif_light": "DejaVuSerif.ttf"}[kind]
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def text(d, xy, s, size, fill, kind="sans", stroke=0, stroke_fill=INK, max_w=T - 40):
    """Centred text at xy, shrunk to fit max_w."""
    while True:
        f = font(size, kind)
        box = d.textbbox((0, 0), s, font=f, stroke_width=stroke)
        w = box[2] - box[0]
        if w <= max_w or size < 12:
            break
        size -= 2
    h = box[3] - box[1]
    d.text((xy[0] - w / 2 - box[0], xy[1] - h / 2 - box[1]), s, font=f, fill=fill,
           stroke_width=stroke, stroke_fill=stroke_fill)


def potato(d, cx, cy, rx, ry, fill, outline):
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=fill, outline=outline, width=8)
    for ex, ey in ((-0.4, -0.3), (0.3, 0.1), (-0.1, 0.45), (0.5, -0.4)):
        x, y = cx + ex * rx, cy + ey * ry
        d.ellipse((x - 7, y - 5, x + 7, y + 5), fill=outline)


def gull(d, cx, cy, s, fill):
    """A gull in flight: two curved wings."""
    pts = []
    for i in range(21):
        t = i / 20.0
        x = cx + (t - 0.5) * 2.0 * s
        y = cy - abs(math.sin((t - 0.5) * math.pi)) * s * 0.55 + (0.12 * s if abs(t - 0.5) < 0.05 else 0)
        pts.append((x, y))
    d.line(pts, fill=fill, width=max(6, int(s * 0.13)), joint="curve")


def lobster(d, cx, cy, s, fill, dark):
    d.ellipse((cx - 0.28 * s, cy - 0.55 * s, cx + 0.28 * s, cy + 0.2 * s), fill=fill)  # body
    for i in range(4):  # tail
        y = cy + 0.2 * s + i * 0.13 * s
        w = 0.24 * s - i * 0.03 * s
        d.ellipse((cx - w, y - 0.08 * s, cx + w, y + 0.09 * s), fill=fill, outline=dark, width=3)
    d.polygon([(cx, cy + 0.68 * s), (cx - 0.3 * s, cy + 0.85 * s), (cx + 0.3 * s, cy + 0.85 * s)], fill=fill)
    for side in (-1, 1):  # arms and claws
        d.line([(cx + side * 0.2 * s, cy - 0.4 * s), (cx + side * 0.5 * s, cy - 0.65 * s)], fill=fill, width=int(0.09 * s))
        x, y = cx + side * 0.6 * s, cy - 0.85 * s
        d.ellipse((x - 0.2 * s, y - 0.28 * s, x + 0.2 * s, y + 0.22 * s), fill=fill)
        d.polygon([(x, y - 0.3 * s), (x + side * 0.08 * s, y - 0.02 * s), (x - side * 0.06 * s, y - 0.32 * s)], fill=(0, 0, 0, 0))
        for k in range(3):  # legs
            ly = cy - 0.15 * s + k * 0.13 * s
            d.line([(cx + side * 0.25 * s, ly), (cx + side * 0.48 * s, ly + 0.08 * s)], fill=dark, width=5)
    for side in (-1, 1):  # feelers
        d.line([(cx + side * 0.08 * s, cy - 0.55 * s), (cx + side * 0.35 * s, cy - 1.05 * s)], fill=dark, width=4)


def skull_potato(d, cx, cy, rx, ry):
    """A potato with a skull's face: the Spud or Die mascot."""
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=CREAM, outline=INK, width=10)
    for side in (-1, 1):  # eye sockets
        ex = cx + side * rx * 0.38
        d.ellipse((ex - rx * 0.24, cy - ry * 0.45, ex + rx * 0.24, cy + ry * 0.05), fill=INK)
    d.polygon([(cx, cy + ry * 0.05), (cx - rx * 0.09, cy + ry * 0.3), (cx + rx * 0.09, cy + ry * 0.3)], fill=INK)
    top, bot = cy + ry * 0.42, cy + ry * 0.75
    d.rectangle((cx - rx * 0.4, top, cx + rx * 0.4, bot), fill=CREAM, outline=INK, width=6)
    for i in range(1, 6):
        x = cx - rx * 0.4 + i * rx * 0.8 / 6
        d.line([(x, top), (x, bot)], fill=INK, width=5)
    d.line([(cx - rx * 0.4, (top + bot) / 2), (cx + rx * 0.4, (top + bot) / 2)], fill=INK, width=4)
    for ex, ey in ((-0.7, -0.6), (0.75, -0.3), (-0.8, 0.4)):  # potato eyes, still
        x, y = cx + ex * rx, cy + ey * ry
        d.ellipse((x - 8, y - 6, x + 8, y + 6), fill=SPUD)


def fork(d, x0, y0, x1, y1, fill):
    d.line([(x0, y0), (x1, y1)], fill=fill, width=22)
    ang = math.atan2(y1 - y0, x1 - x0)
    px, py = -math.sin(ang), math.cos(ang)
    for k in (-1.5, -0.5, 0.5, 1.5):  # tines past the far end
        bx, by = x1 + px * k * 14, y1 + py * k * 14
        d.line([(bx, by), (bx + math.cos(ang) * 60, by + math.sin(ang) * 60)], fill=fill, width=9)
    d.line([(x1 + px * -26, y1 + py * -26), (x1 + px * 26, y1 + py * 26)], fill=fill, width=12)


def angry_gull(d, cx, cy, s):
    """A gull with a stolen fry and a grudge."""
    d.ellipse((cx - 0.75 * s, cy - 0.2 * s, cx + 0.45 * s, cy + 0.55 * s), fill=CREAM, outline=INK, width=8)  # body
    d.polygon([(cx - 0.6 * s, cy), (cx + 0.1 * s, cy + 0.05 * s), (cx - 0.95 * s, cy + 0.45 * s)], fill=(150, 156, 165), outline=INK)  # wing
    d.ellipse((cx + 0.05 * s, cy - 0.65 * s, cx + 0.65 * s, cy - 0.05 * s), fill=CREAM, outline=INK, width=8)  # head
    d.polygon([(cx + 0.58 * s, cy - 0.38 * s), (cx + 1.05 * s, cy - 0.3 * s), (cx + 0.58 * s, cy - 0.2 * s)], fill=GOLD, outline=INK)  # beak
    d.ellipse((cx + 0.86 * s, cy - 0.3 * s, cx + 0.94 * s, cy - 0.22 * s), fill=RED)
    d.ellipse((cx + 0.32 * s, cy - 0.45 * s, cx + 0.44 * s, cy - 0.33 * s), fill=INK)  # eye
    d.line([(cx + 0.22 * s, cy - 0.58 * s), (cx + 0.5 * s, cy - 0.44 * s)], fill=INK, width=10)  # the brow
    d.polygon([(cx + 0.85 * s, cy - 0.32 * s), (cx + 1.25 * s, cy - 0.7 * s), (cx + 1.32 * s, cy - 0.62 * s), (cx + 0.92 * s, cy - 0.24 * s)],
              fill=(240, 200, 70), outline=INK)  # the fry


def badge(img, draw_fn):
    tile = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(tile), tile)
    return tile


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


def skull_potato(d, cx, cy, rx, ry):
    """A potato with a skull's face: the Spud or Die mascot."""
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=CREAM, outline=INK, width=10)
    for side in (-1, 1):  # eye sockets
        ex = cx + side * rx * 0.38
        d.ellipse((ex - rx * 0.24, cy - ry * 0.45, ex + rx * 0.24, cy + ry * 0.05), fill=INK)
    d.polygon([(cx, cy + ry * 0.05), (cx - rx * 0.09, cy + ry * 0.3), (cx + rx * 0.09, cy + ry * 0.3)], fill=INK)
    top, bot = cy + ry * 0.42, cy + ry * 0.75
    d.rectangle((cx - rx * 0.4, top, cx + rx * 0.4, bot), fill=CREAM, outline=INK, width=6)
    for i in range(1, 6):
        x = cx - rx * 0.4 + i * rx * 0.8 / 6
        d.line([(x, top), (x, bot)], fill=INK, width=5)
    d.line([(cx - rx * 0.4, (top + bot) / 2), (cx + rx * 0.4, (top + bot) / 2)], fill=INK, width=4)
    for ex, ey in ((-0.7, -0.6), (0.75, -0.3), (-0.8, 0.4)):  # potato eyes, still
        x, y = cx + ex * rx, cy + ey * ry
        d.ellipse((x - 8, y - 6, x + 8, y + 6), fill=SPUD)


def fork(d, x0, y0, x1, y1, fill):
    d.line([(x0, y0), (x1, y1)], fill=fill, width=22)
    ang = math.atan2(y1 - y0, x1 - x0)
    px, py = -math.sin(ang), math.cos(ang)
    for k in (-1.5, -0.5, 0.5, 1.5):  # tines past the far end
        bx, by = x1 + px * k * 14, y1 + py * k * 14
        d.line([(bx, by), (bx + math.cos(ang) * 60, by + math.sin(ang) * 60)], fill=fill, width=9)
    d.line([(x1 + px * -26, y1 + py * -26), (x1 + px * 26, y1 + py * 26)], fill=fill, width=12)


def angry_gull(d, cx, cy, s):
    """A gull with a stolen fry and a grudge."""
    d.ellipse((cx - 0.75 * s, cy - 0.2 * s, cx + 0.45 * s, cy + 0.55 * s), fill=CREAM, outline=INK, width=8)  # body
    d.polygon([(cx - 0.6 * s, cy), (cx + 0.1 * s, cy + 0.05 * s), (cx - 0.95 * s, cy + 0.45 * s)], fill=(150, 156, 165), outline=INK)  # wing
    d.ellipse((cx + 0.05 * s, cy - 0.65 * s, cx + 0.65 * s, cy - 0.05 * s), fill=CREAM, outline=INK, width=8)  # head
    d.polygon([(cx + 0.58 * s, cy - 0.38 * s), (cx + 1.05 * s, cy - 0.3 * s), (cx + 0.58 * s, cy - 0.2 * s)], fill=GOLD, outline=INK)  # beak
    d.ellipse((cx + 0.86 * s, cy - 0.3 * s, cx + 0.94 * s, cy - 0.22 * s), fill=RED)
    d.ellipse((cx + 0.32 * s, cy - 0.45 * s, cx + 0.44 * s, cy - 0.33 * s), fill=INK)  # eye
    d.line([(cx + 0.22 * s, cy - 0.58 * s), (cx + 0.5 * s, cy - 0.44 * s)], fill=INK, width=10)  # the brow
    d.polygon([(cx + 0.85 * s, cy - 0.32 * s), (cx + 1.25 * s, cy - 0.7 * s), (cx + 1.32 * s, cy - 0.62 * s), (cx + 0.92 * s, cy - 0.24 * s)],
              fill=(240, 200, 70), outline=INK)  # the fry


def badge(img, draw_fn):
    tile = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(tile), tile)
    return tile


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


# --- the prints, in tile order ---------------------------------------------------------

def spud_or_die(d, im):
    # Red Clay Spud Co.: workwear from the potato fields.
    fork(d, 90, 420, 360, 150, CLAY)
    fork(d, 422, 420, 152, 150, CLAY)
    skull_potato(d, T / 2, 270, 120, 100)
    text(d, (T / 2, 70), "SPUD OR DIE", 80, CREAM, stroke=7)
    text(d, (T / 2, 450), "RED CLAY SPUD CO.", 40, CLAY, stroke=5, stroke_fill=CREAM)


def canada_gull(d, im):
    # Canada Gull: puffers for people who'll never see the Arctic.
    d.ellipse((30, 30, T - 30, T - 30), fill=INK, outline=CREAM, width=10)
    angry_gull(d, 200, 250, 150)
    text(d, (T / 2, 90), "CANADA GULL", 50, CREAM, max_w=360)
    text(d, (T / 2, 420), "PROTECT YOUR FRIES", 30, GOLD, max_w=340)


def gentle_island(d, im):
    text(d, (T / 2, 140), "THE GENTLE", 80, CREAM, kind="serif", stroke=6)
    text(d, (T / 2, 250), "ISLAND*", 130, CREAM, kind="serif", stroke=7)
    d.line([(60, 330), (T - 60, 310)], fill=RED, width=12)
    text(d, (T / 2, 400), "*not after last call", 42, RED, kind="serif", stroke=4, stroke_fill=CREAM)


def cfa(d, im):
    # A rubber stamp, slapped on crooked.
    stamp = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    s = ImageDraw.Draw(stamp)
    s.rounded_rectangle((40, 140, T - 40, 370), radius=20, outline=RED, width=14)
    text(s, (T / 2, 230), "C.F.A.", 150, RED)
    text(s, (T / 2, 330), "CAME FROM AWAY", 40, RED)
    im.alpha_composite(stamp.rotate(-12, resample=Image.BICUBIC))
    text(d, (T / 2, 450), "3 generations in. still one.", 32, CREAM, kind="serif", stroke=3)


def whos_your_father(d, im):
    text(d, (T / 2, 110), "WHO'S", 120, CREAM, stroke=7)
    text(d, (T / 2, 230), "YOUR", 120, CREAM, stroke=7)
    text(d, (T / 2, 350), "FATHER?", 120, GOLD, stroke=7)
    text(d, (T / 2, 450), "(we might be related)", 36, CREAM, kind="serif", stroke=3)


def pay_to_leave(d, im):
    # The bridge off the Island is free one way. Guess which.
    text(d, (T / 2, 75), "FREE TO GET ON.", 60, CREAM, stroke=5)
    y0 = 250
    d.line([(20, y0), (T - 20, y0)], fill=CREAM, width=12)
    for i in range(7):
        x = 20 + i * (T - 40) / 7.0
        d.arc((x, y0 - 45, x + (T - 40) / 7.0, y0 + 55), 180, 360, fill=CREAM, width=8)
        d.line([(x, y0), (x, y0 + 70)], fill=CREAM, width=8)
    for i in range(5):
        d.arc((50 + i * 90, 330, 125 + i * 90, 360), 0, 180, fill=SEA, width=6)
    text(d, (T / 2, 430), "PAY TO LEAVE.", 76, RED, stroke=6, stroke_fill=CREAM)


def spud_kings(d, im):
    # The Charlottetown Spud Kings, junior hockey. They play dirty.
    shield = [(T / 2, 480), (70, 360), (60, 80), (T / 2, 40), (T - 60, 80), (T - 70, 360)]
    d.polygon(shield, fill=INK)
    d.line(shield + [shield[0]], fill=GOLD, width=14)
    for x0 in (120, 300):  # crossed sticks
        d.line([(x0, 130), (x0 + 90, 330)] if x0 == 120 else [(x0 + 90, 130), (x0, 330)], fill=(120, 90, 60), width=14)
    potato(d, T / 2, 245, 95, 70, SPUD, (90, 60, 30))
    for side in (-1, 1):  # angry eyes and brows
        ex = T / 2 + side * 35
        d.ellipse((ex - 12, 220, ex + 12, 244), fill=INK)
        d.line([(ex - side * 24, 218), (ex + side * 20, 196)], fill=INK, width=10)  # inner end down: a scowl
    d.chord((T / 2 - 40, 255, T / 2 + 40, 305), 0, 180, fill=INK)  # snarl
    for i in range(4):
        x = T / 2 - 30 + i * 20
        d.polygon([(x, 280), (x + 10, 280), (x + 5, 293)], fill=CREAM)
    crown = [(T / 2 - 75, 175), (T / 2 - 75, 115), (T / 2 - 38, 150), (T / 2, 95), (T / 2 + 38, 150), (T / 2 + 75, 115), (T / 2 + 75, 175)]
    d.polygon(crown, fill=GOLD, outline=INK)
    text(d, (T / 2, 355), "SPUD KINGS", 62, CREAM, max_w=330)
    text(d, (T / 2, 405), "WE HIT LIKE HARVESTERS", 22, GOLD, max_w=240)


def varsity_s(d, im):
    # The chenille letter for the Spud Kings varsity jacket.
    text(d, (T / 2, T / 2), "S", 470, GOLD, kind="serif", stroke=22, stroke_fill=CREAM)


def mussel_beach(d, im):
    # A mussel with arms. Big ones.
    cx, cy = T / 2, 250
    shell = [(cx, cy - 130), (cx + 70, cy - 60), (cx + 60, cy + 90), (cx, cy + 130), (cx - 60, cy + 90), (cx - 70, cy - 60)]
    d.polygon(shell, fill=(30, 34, 60), outline=CREAM)
    d.line(shell + [shell[0]], fill=CREAM, width=8)
    for i in range(1, 4):
        d.arc((cx - 60 + i * 6, cy - 110 + i * 40, cx + 60 - i * 6, cy - 50 + i * 40), 20, 160, fill=(80, 90, 130), width=4)
    for side in (-1, 1):  # flexing arms
        sx = cx + side * 60
        ex = cx + side * 160
        d.line([(sx, cy), (ex, cy)], fill=CREAM, width=26)
        d.line([(ex, cy + 10), (ex, cy - 90)], fill=CREAM, width=24)
        d.ellipse((cx + side * 110 - 35, cy - 45, cx + side * 110 + 35, cy + 15), fill=CREAM)  # biceps
        d.ellipse((ex - 22, cy - 120, ex + 22, cy - 76), fill=CREAM)  # fist
    text(d, (T / 2, 60), "MUSSEL BEACH", 66, CREAM, stroke=6)
    text(d, (T / 2, 440), "NO SHELLFISH EXCUSES", 38, GOLD, stroke=4)


def potholes(d, im):
    # University Avenue in March.
    d.ellipse((90, 200, T - 90, 330), fill=INK)
    for a in range(0, 360, 40):
        r = math.radians(a)
        d.line([(T / 2 + math.cos(r) * 150, 265 + math.sin(r) * 60), (T / 2 + math.cos(r) * 230, 265 + math.sin(r) * 100)], fill=INK, width=6)
    d.ellipse((150, 215, T - 150, 300), fill=(70, 50, 40))
    text(d, (T / 2, 85), "I SURVIVED", 74, CREAM, stroke=6)
    text(d, (T / 2, 165), "THE POTHOLES", 64, GOLD, stroke=6)
    text(d, (T / 2, 400), "UNIVERSITY AVE", 54, CREAM, stroke=5)
    text(d, (T / 2, 460), "pray for my suspension", 30, CREAM, kind="serif", stroke=3)


def tom_hurtins(d, im):
    # Tom Hurtin's, the coffee and doughnut place on every corner.
    d.rounded_rectangle((40, 100, T - 40, 360), radius=40, fill=(150, 30, 34), outline=CREAM, width=8)
    text(d, (T / 2, 190), "Tom Hurtin's", 84, CREAM, kind="serif", max_w=400)
    text(d, (T / 2, 290), "ALWAYS HURTIN'", 46, GOLD, max_w=380)
    text(d, (T / 2, 430), "ROLL UP THE RIM TO LOSE", 34, CREAM, stroke=3)


def crack_em(d, im):
    lobster(d, T / 2, 260, 150, RED, (110, 16, 20))
    # Shades.
    d.rectangle((T / 2 - 60, 205, T / 2 + 60, 218), fill=INK)
    for side in (-1, 1):
        x = T / 2 + side * 32
        d.rounded_rectangle((x - 30, 205, x + 30, 245), radius=10, fill=INK)
    text(d, (T / 2, 55), "CRACK 'EM OPEN", 56, CREAM, stroke=5)
    text(d, (T / 2, 465), "LOBSTER SUPPER CLUB", 38, CREAM, stroke=4)


def island_time(d, im):
    # A clock with its hands fallen off.
    d.ellipse((136, 40, 376, 280), fill=CREAM, outline=INK, width=12)
    cx, cy = 256, 160
    for i in range(12):
        a = i * math.pi / 6
        d.line([(cx + math.cos(a) * 95, cy + math.sin(a) * 95), (cx + math.cos(a) * 108, cy + math.sin(a) * 108)], fill=INK, width=6)
    d.line([(cx - 40, 250), (cx + 30, 262)], fill=INK, width=10)
    d.line([(cx - 10, 240), (cx + 60, 230)], fill=INK, width=6)
    text(d, (T / 2, 345), "ISLAND TIME", 82, CREAM, stroke=6)
    text(d, (T / 2, 425), "we'll get to it.", 44, GOLD, kind="serif", stroke=3)
    text(d, (T / 2, 480), "(we won't)", 32, CREAM, kind="serif", stroke=3)


def mainlanders(d, im):
    # Warning tape top and bottom.
    for y in (40, 430):
        d.rectangle((20, y, T - 20, y + 50), fill=GOLD)
        for i in range(-2, 14):
            x = 20 + i * 44
            d.polygon([(x, y + 50), (x + 22, y + 50), (x + 47, y), (x + 25, y)], fill=INK)
    d.rectangle((0, 0, T, 40), fill=(0, 0, 0, 0))
    d.rectangle((0, 480, T, T), fill=(0, 0, 0, 0))
    text(d, (T / 2, 160), "MAINLANDERS", 84, CREAM, stroke=6)
    text(d, (T / 2, 270), "GO HOME", 120, RED, stroke=7, stroke_fill=CREAM)
    text(d, (T / 2, 370), "(after you spend your money)", 30, CREAM, kind="serif", stroke=3)


def red_mud(d, im):
    # Red Mud Racing: dirt roads, no brakes.
    sq = 34
    for i in range(10):  # a checker band
        for j in range(3):
            if (i + j) % 2 == 0:
                d.rectangle((86 + i * sq, 60 + j * sq, 86 + (i + 1) * sq, 60 + (j + 1) * sq), fill=CREAM)
    d.rectangle((86, 60, 86 + 10 * sq, 60 + 3 * sq), outline=CREAM, width=4)
    text(d, (T / 2, 250), "RED MUD", 120, CLAY, stroke=8, stroke_fill=CREAM)
    text(d, (T / 2, 350), "RACING", 90, CREAM, stroke=6)
    for k in range(2):  # tyre tracks
        pts = [(40 + i * 36, 430 + k * 30 + (10 if i % 2 else -10)) for i in range(13)]
        d.line(pts, fill=CLAY, width=10)


def tca(d, im):
    # The game's own merch: the TCA shield from branding/.
    logo = Image.open(os.path.join(ROOT, "branding", "logo.png")).convert("RGBA")
    logo.thumbnail((T - 60, T - 60), Image.LANCZOS)
    im.alpha_composite(logo, ((T - logo.width) // 2, (T - logo.height) // 2))


# In tile order; must match PRINTS in scripts/characters/outfit.gd. The
# second value is how worn the print is (0 new, about 0.3 well washed).
PRINTS = [(spud_or_die, 0.22), (canada_gull, 0.08), (gentle_island, 0.25), (cfa, 0.3),
          (whos_your_father, 0.22), (pay_to_leave, 0.2), (spud_kings, 0.15), (varsity_s, 0.05),
          (mussel_beach, 0.2), (potholes, 0.28), (tom_hurtins, 0.15), (crack_em, 0.2),
          (island_time, 0.25), (mainlanders, 0.25), (red_mud, 0.3), (tca, 0.1)]


def main():
    sheet = Image.new("RGBA", (T * 4, T * 4), (0, 0, 0, 0))
    for i, (fn, wear) in enumerate(PRINTS):
        tile = distress(badge(None, fn), wear, i)
        sheet.alpha_composite(tile, ((i % 4) * T, (i // 4) * T))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Draw the advertising in the town: window posters for the chains' shops
and roadside billboards, one PNG each in textures/ads/.

Every ad belongs to one of the world's spoof brands (data/map_config.json
"brands"). A brand lists its window posters there ("posters"), and a
billboard shows one by its name (a sign=billboard point with "ad" set, see
scripts/world/placed_signs.gd). scripts/world/ads.gd finds the files.

Run from the repository root:

    python3 tools/make_ads.py

Needs Pillow and NumPy; the lettering comes from tools/fonts/ (see the
README there) and DejaVu Sans for the fine print. Posters are 512 x 768
(2:3, about 0.9 x 1.35 m in a window); billboards 1536 x 480 (3.2:1).
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_clothing_prints as mcp  # noqa: E402  (shared lettering helpers)
from make_clothing_prints import CLEAR, place, word  # noqa: E402

mcp.FACES["plain"] = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
mcp.FACES["plain_bold"] = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures", "ads")
PW, PH = 512, 768
BW, BH = 1536, 480

# Tim Hardly's colours.
TH_RED = (166, 25, 46, 255)
TH_DARK = (110, 14, 28, 255)
CREAM = (246, 239, 224, 255)
BROWN = (92, 56, 34, 255)
COFFEE = (120, 74, 44, 255)
INK = (28, 24, 22, 255)
WHITE = (252, 252, 248, 255)
TAN = (214, 164, 100, 255)
EGG = (250, 246, 232, 255)
YOLK = (246, 184, 40, 255)
CHEESE = (248, 196, 60, 255)
BACON = (176, 62, 46, 255)
FAT = (236, 190, 160, 255)
SMOKE = (120, 120, 120, 170)


def canvas(w, h, bg):
    return Image.new("RGBA", (w, h), bg)


# --- the Tim Hardly's badge --------------------------------------------------------------

def th_logo(img, cx, cy, w, tagline=True, bg=TH_RED, fg=CREAM):
    h = w * 0.5
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=h / 2, fill=bg)
    d.rounded_rectangle((cx - w / 2 + w * 0.03, cy - h / 2 + w * 0.03, cx + w / 2 - w * 0.03, cy + h / 2 - w * 0.03),
                        radius=h / 2 - w * 0.03, outline=fg, width=max(2, int(w * 0.008)))
    place(img, word("Tim Hardly's", "script", w * 0.19, fg), cx, cy - (h * 0.1 if tagline else 0), max_w=w * 0.78)
    if tagline:
        place(img, word("CLOSE ENOUGH", "bebas", w * 0.075, fg, tracking=0.25), cx, cy + h * 0.24)


# --- food ----------------------------------------------------------------------------

def muffin_sandwich(d, cx, cy, s, filling="bacon"):
    """An English muffin breakfast sandwich, side on."""
    d.rounded_rectangle((cx - s, cy + 0.35 * s, cx + s, cy + 0.65 * s), radius=0.12 * s, fill=TAN)  # bottom
    if filling == "bacon":
        for k in range(3):  # wavy strips hanging out
            y = cy + 0.22 * s - k * 0.12 * s
            pts = [(cx - 1.12 * s + i * 0.1 * s, y + math.sin(i * 1.3 + k) * 0.04 * s) for i in range(24)]
            d.line(pts, fill=BACON, width=int(0.09 * s), joint="curve")
            d.line([(x, y2 - 0.01 * s) for x, y2 in pts], fill=FAT, width=int(0.025 * s), joint="curve")
    d.ellipse((cx - 0.95 * s, cy - 0.12 * s, cx + 0.95 * s, cy + 0.18 * s), fill=EGG)  # egg
    d.polygon([(cx - 0.9 * s, cy - 0.12 * s), (cx + 0.9 * s, cy - 0.12 * s), (cx + 0.55 * s, cy + 0.12 * s),
               (cx + 0.35 * s, cy - 0.02 * s), (cx - 0.2 * s, cy + 0.2 * s), (cx - 0.4 * s, cy - 0.02 * s)], fill=CHEESE)
    d.chord((cx - s, cy - 0.75 * s, cx + s, cy + 0.05 * s), 180, 360, fill=TAN)  # top
    d.chord((cx - s, cy - 0.75 * s, cx + s, cy + 0.05 * s), 200, 340, fill=(226, 182, 120, 255))
    for i in range(14):  # cornmeal
        a = math.radians(200 + i * 10)
        d.ellipse((cx + math.cos(a) * 0.8 * s - 4, cy - 0.35 * s + math.sin(a) * 0.32 * s - 3,
                   cx + math.cos(a) * 0.8 * s + 4, cy - 0.35 * s + math.sin(a) * 0.32 * s + 3), fill=(246, 230, 196, 255))


def bagel(img, cx, cy, r, burnt=0.0):
    """A bagel from above, golden to charcoal across it."""
    ys, xs = np.mgrid[0:img.height, 0:img.width].astype(np.float32)
    dx, dy = xs - cx, ys - cy
    dist = np.sqrt(dx * dx + dy * dy)
    ring = (dist < r) & (dist > r * 0.32)
    shade = np.clip(0.55 + 0.45 * (1.0 - np.abs(dist - r * 0.66) / (r * 0.34)), 0, 1)
    side = np.clip((dx / r) * 0.5 + 0.5, 0, 1)  # burnt on the right
    char = np.clip((side - (1.0 - burnt)) / max(0.01, burnt), 0, 1) if burnt > 0 else np.zeros_like(side)
    base = np.array([214, 160, 92], np.float32)
    dark = np.array([40, 26, 20], np.float32)
    col = (base[None, None, :] * (1 - char[..., None]) + dark[None, None, :] * char[..., None]) * shade[..., None]
    a = np.asarray(img).copy()
    a[ring, :3] = np.clip(col[ring], 0, 255).astype(np.uint8)
    a[ring, 3] = 255
    img.paste(Image.fromarray(a, "RGBA"))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(4)
    for _ in range(70):  # sesame seeds
        ang = rng.uniform(0, math.tau)
        rr = rng.uniform(0.42, 0.92) * r
        x, y = cx + math.cos(ang) * rr, cy + math.sin(ang) * rr
        if x < cx + r * (1.0 - 2.0 * burnt) * 0.9:
            d.ellipse((x - 5, y - 3, x + 5, y + 3), fill=(250, 238, 206, 255))


def smoke(img, x, y, h, width=14, colour=SMOKE):
    layer = Image.new("RGBA", img.size, CLEAR)
    d = ImageDraw.Draw(layer)
    for k in range(3):
        pts = [(x + k * width * 2.2 + math.sin(i * 0.5 + k) * width * 1.2, y - i * h / 20.0) for i in range(21)]
        d.line(pts, fill=colour, width=width, joint="curve")
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(width * 0.4)))


def cup(d, cx, bottom, h, colour=TH_RED, lid=WHITE, label=True):
    """A paper coffee cup with a lid."""
    tw, bw = h * 0.36, h * 0.27
    top = bottom - h
    d.polygon([(cx - tw, top + h * 0.1), (cx + tw, top + h * 0.1), (cx + bw, bottom), (cx - bw, bottom)], fill=colour)
    d.rounded_rectangle((cx - tw * 1.08, top, cx + tw * 1.08, top + h * 0.12), radius=h * 0.03, fill=lid)
    d.rectangle((cx - tw * 0.4, top - h * 0.03, cx + tw * 0.4, top + h * 0.01), fill=lid)
    if label:
        d.polygon([(cx - tw * 0.93, top + h * 0.38), (cx + tw * 0.93, top + h * 0.38), (cx + tw * 0.88, top + h * 0.62), (cx - tw * 0.88, top + h * 0.62)],
                  fill=(150, 110, 70, 255))  # sleeve


def iced_cup(d, cx, bottom, h):
    tw, bw = h * 0.33, h * 0.25
    top = bottom - h
    d.polygon([(cx - tw, top + h * 0.12), (cx + tw, top + h * 0.12), (cx + bw, bottom), (cx - bw, bottom)], fill=(200, 210, 214, 120))
    d.polygon([(cx - tw * 0.96, top + h * 0.2), (cx + tw * 0.96, top + h * 0.2), (cx + bw * 0.96, bottom - 4), (cx - bw * 0.96, bottom - 4)], fill=(176, 128, 90, 255))
    d.chord((cx - tw * 1.05, top - h * 0.12, cx + tw * 1.05, top + h * 0.28), 180, 360, fill=(230, 236, 238, 150))  # dome lid
    d.line([(cx + tw * 0.2, top + h * 0.05), (cx + tw * 0.55, top - h * 0.35)], fill=TH_RED, width=int(h * 0.05))  # straw


def finish(img, name, wear=0.0):
    """A little sun fade and paper texture, then save."""
    a = np.asarray(img, dtype=np.float32).copy()
    rng = np.random.default_rng(abs(hash(name)) % 2**32)
    grain = rng.normal(0.0, 4.0, a.shape[:2])[..., None]
    a[..., :3] = np.clip(a[..., :3] * (1.0 - wear) + 235 * wear + grain, 0, 255)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(a.astype(np.uint8), "RGBA").convert("RGB").save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def fine(img, text, cx, cy, size, fill, max_w):
    place(img, word(text, "plain", size, fill), cx, cy, max_w=max_w)


# --- window posters -------------------------------------------------------------------

def poster_sausage():
    img = canvas(PW, PH, CREAM)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, PW, 210), fill=TH_RED)
    place(img, word("NEW!", "bebas", 60, YOLK, tracking=0.2), PW / 2, 48)
    place(img, word("SAUSAGE & EGG", "anton", 84, CREAM), PW / 2, 118, max_w=460)
    place(img, word("BREAKFAST SANDWICH", "bebas", 44, CREAM, tracking=0.12), PW / 2, 178, max_w=460)
    muffin_sandwich(d, PW / 2, 380, 170)
    place(img, word("now with bacon.", "script", 62, TH_RED), PW / 2, 548, max_w=440)
    fine(img, "We ran out of sausage in 2019.", PW / 2, 612, 22, INK, 440)
    th_logo(img, PW / 2, 700, 230)
    finish(img, "tim_hardlys_sausage", 0.04)


def poster_bagel():
    img = canvas(PW, PH, (40, 34, 30, 255))
    bagel(img, PW / 2, 330, 150, burnt=0.55)
    smoke(img, PW / 2 + 60, 200, 160, 12)
    place(img, word("TOASTED BAGEL", "anton", 80, CREAM), PW / 2, 70, max_w=460)
    place(img, word("SEASON", "bebas", 60, YOLK, tracking=0.4), PW / 2, 132)
    place(img, word("Toasted. Untoasted.", "bebas", 50, CREAM, tracking=0.05), PW / 2, 528)
    place(img, word("On fire.", "script", 64, YOLK), PW / 2, 588)
    fine(img, "Let's find out together.", PW / 2, 640, 22, CREAM, 440)
    th_logo(img, PW / 2, 712, 210)
    finish(img, "tim_hardlys_bagel", 0.05)


def poster_iced_capp():
    img = canvas(PW, PH, (238, 226, 206, 255))
    d = ImageDraw.Draw(img)
    for i in range(8):  # summery rays
        a0 = i * 45
        d.pieslice((-300, -100, PW + 300, 900), a0, a0 + 20, fill=(246, 214, 160, 255))
    iced_cup(d, PW / 2, 545, 300)
    smoke(img, PW / 2 - 40, 225, 60, 10, (255, 255, 255, 210))
    place(img, word("TRY OUR NEW", "bebas", 52, TH_RED, tracking=0.2), PW / 2, 52)
    place(img, word("ICED CAPP", "anton", 104, TH_DARK), PW / 2, 120, max_w=470)
    place(img, word("Served warm.", "script", 66, TH_RED), PW / 2, 608, max_w=440)
    th_logo(img, PW / 2, 700, 230)
    finish(img, "tim_hardlys_iced_capp", 0.06)


def poster_surprise():
    img = canvas(PW, PH, TH_RED)
    d = ImageDraw.Draw(img)
    place(img, word("START", "anton", 120, CREAM), PW / 2, 90)
    place(img, word("YOUR DAY", "anton", 120, CREAM), PW / 2, 205, max_w=470)
    place(img, word("WITH A", "bebas", 64, YOLK, tracking=0.3), PW / 2, 298)
    place(img, word("Surprise", "script", 120, CREAM), PW / 2, 390, max_w=470)
    d.rounded_rectangle((60, 480, PW - 60, 600), radius=16, fill=CREAM)
    place(img, word("You ordered it.", "bebas", 44, TH_RED, tracking=0.08), PW / 2, 515)
    place(img, word("We made something.", "bebas", 44, TH_RED, tracking=0.08), PW / 2, 565)
    th_logo(img, PW / 2, 692, 240, bg=CREAM, fg=TH_RED)
    finish(img, "tim_hardlys_surprise", 0.04)


def poster_hiring():
    img = canvas(PW, PH, CREAM)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, PW, 170), fill=INK)
    place(img, word("NOW HIRING", "anton", 110, YOLK), PW / 2, 86, max_w=470)
    y = 230
    for line in ("Must be able to hear", "\"double-double\"", "and pour a black coffee", "with confidence."):
        place(img, word(line, "bebas", 52, INK, tracking=0.03), PW / 2, y, max_w=450)
        y += 58
    d.line([(80, 478), (PW - 80, 478)], fill=TH_RED, width=4)
    place(img, word("Arguing with customers", "bebas", 40, TH_RED, tracking=0.05), PW / 2, 515)
    place(img, word("an asset.", "script", 56, TH_RED), PW / 2, 570)
    fine(img, "Ask inside. We'll tell you the wrong day.", PW / 2, 622, 20, INK, 450)
    th_logo(img, PW / 2, 700, 220)
    finish(img, "tim_hardlys_hiring", 0.05)


# --- billboards -----------------------------------------------------------------------

def bb_large_coffee():
    img = canvas(BW, BH, TH_RED)
    d = ImageDraw.Draw(img)
    # The large you asked for, dashed, and the medium you got.
    cx, bottom = 1180, 430
    h = 360
    tw, bw = h * 0.36, h * 0.27
    top = bottom - h
    outline = [(cx - tw, top + h * 0.1), (cx + tw, top + h * 0.1), (cx + bw, bottom), (cx - bw, bottom), (cx - tw, top + h * 0.1)]
    for i in range(len(outline) - 1):
        a, b = outline[i], outline[i + 1]
        n = int(math.dist(a, b) / 22)
        for k in range(0, n, 2):
            p0 = (a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n)
            p1 = (a[0] + (b[0] - a[0]) * (k + 1) / n, a[1] + (b[1] - a[1]) * (k + 1) / n)
            d.line([p0, p1], fill=CREAM, width=6)
    cup(d, cx, bottom, 250, colour=CREAM, lid=WHITE)
    place(img, word("LARGE COFFEE?", "anton", 120, CREAM), 470, 130, max_w=800)
    place(img, word("NO PROBLEM.", "anton", 120, CREAM), 470, 260, max_w=800)
    place(img, word("Medium.", "script", 110, YOLK), 400, 390)
    th_logo(img, 1430, 70, 170, tagline=False, bg=CREAM, fg=TH_RED)
    finish(img, "tim_hardlys_bb_large", 0.03)


def bb_order_ready():
    img = canvas(BW, BH, CREAM)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 40, BH), fill=TH_RED)
    w, _ = place(img, word("YOUR ORDER IS READY.", "anton", 120, INK), 650, 200, max_w=1100)
    # "Your" struck out, "Someone's" written over it.
    x0 = 650 - w / 2
    d.line([(x0 - 10, 205), (x0 + 235, 190)], fill=TH_RED, width=14)
    place(img, word("Someone's", "script", 90, TH_RED), x0 + 130, 95)
    place(img, word("CLOSE ENOUGH.", "bebas", 70, TH_RED, tracking=0.25), 650, 360)
    cup(d, 1290, 440, 300)
    th_logo(img, 1290, 75, 200)
    finish(img, "tim_hardlys_bb_ready", 0.03)


def hash_brown(img, cx, cy, w, h):
    """A golden hash brown patty, crisp at the edges, shredded on top."""
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=h * 0.48, fill=(196, 128, 46, 255))
    d.rounded_rectangle((cx - w / 2 + 10, cy - h / 2 + 8, cx + w / 2 - 10, cy + h / 2 - 8), radius=h * 0.44, fill=(232, 170, 70, 255))
    rng = np.random.default_rng(11)
    for _ in range(90):  # the shreds
        x = rng.uniform(cx - w * 0.42, cx + w * 0.42)
        y = rng.uniform(cy - h * 0.32, cy + h * 0.32)
        a = rng.uniform(-0.5, 0.5)
        ln = rng.uniform(14, 34)
        col = (250, 206, 120, 255) if rng.random() < 0.6 else (204, 132, 50, 255)
        d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=col, width=4)


def bb_hash_brown():
    img = canvas(BW, BH, (34, 30, 28, 255))
    d = ImageDraw.Draw(img)
    place(img, word("\"I WANTED A HASH BROWN TOO.\"", "anton", 112, CREAM), 610, 120, max_w=1120)
    place(img, word("No you didn't.", "script", 104, YOLK), 610, 268)
    place(img, word("NO HASH BROWN FOR YOU.", "bebas", 52, CREAM, tracking=0.2), 610, 395)
    hash_brown(img, 1335, 200, 250, 150)
    d.line([(1215, 95), (1455, 305)], fill=TH_RED, width=16)  # not for you
    th_logo(img, 1335, 400, 190, tagline=True)
    finish(img, "tim_hardlys_bb_hash_brown", 0.04)


def bb_roll_up():
    img = canvas(BW, BH, TH_RED)
    d = ImageDraw.Draw(img)
    place(img, word("ROLL UP THE RIM", "anton", 140, CREAM), 600, 140, max_w=1060)
    place(img, word("to see what you actually ordered.", "script", 70, YOLK), 600, 300, max_w=1060)
    cup(d, 1330, 450, 360, colour=CREAM, label=False)
    d.rectangle((1240, 175, 1420, 215), fill=TH_DARK)  # the rolled rim
    place(img, word("TEA", "bebas", 44, CREAM, tracking=0.3), 1330, 195)
    place(img, word("TIM HARDLY'S", "bebas", 46, CREAM, tracking=0.35), 600, 420)
    finish(img, "tim_hardlys_bb_roll_up", 0.03)


def bb_summerside():
    img = canvas(BW, BH, CREAM)
    d = ImageDraw.Draw(img)
    place(img, word("12 TIM HARDLY'S", "anton", 130, TH_RED), 560, 120, max_w=1000)
    place(img, word("BETWEEN HERE AND SUMMERSIDE.", "bebas", 76, INK, tracking=0.06), 560, 240, max_w=1020)
    place(img, word("Not one will get it right.", "script", 76, TH_RED), 560, 360)
    d.line([(1150, 40), (1150, BH - 40)], fill=TH_RED, width=4)
    th_logo(img, 1345, BH / 2, 300)
    finish(img, "tim_hardlys_bb_summerside", 0.03)


# --- Windy's (Wendy's): split from Tim Hardly's, now selling breakfast ----------------

W_RED = (226, 32, 61, 255)
W_NAVY = (24, 34, 62, 255)
BUN = (214, 150, 74, 255)
PATTY = (92, 52, 34, 255)
LETTUCE = (110, 170, 60, 255)


def windsock(d, x, y, s, colour):
    d.line([(x, y), (x, y + s * 1.4)], fill=colour, width=max(3, int(s * 0.12)))  # pole
    for k in range(4):  # the sock, in bands, blown out to the right
        x0 = x + k * s * 0.42
        top = y + k * s * 0.08
        bot = y + s * 0.62 - k * s * 0.08
        d.polygon([(x0, top), (x0 + s * 0.42, top + s * 0.08), (x0 + s * 0.42, bot - s * 0.08), (x0, bot)], fill=colour if k % 2 == 0 else (255, 255, 255, 255))


def windys_logo(img, cx, cy, w, tagline=True):
    h = w * 0.46
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=h * 0.2, fill=WHITE, outline=W_RED, width=max(3, int(w * 0.02)))
    windsock(d, cx - w * 0.4, cy - h * 0.32, w * 0.12, W_RED)
    place(img, word("Windy's", "script", w * 0.22, W_RED), cx + w * 0.06, cy - (h * 0.08 if tagline else 0), max_w=w * 0.66)
    if tagline:
        place(img, word("OLD-FASHIONED BURGERS", "bebas", w * 0.065, W_NAVY, tracking=0.18), cx + w * 0.06, cy + h * 0.28, max_w=w * 0.7)


def burger(d, cx, cy, s):
    d.chord((cx - s, cy - 0.8 * s, cx + s, cy + 0.2 * s), 180, 360, fill=BUN)
    d.rectangle((cx - 1.05 * s, cy - 0.32 * s, cx + 1.05 * s, cy - 0.2 * s), fill=LETTUCE)
    d.rounded_rectangle((cx - s, cy - 0.22 * s, cx + s, cy + 0.08 * s), radius=0.1 * s, fill=PATTY)
    d.polygon([(cx - 0.95 * s, cy - 0.24 * s), (cx + 0.95 * s, cy - 0.24 * s), (cx + 0.5 * s, cy - 0.05 * s), (cx, cy - 0.16 * s), (cx - 0.5 * s, cy - 0.05 * s)], fill=CHEESE)
    d.rounded_rectangle((cx - s, cy + 0.08 * s, cx + s, cy + 0.38 * s), radius=0.14 * s, fill=BUN)


def no_sign(d, cx, cy, r, colour=W_RED):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=colour, width=int(r * 0.16))
    k = r * 0.7
    d.line([(cx - k, cy - k), (cx + k, cy + k)], fill=colour, width=int(r * 0.16))


def broken_heart(d, cx, cy, s, colour, bg):
    """A heart with a jagged crack down the middle."""
    r = s * 0.5
    d.ellipse((cx - 2 * r, cy - r, cx, cy + r), fill=colour)
    d.ellipse((cx, cy - r, cx + 2 * r, cy + r), fill=colour)
    d.polygon([(cx - 1.93 * r, cy + 0.35 * r), (cx + 1.93 * r, cy + 0.35 * r), (cx, cy + 2.3 * r)], fill=colour)
    crack = [(cx - 0.05 * r, cy - 0.75 * r), (cx + 0.25 * r, cy - 0.1 * r), (cx - 0.25 * r, cy + 0.5 * r),
             (cx + 0.2 * r, cy + 1.1 * r), (cx - 0.1 * r, cy + 1.7 * r), (cx + 0.05 * r, cy + 2.35 * r)]
    d.line(crack, fill=bg, width=int(r * 0.16), joint="curve")


def bb_windys_breakup():
    img = canvas(BW, BH, WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, BW, 26), fill=W_RED)
    d.rectangle((0, BH - 26, BW, BH), fill=W_RED)
    broken_heart(d, 172, 150, 145, W_RED, WHITE)
    place(img, word("WE BROKE UP WITH TIM HARDLY'S.", "anton", 96, W_NAVY), 790, 120, max_w=930)
    place(img, word("So now we do breakfast too.", "script", 84, W_RED), 760, 250, max_w=900)
    place(img, word("Between you and me? It's sh*t.", "bebas", 52, W_NAVY, tracking=0.12), 760, 370)
    windys_logo(img, 1365, 370, 270, tagline=False)
    finish(img, "windys_bb_breakup", 0.03)


def bb_windys_no_burger():
    img = canvas(BW, BH, W_RED)
    d = ImageDraw.Draw(img)
    place(img, word("WINDY'S IS NOW OPEN FOR BREAKFAST.", "anton", 92, WHITE), 580, 95, max_w=1040)
    place(img, word("Like Tim Hardly's, but worse.", "script", 84, (255, 224, 120, 255)), 600, 225)
    place(img, word("NO, YOU CAN'T HAVE A BURGER. EAT YOUR BREAKFAST.", "bebas", 50, WHITE, tracking=0.1), 600, 345, max_w=1060)
    burger(d, 1330, 300, 120)
    no_sign(d, 1330, 270, 150, WHITE)
    windys_logo(img, 1330, 75, 230, tagline=False)
    finish(img, "windys_bb_no_burger", 0.03)


def fries(d, cx, cy, s, box=W_RED):
    """A carton of fries."""
    for k in range(9):
        x = cx - 0.55 * s + k * 0.14 * s
        top = cy - (0.9 + 0.25 * math.sin(k * 1.7)) * s
        d.rectangle((x, top, x + 0.1 * s, cy), fill=(246, 196, 70, 255), outline=(214, 150, 40, 255))
    d.polygon([(cx - 0.75 * s, cy - 0.35 * s), (cx + 0.75 * s, cy - 0.35 * s), (cx + 0.55 * s, cy + 0.75 * s), (cx - 0.55 * s, cy + 0.75 * s)], fill=box)
    d.arc((cx - 0.6 * s, cy - 0.7 * s, cx + 0.6 * s, cy - 0.05 * s), 20, 160, fill=WHITE, width=int(0.06 * s))


def bb_windys_burger_chain():
    img = canvas(BW, BH, W_NAVY)
    d = ImageDraw.Draw(img)
    place(img, word("WE'RE A BURGER CHAIN. YOU CAN TELL.", "anton", 88, WHITE), 600, 90, max_w=1080)
    place(img, word("Everything tastes like a greasy hamburger.", "script", 70, (255, 224, 120, 255)), 600, 220, max_w=1060)
    place(img, word("BUT HEY, WE DO BREAKFAST.", "anton", 76, W_RED), 600, 355)
    muffin_sandwich(d, 1330, 300, 110, filling="bacon")
    for k in range(3):  # grease
        d.ellipse((1260 + k * 55, 395 + (k % 2) * 12, 1290 + k * 55, 418 + (k % 2) * 12), fill=(250, 214, 110, 200))
    windys_logo(img, 1330, 80, 220, tagline=False)
    finish(img, "windys_bb_burger_chain", 0.03)


def bb_windys_fries():
    img = canvas(BW, BH, (255, 214, 92, 255))
    d = ImageDraw.Draw(img)
    place(img, word("TRY OUR NEW", "bebas", 64, W_NAVY, tracking=0.3), 560, 70)
    place(img, word("BREAKFAST FRIES", "anton", 150, W_RED), 560, 185, max_w=1000)
    place(img, word("They're fries.", "script", 92, W_NAVY), 560, 340)
    fries(d, 1330, 270, 170)
    windys_logo(img, 1330, 410, 200, tagline=False)
    finish(img, "windys_bb_fries", 0.03)


def poster_windys_greasy():
    img = canvas(PW, PH, W_NAVY)
    d = ImageDraw.Draw(img)
    place(img, word("WE'RE A", "anton", 96, WHITE), PW / 2, 70)
    place(img, word("BURGER CHAIN.", "anton", 96, WHITE), PW / 2, 170, max_w=470)
    place(img, word("You can tell.", "script", 70, (255, 224, 120, 255)), PW / 2, 265)
    fries(d, PW / 2, 450, 120)
    place(img, word("BUT HEY, WE DO BREAKFAST.", "bebas", 50, WHITE, tracking=0.08), PW / 2, 615, max_w=460)
    windys_logo(img, PW / 2, 712, 220, tagline=False)
    finish(img, "windys_greasy", 0.04)


def poster_windys_after():
    img = canvas(PW, PH, WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, PW, 230), fill=W_RED)
    place(img, word("BURGERS", "anton", 130, WHITE), PW / 2, 85)
    place(img, word("AFTER 11.", "anton", 96, (255, 224, 120, 255)), PW / 2, 182)
    burger(d, PW / 2, 430, 120)
    no_sign(d, PW / 2, 405, 150)
    place(img, word("Not a minute before.", "script", 58, W_RED), PW / 2, 608, max_w=450)
    fine(img, "We will check your watch.", PW / 2, 656, 22, W_NAVY, 440)
    windys_logo(img, PW / 2, 718, 220, tagline=False)
    finish(img, "windys_burgers_after", 0.04)


def poster_windys_breakfast():
    img = canvas(PW, PH, W_RED)
    d = ImageDraw.Draw(img)
    place(img, word("BREAKFAST", "anton", 120, WHITE), PW / 2, 80)
    place(img, word("IS HERE", "anton", 120, WHITE), PW / 2, 196)
    muffin_sandwich(d, PW / 2, 400, 150, filling="none")
    place(img, word("It's fine.", "script", 92, (255, 224, 120, 255)), PW / 2, 585)
    fine(img, "Tim Hardly's taught us everything we know.", PW / 2, 645, 20, WHITE, 450)
    windys_logo(img, PW / 2, 716, 230, tagline=False)
    finish(img, "windys_breakfast_fine", 0.04)


ADS = [poster_sausage, poster_bagel, poster_iced_capp, poster_surprise, poster_hiring,
       bb_large_coffee, bb_order_ready, bb_hash_brown, bb_roll_up, bb_summerside,
       bb_windys_breakup, bb_windys_no_burger, bb_windys_burger_chain, bb_windys_fries,
       poster_windys_after, poster_windys_breakfast, poster_windys_greasy]


def main():
    for fn in ADS:
        fn()


if __name__ == "__main__":
    main()

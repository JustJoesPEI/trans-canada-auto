#!/usr/bin/env python3
"""Draw the art for "Two Years Less a Day", the comic-book panels played
when the police catch you (scripts/wanted/jail_panels.gd).

Same inked, halftoned look as the loading screens (tools/make_branding.py,
whose helpers this borrows): flat printed colours, black ink round the
shapes, halftone dots in the shadows. The panels carry no captions: the
game sets those itself in Anton (branding/fonts/), so the fine and the
excuse can change every time.

Run from the repository root:

    python3 tools/make_jail_panels.py

Needs Pillow and NumPy. Writes branding/jail/:
    backdrop.jpg   the black dotted ground the panels sit on, 1920 x 1080
    judge.jpg      the judge bangs the gavel
    served.jpg     the cell: one tally mark on the wall
    released.jpg   out the front door into the morning (a game screenshot)
    taxpayers.jpg  the Federal Overreach receipt
    dismissed.jpg  the evidence box, flooded again
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_branding as mb  # noqa: E402

OUT = os.path.join(mb.ROOT, "branding", "jail")
W, H = 1200, 760

INK = mb.INK
WOOD = (122, 66, 34)
WOOD_DARK = (84, 42, 22)
ROBE = (24, 20, 30)
SKIN = (232, 182, 140)
HAIR = (205, 205, 200)
GOLD = (236, 184, 52)
PAPER = (250, 246, 234)


def _print(img, colors=24, dot=8):
    """A drawing as a printed comic panel: colours flattened, ink round the
    shapes, halftone dots in the darks (make_branding.comic, without the sky)."""
    img = img.convert("RGB")
    w, h = img.size
    flat = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    g = ImageOps.grayscale(img)
    e = g.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 24 else 0)
    e = e.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.9)).point(lambda v: 255 if v > 90 else 0)
    out = flat.copy()
    out.paste(INK, (0, 0, w, h), e)
    lum = np.asarray(ImageOps.grayscale(flat)).astype(np.float32) / 255
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(((xx + yy) % dot) - dot / 2, ((xx - yy) % dot) - dot / 2)
    dark = np.clip((0.55 - lum) / 0.55, 0, 1)
    out.paste((30, 20, 50), (0, 0, w, h), Image.fromarray(((r < dark * dot * 0.6) * 110).astype(np.uint8)))
    return out


def _burst(w, h, cx, cy, a, b, rays=28):
    """Comic action lines: wedges of two colours fanning out from a point."""
    img = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(img)
    R = math.hypot(w, h)
    for i in range(rays):
        if i % 2:
            continue
        t0 = i / rays * math.tau
        t1 = (i + 1) / rays * math.tau
        d.polygon([(cx, cy), (cx + R * math.cos(t0), cy + R * math.sin(t0)),
                   (cx + R * math.cos(t1), cy + R * math.sin(t1))], fill=b)
    return img


def _star(d, cx, cy, r0, r1, n, fill, outline=None, width=0):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r0
        t = i / (n * 2) * math.tau - math.pi / 2
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    if outline:
        d.line(pts + [pts[0]], fill=outline, width=width, joint="curve")
    d.polygon(pts, fill=fill)


def _text(img, text, size, xy, fill, angle=0.0, outline=None, stroke=0, face="anton"):
    """Text stamped into the art, centred on xy, turned by angle degrees."""
    f = mb.font(face, size)
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    b = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    layer = Image.new("RGBA", (b[2] - b[0] + 40, b[3] - b[1] + 40), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((20 - b[0], 20 - b[1]), text, font=f, fill=fill,
                               stroke_width=stroke, stroke_fill=outline)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    img.paste(layer, (int(xy[0] - layer.width / 2), int(xy[1] - layer.height / 2)), layer)


# ---------------------------------------------------------------- the panels

def judge():
    """A judge behind the bench, gavel coming down: BANG."""
    img = _burst(W, H, 860, 170, (196, 52, 40), (236, 110, 60))
    d = ImageDraw.Draw(img)
    # the judge: robe, white tabs, head, grey hair, glasses
    d.rounded_rectangle([380, 250, 820, 700], 90, fill=ROBE)
    d.polygon([(560, 262), (640, 262), (600, 330)], fill=(250, 250, 250))
    d.rectangle([586, 300, 598, 372], fill=(250, 250, 250))
    d.rectangle([602, 300, 614, 372], fill=(250, 250, 250))
    d.ellipse([505, 92, 695, 290], fill=SKIN)
    d.chord([495, 78, 705, 250], 180, 360, fill=HAIR)
    d.ellipse([492, 150, 530, 214], fill=SKIN)
    d.ellipse([670, 150, 708, 214], fill=SKIN)
    for x in (545, 625):
        d.ellipse([x, 168, x + 46, 204], outline=INK, width=6)
    d.line([(591, 184), (625, 184)], fill=INK, width=5)
    d.line([(548, 152), (590, 160)], fill=INK, width=7)
    d.line([(626, 160), (668, 152)], fill=INK, width=7)
    d.arc([560, 222, 640, 262], 200, 340, fill=INK, width=6)
    # the arm up and the gavel coming down
    d.polygon([(760, 330), (820, 290), (930, 170), (880, 130), (740, 280)], fill=ROBE)
    d.ellipse([872, 118, 940, 182], fill=SKIN)
    d.line([(905, 150), (1040, 260)], fill=WOOD_DARK, width=18)
    head = Image.new("RGBA", (180, 90), (0, 0, 0, 0))
    hd = ImageDraw.Draw(head)
    hd.rounded_rectangle([4, 4, 176, 86], 24, fill=WOOD)
    hd.rectangle([40, 4, 54, 86], fill=GOLD)
    hd.rectangle([126, 4, 140, 86], fill=GOLD)
    head = head.rotate(-50, resample=Image.BICUBIC, expand=True)
    img.paste(head, (980, 200), head)
    # speed lines behind the gavel head
    for k in range(4):
        x, y = 960 + k * 34, 150 + k * 22
        d.line([(x, y), (x + 70, y - 40)], fill=(255, 236, 170), width=7)
    # the bench
    d.rectangle([0, 470, W, H], fill=WOOD)
    d.rectangle([0, 470, W, 500], fill=WOOD_DARK)
    for x in range(60, W, 180):
        d.rectangle([x, 520, x + 8, H], fill=WOOD_DARK)
    d.ellipse([520, 540, 680, 700], fill=GOLD)
    d.ellipse([536, 556, 664, 684], fill=(200, 140, 30))
    leaf = mb._leaf_layer((W, H), 548, 566, 104, fill=GOLD, line_w=0, outer_w=0)
    img.paste(leaf, (0, 0), leaf)
    # the sound block, and BANG
    d.ellipse([1010, 448, 1150, 486], fill=WOOD_DARK)
    _star(d, 1060, 590, 60, 135, 12, (255, 220, 40), INK, 10)
    _text(img, "BANG!", 76, (1060, 594), (213, 43, 30), -12, INK, 3)
    return _print(img)


def served():
    """The cell: cinderblock, a calendar on day one, one tally mark, bars."""
    img = Image.new("RGB", (W, H), (176, 168, 140))
    d = ImageDraw.Draw(img)
    for row, y in enumerate(range(0, H, 64)):
        d.line([(0, y), (W, y)], fill=(130, 122, 100), width=5)
        off = 0 if row % 2 else 70
        for x in range(off, W, 140):
            d.line([(x, y), (x, y + 64)], fill=(130, 122, 100), width=5)
    # the calendar: day one circled, everything after it struck off
    d.rectangle([150, 120, 470, 470], fill=PAPER)
    d.rectangle([150, 120, 470, 190], fill=(200, 46, 36))
    _text(img, "TWO YEARS", 40, (310, 155), PAPER)
    for i in range(28):
        x = 170 + (i % 7) * 42
        y = 210 + (i // 7) * 60
        d.rectangle([x, y, x + 34, y + 48], outline=(150, 150, 150), width=2)
        if i == 0:
            d.ellipse([x - 8, y - 6, x + 42, y + 54], outline=(213, 43, 30), width=6)
    d.line([(212, 266), (452, 440)], fill=(213, 43, 30), width=10)
    d.line([(452, 266), (212, 440)], fill=(213, 43, 30), width=10)
    # one tally mark scratched by the bunk, and the clock
    d.line([(500, 300), (510, 400)], fill=INK, width=9)
    d.ellipse([860, 90, 1040, 270], fill=PAPER, outline=INK, width=8)
    d.line([(950, 180), (950, 110)], fill=INK, width=8)
    d.line([(950, 180), (1000, 200)], fill=INK, width=8)
    # the bunk
    d.rectangle([560, 520, 1200, 600], fill=(70, 80, 60))
    d.rectangle([560, 500, 1200, 525], fill=(220, 214, 196))
    # the cell door's bars, across the right of the panel
    d.rectangle([548, 0, 580, H], fill=(52, 50, 56))
    for x in range(640, W, 110):
        d.rectangle([x, 0, x + 26, H], fill=(52, 50, 56))
        d.rectangle([x + 5, 0, x + 11, H], fill=(120, 118, 126))
    d.rectangle([548, 600, W, 632], fill=(52, 50, 56))
    d.rectangle([548, 606, W, 612], fill=(120, 118, 126))
    return _print(img)


def released():
    """Out the front door into the morning: the town, inked like the
    loading screens."""
    shot = mb._fill(mb._screen("university"), W, H, (0.5, 0.6))
    return mb.comic(shot, mb.MORNING, None)


def taxpayers():
    """Federal Overreach: the receipt for one arrest, longer than the panel."""
    img = _burst(W, H, 600, 380, (40, 110, 70), (70, 150, 90), 36)
    rcpt = Image.new("RGBA", (560, 1000), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rcpt)
    pts = [(0, 0), (560, 0), (560, 960)]
    for k in range(28, -1, -1):
        pts.append((k * 20, 960 + (20 if k % 2 else 0)))
    rd.polygon(pts, fill=PAPER)
    f = mb.font("bebas", 50)
    big = mb.font("anton", 54)
    rd.text((280, 30), "ISLAND SAFETY INITIATIVE", font=mb.font("anton", 34), fill=INK, anchor="mt")
    rd.text((280, 78), "ONE (1) ARREST", font=f, fill=INK, anchor="mt")
    items = [("TACTICAL OVERTIME", "1,904,000"), ("PAINT TANK, DIESEL", "612,400"),
             ("DRONE (NO LAUNCH)", "388,000"), ("HORSE TRAILER", "41,250"),
             ("REVIEW OF REVIEW", "1,254,350")]
    y = 160
    for name, cost in items:
        rd.text((30, y), name, font=f, fill=INK)
        rd.text((530, y), cost, font=f, fill=INK, anchor="ra")
        y += 76
    rd.line([(30, y + 10), (530, y + 10)], fill=INK, width=4)
    rd.text((30, y + 30), "TOTAL", font=big, fill=(200, 40, 30))
    rd.text((530, y + 30), "$4.2M", font=big, fill=(200, 40, 30), anchor="ra")
    rcpt = rcpt.rotate(-6, resample=Image.BICUBIC, expand=True)
    img.paste(rcpt, (int(W / 2 - rcpt.width / 2), 40), rcpt)
    d = ImageDraw.Draw(img)
    # a lone coin, for the fine
    d.ellipse([920, 560, 1060, 700], fill=GOLD, outline=INK, width=6)
    d.ellipse([944, 584, 1036, 676], outline=(200, 140, 30), width=6)
    return _print(img)


def dismissed():
    """The evidence: a soggy box in a puddle, the lid off, nothing in it."""
    img = Image.new("RGB", (W, H), (150, 140, 118))
    d = ImageDraw.Draw(img)
    # shelving behind
    for y in (120, 300):
        d.rectangle([0, y, W, y + 22], fill=(96, 90, 76))
        for x in range(30, W, 230):
            d.rectangle([x, y - 110, x + 150, y], fill=(176, 140, 92))
            d.rectangle([x + 40, y - 80, x + 110, y - 50], fill=PAPER)
    d.rectangle([0, 470, W, H], fill=(112, 108, 100))
    # the puddle
    d.ellipse([140, 560, 1080, 740], fill=(84, 126, 150))
    d.ellipse([220, 590, 1000, 710], fill=(120, 168, 190))
    # the box, lid off
    d.polygon([(380, 360), (820, 360), (860, 660), (340, 660)], fill=(196, 150, 96))
    d.polygon([(380, 360), (820, 360), (780, 300), (420, 300)], fill=(150, 108, 62))
    lid = Image.new("RGBA", (420, 90), (0, 0, 0, 0))
    ImageDraw.Draw(lid).rectangle([0, 0, 420, 90], fill=(210, 168, 110))
    lid = lid.rotate(18, resample=Image.BICUBIC, expand=True)
    img.paste(lid, (720, 520), lid)
    _text(img, "EVIDENCE", 92, (600, 470), (200, 40, 30), 4)
    # the drips, and a tag on a string
    for x, y in ((300, 140), (520, 180), (900, 120), (1040, 220)):
        d.ellipse([x, y, x + 18, y + 30], fill=(120, 168, 190))
    d.line([(820, 420), (930, 470)], fill=INK, width=4)
    d.polygon([(920, 450), (1010, 470), (1000, 520), (910, 500)], fill=PAPER)
    _text(img, "?", 60, (962, 484), INK, -12)
    return _print(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    mb._backdrop(1920, 1080).convert("RGB").save(os.path.join(OUT, "backdrop.jpg"), quality=86)
    for name, draw in (("judge", judge), ("served", served), ("released", released),
                       ("taxpayers", taxpayers), ("dismissed", dismissed)):
        draw().save(os.path.join(OUT, name + ".jpg"), quality=88)
    print("wrote branding/jail/ (backdrop, judge, served, released, taxpayers, dismissed)")


if __name__ == "__main__":
    main()

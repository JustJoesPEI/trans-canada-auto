#!/usr/bin/env python3
"""Draws the signs at the city entrance, Riverside Drive at the Hillsborough
Bridge (Joe's photos from the Riverside Drive lights, 2026-11-24):

* textures/signs/welcome_charlatown.png: the welcome sign on its dark stone
  wall: the round "Historic Charlatown" seal on the left, then
  "Bienvenue / Pjila'si / Welcome", the city's name, and "Birthplace of
  Confederation / Berceau de la Confederation" in white.
* textures/signs/lane_use_riverside.png: the black lane-use sign on the
  island before the lights: two left turns, a lane that ends, a right turn.
* textures/signs/hazard_marker.png: the yellow marker under it, a black
  triangle pointing up (keep either side).
* textures/signs/mural_entrance.png: the mural on the low wall in the
  fence behind the flags, between brick piers: the Island's red shore,
  the strait and the bridge, a lighthouse, and the city's spires, in the
  muted greys, reds and blues of the real one (not a copy of it).
* textures/signs/pylon_tim_hardlys*.png and pylon_windys*.png: the two
  pole signs by the road on Grafton Street, seen looking down Grafton from
  the lights: Tim Hardly's red board with "Drive Thru" under it, and
  Windy's white board over a reader board. Our own names and lettering,
  in the chains' colours (see "brands" in data/map_config.json).

Run from the repo root:  python3 tools/make_entrance_signs.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "textures" / "signs"
FONTS = ROOT / "tools" / "fonts"

STONE = (52, 44, 40)
WHITE = (238, 236, 228)
YELLOW = (250, 196, 20)
BLACK = (18, 18, 18)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def centred(d: ImageDraw.ImageDraw, x: float, y: float, text: str, f, fill=WHITE) -> None:
    w = d.textlength(text, font=f)
    d.text((x - w / 2, y), text, font=f, fill=fill)


def welcome() -> Image.Image:
    W, H = 2048, 512
    img = Image.new("RGB", (W, H), STONE)
    d = ImageDraw.Draw(img)
    # A faint stone texture: darker courses, so the wall isn't flat paint.
    for y in range(0, H, 64):
        d.line([(0, y), (W, y)], fill=(44, 37, 34), width=2)
    # The seal: a ring with the words round it and a star in the middle.
    cx, cy, r = 260, H / 2, 190
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=8)
    d.ellipse([cx - r * 0.66, cy - r * 0.66, cx + r * 0.66, cy + r * 0.66], outline=WHITE, width=5)
    small = font("LiberationSerif-Regular.ttf", 34)
    words = "HISTORIC \u2022 HISTORIQUE \u2022 CHARLATOWN \u2022 "
    rr = r * 0.83
    widths = [d.textlength(ch, font=small) + 3 for ch in words]
    total = sum(widths)
    a = -math.pi / 2
    for ch, w in zip(words, widths):
        mid = a + (w / 2) / total * 2 * math.pi
        glyph = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glyph)
        gd.text((28 - (w - 3) / 2, 8), ch, font=small, fill=WHITE)
        glyph = glyph.rotate(-math.degrees(mid) - 90, resample=Image.BICUBIC)
        img.paste(glyph, (int(cx + math.cos(mid) * rr - 28), int(cy + math.sin(mid) * rr - 28)), glyph)
        a += w / total * 2 * math.pi
    centred(d, cx, cy - 70, "1864", font("LiberationSerif-Regular.ttf", 44))
    d.polygon([(cx, cy - 10), (cx + 18, cy + 30), (cx + 60, cy + 30), (cx + 26, cy + 54), (cx + 40, cy + 96),
               (cx, cy + 70), (cx - 40, cy + 96), (cx - 26, cy + 54), (cx - 60, cy + 30), (cx - 18, cy + 30)], fill=WHITE)
    # The words.
    x = 1260
    centred(d, x, 40, "Bienvenue / Pjila'si / Welcome", font("LiberationSans-Bold.ttf", 62))
    centred(d, x, 120, "Charlatown", font("LiberationSerif-Regular.ttf", 210))
    centred(d, x, 360, "Birthplace of Confederation", font("LiberationSerif-Regular.ttf", 60))
    centred(d, x, 428, "Berceau de la Confédération", font("LiberationSerif-Regular.ttf", 52))
    return img


def lane_use() -> Image.Image:
    W, H = 384, 512
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, W - 7, H - 7], outline=WHITE, width=6)
    lw = 16
    base = H - 50

    def head(x: float, y: float, direction: str) -> None:
        s = 26
        if direction == "up":
            d.polygon([(x - s, y + s), (x + s, y + s), (x, y - 4)], fill=WHITE)
        elif direction == "left":
            d.polygon([(x + s, y - s), (x + s, y + s), (x - 4, y)], fill=WHITE)
        else:
            d.polygon([(x - s, y - s), (x - s, y + s), (x + 4, y)], fill=WHITE)

    def turn(x: float, top: float, left: bool) -> None:
        """A stem up from the bottom that bends 90 degrees toward the turn."""
        k = -1 if left else 1
        r = 36
        pts = [(x, base), (x, top + r)]
        for i in range(1, 9):
            t = i / 8 * math.pi / 2
            pts.append((x + k * r * (1 - math.cos(t)), top + r - r * math.sin(t)))
        pts.append((x + k * (r + 12), top))
        d.line(pts, fill=WHITE, width=lw, joint="curve")
        head(x + k * (r + 14), top, "left" if left else "right")

    turn(70, 130, True)
    turn(160, 80, True)
    # The third lane: a stem into a funnel (the lane ends past the lights).
    x = 248
    d.line([(x, base), (x, 190)], fill=WHITE, width=lw)
    d.polygon([(x - 44, 90), (x + 44, 90), (x + 8, 190), (x - 8, 190)], fill=WHITE)
    turn(320, 200, False)
    return img


def hazard() -> Image.Image:
    img = Image.new("RGB", (256, 256), YELLOW)
    d = ImageDraw.Draw(img)
    d.rectangle([4, 4, 251, 251], outline=BLACK, width=6)
    d.polygon([(128, 40), (210, 210), (46, 210)], fill=BLACK)
    return img


def board(W: int, H: int, bg, text: str, fg, fnt: str, size: int, radius: int, rim=None) -> Image.Image:
    """A rounded board with one line of lettering, transparent outside."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=radius, fill=bg + (255,))
    if rim:
        d.rounded_rectangle([10, 10, W - 11, H - 11], radius=max(1, radius - 10), outline=rim + (255,), width=8)
    f = font(fnt, size)
    box = d.textbbox((0, 0), text, font=f)
    d.text(((W - (box[2] - box[0])) / 2 - box[0], (H - (box[3] - box[1])) / 2 - box[1]), text, font=f, fill=fg + (255,))
    return img


def tim_hardlys() -> tuple[Image.Image, Image.Image]:
    red = (166, 25, 46)
    top = board(1024, 512, red, "Tim Hardly's", WHITE, "Pacifico-Regular.ttf", 170, 120, WHITE)
    below = board(1024, 256, (25, 22, 22), "DRIVE THRU", WHITE, "LiberationSans-Bold.ttf", 130, 20)
    return top, below


def windys() -> tuple[Image.Image, Image.Image]:
    red = (226, 32, 61)
    top = board(1024, 512, WHITE, "Windy's", red, "Pacifico-Regular.ttf", 220, 60, red)
    reader = Image.new("RGBA", (1024, 384), (245, 245, 240, 255))
    d = ImageDraw.Draw(reader)
    d.rectangle([0, 0, 1023, 383], outline=(60, 60, 60, 255), width=14)
    f = font("LiberationSans-Bold.ttf", 110)
    for i, line in enumerate(["NO BURGERS", "BEFORE 11"]):
        w = d.textlength(line, font=f)
        d.text(((1024 - w) / 2, 40 + i * 160), line, font=f, fill=(20, 20, 20, 255))
    return top, reader


def mural() -> Image.Image:
    W, H = 1280, 256
    img = Image.new("RGB", (W, H), (196, 204, 210))
    d = ImageDraw.Draw(img)
    # Sky in bands, paler toward the horizon.
    for k in range(6):
        c = 150 + k * 12
        d.rectangle([0, k * 18, W, k * 18 + 18], fill=(c - 30, c - 12, c + 10))
    # The strait, and the bridge across it on its piers.
    d.rectangle([0, 120, W, 175], fill=(70, 100, 130))
    for x in range(0, W, 36):
        d.arc([x, 128, x + 36, 140], 180, 360, fill=(150, 175, 195), width=3)
    d.rectangle([520, 104, W, 112], fill=(80, 80, 84))
    for x in range(540, W, 70):
        d.rectangle([x, 112, x + 8, 150], fill=(80, 80, 84))
    # The red shore and the green fields above it.
    d.polygon([(0, 150), (180, 132), (420, 150), (640, 140), (W, 165), (W, H), (0, H)], fill=(160, 64, 44))
    d.polygon([(0, 190), (300, 176), (700, 196), (W, 186), (W, H), (0, H)], fill=(80, 120, 60))
    d.rectangle([0, 228, W, H], fill=(60, 58, 56))
    # A lighthouse on the point.
    d.polygon([(150, 140), (170, 140), (166, 62), (154, 62)], fill=WHITE)
    d.rectangle([150, 54, 170, 64], fill=(180, 40, 30))
    d.polygon([(148, 54), (172, 54), (160, 42)], fill=(180, 40, 30))
    # The city's spires on the far side.
    for x, h in ((360, 70), (392, 86), (424, 70), (470, 52)):
        d.rectangle([x - 8, 120 - h + 22, x + 8, 120], fill=(110, 104, 100))
        d.polygon([(x - 9, 120 - h + 22), (x + 9, 120 - h + 22), (x, 120 - h)], fill=(60, 64, 70))
    # Bold dark figures across the front, the way the real one has them.
    for i, x in enumerate(range(230, 1200, 160)):
        y = 200
        d.ellipse([x - 14, y - 74, x + 14, y - 46], fill=(30, 30, 34))
        d.polygon([(x - 22, y - 44), (x + 22, y - 44), (x + 16, y), (x - 16, y)], fill=(30, 30, 34) if i % 2 else (150, 40, 36))
        d.rectangle([x - 14, y, x - 4, y + 26], fill=(30, 30, 34))
        d.rectangle([x + 4, y, x + 14, y + 26], fill=(30, 30, 34))
    d.rectangle([0, 0, W - 1, H - 1], outline=(60, 58, 56), width=6)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    welcome().save(OUT / "welcome_charlatown.png")
    lane_use().save(OUT / "lane_use_riverside.png")
    hazard().save(OUT / "hazard_marker.png")
    mural().save(OUT / "mural_entrance.png")
    for name, (top, below) in (("tim_hardlys", tim_hardlys()), ("windys", windys())):
        top.save(OUT / f"pylon_{name}.png")
        below.save(OUT / f"pylon_{name}_lower.png")
    print("wrote the welcome sign, the lane-use sign, the hazard marker, the mural and the Grafton Street pole signs to", OUT)


if __name__ == "__main__":
    main()

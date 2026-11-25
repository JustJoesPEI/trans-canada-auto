#!/usr/bin/env python3
"""Draws Delayed & Lost Trucking's signs (docs/design.md section 6½): the
trucking company in the old McQuaid's lot on Riverside Drive, our Day &
Ross. Red and white like the real one's trucks; the name, the snail and
the lines are our own.

* textures/signs/pylon_delayed_lost.png: the top board of the pole sign by
  Riverside Drive: the snail with a parcel on its back, DELAYED & LOST,
  TRUCKING and "We'll get there."
* textures/signs/pylon_delayed_lost_lower.png: the board under it:
  DISPATCH and SURPLUS TRUCKS.
* textures/signs/delayed_lost_door.png: the logo on the yard trucks' doors
  (and on the dispatch window): the snail roundel and the name.

Run from the repo root:  python3 tools/make_delayed_lost_signs.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "textures" / "signs"
FONTS = ROOT / "tools" / "fonts"

RED = (168, 30, 36)
NAVY = (24, 36, 62)
WHITE = (244, 242, 236)
TAN = (196, 150, 92)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def centred(d: ImageDraw.ImageDraw, x: float, y: float, text: str, f, fill) -> None:
    box = d.textbbox((0, 0), text, font=f)
    d.text((x - (box[2] - box[0]) / 2 - box[0], y - box[1]), text, font=f, fill=fill)


def snail(d: ImageDraw.ImageDraw, cx: float, cy: float, s: float, fg, bg) -> None:
    """The company's snail, side on and heading right, a parcel strapped on
    its shell. (cx, cy) is the middle of the shell; s its radius."""
    w = max(2, int(s * 0.09))
    # The foot: a long low slug under the shell, the head up at the front.
    d.rounded_rectangle([cx - s * 1.3, cy + s * 0.55, cx + s * 1.55, cy + s * 0.95], radius=int(s * 0.2), fill=fg)
    d.rounded_rectangle([cx + s * 1.05, cy - s * 0.1, cx + s * 1.5, cy + s * 0.9], radius=int(s * 0.22), fill=fg)
    # Eye stalks.
    for dx, top in [(1.2, -0.75), (1.42, -0.6)]:
        d.line([(cx + s * dx, cy), (cx + s * (dx + 0.08), cy + s * top)], fill=fg, width=w)
        r = s * 0.09
        d.ellipse([cx + s * (dx + 0.08) - r, cy + s * top - r, cx + s * (dx + 0.08) + r, cy + s * top + r], fill=fg)
    # The shell, a spiral of rings.
    d.ellipse([cx - s, cy - s, cx + s, cy + s], fill=fg)
    for k, rr in enumerate([0.78, 0.55, 0.32]):
        c = bg if k % 2 == 0 else fg
        off = (1.0 - rr) * s * 0.25
        d.ellipse([cx - s * rr + off, cy - s * rr + off * 0.6, cx + s * rr + off, cy + s * rr + off * 0.6], fill=c)
    # The parcel on top, tied with string.
    px0, py0, px1, py1 = cx - s * 0.55, cy - s * 1.55, cx + s * 0.45, cy - s * 0.85
    d.rectangle([px0, py0, px1, py1], fill=TAN, outline=fg, width=w)
    d.line([((px0 + px1) / 2, py0), ((px0 + px1) / 2, py1)], fill=fg, width=w)
    d.line([(px0, (py0 + py1) / 2), (px1, (py0 + py1) / 2)], fill=fg, width=w)


def top_board() -> Image.Image:
    W, H = 1024, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=48, fill=RED + (255,))
    d.rounded_rectangle([14, 14, W - 15, H - 15], radius=38, outline=WHITE + (255,), width=8)
    snail(d, 190, 270, 105, WHITE + (255,), RED + (255,))
    big = font("Anton-Regular.ttf", 150)
    d.text((370, 40), "DELAYED", font=big, fill=WHITE + (255,))
    d.text((370, 205), "& LOST", font=big, fill=WHITE + (255,))
    small = font("LiberationSans-Bold.ttf", 46)
    d.text((372, 400), "TRUCKING", font=small, fill=WHITE + (255,))
    tag = font("Pacifico-Regular.ttf", 40)
    d.text((640, 392), "We'll get there.", font=tag, fill=WHITE + (255,))
    return img


def lower_board() -> Image.Image:
    W, H = 1024, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=28, fill=NAVY + (255,))
    f = font("LiberationSans-Bold.ttf", 78)
    centred(d, W / 2, 30, "DISPATCH", f, WHITE + (255,))
    g = font("LiberationSans-Bold.ttf", 52)
    centred(d, W / 2, 142, "SURPLUS TRUCKS FOR SALE", g, (232, 196, 80, 255))
    return img


def door() -> Image.Image:
    """Square-ish, transparent round the roundel and the words, so it sits on
    any paint: the red roundel with the snail, the name in two lines under it
    on a white plate."""
    W, H = 512, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, W - 5, H - 5], radius=36, fill=WHITE + (255,), outline=RED + (255,), width=10)
    d.ellipse([22, 28, 222, 228], fill=RED + (255,))
    snail(d, 112, 140, 52, WHITE + (255,), RED + (255,))
    f = font("Anton-Regular.ttf", 76)
    d.text((244, 28), "DELAYED", font=f, fill=RED + (255,))
    d.text((244, 124), "& LOST", font=f, fill=RED + (255,))
    return img


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    top_board().save(OUT / "pylon_delayed_lost.png")
    lower_board().save(OUT / "pylon_delayed_lost_lower.png")
    door().save(OUT / "delayed_lost_door.png")
    print("wrote", OUT / "pylon_delayed_lost.png", OUT / "pylon_delayed_lost_lower.png", OUT / "delayed_lost_door.png")

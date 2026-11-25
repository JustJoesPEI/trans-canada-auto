#!/usr/bin/env python3
"""Draws Delayed & Lost Trucking's signs (docs/design.md section 6½): the
trucking company in the old McQuaid's lot on Riverside Drive, our Day &
Ross. A spoof of the real one's look, so anyone from the Island gets it at
a glance: the name in heavy navy capitals on white, with a big orange
ampersand between the words, as on Day & Ross's trucks and trailers. The
name and the lines are our own.

* textures/signs/pylon_delayed_lost.png: the top board of the pole sign by
  Riverside Drive: DELAYED & LOST over TRUCKING, and "We'll get there."
* textures/signs/pylon_delayed_lost_lower.png: the board under it:
  DISPATCH and SURPLUS TRUCKS FOR SALE.
* textures/signs/delayed_lost_door.png: the wordmark on the yard trucks'
  doors.
* textures/signs/delayed_lost_board.png: the same on the boards over the
  dispatch and Surplus booths (their shape: 1.6 by 0.62 m).

Run from the repo root:  python3 tools/make_delayed_lost_signs.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "textures" / "signs"
FONTS = ROOT / "tools" / "fonts"

NAVY = (22, 40, 86)
ORANGE = (240, 124, 22)
WHITE = (246, 246, 242)
WORD_FONT = "LiberationSans-Bold.ttf"


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def text_w(d: ImageDraw.ImageDraw, text: str, f) -> float:
    box = d.textbbox((0, 0), text, font=f)
    return box[2] - box[0]


def wordmark(d: ImageDraw.ImageDraw, cx: float, top: float, size: int, max_w: float) -> float:
    """DELAYED & LOST on one line, centred on cx: navy words, a bigger orange
    ampersand. Shrinks to fit max_w. Returns the height used."""
    while True:
        f = font(WORD_FONT, size)
        amp = font(WORD_FONT, int(size * 1.35))
        gap = size * 0.18
        parts = [("DELAYED", f, NAVY), ("&", amp, ORANGE), ("LOST", f, NAVY)]
        width = sum(text_w(d, t, ff) for t, ff, _ in parts) + gap * 2
        if width <= max_w or size < 20:
            break
        size -= 4
    x = cx - width / 2
    # Line the words up on one baseline; the ampersand stands a little taller.
    base = top + size * 1.05
    for t, ff, col in parts:
        box = d.textbbox((0, 0), t, font=ff, anchor="ls")
        d.text((x - box[0], base), t, font=ff, fill=col + (255,), anchor="ls")
        x += text_w(d, t, ff) + gap
    return base - top + size * 0.1


def top_board() -> Image.Image:
    W, H = 1024, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=40, fill=WHITE + (255,))
    d.rounded_rectangle([12, 12, W - 13, H - 13], radius=30, outline=NAVY + (255,), width=10)
    h = wordmark(d, W / 2, 95, 170, W - 90)
    # A navy band under the name with TRUCKING in it, as on the trailers.
    y0 = 95 + h + 40
    d.rectangle([12, y0, W - 13, y0 + 100], fill=NAVY + (255,))
    f = font(WORD_FONT, 64)
    d.text((W / 2, y0 + 50), "T R U C K I N G", font=f, fill=WHITE + (255,), anchor="mm")
    tag = font("LiberationSans-Bold.ttf", 48)
    d.text((W / 2, y0 + 150), "We'll get there.", font=tag, fill=ORANGE + (255,), anchor="mm")
    return img


def lower_board() -> Image.Image:
    W, H = 1024, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=28, fill=NAVY + (255,))
    d.text((W / 2, 78), "DISPATCH", font=font(WORD_FONT, 84), fill=WHITE + (255,), anchor="mm")
    d.text((W / 2, 182), "SURPLUS TRUCKS FOR SALE", font=font(WORD_FONT, 52), fill=ORANGE + (255,), anchor="mm")
    return img


def door() -> Image.Image:
    """The wordmark on a white plate with a thin navy edge (it sits on any
    paint), an orange rule under it."""
    W, H = 512, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, W - 5, H - 5], radius=28, fill=WHITE + (255,), outline=NAVY + (255,), width=8)
    h = wordmark(d, W / 2, 50, 92, W - 50)
    d.rectangle([40, 50 + h + 22, W - 41, 50 + h + 34], fill=ORANGE + (255,))
    d.text((W / 2, 50 + h + 66), "TRUCKING", font=font(WORD_FONT, 34), fill=NAVY + (255,), anchor="mm")
    return img


def booth_board() -> Image.Image:
    """The booths' boards: white edge to edge, so none of the post's own
    board shows round it, the wordmark over the navy band."""
    W, H = 1024, 400
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=NAVY, width=14)
    h = wordmark(d, W / 2, 60, 130, W - 80)
    d.rectangle([14, 60 + h + 40, W - 15, H - 15], fill=NAVY)
    d.text((W / 2, (60 + h + 40 + H - 15) / 2), "T R U C K I N G", font=font(WORD_FONT, 60), fill=WHITE, anchor="mm")
    return img


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    top_board().save(OUT / "pylon_delayed_lost.png")
    lower_board().save(OUT / "pylon_delayed_lost_lower.png")
    door().save(OUT / "delayed_lost_door.png")
    booth_board().save(OUT / "delayed_lost_board.png")
    print("wrote the Delayed & Lost signs in", OUT)

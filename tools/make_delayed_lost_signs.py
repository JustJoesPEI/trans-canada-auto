#!/usr/bin/env python3
"""Draws Delayed & Lost Trucking's signs (docs/design.md section 6½): the
trucking company in the old McQuaid's lot on Riverside Drive, our Day &
Ross. A spoof of the real one's look (from Joe's photo of their trucks,
2026-11-25), so anyone from the Island gets it at a glance: on white, the
name stacked in two lines of heavy black condensed capitals, leaning and
tilted up to the right, a small orange ampersand tucked in after the first
word, and a run of slanted black and orange blocks. The name and the lines
are our own.

* textures/signs/pylon_delayed_lost.png: the top board of the pole sign by
  Riverside Drive: the stacked name, the blocks, "We'll get there."
* textures/signs/pylon_delayed_lost_lower.png: the board under it:
  DISPATCH and SURPLUS TRUCKS FOR SALE.
* textures/signs/delayed_lost_door.png: the stacked name on the trucks'
  doors, on clear (it goes on white cabs, as theirs does).
* textures/signs/delayed_lost_board.png: the boards over the dispatch and
  Surplus booths (their shape: 1.6 by 0.62 m).

Run from the repo root:  python3 tools/make_delayed_lost_signs.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "textures" / "signs"
FONTS = ROOT / "tools" / "fonts"

BLACK = (22, 22, 24)
ORANGE = (240, 118, 40)
WHITE = (246, 246, 243)
WORD_FONT = "Anton-Regular.ttf"
# The name leans (italic shear) and tilts up to the right, as theirs does.
LEAN = 0.12
TILT = 9.0


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def stacked_name(size: int) -> Image.Image:
    """DELAYED over LOST, black, with a small orange & up after DELAYED,
    leaning and tilted; on clear, cropped to the ink."""
    f = font(WORD_FONT, size)
    amp = font(WORD_FONT, int(size * 0.62))
    pad = size
    layer = Image.new("RGBA", (size * 6 + pad * 2, size * 3 + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    top_w = d.textlength("DELAYED", font=f)
    x0 = pad
    d.text((x0, pad), "DELAYED", font=f, fill=BLACK + (255,))
    d.text((x0 + top_w + size * 0.04, pad - size * 0.02), "&", font=amp, fill=ORANGE + (255,))
    # The second line tucked up close under the first, starting a little in.
    d.text((x0 + size * 0.25, pad + size * 1.12), "LOST", font=f, fill=BLACK + (255,))
    # Lean: shear x by y (the top leans right).
    w, h = layer.size
    layer = layer.transform((w + int(h * LEAN), h), Image.AFFINE, (1, LEAN, -h * LEAN, 0, 1, 0), resample=Image.BICUBIC)
    layer = layer.rotate(TILT, resample=Image.BICUBIC, expand=True)
    return layer.crop(layer.getbbox())


def blocks(d: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float) -> None:
    """The run of slanted blocks: two rows of parallelograms, black and
    orange in turn, stepping up to the right."""
    n = 4
    cw = w / n
    slant = cw * 0.3
    body = cw * 0.66
    for row in range(2):
        for i in range(n):
            col = (BLACK if (i + row) % 2 == 0 else ORANGE) + (255,)
            rise = (i + row) * h * 0.07
            bx = x + i * cw + row * cw * 0.15
            by = y + row * h / 2 - rise
            d.polygon([(bx + slant, by), (bx + body + slant, by), (bx + body, by + h / 2 - 6), (bx, by + h / 2 - 6)], fill=col)


def paste_fit(img: Image.Image, mark: Image.Image, box: tuple) -> None:
    """Pastes `mark` scaled to fit inside box (x0, y0, x1, y1), centred."""
    x0, y0, x1, y1 = box
    s = min((x1 - x0) / mark.width, (y1 - y0) / mark.height)
    m = mark.resize((int(mark.width * s), int(mark.height * s)), Image.LANCZOS)
    img.alpha_composite(m, (int(x0 + (x1 - x0 - m.width) / 2), int(y0 + (y1 - y0 - m.height) / 2)))


def top_board() -> Image.Image:
    W, H = 1024, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=36, fill=WHITE + (255,))
    d.rounded_rectangle([10, 10, W - 11, H - 11], radius=28, outline=BLACK + (255,), width=8)
    paste_fit(img, stacked_name(200), (50, 40, 600, 420))
    blocks(d, 640, 150, 320, 190)
    d.text((W / 2, 462), "TRUCKING  ·  We'll get there.", font=font("LiberationSans-Bold.ttf", 40), fill=BLACK + (255,), anchor="mm")
    return img


def lower_board() -> Image.Image:
    W, H = 1024, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=28, fill=BLACK + (255,))
    d.text((W / 2, 80), "DISPATCH", font=font(WORD_FONT, 96), fill=WHITE + (255,), anchor="mm")
    d.text((W / 2, 188), "SURPLUS TRUCKS FOR SALE", font=font(WORD_FONT, 60), fill=ORANGE + (255,), anchor="mm")
    return img


def door() -> Image.Image:
    """The stacked name on clear, for white cabs (drawn blended, so the
    letters' edges stay smooth)."""
    W, H = 512, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    paste_fit(img, stacked_name(160), (60, 8, W - 60, H - 8))
    return img


def booth_board() -> Image.Image:
    """The booths' boards: white edge to edge, so none of the post's own
    board shows round it: the name and the blocks."""
    W, H = 1024, 400
    img = Image.new("RGBA", (W, H), WHITE + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=BLACK + (255,), width=12)
    paste_fit(img, stacked_name(200), (40, 30, 600, H - 30))
    blocks(d, 640, 110, 320, 190)
    return img.convert("RGB")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    top_board().save(OUT / "pylon_delayed_lost.png")
    lower_board().save(OUT / "pylon_delayed_lost_lower.png")
    door().save(OUT / "delayed_lost_door.png")
    booth_board().save(OUT / "delayed_lost_board.png")
    print("wrote the Delayed & Lost signs in", OUT)

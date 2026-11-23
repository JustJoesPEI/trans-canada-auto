#!/usr/bin/env python3
"""Draw Trans-Canada Auto's branding: the TCA shield, the loading screen,
the game icon and the itch.io page images.

Everything is drawn here from shapes and the free DejaVu Sans font, so it can be
changed and redrawn any time. Run from the repository root:

    python3 tools/make_branding.py

Needs Pillow and the DejaVu fonts (on Ubuntu: fonts-dejavu-core). Writes:
    branding/logo.png          the shield on its own, transparent, 1024 x 1152
    branding/icon.png          the shield for the game's window icon, 256 x 256
    branding/splash.png        the loading screen, 1920 x 1080
    branding/title.png         the shield and name for the title menu, transparent
    branding/itch/cover.png    itch.io cover image, 630 x 500
    branding/itch/banner.png   itch.io page banner, 960 x 300
    branding/itch/background.png  itch.io page background, 1920 x 1080
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "branding")
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"

# The palette: highway-sign green and white, with red clay for PEI's map.
GREEN = (31, 92, 61)
GREEN_DARK = (18, 54, 36)
WHITE = (250, 250, 246)
CLAY = (180, 71, 44)
CREAM = (243, 234, 216)
INK = (20, 35, 27)


def font(size, bold=True):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def shield_outline(w, h, inset=0.0):
    """Points round our route shield: a flat top with notched corners,
    straight sides, and a rounded point at the bottom. Symmetrical: the
    right half is worked out and mirrored."""
    import math
    n = inset
    notch = 0.12 * w
    cx = w / 2
    right = [(w - notch - n, n), (w - n, notch + n), (w - n, 0.58 * h)]
    # The bottom right: a curve from the side down to a soft point.
    for i in range(1, 25):
        t = i / 24.0
        x = (w - n) + (cx - (w - n)) * t
        y = 0.58 * h + (h - n - 0.58 * h) * math.sin(t * math.pi / 2) ** 1.4
        right.append((x, y))
    left = [(w - x, y) for (x, y) in reversed(right[:-1])]
    return right + left


def draw_shield(size_w, map_name="RED CLAY"):
    """The TCA shield at width size_w, on a transparent image."""
    w = size_w
    h = int(size_w * 1.125)
    s = 4  # draw big and shrink, for smooth edges
    big = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    W, H = w * s, h * s
    d.polygon(shield_outline(W, H), fill=WHITE)
    d.polygon(shield_outline(W, H, inset=0.035 * W), fill=GREEN)
    # Red clay band across the top with TRANS-CANADA.
    band = shield_outline(W, H, inset=0.075 * W)
    top = min(p[1] for p in band)
    band_h = 0.2 * H
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(band, fill=255)
    clay = Image.new("RGBA", (W, H), CLAY + (255,))
    strip = Image.new("L", (W, H), 0)
    ImageDraw.Draw(strip).rectangle([0, 0, W, top + band_h], fill=255)
    from PIL import ImageChops
    big.paste(clay, (0, 0), ImageChops.multiply(mask, strip))
    d = ImageDraw.Draw(big)
    _centred(d, "TRANS-CANADA", W / 2, top + band_h * 0.52, font(int(0.105 * W)), WHITE, max_w=0.66 * W)
    # The big TCA.
    _centred(d, "TCA", W / 2, 0.5 * H, font(int(0.42 * W)), WHITE, max_w=0.72 * W)
    # A thin white rule and AUTO under it.
    d.rectangle([0.22 * W, 0.70 * H, 0.78 * W, 0.70 * H + 0.012 * W], fill=WHITE)
    _centred(d, "AUTO", W / 2, 0.775 * H, font(int(0.12 * W)), WHITE, max_w=0.5 * W)
    if map_name:
        _centred(d, map_name, W / 2, 0.865 * H, font(int(0.06 * W)), CREAM, max_w=0.36 * W)
    return big.resize((w, h), Image.LANCZOS)


def _fit(d, text, f, max_w):
    """The same font, smaller if needed, so text fits in max_w."""
    size = f.size
    while size > 8 and d.textlength(text, font=f) > max_w:
        size -= 2
        f = ImageFont.truetype(f.path, size)
    return f


def _centred(d, text, x, y, f, fill, max_w=None):
    if max_w:
        f = _fit(d, text, f, max_w)
    box = d.textbbox((0, 0), text, font=f)
    d.text((x - (box[0] + box[2]) / 2, y - (box[1] + box[3]) / 2), text, font=f, fill=fill)


def road_backdrop(w, h):
    """A dark green field with a road running up into the distance and its
    dashed centre line, for the loading screen."""
    img = Image.new("RGB", (w, h), GREEN_DARK)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        c = tuple(int(GREEN_DARK[i] * (1 - t * 0.5) + GREEN[i] * t * 0.5) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    horizon = int(h * 0.74)
    d.polygon([(w * 0.5 - 6, horizon), (w * 0.5 + 6, horizon), (w * 0.78, h), (w * 0.22, h)], fill=(42, 44, 46))
    # Gravel shoulders in red clay.
    d.polygon([(w * 0.5 - 6, horizon), (w * 0.5 - 2, horizon), (w * 0.22, h), (w * 0.17, h)], fill=CLAY)
    d.polygon([(w * 0.5 + 2, horizon), (w * 0.5 + 6, horizon), (w * 0.83, h), (w * 0.78, h)], fill=CLAY)
    # Dashes, getting longer toward the viewer.
    y = horizon + 6
    k = 0
    while y < h:
        t = (y - horizon) / (h - horizon)
        step = 6 + t * 90
        if k % 2 == 0:
            y2 = min(h, y + step)
            t2 = (y2 - horizon) / (h - horizon)
            d.polygon([(w * 0.5 - 1 - t * 6, y), (w * 0.5 + 1 + t * 6, y), (w * 0.5 + 1 + t2 * 6, y2), (w * 0.5 - 1 - t2 * 6, y2)], fill=(232, 190, 60))
        y += step
        k += 1
    return img


def splash():
    w, h = 1920, 1080
    img = road_backdrop(w, h)
    shield = draw_shield(420)
    img.paste(shield, (w // 2 - 210, 90), shield)
    d = ImageDraw.Draw(img)
    _centred(d, "TRANS-CANADA AUTO", w / 2, 640, font(96), WHITE)
    _centred(d, "Red Clay  ·  Charlatown, Prince Edward Island", w / 2, 715, font(40, bold=False), CREAM)
    return img


def title_art():
    """The shield beside the name, for the title menu (transparent)."""
    w, h = 1500, 440
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shield = draw_shield(360, map_name=None)
    img.paste(shield, (0, 20), shield)
    d = ImageDraw.Draw(img)
    big = _fit(d, "TRANS-CANADA", font(120), 1060)
    d.text((410, 70), "TRANS-CANADA", font=big, fill=WHITE)
    d.text((410, 200), "AUTO", font=big, fill=WHITE)
    d.text((414, 340), "RED CLAY  ·  CHARLATOWN, PEI", font=font(46, bold=False), fill=CREAM)
    return img


def cover():
    """itch.io cover, 630 x 500: an aerial view of the city, darkened, with the shield and name."""
    w, h = 630, 500
    shot = Image.open(os.path.join(OUT, "screens", "overview.jpg")).convert("RGB")
    shot = _fill(shot, w, h)
    shade = Image.new("RGB", (w, h), GREEN_DARK)
    img = Image.blend(shot, shade, 0.45)
    shield = draw_shield(200)
    img.paste(shield, (w // 2 - 100, 40), shield)
    d = ImageDraw.Draw(img)
    _centred(d, "TRANS-CANADA AUTO", w / 2, 320, font(48), WHITE)
    _centred(d, "Red Clay · Charlatown, PEI", w / 2, 362, font(24, bold=False), CREAM)
    _centred(d, "Drive a whole real city", w / 2, 450, font(26), WHITE)
    return img


def banner():
    w, h = 960, 300
    shot = _fill(Image.open(os.path.join(OUT, "screens", "riverside.jpg")).convert("RGB"), w, h)
    img = Image.blend(shot, Image.new("RGB", (w, h), GREEN_DARK), 0.55)
    shield = draw_shield(190, map_name=None)
    img.paste(shield, (40, 46), shield)
    d = ImageDraw.Draw(img)
    d.text((260, 80), "TRANS-CANADA AUTO", font=_fit(d, "TRANS-CANADA AUTO", font(70), 670), fill=WHITE)
    sub = "Red Clay \u00b7 Charlatown, Prince Edward Island"
    d.text((264, 170), sub, font=_fit(d, sub, font(30, bold=False), 670), fill=CREAM)
    return img


def background():
    w, h = 1920, 1080
    img = road_backdrop(w, h).filter(ImageFilter.GaussianBlur(2))
    return img


def _fill(img, w, h):
    """Scale and crop an image to fill w x h."""
    s = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * s + 0.5), int(img.height * s + 0.5)), Image.LANCZOS)
    x = (img.width - w) // 2
    y = (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def main():
    os.makedirs(os.path.join(OUT, "itch"), exist_ok=True)
    draw_shield(1024).save(os.path.join(OUT, "logo.png"))
    icon = draw_shield(228, map_name=None)
    sq = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    sq.paste(icon, ((256 - icon.width) // 2, (256 - icon.height) // 2), icon)
    sq.save(os.path.join(OUT, "icon.png"))
    splash().save(os.path.join(OUT, "splash.png"))
    title_art().save(os.path.join(OUT, "title.png"))
    cover().save(os.path.join(OUT, "itch", "cover.png"))
    banner().save(os.path.join(OUT, "itch", "banner.png"))
    background().save(os.path.join(OUT, "itch", "background.png"))
    print("wrote branding/ (logo, icon, splash, title) and branding/itch/ (cover, banner, background)")


if __name__ == "__main__":
    main()

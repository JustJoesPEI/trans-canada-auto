#!/usr/bin/env python3
"""Draw Trans-Canada Auto's branding: the wordmark, the loading screens, the
game icon and the itch.io page images.

The look is a loving send-up of the big crime-sandbox games. Each map is an
edition, titled the way their editions are, with the edition's name the
big thing; ours is stamped on a licence plate: green on white like the
Island's, "TRANS-CANADA AUTO" where the province goes, "SAND BAR" in the
middle, a made-up province along the bottom, and TCA on the renewal
sticker. The loading screens are tilted comic-book panels over a
screen-printed sunset. The panels are the game's own screenshots
(branding/screens/), inked and halftoned here, with captions in our own voice.

Everything is drawn from the screenshots, shapes and the free fonts in
tools/fonts/, so it can be changed and redrawn any time. Run from the
repository root:

    python3 tools/make_branding.py

Needs Pillow and NumPy. Writes:
    branding/logo.png             the series name and leaf on their own, transparent
    branding/logo_edition.png     the edition logo, transparent
    branding/title.png            the edition logo for the title menu, transparent
    branding/icon.png             the game's window icon, 256 x 256
    branding/splash.png           the boot splash: the first loading screen
    branding/loading/NN.jpg       the loading screens, 1920 x 1080, shown in turn
    branding/itch/cover.png       itch.io cover image, 630 x 500
    branding/itch/banner.png      itch.io page banner, 960 x 300
    branding/itch/background.png  itch.io page background, 1920 x 1080
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "branding")
SCREENS = os.path.join(OUT, "screens")
ADS = os.path.join(ROOT, "textures", "ads")
FONTS = os.path.join(ROOT, "tools", "fonts")

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
INK = (22, 16, 28)
LEAF_RED = (213, 43, 30)
CLAY = (196, 72, 44)
CREAM = (250, 244, 230)
YELLOW = (255, 214, 0)

# The Canadian maple leaf (as in make_flags.py), right half from the top point
# down to the stem on a 100 x 100 box, mirrored for the left half.
LEAF_RIGHT = [(50, 0), (57, 13), (65, 9), (62, 36), (74, 22), (77, 30), (90, 27), (86, 41),
              (93, 45), (72, 62), (75, 71), (54, 68), (55, 92)]
LEAF = LEAF_RIGHT + [(100 - x, y) for x, y in reversed(LEAF_RIGHT[1:])]

# Sky ramps for the panels, top of the sky to the horizon.
SUNSET = [(0.0, (38, 52, 110)), (0.35, (120, 70, 140)), (0.62, (236, 104, 86)),
          (0.85, (252, 168, 82)), (1.0, (255, 214, 140))]
DUSK = [(0.0, (16, 22, 60)), (0.4, (52, 44, 110)), (0.7, (170, 70, 120)),
        (0.9, (240, 120, 96)), (1.0, (255, 170, 110))]
MORNING = [(0.0, (60, 130, 190)), (0.45, (120, 180, 214)), (0.75, (246, 200, 160)),
           (1.0, (255, 226, 180))]


def font(name, size):
    files = {"anton": "Anton-Regular.ttf",
             "bebas": "BebasNeue-Regular.ttf", "plate": "Graduate-Regular.ttf"}
    return ImageFont.truetype(os.path.join(FONTS, files[name]), int(size))


# ---------------------------------------------------------------- helpers

def _shadow(layer, off, blur, alpha=170):
    """A soft drop shadow of an RGBA layer, the same size as it."""
    a = layer.split()[3].point(lambda v: v * alpha // 255)
    sh = Image.new("RGBA", layer.size, BLACK + (0,))
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(sh, off, sh)
    return out


def _with_shadow(img, layer, off, blur, alpha=170):
    img.alpha_composite(_shadow(layer, off, blur, alpha))
    img.alpha_composite(layer)


def _outlined(layer, widths, colours):
    """An RGBA layer given solid outlines, innermost first (widths in px)."""
    a = layer.split()[3]
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    masks = []
    total = 0
    for w in widths:
        total += w
        # grow the shape by blurring and cutting off low: round, and fast
        grown = a.filter(ImageFilter.GaussianBlur(total / 2)).point(lambda v: 255 if v > 8 else 0)
        masks.append(grown.filter(ImageFilter.GaussianBlur(0.8)))
    for m, c in reversed(list(zip(masks, colours))):
        out.paste(Image.new("RGBA", layer.size, c + (255,)), (0, 0), m)
    out.alpha_composite(layer)
    return out


def _ramp(t, stops):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / max(1e-6, t1 - t0)
            return tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
    return stops[-1][1]


def _fill(img, w, h, focus=(0.5, 0.5)):
    """Scale and crop an image to fill w x h, keeping the focus point in view."""
    s = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * s + 0.5), int(img.height * s + 0.5)), Image.LANCZOS)
    x = int((img.width - w) * focus[0])
    y = int((img.height - h) * focus[1])
    return img.crop((x, y, x + w, y + h))


def _screen(name):
    """A screenshot without the place name and map credit burned into it."""
    im = Image.open(os.path.join(SCREENS, name + ".jpg")).convert("RGB")
    return im.crop((0, 60, im.width, im.height - 50))


# ---------------------------------------------------------------- wordmark

def _leaf_layer(size, x, y, s, fill=LEAF_RED, line=WHITE, line_w=0.09, outer=BLACK, outer_w=0.16):
    """A maple leaf s pixels across at (x, y), with a white then black edge."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = [(x + px / 100 * s, y + py / 100 * s) for px, py in LEAF]
    if outer_w:
        d.line(pts + [pts[0]], fill=outer, width=int(s * outer_w), joint="curve")
        d.polygon(pts, fill=outer)
    if line_w:
        d.line(pts + [pts[0]], fill=line, width=int(s * line_w), joint="curve")
    d.polygon(pts, fill=fill)
    return layer


# The edition this build is, stamped on its licence plate: the name big in
# the middle, and a made-up province along the bottom (same as the
# businesses in town, nothing real). A new map is a new edition, on its own
# plate: change these and redraw.
EDITION = "SAND BAR"
EDITION_LINE = "PRINCE EDDIE ISLAND"
# The plate's ink: the Island's plates are green on white.
PLATE_INK = (0, 104, 62)
PLATE_WHITE = (247, 247, 242)

_LOGOS = {}


def _text_mask(text, f, spacing=0):
    """White-on-black mask of text, cropped tight; spacing adds letter space."""
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    widths = [d.textlength(c, font=f) for c in text]
    w = int(sum(widths) + spacing * len(text)) + 60
    h = d.textbbox((0, 0), text, font=f)[3] + 60
    mk = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mk)
    if spacing:
        x = 30
        for c, cw in zip(text, widths):
            md.text((x, 30), c, font=f, fill=255)
            x += cw + spacing
    else:
        md.text((30, 30), text, font=f, fill=255)
    return mk.crop(mk.getbbox())


def _pad(layer, p):
    out = Image.new("RGBA", (layer.width + 2 * p, layer.height + 2 * p), (0, 0, 0, 0))
    out.alpha_composite(layer, (p, p))
    return out


def _stack(layers, gap=0):
    """Layers one under the other, centred."""
    w = max(l.width for l in layers)
    h = sum(l.height for l in layers) + gap * (len(layers) - 1)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for l in layers:
        out.alpha_composite(l, ((w - l.width) // 2, y))
        y += l.height + gap
    return out


def _series_name(size):
    """'trans-canada auto' in white lowercase with a black edge. The T, C and A
    are maple-leaf red: TCA, if you're looking for it."""
    f = font("anton", size)
    text = "trans-canada auto"
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    w = int(d.textlength(text, font=f)) + 60
    h = d.textbbox((0, 0), text, font=f)[3] + 60
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.text((30, 30), text, font=f, fill=WHITE)
    for i in (0, text.index("canada"), text.index("auto")):
        ld.text((30 + d.textlength(text[:i], font=f), 30), text[i], font=f, fill=LEAF_RED)
    layer = layer.crop(layer.getbbox())
    return _outlined(_pad(layer, int(size * 0.12)), [int(size * 0.075)], [BLACK])


def _draw_logo(edition):
    """The logo. For an edition, its licence plate: the series name where the
    province goes, the edition's name stamped big, the made-up province
    along the bottom. With no edition, the series name and a maple leaf on
    their own. Transparent."""
    if not edition:
        name = _series_name(220)
        leaf = _leaf_layer((int(name.height * 1.3), int(name.height * 1.3)), 10, 10, name.height * 1.1)
        out = Image.new("RGBA", (name.width + leaf.width, max(name.height, leaf.height)), (0, 0, 0, 0))
        out.alpha_composite(name, (0, (out.height - name.height) // 2))
        out.alpha_composite(leaf, (name.width - 20, 0))
        return _with_drop(out)
    return _with_drop(_plate(edition).rotate(-4, resample=Image.BICUBIC, expand=True))


def _stamp(plate, mask, x, y, ink, depth=5):
    """Pressed-metal letters: a light edge up and left, a dark one down and
    right, then the ink."""
    plate.paste(Image.new("RGBA", mask.size, (255, 255, 255, 255)), (x - depth // 2, y - depth // 2), mask)
    plate.paste(Image.new("RGBA", mask.size, (120, 120, 116, 255)), (x + depth, y + depth), mask)
    plate.paste(Image.new("RGBA", mask.size, ink + (255,)), (x, y), mask)


def _plate(edition):
    """The edition's licence plate, 1300 x 650, flat (tilt it after)."""
    W, H = 1300, 650
    plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shape = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, W - 1, H - 1], radius=56, fill=255)
    face = Image.new("RGB", (W, H))
    fd = ImageDraw.Draw(face)
    for y in range(H):
        fd.line([(0, y), (W, y)], fill=_ramp(y / H, [(0, (252, 252, 248)), (1, (232, 232, 226))]))
    # red clay road dust, thickest along the bottom edge, flecked
    rng = np.random.default_rng(7)
    t = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
    dust = np.clip((t - 0.62) / 0.38, 0, 1) ** 1.6 * 0.55
    dust *= 0.65 + 0.35 * rng.random((H, W))
    dust_img = Image.fromarray((dust * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    face.paste((176, 78, 50), (0, 0, W, H), dust_img)
    plate.paste(face, (0, 0), shape)
    d = ImageDraw.Draw(plate)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=56, outline=(40, 44, 40), width=8)
    # the pressed rim
    d.rounded_rectangle([24, 24, W - 25, H - 25], radius=40, outline=(255, 255, 255), width=4)
    d.rounded_rectangle([28, 28, W - 21, H - 21], radius=40, outline=(150, 150, 146), width=3)
    d.rounded_rectangle([26, 26, W - 23, H - 23], radius=40, outline=PLATE_INK, width=6)
    # bolt slots
    for x in (120, W - 120):
        for y in (80, H - 80):
            d.rounded_rectangle([x - 34, y - 13, x + 34, y + 13], radius=13, fill=(70, 72, 70), outline=(30, 30, 30), width=3)
            d.ellipse([x - 13, y - 13, x + 13, y + 13], fill=(196, 196, 192), outline=(90, 90, 90), width=3)
    # the series name where the province goes, with a leaf
    top = _text_mask("TRANS-CANADA AUTO", font("bebas", 92), spacing=12)
    tx = (W - top.width) // 2 - 20
    plate.paste(Image.new("RGBA", top.size, PLATE_INK + (255,)), (tx, 50), top)
    plate.alpha_composite(_leaf_layer((W, H), tx + top.width + 14, 46, 72, line_w=0.0, outer_w=0.0))
    # the edition, stamped
    big = _text_mask(edition, font("plate", 250))
    if big.width > W - 170:
        big = big.resize((W - 170, big.height), Image.LANCZOS)
    _stamp(plate, big, (W - big.width) // 2, 190, PLATE_INK)
    # the made-up province along the bottom
    low = _text_mask(EDITION_LINE, font("bebas", 66), spacing=10)
    plate.paste(Image.new("RGBA", low.size, PLATE_INK + (255,)), ((W - low.width) // 2 - 40, H - 118), low)
    # the renewal sticker in the corner: TCA, and the year
    st = Image.new("RGBA", (150, 96), (0, 0, 0, 0))
    sd = ImageDraw.Draw(st)
    sd.rounded_rectangle([0, 0, 149, 95], radius=10, fill=(255, 200, 30), outline=(150, 110, 0), width=3)
    sf = font("anton", 46)
    sd.text((14, 6), "TCA", font=sf, fill=(20, 20, 20))
    sd.text((96, 14), "26", font=font("bebas", 40), fill=(20, 20, 20))
    sd.line([(14, 66), (136, 66)], fill=(20, 20, 20), width=2)
    sd.text((14, 68), "VALID", font=font("bebas", 22), fill=(20, 20, 20))
    st = st.resize((126, 81), Image.LANCZOS)
    plate.alpha_composite(st.rotate(3, resample=Image.BICUBIC, expand=True), (W - 300, H - 128))
    return plate


def _with_drop(layer):
    layer = _pad(layer, 40)
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.alpha_composite(_shadow(layer, (10, 14), 12, 190))
    out.alpha_composite(layer)
    return out.crop(out.getbbox())


def wordmark(width, edition=EDITION):
    """The logo at the given width (drawn once, then scaled). Pass
    edition=None for the series name on its own."""
    if edition not in _LOGOS:
        _LOGOS[edition] = _draw_logo(edition)
    img = _LOGOS[edition]
    return img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)


def icon():
    """The window icon: 'tca' in the black box with the leaf in its corner."""
    S = 4
    n = 256 * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    box = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(box)
    m = 10 * S
    d.rounded_rectangle([m, m, n - m, n - m], radius=34 * S, fill=(8, 8, 8, 255), outline=WHITE, width=9 * S)
    f = font("anton", 150 * S)
    bb = d.textbbox((0, 0), "tca", font=f)
    d.text(((n - (bb[2] + bb[0])) / 2, n * 0.6 - (bb[3] + bb[1]) / 2), "tca", font=f, fill=WHITE)
    img.alpha_composite(box)
    img.alpha_composite(_leaf_layer((n, n), n * 0.36, n * 0.07, n * 0.28, line_w=0.0, outer_w=0.0))
    return img.resize((256, 256), Image.LANCZOS)


# ---------------------------------------------------------------- comic panels

def _sky_mask(img):
    """Where the sky is: blue-ish pixels reached straight down from the top."""
    a = np.asarray(img).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    sky = (b > r + 12) & (b > 120) & (b >= g - 5)
    sky = Image.fromarray((sky * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    run = np.cumprod(np.asarray(sky) > 0, axis=0).astype(np.uint8) * 255
    return Image.fromarray(run).filter(ImageFilter.GaussianBlur(1.2))


def _sky(w, h, horizon, stops, sun):
    """A banded, screen-printed sky with a striped sun sinking at the horizon."""
    sky = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(sky)
    bands = 9
    for y in range(h):
        t = round(min(1.0, y / max(1, horizon)) * bands) / bands
        d.line([(0, y), (w, y)], fill=_ramp(t, stops))
    if sun:
        sx, r = sun[0] * w, sun[1] * h
        sy = horizon - r * 0.35
        disc = Image.new("L", (w, h), 0)
        dd = ImageDraw.Draw(disc)
        dd.ellipse([sx - r, sy - r, sx + r, sy + r], fill=255)
        # the stripes across the lower half, thicker toward the bottom
        y, k = sy, 0
        while y < sy + r:
            gapw = 2 + k * 2.2 * (r / 120)
            dd.rectangle([sx - r, y, sx + r, y + gapw], fill=0)
            y += gapw + r * 0.12
            k += 1
        top, bottom = (255, 236, 120), (255, 92, 70)
        grad = Image.new("RGB", (w, h))
        gd = ImageDraw.Draw(grad)
        for yy in range(int(sy - r), int(sy + r) + 1):
            gd.line([(0, yy), (w, yy)], fill=_ramp((yy - (sy - r)) / (2 * r), [(0, top), (1, bottom)]))
        sky.paste(grad, (0, 0), disc)
    return sky


def comic(img, stops=SUNSET, sun=None, colors=28, dot=8):
    """A screenshot as a comic panel: the sky swapped for a printed sunset,
    the colours flattened, ink round the shapes and halftone in the shadows."""
    img = img.convert("RGB")
    w, h = img.size
    m = _sky_mask(img)
    rows = np.asarray(m).sum(axis=1) / 255
    clear = np.nonzero(rows < w * 0.02)[0]
    horizon = int(clear[0]) if len(clear) else h // 2
    sky = _sky(w, h, max(horizon, h // 4), stops, sun)
    src = img.filter(ImageFilter.MedianFilter(7)).filter(ImageFilter.MedianFilter(5))
    src = ImageEnhance.Color(src).enhance(1.5)
    src = ImageEnhance.Contrast(src).enhance(1.15)
    a = np.asarray(src).astype(np.float32) * np.array([1.06, 0.99, 0.9]) + np.array([8, 0, -4])
    src = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    src = Image.composite(sky, src, m)
    flat = src.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    flat = flat.filter(ImageFilter.ModeFilter(7))
    # Ink: the edges of the scene (none inside the sky), and the skyline.
    g = ImageOps.grayscale(img.filter(ImageFilter.MedianFilter(5)))
    e = g.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 20 else 0)
    e = e.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.0)).point(lambda v: 255 if v > 100 else 0)
    ink = np.asarray(e).astype(np.float32) * (1 - np.asarray(m).astype(np.float32) / 255)
    ink += (np.asarray(m.filter(ImageFilter.FIND_EDGES)) > 40) * 255.0
    out = flat.copy()
    out.paste(INK, (0, 0, w, h), Image.fromarray(np.clip(ink, 0, 255).astype(np.uint8)))
    # Halftone dots in the shadows, on a 45 degree screen.
    lum = np.asarray(ImageOps.grayscale(flat)).astype(np.float32) / 255
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(((xx + yy) % dot) - dot / 2, ((xx - yy) % dot) - dot / 2)
    dark = np.clip((0.5 - lum) / 0.5, 0, 1)
    out.paste((30, 20, 50), (0, 0, w, h), Image.fromarray(((r < dark * dot * 0.6) * 110).astype(np.uint8)))
    return out


def _caption(text, size, bg=YELLOW, fg=BLACK, angle=0.0, pad=0.32):
    """A comic caption box: Anton capitals on a yellow card with a black edge."""
    f = font("anton", size)
    lines = text.split("\n")
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    boxes = [d.textbbox((0, 0), ln, font=f) for ln in lines]
    lh = int(size * 1.08)
    tw = max(b[2] - b[0] for b in boxes)
    p = int(size * pad)
    w, h = tw + 2 * p, lh * len(lines) + 2 * p - int(size * 0.12)
    card = Image.new("RGBA", (w + 16, h + 16), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rectangle([4, 4, w + 11, h + 11], fill=BLACK)
    cd.rectangle([8, 8, w + 7, h + 7], fill=bg)
    for i, (ln, b) in enumerate(zip(lines, boxes)):
        cd.text((8 + p - b[0], 8 + p + i * lh - int(size * 0.17)), ln, font=f, fill=fg)
    if angle:
        card = card.rotate(angle, resample=Image.BICUBIC, expand=True)
    return card


def _panel(art, w, h, angle, border=9):
    """Art framed as a panel: white border, black keyline, tilted by angle."""
    art = _fill(art, w, h)
    fr = Image.new("RGBA", (w + 2 * border + 6, h + 2 * border + 6), BLACK + (255,))
    fr.paste(Image.new("RGBA", (w + 2 * border, h + 2 * border), WHITE + (255,)), (3, 3))
    fr.paste(art, (border + 3, border + 3))
    return fr.rotate(angle, resample=Image.BICUBIC, expand=True)


def _place(canvas, layer, cx, cy, shadow=True):
    """Paste an RGBA layer onto the canvas centred at (cx, cy), with a shadow."""
    x, y = int(cx - layer.width / 2), int(cy - layer.height / 2)
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        sh.paste(layer, (x, y), layer)
        canvas.alpha_composite(_shadow(sh, (10, 14), 12, 200))
    canvas.alpha_composite(layer, (x, y))


def _ad(name):
    return Image.open(os.path.join(ADS, name + ".png")).convert("RGB")


def _backdrop(w, h):
    """The black ground the panels sit on, with a faint printed dot screen."""
    img = Image.new("RGBA", (w, h), (10, 8, 14, 255))
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(((xx + yy) % 14) - 7, ((xx - yy) % 14) - 7)
    dots = ((r < 2.2) * 26).astype(np.uint8)
    img.paste((120, 60, 70, 255), (0, 0, w, h), Image.fromarray(dots))
    return img


# ---------------------------------------------------------------- loading screens

def cover_screen():
    """The box-art collage: a grid of tilted panels round the wordmark."""
    W, H = 1920, 1080
    img = _backdrop(W, H)
    panels = [
        # art, (cx, cy), (w, h), angle, caption, caption corner
        (comic(_screen("downtown"), SUNSET, sun=(0.82, 0.16)), (330, 170), (600, 300), 1.2,
         "Everyone here\nknows your mother.", "bl"),
        (comic(_screen("megastore"), DUSK, sun=(0.2, 0.25)), (960, 160), (560, 290), -1.3,
         "Parking lot the\nsize of Summerside.", "br"),
        (comic(_screen("macdougalls"), DUSK, sun=(0.15, 0.2)), (1592, 172), (600, 305), -0.8,
         "Breakfast until 11.\nNo exceptions.", "br"),
        (comic(_screen("victoria-park"), MORNING), (300, 540), (520, 290), -1.8,
         "The harbour's that way.\nEverything's that way.", "tl"),
        (comic(_screen("roundabout"), SUNSET), (310, 912), (580, 300), -1.4,
         "Yield. Then yield\nagain. Then go.", "tl"),
        (comic(_screen("gas-station"), MORNING), (960, 922), (560, 290), 0.9,
         "Fill 'er up.\nSay sorry.", "tr"),
        (comic(_screen("riverside"), SUNSET, sun=(0.47, 0.22)), (1600, 905), (600, 310), 1.6,
         "Nobody locks\ntheir car here.", "bl"),
    ]
    for art, (cx, cy), (w, h), ang, cap, corner in panels:
        p = _panel(art, w, h, ang)
        _place(img, p, cx, cy)
        if cap:
            c = _caption(cap.upper(), 28, angle=-ang * 1.5)
            ox = -w / 2 + c.width / 2 + 10 if corner[1] == "l" else w / 2 - c.width / 2 - 10
            oy = -h / 2 + c.height / 2 + 10 if corner[0] == "t" else h / 2 - c.height / 2 - 10
            _place(img, c, cx + ox, cy + oy, shadow=False)
    # a coffee ad pinned up on the right, the way the real cover sneaks one in
    _place(img, _panel(_ad("tim_hardlys_sausage"), 300, 450, 3.5), 1640, 545)
    wm = wordmark(620)
    _place(img, wm, 950, 540)
    return img.convert("RGB")


def hero_screen(shot, stops, sun, caption, inset, inset_pos, focus=(0.5, 0.5)):
    """One big panel filling the screen, a smaller tilted panel tucked in,
    the wordmark in the corner and a caption across it. A long caption
    (more than two lines) is set smaller, and the inset sits lower to
    make room for it."""
    W, H = 1920, 1080
    img = _backdrop(W, H)
    art = comic(_fill(_screen(shot), 1880, 1040, focus), stops, sun=sun)
    _place(img, _panel(art, 1860, 1020, 0.0, border=10), W / 2, H / 2, shadow=False)
    long = caption.count("\n") >= 2
    iw = 360 if long else 420
    p = _panel(inset, iw, int(iw * inset.height / inset.width), inset_pos[2])
    _place(img, p, inset_pos[0], inset_pos[1] + (80 if long else 0))
    _place(img, wordmark(500), 330, 200)
    c = _caption(caption.upper(), 54 if long else 64, angle=1.5)
    _place(img, c, W - c.width / 2 - 70, 40 + c.height / 2, shadow=True)
    return img.convert("RGB")


def loading_screens():
    return [
        cover_screen(),
        hero_screen("riverside", SUNSET, (0.5, 0.2), "Nobody locks their car here.\nJust saying.",
                    _ad("windys_greasy"), (1640, 600, -3.0)),
        hero_screen("queen-street", DUSK, (0.2, 0.18), "Island time\nis not a speed.",
                    _ad("macdougalls_flurry"), (1650, 620, 2.5)),
        hero_screen("university", MORNING, None, "Speed limit 50.\nOr thereabouts.",
                    _ad("tim_hardlys_iced_capp"), (1640, 610, -2.0)),
        hero_screen("roundabout", SUNSET, (0.7, 0.15),
                    "We have roundabouts.\nAnd roundabouts.\nAnd roundabouts.\nAnd roundabouts.",
                    _ad("tim_hardlys_bagel"), (1660, 620, 3.0)),
        hero_screen("gas-station", DUSK, (0.3, 0.2),
                    "Sorry about the pollution plant.\nSmells like shit all the time.\n"
                    "But you can blame\nyour girlfriend if you want.",
                    _ad("tim_hardlys_hiring"), (1680, 620, -2.5)),
    ]


# ---------------------------------------------------------------- itch.io

def cover(screen):
    """itch.io cover, 630 x 500: a crop of the collage with the wordmark big."""
    w, h = 630, 500
    # the collage's own wordmark is under there: soften and darken it away
    img = _fill(screen, w, h).filter(ImageFilter.GaussianBlur(3)).convert("RGBA")
    img.alpha_composite(Image.new("RGBA", (w, h), (10, 8, 14, 185)))
    _place(img, wordmark(540), w / 2, h / 2 - 20)
    c = _caption("DRIVE A WHOLE REAL CITY", 26, angle=1.5)
    _place(img, c, w / 2, h - 60, shadow=False)
    return img.convert("RGB")


def banner():
    w, h = 960, 300
    img = Image.new("RGBA", (w, h), (10, 8, 14, 255))
    art = comic(_fill(_screen("riverside"), w, h), SUNSET, sun=(0.75, 0.2))
    img.paste(art, (0, 0))
    img.alpha_composite(Image.new("RGBA", (w, h), (10, 8, 14, 60)))
    _place(img, wordmark(420), 250, h / 2)
    return img.convert("RGB")


def background(screen):
    img = screen.filter(ImageFilter.GaussianBlur(6))
    return Image.blend(img, Image.new("RGB", img.size, (10, 8, 14)), 0.6)


def _png_small(img, path):
    """Save as a 256-colour PNG: the printed look survives it, and it's small."""
    img.convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def main():
    os.makedirs(os.path.join(OUT, "itch"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "loading"), exist_ok=True)
    wordmark(1200, edition=None).save(os.path.join(OUT, "logo.png"), optimize=True)
    wordmark(1200).save(os.path.join(OUT, "logo_edition.png"), optimize=True)
    wordmark(1000).save(os.path.join(OUT, "title.png"), optimize=True)
    icon().save(os.path.join(OUT, "icon.png"))
    screens = loading_screens()
    for old in os.listdir(os.path.join(OUT, "loading")):
        if old.endswith(".jpg"):
            os.remove(os.path.join(OUT, "loading", old))
    for i, s in enumerate(screens):
        s.save(os.path.join(OUT, "loading", "%02d.jpg" % (i + 1)), quality=88)
    _png_small(screens[0], os.path.join(OUT, "splash.png"))
    cover(screens[0]).save(os.path.join(OUT, "itch", "cover.png"))
    banner().save(os.path.join(OUT, "itch", "banner.png"))
    background(screens[0]).save(os.path.join(OUT, "itch", "background.png"))
    print("wrote branding/ (logo, title, icon, splash, loading/) and branding/itch/ (cover, banner, background)")


if __name__ == "__main__":
    main()

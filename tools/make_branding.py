#!/usr/bin/env python3
"""Draw Trans-Canada Auto's branding: the wordmark, the loading screens, the
game icon and the itch.io page images.

The look is a loving send-up of the big crime-sandbox games: a stacked,
lowercase, heavy-condensed name in a black box ("trans-canada / auto", with
a maple leaf where the sequel number would go), the map's name in a slanted
script underneath, and loading screens of tilted comic-book panels over a
screen-printed sunset. The panels are the game's own screenshots
(branding/screens/), inked and halftoned here, with captions in our own voice.

Everything is drawn from the screenshots, shapes and the free fonts in
tools/fonts/, so it can be changed and redrawn any time. Run from the
repository root:

    python3 tools/make_branding.py

Needs Pillow and NumPy. Writes:
    branding/logo.png             the wordmark, transparent
    branding/title.png            the wordmark for the title menu, transparent
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
    files = {"anton": "Anton-Regular.ttf", "script": "Pacifico-Regular.ttf",
             "bebas": "BebasNeue-Regular.ttf"}
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


_WORDMARKS = {}


def wordmark(width, sub="Red Clay"):
    """The wordmark at the given width (drawn once per subtitle, then scaled)."""
    if sub not in _WORDMARKS:
        _WORDMARKS[sub] = _draw_wordmark(sub)
    img = _WORDMARKS[sub]
    return img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)


# Which wordmark layout to draw (see _draw_wordmark): "inbox", "stack" or "over".
WORDMARK_LAYOUT = "inbox"


def _draw_wordmark(sub, layout=None):
    """The name the way the box art does it: a black box with the name in
    heavy lowercase, a maple leaf where the sequel number would go, and the
    map's name in slanted script under it. Transparent.

    layout "stack": 'trans-canada' over 'auto' in the box, leaf outside.
    layout "inbox": the same, with the leaf in the box beside 'auto'.
    layout "over":  'trans-canada' over the box, 'auto' big in it, leaf outside."""
    layout = layout or WORDMARK_LAYOUT
    S = 2  # drawn at twice the design size and shrunk, for smooth edges
    W, H = 2600 * S, 1200 * S
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bx, by, pad, gap = 30 * S, 200 * S, 34 * S, 6 * S

    def box_layer(x0, y0, x1, y1):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(layer)
        bd.rounded_rectangle([x0, y0, x1, y1], radius=10 * S, fill=(8, 8, 8, 255), outline=WHITE, width=7 * S)
        bd.rounded_rectangle([x0 + 14 * S, y0 + 14 * S, x1 - 14 * S, y1 - 14 * S], radius=6 * S,
                             outline=(255, 255, 255, 60), width=2 * S)
        return layer, bd

    if layout in ("stack", "inbox"):
        big = font("anton", 230 * S)
        b1 = d.textbbox((0, 0), "trans-canada", font=big)
        b2 = d.textbbox((0, 0), "auto", font=big)
        lh = b1[3] - b1[1]
        bw = (b1[2] - b1[0]) + 2 * pad
        bh = lh * 2 + gap + 2 * pad
        box, bd = box_layer(bx, by, bx + bw, by + bh)
        bd.text((bx + pad - b1[0], by + pad - b1[1]), "trans-canada", font=big, fill=WHITE)
        bd.text((bx + pad - b2[0], by + pad + lh + gap - b1[1]), "auto", font=big, fill=WHITE)
        _with_shadow(img, box, (10 * S, 14 * S), 14 * S)
        if layout == "stack":
            lsz = bh * 1.08
            lx = bx + bw - 22 * S
            ly = by + (bh - lsz * 0.92) / 2 - 20 * S
            _with_shadow(img, _leaf_layer((W, H), lx, ly, lsz), (10 * S, 14 * S), 14 * S)
            sub_right = lx + lsz + 20 * S
        else:
            # the leaf fills the room left of the second line, past 'auto'
            # (kept below the first line, hanging off the bottom of the box)
            lsz = lh * 1.7
            room_l = bx + pad + (b2[2] - b2[0]) + 40 * S
            lx = room_l + (bx + bw - pad - room_l - lsz) * 0.5
            ly = by + pad + lh + gap + 10 * S
            _with_shadow(img, _leaf_layer((W, H), lx, ly, lsz), (6 * S, 8 * S), 8 * S)
            sub_right = bx + bw + 90 * S
        sub_y = by + bh - (60 if layout == "stack" else 20) * S
    else:  # "over"
        big = font("anton", 330 * S)
        b2 = d.textbbox((0, 0), "auto", font=big)
        lh = b2[3] - b2[1]
        bw = (b2[2] - b2[0]) + 2 * pad + 20 * S
        bh = lh + 2 * pad
        top = "trans-canada"
        tf = font("anton", 150 * S)
        bt = d.textbbox((0, 0), top, font=tf)
        # stretch 'auto' box to the width of the name above it
        bw = max(bw, bt[2] - bt[0] + 12 * S)
        box, bd = box_layer(bx, by, bx + bw, by + bh)
        bd.text((bx + (bw - (b2[2] - b2[0])) / 2 - b2[0], by + pad - b2[1]), "auto", font=big, fill=WHITE)
        _with_shadow(img, box, (10 * S, 14 * S), 14 * S)
        t = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(t).text((bx + 6 * S - bt[0], by - bt[3] + 6 * S), top, font=tf, fill=WHITE,
                               stroke_width=9 * S, stroke_fill=BLACK)
        _with_shadow(img, t, (8 * S, 10 * S), 10 * S)
        lsz = bh * 1.15
        lx = bx + bw - 22 * S
        ly = by + (bh - lsz * 0.92) / 2 - 30 * S
        _with_shadow(img, _leaf_layer((W, H), lx, ly, lsz), (10 * S, 14 * S), 14 * S)
        sub_right = lx + lsz + 20 * S
        sub_y = by + bh - 50 * S

    if sub:
        sf = font("script", 165 * S)
        sb = d.textbbox((0, 0), sub, font=sf)
        sx = sub_right - (sb[2] - sb[0])
        sy = sub_y
        s = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(s).text((sx, sy), sub, font=sf, fill=CLAY)
        s = s.rotate(7, resample=Image.BICUBIC, center=(sx, sy))
        x0, y0, x1, y1 = s.getbbox()
        s = s.crop((x0 - 60, y0 - 60, x1 + 60, y1 + 60))
        s = _outlined(s, [9 * S, 5 * S], [CREAM, BLACK])
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.alpha_composite(s, (x0 - 60, y0 - 60))
        _with_shadow(img, layer, (8 * S, 12 * S), 12 * S)

    return img.crop(img.getbbox())


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
    wm = wordmark(640)
    _place(img, wm, 950, 540)
    return img.convert("RGB")


def hero_screen(shot, stops, sun, caption, inset, inset_pos, focus=(0.5, 0.5)):
    """One big panel filling the screen, a smaller tilted panel tucked in,
    the wordmark in the corner and a caption across it."""
    W, H = 1920, 1080
    img = _backdrop(W, H)
    art = comic(_fill(_screen(shot), 1880, 1040, focus), stops, sun=sun)
    _place(img, _panel(art, 1860, 1020, 0.0, border=10), W / 2, H / 2, shadow=False)
    p = _panel(inset, 420, int(420 * inset.height / inset.width), inset_pos[2])
    _place(img, p, inset_pos[0], inset_pos[1])
    _place(img, wordmark(520), 340, 190)
    c = _caption(caption.upper(), 64, angle=1.5)
    _place(img, c, W - c.width / 2 - 70, 150, shadow=True)
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
        hero_screen("roundabout", SUNSET, (0.7, 0.15), "Yield. Then yield again.\nThen apologize.",
                    _ad("tim_hardlys_bagel"), (1640, 620, 3.0)),
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
    _place(img, wordmark(430), 255, h / 2)
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
    wordmark(1200).save(os.path.join(OUT, "logo.png"), optimize=True)
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

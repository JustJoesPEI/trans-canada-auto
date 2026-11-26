#!/usr/bin/env python3
"""Makes textures/ground/street_decals.png: the marks on the streets and
sidewalks (cracks, sealed cracks, patches, manhole covers, storm drains,
oil stains, tyre marks, ravelled asphalt), eight 512 px layers of a
texture array (textures/ground/street_decals.png.import) that
shaders/asphalt.gdshader and sidewalk.gdshader read by world position.

    python3 tools/make_street_decals.py [--preview=sheet.png]

Each layer is one mark centred in its square, nothing at the edges:
    RGB  how the surface under it changes, as a multiplier with 0.5 as
         no change (0.25 halves the asphalt's colour, 0.75 brightens it)
    A    how much of the mark is there (0 = untouched surface)
The shaders place them (where, how big, which way round) from a hash of
the spot, one per cell of a grid, so a pixel reads at most one or two
and nothing is a node. Seeded: it draws the same each time.

To add a mark: write a function returning (rgb, alpha) at S x S, add it
to LAYERS (the order is the layer number) and give it a place in the
shaders' placement (see docs/world_art.md, "Street marks").
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

S = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "ground", "street_decals.png")
SS = 2 # drawn at twice the size and scaled down, for smooth edges


def value_noise(rng, cells, size=S):
    lat = rng.random((cells, cells))
    t = (np.arange(size) + 0.5) / size * cells
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(rng, cells, octaves=4, size=S):
    out = np.zeros((size, size))
    amp = tot = 0.0
    a = 1.0
    for o in range(octaves):
        out += value_noise(rng, cells << o, size) * a
        tot += a
        a *= 0.5
    return out / tot


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def grid():
    y, x = np.mgrid[0:S, 0:S]
    return (x + 0.5) / S * 2 - 1, (y + 0.5) / S * 2 - 1 # -1..1


def radial_fade(r0=0.6, r1=0.95, rng=None):
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    if rng is not None:
        r = r + (fbm(rng, 4, 3) - 0.5) * 0.4
    return 1 - smoothstep(r0, r1, r)


def draw_lines(paths, width_px):
    """Polylines (lists of points in -1..1) as a soft mask."""
    img = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(img)
    for pts, w in paths:
        q = [((x + 1) / 2 * S * SS, (y + 1) / 2 * S * SS) for x, y in pts]
        d.line(q, fill=255, width=max(1, int(w * width_px * SS)), joint="curve")
    return np.asarray(img.resize((S, S), Image.LANCZOS), float) / 255.0


def wander(rng, start, heading, steps, step, turn):
    pts = [start]
    x, y = start
    for _ in range(steps):
        heading += rng.normal(0, turn)
        x += math.cos(heading) * step
        y += math.sin(heading) * step
        pts.append((x, y))
    return pts


def alligator(rng):
    """Fatigue cracking: a net of cracks a few hand-widths across, densest
    in the middle and running out at the edges."""
    x, y = grid()
    n = 14
    pts = rng.random((n * n, 2)) * 2 - 1
    pts = (pts + np.stack(np.meshgrid(np.arange(n), np.arange(n)), -1).reshape(-1, 2) * (2 / n) - 1 + 1 / n * 0) * 0.5
    pts = rng.uniform(-1, 1, (110, 2))
    best = np.full(x.shape, 9.0)
    second = np.full(x.shape, 9.0)
    for px_, py_ in pts:
        d = np.hypot(x - px_, (y - py_) * 0.8)
        second = np.where(d < best, best, np.minimum(second, d))
        best = np.minimum(best, d)
    edge = (second - best) + (fbm(rng, 16, 3) - 0.5) * 0.03
    crack = 1 - smoothstep(0.004, 0.014, edge)
    fade = radial_fade(0.35, 0.9, rng)
    a = np.clip(crack * fade * 1.2, 0, 1)
    # The pieces between the cracks are a touch darker (stained).
    area = fade * 0.25
    alpha = np.maximum(a, area)
    mult = np.where(a > area, 0.3, 0.42)
    rgb = np.repeat(mult[..., None], 3, -1)
    return rgb, alpha


def sealed(rng):
    """Cracks sealed with tar: glossy black ribbons wandering across."""
    paths = []
    for k in range(3):
        start = (rng.uniform(-0.8, -0.3), rng.uniform(-0.6, 0.6))
        main = wander(rng, start, rng.uniform(-0.4, 0.4), 40, 0.035, 0.25)
        paths.append((main, 1.0))
        for _ in range(2):
            b = main[rng.integers(5, 35)]
            paths.append((wander(rng, b, rng.uniform(0, 2 * math.pi), 12, 0.03, 0.35), 0.8))
    m = draw_lines(paths, 7)
    m *= radial_fade(0.75, 1.0)
    rgb = np.full((S, S, 3), 0.18)
    return rgb, np.clip(m * 1.3, 0, 1)


def patch(rng):
    """A rectangular patch of newer asphalt with a sealed seam round it."""
    x, y = grid()
    w, h = 0.85, 0.6
    e = (fbm(rng, 30, 3) - 0.5) * 0.03
    d = np.minimum(w - np.abs(x), h - np.abs(y)) + e
    inside = smoothstep(0.0, 0.01, d)
    seam = (1 - smoothstep(0.006, 0.03, np.abs(d))) * smoothstep(-0.03, 0.0, d)
    grain = fbm(rng, 64, 3)
    mult = 0.36 + (grain - 0.5) * 0.12
    mult = np.where(seam > 0.3, 0.2, mult)
    alpha = np.maximum(inside, seam)
    return np.repeat(mult[..., None], 3, -1), alpha


def manhole(rng):
    """A cast-iron manhole cover in its frame, with a raised grid pattern."""
    x, y = grid()
    r = np.hypot(x, y)
    lid = 0.82
    frame = 0.9
    a = 1 - smoothstep(frame + 0.04, frame + 0.06, r)
    gx = np.abs((x * 9) % 1 - 0.5)
    gy = np.abs((y * 9) % 1 - 0.5)
    pattern = ((gx > 0.38) | (gy > 0.38)).astype(float)
    rings = (np.abs(r - 0.55) < 0.02) | (np.abs(r - 0.3) < 0.02)
    iron = 0.42 + pattern * 0.1 + rings * 0.12 + (fbm(rng, 20, 3) - 0.5) * 0.15
    gap = (np.abs(r - lid) < 0.012)
    frame_m = (r > lid) & (r < frame)
    mult = np.where(r < lid, iron, 0.5)
    mult = np.where(frame_m, 0.55 + (fbm(rng, 30, 2) - 0.5) * 0.1, mult)
    mult = np.where(gap, 0.08, mult)
    # A ring of patched asphalt round the frame.
    ringa = (r >= frame) * 0.6
    mult = np.where(r >= frame, 0.35, mult)
    # Rust toward the rim.
    rust = smoothstep(0.5, 0.8, fbm(rng, 10, 3)) * (r < lid)
    rgb = np.stack([mult * (1 + 0.25 * rust), mult * (1 + 0.05 * rust), mult * (1 - 0.15 * rust)], -1)
    return rgb, np.maximum(a * (r < frame), ringa * a)


def drain(rng):
    """A storm drain grate: iron bars across a dark slot, in a concrete
    frame. Drawn across the middle of the square, long side along x."""
    x, y = grid()
    w, h = 0.9, 0.5
    fw = 0.08
    inside = (np.abs(x) < w) & (np.abs(y) < h)
    grate = (np.abs(x) < w - fw) & (np.abs(y) < h - fw)
    bars = (np.abs((y * 7) % 1 - 0.5) > 0.3) # bars run along the curb
    cross = np.abs(x) < 0.03
    mult = np.where(inside, 0.9 + (fbm(rng, 30, 2) - 0.5) * 0.15, 0.5) # concrete frame
    iron = 0.45 + (fbm(rng, 40, 2) - 0.5) * 0.12
    mult = np.where(grate, np.where(bars | cross, iron, 0.03), mult)
    alpha = inside.astype(float)
    return np.repeat(mult[..., None], 3, -1), alpha


def oil(rng):
    """An oil stain: dark, brownish, blotchy, with a darker middle."""
    x, y = grid()
    r = np.hypot(x * 1.2, y)
    n = fbm(rng, 6, 4)
    a = (1 - smoothstep(0.35, 0.8, r + (n - 0.5) * 0.6)) * (0.55 + 0.45 * fbm(rng, 24, 3))
    core = 1 - smoothstep(0.0, 0.4, r + (n - 0.5) * 0.4)
    m = 0.32 - core * 0.08
    rgb = np.stack([m * 1.05, m * 1.0, m * 0.9], -1)
    return rgb, np.clip(a, 0, 1)


def tyre(rng):
    """Skid and turning marks: a pair of dark curved streaks."""
    paths = []
    for k in range(2):
        r0 = 1.4 + k * 0.0
        cx, cy = -0.2, 1.6
        off = k * 0.36
        pts = []
        for t in np.linspace(-0.6, 0.5, 60):
            rr = r0 + off
            pts.append((cx + math.sin(t) * rr, cy - math.cos(t) * rr))
        paths.append((pts, 1.0))
    m = draw_lines(paths, 22)
    streak = value_noise(rng, 200) * 0.5 + value_noise(rng, 50) * 0.5
    m *= 0.45 + 0.55 * streak
    m *= radial_fade(0.6, 1.0)
    rgb = np.full((S, S, 3), 0.28)
    return rgb, np.clip(m, 0, 1)


def ravelled(rng):
    """Ravelled asphalt: the binder worn off, pale stones showing, a soft
    irregular patch."""
    x, y = grid()
    r = np.hypot(x, y * 1.3)
    n = fbm(rng, 5, 4)
    a = 1 - smoothstep(0.3, 0.85, r + (n - 0.5) * 0.7)
    stones = value_noise(rng, 180) * 0.6 + value_noise(rng, 90) * 0.4
    mult = 0.6 + (stones - 0.5) * 0.35
    pits = (value_noise(rng, 140) > 0.78)
    mult = np.where(pits, 0.3, mult)
    return np.repeat(mult[..., None], 3, -1), np.clip(a * 0.85, 0, 1)


LAYERS = [
    ("alligator", alligator),
    ("sealed", sealed),
    ("patch", patch),
    ("manhole", manhole),
    ("drain", drain),
    ("oil", oil),
    ("tyre", tyre),
    ("ravelled", ravelled),
]


def main():
    layers = []
    for i, (name, fn) in enumerate(LAYERS):
        rng = np.random.default_rng(700 + i)
        rgb, a = fn(rng)
        img = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], -1)
        # Under nothing, no change: keeps the blurred mip levels honest.
        img[..., :3] = np.where(img[..., 3:4] > 0.0, img[..., :3], 0.5)
        layers.append((img * 255 + 0.5).astype(np.uint8))
        print("%d %-10s coverage %.2f" % (i, name, a.mean()))
    out = np.concatenate(layers, 0)
    Image.fromarray(out, "RGBA").save(OUT, optimize=True)
    print("wrote", os.path.normpath(OUT), out.shape)
    preview = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--preview=")]
    if preview:
        tiles = []
        for l in layers:
            f = l.astype(float) / 255
            base = np.full((S, S, 3), 0.3)
            c = base * (1 - f[..., 3:4]) + base * f[..., :3] * 2 * f[..., 3:4]
            tiles.append((np.clip(c, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8))
        sheet = np.concatenate([np.concatenate(tiles[k:k + 4], 1) for k in range(0, len(tiles), 4)], 0)
        Image.fromarray(sheet).save(preview[0])
        print("preview", preview[0])


if __name__ == "__main__":
    main()

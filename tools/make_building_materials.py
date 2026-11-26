#!/usr/bin/env python3
"""Makes textures/facade/wall_materials.png and roof_materials.png: the
tiling wall and roof materials the building shaders read
(shaders/include/building_wall_body.gdshaderinc, building_roof_body), one
layer each (walls 1024 px, roofs 512), stacked top to bottom as texture
arrays (their .import files).

    python3 tools/make_building_materials.py [--preview=sheet.png]

Every layer is drawn here from numbers (seeded, so it comes out the same
each time) at a real size, so the shader tiles it at that size and a brick
course is 7.5 cm wherever it is. A layer holds no colour of its own: the
building's colour (its vertex colour) is the hue, and the layer says how
each spot differs from it. Three channels, all read as numbers (the import
is VRAM-compressed with the high-quality setting, BC7: a byte a pixel; BC1,
half that, smeared the three channels into each other):

    R  shade: 0.5 is the building's colour, 0 black, 1 twice as bright
       (each brick, board or shingle a little different, grain, grime)
    G  joint: 1 where the surface is something else (mortar between bricks,
       the shadow under a lap of siding, the gap between shingles, a seam);
       the shader colours it per layer (JOINT in the shader)
    B  height: 0.5 is the face of the wall; the shader on High turns it
       into light and shade (d_bump), on Low it isn't used


To add a material: write a function returning (shade, joint, height) as
1024x1024 float arrays that tile, add it to LAYERS at the end (the order is
the layer number), run this, and give the layer its size and joint colour in
the shaders' tables (see docs/world_art.md, "Building materials").
--preview=PATH also writes a rough coloured contact sheet there (2x2 tiles
of each layer at half size).
"""
import os
import sys

import numpy as np
from PIL import Image

N = 1024
DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "facade")
# The walls' layers at 1024 px (seen up close), the roofs' (the last
# ROOF_LAYERS) in an array of their own at 512 px: seen from the street or
# from above, never at arm's length.
WALLS = os.path.join(DIR, "wall_materials.png")
ROOFS = os.path.join(DIR, "roof_materials.png")
ROOF_LAYERS = 3
ROOF_SIZE = 512


# --- tiling noise -----------------------------------------------------------

def value_noise(rng, cx, cy=None):
    """Smoothed value noise with cx x cy lattice cells across the tile."""
    cy = cy or cx
    lat = rng.random((cy, cx))
    def axis(cells):
        t = (np.arange(N) + 0.5) / N * cells
        i0 = np.floor(t).astype(int) % cells
        f = t - np.floor(t)
        return i0, (i0 + 1) % cells, f * f * (3.0 - 2.0 * f)
    y0, y1, fy = axis(cy)
    x0, x1, fx = axis(cx)
    a = lat[np.ix_(y0, x0)]
    b = lat[np.ix_(y0, x1)]
    c = lat[np.ix_(y1, x0)]
    d = lat[np.ix_(y1, x1)]
    fx = fx[None, :]
    fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(rng, cx, cy=None, octaves=4, gain=0.5):
    cy = cy or cx
    out = np.zeros((N, N))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(rng, cx << o, cy << o) * amp
        total += amp
        amp *= gain
    return out / total


def blur(img, sigma_px):
    """Gaussian blur that wraps round the edges (the FFT is periodic)."""
    if sigma_px <= 0:
        return img
    fy = np.fft.fftfreq(img.shape[0])[:, None]
    fx = np.fft.fftfreq(img.shape[1])[None, :]
    k = np.exp(-2.0 * (np.pi * sigma_px) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * k))


def speckle(rng, density, size_px=1.0):
    """Sparse dots (grit, granules, pits): 1 at a dot, softened."""
    d = (rng.random((N, N)) < density).astype(float)
    return np.clip(blur(d, size_px) * (2.0 * np.pi * size_px * size_px), 0.0, 1.0) if size_px > 0 else d


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def coords(tile_w, tile_h):
    """Metres across and up for every pixel. Row 0 of the image is the TOP of
    the tile; up the wall is y, so y counts up from the bottom row."""
    x = (np.arange(N) + 0.5) / N * tile_w
    y = (N - 1 - np.arange(N) + 0.5) / N * tile_h
    return np.broadcast_to(x[None, :], (N, N)), np.broadcast_to(y[:, None], (N, N))


def rows_layout(tile_w, tile_h, row_edges, row_breaks):
    """Units laid in rows (bricks, blocks, shingles, tabs). row_edges are the
    rows' bottoms and tops (metres, ascending, 0 to tile_h); row_breaks[i]
    the x where units start in row i (wrapping round tile_w). Returns per
    pixel: unit id (unique), distance to the unit's nearest side and to its
    bottom and top, and its local x from the unit's left (all metres)."""
    x, y = coords(tile_w, tile_h)
    uid = np.zeros((N, N), int)
    dside = np.zeros((N, N))
    dbot = np.zeros((N, N))
    dtop = np.zeros((N, N))
    lx = np.zeros((N, N))
    width = np.zeros((N, N))
    base = 0
    for r in range(len(row_edges) - 1):
        y0, y1 = row_edges[r], row_edges[r + 1]
        m = (y >= y0) & (y < y1)
        br = np.sort(np.asarray(row_breaks[r]) % tile_w)
        xs = x[m]
        k = np.searchsorted(br, xs, side="right") - 1 # -1 = wraps to the last
        left = br[k % len(br)]
        right = np.where(k + 1 < len(br), br[np.minimum(k + 1, len(br) - 1)], br[0] + tile_w)
        left = np.where(k < 0, br[-1] - tile_w, left)
        right = np.where(k < 0, br[0], right)
        uid[m] = base + (k % len(br))
        dside[m] = np.minimum(xs - left, right - xs)
        lx[m] = xs - left
        width[m] = right - left
        dbot[m] = y[m] - y0
        dtop[m] = y1 - y[m]
        base += len(br)
    return uid, dside, dbot, dtop, lx, width


def per_unit(rng, uid, lo=0.0, hi=1.0):
    vals = rng.uniform(lo, hi, uid.max() + 1)
    return vals[uid]


def rounded(dx, dy, r):
    """Inside distance of a box with rounded corners, from the distances to
    its nearest side (dx) and to its nearest top or bottom (dy)."""
    d = np.minimum(dx, dy)
    cx = np.clip(r - dx, 0.0, None)
    cy = np.clip(r - dy, 0.0, None)
    corner = r - np.sqrt(cx * cx + cy * cy)
    return np.where((dx < r) & (dy < r), corner, d)


def finish(shade, joint, height, mean_on_units=True):
    """Shade averages 0.5 over the units (not the joints), so the building's
    colour is what the wall averages to; everything clipped to 0..1."""
    if mean_on_units:
        w = 1.0 - joint
        shade = shade - (shade * w).sum() / max(w.sum(), 1.0) + 0.5
    return np.clip(shade, 0, 1), np.clip(joint, 0, 1), np.clip(height, 0, 1)


# --- the materials ----------------------------------------------------------
# Each takes a seeded generator and returns (shade, joint, height).

def brick(rng):
    """Running bond, 1.8 m square: 24 courses of 7.5 cm, 8 bricks of
    22.5 cm, 1 cm joints a little recessed. Each brick its own shade, a few
    burnt dark ones, pale soft ones, chipped arrises, sandy mortar."""
    W = H = 1.8
    rows = 24
    ch = H / rows
    bl = W / 8
    edges = [i * ch for i in range(rows + 1)]
    breaks = []
    for r in range(rows):
        off = (bl * 0.5 if r % 2 else 0.0) + rng.uniform(-0.012, 0.012)
        breaks.append([off + i * bl + rng.uniform(-0.008, 0.008) for i in range(8)])
    uid, ds, db, dt, lx, wd = rows_layout(W, H, edges, breaks)
    jh = 0.0045 # half joint
    edge_n = (fbm(rng, 48, 48, 3) - 0.5) * 0.006 + (value_noise(rng, 220) - 0.5) * 0.003
    d = rounded(ds - jh, np.minimum(db, dt) - jh, 0.004) + edge_n
    inside = smoothstep(-0.0008, 0.0012, d)
    tone = per_unit(rng, uid, -1.0, 1.0)
    shade = 0.5 + 0.11 * tone
    kind = per_unit(rng, uid)
    shade = np.where(kind > 0.94, shade - 0.16, shade) # burnt headers
    shade = np.where(kind < 0.05, shade + 0.1, shade) # soft pale bricks
    # Each face: fired unevenly (a darker end), sand pits, a little grime.
    end = per_unit(rng, uid, -1, 1)
    shade += 0.05 * end * (lx / np.maximum(wd, 1e-3) - 0.5)
    face = fbm(rng, 64, 64, 4)
    shade += (face - 0.5) * 0.16
    pits = speckle(rng, 0.004, 0.8)
    shade -= pits * 0.18
    mortar_shade = 0.5 + (fbm(rng, 128, 128, 3) - 0.5) * 0.3 - speckle(rng, 0.02, 0.6) * 0.15
    shade = shade * inside + mortar_shade * (1 - inside)
    height = 0.5 + 0.08 * smoothstep(0.0, 0.004, d) + (face - 0.5) * 0.12 - pits * 0.15
    height = height * inside + (0.18 + (mortar_shade - 0.5) * 0.2) * (1 - inside)
    return finish(shade, 1 - inside, height)


def clapboard(rng):
    """Painted lap siding, 2.4 m by 1.2 m: twelve 10 cm boards, each thicker
    at its foot so it throws a thin shadow on the board below, with the
    odd butt joint, faint grain through the paint and worn spots."""
    W, H = 2.4, 1.2
    boards = 12
    bh = H / boards
    x, y = coords(W, H)
    fy = (y % bh) / bh # 0 at the board's foot, 1 at its top
    row = np.floor(y / bh).astype(int)
    # Lap: thick at the foot, thin at the top, under the next board.
    height = 0.75 - 0.45 * fy
    shadow = 1.0 - smoothstep(0.0, 0.07, fy) # the shadow line under each lap
    joint = shadow * 0.85
    grain = fbm(rng, 6, 96, 4)
    grain2 = value_noise(rng, 12, 300)
    shade = 0.5 + (grain - 0.5) * 0.04 + (grain2 - 0.5) * 0.03
    shade += 0.05 * fy # a board's top catches less of the sky... and lap shading
    # Butt joints: about one per board in 2.4 m, at random.
    jx = rng.uniform(0, W, boards)
    has = rng.random(boards) < 0.7
    dj = np.abs(((x - jx[row] + W / 2) % W) - W / 2)
    butt = has[row] * (1.0 - smoothstep(0.0012, 0.003, dj))
    joint = np.maximum(joint, butt * 0.7)
    height -= butt * 0.2
    # Boards differ a touch (repainted at different times).
    shade += (rng.uniform(-1, 1, boards)[row]) * 0.025
    # Worn paint and hairline cracks along the grain.
    wear = smoothstep(0.66, 0.8, fbm(rng, 10, 20, 4)) * smoothstep(0.55, 0.7, grain2)
    shade -= wear * 0.12
    cracks = smoothstep(0.86, 0.95, value_noise(rng, 30, 600)) * smoothstep(0.5, 0.7, value_noise(rng, 8, 16))
    shade -= cracks * 0.1
    height -= cracks * 0.05
    return finish(shade, joint, height)


def vinyl(rng):
    """Vinyl siding, Dutch lap, 3.6 m by 1.2 m: 10 cm courses, each a flat
    face and a cove at its foot, an embossed grain, and the panels'
    overlaps every few metres. Even in colour: it's plastic."""
    W, H = 3.6, 1.2
    courses = 12
    bh = H / courses
    x, y = coords(W, H)
    fy = (y % bh) / bh
    row = np.floor(y / bh).astype(int)
    panel = row // 2
    # Dutch lap: a cove for the lower quarter, then a flat face.
    cove = smoothstep(0.0, 0.28, fy)
    height = 0.35 + 0.35 * cove + 0.08 * (1 - smoothstep(0.0, 0.03, fy))
    shade = 0.5 - 0.08 * (1 - cove) + 0.04 * smoothstep(0.85, 1.0, fy)
    joint = (1.0 - smoothstep(0.0, 0.045, fy)) * 0.8
    emboss = value_noise(rng, 24, 500) * 0.6 + value_noise(rng, 60, 900) * 0.4
    shade += (emboss - 0.5) * 0.03
    height += (emboss - 0.5) * 0.05
    # Panel ends overlap (a straight vertical step) every 3.6 m, staggered.
    px = rng.uniform(0, W, 6)
    dj = ((x - px[panel]) % W)
    lap = smoothstep(0.0, 0.0015, dj) * (1 - smoothstep(0.0015, 0.012, dj))
    shade -= (1 - smoothstep(0.0, 0.003, dj)) * 0.12
    shade += lap * 0.03
    height += lap * 0.1
    # Chalky streaks.
    shade += (fbm(rng, 4, 8, 3) - 0.5) * 0.04
    return finish(shade, joint, height)


def cedar_shingle(rng):
    """Cedar shingles, 1.5 m square: courses of 12.5 cm, shingles 8 to 30 cm
    wide with dark keyways between, each weathered its own grey-brown,
    grain running down them and a shadow under each butt."""
    W = H = 1.5
    rows = 12
    ch = H / rows
    edges = [i * ch for i in range(rows + 1)]
    breaks = []
    for r in range(rows):
        xs, p = [], rng.uniform(0, W)
        start = p
        while p < start + W - 0.1:
            xs.append(p)
            p += rng.uniform(0.08, 0.30)
        breaks.append(xs)
    uid, ds, db, dt, lx, wd = rows_layout(W, H, edges, breaks)
    _, y = coords(W, H)
    fy = db / ch
    keyway = 1 - smoothstep(0.0015, 0.004, ds)
    butt = 1 - smoothstep(0.0, 0.1, fy)
    tone = per_unit(rng, uid, -1, 1)
    shade = 0.5 + 0.1 * tone
    shade += (per_unit(rng, uid) > 0.93) * 0.08 # a newer, paler one
    grain = value_noise(rng, 260, 10) * 0.6 + value_noise(rng, 520, 24) * 0.4
    shade += (grain - 0.5) * 0.16
    shade += (fbm(rng, 16, 16, 3) - 0.5) * 0.1
    # The bottom edges darken with damp; the tops are hidden under the next course.
    shade -= butt * 0.08 + smoothstep(0.75, 1.0, fy) * 0.04
    height = 0.3 + 0.5 * (1 - fy) + (grain - 0.5) * 0.12 - keyway * 0.3
    joint = np.maximum(keyway, (1 - smoothstep(0.0, 0.045, fy)) * 0.8)
    # Curl: a few shingles cup and lift at the butt.
    curl = per_unit(rng, uid) > 0.85
    height += curl * butt * 0.15
    return finish(shade, joint, height)


def sandstone(rng):
    """Island sandstone ashlar, 2.4 m square: courses 30 to 45 cm, blocks
    55 to 110 cm, fine joints of pale mortar, soft worn arrises, bedding
    lines through the stone, tooling and weathering patches."""
    W = H = 2.4
    heights = [0.3, 0.42, 0.3, 0.36, 0.3, 0.42, 0.3]
    edges = np.concatenate([[0.0], np.cumsum(heights)])
    edges = edges / edges[-1] * H
    breaks = []
    for r in range(len(heights)):
        xs, p = [], rng.uniform(0, W)
        start = p
        while p < start + W - 0.4:
            xs.append(p)
            p += rng.uniform(0.55, 1.1)
        breaks.append(xs)
    uid, ds, db, dt, lx, wd = rows_layout(W, H, edges, breaks)
    x, y = coords(W, H)
    jh = 0.004
    edge_n = (fbm(rng, 40, 40, 3) - 0.5) * 0.01
    d = rounded(ds - jh, np.minimum(db, dt) - jh, 0.015) + edge_n
    inside = smoothstep(-0.001, 0.002, d)
    tone = per_unit(rng, uid, -1, 1)
    shade = 0.5 + 0.09 * tone
    bed = value_noise(rng, 3, 90) * 0.6 + value_noise(rng, 5, 200) * 0.4 # bedding lines run along
    shade += (bed - 0.5) * 0.1
    weather = fbm(rng, 10, 10, 5)
    shade += (weather - 0.5) * 0.22
    tooling = value_noise(rng, 600, 40)
    shade += (tooling - 0.5) * 0.025
    grit = speckle(rng, 0.01, 0.7)
    shade -= grit * 0.08
    arris = smoothstep(0.0, 0.03, d) # worn edges dip and darken a little
    shade -= (1 - arris) * inside * 0.05
    mortar = 0.5 + (fbm(rng, 100, 100, 3) - 0.5) * 0.2
    shade = shade * inside + mortar * (1 - inside)
    height = 0.45 + 0.25 * arris + (weather - 0.5) * 0.25 + (tooling - 0.5) * 0.05
    height = height * inside + 0.2 * (1 - inside)
    return finish(shade, 1 - inside, height)


def stucco(rng):
    """Painted render, 2 m square: trowel swirls, sand grain, a few hairline
    cracks; flat in colour, as paint is."""
    W = H = 2.0
    warp_x = fbm(rng, 6, 6, 3)
    warp_y = fbm(rng, 6, 6, 3)
    swirl = fbm(rng, 14, 14, 4)
    # Domain-warp the swirl by rolling rows and columns (keeps the tiling).
    idx = np.arange(N)
    sx = ((idx[None, :] + (warp_x - 0.5) * 120).astype(int)) % N
    sy = ((idx[:, None] + (warp_y - 0.5) * 120).astype(int)) % N
    swirl = swirl[sy, sx]
    grain = value_noise(rng, 512) * 0.5 + value_noise(rng, 256) * 0.5
    shade = 0.5 + (swirl - 0.5) * 0.12 + (grain - 0.5) * 0.08
    # Hairline cracks: thin ridges of a stretched noise, in a few places.
    c1 = np.abs(fbm(rng, 8, 8, 4) - 0.5)
    crack = (1 - smoothstep(0.0, 0.006, c1)) * smoothstep(0.7, 0.78, fbm(rng, 4, 4, 2))
    shade -= crack * 0.08
    height = 0.5 + (swirl - 0.5) * 0.35 + (grain - 0.5) * 0.25 - crack * 0.2
    return finish(shade, crack * 0.6, height)


def concrete_block(rng):
    """Painted concrete block, 1.6 m square: 40 by 20 cm blocks in running
    bond, concave 1 cm joints, porous faces under the paint."""
    W = H = 1.6
    rows = 8
    ch = H / rows
    bl = 0.4
    edges = [i * ch for i in range(rows + 1)]
    breaks = [[(bl * 0.5 if r % 2 else 0.0) + i * bl for i in range(4)] for r in range(rows)]
    uid, ds, db, dt, lx, wd = rows_layout(W, H, edges, breaks)
    jh = 0.005
    d = rounded(ds - jh, np.minimum(db, dt) - jh, 0.003)
    inside = smoothstep(-0.001, 0.0015, d)
    shade = 0.5 + per_unit(rng, uid, -1, 1) * 0.035
    pores = speckle(rng, 0.012, 0.9)
    shade -= pores * 0.12
    face = fbm(rng, 40, 40, 4)
    shade += (face - 0.5) * 0.08
    shade += (fbm(rng, 4, 4, 3) - 0.5) * 0.06 # paint unevenly weathered
    jshade = 0.5 + (fbm(rng, 90, 90, 2) - 0.5) * 0.1
    shade = shade * inside + jshade * (1 - inside)
    concave = np.clip(-d / jh, 0, 1)
    height = (0.6 + (face - 0.5) * 0.1 - pores * 0.2) * inside + (0.3 - 0.15 * (1 - concave)) * (1 - inside)
    return finish(shade, (1 - inside) * 0.8, height)


def fieldstone(rng):
    """Rubble foundation stone, 1.5 m square: rounded stones 10 to 35 cm
    (a jittered grid, Voronoi), deep mortar between, each stone its own
    shade."""
    W = 1.5
    cells = 7
    pts = []
    for j in range(cells):
        for i in range(cells):
            pts.append(((i + rng.uniform(0.15, 0.85)) / cells * W, (j + rng.uniform(0.15, 0.85)) / cells * W))
    pts = np.array(pts)
    x, y = coords(W, W)
    best = np.full((N, N), 1e9)
    second = np.full((N, N), 1e9)
    sid = np.zeros((N, N), int)
    for k, (px, py) in enumerate(pts):
        for ox in (-W, 0, W):
            for oy in (-W, 0, W):
                dx = x - (px + ox)
                dy = (y - (py + oy)) * 1.25 # stones laid flatter than tall
                dd = np.sqrt(dx * dx + dy * dy)
                closer = dd < best
                second = np.where(closer, best, np.minimum(second, dd))
                sid = np.where(closer, k, sid)
                best = np.minimum(best, dd)
    edge = (second - best) * 0.5 # distance to the border with the next stone
    edge += (fbm(rng, 24, 24, 4) - 0.5) * 0.025
    inside = smoothstep(0.008, 0.016, edge)
    tone = rng.uniform(-1, 1, len(pts))[sid]
    shade = 0.5 + 0.16 * tone + (fbm(rng, 20, 20, 3) - 0.5) * 0.2
    dome = np.clip(edge / 0.06, 0, 1)
    shade += (dome - 0.5) * 0.08
    mortar = 0.5 + (fbm(rng, 80, 80, 3) - 0.5) * 0.25
    shade = shade * inside + mortar * (1 - inside)
    height = (0.35 + 0.55 * np.sqrt(dome)) * inside + 0.12 * (1 - inside)
    return finish(shade, 1 - inside, height)


def asphalt_shingle(rng):
    """Laminated asphalt shingles, 2 m across by 1.4 m up the slope:
    courses of 14 cm, tabs 15 to 35 cm of slightly different granule
    colour with dark shadow bands between, gritty granules all over."""
    W, H = 2.0, 1.4
    rows = 10
    ch = H / rows
    edges = [i * ch for i in range(rows + 1)]
    breaks = []
    for r in range(rows):
        xs, p = [], rng.uniform(0, W)
        start = p
        while p < start + W - 0.12:
            xs.append(p)
            p += rng.uniform(0.15, 0.35)
        breaks.append(xs)
    uid, ds, db, dt, lx, wd = rows_layout(W, H, edges, breaks)
    fy = db / ch
    tone = per_unit(rng, uid, -1, 1)
    shade = 0.5 + 0.1 * tone
    # Laminated: a darker band at the foot of some tabs (the shadow layer).
    band = per_unit(rng, uid) < 0.5
    shade -= band * (1 - smoothstep(0.25, 0.32, fy)) * 0.14
    granules = value_noise(rng, 700) * 0.6 + value_noise(rng, 350) * 0.4
    shade += (granules - 0.5) * 0.35
    shade -= speckle(rng, 0.02, 0.6) * 0.15
    shade += speckle(rng, 0.01, 0.6) * 0.15
    shade += (fbm(rng, 5, 5, 3) - 0.5) * 0.08 # sun-faded patches
    gap = 1 - smoothstep(0.0008, 0.0025, ds)
    butt = 1 - smoothstep(0.0, 0.08, fy)
    joint = np.maximum(gap * 0.7, butt * 0.75)
    height = 0.35 + 0.4 * (1 - fy) + (granules - 0.5) * 0.15 - gap * 0.25
    return finish(shade, joint, height)


def standing_seam(rng):
    """Standing-seam metal roof, 1.6 m square: a raised seam every 40 cm,
    two faint stiffening ribs in each pan, and a little oil-canning
    (the flat pans aren't quite flat)."""
    W = H = 1.6
    x, y = coords(W, H)
    pw = 0.4
    u = (x % pw) / pw
    ds = np.minimum(u, 1 - u) * pw # metres to the seam
    seam = 1 - smoothstep(0.006, 0.012, ds)
    rib = np.exp(-((np.abs(u - 0.5) - 0.17) / 0.012) ** 2)
    pan_id = np.floor(x / pw).astype(int)
    shade = 0.5 + rng.uniform(-1, 1, 4)[pan_id % 4] * 0.03
    oil = fbm(rng, 4, 3, 3)
    shade += (oil - 0.5) * 0.12
    shade += rib * 0.04
    # Seam: a bright top and a dark shadow on one side.
    side = (u > 0.5) & (ds < 0.02)
    shade -= side * (1 - smoothstep(0.012, 0.02, ds)) * 0.15
    shade += (fbm(rng, 3, 40, 3) - 0.5) * 0.05 # streaks down the slope
    height = 0.4 + 0.5 * seam + 0.05 * rib + (oil - 0.5) * 0.1
    return finish(shade, seam, height)


def flat_roof(rng):
    """Flat roof, 3.84 m square: granular modified-bitumen sheet in 96 cm
    rolls, the laps between them a little raised and darker, patches of
    gravel and grit."""
    W = H = 3.84
    x, y = coords(W, H)
    rw = 0.96
    u = (x % rw) / rw
    dl = np.minimum(u, 1 - u) * rw
    lap = 1 - smoothstep(0.02, 0.035, dl)
    # End laps: the rolls are 10 m long, so the odd one in a tile.
    roll = np.floor(x / rw).astype(int)
    ey = rng.uniform(0, H, 4)
    de = np.abs(((y - ey[roll % 4] + H / 2) % H) - H / 2)
    lap = np.maximum(lap, (1 - smoothstep(0.02, 0.035, de)) * (rng.random(4)[roll % 4] < 0.5))
    granules = value_noise(rng, 512) * 0.5 + value_noise(rng, 256) * 0.5
    shade = 0.5 + (granules - 0.5) * 0.3
    gravel = smoothstep(0.55, 0.7, fbm(rng, 6, 6, 4))
    stones = speckle(rng, 0.03, 0.9)
    shade += gravel * (stones * 0.3 - 0.05)
    shade += (fbm(rng, 8, 8, 4) - 0.5) * 0.12
    height = 0.5 + lap * 0.15 + gravel * stones * 0.3 + (granules - 0.5) * 0.1
    return finish(shade, lap * 0.6, height)


# The layer number is the place in this list: the shaders' tables follow it.
LAYERS = [
    ("brick", brick),
    ("clapboard", clapboard),
    ("vinyl", vinyl),
    ("cedar_shingle", cedar_shingle),
    ("sandstone", sandstone),
    ("stucco", stucco),
    ("concrete_block", concrete_block),
    ("fieldstone", fieldstone),
    ("asphalt_shingle", asphalt_shingle),
    ("standing_seam", standing_seam),
    ("flat_roof", flat_roof),
]


def main():
    strips = []
    for i, (name, fn) in enumerate(LAYERS):
        rng = np.random.default_rng(1000 + i)
        s, j, h = fn(rng)
        rgb = np.stack([s, j, h], axis=-1)
        strips.append((rgb * 255.0 + 0.5).astype(np.uint8))
        print("%2d %-16s shade %.2f-%.2f mean %.3f  joint %.2f" % (i, name, s.min(), s.max(), s.mean(), j.mean()))
    walls = np.concatenate(strips[:-ROOF_LAYERS], axis=0)
    Image.fromarray(walls, "RGB").save(WALLS, optimize=True)
    roofs = [np.asarray(Image.fromarray(r, "RGB").resize((ROOF_SIZE, ROOF_SIZE), Image.LANCZOS)) for r in strips[-ROOF_LAYERS:]]
    Image.fromarray(np.concatenate(roofs, axis=0), "RGB").save(ROOFS, optimize=True)
    print("wrote", os.path.normpath(WALLS), walls.shape, "and", os.path.normpath(ROOFS))
    preview = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--preview=")]
    if preview:
        # A rough look: each layer coloured as the shader would, 2x2 tiles.
        cols = [(0.55, 0.25, 0.18), (0.93, 0.87, 0.7), (0.6, 0.7, 0.78), (0.52, 0.39, 0.28), (0.66, 0.44, 0.34),
                (0.9, 0.85, 0.7), (0.72, 0.71, 0.67), (0.6, 0.58, 0.55), (0.3, 0.3, 0.32), (0.35, 0.2, 0.16), (0.3, 0.3, 0.3)]
        joints = [(0.72, 0.7, 0.66), None, None, None, (0.8, 0.77, 0.72), None, None, (0.6, 0.6, 0.58), None, None, None]
        jk = [0, 0.35, 0.45, 0.25, 0, 0.6, 0.9, 0, 0.35, 1.25, 0.7]
        tiles = []
        for i, st in enumerate(strips):
            a = st.astype(float) / 255.0
            c = np.array(cols[i])
            body = c * (a[..., 0:1] * 2.0)
            jc = np.array(joints[i]) if joints[i] else c * jk[i]
            jcol = jc * (a[..., 0:1] * 2.0)
            out = body * (1 - a[..., 1:2]) + jcol * a[..., 1:2]
            out = np.clip(out, 0, 1)
            t = (np.tile(out, (2, 2, 1))[::2, ::2] * 255).astype(np.uint8)
            tiles.append(t)
        sheet = np.concatenate([np.concatenate(tiles[k:k + 4] + [np.zeros_like(tiles[0])] * (4 - len(tiles[k:k + 4])), axis=1) for k in range(0, len(tiles), 4)], axis=0)
        Image.fromarray(sheet).save(preview[0])
        print("preview", preview[0])


if __name__ == "__main__":
    main()

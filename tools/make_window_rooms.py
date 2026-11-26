#!/usr/bin/env python3
"""Makes textures/facade/window_rooms.png: the rooms seen through the
town's windows, sixteen 256 px layers of a texture array
(textures/facade/window_rooms.png.import), for the wall shader's interior
mapping (shaders/include/building_wall_body.gdshaderinc, `room_view`).

    python3 tools/make_window_rooms.py [--preview=sheet.png]

Each layer is one room, pre-projected: the picture you'd see standing
outside the middle of the window, one room-depth back from the glass
(EYE). The back wall is the square in the middle, the floor, ceiling and
side walls the trapezoids round it. The shader traces the view ray through
a box the size of the window's bay and storey and looks up where it hits
in this picture, so the room's walls, floor and ceiling move right as the
camera passes (the furniture is painted on them, so it leans a little when
seen from the side, which nobody notices through glass).

The rooms are traced here, in numbers: a box room 2.6 m wide, 3 m high
and 4 m deep, furniture as boxes, lit from the window and, where the
lights are on, from the ceiling. Seeded, so it draws the same each time.

To add a room: write a function returning a Room, put it in ROOMS (the
order is the layer number; offices, flats and shops are grouped, see the
ROOM_* ranges in the shader) and run this.
"""
import os
import sys

import numpy as np
from PIL import Image

S = 256
# Metres: the room a picture is drawn for. Offices and flats are one
# window bay wide; a shop is three bays (the shader's shopfronts put one
# shop behind every three) and as tall as the shop floor.
ROOM = (2.6, 3.0, 4.0)
SHOP = (7.8, 4.0, 5.0)
EYE = 1.0 # eye distance in front of the glass, in room depths (the shader's ROOM_EYE)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures", "facade", "window_rooms.png")


def srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def lin(*rgb):
    c = np.array(rgb, float) / 255.0 if max(rgb) > 1.0 else np.array(rgb, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class Room:
    def __init__(self, wall, floor, ceiling=lin(0.85, 0.85, 0.83), lit=0.0, light=lin(1.0, 0.93, 0.8),
                 floor_kind="wood", wall_kind="paint", ceiling_kind="plain", window_light=1.0, back=None, size=ROOM):
        self.wall = wall
        self.back = back if back is not None else wall
        self.floor = floor
        self.ceiling = ceiling
        self.lit = lit # ceiling light strength (0 = off)
        self.light = light
        self.floor_kind = floor_kind
        self.wall_kind = wall_kind
        self.ceiling_kind = ceiling_kind
        self.window_light = window_light
        self.boxes = [] # (min xyz, max xyz, colour, pattern)
        self.size = size
        # Furniture is placed for a 2.6 m room and stretched across a wider one.
        self.xs = size[0] / ROOM[0]

    def box(self, x0, y0, z0, x1, y1, z1, colour, pattern=None):
        self.boxes.append((np.array([x0 * self.xs, y0, z0]), np.array([x1 * self.xs, y1, z1]), np.asarray(colour, float), pattern))
        return self


def hash2(a, b):
    return np.modf(np.sin(a * 127.1 + b * 311.7) * 43758.5453)[0] % 1.0


def render(room, rng):
    W, H, D = room.size
    v, u = np.mgrid[0:S, 0:S]
    u = (u + 0.5) / S
    v = (v + 0.5) / S
    # A ray from the eye through this point of the window plane (metres).
    o = np.stack([u * W, (1 - v) * H, np.zeros_like(u)], -1)
    d = np.stack([(u - 0.5) * W, (0.5 - v) * H, np.full_like(u, EYE * D)], -1)
    # The room's own walls.
    t = np.full(u.shape, 1e9)
    face = np.zeros(u.shape, int)
    for axis, lo, hi, f_lo, f_hi in ((0, 0.0, W, 1, 2), (1, 0.0, H, 3, 4), (2, None, D, None, 5)):
        dd = d[..., axis]
        with np.errstate(divide="ignore", invalid="ignore"):
            if lo is not None:
                tl = np.where(dd < 0, (lo - o[..., axis]) / dd, 1e9)
                better = (tl > 0) & (tl < t)
                t = np.where(better, tl, t)
                face = np.where(better, f_lo, face)
            th = np.where(dd > 0, (hi - o[..., axis]) / dd, 1e9)
            better = (th > 0) & (th < t)
            t = np.where(better, th, t)
            face = np.where(better, f_hi, face)
    normal = np.zeros(u.shape + (3,))
    normal[face == 1] = (1, 0, 0)
    normal[face == 2] = (-1, 0, 0)
    normal[face == 3] = (0, 1, 0)
    normal[face == 4] = (0, -1, 0)
    normal[face == 5] = (0, 0, -1)
    p = o + d * t[..., None]
    col = np.zeros(u.shape + (3,))
    col[(face == 1) | (face == 2)] = room.wall
    col[face == 5] = room.back
    col[face == 3] = room.floor
    col[face == 4] = room.ceiling
    # Surface patterns.
    fl = face == 3
    if room.floor_kind == "wood":
        board = np.floor(p[..., 0] / 0.12)
        col[fl] *= (0.85 + 0.25 * hash2(board, np.floor(p[..., 2] / 1.2 + board * 0.37)))[fl, None]
    elif room.floor_kind == "tile":
        chk = (np.floor(p[..., 0] / 0.3) + np.floor(p[..., 2] / 0.3)) % 2
        col[fl] *= (0.85 + 0.15 * chk)[fl, None]
    elif room.floor_kind == "carpet":
        col[fl] *= (0.92 + 0.08 * rng.random(u.shape))[fl, None]
    ce = face == 4
    if room.ceiling_kind == "panels":
        gx = np.abs((p[..., 0] / 0.6) % 1 - 0.5)
        gz = np.abs((p[..., 2] / 0.6) % 1 - 0.5)
        grid = (gx > 0.47) | (gz > 0.47)
        col[ce & grid] *= 0.75
        lamp = (np.abs(p[..., 0] - W / 2) < 0.3) & (((p[..., 2] % 1.8) > 0.6) & ((p[..., 2] % 1.8) < 1.8))
        if room.lit > 0:
            col[ce & lamp] = room.light * 3.0
    wl = (face == 1) | (face == 2) | (face == 5)
    if room.wall_kind == "wallpaper":
        along = np.where(face == 5, p[..., 0], p[..., 2])
        stripe = (np.floor(along / 0.12) % 2)
        col[wl] *= (0.9 + 0.1 * stripe)[wl, None]
        # Wainscot below the chair rail.
        low = wl & (p[..., 1] < 0.9)
        col[low] = lin(0.42, 0.3, 0.2) * 0.8
    if room.wall_kind in ("paint", "wallpaper"):
        # Skirting board.
        skirt = wl & (p[..., 1] < 0.1)
        col[skirt] = lin(0.9, 0.88, 0.84)
    # Furniture.
    for bmin, bmax, bcol, pattern in room.boxes:
        with np.errstate(divide="ignore", invalid="ignore"):
            t0 = (bmin - o) / d
            t1 = (bmax - o) / d
        tn = np.minimum(t0, t1)
        tf = np.maximum(t0, t1)
        tnear = tn.max(-1)
        tfar = tf.min(-1)
        hit = (tnear < tfar) & (tnear > 0) & (tnear < t)
        if not hit.any():
            continue
        ax = tn.argmax(-1)
        t = np.where(hit, tnear, t)
        p = o + d * t[..., None]
        n = np.zeros(u.shape + (3,))
        for a in range(3):
            sel = hit & (ax == a)
            n[sel, a] = -np.sign(d[sel, a])
        normal = np.where(hit[..., None], n, normal)
        c = np.broadcast_to(bcol, u.shape + (3,)).copy()
        if pattern == "products":
            # Rows of packets on shelves: coloured blocks.
            cell = np.floor(p[..., 0] / 0.07) + 31 * np.floor(p[..., 1] / 0.33)
            pal = np.array([lin(200, 40, 40), lin(240, 200, 60), lin(40, 90, 170), lin(230, 230, 220), lin(60, 140, 60), lin(220, 120, 40)])
            pick = (hash2(cell, 3.0) * len(pal)).astype(int) % len(pal)
            prod = pal[pick]
            band = ((p[..., 1] % 0.33) < 0.26)
            c = np.where((band & hit)[..., None], prod, c * 0.6)
        elif pattern == "books":
            cell = np.floor(p[..., 0] / 0.035 + np.floor(p[..., 1] / 0.4) * 7)
            pal = np.array([lin(120, 30, 30), lin(30, 50, 100), lin(40, 80, 50), lin(200, 180, 140), lin(90, 60, 40), lin(30, 30, 30)])
            pick = (hash2(cell, 9.0) * len(pal)).astype(int) % len(pal)
            band = ((p[..., 1] % 0.4) < 0.3)
            c = np.where((band & hit)[..., None], pal[pick], c)
        elif pattern == "clothes":
            cell = np.floor(p[..., 0] / 0.06) + np.floor(p[..., 2] / 0.06)
            pal = np.array([lin(30, 30, 40), lin(170, 40, 50), lin(200, 190, 170), lin(60, 90, 140), lin(110, 110, 110), lin(190, 150, 60)])
            pick = (hash2(cell, 5.0) * len(pal)).astype(int) % len(pal)
            c = pal[pick] * (0.85 + 0.15 * hash2(cell, 2.0))[..., None]
        elif pattern == "screen":
            c = np.broadcast_to(lin(0.25, 0.4, 0.55), c.shape).copy()
        elif pattern == "picture":
            c = c * (0.7 + 0.6 * hash2(np.floor(p[..., 0] / 0.08), np.floor(p[..., 1] / 0.08)))[..., None]
        col = np.where(hit[..., None], c, col)
    # Light: a soft daylight from the window (falling off with depth), the
    # ceiling lights where they're on, and darker corners.
    depth = p[..., 2] / D
    day = room.window_light * (0.55 * np.exp(-depth * 1.8) + 0.12)
    facing_window = np.clip(-normal[..., 2], 0, 1) * 0.35 + 0.65
    shade = day * facing_window
    if room.lit > 0:
        lp = np.array([W / 2, H - 0.05, D * 0.5])
        to = lp - p
        dist = np.linalg.norm(to, axis=-1)
        ndl = np.clip((normal * to).sum(-1) / np.maximum(dist, 1e-3), 0, 1)
        shade = shade[..., None] + (room.lit * (0.35 + 0.65 * ndl) / (1 + 0.15 * dist * dist))[..., None] * room.light
    else:
        shade = shade[..., None] * np.ones(3)
    # Corners and the floor's edges darker (a cheap occlusion).
    edge = np.minimum.reduce([p[..., 0], W - p[..., 0], p[..., 1], H - p[..., 1], D - p[..., 2]])
    ao = 0.65 + 0.35 * np.clip(edge / 0.4, 0, 1)
    out = col * shade * ao[..., None]
    out[(face == 4) & (col.max(-1) > 1.5)] = np.clip(col[(face == 4) & (col.max(-1) > 1.5)], 0, 1) # lit panels
    return out


# --- the rooms ----------------------------------------------------------------
# Offices (layers 0-3), flats and houses (4-9), shops (10-15).

def office(lit, seed):
    r = Room(lin(0.78, 0.78, 0.75), lin(0.32, 0.33, 0.35), lit=lit, floor_kind="carpet", ceiling_kind="panels",
             light=lin(0.95, 0.98, 1.0))
    rng = np.random.default_rng(seed)
    for z in (1.2, 2.9):
        r.box(0.2, 0.72, z, 2.4, 0.76, z + 0.8, lin(0.55, 0.5, 0.42)) # desk
        r.box(0.25, 0, z + 0.1, 0.3, 0.72, z + 0.7, lin(0.3, 0.3, 0.3))
        r.box(2.3, 0, z + 0.1, 2.35, 0.72, z + 0.7, lin(0.3, 0.3, 0.3))
        x = rng.uniform(0.4, 1.6)
        r.box(x, 0.76, z + 0.55, x + 0.55, 1.12, z + 0.6, lin(0.05, 0.05, 0.05), "screen")
        r.box(0.0, 0, z + 0.85, 1.1, 1.3, z + 0.9, lin(0.4, 0.45, 0.5)) # partition
    r.box(2.0, 0, 3.6, 2.55, 1.3, 4.0, lin(0.45, 0.45, 0.45)) # filing cabinet
    return r


def boardroom():
    r = Room(lin(0.6, 0.62, 0.6), lin(0.25, 0.22, 0.2), lit=1.2, floor_kind="carpet", ceiling_kind="panels",
             back=lin(0.35, 0.4, 0.48))
    r.box(0.6, 0.72, 0.9, 2.0, 0.78, 3.4, lin(0.3, 0.2, 0.13))
    for z in (1.2, 2.0, 2.8):
        r.box(0.3, 0, z, 0.55, 1.0, z + 0.45, lin(0.1, 0.1, 0.1))
        r.box(2.05, 0, z, 2.3, 1.0, z + 0.45, lin(0.1, 0.1, 0.1))
    r.box(0.8, 1.2, 3.96, 1.8, 1.8, 4.0, lin(0.02, 0.02, 0.03), "screen")
    return r


def living(wall, sofa, lit, seed):
    r = Room(wall, lin(0.45, 0.3, 0.18), lit=lit, floor_kind="wood")
    r.box(0.4, 0.0, 3.2, 2.2, 0.45, 4.0, sofa) # sofa seat
    r.box(0.4, 0.45, 3.75, 2.2, 0.85, 4.0, sofa * 0.85) # back
    r.box(0.3, 0.0, 3.2, 0.45, 0.65, 4.0, sofa * 0.9)
    r.box(2.15, 0.0, 3.2, 2.3, 0.65, 4.0, sofa * 0.9)
    r.box(0.9, 1.4, 3.98, 1.7, 2.0, 4.0, lin(0.5, 0.45, 0.35), "picture")
    r.box(0.7, 0.0, 1.9, 1.9, 0.02, 3.0, lin(0.5, 0.15, 0.12)) # rug
    r.box(0.9, 0.0, 2.2, 1.7, 0.42, 2.7, lin(0.35, 0.24, 0.15)) # coffee table
    r.box(2.35, 0.0, 1.0, 2.6, 1.9, 2.4, lin(0.4, 0.28, 0.18), "books")
    return r


def living_tv(seed):
    r = Room(lin(0.55, 0.65, 0.62), lin(0.5, 0.36, 0.22), lit=0.0, floor_kind="wood")
    r.box(0.0, 0.0, 1.3, 0.9, 0.45, 3.4, lin(0.35, 0.33, 0.3)) # sofa along the left wall
    r.box(0.0, 0.45, 1.3, 0.25, 0.85, 3.4, lin(0.3, 0.28, 0.26))
    r.box(1.9, 0.0, 1.8, 2.5, 0.5, 3.0, lin(0.2, 0.15, 0.1)) # TV stand
    r.box(2.45, 0.6, 1.9, 2.5, 1.2, 2.9, lin(0.02, 0.02, 0.02))
    r.box(0.5, 0.0, 3.8, 2.1, 2.0, 4.0, lin(0.6, 0.45, 0.3), "books")
    return r


def bedroom():
    r = Room(lin(0.62, 0.55, 0.62), lin(0.45, 0.32, 0.2), lit=0.6, wall_kind="paint", light=lin(1.0, 0.85, 0.65))
    r.box(0.5, 0.0, 2.0, 2.1, 0.55, 4.0, lin(0.85, 0.85, 0.88)) # bed
    r.box(0.5, 0.55, 2.0, 2.1, 0.6, 3.0, lin(0.3, 0.4, 0.6)) # duvet
    r.box(0.45, 0.0, 3.9, 2.15, 1.1, 4.0, lin(0.35, 0.22, 0.12)) # headboard
    r.box(2.2, 0.0, 3.4, 2.6, 0.6, 3.9, lin(0.35, 0.22, 0.12)) # bedside
    r.box(0.0, 0.0, 0.8, 0.5, 1.2, 1.8, lin(0.45, 0.3, 0.2)) # dresser
    return r


def kitchen():
    r = Room(lin(0.85, 0.82, 0.7), lin(0.6, 0.6, 0.58), lit=0.9, floor_kind="tile", light=lin(1.0, 0.95, 0.85))
    r.box(0.0, 0.0, 3.4, 2.6, 0.9, 4.0, lin(0.7, 0.7, 0.68)) # lower cabinets
    r.box(0.0, 0.9, 3.4, 2.6, 0.94, 4.0, lin(0.25, 0.25, 0.25)) # counter
    r.box(0.0, 1.5, 3.7, 2.6, 2.3, 4.0, lin(0.7, 0.7, 0.68)) # upper cabinets
    r.box(2.0, 0.0, 2.6, 2.6, 1.8, 3.35, lin(0.8, 0.8, 0.8)) # fridge
    r.box(0.6, 0.72, 1.2, 1.6, 0.76, 2.2, lin(0.5, 0.35, 0.2)) # table
    r.box(0.65, 0.0, 1.25, 0.7, 0.72, 2.15, lin(0.4, 0.28, 0.16))
    r.box(1.5, 0.0, 1.25, 1.55, 0.72, 2.15, lin(0.4, 0.28, 0.16))
    return r


def parlour():
    r = Room(lin(0.55, 0.35, 0.3), lin(0.35, 0.22, 0.13), lit=0.5, wall_kind="wallpaper", light=lin(1.0, 0.8, 0.55))
    r.box(0.9, 0.0, 3.6, 1.7, 1.1, 4.0, lin(0.55, 0.5, 0.45)) # fireplace
    r.box(1.05, 0.15, 3.59, 1.55, 0.7, 3.6, lin(0.03, 0.02, 0.02))
    r.box(1.0, 1.4, 3.98, 1.6, 2.1, 4.0, lin(0.4, 0.35, 0.25), "picture")
    r.box(0.1, 0.0, 2.2, 0.8, 0.9, 2.9, lin(0.35, 0.12, 0.1)) # armchair
    r.box(1.9, 0.0, 2.2, 2.55, 0.9, 2.9, lin(0.35, 0.12, 0.1))
    return r


def dark_room():
    r = Room(lin(0.6, 0.6, 0.58), lin(0.3, 0.25, 0.2), lit=0.0, window_light=0.45)
    r.box(1.6, 0.0, 3.3, 2.5, 0.6, 4.0, lin(0.4, 0.35, 0.3)) # boxes
    r.box(1.8, 0.6, 3.5, 2.4, 1.0, 4.0, lin(0.45, 0.4, 0.33))
    r.box(0.8, 0.0, 3.98, 1.6, 2.1, 4.0, lin(0.3, 0.25, 0.2)) # a door
    return r


def shop_clothes():
    r = Room(lin(0.9, 0.9, 0.88), lin(0.55, 0.45, 0.35), lit=1.6, ceiling_kind="plain", light=lin(1.0, 0.95, 0.88), size=SHOP)
    for z in (1.0, 2.2):
        r.box(0.4, 0.55, z, 2.2, 1.45, z + 0.45, lin(0.5, 0.5, 0.5), "clothes")
        r.box(0.4, 1.45, z + 0.2, 2.2, 1.5, z + 0.25, lin(0.7, 0.7, 0.72))
    r.box(0.0, 0.3, 3.7, 2.6, 2.2, 4.0, lin(0.5, 0.5, 0.5), "clothes")
    r.box(2.05, 0.0, 0.7, 2.35, 1.75, 0.95, lin(0.85, 0.82, 0.78)) # mannequin
    return r


def shop_cafe():
    r = Room(lin(0.55, 0.35, 0.22), lin(0.25, 0.18, 0.12), lit=1.4, floor_kind="wood", light=lin(1.0, 0.82, 0.55),
             back=lin(0.15, 0.15, 0.14), size=SHOP)
    r.box(0.0, 0.0, 2.8, 2.6, 1.05, 3.3, lin(0.4, 0.25, 0.15)) # counter
    r.box(0.3, 1.05, 2.9, 0.8, 1.5, 3.2, lin(0.6, 0.6, 0.62)) # espresso machine
    r.box(0.3, 1.6, 3.98, 2.3, 2.4, 4.0, lin(0.05, 0.05, 0.05), "books") # menu board
    r.box(0.3, 0.0, 0.8, 1.0, 0.75, 1.5, lin(0.2, 0.2, 0.2)) # table
    r.box(1.6, 0.0, 0.8, 2.3, 0.75, 1.5, lin(0.2, 0.2, 0.2))
    return r


def shop_store(lit):
    r = Room(lin(0.92, 0.92, 0.9), lin(0.75, 0.75, 0.72), lit=lit, floor_kind="tile", ceiling_kind="panels",
             light=lin(0.95, 1.0, 1.0), size=SHOP)
    for x in (0.0, 1.15, 2.3):
        r.box(x, 0.0, 1.0, x + 0.3, 1.8, 3.6, lin(0.8, 0.8, 0.8), "products")
    r.box(0.0, 0.0, 3.7, 2.6, 2.0, 4.0, lin(0.8, 0.8, 0.8), "products")
    return r


def shop_books():
    r = Room(lin(0.3, 0.35, 0.3), lin(0.45, 0.3, 0.18), lit=1.3, floor_kind="wood", light=lin(1.0, 0.9, 0.7), size=SHOP)
    r.box(0.0, 0.0, 0.8, 0.35, 2.3, 4.0, lin(0.35, 0.22, 0.12), "books")
    r.box(2.25, 0.0, 0.8, 2.6, 2.3, 4.0, lin(0.35, 0.22, 0.12), "books")
    r.box(0.0, 0.0, 3.65, 2.6, 2.3, 4.0, lin(0.35, 0.22, 0.12), "books")
    r.box(0.8, 0.0, 1.5, 1.8, 0.8, 2.4, lin(0.4, 0.26, 0.14), "books")
    return r


def shop_empty():
    r = Room(lin(0.8, 0.8, 0.78), lin(0.5, 0.5, 0.48), lit=0.0, floor_kind="tile", ceiling_kind="panels", window_light=0.7, size=SHOP)
    r.box(1.6, 0.0, 3.0, 2.2, 0.5, 3.5, lin(0.55, 0.45, 0.3)) # a box left behind
    r.box(0.3, 0.0, 3.98, 1.1, 2.1, 4.0, lin(0.35, 0.35, 0.36)) # back door
    return r


ROOMS = [
    lambda: office(1.3, 1), lambda: office(0.0, 2), lambda: office(1.1, 3), boardroom,
    lambda: living(lin(0.85, 0.78, 0.62), lin(0.3, 0.35, 0.45), 0.0, 4),
    lambda: living(lin(0.6, 0.7, 0.75), lin(0.55, 0.3, 0.2), 0.7, 5),
    lambda: living_tv(6), bedroom, kitchen, parlour,
    dark_room, shop_clothes, shop_cafe, lambda: shop_store(1.5), shop_books, shop_empty,
]


def main():
    layers = []
    for i, make in enumerate(ROOMS):
        rng = np.random.default_rng(500 + i)
        img = render(make(), rng)
        # Soften the traced edges a touch (four samples a pixel would be
        # better; this is a blur of half a pixel).
        img = (img + np.roll(img, 1, 0) * 0.25 + np.roll(img, 1, 1) * 0.25) / 1.5
        layers.append((srgb(img) * 255 + 0.5).astype(np.uint8))
    out = np.concatenate(layers, axis=0)
    Image.fromarray(out, "RGB").save(OUT, optimize=True)
    print("wrote", os.path.normpath(OUT), out.shape)
    preview = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--preview=")]
    if preview:
        sheet = np.concatenate([np.concatenate(layers[k:k + 4], axis=1) for k in range(0, len(layers), 4)], axis=0)
        Image.fromarray(sheet).save(preview[0])
        print("preview", preview[0])


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Put a world brand's billboards up by the road near its locations.

For each building of the brand (matched like the game does: its OSM brand
or name is one the brand replaces, see data/map_config.json "brands"), it
finds the main road beside it and a spot on that road's right-hand verge
50 to 110 m before the shop, as drivers on their way there see it: clear of
buildings, other streets, water and the other billboards. The board stands
there angled toward those drivers. Each location gets the next ad of the
list, and they are written to data/edits.json as ordinary sign=billboard
points (with "ad"), so they can be moved or deleted in the map editor like
any other sign.

    python3 tools/place_billboards.py "Tim Hardly's" tim_hardlys_bb_large tim_hardlys_bb_ready ...

Running it again for a brand replaces that brand's billboards (they carry
"brand" so they can be found). Ads are names from textures/ads/ (drawn by
tools/make_ads.py).
"""

import glob
import json
import math
import os
import sys
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

MAIN_ROADS = {"trunk", "primary", "secondary", "tertiary"}
NOT_ROADS = {"footway", "path", "cycleway", "steps", "pedestrian", "track", "bridleway", "corridor", "proposed", "construction"}
BOARD_HALF = 4.8  # half the width of a default ad billboard (9.6 m)


class Projection:
    """The game's projection (scripts/world/geo_projection.gd)."""

    def __init__(self, lat, lon):
        self.lat, self.lon = lat, lon
        phi = math.radians(lat)
        self.m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
        self.m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)

    def ground(self, lon, lat):
        return np.array([(lon - self.lon) * self.m_lon, -(lat - self.lat) * self.m_lat])

    def lon_lat(self, g):
        return [round(self.lon + g[0] / self.m_lon, 7), round(self.lat - g[1] / self.m_lat, 7)]


def load_elevation():
    meta = json.load(open(os.path.join(DATA, "elevation.json")))
    raw = zlib.decompress(open(os.path.join(DATA, meta["file"]), "rb").read())
    grid = np.frombuffer(raw, dtype="<i2").reshape(meta["nz"], meta["nx"])
    return meta, grid


def height_at(meta, grid, g):
    i = int(round((g[0] - meta["origin_x"]) / meta["spacing"]))
    j = int(round((g[1] - meta["origin_z"]) / meta["spacing"]))
    if 0 <= j < grid.shape[0] and 0 <= i < grid.shape[1]:
        return grid[j, i] / 100.0
    return -1.0


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(np.dot(p - a, ab) / max(1e-9, np.dot(ab, ab)), 0.0, 1.0)
    return np.linalg.norm(p - (a + ab * t)), t


def point_in_ring(p, ring):
    x, y = p
    inside = False
    n = len(ring)
    for i in range(n):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside
    return inside


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    brand_name, ads = sys.argv[1], sys.argv[2:]
    config = json.load(open(os.path.join(DATA, "map_config.json")))
    brand = config["brands"][brand_name]
    replaces = set(brand.get("replaces", []))
    proj = Projection(config["origin"]["lat"], config["origin"]["lon"])
    widths = config["road_defaults"]
    meta, grid = load_elevation()

    roads = []
    for f in json.load(open(os.path.join(DATA, "city", "roads.geojson")))["features"]:
        if f["geometry"]["type"] != "LineString":
            continue
        hw = f["properties"].get("highway", "")
        if hw in NOT_ROADS:
            continue
        pts = np.array([proj.ground(*c) for c in f["geometry"]["coordinates"]])
        half = float(widths.get(hw, {}).get("width", 7.0)) * 0.5 + float(widths.get(hw, {}).get("sidewalk", 0.0))
        roads.append((hw, pts, half, pts.min(axis=0) - half - 20, pts.max(axis=0) + half + 20))

    buildings, shops = [], []
    for path in glob.glob(os.path.join(DATA, "city", "chunks", "*.geojson")):
        for f in json.load(open(path))["features"]:
            p = f.get("properties", {})
            if p.get("kind") != "building" or f["geometry"]["type"] != "Polygon":
                continue
            ring = np.array([proj.ground(*c) for c in f["geometry"]["coordinates"][0]])
            buildings.append((ring, ring.min(axis=0), ring.max(axis=0)))
            if p.get("brand") in replaces or p.get("name") in replaces:
                shops.append((p.get("addr:street", p.get("name", "")), ring.mean(axis=0)))

    edits_path = os.path.join(DATA, "edits.json")
    edits = json.load(open(edits_path))
    kept = [f for f in edits.get("new_features", []) if (f.get("tags") or {}).get("brand") != brand_name]
    placed = [proj.ground(*f["pos"]) for f in kept if str((f.get("tags") or {}).get("type", "")) == "sign=billboard"]

    def clear(q):
        if height_at(meta, grid, q) < 0.3:
            return False  # water or the shore
        for other in placed:
            if np.linalg.norm(q - other) < 40.0:
                return False
        for hw, pts, half, lo, hi in roads:
            if not (lo[0] < q[0] < hi[0] and lo[1] < q[1] < hi[1]):
                continue
            for i in range(len(pts) - 1):
                if seg_dist(q, pts[i], pts[i + 1])[0] < half + BOARD_HALF * 0.6 + 1.5:
                    return False
        for ring, lo, hi in buildings:
            if lo[0] - 6 < q[0] < hi[0] + 6 and lo[1] - 6 < q[1] < hi[1] + 6:
                if point_in_ring(q, ring):
                    return False
                for i in range(len(ring) - 1):
                    if seg_dist(q, ring[i], ring[i + 1])[0] < BOARD_HALF + 1.0:
                        return False
        return True

    out = []
    for n, (street, c) in enumerate(sorted(shops, key=lambda s: s[0])):
        # The main road beside the shop, and where along it the shop is.
        best = None
        for hw, pts, half, lo, hi in roads:
            if hw not in MAIN_ROADS:
                continue
            for i in range(len(pts) - 1):
                d, t = seg_dist(c, pts[i], pts[i + 1])
                if d < 120 and (best is None or d < best[0]):
                    best = (d, pts, half, i, t)
        if best is None:
            print("  no main road near the one on", street)
            continue
        _, pts, half, i0, t0 = best
        lengths = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        s0 = lengths[i0] + t0 * (lengths[i0 + 1] - lengths[i0])

        def along(s):
            k = int(np.clip(np.searchsorted(lengths, s) - 1, 0, len(pts) - 2))
            seg = pts[k + 1] - pts[k]
            f = (s - lengths[k]) / max(1e-9, lengths[k + 1] - lengths[k])
            return pts[k] + seg * f, seg / np.linalg.norm(seg)

        found = None
        for dist in (70, 60, 80, 50, 90, 100, 110):
            for sign in (1, -1):  # before the shop coming one way, then the other
                s = s0 - sign * dist
                if s < 0 or s > lengths[-1]:
                    continue
                p, tangent = along(s)
                travel = tangent * sign  # drivers heading toward the shop
                right = np.array([-travel[1], travel[0]])  # x east, z south: right of travel
                for setback in (half + 6.0, half + 9.0, half + 13.0):
                    q = p + right * setback
                    if clear(q):
                        found = (q, travel, right)
                        break
                if found:
                    break
            if found:
                break
        if not found:
            print("  no clear verge near the one on", street)
            continue
        q, travel, right = found
        face = -travel * 0.8 - right * 0.6  # toward the oncoming drivers, turned to the road
        face /= np.linalg.norm(face)
        bearing = math.degrees(math.atan2(face[0], -face[1])) % 360.0  # compass: 0 north, 90 east
        ad = ads[len(out) % len(ads)]
        placed.append(q)
        out.append({"id": "edit:ad_%s_%d" % ("".join(ch for ch in brand_name.lower() if ch.isalnum()), len(out) + 1),
                    "kind": "point", "pos": proj.lon_lat(q),
                    "tags": {"type": "sign=billboard", "ad": ad, "brand": brand_name, "direction": str(round(bearing))}})
        print("  %-24s %s, facing %d" % (street or "?", ad, round(bearing)))

    edits["new_features"] = kept + out
    with open(edits_path, "w") as fh:
        json.dump(edits, fh, indent=2)
        fh.write("\n")
    print("placed %d billboards for %s" % (len(out), brand_name))


if __name__ == "__main__":
    main()

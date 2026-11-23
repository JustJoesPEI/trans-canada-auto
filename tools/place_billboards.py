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
any other sign. Shops downtown (inside the heritage district) get none.

    python3 tools/place_billboards.py "Tim Hardly's" tim_hardlys_bb_large tim_hardlys_bb_ready ...

--each=2 puts up a board for drivers coming from each way (for a brand
with few locations and plenty to say).

Running it again for a brand replaces that brand's billboards (they carry
"brand" so they can be found). Ads are names from textures/ads/ (drawn by
tools/make_ads.py).

    python3 tools/place_billboards.py --tourism

puts up the Sand Bar Tourism Board's billboards instead (drawn by
tools/make_branding.py): each by the place its joke is about, listed in
TOURISM_BOARDS below: the roundabouts one at roundabouts, the pollution
plant one by the pollution control plant, and so on. A place is a name of
an area or building in the map data, or "roundabout". Running it again
replaces them all.
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
TOURISM = "Sand Bar Tourism Board"

# The tourism board's billboards: (place, ads, how many places at most, boards per place).
TOURISM_BOARDS = [
    ("roundabout", ["sandbar_bb_roundabouts"], 4, 1),
    ("Charlottetown Pollution Control Plant", ["sandbar_bb_plant"], 1, 2),
    ("PEI Energy Systems District Heating Plant", ["sandbar_bb_recycling"], 1, 1),
    ("Queen Elizabeth Hospital", ["sandbar_bb_nurse"], 1, 2),
    ("University of Prince Edward Island", ["sandbar_bb_speed"], 1, 1),
    ("Eastlink Centre", ["sandbar_bb_mother"], 1, 1),
    ("Bunbury Mall", ["sandbar_bb_locks"], 1, 1),
    ("Victoria Park", ["sandbar_bb_island_time"], 1, 1),
]


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


def ring_dist(q, rings):
    """How far q is from the nearest of these outlines (0 inside one)."""
    best = 1e9
    for ring in rings:
        if point_in_ring(q, ring):
            return 0.0
        for i in range(len(ring) - 1):
            best = min(best, seg_dist(q, ring[i], ring[i + 1])[0])
    return best


def roundabouts(proj):
    """The middle of each roundabout: its pieces of road grouped together."""
    pieces = []
    for f in json.load(open(os.path.join(DATA, "city", "roads.geojson")))["features"]:
        if f["properties"].get("junction") == "roundabout" and f["geometry"]["type"] == "LineString":
            pieces.append(np.array([proj.ground(*c) for c in f["geometry"]["coordinates"]]).mean(axis=0))
    groups = []
    for c in pieces:
        for g in groups:
            if np.linalg.norm(np.mean(g, axis=0) - c) < 60.0:
                g.append(c)
                break
        else:
            groups.append([c])
    return [np.mean(g, axis=0) for g in groups]


def spread(points, n):
    """n of the points, spread out: each next one the farthest from those chosen."""
    if len(points) <= n:
        return list(points)
    chosen = [min(points, key=lambda p: np.linalg.norm(p))]
    while len(chosen) < n:
        chosen.append(max(points, key=lambda p: min(np.linalg.norm(p - c) for c in chosen)))
    return chosen


def main():
    if len(sys.argv) < 2 or (len(sys.argv) < 3 and "--tourism" not in sys.argv):
        print(__doc__)
        sys.exit(1)
    tourism = "--tourism" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    each = max([1] + [int(a[7:]) for a in sys.argv[1:] if a.startswith("--each=")])
    config = json.load(open(os.path.join(DATA, "map_config.json")))
    if tourism:
        brand_name, ads, replaces = TOURISM, [], set()
    else:
        brand_name, ads = args[0], args[1:]
        replaces = set(config["brands"][brand_name].get("replaces", []))
    proj = Projection(config["origin"]["lat"], config["origin"]["lon"])
    widths = config["road_defaults"]
    meta, grid = load_elevation()
    downtown = float(config.get("heritage_district_m", 0.0))  # no billboards in the heritage district

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
    named = {}  # name: outlines, for the tourism board's places
    wanted = {t[0] for t in TOURISM_BOARDS} if tourism else set()
    for path in glob.glob(os.path.join(DATA, "city", "chunks", "*.geojson")):
        for f in json.load(open(path))["features"]:
            p = f.get("properties", {})
            if not f.get("geometry") or f["geometry"]["type"] != "Polygon":
                continue
            if p.get("name") in wanted:
                named.setdefault(p["name"], []).append(np.array([proj.ground(*c) for c in f["geometry"]["coordinates"][0]]))
            if p.get("kind") != "building":
                continue
            ring = np.array([proj.ground(*c) for c in f["geometry"]["coordinates"][0]])
            buildings.append((ring, ring.min(axis=0), ring.max(axis=0)))
            if (p.get("brand") in replaces or p.get("name") in replaces) and np.linalg.norm(ring.mean(axis=0)) > downtown:
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

    # What to put boards by: (label, centre, outlines or None, ads, boards there).
    targets = []
    if tourism:
        for place, place_ads, most, per in TOURISM_BOARDS:
            if place == "roundabout":
                spots = [c for c in roundabouts(proj) if np.linalg.norm(c) > downtown]
                for c in spread(spots, most):
                    targets.append(("a roundabout", c, None, place_ads, per))
            elif place in named:
                rings = named[place]
                targets.append((place, np.concatenate(rings).mean(axis=0), rings, place_ads, per))
            else:
                print("  no %s in the map data" % place)
    else:
        for street, c in sorted(shops, key=lambda s: s[0]):
            targets.append((street, c, None, ads, each))

    out = []
    for label, c, rings, target_ads, per in targets:
        # Spots along the main roads near the place (50-110 m from a shop or
        # a roundabout's middle, nearest 70 m first; 15-110 m from the edge
        # of a named place, nearest 45 m first), each for drivers heading
        # toward it, on their right.
        lo_d, ideal, hi_d = (15.0, 45.0, 110.0) if rings is not None else (50.0, 70.0, 110.0)
        reach = 120.0 + (max(np.ptp(np.concatenate(rings), axis=0)) if rings is not None else 0.0)
        cands = []
        for hw, pts, half, lo, hi in roads:
            if hw not in MAIN_ROADS or not (lo[0] - reach < c[0] < hi[0] + reach and lo[1] - reach < c[1] < hi[1] + reach):
                continue
            for i in range(len(pts) - 1):
                seg = pts[i + 1] - pts[i]
                ln = np.linalg.norm(seg)
                if ln < 0.5:
                    continue
                tangent = seg / ln
                for k in range(int(ln // 5) + 1):
                    p = pts[i] + tangent * min(ln, k * 5.0)
                    dist = ring_dist(p, rings) if rings is not None else np.linalg.norm(p - c)
                    if lo_d <= dist <= hi_d:
                        travel = tangent if np.dot(c - p, tangent) > 0 else -tangent
                        cands.append((abs(dist - ideal), p, travel, half))
        cands.sort(key=lambda x: x[0])
        founds = []
        for _, p, travel, half in cands:
            if len(founds) >= per:
                break
            if any(np.dot(travel, f[1]) > 0.0 for f in founds):
                continue  # one per way in
            right = np.array([-travel[1], travel[0]])  # x east, z south: right of travel
            for setback in (half + 6.0, half + 9.0, half + 13.0):
                q = p + right * setback
                too_close = ring_dist(q, rings) < 3.0 if rings is not None else np.linalg.norm(q - c) < 35.0
                if too_close or not clear(q):
                    continue
                founds.append((q, travel, right))
                placed.append(q)
                break
        if not founds:
            print("  no clear verge near", label or "?")
            continue
        for q, travel, right in founds:
            face = -travel * 0.8 - right * 0.6  # toward the oncoming drivers, turned to the road
            face /= np.linalg.norm(face)
            bearing = math.degrees(math.atan2(face[0], -face[1])) % 360.0  # compass: 0 north, 90 east
            ad = target_ads[len(out) % len(target_ads)]
            out.append({"id": "edit:ad_%s_%d" % ("".join(ch for ch in brand_name.lower() if ch.isalnum()), len(out) + 1),
                        "kind": "point", "pos": proj.lon_lat(q),
                        "tags": {"type": "sign=billboard", "ad": ad, "brand": brand_name, "direction": str(round(bearing))}})
            print("  %-36s %s, facing %d" % (label or "?", ad, round(bearing)))

    edits["new_features"] = kept + out
    with open(edits_path, "w") as fh:
        json.dump(edits, fh, indent=2)
        fh.write("\n")
    print("placed %d billboards for %s" % (len(out), brand_name))


if __name__ == "__main__":
    main()

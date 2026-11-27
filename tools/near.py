#!/usr/bin/env python3
"""What's on the map near a spot, for placing props and checking research.

    python3 tools/near.py LAT LON [RADIUS_M]
    python3 tools/near.py --street "Victoria Row"     # a street's points
    python3 tools/near.py --find "Rochford"           # names matching

Lists the streets (nearest point and its distance), buildings (OSM id,
name, address, landmark name, footprint centre and size), mapped areas
(parks, playgrounds, patios, pitches...) and the props and signs already
placed in data/edits.json within RADIUS_M (default 60) of LAT, LON.
Positions are [lat, lon] with metres east/north of the spot, so a prop can
be placed by offset ("4 m north of the arch's west post").
"""
import glob
import json
import math
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LAT0 = 46.2346406
M_LAT = 111132.92 - 559.82 * math.cos(2 * math.radians(LAT0)) + 1.175 * math.cos(4 * math.radians(LAT0))
M_LON = 111412.84 * math.cos(math.radians(LAT0)) - 93.5 * math.cos(3 * math.radians(LAT0))


def off(lat, lon, lat1, lon1):
    """Metres east and north of (lat, lon)."""
    return (lon1 - lon) * M_LON, (lat1 - lat) * M_LAT


def load_chunks():
    feats = []
    for f in glob.glob(os.path.join(ROOT, "data/city/chunks/*.geojson")):
        feats += json.load(open(f))["features"]
    return feats


def centre(ring):
    xs = [c[0] for c in ring]
    ys = [c[1] for c in ring]
    return sum(ys) / len(ys), sum(xs) / len(xs), ring


def size_of(lat, ring):
    e = [(c[0] - ring[0][0]) * M_LON for c in ring]
    n = [(c[1] - ring[0][1]) * M_LAT for c in ring]
    return max(e) - min(e), max(n) - min(n)


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    qx, qy = ax + t * dx, ay + t * dy
    return math.hypot(px - qx, py - qy), (qx, qy)


def main():
    args = sys.argv[1:]
    cfg = json.load(open(os.path.join(ROOT, "data/map_config.json")))
    lms = cfg.get("landmarks", {})
    roads = [r for r in json.load(open(os.path.join(ROOT, "data/city/roads.geojson")))["features"]
             if r["geometry"]["type"] == "LineString"]
    if args and args[0] == "--street":
        for r in roads:
            if r["properties"].get("name", "").lower() == args[1].lower():
                cs = r["geometry"]["coordinates"]
                print(r["properties"].get("highway"), " ".join("[%.6f, %.6f]" % (c[1], c[0]) for c in cs))
        return
    if args and args[0] == "--find":
        q = args[1].lower()
        for f in load_chunks():
            p = f["properties"]
            lm = lms.get(str(p.get("osm_id")), {})
            text = " ".join(str(v) for v in [p.get("name", ""), lm.get("name", ""), p.get("addr:street", ""), p.get("addr:housenumber", "")])
            if q in text.lower() and f["geometry"]["type"] == "Polygon":
                la, lo, _ = centre(f["geometry"]["coordinates"][0])
                print("%s %s [%.6f, %.6f] %s | %s" % (p.get("kind"), p.get("osm_id"), la, lo, p.get("name", ""), lm.get("name", "")))
        return
    lat, lon = float(args[0]), float(args[1])
    rad = float(args[2]) if len(args) > 2 else 60.0
    here = (0.0, 0.0)
    print("== streets")
    best = {}
    for r in roads:
        name = r["properties"].get("name") or r["properties"].get("highway")
        cs = r["geometry"]["coordinates"]
        pts = [off(lat, lon, c[1], c[0]) for c in cs]
        for a, b in zip(pts, pts[1:]):
            d, q = seg_dist(here, a, b)
            if d < rad and (name not in best or d < best[name][0]):
                ang = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1])) % 180
                best[name] = (d, q, ang)
    for name, (d, q, ang) in sorted(best.items(), key=lambda x: x[1][0]):
        print("  %-28s %5.1f m away, nearest at %+.0f E %+.0f N, runs %03.0f/%03.0f deg" % (name, d, q[0], q[1], ang, ang + 180))
    print("== buildings, areas, points")
    rows = []
    for f in load_chunks():
        p = f["properties"]
        g = f.get("geometry") or {"type": None}
        if g["type"] == "Polygon":
            la, lo, ring = centre(g["coordinates"][0])
        elif g["type"] == "Point":
            lo, la = g["coordinates"]
            ring = None
        else:
            continue
        e, n = off(lat, lon, la, lo)
        d = math.hypot(e, n)
        if d > rad + (30 if ring else 0):
            continue
        if ring:
            # Nearest corner, so a big park whose middle is far still shows.
            d = min(d, min(math.hypot(*off(lat, lon, c[1], c[0])) for c in ring))
            if d > rad:
                continue
        lm = lms.get(str(p.get("osm_id")), {})
        what = p.get("type") or p.get("building") or p.get("kind")
        label = " ".join(x for x in [p.get("name", ""), ("#" + p["addr:housenumber"] + " " + p.get("addr:street", "")) if p.get("addr:housenumber") else "", ("LANDMARK: " + lm.get("name", "?")) if lm else ""] if x)
        sz = " %.0fx%.0f m" % size_of(la, ring) if ring else ""
        rows.append((d, "  %-9s %-22s %-11s centre [%.6f, %.6f] (%+.0f E %+.0f N)%s %s" % (p.get("kind"), what, p.get("osm_id", ""), la, lo, e, n, sz, label)))
    for d, s in sorted(rows):
        print(s)
    print("== placed in edits.json")
    ed = json.load(open(os.path.join(ROOT, "data/edits.json")))
    for f in ed.get("new_features", []):
        if f.get("kind") != "point":
            continue
        lo, la = f["pos"]
        e, n = off(lat, lon, la, lo)
        if math.hypot(e, n) <= rad:
            t = f.get("tags", {})
            print("  %-26s %s (%+.0f E %+.0f N) dir %s %s" % (t.get("type"), f["id"], e, n, t.get("direction", "-"), t.get("text", t.get("note", ""))[:70]))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Write data/city/addresses.json: the real street addresses jobs deliver to.

    python3 tools/make_addresses.py

Every building in the OSM chunks with a house number and a street
(addr:housenumber, addr:street), about 1,700 of them, as:

    {"n": "45", "street": "Kent Street", "kind": "home" | "apartments" | "business",
     "x", "z":      the footprint's middle (game metres),
     "door": [x, z] the point of the footprint nearest its street,
     "road": [x, z] the nearest point on that street's centreline}

"door" to "road" is the way in from the street: a delivery's drop zone
is on that line (the front lawn, the driveway, the curb). A building whose
street isn't in the road data (a typo, a lane OSM doesn't have) is left
out. Same projection as scripts/world/geo_projection.gd.
scripts/economy/addresses.gd reads it. Run it again after refreshing the
OSM data.
"""

import glob
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HOMES = {"house", "detached", "semidetached_house", "residential", "terrace", "bungalow", "cabin", "duplex"}


def projection(cfg):
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    return lambda lon, lat: ((lon - lon0) * m_lon, -(lat - lat0) * m_lat)


def closest_on_segment(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / l2))
    return (ax + dx * t, az + dz * t)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def main():
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    to_ground = projection(cfg)
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    # Street centrelines by name.
    streets = {}
    for f in json.load(open(os.path.join(city, "roads.geojson"), encoding="utf-8"))["features"]:
        name = f["properties"].get("name")
        if not name or f["geometry"]["type"] != "LineString":
            continue
        streets.setdefault(name, []).append([to_ground(*c[:2]) for c in f["geometry"]["coordinates"]])
    out = []
    seen = set()
    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        for f in json.load(open(path, encoding="utf-8"))["features"]:
            p = f["properties"]
            n, street = p.get("addr:housenumber"), p.get("addr:street")
            geom = f.get("geometry") or {}
            if not n or not street or geom.get("type") != "Polygon" or street not in streets:
                continue
            key = (n, street)
            if key in seen:
                continue # a building split over chunks
            seen.add(key)
            ring = [to_ground(*c[:2]) for c in geom["coordinates"][0]]
            cx = sum(q[0] for q in ring) / len(ring)
            cz = sum(q[1] for q in ring) / len(ring)
            # The nearest point of the street to the building's middle...
            road, best = None, float("inf")
            for line in streets[street]:
                for i in range(len(line) - 1):
                    q = closest_on_segment((cx, cz), line[i], line[i + 1])
                    d = dist(q, (cx, cz))
                    if d < best:
                        road, best = q, d
            if best > 120.0:
                continue # the street's a long way off: a stray tag
            # ...and the point of the footprint nearest that.
            door, dbest = ring[0], float("inf")
            for i in range(len(ring) - 1):
                q = closest_on_segment(road, ring[i], ring[i + 1])
                d = dist(q, road)
                if d < dbest:
                    door, dbest = q, d
            business = bool(p.get("shop") or p.get("amenity") or p.get("office") or p.get("tourism") or p.get("craft"))
            b = p.get("building", "yes")
            kind = "business" if business or b in ("commercial", "retail", "industrial", "office", "school", "church", "public") \
                else ("apartments" if b == "apartments" else ("home" if b in HOMES or b == "yes" else "business"))
            out.append({"n": n, "street": street, "kind": kind, "x": round(cx, 1), "z": round(cz, 1),
                        "door": [round(door[0], 1), round(door[1], 1)], "road": [round(road[0], 1), round(road[1], 1)]})
    out.sort(key=lambda a: (a["street"], int("".join(ch for ch in a["n"] if ch.isdigit()) or 0), a["n"]))
    dest = os.path.join(city, "addresses.json")
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump({"_comment": "Street addresses for jobs, made by tools/make_addresses.py from the OSM chunks and roads. Don't edit by hand: run the tool again.",
                   "addresses": out}, fh, separators=(",", ":"), ensure_ascii=False)
        fh.write("\n")
    kinds = {}
    for a in out:
        kinds[a["kind"]] = kinds.get(a["kind"], 0) + 1
    print("%d addresses -> %s  %s" % (len(out), os.path.relpath(dest, ROOT), kinds))


if __name__ == "__main__":
    main()

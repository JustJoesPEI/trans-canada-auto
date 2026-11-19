#!/usr/bin/env python3
"""Convert an OpenStreetMap extract into the GeoJSON the game reads.

Input:  an OSM XML file (from the OSM API "map" call or JOSM) or an
        Overpass JSON file ("[out:json]").
Output: a GeoJSON FeatureCollection with three kinds of feature:
          kind = "road"      LineString, one per OSM way (clipped to the bbox)
          kind = "building"  Polygon, one per closed OSM building way
          kind = "point"     Point, traffic signals / stops / crossings / lamps

Every coordinate in the output is a real OSM coordinate, except for two
clearly-marked cleaning steps:
  * Roads are clipped to the bounding box. Where a way crosses the edge a new
    vertex is interpolated on the edge; its node id starts with "clip:".
  * Street junction nodes closer together than --merge-m metres (default 6) are
    merged to their average position, so the road mesher does not have to
    build a 4 m sliver of road between two almost-identical intersections.
    Merged ids are listed in metadata.merged_nodes.

Python 3 standard library only. Usage:
    python3 tools/osm_to_geojson.py raw/downtown.osm data/downtown.geojson \
        --bbox 46.2318,-63.1302,46.2378,-63.1212
"""

import argparse
import datetime
import json
import math
import sys
import xml.etree.ElementTree as ET

ROAD_TAGS = ("name", "highway", "oneway", "lanes", "width", "maxspeed",
             "surface", "sidewalk", "parking:both", "parking:left",
             "parking:right", "parking:lane:both", "lit", "junction")
BUILDING_TAGS = ("building", "building:levels", "height", "roof:shape",
                 "roof:levels", "roof:colour", "building:colour",
                 "building:material", "name", "addr:housenumber",
                 "addr:street", "shop", "amenity", "tourism", "office",
                 "historic", "heritage")
POINT_KEYS = {
    "highway": ("traffic_signals", "stop", "give_way", "crossing", "street_lamp"),
    "amenity": ("bench", "post_box", "waste_basket", "parking_entrance"),
    "natural": ("tree",),
}
# Junctions are only merged between public streets (not lanes or driveways),
# so a parking-lot entrance never pulls a real intersection out of place.
STREETS = {"motorway", "trunk", "primary", "secondary", "tertiary",
           "unclassified", "residential", "living_street",
           "motorway_link", "trunk_link", "primary_link", "secondary_link",
           "tertiary_link"}


def load_osm(path):
    """Return (nodes, ways). nodes: id -> (lat, lon, tags). ways: list of (id, [node ids], tags)."""
    nodes, ways = {}, []
    if path.endswith(".json"):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for el in data.get("elements", []):
            if el["type"] == "node":
                nodes[str(el["id"])] = (el["lat"], el["lon"], el.get("tags", {}))
            elif el["type"] == "way":
                ways.append((str(el["id"]), [str(n) for n in el.get("nodes", [])], el.get("tags", {})))
    else:
        root = ET.parse(path).getroot()
        for n in root.iter("node"):
            tags = {t.get("k"): t.get("v") for t in n.iter("tag")}
            nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")), tags)
        for w in root.iter("way"):
            tags = {t.get("k"): t.get("v") for t in w.iter("tag")}
            refs = [nd.get("ref") for nd in w.findall("nd")]
            ways.append((w.get("id"), refs, tags))
    return nodes, ways


def metres_per_degree(lat):
    phi = math.radians(lat)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    return m_lat, m_lon


def clip_segment(p0, p1, box):
    """Liang-Barsky in (lat, lon). Returns (t0, t1) or None."""
    s, w, n, e = box
    (y0, x0), (y1, x1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x0 - w), (dx, e - x0), (-dy, y0 - s), (dy, n - y0)):
        if p == 0:
            if q < 0:
                return None
            continue
        r = q / p
        if p < 0:
            if r > t1:
                return None
            t0 = max(t0, r)
        else:
            if r < t0:
                return None
            t1 = min(t1, r)
    return t0, t1


def clip_way(way_id, refs, nodes, box):
    """Split a way into pieces inside the box. Each piece is a list of (node_id, lat, lon)."""
    pieces, cur, clip_n = [], [], 0
    pts = [(r, nodes[r][0], nodes[r][1]) for r in refs if r in nodes]
    for i in range(len(pts) - 1):
        (ia, la, oa), (ib, lb, ob) = pts[i], pts[i + 1]
        res = clip_segment((la, oa), (lb, ob), box)
        if res is None:
            if cur:
                pieces.append(cur)
                cur = []
            continue
        t0, t1 = res
        if t0 > 0:
            if cur:
                pieces.append(cur)
            clip_n += 1
            cur = [("clip:%s:%d" % (way_id, clip_n), la + (lb - la) * t0, oa + (ob - oa) * t0)]
        elif not cur:
            cur = [(ia, la, oa)]
        if t1 < 1:
            clip_n += 1
            cur.append(("clip:%s:%d" % (way_id, clip_n), la + (lb - la) * t1, oa + (ob - oa) * t1))
            pieces.append(cur)
            cur = []
        else:
            cur.append((ib, lb, ob))
    if cur:
        pieces.append(cur)
    return [p for p in pieces if len(p) >= 2]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--bbox", required=True, help="south,west,north,east in degrees")
    ap.add_argument("--merge-m", type=float, default=6.0, help="merge road junctions closer than this (metres)")
    ap.add_argument("--retrieved", default=None, help="date the OSM data was downloaded (YYYY-MM-DD)")
    args = ap.parse_args()

    box = tuple(float(v) for v in args.bbox.split(","))
    s, w, n, e = box
    nodes, ways = load_osm(args.input)
    m_lat, m_lon = metres_per_degree((s + n) / 2)

    # --- roads ---------------------------------------------------------------
    roads = []  # dicts: id, tags, pts [(nid, lat, lon)]
    for wid, refs, tags in ways:
        if "highway" not in tags or "area" in tags and tags["area"] == "yes":
            continue
        for k, piece in enumerate(clip_way(wid, refs, nodes, box)):
            roads.append({"id": wid if k == 0 else "%s#%d" % (wid, k), "osm_id": wid, "tags": tags, "pts": piece})

    # Junction merge (drivable roads only).
    use = {}
    for r in roads:
        if r["tags"]["highway"] not in STREETS:
            continue
        ids = [p[0] for p in r["pts"]]
        for i, nid in enumerate(ids):
            use.setdefault(nid, set()).add(r["id"])
            if i in (0, len(ids) - 1):
                use[nid].add(r["id"] + "#end")
    junctions = {nid for nid, s_ in use.items() if len(s_) >= 2}
    pos = {}
    for r in roads:
        for nid, la, lo in r["pts"]:
            pos[nid] = (la, lo)
    parent = {j: j for j in junctions}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    jl = sorted(junctions)
    for i, a in enumerate(jl):
        for b in jl[i + 1:]:
            dy = (pos[a][0] - pos[b][0]) * m_lat
            dx = (pos[a][1] - pos[b][1]) * m_lon
            if dx * dx + dy * dy < args.merge_m ** 2:
                ra, rb = find(a), find(b)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
    groups = {}
    for j in jl:
        groups.setdefault(find(j), []).append(j)
    remap, merged = {}, []
    for rep, members in groups.items():
        if len(members) < 2:
            continue
        la = sum(pos[m][0] for m in members) / len(members)
        lo = sum(pos[m][1] for m in members) / len(members)
        for m in members:
            remap[m] = (rep, la, lo)
        merged.append(sorted(members))

    features = []
    for r in roads:
        pts = []
        for nid, la, lo in r["pts"]:
            if nid in remap:
                nid, la, lo = remap[nid]
            if pts and pts[-1][0] == nid:
                continue
            pts.append((nid, la, lo))
        if len(pts) < 2:
            continue
        props = {"kind": "road", "osm_id": r["osm_id"], "id": r["id"],
                 "nodes": [p[0] for p in pts]}
        for k in ROAD_TAGS:
            if k in r["tags"]:
                props[k] = r["tags"][k]
        features.append({"type": "Feature", "properties": props,
                         "geometry": {"type": "LineString",
                                      "coordinates": [[round(p[2], 7), round(p[1], 7)] for p in pts]}})

    # --- buildings -------------------------------------------------------------
    for wid, refs, tags in ways:
        if "building" not in tags or len(refs) < 4 or refs[0] != refs[-1]:
            continue
        ring = [nodes[r] for r in refs if r in nodes]
        if len(ring) != len(refs):
            continue  # incomplete way at the edge of the download
        clat = sum(p[0] for p in ring[:-1]) / (len(ring) - 1)
        clon = sum(p[1] for p in ring[:-1]) / (len(ring) - 1)
        if not (s <= clat <= n and w <= clon <= e):
            continue
        props = {"kind": "building", "osm_id": wid}
        for k in BUILDING_TAGS:
            if k in tags:
                props[k] = tags[k]
        features.append({"type": "Feature", "properties": props,
                         "geometry": {"type": "Polygon",
                                      "coordinates": [[[round(p[1], 7), round(p[0], 7)] for p in ring]]}})

    # --- points ----------------------------------------------------------------
    for nid, (la, lo, tags) in nodes.items():
        if not (s <= la <= n and w <= lo <= e):
            continue
        hit = None
        for key, vals in POINT_KEYS.items():
            if tags.get(key) in vals:
                hit = "%s=%s" % (key, tags[key])
                break
        if not hit:
            continue
        props = {"kind": "point", "osm_id": nid, "type": hit}
        props.update({k: v for k, v in tags.items() if k in ("crossing", "direction", "highway", "name")})
        features.append({"type": "Feature", "properties": props,
                         "geometry": {"type": "Point", "coordinates": [round(lo, 7), round(la, 7)]}})

    out = {
        "type": "FeatureCollection",
        "metadata": {
            "source": "OpenStreetMap",
            "attribution": "© OpenStreetMap contributors",
            "license": "Open Database License (ODbL) 1.0, https://www.openstreetmap.org/copyright",
            "bbox_s_w_n_e": list(box),
            "retrieved": args.retrieved or datetime.date.today().isoformat(),
            "generator": "tools/osm_to_geojson.py",
            "merged_nodes": merged,
        },
        "features": features,
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), ensure_ascii=False)
        f.write("\n")
    kinds = {}
    for ft in features:
        kinds[ft["properties"]["kind"]] = kinds.get(ft["properties"]["kind"], 0) + 1
    print("wrote %s: %s, merged %d junction groups" % (args.output, kinds, len(merged)), file=sys.stderr)


if __name__ == "__main__":
    main()

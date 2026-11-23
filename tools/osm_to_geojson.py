#!/usr/bin/env python3
"""Convert an OpenStreetMap extract into the map data the game reads.

Input:  a clipped .osm.pbf (from tools/clip_osm.py; needs pyosmium), an OSM
        XML file (from the OSM API "map" call or JOSM) or an Overpass JSON file.
Output: a folder (data/city/) holding
          roads.geojson        every highway line (streets, ramps, paths),
                               clipped to the box, kind = "road", plus the
                               traffic signals, stop signs and crossings
          chunks/X_Z.geojson   buildings, ground areas and street furniture,
                               split into CHUNK-metre squares of the game
                               world (X, Z = square number east and south of
                               the origin). The game loads a square when the
                               player comes near it.
          index.json           the box, the chunk size and which chunks exist

Every coordinate in the output is a real OSM coordinate, except for two
clearly-marked cleaning steps:
  * Roads are clipped to the bounding box. Where a way crosses the edge a new
    vertex is interpolated on the edge; its node id starts with "clip:".
  * Street junction nodes closer together than --merge-m metres (default 6) are
    merged to their average position, so the road mesher does not have to
    build a 4 m sliver of road between two almost-identical intersections.
    So are two junctions joined directly by a piece of street shorter than
    --merge-link-m (default 12).
    Merged ids are listed in metadata.merged_nodes. Junctions on roundabouts
    and highway ramps are never merged: their geometry is the point.

Buildings and points go in the square their middle is in. Ground areas go in
every square they overlap, so each square can paint and plant its own part.
Multipolygon relations (big parks, buildings with courtyards) come through
from .pbf input as their outer ring.

Usage:
    python3 tools/osm_to_geojson.py raw/charlottetown.osm.pbf data/city \
        --bbox 46.2215,-63.1860,46.2795,-63.0970
"""

import argparse
import datetime
import json
import math
import os
import shutil
import sys
import xml.etree.ElementTree as ET

ROAD_TAGS = ("name", "highway", "oneway", "lanes", "width", "maxspeed",
             "surface", "sidewalk", "parking:both", "parking:left",
             "parking:right", "parking:lane:both", "lit", "junction",
             "bridge", "tunnel", "layer", "ref", "footway", "service", "area")
BUILDING_TAGS = ("building", "building:levels", "height", "roof:shape",
                 "roof:levels", "roof:colour", "building:colour",
                 "building:material", "name", "addr:housenumber",
                 "addr:street", "shop", "amenity", "tourism", "office",
                 "historic", "heritage", "brand", "man_made")
POINT_KEYS = {
    "highway": ("traffic_signals", "stop", "give_way", "crossing", "street_lamp"),
    "amenity": ("bench", "post_box", "waste_basket", "parking_entrance"),
    "natural": ("tree",),
}
# Ground areas worth drawing: (tag, values). Order here is not draw order;
# the game and tools/make_ground_mask.py decide that from the "area" type.
AREA_KEYS = {
    "amenity": ("parking", "fountain", "school", "university", "college"),
    "landuse": ("grass", "village_green", "flowerbed", "forest", "religious",
                "residential", "commercial", "retail", "industrial", "cemetery",
                "recreation_ground", "meadow", "farmland", "paved"),
    "leisure": ("park", "garden", "playground", "outdoor_seating", "pitch",
                "sports_centre", "track", "common", "golf_course", "marina"),
    "natural": ("wood", "scrub", "grassland", "water", "wetland", "sand", "beach"),
    "highway": ("pedestrian", "footway"),  # only when area=yes
    "area:highway": ("pedestrian", "footway"),
    "place": ("square",),
}
AREA_TAGS = ("name", "surface", "parking", "access", "leaf_type", "sport")

# Junctions are only merged between public streets (not lanes or driveways),
# so a parking-lot entrance never pulls a real intersection out of place.
STREETS = {"motorway", "trunk", "primary", "secondary", "tertiary",
           "unclassified", "residential", "living_street",
           "motorway_link", "trunk_link", "primary_link", "secondary_link",
           "tertiary_link"}
LINKS = {"motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
SKIP_HIGHWAYS = {"proposed", "construction", "abandoned", "razed", "platform",
                 "bus_stop", "elevator", "corridor", "raceway"}


def load_osm(path):
    """Return (nodes, ways, polys).
    nodes: id -> (lat, lon, tags). ways: list of (id, [node ids], tags).
    polys: multipolygon relations as (id, [(lat, lon), ...] outer ring, tags)."""
    nodes, ways, polys = {}, [], []
    if path.endswith(".pbf"):
        import osmium
        for o in osmium.FileProcessor(path, osmium.osm.NODE | osmium.osm.WAY).with_locations():
            if o.is_node():
                nodes[str(o.id)] = (o.location.lat, o.location.lon, dict(o.tags))
            else:
                ways.append((str(o.id), [str(n.ref) for n in o.nodes], dict(o.tags)))
        for a in osmium.FileProcessor(path).with_areas():
            if not a.is_area() or a.from_way():
                continue
            tags = dict(a.tags)
            if "building" not in tags and not any(tags.get(k) in v for k, v in AREA_KEYS.items()):
                continue
            # Take the biggest outer ring; inner courtyards are not modelled.
            best = []
            for outer in a.outer_rings():
                ring = [(nd.lat, nd.lon) for nd in outer]
                if len(ring) > len(best):
                    best = ring
            if len(best) >= 4:
                polys.append(("r%d" % a.orig_id(), best, tags))
    elif path.endswith(".json"):
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
    return nodes, ways, polys


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
    ap.add_argument("output", help="output folder, e.g. data/city")
    ap.add_argument("--bbox", required=True, help="south,west,north,east in degrees")
    ap.add_argument("--merge-m", type=float, default=6.0, help="merge road junctions closer than this (metres)")
    ap.add_argument("--merge-link-m", type=float, default=12.0, help="also merge two junctions joined by a street piece shorter than this")
    ap.add_argument("--chunk", type=float, default=200.0, help="chunk size in metres")
    ap.add_argument("--config", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "map_config.json"))
    ap.add_argument("--retrieved", default=None, help="date the OSM data was extracted (YYYY-MM-DD)")
    args = ap.parse_args()

    box = tuple(float(v) for v in args.bbox.split(","))
    s, w, n, e = box
    cfg = json.load(open(args.config, encoding="utf-8"))
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    nodes, ways, polys = load_osm(args.input)
    # The game's own projection (scripts/world/geo_projection.gd), around the origin.
    m_lat, m_lon = metres_per_degree(lat0)

    def ground(lat, lon):
        return ((lon - lon0) * m_lon, -(lat - lat0) * m_lat)

    def chunk_of(lat, lon):
        x, z = ground(lat, lon)
        return (int(math.floor(x / args.chunk)), int(math.floor(z / args.chunk)))

    # --- roads ---------------------------------------------------------------
    roads = []  # dicts: id, tags, pts [(nid, lat, lon)]
    for wid, refs, tags in ways:
        if "highway" not in tags or tags.get("area") == "yes" or tags["highway"] in SKIP_HIGHWAYS:
            continue
        for k, piece in enumerate(clip_way(wid, refs, nodes, box)):
            roads.append({"id": wid if k == 0 else "%s#%d" % (wid, k), "osm_id": wid, "tags": tags, "pts": piece})

    # Junction merge (drivable roads only), using a grid so it stays quick
    # for a whole city.
    use = {}
    fixed = set()
    for r in roads:
        hw = r["tags"]["highway"]
        if hw not in STREETS:
            continue
        ids = [p[0] for p in r["pts"]]
        for i, nid in enumerate(ids):
            use.setdefault(nid, set()).add(r["id"])
            if i in (0, len(ids) - 1):
                use[nid].add(r["id"] + "#end")
            if hw in LINKS or r["tags"].get("junction") in ("roundabout", "circular"):
                fixed.add(nid)
    junctions = {nid for nid, s_ in use.items() if len(s_) >= 2 and nid not in fixed}
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

    cell = max(args.merge_m, 1.0)
    grid = {}
    for j in sorted(junctions):
        x, z = ground(*pos[j])
        grid.setdefault((int(x // cell), int(z // cell)), []).append((j, x, z))
    for (cx, cz), items in grid.items():
        near = []
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                near.extend(grid.get((cx + dx, cz + dz), []))
        for a, ax, az in items:
            for b, bx, bz in near:
                if a < b and (ax - bx) ** 2 + (az - bz) ** 2 < args.merge_m ** 2:
                    ra, rb = find(a), find(b)
                    if ra != rb:
                        parent[max(ra, rb)] = min(ra, rb)
    # Two junctions joined directly by a stretch of street shorter than
    # --merge-link-m (a short stub where a divided road splits right beside a
    # crossroads, say) are merged too: the curb maths can't fit a crossroads
    # into ten metres.
    for r in roads:
        if r["tags"]["highway"] not in STREETS:
            continue
        # Walk the way from junction to junction, adding up the length between.
        last = None
        run = 0.0
        prev = None
        for nid, la, lo in r["pts"]:
            x, z = ground(la, lo)
            if prev is not None:
                run += math.hypot(x - prev[0], z - prev[1])
            prev = (x, z)
            if nid in junctions:
                if last is not None and run < args.merge_link_m and find(last) != find(nid):
                    ra, rb = find(last), find(nid)
                    parent[max(ra, rb)] = min(ra, rb)
                last = nid
                run = 0.0
    groups = {}
    for j in sorted(junctions):
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

    road_features = []
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
        road_features.append({"type": "Feature", "properties": props,
                              "geometry": {"type": "LineString",
                                           "coordinates": [[round(p[2], 7), round(p[1], 7)] for p in pts]}})

    chunks = {}

    def put(key, feature):
        chunks.setdefault(key, []).append(feature)

    def ring_of(refs):
        ring = [nodes[r] for r in refs if r in nodes]
        if len(ring) != len(refs):
            return None
        return [(p[0], p[1]) for p in ring]

    def centre(ring):
        k = len(ring) - 1 if ring[0] == ring[-1] else len(ring)
        return (sum(p[0] for p in ring[:k]) / k, sum(p[1] for p in ring[:k]) / k)

    def poly_feature(props, ring):
        if ring[0] != ring[-1]:
            ring = ring + [ring[0]]
        return {"type": "Feature", "properties": props,
                "geometry": {"type": "Polygon",
                             "coordinates": [[[round(p[1], 7), round(p[0], 7)] for p in ring]]}}

    # --- buildings -------------------------------------------------------------
    shapes = [(wid, ring_of(refs), tags) for wid, refs, tags in ways
              if len(refs) >= 4 and refs[0] == refs[-1]]
    shapes += [(rid, ring, tags) for rid, ring, tags in polys]
    n_buildings = 0
    for wid, ring, tags in shapes:
        if ring is None or "building" not in tags:
            continue
        clat, clon = centre(ring)
        if not (s <= clat <= n and w <= clon <= e):
            continue
        props = {"kind": "building", "osm_id": wid}
        for k in BUILDING_TAGS:
            if k in tags:
                props[k] = tags[k]
        put(chunk_of(clat, clon), poly_feature(props, ring))
        n_buildings += 1

    # --- ground areas ------------------------------------------------------------
    n_areas = 0
    for wid, ring, tags in shapes:
        if ring is None or "building" in tags:
            continue
        hit = None
        for key, vals in AREA_KEYS.items():
            if tags.get(key) in vals:
                if key == "highway" and tags.get("area") != "yes":
                    continue
                hit = "%s=%s" % (key, tags[key])
                break
        if not hit:
            continue
        lats = [p[0] for p in ring]
        lons = [p[1] for p in ring]
        if max(lats) < s or min(lats) > n or max(lons) < w or min(lons) > e:
            continue
        props = {"kind": "area", "osm_id": wid, "type": hit}
        for k in AREA_TAGS:
            if k in tags:
                props[k] = tags[k]
        feat = poly_feature(props, ring)
        c0 = chunk_of(max(lats), min(lons))
        c1 = chunk_of(min(lats), max(lons))
        for cx in range(c0[0], c1[0] + 1):
            for cz in range(c0[1], c1[1] + 1):
                put((cx, cz), feat)
        n_areas += 1

    # --- points ----------------------------------------------------------------
    n_points = 0
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
        feat = {"type": "Feature", "properties": props,
                "geometry": {"type": "Point", "coordinates": [round(lo, 7), round(la, 7)]}}
        if hit.startswith("highway="):
            # Signals, stops and crossings belong to the street network
            # (a junction can sit on the edge of a chunk), so they go with it.
            road_features.append(feat)
        else:
            put(chunk_of(la, lo), feat)
        n_points += 1

    metadata = {
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "license": "Open Database License (ODbL) 1.0, https://www.openstreetmap.org/copyright",
        "bbox_s_w_n_e": list(box),
        "retrieved": args.retrieved or datetime.date.today().isoformat(),
        "generator": "tools/osm_to_geojson.py",
    }
    out = args.output
    if os.path.isdir(os.path.join(out, "chunks")):
        shutil.rmtree(os.path.join(out, "chunks"))
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    with open(os.path.join(out, "roads.geojson"), "w", encoding="utf-8") as f:
        json.dump({"type": "FeatureCollection", "metadata": dict(metadata, merged_nodes=merged),
                   "features": road_features}, f, separators=(",", ":"), ensure_ascii=False)
        f.write("\n")
    for (cx, cz), feats in sorted(chunks.items()):
        with open(os.path.join(out, "chunks", "%d_%d.geojson" % (cx, cz)), "w", encoding="utf-8") as f:
            json.dump({"type": "FeatureCollection", "features": feats}, f, separators=(",", ":"), ensure_ascii=False)
            f.write("\n")
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(dict(metadata, chunk_size=args.chunk,
                       chunks=sorted("%d_%d" % k for k in chunks)), f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("wrote %s: %d roads, %d buildings, %d areas, %d points in %d chunks; merged %d junction groups"
          % (out, sum(1 for f in road_features if f["properties"]["kind"] == "road"), n_buildings, n_areas, n_points, len(chunks), len(merged)), file=sys.stderr)


if __name__ == "__main__":
    main()

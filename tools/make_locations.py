#!/usr/bin/env python3
"""Write data/city/locations.json: the named places shown on the game map.

    python3 tools/make_locations.py

Reads the city chunks (data/city/chunks/*.geojson) and data/map_config.json
and keeps the places worth finding on a map, one entry each:

  * parks, squares, schools and campuses, golf courses, cemeteries, ponds,
    marinas, racetracks and sports grounds (OSM areas, by name),
  * civic buildings: churches, museums, theatres, libraries, the courthouse
    and the hand-described landmarks in map_config.json "landmarks" that
    aren't shops,
  * businesses of the made-up world brands (map_config.json "brands"),
    under the brand's name: the same exact match on the OSM brand or name
    that scripts/world/building_generator.gd uses, or a landmark's "brand".

Real chain names never reach the map: a business is only listed under a
world brand, and other shops aren't listed. "Charlottetown" reads
"Charlatown", as it does on the signs.

Each entry: {"name", "kind", "x", "z"} (game metres, +x east, +z south, the
same projection as scripts/world/geo_projection.gd). Kinds: park, school,
golf, cemetery, water, marina, sport, landmark, church, coffee, food, gas,
grocery, shop, bank, hotel, dealer, cinema. scripts/ui/world_map.gd draws
them; the police station and the car washes come from the game itself.
Run it again after refreshing the OSM data or the brands.
"""

import glob
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

AREA_KINDS = {
    "leisure=park": "park", "leisure=garden": "park", "place=square": "park",
    "landuse=village_green": "park", "landuse=recreation_ground": "park",
    "amenity=school": "school", "amenity=university": "school", "amenity=college": "school",
    "leisure=golf_course": "golf", "landuse=cemetery": "cemetery",
    "natural=water": "water", "leisure=marina": "marina",
    "leisure=track": "sport", "leisure=sports_centre": "sport", "leisure=stadium": "sport",
}
CIVIC = {
    "place_of_worship": "church", "museum": "landmark", "theatre": "landmark",
    "arts_centre": "landmark", "library": "landmark", "courthouse": "landmark",
    "townhall": "landmark", "college": "school", "university": "school",
}
BRAND_KINDS = {
    "coffee": "coffee", "burgers": "food", "pizza": "food", "grocery": "grocery",
    "gas": "gas", "big box": "shop", "store": "shop", "pharmacy": "shop",
    "bank": "bank", "hotel": "hotel", "car dealer": "dealer", "cinema": "cinema",
}
# Small areas aren't worth a name on the map (m², by kind; default 0).
MIN_AREA = {"park": 2500.0, "sport": 4000.0, "water": 1500.0}


def projection(cfg):
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    return lambda lon, lat: ((lon - lon0) * m_lon, -(lat - lat0) * m_lat)


def ring_of(geom):
    if geom.get("type") == "Polygon":
        return geom["coordinates"][0]
    if geom.get("type") == "MultiPolygon":
        return max((p[0] for p in geom["coordinates"]), key=len)
    if geom.get("type") == "Point":
        return [geom["coordinates"]]
    return []


def centre_area(pts):
    """Centroid and area of a ring (the mean for a point or a line)."""
    if len(pts) < 3:
        n = max(1, len(pts))
        return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n), 0.0
    a = cx = cz = 0.0
    for i in range(len(pts)):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % len(pts)]
        c = x0 * z1 - x1 * z0
        a += c
        cx += (x0 + x1) * c
        cz += (z0 + z1) * c
    if abs(a) < 1e-6:
        return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)), 0.0
    return (cx / (3 * a), cz / (3 * a)), abs(a) * 0.5


def island_name(name):
    return name.replace("Charlottetown", "Charlatown")


def main():
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    to_ground = projection(cfg)
    landmarks = {k: v for k, v in cfg.get("landmarks", {}).items() if not k.startswith("_")}
    brand_for = {}
    brand_kind = {}
    for name, b in cfg.get("brands", {}).items():
        if name.startswith("_"):
            continue
        brand_kind[name] = BRAND_KINDS.get(b.get("kind", ""), "shop")
        for real in b.get("replaces", []):
            brand_for[real] = name
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    # name|kind -> [x, z, area]: the biggest piece of a place split over
    # chunks (or over several OSM areas) stands for it.
    found = {}

    def add(name, kind, ring, site=""):
        if not ring:
            return
        pts = [to_ground(p[0], p[1]) for p in ring]
        (x, z), area = centre_area(pts)
        if 0.0 < area < MIN_AREA.get(kind, 0.0):
            return
        # A chain's stores are told apart by building (`site`, the OSM id),
        # so every Ervin's is listed, not only the biggest.
        key = "%s|%s|%s" % (name, kind, site)
        if key not in found or area > found[key][2]:
            found[key] = [x, z, area]

    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        for f in json.load(open(path, encoding="utf-8"))["features"]:
            p = f["properties"]
            geom = f.get("geometry") or {}
            if geom.get("type") == "LineString":
                continue
            ring = ring_of(geom)
            osm = str(p.get("osm_id", ""))
            lm = landmarks.get(osm, {})
            # A world brand: the landmark's, else the OSM brand or name's.
            brand = lm.get("brand") if lm.get("brand") in brand_kind else None
            for key in (p.get("brand", ""), p.get("name", "")):
                if brand is None and key and key in brand_for:
                    brand = brand_for[key]
            if brand:
                add(brand, brand_kind[brand], ring, osm)
                continue
            name = p.get("name", "")
            if p.get("kind") == "area" and name and p.get("type") in AREA_KINDS:
                add(island_name(name), AREA_KINDS[p["type"]], ring)
            elif p.get("kind") == "building":
                amenity = p.get("amenity", "")
                if amenity in CIVIC and name:
                    add(island_name(name), CIVIC[amenity], ring)
                elif p.get("tourism") == "museum" and name:
                    add(island_name(name), "landmark", ring)
                elif lm and lm.get("shop") is False and lm.get("style") in ("sandstone", "brick", "church"):
                    # A described landmark: its name up to the first comma
                    # (the rest says where it is, for whoever edits it).
                    label = lm.get("sign") or lm["name"].split(",")[0]
                    add(island_name(label), "church" if lm.get("style") == "church" else "landmark", ring)
                elif lm.get("style") == "church":
                    add(island_name(lm["name"].split(",")[0]), "church", ring)

    out = []
    for key, (x, z, _area) in found.items():
        name, kind, _site = key.split("|")
        out.append({"name": name, "kind": kind, "x": round(x, 1), "z": round(z, 1)})
    # The same chain twice is two places: keep both. But one place found
    # as two kinds (a school that's also a described landmark) keeps the
    # more particular kind, and two names for one spot ("Red Shores
    # Racetrack" and "Red Shores Racetrack & Casino") keep the longer.
    rank = lambda e: 1 if e["kind"] == "landmark" else 0
    out.sort(key=lambda e: (rank(e), -len(e["name"])))
    kept = []
    for e in out:
        if not any(math.hypot(e["x"] - k["x"], e["z"] - k["z"]) < 150.0
                   and (e["name"] == k["name"] or (e["kind"] == k["kind"] and k["name"].startswith(e["name"])))
                   for k in kept):
            kept.append(e)
    out = sorted(kept, key=lambda e: (e["kind"], e["name"], e["x"]))
    dest = os.path.join(city, "locations.json")
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump({"_comment": "Named places for the game map, made by tools/make_locations.py from the OSM chunks and map_config.json. Don't edit by hand: run the tool again.",
                   "locations": out}, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    kinds = {}
    for e in out:
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
    print("%d locations -> %s  %s" % (len(out), os.path.relpath(dest, ROOT), kinds))


if __name__ == "__main__":
    main()

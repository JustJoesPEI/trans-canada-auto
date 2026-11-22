#!/usr/bin/env python3
"""Paint the OSM ground areas into images the terrain shader reads.

Lawns and parks, parking lots and driveways, stone-paved squares and paths
are drawn into RGBA images:
    R = grass, G = parking and driveways (asphalt), B = plaza (stone),
    A = path: 255 brick footpath, 100 gravel trail
Anything left blank is ordinary rough grass. Because the
terrain mesh reads these, the areas follow the real slope with no extra
geometry. Yards in residential areas, school grounds, cemeteries and
playing fields are lawn; commercial and industrial land is asphalt.

Two outputs:
  * data/city/masks/X_Z.png, one per map chunk (same squares as
    data/city/chunks), at --resolution metres per pixel. The game loads the
    ones near the player.
  * data/ground_mask.png, the whole map at --coarse metres per pixel, for
    the low-detail ground further away.

Run after osm_to_geojson.py and fetch_elevation.py. Needs Pillow.

    python3 tools/make_ground_mask.py --resolution 0.5 --coarse 4
"""

import argparse
import glob
import json
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Must match the categories terrain_ground.gdshader draws.
YARDS = {"landuse=residential", "landuse=cemetery", "landuse=recreation_ground", "landuse=meadow",
         "landuse=farmland", "amenity=school", "amenity=university", "amenity=college", "leisure=common",
         "leisure=golf_course", "natural=wetland"}
BARE = {"landuse=commercial", "landuse=retail", "landuse=industrial", "landuse=paved"}
GRASS = {"landuse=grass", "landuse=village_green", "landuse=flowerbed", "landuse=religious",
         "landuse=forest", "leisure=park", "leisure=garden", "leisure=playground", "natural=wood",
         "natural=scrub", "natural=grassland", "leisure=pitch", "leisure=sports_centre"}
PLAZA = {"highway=pedestrian", "highway=footway", "area:highway=pedestrian", "area:highway=footway",
         "place=square", "leisure=outdoor_seating", "amenity=fountain", "leisure=track"}
# Lines painted as paths: width in metres and alpha (255 brick, 100 gravel).
PATHS = {"footway": (2.2, 255), "pedestrian": (4.0, 255), "steps": (2.0, 255),
         "path": (2.0, 100), "cycleway": (3.0, 100), "track": (3.0, 100), "bridleway": (2.0, 100)}
# Service roads aren't built as streets; they're painted as asphalt.
SERVICE = {"driveway": 3.2, "parking_aisle": 6.0, "alley": 4.0, "drive-through": 3.5, "": 5.0}


def kind(props):
    surface = props.get("surface", "")
    t = props.get("type", "")
    if surface == "grass":
        return "grass"
    if surface in ("paving_stones", "brick", "sett", "concrete") and t != "amenity=parking":
        return "plaza"
    if t == "amenity=parking" or surface == "asphalt":
        return "parking"
    if t in GRASS:
        return "grass"
    if t in PLAZA:
        return "plaza"
    if t in YARDS:
        return "yard"
    if t in BARE:
        return "bare"
    return ""


def load(city):
    roads = [f for f in json.load(open(os.path.join(city, "roads.geojson"), encoding="utf-8"))["features"]
             if f["properties"]["kind"] == "road"]
    areas = {}
    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        for f in json.load(open(path, encoding="utf-8"))["features"]:
            if f["properties"]["kind"] == "area":
                areas[f["properties"]["osm_id"]] = f
    return roads, list(areas.values())


def paint(w, h, to_px, res, roads, areas):
    """One RGBA mask of w x h pixels; to_px maps (lon, lat) to pixel (x, y)."""
    layers = {k: Image.new("L", (w, h), 0) for k in ("grass", "parking", "plaza", "path")}
    draws = {k: ImageDraw.Draw(im) for k, im in layers.items()}
    # Big areas first, so a small park inside a residential area wins, and a
    # parking lot always wins over the lawn round it. Commercial and
    # industrial land is mostly parking and yards of asphalt in real life,
    # so it's painted as asphalt under whatever is mapped on top.
    order = ("yard", "grass", "bare", "parking", "plaza")
    for want in order:
        for f in areas:
            k = kind(f["properties"])
            if k != want:
                continue
            ring = [to_px(c) for c in f["geometry"]["coordinates"][0]]
            if k in ("yard", "grass"):
                draws["grass"].polygon(ring, fill=255)
                if k == "grass":
                    draws["parking"].polygon(ring, fill=0)
            elif k in ("bare", "parking"):
                draws["parking"].polygon(ring, fill=255)
                draws["grass"].polygon(ring, fill=0)
            else:
                draws["plaza"].polygon(ring, fill=255)
                draws["parking"].polygon(ring, fill=0)
                draws["grass"].polygon(ring, fill=0)
    for f in roads:
        p = f["properties"]
        hw = p.get("highway")
        pts = [to_px(c) for c in f["geometry"]["coordinates"]]
        if hw == "service":
            width = SERVICE.get(p.get("service", ""), SERVICE[""])
            draws["parking"].line(pts, fill=255, width=max(1, int(round(width / res))), joint="curve")
            draws["grass"].line(pts, fill=0, width=max(1, int(round(width / res))), joint="curve")
        elif hw in PATHS and p.get("area") != "yes" and p.get("footway") not in ("sidewalk", "crossing"):
            width, alpha = PATHS[hw]
            draws["path"].line(pts, fill=alpha, width=max(1, int(round(width / res))), joint="curve")
    return Image.merge("RGBA", (layers["grass"], layers["parking"], layers["plaza"], layers["path"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--resolution", type=float, default=0.5, help="metres per pixel in the chunk masks")
    ap.add_argument("--coarse", type=float, default=4.0, help="metres per pixel in the whole-map mask")
    args = ap.parse_args()
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    index = json.load(open(os.path.join(city, "index.json"), encoding="utf-8"))
    el = json.load(open(os.path.join(ROOT, "data", "elevation.json"), encoding="utf-8"))
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    roads, areas = load(city)

    def world(c):
        return ((c[0] - lon0) * m_lon, -(c[1] - lat0) * m_lat)

    def bounds(f):
        cs = f["geometry"]["coordinates"]
        if f["geometry"]["type"] == "Polygon":
            cs = cs[0]
        xs, zs = zip(*(world(c) for c in cs))
        return min(xs), min(zs), max(xs), max(zs)

    # Whole map, coarse.
    ox, oz = el["origin_x"], el["origin_z"]
    width_m = (el["nx"] - 1) * el["spacing"]
    depth_m = (el["nz"] - 1) * el["spacing"]
    res = args.coarse
    w, h = int(round(width_m / res)), int(round(depth_m / res))
    img = paint(w, h, lambda c: ((world(c)[0] - ox) / res, (world(c)[1] - oz) / res), res, roads, areas)
    img.save(os.path.join(ROOT, "data", "ground_mask.png"), optimize=True)
    print("wrote data/ground_mask.png: %d x %d px at %.1f m per pixel" % (w, h, res))

    # One mask per chunk.
    size = float(index["chunk_size"])
    out_dir = os.path.join(city, "masks")
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, "*.png")):
        os.remove(old)
    road_box = [(bounds(f), f) for f in roads if f["properties"].get("highway") in PATHS or f["properties"].get("highway") == "service"]
    res = args.resolution
    px = int(round(size / res))
    written = 0
    total = 0
    for key in index["chunks"]:
        cx, cz = (int(v) for v in key.split("_"))
        x0, z0 = cx * size, cz * size
        feats = json.load(open(os.path.join(city, "chunks", key + ".geojson"), encoding="utf-8"))["features"]
        chunk_areas = [f for f in feats if f["properties"]["kind"] == "area"]
        pad = 6.0
        chunk_roads = [f for (b, f) in road_box if b[2] > x0 - pad and b[0] < x0 + size + pad and b[3] > z0 - pad and b[1] < z0 + size + pad]
        img = paint(px, px, lambda c: ((world(c)[0] - x0) / res, (world(c)[1] - z0) / res), res, chunk_roads, chunk_areas)
        if img.getbbox() is None:
            continue
        path = os.path.join(out_dir, key + ".png")
        img.save(path, optimize=True)
        written += 1
        total += os.path.getsize(path)
    print("wrote %d chunk masks in %s (%.1f MB) at %.2f m per pixel" % (written, out_dir, total / 1e6, res))


if __name__ == "__main__":
    main()

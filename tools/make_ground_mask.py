#!/usr/bin/env python3
"""Paint the OSM ground areas into an image the terrain shader reads.

Lawns and parks, parking lots, stone-paved squares and brick footpaths are
drawn into one RGBA image covering the same area as data/elevation.json:
    R = grass, G = parking, B = plaza (stone), A = path (brick)
Anything left blank is an ordinary lot. Because the terrain mesh reads this
image, the areas follow the real slope with no extra geometry.

Run after osm_to_geojson.py and fetch_elevation.py. Needs Pillow.

    python3 tools/make_ground_mask.py data/ground_mask.png --resolution 0.5
"""

import argparse
import json
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Must match the categories the game used to draw (see terrain_ground.gdshader).
GRASS = {"landuse=grass", "landuse=village_green", "landuse=flowerbed", "landuse=religious",
         "landuse=forest", "leisure=park", "leisure=garden", "leisure=playground", "natural=wood",
         "natural=scrub", "natural=grassland"}
PLAZA = {"highway=pedestrian", "highway=footway", "area:highway=pedestrian", "area:highway=footway",
         "place=square", "leisure=outdoor_seating", "amenity=fountain"}
PATHS = {"footway": 2.2, "pedestrian": 4.0, "path": 1.6, "steps": 2.0}


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
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    ap.add_argument("--resolution", type=float, default=0.5, help="metres per pixel")
    args = ap.parse_args()
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    gj = json.load(open(os.path.join(ROOT, cfg["geojson"].replace("res://", "")), encoding="utf-8"))
    el = json.load(open(os.path.join(ROOT, "data", "elevation.json"), encoding="utf-8"))
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    ox, oz = el["origin_x"], el["origin_z"]
    width_m = (el["nx"] - 1) * el["spacing"]
    depth_m = (el["nz"] - 1) * el["spacing"]
    res = args.resolution
    w = int(round(width_m / res))
    h = int(round(depth_m / res))

    def px(c):
        x = (c[0] - lon0) * m_lon
        z = -(c[1] - lat0) * m_lat
        return ((x - ox) / res, (z - oz) / res)

    layers = {k: Image.new("L", (w, h), 0) for k in ("grass", "parking", "plaza", "path")}
    draws = {k: ImageDraw.Draw(im) for k, im in layers.items()}
    # Areas in a stable order: parking first, then grass, then plazas on top.
    areas = [f for f in gj["features"] if f["properties"]["kind"] == "area"]
    for want in ("parking", "grass", "plaza"):
        for f in areas:
            if kind(f["properties"]) != want:
                continue
            ring = [px(c) for c in f["geometry"]["coordinates"][0]]
            draws[want].polygon(ring, fill=255)
            # A later, higher layer wins where areas overlap.
            for lower in ("parking", "grass"):
                if lower != want and ("parking", "grass", "plaza").index(lower) < ("parking", "grass", "plaza").index(want):
                    draws[lower].polygon(ring, fill=0)
    for f in gj["features"]:
        p = f["properties"]
        if p["kind"] == "road" and p.get("highway") in PATHS and p.get("area") != "yes":
            pts = [px(c) for c in f["geometry"]["coordinates"]]
            width = max(1, int(round(PATHS[p["highway"]] / res)))
            draws["path"].line(pts, fill=255, width=width, joint="curve")
    img = Image.merge("RGBA", (layers["grass"], layers["parking"], layers["plaza"], layers["path"]))
    img.save(args.output, optimize=True)
    print("wrote %s: %d x %d px at %.2f m per pixel" % (args.output, w, h, res))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Paint the OSM ground areas into images the terrain shader reads.

Lawns and parks, parking lots and driveways, stone-paved squares and paths
are drawn as four layers:
    R = grass, G = parking and driveways (asphalt),
    B = what else the ground is: 255 plaza (stone), 190 farm field
        (soil), 125 wetland, 60 sand (beaches, bunkers); one value per
        pixel, which the shader reads without blending,
    A = path: 255 brick footpath, 100 gravel trail
and packed into one byte a pixel (pack() below: a quarter of the graphics
memory of RGBA, and still exact), which terrain_ground.gdshader unpacks.
Anything left blank is ordinary rough grass. Because the
terrain mesh reads these, the areas follow the real slope with no extra
geometry. Yards in residential areas, school grounds, cemeteries and
playing fields are lawn; commercial and industrial land is asphalt.

The same areas are also written as what a tyre drives on (GroundMap): one
byte per square metre, a GroundMap kind (KINDS below), zlib-compressed, in
data/city/ground/X_Z.bin. Fields are mud, wetland is a bog, sand is soft.

Three outputs:
  * data/city/masks/X_Z.png, one per map chunk (same squares as
    data/city/chunks), at --resolution metres per pixel. The game loads the
    ones near the player.
  * data/ground_mask.png, the whole map at --coarse metres per pixel, for
    the low-detail ground further away.
  * data/city/ground/X_Z.bin, per chunk, what the ground is to drive on,
    a byte per metre.

Hand edits (data/edits.json, the map editor's) are laid over the OSM
areas the way the game lays them over its data: areas deleted or given new
tags or a new outline under "features" ("area:<osm id>"), and new areas in
"new_features" (kind "area", a "ring" of [longitude, latitude]). Run it
again after adding or changing an area in the editor; --chunks rewrites
only the squares named (and the whole-map mask), leaving the rest as they
are:

    python3 tools/make_ground_mask.py --chunks 6_-10,6_-11

Run after osm_to_geojson.py and fetch_elevation.py. Needs Pillow.
--repack packs masks written as RGBA (before the masks were packed) in
place, without painting anything again.

    python3 tools/make_ground_mask.py --resolution 0.5 --coarse 4
"""

import argparse
import glob
import json
import math
import os
import zlib

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Must match the categories terrain_ground.gdshader draws.
YARDS = {"landuse=residential", "landuse=cemetery", "landuse=recreation_ground", "landuse=meadow",
         "amenity=school", "amenity=university", "amenity=college", "leisure=common",
         "leisure=golf_course"}
# Soft ground: its B value in the mask and its GroundMap kind.
SOFT = {"landuse=farmland": "field", "natural=wetland": "wet", "natural=sand": "sand", "natural=beach": "sand"}
SOFT_B = {"field": 190, "wet": 125, "sand": 60}
# GroundMap kinds (scripts/world/ground_map.gd): what each spot is to a tyre.
KINDS = {"paved": 0, "gravel": 1, "lawn": 2, "rough": 3, "field": 4, "wet": 5, "sand": 6}
# Mapped areas that are lawn to look at but rough, uneven ground to drive on.
ROUGH_AREAS = {"landuse=meadow", "natural=wood", "landuse=forest", "natural=scrub", "natural=grassland"}
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


# The values each layer can take, in the order of their codes in pack().
B_CODES = (0, 60, 125, 190, 255)
A_CODES = (0, 100, 255)


def pack(img):
    """The four layers of an RGBA mask in one 8-bit grey image: bit 0 grass
    (R), bit 1 asphalt (G), bits 2-3 the path (A: 1 gravel, 2 brick), bits
    4-6 the B kind (1 sand, 2 wetland, 3 field, 4 plaza). Exact: every value
    a layer can have has its own code (anything else is an error)."""
    r, g, b, a = img.split()
    lut_b = [0] * 256
    lut_a = [0] * 256
    for i in range(256):
        lut_b[i] = (B_CODES.index(i) << 4) if i in B_CODES else 255
        lut_a[i] = (A_CODES.index(i) << 2) if i in A_CODES else 255
    for band, name in ((r, "R"), (g, "G")):
        if any(band.histogram()[1:255]):
            raise ValueError("mask %s layer has values other than 0 and 255" % name)
    bb = b.point(lut_b)
    aa = a.point(lut_a)
    if 255 in (bb.getextrema()[1], aa.getextrema()[1]):
        raise ValueError("mask B or A layer has a value with no code")
    rr = r.point(lambda v: 1 if v else 0)
    gg = g.point(lambda v: 2 if v else 0)
    # The bits never overlap (and add up to under 128), so adding is OR.
    return ImageChops.add(ImageChops.add(rr, gg), ImageChops.add(bb, aa))


def repack(paths):
    """Packs RGBA masks (written before pack()) in place."""
    n = 0
    for path in paths:
        img = Image.open(path)
        if img.mode == "L":
            continue
        pack(img.convert("RGBA")).save(path, optimize=True)
        n += 1
    print("packed %d masks" % n)


def kind(props):
    surface = props.get("surface", "")
    t = props.get("type", "")
    if surface == "grass":
        return "grass"
    if surface in ("paving_stones", "brick", "sett", "concrete") and t != "amenity=parking":
        return "plaza"
    if t == "amenity=parking" or surface == "asphalt":
        return "parking"
    if t in SOFT:
        return SOFT[t]
    if t in GRASS:
        return "grass"
    if t in PLAZA:
        return "plaza"
    if t in YARDS:
        return "yard"
    if t in BARE:
        return "bare"
    return ""


def load_edits(path):
    """The area edits in the map editor's file: (changes by osm id, new
    areas as GeoJSON features)."""
    if not os.path.exists(path):
        return {}, []
    edits = json.load(open(path, encoding="utf-8"))
    changes = {}
    for key, ch in edits.get("features", {}).items():
        if key.startswith("area:") and isinstance(ch, dict):
            changes[key[len("area:"):]] = ch
    new = []
    for f in edits.get("new_features", []):
        if not isinstance(f, dict) or f.get("kind") != "area" or len(f.get("ring", [])) < 3:
            continue
        ring = list(f["ring"])
        if ring[0] != ring[-1]:
            ring.append(ring[0])
        props = dict(f.get("tags", {}))
        props["kind"] = "area"
        props["osm_id"] = str(f.get("id", ""))
        new.append({"type": "Feature", "properties": props, "geometry": {"type": "Polygon", "coordinates": [ring]}})
    return changes, new


def edited(areas, changes):
    """The areas with the editor's changes made: deleted ones left out,
    tags (None removes one) and outlines replaced."""
    out = []
    for f in areas:
        ch = changes.get(str(f["properties"].get("osm_id", "")))
        if ch is None:
            out.append(f)
            continue
        if ch.get("delete"):
            continue
        f = {"type": "Feature", "properties": dict(f["properties"]), "geometry": f["geometry"]}
        for k, v in ch.get("tags", {}).items():
            if v is None:
                f["properties"].pop(k, None)
            else:
                f["properties"][k] = v
        if len(ch.get("ring", [])) >= 3:
            f["geometry"] = {"type": "Polygon", "coordinates": [ch["ring"]]}
        out.append(f)
    return out


def load(city, changes, new):
    roads = [f for f in json.load(open(os.path.join(city, "roads.geojson"), encoding="utf-8"))["features"]
             if f["properties"]["kind"] == "road"]
    areas = {}
    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        for f in json.load(open(path, encoding="utf-8"))["features"]:
            if f["properties"]["kind"] == "area":
                areas[f["properties"]["osm_id"]] = f
    return roads, edited(list(areas.values()), changes) + new


def paint(w, h, to_px, res, roads, areas):
    """One RGBA mask of w x h pixels; to_px maps (lon, lat) to pixel (x, y)."""
    layers = {k: Image.new("L", (w, h), 0) for k in ("grass", "parking", "plaza", "path")}
    draws = {k: ImageDraw.Draw(im) for k, im in layers.items()}
    # Fields, wetland and sand sit on the big areas round them, under
    # anything paved.
    # Big areas first, so a small park inside a residential area wins, and a
    # parking lot always wins over the lawn round it. Commercial and
    # industrial land is mostly parking and yards of asphalt in real life,
    # so it's painted as asphalt under whatever is mapped on top.
    for want in ORDER:
        for f in areas:
            k = kind(f["properties"])
            if k != want:
                continue
            ring = [to_px(c) for c in f["geometry"]["coordinates"][0]]
            if k in ("yard", "grass"):
                draws["grass"].polygon(ring, fill=255)
                if k == "grass":
                    draws["parking"].polygon(ring, fill=0)
            elif k in SOFT_B:
                draws["plaza"].polygon(ring, fill=SOFT_B[k])
                draws["grass"].polygon(ring, fill=0)
                draws["parking"].polygon(ring, fill=0)
            elif k in ("bare", "parking"):
                draws["parking"].polygon(ring, fill=255)
                draws["grass"].polygon(ring, fill=0)
                draws["plaza"].polygon(ring, fill=0)
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
            draws["plaza"].line(pts, fill=0, width=max(1, int(round(width / res))), joint="curve")
        elif hw in PATHS and p.get("area") != "yes" and p.get("footway") not in ("sidewalk", "crossing"):
            width, alpha = PATHS[hw]
            draws["path"].line(pts, fill=alpha, width=max(1, int(round(width / res))), joint="curve")
    return Image.merge("RGBA", (layers["grass"], layers["parking"], layers["plaza"], layers["path"]))


# Big areas first, so what's mapped inside them wins (see paint).
ORDER = ("yard", "grass", "field", "wet", "sand", "bare", "parking", "plaza")


def paint_kinds(w, h, to_px, res, roads, areas):
    """What a tyre drives on, w x h pixels of GroundMap kinds, painted in the
    same order as the mask so the two always agree."""
    img = Image.new("L", (w, h), KINDS["rough"])
    d = ImageDraw.Draw(img)
    for want in ORDER:
        for f in areas:
            k = kind(f["properties"])
            if k != want:
                continue
            ring = [to_px(c) for c in f["geometry"]["coordinates"][0]]
            if k in ("yard", "grass"):
                t = f["properties"].get("type", "")
                d.polygon(ring, fill=KINDS["rough"] if t in ROUGH_AREAS else KINDS["lawn"])
            elif k in SOFT_B:
                d.polygon(ring, fill=KINDS[k])
            else:
                d.polygon(ring, fill=KINDS["paved"])
    for f in roads:
        p = f["properties"]
        hw = p.get("highway")
        pts = [to_px(c) for c in f["geometry"]["coordinates"]]
        if hw == "service":
            width = SERVICE.get(p.get("service", ""), SERVICE[""])
            d.line(pts, fill=KINDS["paved"], width=max(1, int(round(width / res))), joint="curve")
        elif hw in PATHS and p.get("area") != "yes" and p.get("footway") not in ("sidewalk", "crossing"):
            width, alpha = PATHS[hw]
            d.line(pts, fill=KINDS["paved"] if alpha == 255 else KINDS["gravel"], width=max(1, int(round(width / res))), joint="curve")
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--resolution", type=float, default=0.5, help="metres per pixel in the chunk masks")
    ap.add_argument("--coarse", type=float, default=4.0, help="metres per pixel in the whole-map mask")
    ap.add_argument("--chunks", default="", help="only rewrite these chunks' files (X_Z,X_Z,...); the rest are left as they are")
    ap.add_argument("--repack", action="store_true", help="pack masks still in RGBA, in place, and stop")
    args = ap.parse_args()
    if args.repack:
        repack([os.path.join(ROOT, "data", "ground_mask.png")] + sorted(glob.glob(os.path.join(ROOT, "data", "city", "masks", "*.png"))))
        return
    only = set(k for k in args.chunks.split(",") if k)
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    index = json.load(open(os.path.join(city, "index.json"), encoding="utf-8"))
    el = json.load(open(os.path.join(ROOT, "data", "elevation.json"), encoding="utf-8"))
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    changes, new_areas = load_edits(os.path.join(ROOT, cfg.get("edits", "res://data/edits.json").replace("res://", "")))
    roads, areas = load(city, changes, new_areas)

    def world(c):
        return ((c[0] - lon0) * m_lon, -(c[1] - lat0) * m_lat)

    def bounds(f):
        cs = f["geometry"]["coordinates"]
        if f["geometry"]["type"] == "Polygon":
            cs = cs[0]
        xs, zs = zip(*(world(c) for c in cs))
        return min(xs), min(zs), max(xs), max(zs)

    new_box = [(bounds(f), f) for f in new_areas]

    def areas_of(key, x0, z0):
        """A chunk's areas, as the game sees them with the edits."""
        feats = json.load(open(os.path.join(city, "chunks", key + ".geojson"), encoding="utf-8"))["features"]
        own = edited([f for f in feats if f["properties"]["kind"] == "area"], changes)
        return own + [f for (b, f) in new_box if b[2] > x0 and b[0] < x0 + size and b[3] > z0 and b[1] < z0 + size]

    keys = [k for k in index["chunks"] if not only or k in only]

    # Whole map, coarse.
    ox, oz = el["origin_x"], el["origin_z"]
    width_m = (el["nx"] - 1) * el["spacing"]
    depth_m = (el["nz"] - 1) * el["spacing"]
    res = args.coarse
    w, h = int(round(width_m / res)), int(round(depth_m / res))
    img = paint(w, h, lambda c: ((world(c)[0] - ox) / res, (world(c)[1] - oz) / res), res, roads, areas)
    pack(img).save(os.path.join(ROOT, "data", "ground_mask.png"), optimize=True)
    print("wrote data/ground_mask.png: %d x %d px at %.1f m per pixel" % (w, h, res))

    # One mask per chunk.
    size = float(index["chunk_size"])
    out_dir = os.path.join(city, "masks")
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, "*.png")):
        if not only or os.path.basename(old)[:-4] in only:
            os.remove(old)
    road_box = [(bounds(f), f) for f in roads if f["properties"].get("highway") in PATHS or f["properties"].get("highway") == "service"]
    res = args.resolution
    px = int(round(size / res))
    written = 0
    total = 0
    for key in keys:
        cx, cz = (int(v) for v in key.split("_"))
        x0, z0 = cx * size, cz * size
        chunk_areas = areas_of(key, x0, z0)
        pad = 6.0
        chunk_roads = [f for (b, f) in road_box if b[2] > x0 - pad and b[0] < x0 + size + pad and b[3] > z0 - pad and b[1] < z0 + size + pad]
        img = paint(px, px, lambda c: ((world(c)[0] - x0) / res, (world(c)[1] - z0) / res), res, chunk_roads, chunk_areas)
        if not any(band.getbbox() for band in img.split()):
            continue # nothing painted (Pillow's own getbbox looks at the alpha alone)
        path = os.path.join(out_dir, key + ".png")
        pack(img).save(path, optimize=True)
        written += 1
        total += os.path.getsize(path)
    print("wrote %d chunk masks in %s (%.1f MB) at %.2f m per pixel" % (written, out_dir, total / 1e6, res))

    # What each chunk is to drive on, a byte per metre.
    ground_dir = os.path.join(city, "ground")
    os.makedirs(ground_dir, exist_ok=True)
    for old in glob.glob(os.path.join(ground_dir, "*.bin")):
        if not only or os.path.basename(old)[:-4] in only:
            os.remove(old)
    res = 1.0
    px = int(round(size / res))
    written = 0
    total = 0
    for key in keys:
        cx, cz = (int(v) for v in key.split("_"))
        x0, z0 = cx * size, cz * size
        chunk_areas = areas_of(key, x0, z0)
        pad = 6.0
        chunk_roads = [f for (b, f) in road_box if b[2] > x0 - pad and b[0] < x0 + size + pad and b[3] > z0 - pad and b[1] < z0 + size + pad]
        img = paint_kinds(px, px, lambda c: ((world(c)[0] - x0) / res, (world(c)[1] - z0) / res), res, chunk_roads, chunk_areas)
        if img.getextrema() == (KINDS["rough"], KINDS["rough"]):
            continue # all rough ground, which is what a chunk with no file is
        path = os.path.join(ground_dir, key + ".bin")
        with open(path, "wb") as out:
            out.write(zlib.compress(img.tobytes(), 9))
        written += 1
        total += os.path.getsize(path)
    print("wrote %d ground maps in %s (%.1f MB) at %.0f m per cell" % (written, ground_dir, total / 1e6, res))


if __name__ == "__main__":
    main()

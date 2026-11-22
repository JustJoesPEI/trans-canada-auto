#!/usr/bin/env python3
"""Sample real ground elevation for the map area onto a grid the game reads.

Source: Natural Resources Canada, High Resolution Digital Elevation Model
(HRDEM), the PEI 2020 lidar project, 1 m bare-earth model (DTM: the ground
with buildings and trees removed). Open Government Licence - Canada.
Heights are metres above sea level (CGVD2013).

The grid is laid out in the game's own coordinates (metres from the origin in
map_config.json, +x east, +z south), so the game needs no map projection at
runtime. Only the small window over the map is read, not the whole island.

The heights go in a small binary file the game reads straight into memory
(data/elevation.bin: centimetres, rounded to 5 cm, as little-endian 16-bit integers,
row by row from the north-west corner, zlib-compressed), described by
data/elevation.json (where the grid starts, its spacing and size). Water and
any gaps in the survey are set to WATER_M below sea level, so the harbour
and rivers show as water.

Needs: pip install rasterio pyproj numpy

    python3 tools/fetch_elevation.py data/elevation.json --spacing 2
"""

import argparse
import datetime
import json
import math
import os
import zlib

import numpy as np
import rasterio
from rasterio.windows import from_bounds
from pyproj import Transformer

DTM = ("https://canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-lidar/"
       "PEI-Prince_Edward_Island_2020-1m-dtm.tif")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WATER_M = -1.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    ap.add_argument("--spacing", type=float, default=2.0, help="grid spacing in metres")
    ap.add_argument("--source", default=DTM)
    args = ap.parse_args()

    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    index = json.load(open(os.path.join(ROOT, cfg["city"].replace("res://", ""), "index.json"), encoding="utf-8"))
    s, w, n, e = index["bbox_s_w_n_e"]
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)

    # Grid in game coordinates covering the map box.
    x0 = (w - lon0) * m_lon
    x1 = (e - lon0) * m_lon
    z0 = -(n - lat0) * m_lat
    z1 = -(s - lat0) * m_lat
    sp = args.spacing
    nx = int(math.ceil((x1 - x0) / sp)) + 1
    nz = int(math.ceil((z1 - z0) / sp)) + 1
    xs = x0 + np.arange(nx) * sp
    zs = z0 + np.arange(nz) * sp
    gx, gz = np.meshgrid(xs, zs)
    lon = lon0 + gx / m_lon
    lat = lat0 - gz / m_lat

    os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
    with rasterio.open(args.source) as src:
        to_src = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
        px, py = to_src.transform(lon, lat)
        margin = 10.0
        win = from_bounds(px.min() - margin, py.min() - margin, px.max() + margin, py.max() + margin, src.transform)
        win = win.round_offsets().round_lengths()
        data = src.read(1, window=win, masked=True).astype("float32")
        wt = src.window_transform(win)
        nodata_count = int(np.ma.count_masked(data))
        # Water and gaps in the survey: a little below sea level.
        filled = data.filled(WATER_M)
        # Bilinear sample at each grid point.
        inv = ~wt
        col, row = inv * (px, py)
        col = col - 0.5
        row = row - 0.5
        c0 = np.clip(np.floor(col).astype(int), 0, filled.shape[1] - 2)
        r0 = np.clip(np.floor(row).astype(int), 0, filled.shape[0] - 2)
        fc = np.clip(col - c0, 0, 1)
        fr = np.clip(row - r0, 0, 1)
        h = (filled[r0, c0] * (1 - fc) * (1 - fr) + filled[r0, c0 + 1] * fc * (1 - fr)
             + filled[r0 + 1, c0] * (1 - fc) * fr + filled[r0 + 1, c0 + 1] * fc * fr)
        crs = str(src.crs)

    out = {
        "source": "Natural Resources Canada, HRDEM, PEI 2020 lidar project, 1 m DTM (bare earth)",
        "url": args.source,
        "licence": "Open Government Licence - Canada, https://open.canada.ca/en/open-government-licence-canada",
        "attribution": "Contains information licensed under the Open Government Licence - Canada (NRCan HRDEM).",
        "heights": "metres above sea level (CGVD2013), stored as centimetres rounded to 5 cm",
        "retrieved": datetime.date.today().isoformat(),
        "source_crs": crs,
        "origin_x": round(float(x0), 3),
        "origin_z": round(float(z0), 3),
        "spacing": sp,
        "nx": nx,
        "nz": nz,
        "holes_filled": nodata_count,
        "water_m": WATER_M,
        "file": os.path.basename(os.path.splitext(args.output)[0]) + ".bin",
        "encoding": "int16 centimetres, little-endian, row-major from the north-west corner, zlib",
    }
    # Rounded to 5 cm: well inside the lidar's own accuracy (about 10 cm),
    # and it halves the size of the file.
    cm = np.clip(np.round(h * 20.0) * 5.0, -32768, 32767).astype("<i2")
    raw = cm.tobytes()
    out["bytes"] = len(raw)
    with open(os.path.join(os.path.dirname(args.output), out["file"]), "wb") as f:
        f.write(zlib.compress(raw, 9))
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("wrote %s: %d x %d grid at %.1f m, heights %.1f to %.1f m, %d holes filled"
          % (args.output, nx, nz, sp, h.min(), h.max(), nodata_count))


if __name__ == "__main__":
    main()

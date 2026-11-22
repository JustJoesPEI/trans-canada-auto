#!/usr/bin/env python3
"""Read real building heights, roof shapes and trees from the lidar survey.

Natural Resources Canada's PEI 2020 lidar comes as two models: the bare
ground (DTM) and the surface with everything on it (DSM). The difference
between them is how tall whatever stands there is. From that:

  * Every building in data/city/chunks gets
        lidar_top    height of the roof's highest part above the ground (m)
        lidar_eave   height of the eaves (where a pitched roof starts) (m)
        lidar_roof   "flat", "gabled" or "hipped"
        lidar_ridge  "long" or "short": which way the ridge runs, along the
                     footprint's long side or across it
    Buildings the survey doesn't see (built after 2020, or hidden under
    trees) are left alone and the game guesses as before.
  * Every tree the survey sees becomes one entry in a "trees" feature in
    its chunk: [x, z, height, crown radius, 1 if it looks like a conifer],
    in game metres. Tree tops are found as the highest point of the canopy
    within a few metres, outside buildings.

Run after osm_to_geojson.py (it reads and rewrites data/city/chunks).
Needs: pip install rasterio pyproj numpy scipy Pillow

    python3 tools/lidar_features.py
"""

import glob
import json
import math
import os
import sys

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from pyproj import Transformer
from rasterio.windows import from_bounds
from scipy import ndimage

BASE = "https://canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-lidar/PEI-Prince_Edward_Island_2020-1m-"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = 1.0  # metres per sample, in game coordinates
MIN_TREE_H = 3.0


def main():
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    index = json.load(open(os.path.join(city, "index.json"), encoding="utf-8"))
    s, w, n, e = index["bbox_s_w_n_e"]
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)

    def world(c):
        return ((c[0] - lon0) * m_lon, -(c[1] - lat0) * m_lat)

    # A 1 m grid in game coordinates over the whole box.
    x0, x1 = (w - lon0) * m_lon, (e - lon0) * m_lon
    z0, z1 = -(n - lat0) * m_lat, -(s - lat0) * m_lat
    nx = int(math.ceil((x1 - x0) / RES))
    nz = int(math.ceil((z1 - z0) / RES))
    print("grid %d x %d" % (nx, nz), file=sys.stderr)
    os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")

    def sample(kind):
        with rasterio.open(BASE + kind + ".tif") as src:
            to_src = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
            out = np.zeros((nz, nx), dtype=np.float32)
            # In bands of rows, to keep memory down.
            band = 400
            for r0 in range(0, nz, band):
                r1 = min(nz, r0 + band)
                gx, gz = np.meshgrid(x0 + (np.arange(nx) + 0.5) * RES, z0 + (np.arange(r0, r1) + 0.5) * RES)
                px, py = to_src.transform(lon0 + gx / m_lon, lat0 - gz / m_lat)
                win = from_bounds(px.min() - 3, py.min() - 3, px.max() + 3, py.max() + 3, src.transform)
                win = win.round_offsets().round_lengths()
                data = src.read(1, window=win, masked=True).astype("float32").filled(np.nan)
                inv = ~src.window_transform(win)
                col, row = inv * (px, py)
                ci = np.clip(np.round(col - 0.5).astype(int), 0, data.shape[1] - 1)
                ri = np.clip(np.round(row - 0.5).astype(int), 0, data.shape[0] - 1)
                out[r0:r1] = data[ri, ci]
                print("  %s rows %d/%d" % (kind, r1, nz), file=sys.stderr, end="\r")
            print(file=sys.stderr)
            return out

    dtm = sample("dtm")
    dsm = sample("dsm")
    ndsm = np.nan_to_num(dsm - dtm, nan=0.0)
    ndsm[ndsm < 0] = 0
    del dsm

    def px(c):
        x, z = world(c)
        return ((x - x0) / RES, (z - z0) / RES)

    # --- buildings -----------------------------------------------------------
    chunk_files = sorted(glob.glob(os.path.join(city, "chunks", "*.geojson")))
    chunks = {p: json.load(open(p, encoding="utf-8")) for p in chunk_files}
    footprint = Image.new("L", (nx, nz), 0)
    fdraw = ImageDraw.Draw(footprint)
    seen = 0
    for path, gj in chunks.items():
        for f in gj["features"]:
            p = f["properties"]
            if p["kind"] != "building":
                continue
            for k in ("lidar_top", "lidar_eave", "lidar_roof", "lidar_ridge"):
                p.pop(k, None)
            ring = [px(c) for c in f["geometry"]["coordinates"][0]]
            fdraw.polygon(ring, fill=255)
            res = roof_of(ring, ndsm)
            if res:
                p.update(res)
                seen += 1
    print("buildings measured: %d" % seen, file=sys.stderr)

    # --- trees -----------------------------------------------------------------
    built = np.array(footprint) > 0
    built = ndimage.binary_dilation(built, iterations=2)
    canopy = np.where(built, 0.0, ndsm)
    canopy[canopy > 40] = 0  # masts, cranes, noise
    smooth = ndimage.gaussian_filter(canopy, 1.0)
    peak = ndimage.maximum_filter(smooth, size=5)
    tops = (smooth == peak) & (smooth > MIN_TREE_H)
    zi, xi = np.nonzero(tops)
    print("tree tops: %d" % len(zi), file=sys.stderr)
    # Crown size: how far round the top the canopy stays above half its height.
    half = smooth > 0
    trees = {}
    size = float(index["chunk_size"])
    for r, c in zip(zi, xi):
        h = float(smooth[r, c])
        reach = 1
        for d in range(1, 8):
            r0, r1 = max(0, r - d), min(nz - 1, r + d)
            c0, c1 = max(0, c - d), min(nx - 1, c + d)
            ring = [smooth[r0, c], smooth[r1, c], smooth[r, c0], smooth[r, c1]]
            if min(ring) < h * 0.5:
                break
            reach = d
        crown = max(1.2, min(7.0, reach + 0.5))
        # A sharp, narrow top (the canopy falls away fast) reads as a spruce or fir.
        r2 = [smooth[max(0, r - 2), c], smooth[min(nz - 1, r + 2), c], smooth[r, max(0, c - 2)], smooth[r, min(nx - 1, c + 2)]]
        conifer = 1 if (h - float(np.mean(r2))) > 0.16 * h and crown < 0.35 * h else 0
        x = x0 + (c + 0.5) * RES
        z = z0 + (r + 0.5) * RES
        key = "%d_%d" % (math.floor(x / size), math.floor(z / size))
        trees.setdefault(key, []).extend([round(x, 1), round(z, 1), round(h, 1), round(crown, 1), conifer])

    # --- write back ----------------------------------------------------------------
    count = 0
    for path, gj in chunks.items():
        key = os.path.splitext(os.path.basename(path))[0]
        gj["features"] = [f for f in gj["features"] if f["properties"]["kind"] != "trees"]
        if key in trees:
            gj["features"].append({"type": "Feature", "properties": {"kind": "trees", "t": trees.pop(key)},
                                   "geometry": None})
            count += 1
    # Chunks with trees but nothing else yet.
    for key, t in trees.items():
        path = os.path.join(city, "chunks", key + ".geojson")
        chunks[path] = {"type": "FeatureCollection", "features": [
            {"type": "Feature", "properties": {"kind": "trees", "t": t}, "geometry": None}]}
        index["chunks"].append(key)
    for path, gj in chunks.items():
        with open(path, "w", encoding="utf-8") as f:
            json.dump(gj, f, separators=(",", ":"), ensure_ascii=False)
            f.write("\n")
    index["chunks"] = sorted(set(index["chunks"]))
    index["lidar"] = "Building heights, roofs and trees from NRCan HRDEM PEI 2020 (DSM minus DTM), tools/lidar_features.py"
    with open(os.path.join(city, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("wrote trees into %d chunks" % (count + len(trees)), file=sys.stderr)


def roof_of(ring, ndsm):
    """Height and roof shape of one footprint, or None if the survey can't see it."""
    xs = [p[0] for p in ring]
    zs = [p[1] for p in ring]
    c0, c1 = int(math.floor(min(xs))) - 1, int(math.ceil(max(xs))) + 2
    r0, r1 = int(math.floor(min(zs))) - 1, int(math.ceil(max(zs))) + 2
    if c0 < 0 or r0 < 0 or c1 >= ndsm.shape[1] or r1 >= ndsm.shape[0]:
        return None
    mask = Image.new("L", (c1 - c0, r1 - r0), 0)
    ImageDraw.Draw(mask).polygon([(x - c0, z - r0) for x, z in ring], fill=255)
    m = np.array(mask) > 0
    # Stay a metre in from the walls, where the lidar may catch the ground.
    inner = ndimage.binary_erosion(m, iterations=1)
    if inner.sum() >= 6:
        m = inner
    vals = ndsm[r0:r1, c0:c1][m]
    if vals.size < 4:
        return None
    if np.median(vals) < 2.0:
        return None  # not there in 2020, or the survey missed it
    top = float(np.percentile(vals, 92))
    eave = float(np.percentile(vals, 12))
    out = {"lidar_top": round(top, 1), "lidar_eave": round(eave, 1)}
    if top - eave < 1.3 or vals.size < 12:
        out["lidar_roof"] = "flat"
        return out
    # Which way does the roof fall? Compare height against distance from the
    # footprint's middle line along each of its two main directions.
    zz, xx = np.nonzero(m)
    pts = np.stack([xx, zz], axis=1).astype(float)
    pts -= pts.mean(axis=0)
    cov = np.cov(pts.T)
    evals, evecs = np.linalg.eigh(cov)
    long_dir = evecs[:, 1]
    short_dir = evecs[:, 0]
    a = np.abs(pts @ short_dir)  # distance across the footprint from its long middle line
    b = np.abs(pts @ long_dir)
    h = vals

    def fall(d):
        if d.std() < 1e-6:
            return 0.0
        return -float(np.corrcoef(d, h)[0, 1])

    fa, fb = fall(a), fall(b)
    if fa > 0.35 and fb > 0.35:
        out["lidar_roof"] = "hipped"
        out["lidar_ridge"] = "long"
    elif fa > 0.3 or fb > 0.3:
        out["lidar_roof"] = "gabled"
        # Falling away from the long middle line means the ridge runs along it.
        out["lidar_ridge"] = "long" if fa >= fb else "short"
    else:
        out["lidar_roof"] = "flat"
    return out


if __name__ == "__main__":
    main()

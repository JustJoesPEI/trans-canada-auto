#!/usr/bin/env python3
"""Draw a top-down SVG of the town the game will build, without opening Godot.

Runs the same road-graph and curb-corner maths as scripts/world/road_network.gd
(simplified: sidewalks are the same on both sides, so divided roads show a
sidewalk on their median here though not in the game) on data/city/ +
data/map_config.json, and draws asphalt, sidewalks, building footprints and
the play-area ring. Use it to check a data refresh or a width change in
map_config.json at a glance. The ring is drawn straight from corner to
corner; the game follows the roads between them.

    python3 tools/preview_map.py preview.svg            # downtown
    python3 tools/preview_map.py city.svg --centre=-1500,-2000 --half 3300   # the whole city

--centre X,Z picks the middle of the view (metres from the origin) and
--half how far it reaches each way.

If you change the corner maths in road_network.gd, change it here too.
"""

import argparse
import glob
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load():
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    gj = json.load(open(os.path.join(city, "roads.geojson"), encoding="utf-8"))
    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        gj["features"].extend(f for f in json.load(open(path, encoding="utf-8"))["features"]
                              if f["properties"]["kind"] == "building")
    lat0, lon0 = cfg["origin"]["lat"], cfg["origin"]["lon"]
    phi = math.radians(lat0)
    m_lat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    proj = lambda c: ((c[0] - lon0) * m_lon, -(c[1] - lat0) * m_lat)
    return cfg, gj, proj


def style(cfg, name, hw, tags):
    """Width and sidewalk, as StreetData.road_style() works them out."""
    d = cfg["road_defaults"].get(hw) or {}
    oneway = tags.get("oneway") in ("yes", "1", "-1", "true") or tags.get("junction") in ("roundabout", "circular")
    shoulder = d.get("shoulder", 0.0)
    sidewalk = d.get("sidewalk", 2.0)
    width = d.get("oneway_width", d.get("width", 8.0)) if oneway else d.get("width", 8.0)
    try:
        lanes = int(tags.get("lanes", "0"))
    except ValueError:
        lanes = 0
    if lanes > 0 and "lane" in d:
        width = lanes * d["lane"] + shoulder * 2.0
    if tags.get("sidewalk") in ("no", "none"):
        sidewalk = 0.0
    o = cfg["street_overrides"].get(name)
    if o and shoulder <= 0.0:
        width, sidewalk = o.get("width", width), o.get("sidewalk", sidewalk)
    return width, sidewalk


def norm(v):
    l = math.hypot(*v) or 1.0
    return (v[0] / l, v[1] / l)


def perp(d):
    return (-d[1], d[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def add(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s)


class Net:
    def __init__(self, cfg, gj, proj):
        classes = set(cfg["drivable_classes"])
        roads = []
        use = {}
        for f in gj["features"]:
            p = f["properties"]
            if p["kind"] != "road" or p.get("highway") not in classes:
                continue
            pts = [proj(c) for c in f["geometry"]["coordinates"]]
            roads.append((p, pts))
            last = len(p["nodes"]) - 1
            for i, n in enumerate(p["nodes"]):
                use[n] = use.get(n, 0) + (2 if i in (0, last) else 1)
        self.nodes, self.inc, self.edges = {}, {}, []
        for p, pts in roads:
            w, sw = style(cfg, p.get("name", ""), p["highway"], p)
            ids, start = p["nodes"], 0
            for i in range(1, len(ids)):
                if use[ids[i]] >= 2 or i == len(ids) - 1:
                    seg = pts[start:i + 1]
                    if ids[start] != ids[i]:
                        e = {"name": p.get("name", ""), "a": ids[start], "b": ids[i], "pts": seg,
                             "hw": w / 2, "sw": sw}
                        self.edges.append(e)
                        self.nodes[e["a"]], self.nodes[e["b"]] = seg[0], seg[-1]
                        for nid, at_start in ((e["a"], True), (e["b"], False)):
                            d = self.leave(seg, at_start)
                            self.inc.setdefault(nid, []).append({"e": e, "s": at_start, "d": d,
                                                                  "ang": math.atan2(d[1], d[0])})
                    start = i
        for lst in self.inc.values():
            lst.sort(key=lambda x: x["ang"])

    @staticmethod
    def leave(pts, from_start):
        seq = pts if from_start else pts[::-1]
        for q in seq[1:]:
            if math.hypot(q[0] - seq[0][0], q[1] - seq[0][1]) >= 4.0 or q is seq[-1]:
                return norm((q[0] - seq[0][0], q[1] - seq[0][1]))
        return (1.0, 0.0)

    @staticmethod
    def off(e, level):
        return {"curb": e["hw"], "back": e["hw"] + e["sw"]}[level]

    def corner_right(self, nid, k, level):
        lst, c = self.inc[nid], self.nodes[nid]
        i = lst[k]
        hi = self.off(i["e"], level)
        if len(lst) == 1:
            return add(c, perp(i["d"]), hi)
        j = lst[(k + 1) % len(lst)]
        hj = self.off(j["e"], level)
        pi, pj = perp(i["d"]), perp(j["d"])
        det = pi[0] * pj[1] - pi[1] * pj[0]
        if abs(det) < 0.08:
            return add(c, pi, (hi + hj) / 2)
        v = ((hi * pj[1] + pi[1] * hj) / det, (-pi[0] * hj - pj[0] * hi) / det)
        lim = max(hi, hj) * 4
        if math.hypot(*v) > lim:
            v = (v[0] * lim / math.hypot(*v), v[1] * lim / math.hypot(*v))
        return add(c, v)

    def corner_left(self, nid, k, level):
        lst = self.inc[nid]
        if len(lst) == 1:
            return add(self.nodes[nid], perp(lst[0]["d"]), -self.off(lst[0]["e"], level))
        return self.corner_right(nid, (k - 1) % len(lst), level)

    def idx(self, nid, e, at_start):
        for k, x in enumerate(self.inc[nid]):
            if x["e"] is e and x["s"] == at_start:
                return k

    def side_line(self, e, side, level):
        ka, kb = self.idx(e["a"], e, True), self.idx(e["b"], e, False)
        o = self.off(e, level) * side
        out = [self.corner_right(e["a"], ka, level) if side > 0 else self.corner_left(e["a"], ka, level)]
        p = e["pts"]
        for i in range(1, len(p) - 1):
            n1 = perp(norm((p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1])))
            n2 = perp(norm((p[i + 1][0] - p[i][0], p[i + 1][1] - p[i][1])))
            m = norm((n1[0] + n2[0], n1[1] + n2[1]))
            out.append(add(p[i], m, o / max(dot(m, n1), 0.3)))
        out.append(self.corner_left(e["b"], kb, level) if side > 0 else self.corner_right(e["b"], kb, level))
        return out

    def find(self, a, b):
        best, deg = None, 0
        for nid, lst in self.inc.items():
            names = {x["e"]["name"] for x in lst}
            if a in names and b in names and len(lst) > deg:
                best, deg = nid, len(lst)
        return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output", nargs="?", default="preview.svg")
    ap.add_argument("--centre", default="0,0", help="middle of the view, metres x,z from the origin")
    ap.add_argument("--half", type=float, default=260.0, help="metres from the middle to each edge")
    args = ap.parse_args()
    out = args.output
    cfg, gj, proj = load()
    net = Net(cfg, gj, proj)
    play = []
    for item in cfg["play_area"]["ring"]:
        if "streets" in item:
            nid = net.find(*item["streets"])
            if nid:
                play.append(net.nodes[nid])
        elif "water" in item:
            play.append(proj((item["water"][1], item["water"][0])))
    cx, cz = (float(v) for v in args.centre.split(","))
    half = args.half
    vb = "%f %f %f %f" % (cx - half, cz - half, half * 2, half * 2)
    poly = lambda pts, fill, extra="": '<polygon points="%s" fill="%s" %s/>' % (
        " ".join("%.2f,%.2f" % p for p in pts), fill, extra)
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s" width="1200" height="1200">' % vb,
           '<rect x="%f" y="%f" width="%f" height="%f" fill="#6f7d5c"/>' % (cx - half, cz - half, half * 2, half * 2)]
    for e in net.edges:
        for side in (1, -1):
            c, b = net.side_line(e, side, "curb"), net.side_line(e, side, "back")
            for i in range(len(c) - 1):
                svg.append(poly([c[i], c[i + 1], b[i + 1], b[i]], "#a9a49b"))
    for e in net.edges:
        r, l = net.side_line(e, 1, "curb"), net.side_line(e, -1, "curb")
        for i in range(len(r) - 1):
            svg.append(poly([r[i], r[i + 1], l[i + 1], l[i]], "#3f3f42"))
    for nid, lst in net.inc.items():
        if len(lst) >= 3:
            c = net.nodes[nid]
            ring = [net.corner_right(nid, k, "curb") for k in range(len(lst))]
            for k in range(len(ring)):
                svg.append(poly([c, ring[k], ring[(k + 1) % len(ring)]], "#3f3f42"))
    for f in gj["features"]:
        if f["properties"]["kind"] == "building" and f["properties"].get("building") not in ("roof",):
            svg.append(poly([proj(c) for c in f["geometry"]["coordinates"][0]], "#b5523b",
                            'fill-opacity="0.75" stroke="#3a1a12" stroke-width="0.3"'))
    svg.append(poly(play, "none", 'stroke="#ffd34d" stroke-width="%.1f" stroke-dasharray="%d %d"' % (half / 170, half / 40, half / 60)))
    for e in net.edges:
        mid = e["pts"][len(e["pts"]) // 2]
        if e["name"] and abs(mid[0] - cx) < half and abs(mid[1] - cz) < half and half < 800:
            svg.append('<text x="%.1f" y="%.1f" font-size="5" fill="#fff" font-family="sans-serif">%s</text>'
                       % (mid[0], mid[1], e["name"]))
    svg.append("</svg>")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))
    print("wrote %s: %d edges, %d junctions" % (out, len(net.edges), len(net.nodes)))


if __name__ == "__main__":
    main()

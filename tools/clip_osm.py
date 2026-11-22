#!/usr/bin/env python3
"""Cut the map area out of a whole-province OpenStreetMap extract.

Input is Geofabrik's Prince Edward Island file
(https://download.geofabrik.de/north-america/canada/prince-edward-island-latest.osm.pbf).
Output is a smaller .osm.pbf with everything that touches the box: every node
inside it, every way with a node inside it (complete, with all its nodes,
so roads crossing the edge are whole and can be clipped cleanly later), and
every relation with a member inside it (so parks and big buildings mapped as
multipolygons come through whole).

Needs pyosmium (pip install osmium). Usage:

    python3 tools/clip_osm.py raw/prince-edward-island-latest.osm.pbf \
        raw/charlottetown.osm.pbf --bbox 46.2215,-63.1860,46.2795,-63.0970
"""

import argparse
import sys

import osmium


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--bbox", required=True, help="south,west,north,east in degrees")
    args = ap.parse_args()
    s, w, n, e = (float(v) for v in args.bbox.split(","))

    # Pass 1: which ways and relations touch the box.
    keep = osmium.IdTracker()
    inside = set()
    ways = set()
    for obj in osmium.FileProcessor(args.input, osmium.osm.NODE):
        if s <= obj.location.lat <= n and w <= obj.location.lon <= e:
            inside.add(obj.id)
            keep.add_node(obj.id)
    for obj in osmium.FileProcessor(args.input, osmium.osm.WAY | osmium.osm.RELATION):
        if obj.is_way():
            if any(nd.ref in inside for nd in obj.nodes):
                keep.add_way(obj.id)
                ways.add(obj.id)
        elif obj.is_relation():
            for m in obj.members:
                if (m.type == "n" and m.ref in inside) or (m.type == "w" and m.ref in ways):
                    keep.add_relation(obj.id)
                    break
    # Pass 2: pull in every member and node those need, then write them.
    keep.complete_forward_references(args.input, relation_depth=2)
    count = 0
    with osmium.SimpleWriter(args.output, overwrite=True) as writer:
        for obj in osmium.FileProcessor(args.input).with_filter(keep.id_filter()):
            writer.add(obj)
            count += 1
    print("wrote %s: %d objects" % (args.output, count), file=sys.stderr)


if __name__ == "__main__":
    main()

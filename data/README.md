# Street data

The town is built at startup from two files in this folder:

| File | What it is |
|---|---|
| `downtown.geojson` | Roads, building footprints and street furniture points for downtown Charlottetown, converted from OpenStreetMap. |
| `map_config.json` | How to read it: the world origin, the play-area corners (named by street pairs), the spawn point, and road and sidewalk widths per street. |

## Where the data comes from

`downtown.geojson` was made on 2026-11-19 from the OpenStreetMap API, using
the box south 46.2318, west -63.1302, north 46.2378, east -63.1212. That
covers the four play blocks (Queen, Great George and Prince streets crossed by
Grafton, Richmond and Sydney) plus about 120 m of scenery around them.

© OpenStreetMap contributors. The data is under the Open Database License
(ODbL) 1.0: https://www.openstreetmap.org/copyright. Keep that credit with the
data and in the game's credits. If you change the data and share it, the
changed data stays under the ODbL.

### What is real and what is cleaned

* Road centrelines, intersections, one-way tags, building footprints, traffic
  signals, stop signs, crossings and trees are exact OSM positions.
* Roads are cut at the edge of the box. Points made by the cut have ids that
  start with `clip:`.
* Street junctions closer together than 6 m are merged into one at their
  average position (listed in the file's `metadata.merged_nodes`). Right now
  that is 4 groups, including the doubled Queen Street / Richmond Street node.
* Road widths are **not** in OSM for these streets. They are set in
  `map_config.json`, chosen so the curb and sidewalk fit between the real
  building fronts on each street. Treat them as good estimates, not survey
  values.

## Refreshing or growing the map

Python 3 with no extra packages:

```sh
# 1. download a raw extract (south,west,north,east)
python3 tools/fetch_osm.py 46.2318,-63.1302,46.2378,-63.1212 raw/downtown.osm

# 2. convert it to the game's GeoJSON
python3 tools/osm_to_geojson.py raw/downtown.osm data/downtown.geojson \
    --bbox 46.2318,-63.1302,46.2378,-63.1212
```

If the download fails (no network, API busy), get the same box by hand from
https://www.openstreetmap.org/export ("Manually select a different area",
then "Export") or from Overpass Turbo (export as raw OSM data), save it
under `raw/`, and run step 2. Both `.osm` (XML) and Overpass `.json` work.

To add Water Street or the waterfront later, widen the box, rerun both
steps, then move the `play_area.corners` in `map_config.json` to the new
corner junctions. Keep `origin` where it is so the existing coordinates do
not shift.

`raw/` is ignored by git; only the converted GeoJSON is committed.

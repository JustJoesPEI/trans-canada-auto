# Street data

The town is built at startup from two files in this folder:

| File | What it is |
|---|---|
| `downtown.geojson` | Roads, building footprints and street furniture points for downtown Charlottetown, converted from OpenStreetMap. |
| `elevation.json` | Real ground heights on a 2 m grid, from Natural Resources Canada's lidar ground model. Made by `tools/fetch_elevation.py`. |
| `ground_mask.png` | Which ground is lawn, parking, stone square or brick path, painted from the OSM areas for the terrain to draw. Made by `tools/make_ground_mask.py`. |
| `map_config.json` | How to read it: the world origin, the play-area corners (named by street pairs), the spawn point, road and sidewalk widths per street, which streets are brick (Victoria Row), and extra detail for landmark buildings. |

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

* Road centrelines, intersections, one-way tags, building footprints, ground
  areas (lawns, parks, parking lots, plazas), footpaths, traffic signals,
  stop signs, crossings and trees are exact OSM positions.
* Roads are cut at the edge of the box. Points made by the cut have ids that
  start with `clip:`.
* Street junctions closer together than 6 m are merged into one at their
  average position (listed in the file's `metadata.merged_nodes`). Right now
  that is 4 groups, including the doubled Queen Street / Richmond Street node.
* Road widths are **not** in OSM for these streets. They are set in
  `map_config.json`, chosen so the curb and sidewalk fit between the real
  building fronts on each street. Treat them as good estimates, not survey
  values.

### Elevation

The ground's shape comes from Natural Resources Canada's High Resolution
Digital Elevation Model (HRDEM), the PEI 2020 lidar project at 1 m, using
the bare-earth model (DTM: the ground with buildings and trees taken out).
It's sampled onto a 2 m grid lined up with the game's coordinates, and
heights are metres above sea level (CGVD2013), so a height in the game is
the real height. Downtown runs from about 11 m at Queen and Grafton down to
about 6 m at Prince and Sydney and 2 m at Queen and Water.

Contains information licensed under the Open Government Licence – Canada
(https://open.canada.ca/en/open-government-licence-canada).

To refresh it, or after widening the map box (needs Python with
`rasterio`, `pyproj`, `numpy` and `Pillow`):

```sh
python3 tools/fetch_elevation.py data/elevation.json --spacing 2
python3 tools/make_ground_mask.py data/ground_mask.png --resolution 0.5
```

Run `make_ground_mask.py` again after any OSM refresh too, since the lawns,
parking lots and paths come from the OSM data.

### Landmarks

`map_config.json` has a `landmarks` section keyed by OSM way id (for
example `158560871` is St. Dunstan's Basilica). The footprint still comes
from OSM; the entry adds what OSM doesn't record, like the material, colour,
wall height, towers and spires, or a portico, and which way the front faces
(named by a street or a junction, never by coordinates). These are
best estimates, not measurements, so correct them against the real buildings. To add one, find the building's way id on
openstreetmap.org (click it, the number is in the address bar) and copy an
existing entry.

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

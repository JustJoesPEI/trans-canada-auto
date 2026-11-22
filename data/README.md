# Map data

The town is built from these files:

| File | What it is |
|---|---|
| `city/roads.geojson` | Every street, ramp and path in the city, converted from OpenStreetMap, plus the traffic signals, stop signs and crossings. Loaded whole at startup. |
| `city/chunks/X_Z.geojson` | Buildings, ground areas (parks, woods, parking, yards) and points like trees, split into 200 m squares. X and Z count squares east and south of the origin. The game loads a square when the player comes near. |
| `city/masks/X_Z.png` | For each square, which ground is lawn, parking or driveway, stone square or path, painted from the OSM areas at half a metre per pixel. |
| `city/index.json` | The area covered, the square size and which squares have data. |
| `elevation.json` + `elevation.bin` | Real ground heights on a 2 m grid over the whole area, from Natural Resources Canada's lidar ground model. The `.json` says where the grid is; the `.bin` holds the heights. Made by `tools/fetch_elevation.py`. |
| `ground_mask.png` | The same as the masks above for the whole area at 4 m per pixel, for the ground further away. |
| `map_config.json` | How to read it all: the world origin, the play-area ring, the spawn point, road widths by road type and per street, which streets are brick (Victoria Row), how far the downtown look reaches, and extra detail for landmark buildings. |

## Where the data comes from

The map covers the box south 46.2215, west -63.1860, north 46.2795, east
-63.0970: the whole city out to the bypass (Riverside Drive, the Arterial
Highway, Upton Road and Capital Drive) with a few hundred metres of scenery
past it, including the shore of Stratford across the Hillsborough River.

It was cut from Geofabrik's OpenStreetMap extract for Prince Edward Island
(`prince-edward-island-latest.osm.pbf`, dated 2026-11-21), not downloaded
street by street.

© OpenStreetMap contributors. The data is under the Open Database License
(ODbL) 1.0: https://www.openstreetmap.org/copyright. Keep that credit with the
data and in the game's credits. If you change the data and share it, the
changed data stays under the ODbL.

### What is real and what is cleaned

* Road centrelines, intersections, one-way tags, lane counts, bridges,
  roundabouts, building footprints, ground areas (lawns, parks, woods,
  parking lots, plazas), footpaths, traffic signals, stop signs, crossings
  and trees are exact OSM positions.
* Roads are cut at the edge of the box. Points made by the cut have ids that
  start with `clip:`.
* Street junctions closer together than 6 m are merged into one at their
  average position (listed in `roads.geojson`'s `metadata.merged_nodes`),
  except on roundabouts and ramps, where the exact shape matters.
* Buildings and parks mapped as multipolygons (with holes or several parts)
  keep only their biggest outer ring.
* Road widths are **not** in OSM for most streets. Downtown they're set
  per street in `map_config.json`, chosen so the curb and sidewalk fit
  between the real building fronts. Elsewhere they're worked out from the
  road type and, where OSM has it, the number of lanes. Treat them as good
  estimates, not survey values.
* Trees in woods, parks and yards are planted by the game (seeded by
  position, so the same every time); only trees OSM maps one by one are real
  positions.

### Elevation

The ground's shape comes from Natural Resources Canada's High Resolution
Digital Elevation Model (HRDEM), the PEI 2020 lidar project at 1 m, using
the bare-earth model (DTM: the ground with buildings and trees taken out).
It's sampled onto a 2 m grid lined up with the game's coordinates, and
heights are metres above sea level (CGVD2013), so a height in the game is
the real height. Downtown runs from about 11 m at Queen and Grafton down to
about 6 m at Prince and Sydney and 2 m at Queen and Water; the north end of
the city reaches about 50 m. Water and gaps in the survey are set to 1 m
below sea level, so the harbour and rivers show as water.

The heights are stored as centimetres rounded to 5 cm (well inside the
lidar's own accuracy of about 10 cm), in a compressed binary file of about
6.5 MB that the game reads straight into memory (about 22 MB).

Contains information licensed under the Open Government Licence – Canada
(https://open.canada.ca/en/open-government-licence-canada).

### The play area

`map_config.json` "play_area" lists the way round the edge in order:
junctions named by two streets (between two of these the edge follows the
streets listed in "follow", so it hugs the bypass), and points out in the
river or harbour where the shore closes the ring. Those water points are
the one place coordinates are typed, since water has no street names. The
invisible wall sits "margin_m" outside the line. To change the edge, add,
move or remove entries there.

### Landmarks

`map_config.json` has a `landmarks` section keyed by OSM way id (for
example `158560871` is St. Dunstan's Basilica). The footprint still comes
from OSM; the entry adds what OSM doesn't record, like the material, colour,
wall height, towers and spires, or a portico, and which way the front faces
(named by a street or a junction, never by coordinates). These are
best estimates, not measurements, so correct them against the real buildings. To add one, find the building's way id on
openstreetmap.org (click it, the number is in the address bar) and copy an
existing entry.

## Refreshing the map

Needs Python 3 with `osmium`, `rasterio`, `pyproj`, `numpy` and `Pillow`
(`pip install osmium rasterio pyproj numpy Pillow`).

```sh
# 1. Download prince-edward-island-latest.osm.pbf from
#    https://download.geofabrik.de/north-america/canada/prince-edward-island.html
#    into raw/, then cut the city out of it
python3 tools/clip_osm.py raw/prince-edward-island-latest.osm.pbf raw/charlottetown.osm.pbf \
    --bbox 46.2215,-63.1860,46.2795,-63.0970

# 2. convert it to the game's data (data/city/)
python3 tools/osm_to_geojson.py raw/charlottetown.osm.pbf data/city \
    --bbox 46.2215,-63.1860,46.2795,-63.0970 --retrieved 2026-11-21

# 3. elevation (only after widening the box; downloads a window of the lidar)
python3 tools/fetch_elevation.py data/elevation.json --spacing 2

# 4. ground masks (after every OSM refresh)
python3 tools/make_ground_mask.py --resolution 0.5 --coarse 4
```

Step 2 also accepts an OSM `.osm` (XML) file or an Overpass `.json` for a
small area. Please don't fetch the whole city through the OSM API's map
call: OpenStreetMap asks people to use extracts like Geofabrik's for that.

To grow the map, widen the box in steps 1 to 3, then add to the play-area
ring in `map_config.json`. Keep `origin` where it is so the existing
coordinates do not shift.

`raw/` is ignored by git; only the converted data is committed.

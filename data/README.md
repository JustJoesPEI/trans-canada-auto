# Map data

The town is built from these files:

| File | What it is |
|---|---|
| `city/roads.geojson` | Every street, ramp and path in the city, converted from OpenStreetMap, plus the traffic signals, stop signs and crossings. Loaded whole at startup. |
| `city/chunks/X_Z.geojson` | Buildings (with their lidar heights and roofs), ground areas (parks, woods, parking, yards), points like mapped trees, and the lidar's trees, split into 200 m squares. X and Z count squares east and south of the origin. The game loads a square when the player comes near. |
| `city/masks/X_Z.png` | For each square, which ground is lawn, parking or driveway, stone square, farm field, wetland, sand or path, painted from the OSM areas at half a metre per pixel. |
| `city/ground/X_Z.bin` | For each square, what the ground is to drive on (`scripts/world/ground_map.gd`: pavement, gravel, lawn, rough grass, field, bog, sand), a byte per square metre, zlib-compressed. A square with no file is all rough grass. Made with the masks by `tools/make_ground_mask.py`. |
| `city/street_fit.json` | Street widths narrowed to fit between the buildings along them, made by `tools/fit_streets.gd` (see "Street widths" below). Don't edit it by hand. |
| `city/generated_props.json` | Where the game places its own hydrants, lamps, street lights and parked cars, listed for the map editor by `tools/list_generated_props.gd`. The game doesn't read it. |
| `city/index.json` | The area covered, the square size and which squares have data. |
| `elevation.json` + `elevation.bin` | Real ground heights on a 2 m grid over the whole area, from Natural Resources Canada's lidar ground model. The `.json` says where the grid is; the `.bin` holds the heights. Made by `tools/fetch_elevation.py`. |
| `ground_mask.png` | The same as the masks above for the whole area at 4 m per pixel, for the ground further away. |
| `edits.json` | Hand fixes made with the map editor (`tools/map_editor.html`), laid over the OSM data as the game loads it. See "Hand edits" below. |
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
  except on roundabouts and ramps, where the exact shape matters. Two
  junctions joined by less than 12 m of street (like where a divided road
  splits right beside a crossroads) are merged as well. The game also
  merges any two junctions whose curbs wouldn't fit on the street between
  them, worked out from the real road widths (`tools/audit_junctions.gd`
  lists any left).
* Buildings and parks mapped as multipolygons (with holes or several parts)
  keep only their biggest outer ring.
* Service roads (OSM `highway=service` with no `service=` value, or
  `service=alley`) are built as plain asphalt lanes with no curbs,
  sidewalks or paint: the lanes behind downtown blocks, the roads
  through the Ravenwood and Lily Pond area, industrial parks and big lots. Named tracks (Wharf
  Road, Ferry Road) are built the same way. Driveways, parking aisles and
  drive-throughs are only painted on the ground. Which ones are built is
  `minor_roads` in `map_config.json`. Where one meets a street right by a
  junction, it's joined to that junction without moving it.
* Road widths are **not** in OSM for most streets. Downtown they're set
  per street in `map_config.json`, chosen so the curb and sidewalk fit
  between the real building fronts. Elsewhere they're worked out from the
  road type and, where OSM has it, the number of lanes. Treat them as good
  estimates, not survey values.
* Trees come from the lidar survey (see below), plus the ones OSM maps one
  by one downtown.

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

### Building heights, roofs and trees

The same lidar survey comes in two versions: the bare ground (DTM) and the
surface with everything on it (DSM). The difference is how tall whatever
stands there is. `tools/lidar_features.py` reads both for the whole box at
1 m and works out:

* for each building, the height of its roof top and its eaves
  (`lidar_top`, `lidar_eave`, metres above the ground), whether the roof is
  flat, gabled or hipped (`lidar_roof`), and which way the ridge runs
  (`lidar_ridge`: along the footprint's long side or across it). These are
  added to the buildings in the chunk files. About 11,200 of the 11,500
  buildings were measured; the rest weren't there in 2020 or are under trees.
* every tree top in the canopy outside buildings: its spot, height and
  crown size, and whether it looks like a conifer (a sharp, narrow top).
  About 63,000 trees, stored in each chunk as one "trees" feature.

The survey is from 2020, so anything built or cut down since then isn't in
it.

### Brands

Buildings keep OSM's `brand` tag (like `Tim Hortons`), which is how the
game's world brands find every location of a chain. See "World brands" in
the main README.

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

Needs Python 3 with `osmium`, `rasterio`, `pyproj`, `numpy`, `scipy` and
`Pillow` (`pip install osmium rasterio pyproj numpy scipy Pillow`).

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

# 5. building heights, roofs and trees from the lidar (after every OSM
#    refresh, since step 2 rewrites the chunks; needs scipy too)
python3 tools/lidar_features.py
```

Step 2 also accepts an OSM `.osm` (XML) file or an Overpass `.json` for a
small area. Please don't fetch the whole city through the OSM API's map
call: OpenStreetMap asks people to use extracts like Geofabrik's for that.

To grow the map, widen the box in steps 1 to 3, then add to the play-area
ring in `map_config.json`. Keep `origin` where it is so the existing
coordinates do not shift.

`raw/` is ignored by git; only the converted data is committed.


## Street widths

Most street widths come from the road type, which is too wide for the old
lanes and the streets where houses stand close. `tools/fit_streets.gd`
measures, every metre along each stretch of street, how far it is to the
nearest building wall on each side, and narrows the street where it
doesn't fit: the sidewalk first (to 1.2 m), then the roadway (to 5.5 m
two-way, 3.5 m one-way, 3 m for service roads), then the sidewalk away
altogether. It writes `city/street_fit.json`, which the game applies as it
builds the streets.

```sh
godot --headless --path . --script res://tools/fit_streets.gd
godot --headless --path . --script res://tools/audit_roads.gd   # what's left
```

Run it again after an OSM refresh, after adding or moving streets or
buildings, or after changing widths in `map_config.json`. Each fit records
the width it was made from, so a stale one is skipped, never misapplied.
Streets given a `tca:width` or `tca:sidewalk` in the map editor are never
fitted: the hand width wins. A building the centreline itself runs into
(closer than 1 m) is taken as a mistake in the map, not fitted round;
`tools/audit_roads.gd` lists those, and the streets OSM has that the game
doesn't build.


## Hand edits

`edits.json` holds the fixes made with `tools/map_editor.html`. `StreetData`
(`scripts/world/street_data.gd`) applies them as it loads the files above,
so nothing in `city/` is changed and a fresh OSM conversion keeps them.
Positions are `[longitude, latitude]` like GeoJSON, except `removed_trees`,
which are game metres.

| Key | What it holds |
|---|---|
| `nodes` | Street points by OSM node id: moved points, and new ones (`edit:n1`...). A moved junction moves for every street through it. |
| `roads` | Changes to streets by way id: `{"delete": true}`, or `"tags"` (a value of `null` removes the tag) and/or a new `"nodes"` list. |
| `new_roads` | New streets: `{"id": "edit:r1", "tags": {"highway": ...}, "nodes": [...]}`. A node shared with another street joins them there. |
| `features` | Changes to buildings, areas and points by `"kind:osm_id"`: `{"delete": true}`, or `"tags"` and a new `"ring"` (outline) or `"pos"`. |
| `new_features` | New buildings, areas and points: `{"id", "kind", "tags", "ring" or "pos"}`. Props are points of type `prop=<name>` (see `scripts/world/placed_props.gd`) and signs `sign=<kind>` (see `scripts/world/placed_signs.gd`, with `text`, `colour`, `text_colour`, `width`, `height`, and for a billboard `ad`, artwork from `textures/ads/`), with `direction` in compass degrees. |
| `removed_trees` | Lidar trees to leave out, as game `[x, z]`: the nearest tree within 1.5 m goes. |
| `erased_props` | Spots `[x, z, radius]` (game metres) where the game leaves out its own hydrants, lamps, street lights and parked cars. |
| `lines` | Fences, walls, hedges and guardrails: `{"id", "kind", "pts": [[lon, lat], ...], "height"?}`. Kinds are in `scripts/world/edit_lines.gd`. |
| `spawn` | Where the player starts, `{"pos": [lon, lat], "direction": compass degrees}`, instead of map_config.json "spawn". |
| `player_cars` | The cars waiting at the start, `{"pos", "direction", "model", "colour"}`. When there are any, they replace map_config.json "parked_cars". |
| `notes` | Requests for help: a loop round a spot and what should change there. The game ignores them. |

Street tags `tca:width`, `tca:sidewalk` and `tca:shoulder` (metres) set a
street's curb-to-curb width, sidewalk width and shoulder, overriding the
class defaults and `street_overrides`. Building heights in the editor are the
lidar tags (`lidar_eave` the wall height, `lidar_top` the peak, `lidar_roof`
flat, gabled or hipped), which the building generator already prefers.

OSM's `cycleway=lane` or `cycleway:both=lane` on a two-way street paints a
bike lane along each curb: a solid white line `tca:bike_lane` metres out
(1.6 by default) with a bicycle and arrow just past each junction and every
80 m. The 2026-11-21 extract was made before these tags were kept, so the
stretch of St Peters Road through Allen Street and Beasley Avenue has them
as hand edits, with its curb-to-curb width (`tca:width` 10.6), from Joe's
photo stopped at the lights there.

`test_start.json` (beside this file, ignored by git) is the map editor's
"Test here" spot, `{"pos", "direction", "car", "model"}`: while it's there
the game starts you at it, beside a car of that model if `car` is true.

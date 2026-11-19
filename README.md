# Charlottetown (prototype)

A small open-world game set in downtown Charlottetown, PEI, built in Godot 4
with GDScript. The street layout comes from real OpenStreetMap data. The aim
right now is a prototype that feels good to move around in, not a full game.

**Status: Milestone 1 (playable streets) runs in Godot 4.7.2 with no
errors.** See "What has been tested" below.

## Starting it

1. Install **Godot 4.7** (standard build, not .NET): https://godotengine.org/download
2. Open Godot, choose **Import**, and pick `charlottetown/project.godot`.
3. Press **F5** (or the play button). The town is built from the map data
   when the scene starts, which takes a second or two.

The first time you open the project Godot imports it, and you may see it
write `.godot/` and some `.uid` files. That's normal; `.godot/` is ignored
by git.

## Controls

| Action | Keyboard and mouse | Xbox controller |
|---|---|---|
| Walk | W A S D or arrow keys | Left stick |
| Run | Hold Shift | Hold A |
| Look around | Mouse | Right stick |
| Zoom camera | Mouse wheel, or + and - | D-pad up and down |
| Reset camera behind you | C | Click right stick |
| Free the mouse | Esc (click to take it back) | Start |
| Interact (cars, from Milestone 2) | E or F | Y |

Driving controls are already bound for Milestone 2: W/S or the triggers to
accelerate and brake, A/D or the left stick to steer, Space or B for the
handbrake. All bindings live in `scripts/autoload/input_setup.gd`.

## What's in Milestone 1

* **Real streets.** The play area is the four blocks between Queen, Grafton,
  Prince and Sydney streets, with Great George, Richmond and Church streets
  inside it, all at their true positions and angles. (Great George between
  Grafton and Richmond is the pedestrian plaza by Province House, so there's
  no road there, just as in town.) About 120 m of the surrounding streets is
  built too, as scenery past the edge of the play area.
* **Roads, curbs and sidewalks** generated from the OSM centrelines, with
  the curb corners worked out at every intersection so sidewalks meet cleanly.
  Widths are set per street in `data/map_config.json`.
* **Centre lines** on two-way streets, and **crosswalks** wherever OSM maps a
  marked crossing.
* **474 buildings** extruded from their real OSM footprints: brick
  storefronts, clapboard houses with gable roofs, sandstone civic buildings.
  Heights use OSM's height and level tags where they exist.
* **Street-name signs** at each intersection, **stop signs** where OSM maps
  them, **traffic lights** (cycling, for looks only so far) at the junctions
  OSM marks as signalled, and **trees** where OSM maps them.
* **The player**: a plain low-poly person with normal proportions who walks,
  runs, turns smoothly, steps up curbs and bumps into buildings, poles and
  trees.
* **Camera**: an elevated three-quarter view that follows smoothly, orbits,
  zooms, and dithers away any building that comes between it and you.
* **The edge of the play area** is an invisible wall about 30 m past the
  outer streets, with road-closed barriers wherever a street crosses it.
* **HUD**: the name of the street you're on, a controls reminder, and the
  OpenStreetMap credit.

## Project layout

| Folder | What's there |
|---|---|
| `data/` | The street data (`downtown.geojson`) and how to read it (`map_config.json`). See `data/README.md`. |
| `tools/` | Python scripts to fetch OSM data, convert it, and preview the map as an SVG. |
| `scenes/` | `main.tscn` (lighting, sky, and the pieces below), `player/`, `camera/`. |
| `scripts/autoload/` | `InputSetup` (all controls) and `GameState` (money and the save file). |
| `scripts/world/` | Building the town: `world_builder.gd` runs it; `street_data.gd` loads the data, `geo_projection.gd` turns latitude and longitude into metres, `road_network.gd` is the street graph and curb maths, `road_mesher.gd`, `building_generator.gd` and `street_props.gd` make the geometry. |
| `scripts/player/`, `scripts/characters/`, `scripts/camera/`, `scripts/ui/` | The player, the reusable person model, the camera rig, the HUD. |
| `shaders/` | Building walls (windows, brick, siding drawn in the shader) and roofs. |

Coordinates: 1 unit = 1 metre, +X is east, -Z is north, and the origin is
the Great George / Richmond junction. Physics layers are named in
`scripts/world/layers.gd`.

## Checking the map without Godot

```sh
python3 tools/preview_map.py preview.svg
```

That draws the roads, sidewalks, buildings and play area using the same
corner maths as the game. It's a quick way to check a width change or a data
refresh.

## What has been tested

* All GDScript files pass `gdparse` (gdtoolkit 4.5), so there are no syntax
  errors. That does **not** check types or run anything.
* The street geometry was checked by drawing it with `tools/preview_map.py`.
* The OSM conversion was run on the real download (2026-11-19).
* The project imports and runs in Godot 4.7.2 with no errors or warnings
  from the game's scripts. It builds the town (87 street segments, 70
  junctions, 468 buildings) in about 0.2 seconds.
* In-game screenshots were taken with the game's own camera, rendered in
  software (no graphics card), at the spawn point, on Richmond Street, and at
  three junctions. Nobody has played it with a keyboard or controller yet,
  so how walking and the camera feel is still untested.

## Known issues and limits

* The road-closed barriers sit only about 30 m past the outer streets, so
  they're visible from the start point.
* Shopfront glass runs the whole width of the ground floor, with no doors.
* A few larger gable roofs look too big for their walls.
* Street-name signs are hard to read from the default camera height.
* Road and sidewalk widths are estimates. OSM doesn't record them for these
  streets, so they were chosen to fit between the real building fronts.
* Street parking lanes and Queen Street's diagonal parking aren't painted
  yet, and there are no lane lines on one-way streets.
* Gable roofs only go on houses whose footprint is close to a rectangle.
  Everything else gets a flat roof.
* Traffic lights cycle but nothing obeys them yet.
* Esc only frees the mouse. The pause menu comes with Milestone 4.
* Exporting a build: add `*.geojson, *.json` to the export preset's
  "Filters to export non-resource files" so the map data is included.

## Next milestone

**Milestone 2: Driving.** One ordinary older four-door sedan with custom
arcade-leaning physics (accelerate, brake, reverse, coast, steer, collide),
driving parameters as exported variables, entering and exiting from the
driver's side with E / Y, and the camera switching to a lower chase view
while driving. The input bindings and the camera's `set_profile()` and
`auto_follow_yaw` are already in place for it.

## Credits

Map data © OpenStreetMap contributors, under the Open Database License
(https://www.openstreetmap.org/copyright). See `data/README.md`.

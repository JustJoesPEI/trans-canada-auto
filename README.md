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

## If nothing happens when you press play

* **Nothing opens at all when you start Godot:** make sure you unzipped
  Godot first and are running the `.exe` from the unzipped folder, not from
  inside the zip. Windows may show a "Windows protected your PC" box; choose
  "More info", then "Run anyway".
* **The Project Manager opens but the project isn't listed:** click
  **Import** and pick `project.godot` inside the unzipped `charlottetown`
  folder.
* **The editor is open but pressing F5 / play does nothing:** look at the
  **Output** panel along the bottom of the editor and copy what it says.
  Also check the taskbar: the game opens in its own window, which can end up
  behind the editor.
* **The game window opens but stays black or grey:** older or very basic
  graphics chips can't run Godot's default renderer. Start Godot from a
  command prompt with `--rendering-driver opengl3`, or in the editor go to
  Project > Project Settings > Rendering > Renderer and choose
  "gl_compatibility". The game works in that mode too.

## Controls

| Action | Keyboard and mouse | Xbox controller |
|---|---|---|
| Walk | W A S D or arrow keys | Left stick |
| Run | Hold Shift | Hold A |
| Look around | Mouse | Right stick |
| Zoom camera | Mouse wheel, or + and - | D-pad up and down |
| Reset camera behind you | C | Click right stick |
| Free the mouse | Esc (click to take it back) | Start |
| Get in or out of the car | E or F (at the driver's door) | Y |
| Accelerate | W or Up | Right trigger |
| Brake, then reverse once stopped | S or Down | Left trigger |
| Steer | A D or Left Right | Left stick |
| Handbrake | Space | B |

All bindings live in `scripts/autoload/input_setup.gd`.

## Driving

The car is an ordinary older four-door sedan, parked on Grafton Street just
past Great George when you start. Walk up to the driver's door (on the
left) and press E. You sit inside, visible through the glass, and the camera
drops to a lower chase view that swings in behind the car. Slow below about
8 km/h and press E again to step out.

The physics is simple but honest rather than a canned arcade model. Each
axle's tyres grip with a force that builds with slip and then levels off at
what the road allows, so the car has weight, carves corners, and slides if
you push too hard or pull the handbrake. The engine has a power curve, and
brakes, rolling resistance and air drag do the rest, so it coasts when you
lift off and finds its own top speed. Steering lock shrinks with speed, and
below a few km/h it switches smoothly to exact low-speed steering so parking
is tidy. The body pitches and rolls with braking and cornering and rides
over curbs wheel by wheel. Hitting a wall slides you along it and costs
speed rather than stopping you dead.

Measured on a flat test pad with scripted inputs:

| | |
|---|---|
| 0 to 50 km/h | 3.0 s |
| 0 to 100 km/h | 7.9 s |
| Top speed | 130 km/h |
| Braking, 100 to 0 | 44.7 m (0.86 g) |
| Braking, 50 to 0 | 11.5 m |
| Coasting from 50 for 3 s | down to 43 km/h |
| Turning circle at walking pace | about 8 m |
| Cornering grip | about 0.9 g |
| Slalom at 60 km/h | stays composed, under 4° of slide |
| Handbrake turn from 50 | swings round about 150° |
| Reverse | up to 22 km/h |

Every number above comes from settings on the car (`scripts/vehicles/car.gd`),
grouped in the Inspector: engine and brakes, grip and handling, steering,
and body motion. The driving camera has its own group on CameraRig.

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
* **Buildings from their real OSM footprints**, styled like downtown
  Charlottetown: two- to four-storey Victorian brick blocks with arched
  windows, cornices and shopfronts (some with awnings), clapboard and
  cedar-shingle houses with steep gables, white trim and coloured doors, and
  sandstone public buildings. Heights use OSM's height and level tags where
  they exist.
* **Landmarks**, matched to their OSM footprints by id in
  `data/map_config.json`: St. Dunstan's Basilica with its twin spires at the
  foot of Great George Street, Province House with its columned portico,
  Confederation Centre in pale sandstone, St. Paul's and Trinity United
  churches with their towers, and City Hall's clock tower. Their colours, heights
  and towers are best estimates, not measurements, and worth checking
  against the real buildings.
* **The ground between the streets** from OSM: lawns and parks, parking
  lots, stone-paved squares, brick footpaths, and Victoria Row's brick street.
* **Street-name signs** at each intersection, **stop signs** where OSM maps
  them, **traffic lights** (cycling, for looks only so far) at the junctions
  OSM marks as signalled, **trees** where OSM maps them, and black
  **heritage lamp posts** along every sidewalk.
* **The player**: a low-poly person with normal proportions (red fall jacket,
  jeans), built as one smooth skinned mesh on a small skeleton, so each
  person is a single draw call (pedestrians will use the same model with
  random looks: build, height, hair, clothes, some in knit hats), and a walk worked out from speed rather than a canned clip: stride
  and pace match the ground speed, knees bend through each step, hips sway,
  arms swing with the opposite leg, and a run leans forward with bent arms.
  Standing still, they breathe and shift their weight. A light touch on the
  stick strolls, full tilt walks, and Run runs. They turn toward where you
  push and move the way they face, so a run carves a wider turn, and a sharp
  reversal at a run slows down first. They step up curbs and stop against
  buildings, poles and trees without running on the spot.
* **Camera**: a third-person camera that frames you in the lower part of
  the screen with the street ahead in view. Zooming slides it along a curve,
  from low and behind your back (close in) up to a nearly overhead view
  (zoomed out), and the mouse tilts it on top of that; pull the mouse down to
  look up at the spires. It follows on smooth springs, looks a little ahead
  of where you're going, pulls back and widens a touch when you run, and
  eases back in behind you after a moment without camera input. If a
  building would come between you and the camera, it moves in quickly and
  eases back out after; buildings and tree crowns that still block the view
  fade out of the way. All the tuning numbers (distance, angles, follow
  times, recentring) are exported variables on the Player and CameraRig
  nodes, grouped in the Inspector.
* **The edge of the play area** is an invisible wall about 55 m past the
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
| `scripts/player/`, `scripts/characters/`, `scripts/camera/`, `scripts/ui/` | The player, the reusable person model (`body_builder.gd` makes the mesh), the camera rig, the HUD. |
| `scripts/vehicles/` | The car: `car.gd` (driving physics) and `car_builder.gd` (the sedan's mesh). |
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
  so how walking, driving and the camera feel is still untested.
* The car's numbers in the Driving section were measured by driving the real
  car on a test pad with scripted inputs, and it was recorded driving round
  the block downtown with a small driver script pressing the controls.

## Known issues and limits

* Big churches get a simple nave roof; transepts and apses aren't modelled.
* Landmark details (towers, portico, colours) are set by hand in
  `data/map_config.json` and are close to the real buildings, not exact.
* Road and sidewalk widths are estimates. OSM doesn't record them for these
  streets, so they were chosen to fit between the real building fronts.
* Street parking lanes and Queen Street's diagonal parking aren't painted
  yet, and there are no lane lines on one-way streets.
* Gable roofs only go on houses whose footprint is close to a rectangle.
  Everything else gets a flat roof.
* Traffic lights cycle but nothing obeys them yet, and there's no other
  traffic.
* There's one car. Parked cars and more models come with Milestone 3.
* Bumping a wall costs speed, but cars don't dent and there are no sounds yet.
* Esc only frees the mouse. The pause menu comes with Milestone 4.
* Exporting a build: add `*.geojson, *.json` to the export preset's
  "Filters to export non-resource files" so the map data is included.

## Next milestone

**Milestone 3: Living environment.** Pedestrians walking the real
sidewalks (the person model already supports random looks), parked cars
along the curbs, and more street furniture.

## Credits

Map data © OpenStreetMap contributors, under the Open Database License
(https://www.openstreetmap.org/copyright). See `data/README.md`.

# Trans-Canada Auto (TCA)

An open-world driving game set in real Canadian places, built in Godot 4
with GDScript. Each map is a real place: the streets, buildings, parks and
woods come from OpenStreetMap, the ground, building heights and trees from
a real lidar survey. The plan is to grow a map at a time, the way the
Trans-Canada runs province to province.

**The first map is Red Clay: Charlottetown, Prince Edward Island.** Right
now it's a prototype that feels good to move around in, not a full game.

Website (coming): playtca.ca

**Status: all of Charlottetown inside the bypass is playable** (Riverside Drive,
the Arterial Highway, Upton Road and Capital Drive round the outside, the
North River and the harbour on the other sides), built and streamed in
around you as you go. It runs in Godot 4.7.2 with no errors. See "What has
been tested" below.

## Starting it

1. Install **Godot 4.7** (standard build, not .NET): https://godotengine.org/download
2. Open Godot, choose **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the play button). A loading screen stays up while
   downtown is built from the map data (a few seconds, done in small steps
   so the window, or the browser page, never stops responding), then the
   title menu comes up and the rest of the city fills in round you.

The first time you open the project Godot imports it, and you may see it
write `.godot/` and some `.uid` files. That's normal; `.godot/` is ignored
by git.

## Making a click-to-play version

The project includes an export preset for Windows. In Godot: Editor >
Manage Export Templates > Download and Install (once), then Project >
Export, pick "Windows Desktop" and Export Project. You get a single
`TransCanadaAuto.exe` (about 130 MB) with everything packed inside, including
the map data. Windows will warn the first time because the game isn't
signed: "More info", then "Run anyway".

From a command line, with the templates installed:

```sh
godot --headless --path . --export-release "Windows Desktop" export/TransCanadaAuto.exe
```

## New versions and itch.io

Every change pushed to `main` is built automatically for Windows and the
web by GitHub (`.github/workflows/build.yml`); the builds are kept on each
run under the repository's **Actions** tab. Once the itch.io key is set up,
the same build goes straight to the game's itch.io page, and the itch app
updates the game on your computer by itself. Setting up the page, the key,
the text and the images: `docs/itch-page.md`.

The browser version uses Godot's web export (the Compatibility renderer,
so it looks like Low graphics). It's about 60 MB to load the first time,
then cached, and it needs the "SharedArrayBuffer support" option on
itch.io so the town can be built on background threads.

## Branding

The TCA shield, the loading screen, the title art, the window icon and the
itch.io cover, banner and background are all drawn by
`tools/make_branding.py` into `branding/`, from shapes and the free DejaVu
Sans font: highway-sign green and white, with red clay for PEI's map. Change
the script and run it again to redraw them all. The screenshots for the
itch page are in `branding/screens/`.

The game opens on a **title menu** over the live town (Play, Graphics,
Controls, Credits, Quit); Esc brings it back as a pause menu. It's in
`scripts/autoload/title_menu.gd`.

## If nothing happens when you press play

* **Nothing opens at all when you start Godot:** make sure you unzipped
  Godot first and are running the `.exe` from the unzipped folder, not from
  inside the zip. Windows may show a "Windows protected your PC" box; choose
  "More info", then "Run anyway".
* **The Project Manager opens but the project isn't listed:** click
  **Import** and pick `project.godot` inside the unzipped `trans-canada-auto`
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
| Menu (pause) | Esc | Start |
| Graphics High / Low | F10 | |
| Leave a note about this spot | N | |
| Open the folder with your notes | F9 | |
| Get in or out of the car | E or F (at the driver's door) | Y |
| Accelerate | W or Up | Right trigger |
| Brake, then reverse once stopped | S or Down | Left trigger |
| Steer | A D or Left Right | Left stick |
| Handbrake | Space | B |

All bindings live in `scripts/autoload/input_setup.gd`.

## Leaving notes (and sending photos)

To point something out in the town, for a fix or something new to build,
aim the middle of the screen at it and press **N**. Type the note ("this
house is yellow with a red door and a white porch", "a gazebo goes here")
and press Enter. The game pauses while you type.

The note is copied to the clipboard, so you can paste it straight into a
chat with Claude. It reads like this:

```
TCA note 3, Red Clay (2026-11-22 14:05:12): this house is yellow with a red door
  Looking at: building OSM way 28326012 "Queen Parkade", 26 m away, at 46.235931, -63.129089 (game x -271.3, z -143.3)
  Standing: on Grafton Street at 46.235493, -63.126560 (game x -76.1, z -94.8), facing north-west (315 degrees)
```

That's enough to find the exact building or spot. Every note is also kept
in `notes.txt` in the game's own folder (press **F9** to open it; on
Windows it's `%APPDATA%\Godot\app_userdata\Trans-Canada Auto`), so you can
send them all at once. A numbered orange pin marks each note's spot in the
town and stays there next time you play. Delete `notes.txt` and
`notes.json` to clear them.

**Photos** work the same way: take them with your phone's location turned
on for the camera, and send them as they are (not screenshots of them).
Phones record where each photo was taken and usually which way they were
pointing, so each one can be matched to its building. A photo straight on
to the front of a building, in daylight, is the most useful.

The changes from notes go in `data/map_config.json` under "landmarks", by
the building's OSM id. A small entry (just a colour, say) keeps the
building's measured lidar height and roof.

## World brands

Real chains in town are replaced by made-up ones, the way the cars are
(Dunmore, Hanaka, Fjord) and the way GTA does it. Each world brand keeps
the real chain's colours, so you know at a glance what it is, but has its
own name: Double Double for the coffee and donut shop, MacDougall's for the
burgers, SoBuys for the grocery store, and so on. Every location of a chain
changes at once, matched by the brand or name OpenStreetMap gives the
building, and new locations follow as they're mapped.

They're set in `data/map_config.json`: "brands" lists each world brand with
the real chains it replaces, its kind and its colours (`sign_colour` for
the board, `sign_text` for the letters), and "brand_kinds" gives each kind
its usual look. Grocery and big-box stores get a big sign high on the side
facing their car park (it grows with the store, about 4 m tall on a 100 m
front), a stripe of the brand's colour along the top of that wall, a dark
base, and a glass entrance vestibule under the sign, plus a second sign
facing the street. Coffee shops, burger places and gas stations get a board
over the door and a glass shopfront.

**Gas station canopies** are drawn wherever OSM maps one (as a roof over
the pumps): about 5 m up on a row of posts, with a deep fascia in the
brand's colours and its name on both long sides, and a pump island with a
pump each side at every post. You can drive under it; the posts and pumps
are solid. Other roofs mapped on their own (carports, shelters) get a thin
roof on corner posts. To rename a brand,
change its name in "brands". Only chains with a building of their own are
drawn this way; ones mapped as a single point inside a mall don't have a
building to put the sign on.

| World brand | Kind | Stands in for |
|---|---|---|
| Double Double | coffee | Tim Hortons |
| Wren's Donuts | coffee | Robin's Donuts |
| Starbeans | coffee | Starbucks |
| MacDougall's | burgers | McDonald's |
| Burger Baron | burgers | Burger King |
| Windy's | burgers | Wendy's |
| A-OK Root Beer | burgers | A&W |
| Cluckers | burgers | KFC |
| Sub Station | burgers | Subway |
| Dairy Duchess | burgers | Dairy Queen |
| Portland Pizza | pizza | Boston Pizza |
| Wyoming's | pizza | Montana's |
| SoBuys | grocery | Sobeys |
| Maritime Megastore | grocery | Atlantic Superstore, Real Canadian Superstore |
| Food Island | grocery | Foodland |
| Wants | gas | Needs |
| Shamrock Farm | gas | Clover Farm |
| Ervin's | gas | Irving |
| Exo | gas | Esso |
| Petro-North | gas | Petro-Canada |
| Ultrasea | gas | Ultramar |
| Clam | gas | Shell |
| Square Q | gas | Circle K |
| BuyMart | big box | Walmart |
| Maple Tire | big box | Canadian Tire |
| The House Depot | big box | The Home Depot |
| Hearth Hardware | store | Home Hardware |
| Staplers | store | Staples |
| Gulf | store | Gap |
| Reelplex | cinema | Cineplex |
| Stoppers Drug Mart | pharmacy | Shoppers Drug Mart |
| PharmaChance | pharmacy | PharmaChoice |
| Royal Island Bank | bank | RBC |
| Fundy Bank | bank | Scotiabank |
| Dominion Trust | bank | TD |
| Imperial Commerce | bank | CIBC |
| Quality Stay | hotel | Quality Inn |
| Comfy Inn | hotel | Comfort Inn |
| Budget Lodge | hotel | Econo Lodge |
| Hamlet Inn | hotel | Hampton |
| Hanaka | car dealer | Toyota, Honda |
| Nissun | car dealer | Nissan |
| Hyunsung | car dealer | Hyundai |
| Kyo | car dealer | Kia |
| Subtaru | car dealer | Subaru |
| General Motorworks | car dealer | General Motors |
| Take 6 | store | Take 5 |

## Graphics setting

There are two graphics levels, **High** (the default) and **Low**. Press
**F10** in the game to switch; a note in the corner says which one you're
on, and the choice is remembered next time. Low is for older or basic
graphics chips:

| | High | Low |
|---|---|---|
| Soft shadows that sharpen near the object | yes | plain soft-edged shadows, out to 90 m instead of 160 m |
| Shading in corners and under ledges (SSAO) | yes | no |
| Light bouncing off walls and the street (SSIL) | yes | no |
| Glow round lamp glass | yes | no |
| Fine relief on brick, slabs and boards, and depth in the windows | yes | flat (same colours) |
| Trees swaying | yes | no |
| Full detail round you (curbs, lamps, signs, everything solid) | 330 m | 230 m |
| How far the simpler distant town reaches | 1 km | 750 m |

The town looks the same at a glance either way. To start on Low, run the
game with `-- --graphics=low`. When the game runs on the Compatibility
(OpenGL) renderer it starts on Low unless you've picked High with F10.
The setting lives in `scripts/autoload/graphics.gd`.

## Driving

Three cars are parked in a row on Grafton Street, just past Great George,
when you start. Walk up to a driver's door (on the left) and press E. The
car's name comes up as you get in, you sit inside, visible through the
glass, and the camera drops to a lower chase view that swings in behind the
car. Slow below about 8 km/h and press E again to step out.

The brands are made up, the way GTA spoofs real cars:

| Car | What it is | How it drives |
|---|---|---|
| **Dunmore Pony GT** | Two-door coupe, rear-wheel drive | Light and punchy. Planted if you're smooth, but floor it in a corner and the tail steps out; catch it with opposite lock and you can hold a drift. |
| **Hanaka Civique** | Four-door sedan, front-wheel drive | The sensible one. Goes where you point it; too much throttle in a corner just pushes it wide. |
| **Fjord Halfton 150** | Pickup truck, rear-wheel drive | Heavy, tall and soft. Leans in the corners, stops longer, and the light back end can come round if you provoke it. |

The physics is simple but honest rather than a canned arcade model. The
engine drives each car's real wheels (front, rear or all four) with a
power curve, and brakes, rolling resistance, air drag and the slope of the
road do the rest. Weight shifts forward under braking and back under power,
and each axle's tyres grip in proportion to the weight on them. A tyre has
only so much grip to share between pushing and cornering: spin the rear
tyres of a rear-drive car in a corner and the tail comes out, while a
front-drive car runs wide instead. A spinning tyre still keeps some
sideways grip, so slides can be caught. Steering lock shrinks with speed,
and below a few km/h it switches to exact low-speed steering so parking is
tidy. The handbrake locks the rear wheels: a short tug swings the tail, a
long pull at 50 km/h turns you round. The body pitches and rolls and rides
over curbs wheel by wheel, and hitting a wall slides you along it.

Measured on a flat test pad with scripted inputs:

| | Pony GT | Civique | Halfton 150 |
|---|---|---|---|
| 0 to 100 km/h | 5.2 s | 8.0 s | 7.0 s |
| Top speed | 189 km/h | 157 km/h | 165 km/h |
| Braking, 100 to 0 | 40.7 m | 44.8 m | 50.2 m |
| Cornering grip at 50 km/h | 0.92 g | 0.98 g | 0.87 g |
| Slalom at 60 km/h, most it slides | 16° | 3.5° | 2.4° |
| Full throttle at full lock, 45 km/h | tail comes out (spins if you don't catch it) | runs wide, no slide | tail comes out |
| Drift caught with opposite lock | held for 1.8 s of 3 | can't be provoked | needs more provoking |
| Handbrake, 1.5 s pull from 50 km/h | swings round 205° | 194° | 193° |

Each car's numbers (power, weight, grip, balance, steering, how soft the
body is) live in one place, `scripts/vehicles/car_models.gd`, along with its
name, colours and shape. Where they're parked is in `data/map_config.json`
("parked_cars"). The driving camera has its own group on CameraRig.

## What's in the game so far

* **The whole city, from real streets.** Everything inside the bypass is
  playable: downtown, the waterfront and Victoria Park, University Avenue,
  Sherwood, Parkdale, West Royalty, East Royalty out to the Arterial
  Highway, all at their true positions and angles. You can drive the whole
  ring: up Riverside Drive from the Hillsborough Bridge junction, round the
  Arterial Highway past Malpeque Road and University Avenue to the Upton
  Road roundabout, down Upton Road to the Capital Drive roundabout, left
  onto Capital Drive and back into town by North River Road. About 11,500
  buildings and 2,000 stretches of street in all. (Great George between
  Grafton and Richmond is the pedestrian plaza by Province House, so there's
  no road there, just as in town.)
* **Roads, curbs and sidewalks** generated from the OSM centrelines, with
  the curb corners worked out at every intersection so sidewalks meet cleanly.
  Widths are set per street in `data/map_config.json` downtown and worked
  out from the road type and lane count elsewhere.
* **Highways**: the bypass, Riverside Drive and their ramps are built
  highway style, with paved shoulders, white edge lines, lane lines, a solid
  double yellow down the middle where they're two-way, and gravel verges
  instead of curbs and sidewalks. **Roundabouts** are built from their real
  shape. **Divided roads** (two one-way carriageways side by side, like
  University Avenue and Capital Drive) have a median curb on the inside
  instead of a sidewalk. Roundabouts have a raised grass **island** with a
  curb. Where two roads overlap (a roundabout and the roads flaring into
  it, a ramp joining a highway) only one surface is drawn, and sidewalks,
  paint, signs, signals and lights are kept off every roadway, not just
  their own. **Bridges** keep a straight deck from end to end
  with a concrete parapet down each side, whatever the ground does below.
* **Centre lines** on two-way streets, lane lines on wide one-way streets,
  and **crosswalks** wherever OSM maps a marked crossing.
* **Buildings from their real OSM footprints.** Downtown (within about
  900 m of Great George and Richmond) they're styled like downtown
  Charlottetown: two- to four-storey Victorian brick blocks with arched
  windows, cornices and shopfronts (some with awnings), clapboard and
  cedar-shingle houses with steep gables, white trim and coloured doors, and
  sandstone public buildings. Heights and roofs are **measured from the lidar
  survey** wherever it saw the building (all but about 300 of them): the
  real height to the eaves and the ridge, whether the roof is flat, gabled or
  hipped, which way the ridge runs and how steep it is. Where the survey
  didn't see a building (built after 2020, or hidden by trees) the height
  comes from OSM's height and level tags or a good guess. Cornices are stepped, with a bracket between each window bay,
  parapets have a stone coping, and gable roofs have white fascia and barge
  boards. The walls are drawn in a shader: brick with mortar joints you can
  see the light catch, lapped clapboard, grime splashed up the bottom of the
  wall and rain streaks under the sills. Windows sit back in the wall (the
  sides of the opening show as you walk past), and each one is different
  behind the glass: a dark room, curtains, a blind part way down, or a lamp
  on. Roofs have shingle courses with streaks and a little moss; flat roofs
  are tar and gravel. Out in the rest of the city, house-sized buildings
  are clapboard and shingle houses, and big ones (the mall, schools, the
  hospital, plants and warehouses) are plain modern buildings in concrete
  and grey or beige cladding, without shopfronts.
* **Facade detail (prototype).** Near the player, walls are built with
  real holes for the windows, doors and shop windows, with the glass set
  back 8 to 25 cm and the sides of each opening showing. Brick, sandstone,
  clapboard and cedar shingle use photographed textures (CC0, from Poly
  Haven, packed into `textures/facade/`) tinted to each building's colour.
  Windows get projecting sills and heads (masonry) or casings (wooden
  houses); every building stands on a fieldstone foundation; most pitched
  roofs get a brick chimney; houses facing a street usually get a front
  porch with steps, posts and railings; front doors get stone steps; colours
  are toned down to look weathered. Start the game with `-- --flat-facades`
  to see the old flat walls (and the old trees and no street clutter) for
  comparison.
* **Street clutter (prototype).** Wooden utility poles with crossarms,
  transformers and sagging wires down one side of every street outside
  downtown, and cars parked along the curbs (`scripts/world/street_clutter.gd`).
  Trees are made of leaf cards using a leaf texture drawn by
  `tools/make_leaf_atlas.py`.
* **The look**: daylight with a warm, fairly low sun, soft shadows, a deep
  blue sky that fades to haze at the horizon, and a light haze over
  distance. Colours go through AgX tonemapping (so bright skies and white
  trim don't blow out), with ambient occlusion in corners and light bounced
  off walls. The aim is grounded and readable rather than photographic.
* **Landmarks**, matched to their OSM footprints by id in
  `data/map_config.json`: St. Dunstan's Basilica with its twin spires at the
  foot of Great George Street, Province House with its columned portico,
  Confederation Centre in pale sandstone, St. Paul's and Trinity United
  churches with their towers, and City Hall's clock tower. Their colours, heights
  and towers are best estimates, not measurements, and worth checking
  against the real buildings.
* **Real elevation** from Natural Resources Canada's lidar survey of PEI
  (2020): the ground, streets, sidewalks, buildings and street furniture all
  follow the true slopes, from the shore up to about 50 m in the north end
  of the city; about 11 m above sea level at Queen and Grafton, 6 m at
  Prince and Sydney and 2 m at Water Street. Buildings stand
  at their uphill ground level and show a foundation on the downhill side.
  The car feels the grade (it rolls downhill and works uphill), and the
  harbour sits at sea level where the land drops below it.
* **The ground between the streets** from OSM: lawns, yards, parks and
  playing fields, parking lots and driveways, stone-paved squares, brick
  footpaths and gravel trails, and Victoria Row's brick street, painted onto
  the terrain so they follow the slope. Commercial and industrial land is
  asphalt; ground nobody has mapped is rough grass. **Parking lots** are
  asphalt with oil stains and white stall lines: along every parking aisle
  mapped in OSM, and in rows laid out along the lot where no aisle is
  mapped.
* **Streets that look used**: weathered asphalt with darker repair patches,
  hairline cracks, polished wheel paths, oil drips down each lane and grit
  in the gutters; worn paint; concrete sidewalks laid in slabs with a
  separate curb stone, the odd gum spot, and curbs grimy from road spray.
* **Street-name signs** at each intersection, **stop signs** where OSM maps
  them, **traffic lights** (cycling, for looks only so far) at the junctions
  OSM marks as signalled, **trees** where OSM maps them (a forked trunk
  under a crown of leaf clusters that sways a little in the wind), black
  cast-iron **heritage lamp posts** with six-sided lanterns along downtown's
  sidewalks, and ordinary street lights on wooden poles everywhere else.
  **Every tree the lidar survey saw** (about 63,000) stands where it really
  is, at its real height and spread: leafy trees, and spruce and fir where
  the canopy comes to a point. A tree leaning out over a street has its
  trunk moved back to the edge of the sidewalk.
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
  Speed and heading glide on damped springs, so starts, stops and turns ease
  in and out (walking speed in about a quarter of a second, a stop in a
  seventh), big turns pivot a little slower than small corrections, and a
  reversal at a run plants and slows before coming round. Physics
  interpolation is on, so movement stays smooth on 120 and 144 Hz screens.
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
* **The edge of the play area** is an invisible wall 60 m outside the
  bypass ring, and out in the North River and the harbour along the shore,
  with road-closed barriers wherever a street crosses it (the
  Trans-Canada to Cornwall and Stratford, Malpeque Road, St. Peters Road
  and so on). Past it the city carries on as scenery.
* **HUD**: the name of the street you're on, a controls reminder, and the
  OpenStreetMap credit.

## Maps

Trans-Canada Auto is meant to grow a map at a time. A map is one
`map_config.json` and the data it points to (see `data/README.md`); the
"map" entry at the top names it.

| Map | Place | What's in it |
|---|---|---|
| **Red Clay** | Charlottetown, PEI | The whole city inside the bypass and Riverside Drive |

Another place (Halifax, say) would be built the same way: cut its
OpenStreetMap data and lidar with the tools in `tools/`, give it its own
config, and point the World node's `config_path` at it.

## How the town is built as you move

The city is far too big to build all at once, so it's split into 200 m
squares (chunks) and built round you as you go:

* Within about 330 m of the camera (230 m on Low) chunks are built in **full
  detail**: curbs, paint, lamps, signs, trees, and everything solid to walk
  and drive into.
* Out to about 1 km (750 m on Low) they're built in **low detail**: the same
  streets and buildings (windows and all) without the small things, and
  nothing solid.
* Past that, a coarse version of the whole city's ground runs on to the
  horizon under the haze.

Chunks are built on background threads, nearest first, a few at a time, so
there's no long wait or stutter, and a chunk is dropped again once you've
moved well away from it. Each chunk's buildings are merged into one mesh
(two draw calls however many buildings), but each building keeps a number
in that mesh, so the camera still fades just the one building that hides
you. A coarse floor under the whole map means nothing ever falls through
while a chunk is still on its way. The code is in
`scripts/world/chunk_streamer.gd` (what to build when) and
`scripts/world/chunk_builder.gd` (building one chunk).

## Project layout

| Folder | What's there |
|---|---|
| `data/` | The map data (`city/`: streets, plus buildings and the rest in chunks), the elevation, the ground masks, and how to read it all (`map_config.json`). See `data/README.md`. |
| `tools/` | Python scripts to cut the city out of the PEI OpenStreetMap file, convert it, fetch the elevation, paint the ground masks and preview the map as an SVG; and two Godot scripts for checking without playing (`capture.gd` takes screenshots and measurements, `profile_chunks.gd` times chunk building). |
| `scenes/` | `main.tscn` (lighting, sky, and the pieces below), `player/`, `camera/`. |
| `scripts/autoload/` | `InputSetup` (all controls), `GameState` (money and the save file) and `Graphics` (the High/Low setting). |
| `scripts/world/` | Building the town: `world_builder.gd` runs it (data, play-area ring, the first chunks); `chunk_streamer.gd` builds and drops chunks round the player and `chunk_builder.gd` builds one; `street_data.gd` loads the data, `geo_projection.gd` turns latitude and longitude into metres, `road_network.gd` is the street graph and curb maths, `terrain.gd` is the real ground (heights, chunk meshes, collision, harbour), `road_mesher.gd`, `building_generator.gd` and `street_props.gd` make the geometry, and `building_fade.gd` fades one building out of a merged chunk. |
| `scripts/player/`, `scripts/characters/`, `scripts/camera/`, `scripts/ui/` | The player, the reusable person model (`body_builder.gd` makes the mesh), the camera rig, the HUD. |
| `scripts/vehicles/` | The cars: `car_models.gd` (names, shapes, how each drives), `car.gd` (driving physics) and `car_builder.gd` (builds each car's mesh). |
| `shaders/` | Building walls (windows, brick, siding drawn in the shader), roofs, asphalt, sidewalks, road paint, paving, the terrain ground, tree leaves and people's clothes. `include/detail.gdshaderinc` has the noise and bump helpers they share. |

Coordinates: 1 unit = 1 metre, +X is east, -Z is north, +Y is metres above
sea level, and the origin is the Great George / Richmond junction. Physics layers are named in
`scripts/world/layers.gd`.

## Checking the map without Godot

```sh
python3 tools/preview_map.py preview.svg                                  # downtown
python3 tools/preview_map.py city.svg --centre=-1500,-2000 --half 3300   # the whole city
```

That draws the roads, sidewalks, buildings and play-area ring using the
same corner maths as the game. It's a quick way to check a width change or
a data refresh.

## Checking it in Godot without playing

Three scripts in `tools/` run the game by themselves and print what they
find (see the top of each file for how to run them):

* `capture.gd` starts the game, times the startup, saves screenshots from
  set spots and prints frame time, draw calls, triangles and memory.
* `drive_ring.gd` travels the bypass loop at a set speed and checks the
  streets are built and solid under the car the whole way.
* `profile_chunks.gd` times how long chunks take to build.
* `look_lab.gd` renders the same viewpoints in several candidate lighting
  looks, for comparing art direction.

## What has been tested

* The project imports and runs in Godot 4.7.2 with no errors or warnings
  from the game's scripts, on both the normal (Vulkan) renderer and the
  Compatibility (OpenGL) one. The camera fading a single building out of a
  merged chunk was checked on both.
* The map conversion was run on Geofabrik's PEI extract of 2026-11-21:
  2,032 street segments, 1,471 junctions and 11,457 buildings in 857
  chunks.
* `drive_ring.gd` drove the whole loop (11.1 km: Riverside Drive, the
  Arterial Highway, Upton Road, Capital Drive, North River Road) at 100 and
  160 km/h on High and at 120 km/h on Low, and again at 120 km/h after the
  lidar trees and buildings went in. The street was built and solid
  under the car at every check (one every 10 m), and the whole route is
  inside the play area.
* Measured in this cloud container, which has no graphics card (so the
  picture is drawn in software, about one frame a second, and frame times
  say nothing about a real PC):

  | | Before (four blocks) | After (whole city) |
  |---|---|---|
  | Playable after starting | 1.9 s | 3 to 4 s (downtown built; the rest fills in after) |
  | Building one chunk (one core) | | about 0.2 s full detail, 0.1 s distant |
  | Draw calls downtown | 560 to 710 | 670 |
  | Triangles drawn downtown | 2.1 million | 1.5 million |
  | Draw calls elsewhere | | 700 to 920 |
  | Memory (whole program) | 1.7 GB | 1.9 to 2.2 GB |
  | Slowest frame while streaming at 120 km/h (no drawing) | | about 60 ms |

  Most of the memory is the software renderer itself; on a real graphics
  card it will be much less. The game's own memory went from about 100 MB
  to 180 MB.
* Nobody has played it with a keyboard or controller yet, so how walking,
  driving and the camera feel on the new roads is still untested.
* The car's numbers in the Driving section were measured by driving the real
  car on a test pad with scripted inputs, and it was recorded driving round
  the block downtown with a small driver script pressing the controls.

## Known issues and limits

* Where a ramp joins a highway at a shallow angle, the junction is a wide
  wedge of asphalt and the lane paint of the two roads crosses in it.
* Driveways, parking lots and service lanes are painted on the ground
  rather than built as streets, so they have no curbs or paint.
* You can wade or drive into the shallows of the harbour and rivers until
  you reach the invisible wall.
* Building colours and materials are well-chosen guesses, not the real
  ones: the lidar gives shape and height but not colour, and there's no
  open source of building photos to copy from. Malls, schools and the
  hospital are plain modern boxes at their real size.
* Roofs are simple: one gable or hip over the whole footprint (or flat),
  so L-shaped houses and dormers aren't modelled.
* Big churches get a simple nave roof; transepts and apses aren't modelled.
* Landmark details (towers, portico, colours) are set by hand in
  `data/map_config.json` and are close to the real buildings, not exact.
* Road and sidewalk widths are estimates. OSM doesn't record them for most
  streets.
* Street parking lanes and Queen Street's diagonal parking aren't painted
  yet.
* Gable roofs only go on houses whose footprint is close to a rectangle.
  Everything else gets a flat roof.
* Traffic lights cycle but nothing obeys them yet, and there's no other
  traffic.
* Three cars to drive; parked traffic along the curbs comes with Milestone 3.
* Bumping a wall costs speed, but cars don't dent and there are no sounds yet.
* Esc only frees the mouse. The pause menu comes with Milestone 4.

## Next milestone

**Milestone 3: Living environment.** Pedestrians walking the real
sidewalks (the person model already supports random looks), parked cars
along the curbs, and more street furniture.

## Credits

Map data © OpenStreetMap contributors, under the Open Database License
(https://www.openstreetmap.org/copyright). Elevation: Natural Resources
Canada, HRDEM; contains information licensed under the Open Government
Licence – Canada. See `data/README.md`.

Wall textures (brick, sandstone, clapboard, cedar shingle, foundation
stone) are from Poly Haven (https://polyhaven.com), CC0; the list is in
`textures/facade/LICENSE.txt`. The leaf texture is drawn by
`tools/make_leaf_atlas.py`.

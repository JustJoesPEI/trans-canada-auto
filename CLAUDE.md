# Notes for Claude

## Pushing to main: tell Joe the version

Every push to `main` is built by `.github/workflows/build.yml` and becomes
version **0.1.N**, where N is that build's GitHub Actions run number (it's
what itch.io shows, and what the game shows in the menu's bottom-right
corner and in Credits, from `scripts/autoload/build_info.gd`, which the build
stamps). After pushing to `main`, look up the "Build and publish" run for
your commit (`mcp__github__actions_list`, `list_workflow_runs` on
`build.yml`, branch `main`, matching `head_sha`) and tell Joe its version,
e.g. "My push is 0.1.115". If a later push to `main` lands before that build
finishes, the build is cancelled and the later run's version includes your
change; say so.

## Looking up a real place

Landmarks are built from Joe's photos. Before he has one, local news
photos help: `tools/news_photos.py` saves a CBC article's photos and
captions (find the articles with a web search; the environment allows
www.cbc.ca and i.cbc.ca). Image search sites don't work from here. Say in
the landmark's `_comment` which photos it's from, and that Joe's photo
should correct it.

## Writing and humour

Every word a player reads or hears (signs, ads, radio, people on foot,
police radio, jail screens, jobs, phone apps, Kinbook, mission text,
captions, menus) follows `docs/voice.md`: dry, specific, local, aimed
up, a straight face with the honest line at the end, made-up names only.
A new feature isn't finished until its words are in that voice. Read it
before writing any, and add to its "landed / didn't land" tables when
Joe approves or rejects something.

## Models

Every model is built in code, and every new model or added detail must
follow the drawing-cost rules in `docs/models.md`: cache built meshes,
one surface per shared material, `MeshKit.commit_indexed`,
`ModelLod.finish_kits` for automatic LODs, interiors and small parts in the
near-only detail mesh, near and far wheels, cheap flat quads for repeated
features. After changing a model, run

    godot --headless --path . --script res://tools/model_budget.gd

and keep it within budget (it fails the build otherwise). Check how it
looks with `tools/car_studio.gd` (vehicles) or `tools/cargo_studio.gd`
(loads).

## The town

Everything placed in the world (buildings, props, trees, signs, placed
objects, textures) follows the art and drawing-cost rules in
`docs/world_art.md`: geometry only where it shows (close-up detail in the
facade mesh, repeated surface detail in shaders and texture arrays),
`ModelLod.finish_kits` (or `ModelLod.finish` at load time) on every mesh built once and drawn many times, shared
materials from `Materials.get_shared()` (never `StandardMaterial3D.new()`
in a prop or per chunk), repeats through `TiledMulti.add`, a draw distance
from size (`WorldLod.limit`), shadow stand-ins for detailed repeats, and
3D textures imported VRAM-compressed with mipmaps. After changing anything
in the world, run

    godot --headless --path . --script res://tools/world_budget.gd

and keep it within budget (it fails the build otherwise; `-- --verbose`
names what's costing what).

Graphics memory is a hard limit, not just speed: laptops whose graphics
share the computer's memory (often a fixed 512 MB) crash when the game goes
over it. `world_budget.gd` checks each chunk's own mesh memory (`mesh_kb`);
for the whole game on Low at 1080p, with a real renderer (in the cloud,
software drawing, about a minute or two):

    VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
        godot --rendering-driver vulkan --resolution 1920x1080 --path . \
        --script res://tools/memory_budget.gd -- --graphics=low

After changing how streets are built, `tools/audit_shapes.gd` lists
folded curbs, corners left sharp, stubs, divided-road forks and
underpasses (with coordinates for `tools/shot.sh`); `tools/audit_roads.gd`
and `tools/audit_junctions.gd` check streets against buildings and
junctions against each other.

## Traffic and car sounds

After changing traffic, `tools/traffic_watch.gd` runs a minute of
downtown traffic and lists glitches (cars jumping, tipping, spinning,
sliding; far cars snapping round) and frames over 40 ms with what
happened just before. `tools/traffic_check.gd` checks road manners.
After changing people on foot (`scripts/people/`),
`tools/pedestrian_check.gd` watches a minute of them downtown (jumps,
walking in the road, stuck), runs one ride from hail to pay and one bus
stop from waiting to boarding. After changing the bus routes or stops
(`data/transit.json`), `tools/transit_check.gd` checks every stop is on
its route both ways. `tools/kinbook_check.gd` checks the phone's Kinbook
feed and the pedestrian lines (no repeats, chats of two to four lines).
`tools/sound_drive.gd` records a scripted drive through the car sound
code (`--chase` with `--fixed-fps 40` hears it as the game does at a
lower frame rate).

## Server budget

After changing traffic, the police, people on foot or anything on the
server path (`TrafficDensity.server`, a server's chunks:
`ChunkBuilder.server_build`), run a server tick for 48 players:

    godot --headless --fixed-fps 60 --path . --script res://tools/traffic_server.gd -- --players=48 --secs=40 --budget

It fails over budget (CI runs it too, with `--fill=30 --secs=30`): an
average of 24 ms, a 99th percentile of 50 ms, no tick over 200 ms. That
is twice the aim of 12 and 25 ms on a quiet machine, and four times the
aim of no tick over 50 ms (a shared machine can stall one). Measure before and after back to back, twice: other
jobs on the machine move the numbers. `--profile` says where the tick
goes and what the slow ticks were doing; `--move` has the players walk
about, so the town is built round them as they go.

## Godot

A new `class_name` script needs `godot --headless --path . --import`
before headless tools can see it.

## Looking at a change

    tools/shot.sh name:x,z,yaw,pitch[,lift] [more...]

saves `/tmp/tca-shots/name.png` (x, z game metres; yaw 0 north, 90 west;
pitch negative looks down; lift metres above ground). It keeps the game
running between calls: the first call loads the town (about two minutes
in a cloud container, drawing in software), later shots near the last one
take a few seconds, a spot across town about a minute. It restarts itself
when scripts, shaders, scenes or map_config.json change, and picks up
map editor edits live. `tools/shot.sh --stop` ends it. Use
`tools/capture.gd` only for frame-time measurements.

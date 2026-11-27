# Building the town: art and drawing-cost rules

The town is built in code as you move (`scripts/world/`), so every
building, prop, tree and texture in it is paid for many times over: once
per chunk it's in, once per shadow cascade, and again as it streams back
in. These rules keep it looking good without that cost running away as
more objects are placed and the close-up quality spreads across the map.
**Anything new in the world follows them**, and `tools/world_budget.gd`
checks them:

```
godot --headless --path . --script res://tools/world_budget.gd [-- --verbose] [--at=x,z]
```

It builds sample chunks (downtown, the waterfront, two streets of houses
and a far suburb, or the chunk at `--at`) the way the game streams them,
close-up facades and all, and prints one `WORLD` line per chunk and
version: draw calls, triangles up close and from a few hundred metres,
triangles that can be cast into shadows, materials, rule breaks, and build
time. `--verbose` breaks it down by what drew it and names each offender.
It exits non-zero with `WORLD FAIL` lines if anything is over budget, and
the build workflow runs it on every push, like `tools/model_budget.gd`
does for the vehicles (`docs/models.md`, whose rules still apply to
anything modelled in detail, such as a prop with an interior).

## Looking good, cheaply

The quality goes where the camera is. The closer a thing can be seen, the
more it earns:

* **Up close (within the facade radius, 150 m on High):** real geometry
  where light and silhouette show it: window openings with depth, sills,
  porches, chimneys, cornices. Built as a separate mesh on a worker thread
  and swapped in (`ChunkStreamer`, `BuildingGenerator.detail`).
* **Middle distance (out to the full-detail radius, 330 m):** the same
  shapes without the small parts; surface detail (brick courses, mortar,
  clapboard laps, windows behind glass) is drawn in the shader, not modelled.
* **Far (to 1 km):** plain shapes, one mesh per chunk, no shadows, the
  shaders' fine detail fades out on its own (`gfx_detail`, mipmaps).

Surface detail that repeats (brick, siding, shingles, paving, bark) is a
**texture or shader pattern, never geometry**. Detail that changes the
outline or catches light (a porch roof, a window reveal) is geometry, and
goes in the close-up mesh.

## The rules

**W1. Built once, indexed, with automatic LODs.** Every mesh that's built
once and drawn many times (a prop, a tree, a lamp) is passed through
`ModelLod.finish` when it's made (it indexes the mesh itself if it was
committed with `MeshKit.commit`). Meshes merged per chunk (the buildings)
are built with `ModelLod.finish_kits` (indexed, keeping the building id
in CUSTOM0) on the worker thread that builds the chunk. Anything built
while playing uses `finish_kits`, never `finish`: `finish` reads the mesh
back from the graphics card, and that makes the renderer wait for the GPU
to go idle, a visible hitch each time. The
renderer switches to a simpler level only when the difference is under
about a pixel, so it's free to look at and cuts the triangles of
everything a little way off, shadows included. *Exception:* surfaces laid
on one another (the ground carved just under the streets, the streets,
paint) get no LODs, since simplifying one alone would let it poke through
the next; they're stepped by the chunk's near and far versions instead.

**W2. Shared materials only.** Each different material is its own GPU
state and breaks batching. Use `Materials.get_shared()`:
`plain(colour, roughness, metallic)`, `vertex_colour(roughness)` for
anything coloured per vertex, `glow(colour, energy)`, `shadow_caster()`,
the building wall and roof shaders, and the shared street shaders. All are
cached and safe from the chunk-building threads. Colour props with vertex
colours (`MeshKit.use_color`), not a material per colour. Never write
`StandardMaterial3D.new()` in a prop builder or in anything built per
chunk; a material per chunk is only for something that really differs per
chunk (the ground's own mask texture).

**W3. Repeats are tiled MultiMeshes.** Anything there's more than a
handful of in a chunk (trees, lamps, hydrants, parked cars, placed props)
is drawn through `TiledMulti.add`, never a node per instance. The renderer
culls a MultiMesh, picks its LOD and its shadow cascades from the box
round all its instances, so in full-detail chunks they're split into 50 m
tiles (`TiledMulti.TILE`; trees, which are cheap and many, into 100 m
`BIG_TILE`s). Anything drawn further than 280 m (lamps, trees, poles)
also gets one MultiMesh of the chunk's whole lot, the tiles' visibility
parent: past `TiledMulti.HLOD_FROM` from the middle of the chunk's
instances it's drawn in one call instead of the tiles (a tree kind's
shapes share one, drawn with the first shape, as the distant town does).
`TiledMulti.add` does this by itself. Distant chunks keep one MultiMesh per mesh. Something the
camera has to fade one at a time still goes in the MultiMesh, with a
handle node that swaps it out while it fades (`CrownFade`: the mapped
trees' crowns). A sign with its own text is the exception, a node of its
own, and gets W4's draw distance.

**W4. Draw distance from size.** Something small is a speck long before
the town ends. Give every small mesh a visibility range with
`WorldLod.limit(node)` or `WorldLod.draw_distance(mesh)`: about 100 m per
metre of size (it's about 6 pixels tall there), at least 40 m. A
`Label3D` is a draw call of its own: `WorldLod.limit(label, size)` with the
size its text reads at (0.6 for a street-name blade, a store's sign by its
width), and `alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS`, so it's drawn
with the solid things rather than sorted with the see-through ones. A
distant chunk has no text at all. Things drivers need to see coming
(signals, stop signs) get a longer distance by passing a bigger size.
`world_budget.gd` fails any mesh or MultiMesh under 6 m, and any
`Label3D`, with no range (`unbounded`; `labels` counts them).
Give the distance as High would draw it: every visibility range (both
ends) is scaled to the graphics setting as the node joins the scene
(`WorldLod.apply`, from `Graphics.RANGE_SHARE`), small things the most,
so new detail gets the setting's cuts without asking.

**W5. Count surfaces.** Each surface of each tile's MultiMesh is a draw
call. One surface per shared material, and a version drawn by the dozen
merges its finishes into one shader where it can (the parked cars are two
surfaces, not six: `CarBuilder._commit_parked` and
`shaders/car_paint_parked.gdshader` pick the finish per vertex).

**W6. Cheap shadows.** Shadows draw everything again into each cascade
(two on Low, four on Medium and High), out to 90-160 m. So a prop's own
mesh never casts its shadow: a plain stand-in drawn shadows-only does,
from `ShadowProxy` (`scripts/world/shadow_proxy.gd`):

* `ShadowProxy.add(root, label, mesh, xforms, draw_distance, stand_in,
  shadow_distance)` is `TiledMulti.add` for a prop: the real mesh with its
  shadow off, and the stand-in in the same tiles casting it. **New props
  use it rather than `TiledMulti.add`.** `ShadowProxy.attach(node,
  stand_in)` does the same for something that's a node of its own (a sign
  post, a chunk's merged hardware).
* `ShadowProxy.for_mesh(mesh, shape)` makes (and caches) the stand-in:
  `BOX` for solid things (cabinets, bins, sheds), `POST` for a pole with a
  head (lamps, lights: a post at the origin and a box round the top
  tenth), `ROUND` for an eight-sided prism (hydrants, bollards, drums),
  `SELF` for open frames whose shadow is their shape (benches, swings,
  racks: the mesh itself as one plain surface, so only the distance is
  saved). Make the ones a chunk uses in its `prepare()`, on the main thread.
* Small things cast their shadow within `ShadowProxy.DISTANCE` (50 m):
  past that a bench's shadow is a few pixels. Tall things (street lights,
  signal poles: 60 m) and anything 3 m or more cast it further.
* Trees and spruces cast theirs from a few plain lumps or a stack of cones
  stretched to the real crown's bounds (`StreetProps._fit_shadow`): the
  real ones are leaf cards through the alpha-scissor shader, the costliest
  thing there is to draw into the shadow map.

Flat things (paint, decals, wires, sign plates, the sidewalks' 15 cm lip,
the ground) cast none. Distant chunks cast none. `world_budget.gd` fails a
mesh under 4 m casting its own shadow further than 60 m (`no_stand_in`),
and counts the shadow map's draw calls apart from the camera's
(`shadow_calls`).

**W7. Close-up detail is its own mesh.** Facade detail is built into the
separate close-up mesh within `Graphics.facade_radius()`, never into the
chunk's base buildings, so it costs nothing further out. New close-up
detail goes behind `detail` in `BuildingGenerator` (or a near-only range
for props).

**W8. Textures.** Every texture used in 3D is imported VRAM-compressed with
mipmaps (`compress/mode=2`, `mipmaps/generate=true` in its `.import`;
Godot won't switch it automatically for textures loaded from code). Wall,
roof and street surfaces go in the shared texture arrays (one layer per
kind, tinted per building by vertex colour; see "Surface detail: the
texture arrays" below), so a new kind of surface is a new layer, not a
new material. 1024 px per layer is the default; 512 for what's never seen
at arm's length (roofs, street marks), 2048 only for something seen big
and close. Drawn by a `tools/make_*.py` script, or CC0 sources noted in
the folder's `LICENSE.txt`. A packed array that the shader reads as
numbers (shade, joint, height) is imported with `compress/high_quality=true`
(BC7, a byte a pixel): BC1 (half that) smeared its channels into each
other.

Data textures a shader reads as numbers rather than colour (the ground's
noise, `textures/ground/noise.png`) are the exception: block compression
keeps one colour line per 4x4 block and bands unrelated channels, so a
small one (a few hundred KB with mipmaps) is imported lossless
(`compress/mode=0`) with mipmaps.

**W9. A Low path.** Anything costly has a cheaper version on Low graphics:
shader detail behind `gfx_detail`, distances from `Graphics` (detail,
facade and distant radii), shorter shadows, simpler LODs sooner
(`Graphics.MESH_LOD_THRESHOLD`: the renderer drops to a simpler automatic
LOD at 4 pixels of difference on Low, 2 on Medium, 1 on High), and a
smaller sky lighting cube map (64 px a side on Low).

**W10. Cheap pixels.** A shader's per-pixel work is paid for every pixel
of every frame, on the weakest chips most of all. Work that only shows up
close (grain, cracks, blades of grass, bump) goes inside the branch that
fades it in (`fine_ok`, `near`), not computed everywhere and faded to
nothing. Broad noise (patches metres to hundreds of metres across) is read
from a small tiling noise texture, not worked out per pixel: `gn(p)` in
`terrain_ground.gdshader` is four fbm patterns in one texture read, where
`d_fbm(p)` is twelve hashes (`tools/make_ground_noise.py` makes it). Keep
procedural noise for what's fine and close, where a tiling texture would
show its repeat.

**W11. Hidden things aren't drawn.** Occlusion culling is on
(`rendering/occlusion_culling/use_occlusion_culling`): each building tile
carries an `OccluderInstance3D` of its buildings' walls
(`BuildingGenerator._occluder`: the footprint inset 0.3 m, up to 0.3 m
under the eaves, with a lid; buildings over 50 m² and 3.5 m tall; built
on the chunk's worker, never on a headless server), so the props, cars,
people and buildings of the next street behind a block aren't drawn at
all. An occluder must never hide what its building doesn't: keep it
inside the walls, and off while the camera fades that building
(`BuildingFade` switches the tile's off). Something big and solid that's
added later (a monument, a wall, a parkade's blank side) can carry one
the same way. The distant town ends 60 m inside the camera's far plane
(`ChunkStreamer._distant`): a chunk past the far plane can't show a pixel.

## What the map only outlines: TownDressing

`scripts/world/town_dressing.gd` fills in, per full-detail chunk, what
every street has but nobody maps one by one, and hands it to the same
pipelines as the placed props and the editor's lines (PlacedProps,
EditLines), so it adds no mesh or material of its own: each house's yard
by its neighbourhood's profile (`map_config.json` "yards" and each
neighbourhood's "yards": front hedge or fence with gaps for the walk and
driveway, back fence, shed, trampoline, fire pit and chairs, the Waste
Watch cart), OSM's benches, post boxes and bins, and its playgrounds,
pitches (goals, hoops, nets, backstops and court fences by sport), patios
and cemeteries (rows of headstones, no collision). Seeded by the building
or area, so a yard is the same every time. A placed prop of the same kind
within 4 m of an OSM point stands in for it. `tools/near.py` lists what's
on the map round a spot, for placing things by hand.

Placed props share two vertex-colour materials (shiny and matt, the matt
one the fences'), not one per roughness: a chunk with a dozen kinds of
prop would otherwise count a dozen materials.

## Surface detail: the texture arrays

Repeated surface detail is drawn once, into a few texture arrays, and
every building and street reads it by its real size. All are made by
scripts in `tools/` (seeded, so they redraw the same), committed as PNGs
with their `.import`, and set on the shared materials in
`scripts/world/materials.gd`.

| Array | Layers | Read by | Graphics memory | On |
|---|---|---|---|---|
| `textures/facade/wall_materials.png` | 8 at 1024 px: brick, clapboard, vinyl, cedar shingle, sandstone, stucco, concrete block, fieldstone | the wall shader | 11.2 MB | every level |
| `textures/facade/roof_materials.png` | 3 at 512 px: asphalt shingle, standing-seam metal, flat roof | the roof shader | 1.0 MB | every level |
| `textures/facade/window_rooms.png` | 16 at 256 px: rooms seen through windows | the wall shader | 1.4 MB | High and Medium |
| `textures/ground/street_decals.png` | 8 at 512 px: street marks | the asphalt and sidewalk shaders | 2.8 MB | every level |

Measured with `memory_budget.gd` on Low at 1080p when they came in:
textures 71 to 86-89 MB, settled 210-223 to 226-239 MB, peak 277 to
291 MB (High drops the 6.7 MB of photo walls these replaced, and adds the
rooms). Draw calls don't change: the arrays are parameters of the
materials already there.

**Building materials** (`tools/make_building_materials.py`). A layer
holds no colour: R is the shade (0.5 is the building's own vertex
colour, so the town's palettes still pick the hue), G the joint (mortar,
the shadow under a lap, a seam; coloured per layer by `MAT_JOINT` or
`MAT_JOINT_K`), B the height. Each is drawn at a real size (`MAT_TILE`:
brick 1.8 m with 7.5 cm courses, clapboard 10 cm boards over 2.4 x
1.2 m), with the image's top row at the top of the wall. On every level
one read a pixel gives the colour; on High two more give the slope of the
height (`d_tex_bump`, smooth up close, where a screen-space bump of a
texture breaks into 2x2 blocks). The style picks the layer
(`wall_layer()`), and a per-building hash picks a variant (half the
clapboard houses are vinyl, a third of painted buildings painted brick, a
quarter of pitched roofs metal). *To add a material:* write a function in
the tool returning shade, joint and height that tile, append it to
`LAYERS`, add its constant and a row to every table in
`shaders/include/building_materials.gdshaderinc` (size, joint, relief,
roughness), bump `slices/vertical` in the `.import`, and choose it in
`wall_layer()` (or the roof shader). A wall layer costs 1.4 MB; a roof
layer 0.35 MB.

**Rooms behind the windows** (`tools/make_window_rooms.py`, interior
mapping). Each layer is a room traced in Python and pre-projected: the
picture from `ROOM_EYE` depths in front of the glass, back wall in the
middle. The wall shader's `room_view()` traces the view ray into a box
the size of the window's bay and storey (a shop's: three bays and the
shop floor) and looks the hit up in the picture, so walls, floor and
ceiling show the right parallax. The room is added as light of its own
(`ROOM_GLOW`), not lit by the sun. Near only (`rooms_near`: High, a few
centimetres a pixel), one read, with its mip level worked out from the
distance: a mipmapped read inside the window branches, with the GPU's own
derivatives, gave noise. Layers 0-3 offices, 4-10 flats and houses (10 a
dark empty room), 11-15 shops. *To add a room:* a function returning a
`Room` with its boxes (a shop with `size=SHOP`), into `ROOMS` in its
group, then the ranges in the shader's picks and `slices/vertical`.

**Street marks** (`tools/make_street_decals.py`). Each layer is one mark
centred in its square, RGB a multiplier (0.5 no change), A its coverage.
No nodes and no Decals: the asphalt shader puts one scattered mark (cracks,
sealed cracks, patch, oil, tyre marks, ravelling) in each 6 m cell that a
hash picks, sized and turned so it stays inside the cell, so a pixel reads
only its own cell's; storm drains and manholes follow the street, along
and across it (the way the across coordinate, UV2.x, grows over the
ground gives the street's direction), drains at the gutter and manholes
down a lane. At most two reads a pixel, near only (`mark_ok`), with
`textureGrad` and derivatives worked out before the branches. *To add a
mark:* a function returning colour and coverage, appended to `LAYERS`, a
roughness in `MARK_ROUGH` (`shaders/include/street_marks.gdshaderinc`),
and a place in the asphalt or sidewalk shader's picks. A mark layer costs
0.35 MB.

## Budgets

Per chunk, set in `tools/world_budget.gd` (`BUDGETS`). Draw calls are the
camera's (shadows-only stand-ins are counted apart, as `shadow_calls`),
`Label3D`s included, counted before culling (a view draws the tiles in
front of it, fewer still behind the occluders); far
triangles are what's left past every visibility range at the simplest
LODs; build times are on one core of the machine running the check.

| | Draw calls | Triangles | Far triangles | Shadow triangles | Materials | Mesh memory | Build | Facades |
|---|---|---|---|---|---|---|---|---|
| Full detail (near) | 400 | 1,200,000 | 90,000 | 450,000 | 32 | 16 MB | 900 ms | 2,500 ms |
| Distant (far) | 16 | 100,000 | 25,000 | 0 | 10 | 768 KB | 600 ms | |

Mesh memory is the chunk's own meshes in graphics memory (vertices,
indices, LODs, MultiMesh instance data); a mesh shared between chunks
(through a cache) is stored once and isn't counted, which is why shared
props cost next to nothing and the buildings are about 95% of it.

The whole game's graphics memory has a budget too: a peak of 320 MB on
Low at 1920x1080, checked by `tools/memory_budget.gd` (it needs a real
renderer; the top of the file says how to run it in the cloud). Laptops
whose graphics share the computer's memory often get a fixed 512 MB of it,
which Windows' own desktop also uses, and going over it crashes the game
rather than slowing it. When it came in it measured 291-306 MB settled and
a 330 MB peak while the town streamed in round the spawn: about 140 MB
textures (a third of it screen-sized buffers), 90 MB meshes and 65 MB of
room the allocator had reserved. The peak was automatic resolution
stepping the scale down a bit at a time, each change a one-frame jump of
40-50 MB; it now changes in one go and not while loading, and Low scales up
plainly instead of with FSR: 269-283 MB settled, 290 MB peak. On Low the
town's own meshes are only about 25 MB of it (no close-up facades); the
rest is screen buffers, the renderer's own textures, the game's textures
and the cars.

And for every chunk: no mesh over 1,000 triangles without LODs (W1), no
duplicated material (W2), no small mesh, MultiMesh or label drawn to any
distance (W4), no small mesh casting its own shadow far (W6).

## Draw calls per setting

Per chunk isn't the whole story: a frame is every chunk round the camera,
near and distant, the cars, the people, the shadows and the HUD. Each
setting has a budget for the worst frame at the busiest spots, in
`Graphics.DRAW_CALL_BUDGET`, checked by `tools/view_budget.gd` (it needs a
real renderer; the top of the file says how to run it in the cloud) and
shown in the F3 overlay with where the calls go (town, shadows, HUD):

| Setting | Made for | Aim | Draw calls |
|---|---|---|---|
| Low | a laptop's built-in graphics (recent Ryzen, Iris Xe) | 60 fps at 1080p, scaled; a steady 30 at worst | 900 |
| Medium | a modest card (GTX 1650 / RX 6500) | 60 fps at 1080p | 1,600 |
| High | a mid-range card (RTX 3060 / RX 6600) | 60 fps at 1080p | 2,500 |

`view_budget.gd -- --graphics=low --why` stands at each busy spot with
the traffic and people out, finds the worst of four headings and says
what each kind of thing costs there (hidden in turn, the frame drawn
again). Run it after adding anything that's drawn by the hundred.

What a setting saves, from the cheapest to see to the dearest:

* **Small things nearer** (`Graphics.RANGE_SHARE`): Low draws something
  given 40 m to 25 m, 150 m to about 95, 300 m to 240; Medium a little
  less pulled in; High as far as size says. Buildings and streets aren't
  ranged and don't change.
* **Whole chunks in one call** past `HLOD_FROM` (W3), itself a range, so
  nearer on Low (about 145 m) than High (200 m).
* **Cars as their parked mesh** past `Car.DISTANT_FROM` (100 m on High):
  2 draw calls instead of 13, for every car simulated in full, other
  players' included. Liveries, police and emergency vehicles keep theirs.
* **Flat facades, two shadow cascades, no MSAA** on Low (Graphics).

Where it stood when the budgets came in (Low, the worst heading;
the minimap's streets had been a draw call each, about 800 a frame, on
every setting):

| Spot, Low | Before | After |
|---|---|---|
| Downtown | 1,088 | 436 (traffic and people out) |
| Grafton | 689 (minimap already fixed) | 476 |

## Distant chunks: the next step

There are about 50 distant chunks round the player on High (out to 840 m),
each 10 draw calls (ground, two or three street surfaces, the buildings'
walls and roofs, trunks, crowns, spruces): some 500 of a frame's calls for
a few percent of its pixels. The next saving, when the frame needs it, is
to merge them: past about 600 m, build a 2x2 block of chunks as one node
with one mesh per material (the four grounds share the coarse mask's
material already; streets, buildings and trees merge the same way), so 40
calls become 10. It needs the streamer to treat the block as one cell
beyond that radius (built when all four are wanted, swapped back to single
chunks as the player comes within 600 m, with the same hysteresis), and
its build on a worker is four chunks' worth (about 0.5 s on one core), so
it should be checked with `tools/stream_stress.gd` and the hitch log.

## Cheaper again, for the detail to come

Measured with `world_budget.gd` (shadow triangles per full-detail chunk,
before then after) and `tools/shot.sh` (whole frames on High, drawn in
software, so only the counts mean anything):

| | Before | After |
|---|---|---|
| Shadow triangles: downtown, Grafton, houses, suburb | 169k, 101k, 223k, 127k | 126k, 55k, 162k, 66k |
| Distant mesh memory, downtown chunk (streets indexed) | 465 KB | 304 KB |
| Distant chunks built round the player (High, Medium) | about 80, 56 | about 48 |
| Draw calls, downtown street views (`0,0` north and west) | 1,779 and 2,275 | 1,577 and 1,985 (occlusion) |
| Label3Ds drawn to any distance | building signs, gantries, posters | none |
| Graphics memory on Low at 1080p (`memory_budget.gd`), settled and peak | 269-283 MB, 290 MB | 236-254 MB, 280 MB |

The pictures before and after are the same to the eye; trees' shadows are
a touch more solid (lumps for leaf cards) and the lawns' broad patches
fall in different places (a texture, not the same noise worked out).

## Where things stood when the rules came in

Measured with `world_budget.gd` (the worst sample chunk) and `capture.gd`
at the spawn point:

| | Before | After |
|---|---|---|
| Far triangles, busiest chunk | 363,756 | 53,835 |
| Far triangles, distant chunk | 64,413 | 11,401 |
| Building meshes with LODs | none | all |
| Prop and tree meshes with LODs | parked cars only | all |
| Materials, busiest chunk | 33 (16 duplicates) | 24 (none) |
| Small meshes drawn to any distance | 15 | 0 |
| Parked car surfaces | 6 | 2 |
| Draw calls per chunk (before culling) | 112 | 289 (one MultiMesh per tile, so each is culled on its own) |
| Ads, signs, flags, clothing prints | uncompressed, no mipmaps | compressed, mipmapped |
| Close-up facade build per chunk | 650 ms | 1,150 ms (LODs, on a worker thread) |

And in the game (`tools/capture.gd`, 1600x900, High; drawn in software in
the cloud, so only the counts mean anything, not the frame times):

| View | Triangles drawn, before then after | Draw calls, before then after |
|---|---|---|
| Spawn | 4.26M to 2.79M | 1,136 to 1,275 |
| Downtown street (`0,40`) | 5.13M to 2.44M | 1,778 to 1,975 |
| Over downtown, 40 m up (`0,200`) | 4.95M to 2.61M | 1,753 to 2,150 |
| Residential street (`900,-1300`) | 1.37M to 0.35M | 899 to 987 |

The pictures before and after are the same to the eye, and camera fading
still fades just the one building. Draw calls went up by a tenth to a
fifth: that's the per-tile MultiMeshes, each culled on its own. It's the
right trade while the triangle count is what grows with every object
placed, but it's why W3 keeps tiles at 50 m (100 m for trees) and W5
counts surfaces.

Streaming costs no more: `tools/profile_chunks.gd` (25 chunks round
downtown) builds a full-detail chunk in 221 ms on average before and 223 ms
after (the worst went from 487 to 378 ms), and a distant one in 100 ms
both times. Only the close-up facades take longer, on their worker
thread. `tools/drive_ring.gd` at 100 km/h still finds the street solid
under the car at all 1,089 checks.

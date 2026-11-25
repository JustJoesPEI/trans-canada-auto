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
`BIG_TILE`s). Distant chunks keep one MultiMesh per mesh. Things that need
to be one node each (a crown the camera fades, a sign with its own text)
are the exception, and get W4's draw distance.

**W4. Draw distance from size.** Something small is a speck long before
the town ends. Give every small mesh a visibility range with
`WorldLod.limit(node)` or `WorldLod.draw_distance(mesh)`: about 100 m per
metre of size (it's about 6 pixels tall there), at least 40 m. A
`Label3D` is a draw call of its own: `WorldLod.limit(label, 0.6)`. Things
drivers need to see coming (signals, stop signs) get a longer one by
passing a bigger size. `world_budget.gd` fails any mesh under 6 m with no
range.

**W5. Count surfaces.** Each surface of each tile's MultiMesh is a draw
call. One surface per shared material, and a version drawn by the dozen
merges its finishes into one shader where it can (the parked cars are two
surfaces, not six: `CarBuilder._commit_parked` and
`shaders/car_paint_parked.gdshader` pick the finish per vertex).

**W6. Cheap shadows.** Shadows draw everything again into each cascade.
A detailed repeated thing casts its shadow from a plain stand-in drawn
shadows-only (`StreetProps._shadow_stand_in`, `_lamp_shadow_stand_in`)
with the real model's shadow off. Flat things (paint, decals, wires, the
ground) cast none. Distant chunks cast none.

**W7. Close-up detail is its own mesh.** Facade detail is built into the
separate close-up mesh within `Graphics.facade_radius()`, never into the
chunk's base buildings, so it costs nothing further out. New close-up
detail goes behind `detail` in `BuildingGenerator` (or a near-only range
for props).

**W8. Textures.** Every texture used in 3D is imported VRAM-compressed with
mipmaps (`compress/mode=2`, `mipmaps/generate=true` in its `.import`;
Godot won't switch it automatically for textures loaded from code). Wall
and surface photos go in the shared texture arrays (one layer per kind in
`textures/facade/`, tinted per building by vertex colour), so a new kind
of surface is a new layer, not a new material. 1024 px per layer is the
default; 2048 only for something seen big and close. CC0 sources, noted
in the folder's `LICENSE.txt`.

**W9. A Low path.** Anything costly has a cheaper version on Low graphics:
shader detail behind `gfx_detail`, distances from `Graphics` (detail,
facade and distant radii), shorter shadows.

## Budgets

Per chunk, set in `tools/world_budget.gd` (`BUDGETS`). Draw calls are
counted before culling (a view draws the tiles in front of it); far
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
duplicated material (W2), no small mesh drawn to any distance (W4).

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

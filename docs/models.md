# Building models: drawing-cost rules

Every model in Trans-Canada Auto is built in code (cars in
`scripts/vehicles/car_builder.gd`, trucks, the trailer and the forklift in
`truck_builder.gd`, loads in `cargo.gd`). They're detailed, so they're only
affordable if they're built to these rules. **Any new model, or new detail
on an old one, follows them**, and `tools/model_budget.gd` checks them:

```
godot --headless --path . --script res://tools/model_budget.gd
```

It prints one `BUDGET` line per model (draw calls, triangles up close and
far away, the simplest LOD, triangles cast into shadows, build time) and
exits non-zero with `BUDGET FAIL` lines if anything is over. The build
workflow runs it on every push, so an over-budget model fails the build.
`scripts/vehicles/model_lod.gd` (ModelLod) has the shared distances and
helpers.

## The rules

1. **Build once, share.** A model's meshes are built the first time
   they're needed and cached by everything that changes their shape
   (`Car._mesh_cache`: model, livery and a light/dark stripe bucket;
   `Cargo._mesh_cache`: the kind; `CarBuilder._wheel_meshes`: wheel size
   and style). Ten of the same truck are ten instances of one mesh. Never
   build a mesh per instance when a cached one would do. Colour is not
   shape: a car's paint is a surface override on its paint surfaces (LODs
   included), so every colour of a model shares one mesh, and more detail
   on a car costs its memory once, not once per colour. (Trucks still bake
   paint into vertex colours and are keyed by it.) A builder lets go of its
   kits once the mesh is made, and a headless server builds no car or body
   meshes at all (only what collision and shape queries need).
2. **One surface per material.** Each surface is a draw call. Use the
   shared materials (paint, gloss, rough, satin, metal, steel, glass:
   `CarBuilder.material`, `TruckBuilder.surface_material`) and vertex
   colours for colour, never a new material per part.
3. **Shared vertices.** Commit with `MeshKit.commit_indexed`, not `commit`.
4. **Automatic LODs.** Build every finished mesh from its kits with
   `ModelLod.finish_kits([[kit, material], ...])` (one indexed surface per
   pair). `ModelLod.finish` does the same for a mesh already made, but it
   has to read the mesh back from the graphics card, which stalls the
   renderer: use it only for meshes made once while the town loads. It adds simplified levels of detail that the renderer only uses when the
   difference is under about a pixel, so they're free to look at, and they
   cut the cost of everything a little way off, including shadows and the
   parked cars' MultiMeshes.
5. **Near detail is its own mesh.** Interiors and small parts (gauges,
   switches, seams, bolts, wipers, tread patterns, labels, perforations) go
   in the "detail" mesh: `CarBuilder` builds `_interior()` into it; in
   `TruckBuilder`, set `_detail = true` while building them. Car draws it
   with `ModelLod.near_only`: only within `DETAIL_RANGE` (35 m) and never
   into shadows.
6. **Wheels have a near and a far version.** Full-detail wheels within
   `WHEEL_RANGE` (30 m), low-detail ones beyond (`wheel_mesh(..., lod)`).
   Things hidden behind them (brakes) are near-only. Duals are one mesh
   (`wheel_mesh(..., dual)`).
7. **Cheap repeats.** A feature repeated dozens of times (diamond plate,
   rivets, perforations, brick faces) is a flat quad (2 triangles) or a
   low-segment disc, never a box (12) or a bevelled box (44). See
   `TruckBuilder._diamonds`.
8. **Don't model what can't be seen.** No faces inside other parts, no
   detail under a floor nobody looks under; keep cylinder segment counts
   to what reads at the size (8 to 12 for small pipes, 16 to 20 for tanks
   and wheels).
9. **Parked or crowd versions are simpler.** Things drawn by the dozen
   (parked cars) get their own reduced build (`CarBuilder.make_parked`),
   with their finishes merged into one surface and shader
   (`_commit_parked`: two draw calls, not six), and go in a MultiMesh per
   50 m tile (`TiledMulti`).

Anything placed in the town (props, trees, buildings, signs, textures)
also follows the world rules in `docs/world_art.md`.

## Budgets

Set in `tools/model_budget.gd` (`BUDGETS`). Up close means within 5 m;
far away means past every visibility range (200 m).

| | Draw calls | Triangles up close | Far away | Shadow-casting | Built again (cached) |
|---|---|---|---|---|---|
| Car (driven) | 40 | 70,000 | 20,000 | 45,000 | 15 ms |
| Truck, trailer, forklift | 60 | 110,000 | 30,000 | 60,000 | 15 ms |
| Parked car (MultiMesh) | 2 | 10,000 | simplest LOD 2,500 | | |
| Load | 4 | 6,000 | | | 3 ms |
| Held (paintball marker) | 1 | 1,000 | | | 0.5 ms |
| Person | 2 | 10,000 | | | |

Every mesh over 1,000 triangles must have automatic LODs.

**Painted.** Paint on a car or a person is a material overlay on its body
mesh (`PaintCoverage`, `BodyPaint`): one small material of its own, so the
body is drawn once more, a pass per surface, with everything outside the
splats discarded. `model_budget.gd` measures every vehicle again painted
(32 hits) and a person painted (16), counts that pass in the totals, which
must still fit the budgets above, and caps the pass itself:

| Extra pass when painted | Draw calls | Triangles |
|---|---|---|
| Car | 6 | 15,000 |
| Truck, trailer, forklift | 7 | 14,000 |
| Person | 1 | 5,000 |

Measured when it came in: 5 calls and 5,300 to 12,900 triangles on the
cars, 5 or 6 calls and up to 10,100 on the trucks, 1 call and 4,746 on a
person. A clean car or person has no overlay and costs nothing extra.

## Where things stood when the rules came in

Before, every vehicle drew its whole interior, every tyre's full tread
and its brakes at any distance and into the shadow map, and each one was
built from scratch. After:

| | Triangles far away, before then after | Shadow-casting up close | Building another |
|---|---|---|---|
| Hanaka Civique | 29,700 to 8,294 (2,302 at its simplest LOD) | 29,684 to 23,958 | 53 ms to 2 ms |
| Westerly Hauler 579 | 85,530 to 15,500 (4,432) | 85,520 to 59,110 | 144 ms to 2 ms |
| Fjord F-550 Rollback | 71,458 to 13,034 (2,686) | 71,448 to 39,196 | 89 ms to 2.6 ms |
| Fundy flatbed | 55,006 to 9,246 (3,386) | 55,006 to 44,142 | 31 ms to 0.3 ms |
| Pallet of boxes | 2,444 (692) | | 4.6 ms to 0.1 ms |

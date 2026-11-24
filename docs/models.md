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
   they're needed and cached by everything that changes how they look
   (`Car._mesh_cache`: model, colour, livery, unit; `Cargo._mesh_cache`:
   the kind; `CarBuilder._wheel_meshes`: wheel size and style). Ten of the
   same truck are ten instances of one mesh. Never build a mesh per
   instance when a cached one would do.
2. **One surface per material.** Each surface is a draw call. Use the
   shared materials (paint, gloss, rough, satin, metal, steel, glass:
   `CarBuilder.material`, `TruckBuilder.surface_material`) and vertex
   colours for colour, never a new material per part.
3. **Shared vertices.** Commit with `MeshKit.commit_indexed`, not `commit`.
4. **Automatic LODs.** Pass every finished mesh through `ModelLod.finish`.
   It adds simplified levels of detail that the renderer only uses when the
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
   (parked cars) get their own reduced build (`CarBuilder.make_parked`)
   and go in a MultiMesh.

## Budgets

Set in `tools/model_budget.gd` (`BUDGETS`). Up close means within 5 m;
far away means past every visibility range (200 m).

| | Draw calls | Triangles up close | Far away | Shadow-casting | Built again (cached) |
|---|---|---|---|---|---|
| Car (driven) | 40 | 70,000 | 20,000 | 45,000 | 15 ms |
| Truck, trailer, forklift | 60 | 110,000 | 30,000 | 60,000 | 15 ms |
| Parked car (MultiMesh) | 6 | 10,000 | simplest LOD 2,500 | | |
| Load | 4 | 6,000 | | | 3 ms |

Every mesh over 1,000 triangles must have automatic LODs.

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

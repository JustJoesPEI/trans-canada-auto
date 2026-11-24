class_name ModelLod
extends RefCounted
## How the vehicle and load models keep their drawing cost down. Every
## model built in code follows these rules (docs/models.md has them in full, and
## tools/model_budget.gd checks them):
##
##  * Build once, share: a model's meshes are built the first time they're
##    needed and cached by everything that changes them (model, colour,
##    livery, unit; a load's kind), so ten of the same thing are ten
##    instances of one mesh, not ten meshes.
##  * Few surfaces: one surface per shared material (paint, gloss, rough,
##    satin, metal, steel, glass), never a material per part. Each surface
##    is a draw call.
##  * Shared vertices: committed with MeshKit.commit_indexed.
##  * Near detail is its own mesh: interiors and small parts (gauges,
##    switches, bolts, tread patterns, labels, seams) go in a "detail" mesh
##    that's only drawn within DETAIL_RANGE and casts no shadow. From
##    further away nobody can see them, and inside a cab the roof's shadow
##    is the one that matters.
##  * Wheels swap to a low-detail tyre and rim past WHEEL_RANGE, and parts
##    hidden behind them (brakes) aren't drawn past it or into shadows.
##    Duals are one mesh, not two.
##  * Automatic LODs: every finished mesh goes through ModelLod.finish, which
##    adds simplified levels of detail (meshoptimizer). The renderer only
##    switches to a simpler one when the difference is under about a pixel
##    on screen, so it's free to look at and cuts the triangles of
##    everything a little way off, shadows and MultiMeshes (parked cars)
##    included.
##  * Cheap patterns: a repeated small feature (diamond plate, perforations,
##    rivets) is a flat quad (2 triangles), not a box (12) or a bevelled
##    box (44).

## m: interiors and small parts are drawn within this of the camera.
const DETAIL_RANGE := 35.0
## m: full-detail wheels within this, low-detail ones beyond.
const WHEEL_RANGE := 30.0
## m: hysteresis, so a mesh doesn't flicker at the edge of its range.
const MARGIN := 2.0


## The last step for every model mesh: adds automatic levels of detail.
static func finish(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var im := ImporterMesh.new()
	for si in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(si), mesh.surface_get_arrays(si), [], {}, mesh.surface_get_material(si))
	im.generate_lods(60.0, 25.0, [])
	return im.get_mesh()


## Only draw this within `range` m of the camera, and never into shadows.
static func near_only(gi: GeometryInstance3D, range := DETAIL_RANGE) -> void:
	gi.visibility_range_end = range
	gi.visibility_range_end_margin = MARGIN
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Only draw this further than `range` m from the camera.
static func far_only(gi: GeometryInstance3D, range: float) -> void:
	gi.visibility_range_begin = range
	gi.visibility_range_begin_margin = MARGIN

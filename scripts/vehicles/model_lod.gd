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


## The last step for every model mesh, and every mesh in the town that's
## built once and drawn many times: adds automatic levels of detail.
## Surfaces committed without an index (MeshKit.commit) are indexed first,
## since the simplifier needs shared vertices.
static func finish(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var custom_bits := 0
	for c in 4:
		custom_bits |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	var im := ImporterMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		# Keep the custom channels' format (the buildings' id in CUSTOM0).
		var flags := mesh.surface_get_format(si) & custom_bits
		if arrays[Mesh.ARRAY_INDEX] == null and mesh.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
			arrays = _indexed(arrays)
		im.add_surface(mesh.surface_get_primitive_type(si), arrays, [], {}, mesh.surface_get_material(si), "", flags)
	return _with_lods(im).get_mesh()


## Like finish, but straight from the kits: one indexed surface per
## [MeshKit, Material] pair that has anything in it, with automatic LODs.
## Use this wherever the kits are at hand. finish has to read the mesh back
## (surface_get_arrays), and on the graphics card that makes the renderer
## stop and wait for the GPU to go idle: a hitch in the picture every time,
## and chunks and cars are built all the time while driving.
static func finish_kits(parts: Array) -> ArrayMesh:
	var im := ImporterMesh.new()
	for part: Array in parts:
		var kit: MeshKit = part[0]
		if kit == null or kit.is_empty():
			continue
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, kit.indexed_arrays(), [], {}, part[1], "", kit.format_flags())
	if im.get_surface_count() == 0:
		return ArrayMesh.new()
	return _with_lods(im).get_mesh()


## Triangles over which a surface must get LODs (docs/world_art.md W1,
## docs/models.md: "every mesh over 1,000 triangles").
const LOD_MIN := 1000
## Degrees: corners whose normals differ by less than this are welded
## before simplifying (Godot's own default).
const MERGE_ANGLE := 60.0
## The retry for a surface made only of small hard-edged pieces: just past
## a right angle, so a box's corners weld too.
const HARD_EDGE_MERGE := 91.0


## Adds the automatic LODs. Before simplifying, Godot welds corners that sit
## together only if their normals are within MERGE_ANGLE and their UVs
## match, and it never moves an open edge of what it welded. A surface that
## is nothing but small boxes, each face with its own UVs (the close-up
## facade of a building of many short walls, all window frames, sills and
## lintels, like the one by the Grafton Street car wash), is then all
## islands with locked edges: nothing can go, Godot gives up (it keeps a
## LOD only if it saves a quarter) and the surface has none, at any
## distance. Such a surface, if it's over LOD_MIN triangles, is simplified
## again from its shape alone (positions and normals, right-angled corners
## welded) and those LODs are used for it. They can give a box corner its
## neighbour's normal, UV or colour, which only shows where the renderer
## has already judged the shape to be under a pixel off.
static func _with_lods(im: ImporterMesh) -> ImporterMesh:
	im.generate_lods(MERGE_ANGLE, 25.0, [])
	var stuck: Array[int] = []
	for si in im.get_surface_count():
		if im.get_surface_lod_count(si) == 0 and _importer_tris(im, si) > LOD_MIN:
			stuck.append(si)
	if stuck.is_empty():
		return im
	var out := ImporterMesh.new()
	for si in im.get_surface_count():
		var arrays := im.get_surface_arrays(si)
		var src := im
		var at := si
		if stuck.has(si):
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
				shape[k] = arrays[k]
			src = ImporterMesh.new()
			src.add_surface(im.get_surface_primitive_type(si), shape)
			src.generate_lods(HARD_EDGE_MERGE, 25.0, [])
			at = 0
		var lods := {}
		for l in src.get_surface_lod_count(at):
			lods[src.get_surface_lod_size(at, l)] = src.get_surface_lod_indices(at, l)
		out.add_surface(im.get_surface_primitive_type(si), arrays, [], lods, im.get_surface_material(si), im.get_surface_name(si), im.get_surface_format(si))
	return out


static func _importer_tris(im: ImporterMesh, si: int) -> int:
	var arrays := im.get_surface_arrays(si)
	if arrays[Mesh.ARRAY_INDEX] != null:
		return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## The same triangles with identical corners merged and an index.
## (create_from_arrays keeps the custom channels, reading their format
## from the arrays.)
static func _indexed(arrays: Array) -> Array:
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	st.index()
	st.optimize_indices_for_cache()
	return st.commit_to_arrays()


## Only draw this within `range` m of the camera, and never into shadows.
static func near_only(gi: GeometryInstance3D, range := DETAIL_RANGE) -> void:
	gi.visibility_range_end = range
	gi.visibility_range_end_margin = MARGIN
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Only draw this further than `range` m from the camera.
static func far_only(gi: GeometryInstance3D, range: float) -> void:
	gi.visibility_range_begin = range
	gi.visibility_range_begin_margin = MARGIN

class_name TiledMulti
extends RefCounted
## Repeated props (trees, lamps, hydrants, parked cars) are drawn through
## MultiMeshes, and the renderer culls a MultiMesh, picks its level of
## detail and decides which shadow cascades it's in as one block, from the
## box round all of its instances. One MultiMesh for a whole 200 m chunk
## means standing anywhere in it draws every instance at full detail, into
## every cascade. So a full-detail chunk's MultiMeshes are split into
## TILE-metre squares (the same tiles as the buildings): the ones behind
## you are culled and the ones down the street drop to their simpler LODs.
## Distant chunks keep one MultiMesh per mesh, since everything in them is
## far off anyway and fewer draw calls matter more there.
## docs/world_art.md, rule W3.

const TILE := 50.0
## Cheap things drawn by the hundred (trees) use bigger tiles, a quarter of
## a chunk: they gain less from culling than they'd cost in draw calls.
const BIG_TILE := 100.0


## Instance indices grouped by tile: {Vector2i: Array of int}, in a
## stable order.
static func groups(xforms: Array, tiled := true, tile := TILE) -> Dictionary:
	var out := {}
	for i in xforms.size():
		var o: Vector3 = (xforms[i] as Transform3D).origin
		var key := Vector2i(floori(o.x / tile), floori(o.z / tile)) if tiled else Vector2i.ZERO
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(i)
	return out


## One MultiMesh of `mesh` over `xforms` (Transform3D), indices `idx`, with
## optional per-instance custom data (Color) and colours.
static func multimesh(mesh: Mesh, xforms: Array, idx: Array, custom: Array = [], colours: Array = []) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not custom.is_empty()
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = idx.size()
	for k in idx.size():
		mm.set_instance_transform(k, xforms[idx[k]])
		if not custom.is_empty():
			mm.set_instance_custom_data(k, custom[idx[k]])
		if not colours.is_empty():
			mm.set_instance_color(k, colours[idx[k]])
	return mm


## Adds `mesh` at every transform as one MultiMeshInstance3D per tile (one
## in all if `tiled` is false), each named `label` plus its tile and
## carrying a "label" meta of `label`. Returns them.
static func add(root: Node3D, label: String, mesh: Mesh, xforms: Array, shadow: GeometryInstance3D.ShadowCastingSetting,
		draw_distance := 0.0, tiled := true, custom: Array = [], tile := TILE) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	if xforms.is_empty():
		return out
	var g := groups(xforms, tiled, tile)
	for key: Vector2i in g:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = label if not tiled else "%s_t%d_%d" % [label, key.x, key.y]
		mmi.set_meta("label", label)
		mmi.multimesh = multimesh(mesh, xforms, g[key], custom)
		mmi.cast_shadow = shadow
		if draw_distance > 0.0:
			mmi.visibility_range_end = draw_distance
			mmi.visibility_range_end_margin = 4.0
		root.add_child(mmi)
		out.append(mmi)
	return out

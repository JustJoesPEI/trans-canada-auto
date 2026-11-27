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
##
## But tiles cost a draw call each (per surface), so a full-detail chunk
## seen from the next one over, its lamps in sixteen tiles, was sixteen
## times the calls for things all well down the street. So the tiles of
## anything drawn far (lamps, trees, poles) hang under one MultiMesh of
## the whole chunk's lot (`_whole`, a hierarchical LOD in Godot's terms:
## the tiles' visibility_parent). Past HLOD_FROM from the middle of the
## chunk's instances that one draws them all in one call, and the tiles
## are hidden; nearer, the tiles take over, each culled and LOD'd on its
## own. HLOD_FROM is a draw distance like any other, so the graphics
## setting pulls it in (WorldLod.for_setting: about 145 m on Low, 175 m on
## Medium, 200 m on High). Shadows-only stand-ins stay in tiles (the
## shadow cascades are short and gain from the culling).

const TILE := 50.0
## Cheap things drawn by the hundred (trees) use bigger tiles, a quarter of
## a chunk: they gain less from culling than they'd cost in draw calls.
const BIG_TILE := 100.0
## m from the middle of a chunk's instances past which they're drawn as one
## MultiMesh rather than by tile (see the top). Only for things drawn
## further than HLOD_MIN_REACH (or with no limit); a hydrant's tiles are
## gone long before then anyway.
const HLOD_FROM := 200.0
const HLOD_MIN_REACH := 280.0


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
##
## Kinds with several shapes (trees) can share one whole MultiMesh, as the
## distant town does: the first shape's call passes every shape's
## transforms as `whole_xforms` (drawn with its own mesh), the others pass
## its whole (`under`, from the first's tiles' "hlod" meta) to hang their
## tiles under. A tree a couple of hundred metres off is a tree.
static func add(root: Node3D, label: String, mesh: Mesh, xforms: Array, shadow: GeometryInstance3D.ShadowCastingSetting,
		draw_distance := 0.0, tiled := true, custom: Array = [], tile := TILE, whole_xforms: Array = [],
		under: MultiMeshInstance3D = null) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	if xforms.is_empty():
		return out
	var g := groups(xforms, tiled, tile)
	var whole: MultiMeshInstance3D = under
	if whole == null and tiled and (g.size() > 1 or not whole_xforms.is_empty()) \
			and shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
			and (draw_distance <= 0.0 or draw_distance >= HLOD_MIN_REACH):
		whole = _whole(root, label, mesh, xforms if whole_xforms.is_empty() else whole_xforms, shadow, draw_distance,
			custom if whole_xforms.is_empty() else [])
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
		if whole != null:
			mmi.visibility_parent = NodePath("../" + str(whole.name))
			mmi.set_meta("hlod", whole)
		out.append(mmi)
	return out


## The one MultiMesh of all of a chunk's `mesh`, drawn instead of its tiles
## past HLOD_FROM (see the top). Marked "hlod_whole" (world_budget.gd counts
## a chunk's calls as seen from inside it, by tile).
static func _whole(root: Node3D, label: String, mesh: Mesh, xforms: Array, shadow: GeometryInstance3D.ShadowCastingSetting,
		draw_distance: float, custom: Array) -> MultiMeshInstance3D:
	var all := []
	all.resize(xforms.size())
	for i in xforms.size():
		all[i] = i
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_whole" % label
	mmi.set_meta("label", label)
	mmi.set_meta("hlod_whole", true)
	mmi.multimesh = multimesh(mesh, xforms, all, custom)
	# Never into the shadows: it's only drawn past HLOD_FROM, beyond the
	# sun's shadow distance (90-160 m), but its box is the whole chunk, so
	# the shadow pass would draw all of it (leaf cards on High, the dearest
	# thing there is to draw there). The tiles cast as they're told.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = HLOD_FROM
	mmi.visibility_range_begin_margin = 8.0
	if draw_distance > 0.0:
		mmi.visibility_range_end = draw_distance
		mmi.visibility_range_end_margin = 4.0
	root.add_child(mmi, true)
	return mmi

class_name ShadowProxy
extends RefCounted
## Cheap shadows for things placed in the town (docs/world_art.md, rule W6).
##
## The sun draws everything that casts a shadow again into each shadow
## cascade, out to 90-160 m. For a detailed prop drawn by the dozen (a
## hydrant, a bench, a lamp, a tree's leaf cards through the alpha-scissor
## shader) that's most of its cost, and the shadow on the ground reads the
## same from a few boxes. So the real mesh is drawn with its own shadow off,
## and a plain stand-in drawn shadows-only (never seen) casts it instead,
## and only within a short distance for small things: a bench's shadow is a
## few pixels from 50 m.
##
## New props use `add` (a TiledMulti with its stand-in) or `attach` (a node
## of its own) by default. A stand-in is made once per mesh and shape and
## cached, so chunks share it; make the ones a chunk needs in a prepare()
## on the main thread (SELF reads the mesh back from the graphics card).

enum Shape {
	BOX, ## a box filling the mesh's bounds, a little inside: cabinets, bins, sheds
	POST, ## a post at the origin and a box round the top tenth: lamps, signs, poles
	ROUND, ## an eight-sided prism inside the bounds: hydrants, bollards, drums
	SELF, ## the mesh itself as one plain surface: open frames (benches, swings)
}

## How far a small thing's shadow is drawn (m). Its own draw distance is
## longer; past this it's drawn without one, which nobody notices.
const DISTANCE := 50.0

static var _cache := {} ## [mesh, shape] -> stand-in Mesh
static var _lock := Mutex.new()


## The stand-in for `mesh` with `shape` (cached).
static func for_mesh(mesh: Mesh, shape := Shape.BOX) -> Mesh:
	if mesh == null:
		return null
	var key := [mesh.get_instance_id(), shape]
	_lock.lock()
	var m: Mesh = _cache.get(key)
	_lock.unlock()
	if m != null:
		return m
	var b := mesh.get_aabb()
	match shape:
		Shape.POST:
			var h := b.size.y
			var top := AABB(Vector3(b.position.x, b.position.y + h * 0.9, b.position.z), Vector3(b.size.x, h * 0.1, b.size.z))
			var post := AABB(Vector3(-0.08, b.position.y, -0.08), Vector3(0.16, h * 0.9, 0.16))
			m = boxes([post, top])
		Shape.ROUND:
			m = prism(b.grow(-minf(0.02, b.size.x * 0.05)), 8)
		Shape.SELF:
			m = single_surface(mesh)
		_:
			m = boxes([b.grow(-minf(0.03, minf(b.size.x, b.size.z) * 0.05))])
	_lock.lock()
	if _cache.has(key):
		m = _cache[key] # another thread got there first: share theirs
	else:
		_cache[key] = m
	_lock.unlock()
	return m


## One shadows-only surface of boxes (AABBs).
static func boxes(list: Array) -> ArrayMesh:
	var kit := MeshKit.new()
	for box: AABB in list:
		box_into(kit, box)
	return _commit(kit)


## Adds a box's six faces to `kit` (for building a stand-in alongside a
## mesh made per chunk, like the signal hardware).
static func box_into(kit: MeshKit, b: AABB) -> void:
	var lo := b.position
	var hi := b.end
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	kit.quad(c[4], c[5], c[6], c[7], Vector3.UP)
	kit.quad(c[3], c[2], c[1], c[0], Vector3.DOWN)
	kit.quad(c[0], c[1], c[5], c[4], Vector3.FORWARD)
	kit.quad(c[2], c[3], c[7], c[6], Vector3.BACK)
	kit.quad(c[1], c[2], c[6], c[5], Vector3.RIGHT)
	kit.quad(c[3], c[0], c[4], c[7], Vector3.LEFT)


## An upright prism with `sides` sides inside `b`.
static func prism(b: AABB, sides: int) -> ArrayMesh:
	var kit := MeshKit.new()
	var c := b.get_center()
	var rx := b.size.x * 0.5
	var rz := b.size.z * 0.5
	var y0 := b.position.y
	var y1 := b.end.y
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(c.x + cos(a0) * rx, 0.0, c.z + sin(a0) * rz)
		var p1 := Vector3(c.x + cos(a1) * rx, 0.0, c.z + sin(a1) * rz)
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		kit.quad(p0 + Vector3(0, y0, 0), p0 + Vector3(0, y1, 0), p1 + Vector3(0, y1, 0), p1 + Vector3(0, y0, 0), n)
		kit.tri(Vector3(c.x, y1, c.z), p1 + Vector3(0, y1, 0), p0 + Vector3(0, y1, 0), Vector3.UP)
	return _commit(kit)


## `mesh`'s triangles as one surface in the stand-in material, with
## automatic LODs. Reads the mesh back: main thread, at load.
static func single_surface(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for si in mesh.get_surface_count():
		st.append_from(mesh, si, Transform3D.IDENTITY)
	var out := ArrayMesh.new()
	var arrays := st.commit_to_arrays()
	# Only what a shadow needs.
	for k in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
			Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[k] = null
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, Materials.get_shared().shadow_caster())
	return ModelLod.finish(out)


static func _commit(kit: MeshKit) -> ArrayMesh:
	return kit.commit_indexed(null, Materials.get_shared().shadow_caster())


## Draws `mesh` at every transform through TiledMulti (W3) with its own
## shadow off and `stand_in` casting it, shadows-only, out to
## `shadow_distance` (never past `draw_distance`). A null stand-in means a
## BOX of the mesh. Returns the real mesh's MultiMeshInstance3Ds.
static func add(root: Node3D, label: String, mesh: Mesh, xforms: Array, draw_distance: float, stand_in: Mesh = null,
		shadow_distance := DISTANCE, tiled := true, tile := TiledMulti.TILE) -> Array[MultiMeshInstance3D]:
	var out := TiledMulti.add(root, label, mesh, xforms, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, draw_distance, tiled, [], tile)
	if out.is_empty():
		return out
	if stand_in == null:
		stand_in = for_mesh(mesh)
	var d := shadow_distance if draw_distance <= 0.0 else minf(shadow_distance, draw_distance)
	if d <= 0.0:
		d = draw_distance
	TiledMulti.add(root, label + "_shadow", stand_in, xforms, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, d, tiled, [], tile)
	return out


## For a thing that's a node of its own (a sign post, a chunk's merged
## hardware): turns its shadow off and gives it a shadows-only child
## drawing `stand_in` (a BOX of its mesh if null) out to `shadow_distance`.
## Returns the stand-in node.
static func attach(gi: GeometryInstance3D, stand_in: Mesh = null, shadow_distance := DISTANCE) -> MeshInstance3D:
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if stand_in == null and gi is MeshInstance3D:
		stand_in = for_mesh((gi as MeshInstance3D).mesh)
	if stand_in == null:
		return null
	var s := MeshInstance3D.new()
	s.name = "%s_shadow" % gi.name if str(gi.name) != "" else "Shadow"
	s.mesh = stand_in
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var d := shadow_distance
	if gi.visibility_range_end > 0.0:
		d = minf(d, gi.visibility_range_end)
	s.visibility_range_end = d
	s.visibility_range_end_margin = 4.0
	gi.add_child(s)
	return s

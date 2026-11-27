class_name MeshKit
extends RefCounted
## Small helper for building ArrayMeshes out of triangles and quads.
##
## Every triangle is given the normal it should face; the kit fixes the vertex
## order itself (Godot treats clockwise-from-the-front as the front face), so
## generator code never has to think about winding. Optional per-vertex colour
## and UV2 let many buildings share one material, and an optional per-vertex
## id (CUSTOM0) tells the shader which building a vertex belongs to, so one
## merged mesh can still fade a single building.
##
## With `clip` set, a triangle is kept only if its middle (seen from above)
## lies inside it: streets that run through several chunks are built for
## each chunk and every triangle lands in exactly one of them.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var colors := PackedColorArray()

var ids := PackedFloat32Array()
## One bone per vertex (with `use_bones`): a car's doors swing on theirs
## (CarBuilder._split_doors). Filled all at once, not by _v.
var bones := PackedInt32Array()
var use_bones := false

var use_color := false
var use_uv2 := false
var use_id := false
## Applied to every vertex added while set.
var color := Color.WHITE
var uv2 := Vector2.ZERO
var id := 0.0
## Keep only triangles whose middle is inside this (x, z) rectangle.
var clip := Rect2()
var use_clip := false


func is_empty() -> bool:
	return verts.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	tri_full(a, b, c, n, n, n, n, ua, ub, uc, uv2, uv2, uv2)


## Quad a-b-c-d (in order around its edge).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	tri(a, b, c, n, ua, ub, uc)
	tri(a, c, d, n, ua, uc, ud)


## A quad with its own UV2 at each corner (roads use it for the distance
## across the street, so the shader can wear the wheel paths).
func quad_uv2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		u2a: Vector2, u2b: Vector2, u2c: Vector2, u2d: Vector2) -> void:
	tri_full(a, b, c, n, n, n, n, ua, ub, uc, u2a, u2b, u2c)
	tri_full(a, c, d, n, n, n, n, ua, uc, ud, u2a, u2c, u2d)


## A quad with a smooth normal at each corner (rounded car bodies).
## `face` is roughly outward and only decides the winding.
func quad_smooth(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, face: Vector3) -> void:
	tri_full(a, b, c, face, na, nb, nc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, uv2, uv2, uv2)
	tri_full(a, c, d, face, na, nc, nd, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, uv2, uv2, uv2)


## One triangle with everything given per corner. Wound so `face` is its front.
func tri_full(a: Vector3, b: Vector3, c: Vector3, face: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, u2a: Vector2, u2b: Vector2, u2c: Vector2) -> void:
	if use_clip:
		var m := (a + b + c) / 3.0
		if m.x < clip.position.x or m.x >= clip.end.x or m.z < clip.position.y or m.z >= clip.end.y:
			return
	if (b - a).cross(c - a).dot(face) > 0.0:
		# Counter-clockwise seen from the front: swap to clockwise.
		_v(a, na, ua, u2a)
		_v(c, nc, uc, u2c)
		_v(b, nb, ub, u2b)
	else:
		_v(a, na, ua, u2a)
		_v(b, nb, ub, u2b)
		_v(c, nc, uc, u2c)


## Flat, upward-facing triangle with UVs from world position (metres * scale).
func ground_tri(a: Vector3, b: Vector3, c: Vector3, uv_scale := 0.25) -> void:
	tri(a, b, c, Vector3.UP, Vector2(a.x, a.z) * uv_scale, Vector2(b.x, b.z) * uv_scale, Vector2(c.x, c.z) * uv_scale)


func ground_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale := 0.25) -> void:
	ground_tri(a, b, c, uv_scale)
	ground_tri(a, c, d, uv_scale)


## Vertical wall from ground segment p0-p1, between heights y0 and y1, facing n.
## UV x = metres along the wall (+u_offset), UV y = metres of height.
func wall(p0: Vector2, p1: Vector2, y0: float, y1: float, n: Vector3, u_offset := 0.0) -> void:
	var seg_len := p0.distance_to(p1)
	quad(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), n,
		Vector2(u_offset, y0), Vector2(u_offset + seg_len, y0), Vector2(u_offset + seg_len, y1), Vector2(u_offset, y1))


func _v(p: Vector3, n: Vector3, uv: Vector2, u2: Vector2) -> void:
	verts.append(p)
	normals.append(n)
	uvs.append(uv)
	if use_color:
		colors.append(color)
	if use_uv2:
		uv2s.append(u2)
	if use_id:
		ids.append(id)


## Append everything in `other` (same channels), moved up by `lift`.
func append_kit(other: MeshKit, lift := 0.0) -> void:
	var start := verts.size()
	verts.append_array(other.verts)
	if lift != 0.0:
		for i in range(start, verts.size()):
			verts[i].y += lift
	normals.append_array(other.normals)
	uvs.append_array(other.uvs)
	if use_color:
		colors.append_array(other.colors)
	if use_uv2:
		uv2s.append_array(other.uv2s)
	if use_id:
		if other.use_id:
			ids.append_array(other.ids)
		else:
			var n := other.verts.size()
			var add := PackedFloat32Array()
			add.resize(n)
			add.fill(id)
			ids.append_array(add)


## Append everything as a new surface of `mesh` (created if null).
func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if use_color:
		arrays[Mesh.ARRAY_COLOR] = colors
	if use_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var flags := 0
	if use_id:
		arrays[Mesh.ARRAY_CUSTOM0] = ids
		flags = Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Like commit, but with shared vertices: corners that match in position,
## normal, UV and colour are merged and drawn through an index, reordered
## for the GPU's vertex cache. About a third fewer vertices to transform for
## flat-shaded models (and half for smooth ones), at a one-off cost when
## built. Indexed meshes are also what automatic LODs (ModelLod.finish)
## need, so it's used for streamed town meshes too: the cost is paid on the
## worker thread that builds the chunk. The id channel (CUSTOM0) is kept.
func commit_indexed(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var st := _indexed_tool()
	if material != null:
		st.set_material(material)
	return st.commit(mesh)


## The surface commit_indexed would add, as arrays, without making a mesh
## ([] if the kit is empty). ModelLod.finish_kits builds from these, so the
## automatic LODs never have to read a mesh back from the graphics card.
func indexed_arrays() -> Array:
	if verts.is_empty():
		return []
	return _indexed_tool().commit_to_arrays()


## The format flags the surface needs beyond what its arrays say: the
## building id's channel (CUSTOM0, one float).
func format_flags() -> int:
	return Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT if use_id else 0


func _indexed_tool() -> SurfaceTool:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if use_color:
		arrays[Mesh.ARRAY_COLOR] = colors
	if use_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if use_bones:
		# Each vertex wholly on its one bone.
		var bi := PackedInt32Array()
		bi.resize(bones.size() * 4)
		var bw := PackedFloat32Array()
		bw.resize(bones.size() * 4)
		for i in bones.size():
			bi[i * 4] = bones[i]
			bw[i * 4] = 1.0
		arrays[Mesh.ARRAY_BONES] = bi
		arrays[Mesh.ARRAY_WEIGHTS] = bw
	var st := SurfaceTool.new()
	if use_id:
		# create_from_arrays reads its format (one float) from the array.
		arrays[Mesh.ARRAY_CUSTOM0] = ids
	st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	st.index()
	st.optimize_indices_for_cache()
	return st


## Triangle soup for a ConcavePolygonShape3D.
func faces() -> PackedVector3Array:
	return verts


static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

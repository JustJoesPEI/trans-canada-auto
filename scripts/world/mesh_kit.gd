class_name MeshKit
extends RefCounted
## Small helper for building ArrayMeshes out of triangles and quads.
##
## Every triangle is given the normal it should face; the kit fixes the vertex
## order itself (Godot treats clockwise-from-the-front as the front face), so
## generator code never has to think about winding. Optional per-vertex colour
## and UV2 let many buildings share one material.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var colors := PackedColorArray()

var use_color := false
var use_uv2 := false
## Applied to every vertex added while set.
var color := Color.WHITE
var uv2 := Vector2.ZERO


func is_empty() -> bool:
	return verts.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		# Counter-clockwise seen from the front: swap to clockwise.
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	_v(a, n, ua)
	_v(b, n, ub)
	_v(c, n, uc)


## Quad a-b-c-d (in order around its edge).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	tri(a, b, c, n, ua, ub, uc)
	tri(a, c, d, n, ua, uc, ud)


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


func _v(p: Vector3, n: Vector3, uv: Vector2) -> void:
	verts.append(p)
	normals.append(n)
	uvs.append(uv)
	if use_color:
		colors.append(color)
	if use_uv2:
		uv2s.append(uv2)


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
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Triangle soup for a ConcavePolygonShape3D.
func faces() -> PackedVector3Array:
	return verts


static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

class_name Terrain
extends RefCounted
## The real shape of the ground, from NRCan's lidar ground model (PEI 2020,
## bare earth) sampled onto a grid by tools/fetch_elevation.py.
##
## World y is metres above sea level, so heights in the game are real
## heights. Everything that stands on the ground asks height_at(); the
## terrain mesh reads data/ground_mask.png to paint lawns, parking, stone
## squares and brick paths, so those follow the slope with no extra geometry.

## The open ground sits this far below the true surface, so streets and
## sidewalks (built at the true surface) always draw on top of it.
const GROUND_DROP := 0.08
const MESH_STEP := 2 # mesh every Nth grid point (grid is 2 m, so 4 m quads)

var origin := Vector2.ZERO # (x, z) of grid point [0, 0]
var spacing := 2.0
var nx := 0
var nz := 0
var heights := PackedFloat32Array() # metres, row-major: index = z * nx + x
var info: Dictionary = {}


static func load_from(path: String) -> Terrain:
	var t := Terrain.new()
	if not FileAccess.file_exists(path):
		push_warning("Terrain: %s not found; the town will be flat." % path)
		return t
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_warning("Terrain: could not read %s; the town will be flat." % path)
		return t
	t.info = d
	t.origin = Vector2(float(d["origin_x"]), float(d["origin_z"]))
	t.spacing = float(d["spacing"])
	t.nx = int(d["nx"])
	t.nz = int(d["nz"])
	var cm: Array = d["heights_cm"]
	t.heights.resize(cm.size())
	for i in cm.size():
		t.heights[i] = float(cm[i]) / 100.0
	return t


func is_flat() -> bool:
	return heights.is_empty()


## Ground height (m above sea level) at a world position, smoothly
## interpolated. Outside the surveyed area the edge height carries on.
func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var fx := clampf((x - origin.x) / spacing, 0.0, float(nx - 1) - 0.001)
	var fz := clampf((z - origin.y) / spacing, 0.0, float(nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	var a := heights[i]
	var b := heights[i + 1]
	var c := heights[i + nx]
	var d := heights[i + nx + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func h2(p: Vector2) -> float:
	return height_at(p.x, p.y)


## A point on the ground: Vector2(x, z) plus a lift above the surface.
func at(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)


## The ground mesh, its collision and the harbour water.
func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	if heights.is_empty():
		return root
	# --- mesh: a grid of quads every MESH_STEP points ---------------------------
	var cols := (nx - 1) / MESH_STEP + 1
	var rows := (nz - 1) / MESH_STEP + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(cols * rows)
	normals.resize(cols * rows)
	for r in rows:
		for c in cols:
			var gx := mini(c * MESH_STEP, nx - 1)
			var gz := mini(r * MESH_STEP, nz - 1)
			var x := origin.x + gx * spacing
			var z := origin.y + gz * spacing
			verts[r * cols + c] = Vector3(x, heights[gz * nx + gx] - GROUND_DROP, z)
	for r in rows:
		for c in cols:
			var l := verts[r * cols + maxi(c - 1, 0)]
			var rr := verts[r * cols + mini(c + 1, cols - 1)]
			var u := verts[maxi(r - 1, 0) * cols + c]
			var d := verts[mini(r + 1, rows - 1) * cols + c]
			normals[r * cols + c] = (d - u).cross(rr - l).normalized()
			if normals[r * cols + c].y < 0.0:
				normals[r * cols + c] = -normals[r * cols + c]
	var idx := PackedInt32Array()
	for r in rows - 1:
		for c in cols - 1:
			var i := r * cols + c
			# Clockwise seen from above (Godot's front faces).
			idx.append_array([i, i + 1, i + cols, i + 1, i + cols + 1, i + cols])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_ground.gdshader")
	var mask: Texture2D = load("res://data/ground_mask.png")
	if mask != null:
		mat.set_shader_parameter("ground_mask", mask)
	var size := Vector2((nx - 1) * spacing, (nz - 1) * spacing)
	mat.set_shader_parameter("mask_origin", origin)
	mat.set_shader_parameter("mask_size", size)
	mesh.surface_set_material(0, mat)
	# A wide skirt carrying the edge heights outward, so the land runs on to
	# the horizon instead of stopping at the edge of the survey.
	var skirt := MeshKit.new()
	var reach := 700.0
	var ring := PackedVector3Array()
	for c in cols:
		ring.append(verts[c])
	for r in range(1, rows):
		ring.append(verts[r * cols + cols - 1])
	for c in range(cols - 2, -1, -1):
		ring.append(verts[(rows - 1) * cols + c])
	for r in range(rows - 2, 0, -1):
		ring.append(verts[r * cols])
	var centre := Vector3(origin.x + size.x * 0.5, 0.0, origin.y + size.y * 0.5)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var oa := Vector2(a.x - centre.x, a.z - centre.z).normalized() * reach
		var ob := Vector2(b.x - centre.x, b.z - centre.z).normalized() * reach
		skirt.ground_quad(a, b, Vector3(b.x + ob.x, b.y, b.z + ob.y), Vector3(a.x + oa.x, a.y, a.z + oa.y))
	skirt.commit(mesh, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# --- collision: a height map at the grid's own spacing ------------------------
	var hm := HeightMapShape3D.new()
	hm.map_width = nx
	hm.map_depth = nz
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for i in heights.size():
		# The shape is scaled by `spacing` below, heights included, so divide here.
		data[i] = (heights[i] - GROUND_DROP) / spacing
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = Layers.GROUND
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = hm
	# A height map is centred on its node; put it over the grid.
	cs.position = Vector3(origin.x + size.x * 0.5, 0.0, origin.y + size.y * 0.5)
	cs.scale = Vector3(spacing, spacing, spacing)
	body.add_child(cs)
	root.add_child(body)

	# --- the harbour: water at sea level where the land dips below it -------------
	var water := MeshInstance3D.new()
	water.name = "Harbour"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	water.mesh = plane
	water.position = Vector3(origin.x + size.x * 0.5, 0.15, origin.y + size.y * 0.5)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.32, 0.38)
	wm.roughness = 0.08
	wm.metallic = 0.35
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	return root

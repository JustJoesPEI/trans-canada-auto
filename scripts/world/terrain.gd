class_name Terrain
extends RefCounted
## The real shape of the ground, from NRCan's lidar ground model (PEI 2020,
## bare earth) sampled onto a 2 m grid by tools/fetch_elevation.py.
##
## World y is metres above sea level, so heights in the game are real
## heights. Everything that stands on the ground asks height_at(). The
## heights stay packed in memory as they come from data/elevation.bin
## (16-bit centimetres), about 22 MB for the whole city.
##
## The ground itself is built a chunk at a time (chunk_mesh, chunk_collision)
## by the chunk builder; build_global() makes what covers the whole map:
## the harbour, a coarse version of all the land (seen far off, where no
## chunk is built), the land running on past the edge of the survey, and a
## coarse safety floor under everything.

## The open ground sits this far below the true surface, so streets and
## sidewalks (built at the true surface) always draw on top of it.
const GROUND_DROP := 0.08
## Under streets and sidewalks the ground drops this much further, so a bump
## or a crowned bit of ground between the street's vertices never shows
## through it (and the car never catches on it).
const STREET_CARVE := 0.25
## Sea level water sits this high (just above the mean, like a calm tide).
const WATER_Y := 0.15

var origin := Vector2.ZERO # (x, z) of grid point [0, 0]
var spacing := 2.0
var nx := 0
var nz := 0
var _cm := PackedByteArray() # int16 little-endian centimetres, row-major
var info: Dictionary = {}

static var _ground_shader: Shader


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
	var bin_path := path.get_base_dir().path_join(str(d.get("file", "elevation.bin")))
	var packed := FileAccess.get_file_as_bytes(bin_path)
	if packed.is_empty():
		push_warning("Terrain: %s not found; the town will be flat." % bin_path)
		t.nx = 0
		return t
	t._cm = packed.decompress(int(d["bytes"]), FileAccess.COMPRESSION_DEFLATE)
	if t._cm.size() != t.nx * t.nz * 2:
		push_warning("Terrain: %s is the wrong size; the town will be flat." % bin_path)
		t._cm = PackedByteArray()
	return t


func is_flat() -> bool:
	return _cm.is_empty()


## Height of grid point (ix, iz), clamped to the grid.
func grid_h(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, nx - 1)
	iz = clampi(iz, 0, nz - 1)
	return _cm.decode_s16((iz * nx + ix) * 2) * 0.01


## Raises grid point (ix, iz) to at least height h (m). Only for fixing up
## the ground at startup, before any chunk is built.
func raise_grid(ix: int, iz: int, h: float) -> void:
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return
	var i := (iz * nx + ix) * 2
	var cm := clampi(int(round(h * 100.0)), -32768, 32767)
	if cm > _cm.decode_s16(i):
		_cm.encode_s16(i, cm)


## Ground height (m above sea level) at a world position, smoothly
## interpolated. Outside the surveyed area the edge height carries on.
func height_at(x: float, z: float) -> float:
	if _cm.is_empty():
		return 0.0
	var fx := clampf((x - origin.x) / spacing, 0.0, float(nx - 1) - 0.001)
	var fz := clampf((z - origin.y) / spacing, 0.0, float(nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := (iz * nx + ix) * 2
	var row := nx * 2
	var a := _cm.decode_s16(i)
	var b := _cm.decode_s16(i + 2)
	var c := _cm.decode_s16(i + row)
	var d := _cm.decode_s16(i + row + 2)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) * 0.01


func h2(p: Vector2) -> float:
	return height_at(p.x, p.y)


## A point on the ground: Vector2(x, z) plus a lift above the surface.
func at(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)


static func ground_shader() -> Shader:
	if _ground_shader == null:
		_ground_shader = load("res://shaders/terrain_ground.gdshader")
	return _ground_shader


## The ground's material for one chunk: its own fine ground mask if there
## is one, otherwise the coarse whole-map mask.
static func ground_material(mask: Texture2D, mask_origin: Vector2, mask_size: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ground_shader()
	if mask != null:
		mat.set_shader_parameter("ground_mask", mask)
	mat.set_shader_parameter("mask_origin", mask_origin)
	mat.set_shader_parameter("mask_size", mask_size)
	return mat


## The ground mesh over `rect` (a chunk), with a quad every `step` metres
## (a multiple of the grid spacing). A skirt hangs down round the edge so
## neighbouring chunks at a different step never show a crack.
## `carve` (optional) is RoadNetwork.street_mask over the same rect at
## `carve_spacing`: the points under a street sit STREET_CARVE lower.
func chunk_mesh(rect: Rect2, step: float, mat: Material, carve := PackedByteArray(), carve_spacing := 2.0) -> ArrayMesh:
	var n := int(round(rect.size.x / step))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := n + 1
	verts.resize(cols * cols)
	normals.resize(cols * cols)
	var ratio := int(round(step / carve_spacing))
	var mcols := n * ratio + 1
	var carving := carve.size() == mcols * mcols
	for r in cols:
		for c in cols:
			var x := rect.position.x + c * step
			var z := rect.position.y + r * step
			var drop := GROUND_DROP
			if carving and carve[r * ratio * mcols + c * ratio] != 0:
				drop += STREET_CARVE
			verts[r * cols + c] = Vector3(x, height_at(x, z) - drop, z)
	var e := step
	for r in cols:
		for c in cols:
			var v := verts[r * cols + c]
			var hl := height_at(v.x - e, v.z)
			var hr := height_at(v.x + e, v.z)
			var hu := height_at(v.x, v.z - e)
			var hd := height_at(v.x, v.z + e)
			normals[r * cols + c] = Vector3(hl - hr, 2.0 * e, hu - hd).normalized()
	var idx := PackedInt32Array()
	for r in n:
		for c in n:
			var i := r * cols + c
			# Clockwise seen from above (Godot's front faces).
			idx.append_array([i, i + 1, i + cols, i + 1, i + cols + 1, i + cols])
	# Skirt: a strip hanging 1.5 m down along each edge.
	var ring: Array[int] = []
	for c in cols:
		ring.append(c)
	for r in range(1, cols):
		ring.append(r * cols + n)
	for c in range(n - 1, -1, -1):
		ring.append(n * cols + c)
	for r in range(n - 1, 0, -1):
		ring.append(r * cols)
	var base := verts.size()
	for k in ring:
		verts.append(verts[k] - Vector3(0, 1.5, 0))
		normals.append(normals[k])
	for j in ring.size():
		var a := ring[j]
		var b := ring[(j + 1) % ring.size()]
		var a2 := base + j
		var b2 := base + (j + 1) % ring.size()
		# Both windings, so it shows from either side.
		idx.append_array([a, b, b2, a, b2, a2, a, b2, b, a, a2, b2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


## Ground collision for a chunk: a height map at the grid's own spacing.
## Returns a CollisionShape3D, positioned, ready to go under a body.
func chunk_collision(rect: Rect2, carve := PackedByteArray()) -> CollisionShape3D:
	var n := int(round(rect.size.x / spacing)) + 1
	var carving := carve.size() == n * n
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	var gx0 := int(round((rect.position.x - origin.x) / spacing))
	var gz0 := int(round((rect.position.y - origin.y) / spacing))
	var exact := is_equal_approx(origin.x + gx0 * spacing, rect.position.x) and is_equal_approx(origin.y + gz0 * spacing, rect.position.y)
	for r in n:
		for c in n:
			var h: float
			if exact:
				h = grid_h(gx0 + c, gz0 + r)
			else:
				h = height_at(rect.position.x + c * spacing, rect.position.y + r * spacing)
			# The shape is scaled by `spacing` below, heights included, so divide here.
			if carving and carve[r * n + c] != 0:
				h -= STREET_CARVE
			data[r * n + c] = (h - GROUND_DROP) / spacing
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	# A height map is centred on its node; put it over the chunk.
	cs.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	cs.scale = Vector3(spacing, spacing, spacing)
	return cs


## What covers the whole map, built once: the harbour water, land carried on
## past the survey to the horizon, and a coarse floor a metre under the real
## ground so nothing ever falls out of the world while a chunk loads.
func build_global(coarse_mask: Texture2D) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	if _cm.is_empty():
		return root
	var size := Vector2((nx - 1) * spacing, (nz - 1) * spacing)
	var centre := origin + size * 0.5

	# --- safety floor: 16 m grid, a metre under the lowest ground near each point ---
	var step := 8
	var cols := (nx - 1) / step + 1
	var rows := (nz - 1) / step + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = cols
	hm.map_depth = rows
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	var fs := spacing * step
	for r in rows:
		for c in cols:
			# The lowest ground round this point, so the floor never rises
			# above the real ground in a narrow valley or ditch.
			data[r * cols + c] = (_low_h(c * step, r * step, step) - 1.0) / fs
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "SafetyFloor"
	body.collision_layer = Layers.GROUND
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.position = Vector3(origin.x + (cols - 1) * fs * 0.5, 0.0, origin.y + (rows - 1) * fs * 0.5)
	cs.scale = Vector3(fs, fs, fs)
	body.add_child(cs)
	root.add_child(body)

	# --- the whole map, coarse: under the chunks, seen where none are built ----
	var mat := ground_material(coarse_mask, origin, size)
	var far := Node3D.new()
	far.name = "FarLand"
	var fstep := 40.0
	var tiles := 4
	var tile := ceilf(size.x / tiles / fstep) * fstep
	var tile_z := ceilf(size.y / tiles / fstep) * fstep
	for tx in tiles:
		for tz in tiles:
			var r := Rect2(origin + Vector2(tx * tile, tz * tile_z), Vector2(tile, tile_z))
			var tmi := MeshInstance3D.new()
			tmi.mesh = coarse_mesh(r, fstep, 1.5, mat)
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.add_child(tmi)
	root.add_child(far)

	# --- land beyond the survey: a wide skirt carrying the edge heights out -----
	var skirt := MeshKit.new()
	var reach := 2500.0
	var ring := PackedVector3Array()
	var k := 16
	for c in range(0, nx, k):
		ring.append(_edge_v(c, 0))
	for r in range(0, nz, k):
		ring.append(_edge_v(nx - 1, r))
	for c in range(nx - 1, -1, -k):
		ring.append(_edge_v(c, nz - 1))
	for r in range(nz - 1, -1, -k):
		ring.append(_edge_v(0, r))
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var oa := Vector2(a.x - centre.x, a.z - centre.y).normalized() * reach
		var ob := Vector2(b.x - centre.x, b.z - centre.y).normalized() * reach
		skirt.ground_quad(a, b, Vector3(b.x + ob.x, b.y, b.z + ob.y), Vector3(a.x + oa.x, a.y, a.z + oa.y))
	var mi := MeshInstance3D.new()
	mi.name = "LandBeyond"
	mi.mesh = skirt.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# --- the harbour and rivers: water at sea level where the land dips below --
	var water := MeshInstance3D.new()
	water.name = "Harbour"
	var plane := PlaneMesh.new()
	plane.size = size + Vector2(reach, reach) * 2.0
	water.mesh = plane
	water.position = Vector3(centre.x, WATER_Y, centre.y)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.32, 0.38)
	wm.roughness = 0.08
	wm.metallic = 0.35
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	return root


## A plain height-field mesh over `rect` every `step` metres, `drop` metres
## below the ground (so the real chunks always draw over it).
func coarse_mesh(rect: Rect2, step: float, drop: float, mat: Material) -> ArrayMesh:
	var cols := int(round(rect.size.x / step)) + 1
	var rows := int(round(rect.size.y / step)) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for r in rows:
		for c in cols:
			var x := rect.position.x + c * step
			var z := rect.position.y + r * step
			verts.append(Vector3(x, _low_at(x, z, step * 0.5) - drop, z))
			var hl := height_at(x - step, z)
			var hr := height_at(x + step, z)
			var hu := height_at(x, z - step)
			var hd := height_at(x, z + step)
			normals.append(Vector3(hl - hr, 2.0 * step, hu - hd).normalized())
	var idx := PackedInt32Array()
	for r in rows - 1:
		for c in cols - 1:
			var i := r * cols + c
			idx.append_array([i, i + 1, i + cols, i + 1, i + cols + 1, i + cols])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


## Lowest grid height within half a cell (`reach` grid points) of (ix, iz),
## on a 3 x 3 pattern. Ditches narrower than that are covered by the floor
## sitting a metre down.
func _low_h(ix: int, iz: int, reach: int) -> float:
	var low := INF
	var h := reach / 2
	for a in 3:
		for b in 3:
			low = minf(low, grid_h(ix + (a - 1) * h, iz + (b - 1) * h))
	return low


## Lowest ground within `reach` metres of (x, z), on a 3 x 3 pattern.
func _low_at(x: float, z: float, reach: float) -> float:
	var low := INF
	for a in 3:
		for b in 3:
			low = minf(low, height_at(x + (a - 1) * reach, z + (b - 1) * reach))
	return low


func _edge_v(ix: int, iz: int) -> Vector3:
	return Vector3(origin.x + ix * spacing, grid_h(ix, iz) - GROUND_DROP, origin.y + iz * spacing)

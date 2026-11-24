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


## The heights as loaded, before any fixing up (kept only where the map can
## be reloaded live, see WorldBuilder.reload_edits).
var _raw := PackedByteArray()


## Keeps a copy of the heights as they are now, for raw_copy().
func keep_raw() -> void:
	_raw = _cm.duplicate()


## A new Terrain with the heights as keep_raw() found them (null if no
## copy was kept), to fix up again and hand back with take_heights().
func raw_copy() -> Terrain:
	if _raw.is_empty():
		return null
	var t := Terrain.new()
	t.info = info
	t.origin = origin
	t.spacing = spacing
	t.nx = nx
	t.nz = nz
	t._cm = _raw.duplicate()
	return t


## Takes the heights of another Terrain over the same grid (see raw_copy).
func take_heights(other: Terrain) -> void:
	_cm = other._cm


## How the ground under the streets is smoothed (smooth_under): round each
## block of SMOOTH_BLOCK x SMOOTH_BLOCK grid points (8 m across on the 2 m
## grid) a plane is fitted to the street points of the block and its eight
## neighbours (24 m across), and the blocks' planes are blended into one
## surface. A street keeps the real grade and camber of its hill but
## loses the lidar's lumps.
const SMOOTH_BLOCK := 4
## A roadway point the fit would move more than SMOOTH_KEEP is probably
## beside a road at another level (a ramp climbing beside the highway):
## past it the smoothing fades out, and by SMOOTH_KEEP * 2.5 the point
## keeps its real height.
const SMOOTH_KEEP := 0.25
## Off the roadway (sidewalks, verges, the strip where the smoothing fades
## out) the ground follows the roadway's surface, but never moves further
## than this.
const SMOOTH_REACH := 0.6
const SMOOTH_TILE := 256 ## grid points; a multiple of SMOOTH_BLOCK
const _SMOOTH_PAD := 2 ## blocks round each tile, for the blend's reach


## Smooths the grid points listed in `keys` (tile << 32 | point index, the
## tile being SMOOTH_TILE points square, numbered row by row): each moves
## toward the smooth surface fitted to the nearby points marked in `src`,
## by its weight in `wt` (255 = all the way). Only for fixing up the ground
## at startup.
##
## Fitting planes (least squares) rather than taking plain averages keeps a
## steady grade exact even where a street only crosses the corner of a
## block, and blending planes keeps it exact between blocks.
func smooth_under(keys: PackedInt64Array, wt: PackedByteArray, src: PackedByteArray) -> void:
	if keys.is_empty() or _cm.is_empty():
		return
	var b := SMOOTH_BLOCK
	var tiles_x := ceili(float(nx) / SMOOTH_TILE)
	var tb := SMOOTH_TILE / b
	var bnx := tiles_x * tb + 2 * _SMOOTH_PAD
	var bnz := ceili(float(nz) / SMOOTH_TILE) * tb + 2 * _SMOOTH_PAD
	# Positions are in grid points from the middle of the grid and heights
	# from the first street point, the same frame for every block.
	var ox := nx / 2
	var oz := nz / 2
	var base := -1.0e9
	# Per block, the sums a plane fit needs: n, x, z, h, xx, xz, zz, xh, zh.
	const M := 9
	var acc := PackedFloat64Array()
	acc.resize(bnx * bnz * M)
	var used := PackedInt32Array()
	for key in keys:
		var k := key & 0xffffffff
		if src[k] == 0:
			continue
		var ix := k % nx
		var iz := k / nx
		var h := _cm.decode_s16(k * 2) * 0.01
		if base < -1.0e8:
			base = h
		h -= base
		var x := float(ix - ox)
		var z := float(iz - oz)
		var bi := (iz / b + _SMOOTH_PAD) * bnx + ix / b + _SMOOTH_PAD
		var j := bi * M
		if acc[j] == 0.0:
			used.append(bi)
		acc[j] += 1.0
		acc[j + 1] += x
		acc[j + 2] += z
		acc[j + 3] += h
		acc[j + 4] += x * x
		acc[j + 5] += x * z
		acc[j + 6] += z * z
		acc[j + 7] += x * h
		acc[j + 8] += z * h
	if used.is_empty():
		return
	# Each block's plane, h = a + gx * x + gz * z, fitted over it and its
	# neighbours, stored pre-multiplied by the block's own street share:
	# (share * a, share * gx, share * gz, share).
	var planes := PackedFloat32Array()
	planes.resize(bnx * bnz * 4)
	var per := 1.0 / float(b * b)
	var sum := PackedFloat64Array()
	sum.resize(M)
	for bi in used:
		sum.fill(0.0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var j := (bi + dz * bnx + dx) * M
				if acc[j] == 0.0:
					continue
				for m in M:
					sum[m] += acc[j + m]
		var n := sum[0]
		var mx := sum[1] / n
		var mz := sum[2] / n
		var mh := sum[3] / n
		# A little ridge keeps the fit steady where the points lie along a
		# line (a narrow street): across it the plane just stays level.
		var cxx := sum[4] / n - mx * mx + 0.25
		var cxz := sum[5] / n - mx * mz
		var czz := sum[6] / n - mz * mz + 0.25
		var cxh := sum[7] / n - mx * mh
		var czh := sum[8] / n - mz * mh
		var det := cxx * czz - cxz * cxz
		var gx := (czz * cxh - cxz * czh) / det
		var gz := (cxx * czh - cxz * cxh) / det
		var c := acc[bi * M] * per
		var pi := bi * 4
		planes[pi] = (mh - gx * mx - gz * mz) * c
		planes[pi + 1] = gx * c
		planes[pi + 2] = gz * c
		planes[pi + 3] = c
	acc = PackedFloat64Array()
	var blocks := Image.create_from_data(bnx, bnz, false, Image.FORMAT_RGBAF, planes.to_byte_array())
	planes = PackedFloat32Array()
	# Tile by tile, blend the blocks' planes (bilinearly, block i standing at
	# grid point 4i + 1.5, its middle) back to one per grid point, and move
	# the points onto the blended plane there.
	keys.sort()
	var span := tb + 2 * _SMOOTH_PAD
	var size := span * b
	var cur := -1
	var up := PackedFloat32Array()
	var x0 := 0
	var z0 := 0
	var fade := 1.0 / (SMOOTH_KEEP * 1.5)
	for key in keys:
		var tile := key >> 32
		if tile != cur:
			cur = tile
			var tx := tile % tiles_x
			var tz := tile / tiles_x
			# The padded image's block (tx * tb, tz * tb) is PAD blocks before the tile.
			var reg := blocks.get_region(Rect2i(tx * tb, tz * tb, span, span))
			reg.resize(size, size, Image.INTERPOLATE_BILINEAR)
			up = reg.get_data().to_float32_array()
			x0 = tx * SMOOTH_TILE - _SMOOTH_PAD * b
			z0 = tz * SMOOTH_TILE - _SMOOTH_PAD * b
		var k := key & 0xffffffff
		var ix := k % nx
		var iz := k / nx
		var ui := ((iz - z0) * size + ix - x0) * 4
		var cover := up[ui + 3]
		if cover < 0.04:
			continue
		var h := _cm.decode_s16(k * 2) * 0.01
		var move := base + (up[ui] + up[ui + 1] * (ix - ox) + up[ui + 2] * (iz - oz)) / cover - h
		var w := wt[k] / 255.0
		if src[k] != 0:
			w *= clampf(1.0 - (absf(move) - SMOOTH_KEEP) * fade, 0.0, 1.0)
		else:
			move = clampf(move, -SMOOTH_REACH, SMOOTH_REACH)
		if w > 0.0:
			_cm.encode_s16(k * 2, clampi(int(round((h + move * w) * 100.0)), -32768, 32767))


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

class_name CarBuilder
extends RefCounted
## Builds a car's mesh from a shape in CarModels: a lofted lower body, a
## glasshouse with pillars, lights, bumpers, plates and mirrors, plus
## optional touches (hood scoop, spoiler, racing stripes, a pickup's box).
## One body mesh with two surfaces (paint and glass) and one wheel mesh per
## wheel size shared by every car, so a car is six draw calls. Colours are
## vertex colours, so all cars share the same two materials.
##
## Faces -Z (the front), wheels on the ground at y = 0.

static var _paint_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _wheel_meshes := {}

var shape: Dictionary
var paint: Color
var trim := Color(0.13, 0.13, 0.14)
var glass := Color(0.1, 0.13, 0.16)


func _init(car_shape: Dictionary, body_colour: Color) -> void:
	shape = car_shape
	paint = body_colour


static func paint_material() -> StandardMaterial3D:
	if _paint_mat == null:
		_paint_mat = StandardMaterial3D.new()
		_paint_mat.vertex_color_use_as_albedo = true
		_paint_mat.vertex_color_is_srgb = true
		_paint_mat.roughness = 0.32
		_paint_mat.metallic = 0.25
		_paint_mat.metallic_specular = 0.6
	return _paint_mat


static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.vertex_color_use_as_albedo = true
		_glass_mat.vertex_color_is_srgb = true
		_glass_mat.roughness = 0.05
		_glass_mat.metallic = 0.6
	return _glass_mat


func make_body() -> ArrayMesh:
	var body := MeshKit.new()
	body.use_color = true
	var win := MeshKit.new()
	win.use_color = true
	_lower_body(body)
	_cabin(body, win)
	if shape.has("bed"):
		_bed(body)
	_front_and_back(body)
	_wheel_arches(body)
	_mirrors(body)
	if shape.get("hood_scoop", false):
		_hood_scoop(body)
	if shape.get("spoiler", false):
		_spoiler(body)
	if shape.get("stripes", false):
		_stripes(body)
	var mesh := body.commit(null, paint_material())
	win.commit(mesh, glass_material())
	return mesh


# --- lower body: a lofted shell, nose to tail ------------------------------------------

static func _section(w: float, y0: float, y1: float) -> PackedVector2Array:
	# A rounded box, as (x, y) going round the car's cross-section.
	var round_top := minf(0.13, (y1 - y0) * 0.3)
	return PackedVector2Array([
		Vector2(-w * 0.93, y0), Vector2(-w, y0 + 0.1), Vector2(-w, y1 - round_top), Vector2(-w * 0.9, y1),
		Vector2(w * 0.9, y1), Vector2(w, y1 - round_top), Vector2(w, y0 + 0.1), Vector2(w * 0.93, y0),
	])


func _lower_body(kit: MeshKit) -> void:
	var rings: Array[PackedVector3Array] = []
	for st: Array in shape["stations"]:
		var sec := _section(st[1], st[2], st[3])
		var ring := PackedVector3Array()
		for p in sec:
			ring.append(Vector3(p.x, p.y, st[0]))
		rings.append(ring)
	var n := rings[0].size()
	for i in range(rings.size() - 1):
		for j in n:
			var a := rings[i][j]
			var b := rings[i][(j + 1) % n]
			var c := rings[i + 1][(j + 1) % n]
			var d := rings[i + 1][j]
			var mid := (a + b + c + d) * 0.25
			var out := Vector3(mid.x, mid.y - 0.6, 0.0)
			if j == n - 1:
				kit.color = trim.darkened(0.5) # underside
			elif j == 0 or j == n - 2:
				kit.color = trim # rocker panels
			else:
				kit.color = paint
			kit.quad(a, b, c, d, _face_normal(a, b, c, out))
		# A step in the top (a pickup's cab back) needs a wall to close it.
		var top_a := rings[i][3].y
		var top_b := rings[i + 1][3].y
		if absf(top_a - top_b) > 0.05:
			var hi := rings[i] if top_a > top_b else rings[i + 1]
			var lo := rings[i + 1] if top_a > top_b else rings[i]
			var nz := Vector3.BACK if top_a > top_b else Vector3.FORWARD
			kit.color = paint
			for j: int in [2, 3, 4]:
				var p0 := hi[j]
				var p1 := hi[j + 1]
				var y_lo := lo[3].y
				kit.quad(Vector3(p0.x, y_lo, p0.z), Vector3(p1.x, y_lo, p1.z), p1, p0, nz)
	_cap(kit, rings[0], Vector3.FORWARD)
	_cap(kit, rings[rings.size() - 1], Vector3.BACK)


func _cap(kit: MeshKit, ring: PackedVector3Array, n: Vector3) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	kit.color = paint
	for j in ring.size():
		kit.tri(c, ring[j], ring[(j + 1) % ring.size()], n)


static func _face_normal(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> Vector3:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.length() < 0.5:
		return outward.normalized()
	return nrm if nrm.dot(outward) >= 0.0 else -nrm


## Top surface height of the lower body at z (from the stations).
func _top_at(z: float) -> float:
	var st: Array = shape["stations"]
	for i in range(st.size() - 1):
		var a: Array = st[i]
		var b: Array = st[i + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var t := (z - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return lerpf(a[3], b[3], t)
	return float(st[0][3])


# --- cabin ---------------------------------------------------------------------------------

func _cabin(kit: MeshKit, win: MeshKit) -> void:
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var roof: float = cab["roof"]
	var wb: float = cab["wb"] # half width at the belt line
	var wr: float = cab["wr"] # half width at the roof
	var za: float = cab["za"] # windshield foot
	var zb: float = cab["zb"] # windshield top
	var zc: float = cab["zc"] # rear glass top
	var zd: float = cab["zd"] # rear glass foot
	var doors: int = cab.get("doors", 4)
	var c_pillar: float = cab.get("c_pillar", 0.22)
	var A := func(s: float) -> Vector3: return Vector3(wb * s, belt, za)
	var Bp := func(s: float) -> Vector3: return Vector3(wr * s, roof, zb)
	var C := func(s: float) -> Vector3: return Vector3(wr * s, roof, zc)
	var D := func(s: float) -> Vector3: return Vector3(wb * s, belt, zd)
	# Windshield, roof, back glass.
	win.color = glass
	win.quad(A.call(-1.0), A.call(1.0), Bp.call(1.0), Bp.call(-1.0), Vector3(0, zb - za, -(roof - belt)).normalized())
	kit.color = paint
	kit.quad(Bp.call(-1.0), Bp.call(1.0), C.call(1.0), C.call(-1.0), Vector3.UP)
	win.quad(C.call(-1.0), C.call(1.0), D.call(1.0), D.call(-1.0), Vector3(0, maxf(0.05, zd - zc), roof - belt).normalized())
	# Sides: glass, then pillars laid over it.
	for s: float in [-1.0, 1.0]:
		var out := Vector3(s, 0.32, 0.0).normalized()
		var a: Vector3 = A.call(s)
		var b: Vector3 = Bp.call(s)
		var c: Vector3 = C.call(s)
		var d: Vector3 = D.call(s)
		var b_low := Vector3(wb * s, belt, zb)
		var c_low := Vector3(wb * s, belt, zc)
		win.color = glass
		win.tri(a, b, b_low, out)
		win.quad(b_low, b, c, c_low, out)
		if zd - zc > 0.05:
			win.tri(c_low, c, d, out)
		kit.color = paint
		var lift := Vector3(s * 0.006, 0.0, 0.0)
		# A-pillar along the windshield edge.
		kit.quad(a + lift, b + lift, b + lift + Vector3(0, 0, 0.09), a + lift + Vector3(0, 0, 0.12), out)
		# B-pillar between the doors (four doors), or a little quarter window line (two).
		var zb_p := lerpf(zb, zc, 0.42) if doors == 4 else lerpf(zb, zc, 0.78)
		var top_b := Vector3(wr * s, roof, zb_p)
		var low_b := Vector3(wb * s, belt, zb_p)
		kit.color = trim
		kit.quad(low_b + lift + Vector3(0, 0, -0.045), top_b + lift + Vector3(0, 0, -0.045), top_b + lift + Vector3(0, 0, 0.045), low_b + lift + Vector3(0, 0, 0.045), out)
		# C-pillar.
		kit.color = paint
		if zd - zc > 0.05:
			kit.quad(c + lift + Vector3(0, 0, -c_pillar), c + lift, d + lift, d + lift + Vector3(0, 0, -c_pillar * 1.3), out)
		else:
			kit.quad(c_low + lift + Vector3(0, 0, -c_pillar), c + lift + Vector3(0, 0, -c_pillar), c + lift, c_low + lift, out)
		# Roof rail and belt trim.
		kit.quad(b + lift + Vector3(0, -0.04, 0), c + lift + Vector3(0, -0.04, 0), c + lift, b + lift, out)
		kit.color = trim
		kit.quad(a + lift, d + lift, d + lift + Vector3(0, 0.025, 0), a + lift + Vector3(0, 0.025, 0), out)
	# A cab whose back is upright (a pickup) needs a back wall below the glass.
	if zd - zc <= 0.05 and belt > _top_at(zd + 0.06) + 0.05:
		kit.color = paint
		var y0 := _top_at(zd + 0.06)
		kit.quad(Vector3(-wb, y0, zd), Vector3(wb, y0, zd), Vector3(wb, belt, zd), Vector3(-wb, belt, zd), Vector3.BACK)


# --- a pickup's box --------------------------------------------------------------------------

func _bed(kit: MeshKit) -> void:
	var bed: Dictionary = shape["bed"]
	var z0: float = bed["z0"]
	var z1: float = bed["z1"]
	var fl: float = bed["floor"]
	var top: float = bed["top"]
	var t: float = bed["thick"]
	var w: float = float(shape["width"]) * 0.5 - 0.01
	# Side walls: outside, inside and top edge.
	for s: float in [-1.0, 1.0]:
		var xo := w * s
		var xi := (w - t) * s
		kit.color = paint
		kit.quad(Vector3(xo, fl - 0.05, z0), Vector3(xo, fl - 0.05, z1), Vector3(xo, top, z1), Vector3(xo, top, z0), Vector3(s, 0, 0))
		kit.color = trim.lightened(0.15)
		kit.quad(Vector3(xi, fl, z0), Vector3(xi, fl, z1), Vector3(xi, top, z1), Vector3(xi, top, z0), Vector3(-s, 0, 0))
		kit.color = paint
		kit.quad(Vector3(xo, top, z0), Vector3(xo, top, z1), Vector3(xi, top, z1), Vector3(xi, top, z0), Vector3.UP)
	# Tailgate: back, inside and top.
	kit.color = paint
	kit.quad(Vector3(-w, fl - 0.05, z1 + t), Vector3(w, fl - 0.05, z1 + t), Vector3(w, top, z1 + t), Vector3(-w, top, z1 + t), Vector3.BACK)
	kit.color = trim.lightened(0.15)
	kit.quad(Vector3(-w + t, fl, z1), Vector3(w - t, fl, z1), Vector3(w - t, top, z1), Vector3(-w + t, top, z1), Vector3.FORWARD)
	kit.color = paint
	kit.quad(Vector3(-w, top, z1), Vector3(w, top, z1), Vector3(w, top, z1 + t), Vector3(-w, top, z1 + t), Vector3.UP)
	# Bed liner floor.
	kit.color = Color(0.09, 0.09, 0.1)
	kit.quad(Vector3(-w + t, fl + 0.004, z0), Vector3(w - t, fl + 0.004, z0), Vector3(w - t, fl + 0.004, z1), Vector3(-w + t, fl + 0.004, z1), Vector3.UP)


# --- nose, tail, arches, mirrors, extras -------------------------------------------------

func _front_and_back(kit: MeshKit) -> void:
	var st: Array = shape["stations"]
	var fz: float = float(st[0][0]) - 0.005
	var rz: float = float(st[st.size() - 1][0]) + 0.005
	if shape.has("bed"):
		rz = maxf(rz, float(shape["bed"]["z1"]) + float(shape["bed"]["thick"]) + 0.004)
	var w: float = float(shape["width"]) * 0.5
	var ly: float = shape.get("lights_y", 0.57)
	var ty: float = shape.get("tail_y", 0.68)
	var by := float(st[0][2]) + 0.1 # bumper height
	var f := Vector3.FORWARD
	var r := Vector3.BACK
	# Bumpers.
	kit.color = trim
	_panel(kit, Vector3(0, by, fz - 0.03), w * 1.9, 0.18, f)
	_panel(kit, Vector3(0, by + 0.02, rz + 0.03), w * 1.84, 0.18, r)
	# Grille.
	kit.color = Color(0.06, 0.06, 0.07)
	_panel(kit, Vector3(0, ly - 0.01, fz - 0.005), w * (0.95 if shape.has("bed") else 0.78), 0.12 if not shape.has("bed") else 0.26, f)
	# Headlights, indicators, tail lights.
	for s: float in [-1.0, 1.0]:
		kit.color = Color(0.92, 0.92, 0.86)
		_panel(kit, Vector3(w * 0.66 * s, ly, fz - 0.006), w * 0.38, 0.12, f)
		kit.color = Color(0.95, 0.6, 0.15)
		_panel(kit, Vector3(w * 0.9 * s, ly, fz + 0.02), 0.08, 0.1, f)
		kit.color = Color(0.75, 0.06, 0.05)
		_panel(kit, Vector3(w * 0.72 * s, ty, rz + 0.006), w * 0.36, 0.14 if not shape.has("bed") else 0.3, r)
	# Licence plates, PEI white.
	kit.color = Color(0.93, 0.93, 0.9)
	_panel(kit, Vector3(0, ty - 0.06, rz + 0.008), 0.34, 0.16, r)
	_panel(kit, Vector3(0, by, fz - 0.05), 0.34, 0.12, f)


## A flat rectangle facing n, centred at c.
func _panel(kit: MeshKit, c: Vector3, w: float, h: float, n: Vector3) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	kit.quad(c + Vector3(-hw, -hh, 0), c + Vector3(hw, -hh, 0), c + Vector3(hw, hh, 0), c + Vector3(-hw, hh, 0), n)


## Dark wheel openings painted on the body sides.
func _wheel_arches(kit: MeshKit) -> void:
	kit.color = Color(0.03, 0.03, 0.03)
	var wr: float = shape["wheel_radius"]
	var r := wr + 0.07
	var side_x: float = float(shape["width"]) * 0.5 + 0.003
	for z: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		var bottom := float(shape["stations"][1][2])
		for s: float in [-1.0, 1.0]:
			var c := Vector3(side_x * s, wr, z)
			var n := Vector3(s, 0, 0)
			for i in 10:
				var a0 := PI * float(i) / 10.0
				var a1 := PI * float(i + 1) / 10.0
				var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
				var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
				var base0 := Vector3(c.x, maxf(bottom, c.y), p0.z)
				var base1 := Vector3(c.x, maxf(bottom, c.y), p1.z)
				kit.quad(base0, p0, p1, base1, n)


func _mirrors(kit: MeshKit) -> void:
	kit.color = paint
	var cab: Dictionary = shape["cabin"]
	var y := float(cab["belt"]) + 0.1
	var z := float(cab["za"]) + 0.12
	var x := float(cab["wb"]) + 0.12
	for s: float in [-1.0, 1.0]:
		_box(kit, Vector3(x * s, y, z), Vector3(0.08, 0.06, 0.05))


func _box(kit: MeshKit, c: Vector3, h: Vector3) -> void:
	var corners := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0, 1, 2, 3, Vector3.FORWARD], [5, 4, 7, 6, Vector3.BACK], [4, 0, 3, 7, Vector3.LEFT],
		[1, 5, 6, 2, Vector3.RIGHT], [3, 2, 6, 7, Vector3.UP], [4, 5, 1, 0, Vector3.DOWN]]
	for fc: Array in faces:
		kit.quad(corners[fc[0]], corners[fc[1]], corners[fc[2]], corners[fc[3]], fc[4])


## A raised scoop in the middle of the hood.
func _hood_scoop(kit: MeshKit) -> void:
	var z := lerpf(float(shape["stations"][2][0]), float(shape["cabin"]["za"]), 0.55)
	var y := _top_at(z)
	kit.color = paint.darkened(0.1)
	_box(kit, Vector3(0, y + 0.03, z), Vector3(0.24, 0.045, 0.26))
	kit.color = Color(0.05, 0.05, 0.05)
	_panel(kit, Vector3(0, y + 0.035, z - 0.262), 0.4, 0.05, Vector3.FORWARD)


## A small wing on the trunk lid.
func _spoiler(kit: MeshKit) -> void:
	var st: Array = shape["stations"]
	var z := float(st[st.size() - 2][0]) - 0.12
	var y := _top_at(z)
	var w := float(shape["width"]) * 0.42
	kit.color = paint
	_box(kit, Vector3(0, y + 0.14, z), Vector3(w, 0.018, 0.1))
	for s: float in [-1.0, 1.0]:
		_box(kit, Vector3(w * 0.8 * s, y + 0.07, z), Vector3(0.025, 0.06, 0.05))


## Twin racing stripes over the hood, roof and trunk.
func _stripes(kit: MeshKit) -> void:
	kit.color = Color(0.95, 0.94, 0.9) if paint.get_luminance() < 0.6 else Color(0.12, 0.12, 0.13)
	var st: Array = shape["stations"]
	var cab: Dictionary = shape["cabin"]
	for s: float in [-1.0, 1.0]:
		var x0 := 0.08 * s
		var x1 := 0.2 * s
		# Hood and trunk, following the lower body's top.
		for i in range(st.size() - 1):
			var za := float(st[i][0])
			var zb := float(st[i + 1][0])
			if za > float(cab["za"]) - 0.01 and zb < float(cab["zd"]) + 0.01:
				continue
			# Only along the flat of the hood and trunk, not down the nose or tail.
			if absf(float(st[i + 1][3]) - float(st[i][3])) > 0.07:
				continue
			var ya := float(st[i][3]) + 0.006
			var yb := float(st[i + 1][3]) + 0.006
			kit.quad(Vector3(x0, ya, za), Vector3(x1, ya, za), Vector3(x1, yb, zb), Vector3(x0, yb, zb), Vector3.UP)
		# Roof.
		var ry := float(cab["roof"]) + 0.006
		kit.quad(Vector3(x0, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zc"])), Vector3(x0, ry, float(cab["zc"])), Vector3.UP)


# --- wheels --------------------------------------------------------------------------------

## A wheel of the given size, axle along X, outer face (hubcap) on +X.
## Mirror it (scale.x = -1) for the left side. Shared by every car with
## wheels this size.
static func wheel_mesh(r: float = 0.31, width: float = 0.2) -> ArrayMesh:
	var key := "%.3f/%.3f" % [r, width]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var kit := MeshKit.new()
	kit.use_color = true
	var segs := 18
	var hw := width * 0.5
	var tyre := Color(0.07, 0.07, 0.07)
	var sidewall := Color(0.1, 0.1, 0.1)
	var hub := Color(0.72, 0.73, 0.74)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		kit.color = tyre
		kit.quad(Vector3(-hw * 0.85, 0, 0) + d0 * r, Vector3(hw * 0.85, 0, 0) + d0 * r, Vector3(hw * 0.85, 0, 0) + d1 * r, Vector3(-hw * 0.85, 0, 0) + d1 * r, (d0 + d1).normalized())
		for s: float in [-1.0, 1.0]:
			kit.color = tyre
			kit.quad(Vector3(hw * 0.85 * s, 0, 0) + d0 * r, Vector3(hw * s, 0, 0) + d0 * r * 0.93, Vector3(hw * s, 0, 0) + d1 * r * 0.93, Vector3(hw * 0.85 * s, 0, 0) + d1 * r, ((d0 + d1).normalized() + Vector3(s, 0, 0)).normalized())
			kit.color = sidewall
			kit.quad(Vector3(hw * s, 0, 0) + d0 * r * 0.93, Vector3(hw * s, 0, 0) + d0 * r * 0.64, Vector3(hw * s, 0, 0) + d1 * r * 0.64, Vector3(hw * s, 0, 0) + d1 * r * 0.93, Vector3(s, 0, 0))
		kit.color = hub
		kit.tri(Vector3(hw + 0.012, 0, 0), Vector3(hw + 0.004, 0, 0) + d0 * r * 0.64, Vector3(hw + 0.004, 0, 0) + d1 * r * 0.64, Vector3.RIGHT)
		kit.color = Color(0.2, 0.2, 0.21)
		kit.tri(Vector3(-hw, 0, 0), Vector3(-hw, 0, 0) + d0 * r * 0.64, Vector3(-hw, 0, 0) + d1 * r * 0.64, Vector3.LEFT)
		if i % 3 == 0:
			kit.color = hub.darkened(0.35)
			kit.tri(Vector3(hw + 0.013, 0, 0) + d0 * r * 0.15, Vector3(hw + 0.013, 0, 0) + d0 * r * 0.58, Vector3(hw + 0.013, 0, 0) + d1 * r * 0.58, Vector3.RIGHT)
	var mesh := kit.commit(null, paint_material())
	_wheel_meshes[key] = mesh
	return mesh

class_name CarBuilder
extends RefCounted
## Builds an ordinary older four-door sedan from code: about 4.7 m long,
## 1.78 m wide, 1.42 m tall, 2.7 m wheelbase. One body mesh with two
## surfaces (paint and glass) plus one wheel mesh shared by all four wheels,
## so a car is six draw calls. Colours are vertex colours, so every car in
## town shares the same two materials.
##
## Faces -Z (the front), wheels on the ground at y = 0.

const WHEEL_RADIUS := 0.31
const WHEEL_WIDTH := 0.2
const TRACK_HALF := 0.81 ## wheel centre from the middle of the car
const FRONT_AXLE_Z := -1.35
const REAR_AXLE_Z := 1.35
const LENGTH := 4.72
const WIDTH := 1.8

static var _paint_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _wheel_mesh: ArrayMesh

var paint: Color
var trim := Color(0.13, 0.13, 0.14)
var glass := Color(0.1, 0.13, 0.16)


func _init(body_colour: Color) -> void:
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


## Lower body, cabin, lights, bumpers, plate and mirrors.
func make_body() -> ArrayMesh:
	var body := MeshKit.new()
	body.use_color = true
	var win := MeshKit.new()
	win.use_color = true
	_lower_body(body)
	_cabin(body, win)
	_front_and_back(body)
	_wheel_arches(body)
	_mirrors(body)
	var mesh := body.commit(null, paint_material())
	win.commit(mesh, glass_material())
	return mesh


# --- lower body: a lofted shell, nose to tail ------------------------------------------

## z, half width, bottom y, top y (front of the car is -z)
const STATIONS := [
	[-2.36, 0.83, 0.3, 0.6],
	[-2.31, 0.87, 0.27, 0.69],
	[-2.1, 0.89, 0.27, 0.77],
	[-1.5, 0.9, 0.28, 0.84],
	[-0.8, 0.9, 0.28, 0.9],
	[0.9, 0.9, 0.28, 0.92],
	[1.55, 0.89, 0.28, 0.91],
	[2.15, 0.87, 0.29, 0.88],
	[2.31, 0.84, 0.3, 0.72],
	[2.36, 0.81, 0.32, 0.62],
]


static func _section(w: float, y0: float, y1: float) -> PackedVector2Array:
	# A rounded box, as (x, y) going round the car's cross-section.
	return PackedVector2Array([
		Vector2(-w * 0.93, y0), Vector2(-w, y0 + 0.1), Vector2(-w, y1 - 0.13), Vector2(-w * 0.9, y1),
		Vector2(w * 0.9, y1), Vector2(w, y1 - 0.13), Vector2(w, y0 + 0.1), Vector2(w * 0.93, y0),
	])


func _lower_body(kit: MeshKit) -> void:
	var rings: Array[PackedVector3Array] = []
	for st: Array in STATIONS:
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
	# End caps.
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


# --- cabin ---------------------------------------------------------------------------------

func _cabin(kit: MeshKit, win: MeshKit) -> void:
	var belt := 0.9
	var roof := 1.41
	var wb := 0.86 # half width at the belt line
	var wr := 0.69 # half width at the roof
	var za := -0.82 # windshield foot
	var zb := -0.06 # windshield top
	var zc := 0.78 # rear glass top
	var zd := 1.45 # rear glass foot
	var A := func(s: float) -> Vector3: return Vector3(wb * s, belt, za)
	var Bp := func(s: float) -> Vector3: return Vector3(wr * s, roof, zb)
	var C := func(s: float) -> Vector3: return Vector3(wr * s, roof, zc)
	var D := func(s: float) -> Vector3: return Vector3(wb * s, belt, zd)
	# Windshield, roof, back glass.
	win.color = glass
	win.quad(A.call(-1.0), A.call(1.0), Bp.call(1.0), Bp.call(-1.0), Vector3(0, 0.75, -0.66).normalized())
	kit.color = paint
	kit.quad(Bp.call(-1.0), Bp.call(1.0), C.call(1.0), C.call(-1.0), Vector3.UP)
	win.quad(C.call(-1.0), C.call(1.0), D.call(1.0), D.call(-1.0), Vector3(0, 0.8, 0.6).normalized())
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
		win.tri(c_low, c, d, out)
		kit.color = paint
		var lift := Vector3(s * 0.006, 0.0, 0.0)
		# A-pillar along the windshield edge.
		kit.quad(a + lift, b + lift, b + lift + Vector3(0, 0, 0.09), a + lift + Vector3(0, 0, 0.12), out)
		# B-pillar between the doors.
		var zb_p := 0.3
		var top_b := Vector3(wr * s, roof, zb_p)
		var low_b := Vector3(wb * s, belt, zb_p)
		kit.color = trim
		kit.quad(low_b + lift + Vector3(0, 0, -0.045), top_b + lift + Vector3(0, 0, -0.045), top_b + lift + Vector3(0, 0, 0.045), low_b + lift + Vector3(0, 0, 0.045), out)
		# A broad C-pillar, as these sedans had.
		kit.color = paint
		kit.quad(c + lift + Vector3(0, 0, -0.22), c + lift, d + lift, d + lift + Vector3(0, 0, -0.3), out)
		# Roof rail and belt trim.
		kit.quad(b + lift + Vector3(0, -0.04, 0), c + lift + Vector3(0, -0.04, 0), c + lift, b + lift, out)
		kit.color = trim
		kit.quad(a + lift, d + lift, d + lift + Vector3(0, 0.025, 0), a + lift + Vector3(0, 0.025, 0), out)


# --- nose, tail, arches, mirrors --------------------------------------------------------

func _front_and_back(kit: MeshKit) -> void:
	var fz := -2.365
	var rz := 2.365
	var f := Vector3.FORWARD
	var r := Vector3.BACK
	# Bumpers.
	kit.color = trim
	_panel(kit, Vector3(0, 0.38, fz - 0.03), 1.72, 0.18, f)
	_panel(kit, Vector3(0, 0.4, rz + 0.03), 1.66, 0.18, r)
	# Grille.
	kit.color = Color(0.06, 0.06, 0.07)
	_panel(kit, Vector3(0, 0.56, fz - 0.005), 0.7, 0.12, f)
	# Headlights and indicators.
	for s: float in [-1.0, 1.0]:
		kit.color = Color(0.92, 0.92, 0.86)
		_panel(kit, Vector3(0.6 * s, 0.57, fz - 0.006), 0.36, 0.12, f)
		kit.color = Color(0.95, 0.6, 0.15)
		_panel(kit, Vector3(0.83 * s, 0.57, fz + 0.02), 0.08, 0.1, f)
		# Tail lights.
		kit.color = Color(0.75, 0.06, 0.05)
		_panel(kit, Vector3(0.62 * s, 0.68, rz + 0.006), 0.36, 0.14, r)
	# Licence plates, PEI white.
	kit.color = Color(0.93, 0.93, 0.9)
	_panel(kit, Vector3(0, 0.62, rz + 0.008), 0.34, 0.16, r)
	_panel(kit, Vector3(0, 0.38, fz - 0.05), 0.34, 0.12, f)


## A flat rectangle facing n, centred at c.
func _panel(kit: MeshKit, c: Vector3, w: float, h: float, n: Vector3) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	kit.quad(c + Vector3(-hw, -hh, 0), c + Vector3(hw, -hh, 0), c + Vector3(hw, hh, 0), c + Vector3(-hw, hh, 0), n)


## Dark wheel openings painted on the body sides.
func _wheel_arches(kit: MeshKit) -> void:
	kit.color = Color(0.03, 0.03, 0.03)
	var r := WHEEL_RADIUS + 0.07
	for z: float in [FRONT_AXLE_Z, REAR_AXLE_Z]:
		for s: float in [-1.0, 1.0]:
			var c := Vector3(0.903 * s, WHEEL_RADIUS, z)
			var n := Vector3(s, 0, 0)
			for i in 10:
				var a0 := PI * float(i) / 10.0
				var a1 := PI * float(i + 1) / 10.0
				var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
				var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
				var base0 := Vector3(c.x, maxf(0.27, c.y), p0.z)
				var base1 := Vector3(c.x, maxf(0.27, c.y), p1.z)
				kit.quad(base0, p0, p1, base1, n)


func _mirrors(kit: MeshKit) -> void:
	kit.color = paint
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0.98 * s, 1.0, -0.72)
		var hx := 0.08
		var hy := 0.06
		var hz := 0.05
		var corners := [
			c + Vector3(-hx, -hy, -hz), c + Vector3(hx, -hy, -hz), c + Vector3(hx, hy, -hz), c + Vector3(-hx, hy, -hz),
			c + Vector3(-hx, -hy, hz), c + Vector3(hx, -hy, hz), c + Vector3(hx, hy, hz), c + Vector3(-hx, hy, hz),
		]
		var faces := [[0, 1, 2, 3, Vector3.FORWARD], [5, 4, 7, 6, Vector3.BACK], [4, 0, 3, 7, Vector3.LEFT],
			[1, 5, 6, 2, Vector3.RIGHT], [3, 2, 6, 7, Vector3.UP], [4, 5, 1, 0, Vector3.DOWN]]
		for fc: Array in faces:
			kit.quad(corners[fc[0]], corners[fc[1]], corners[fc[2]], corners[fc[3]], fc[4])


# --- wheels --------------------------------------------------------------------------------

## One wheel, axle along X, outer face (hubcap) on +X. Mirror it (scale.x = -1)
## for the left side. Shared by every wheel of every car.
static func wheel_mesh() -> ArrayMesh:
	if _wheel_mesh != null:
		return _wheel_mesh
	var kit := MeshKit.new()
	kit.use_color = true
	var segs := 18
	var r := WHEEL_RADIUS
	var hw := WHEEL_WIDTH * 0.5
	var tyre := Color(0.07, 0.07, 0.07)
	var sidewall := Color(0.1, 0.1, 0.1)
	var hub := Color(0.72, 0.73, 0.74)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		# Tread, slightly rounded at the shoulders.
		kit.color = tyre
		kit.quad(Vector3(-hw * 0.85, 0, 0) + d0 * r, Vector3(hw * 0.85, 0, 0) + d0 * r, Vector3(hw * 0.85, 0, 0) + d1 * r, Vector3(-hw * 0.85, 0, 0) + d1 * r, (d0 + d1).normalized())
		for s: float in [-1.0, 1.0]:
			kit.color = tyre
			kit.quad(Vector3(hw * 0.85 * s, 0, 0) + d0 * r, Vector3(hw * s, 0, 0) + d0 * r * 0.93, Vector3(hw * s, 0, 0) + d1 * r * 0.93, Vector3(hw * 0.85 * s, 0, 0) + d1 * r, ((d0 + d1).normalized() + Vector3(s, 0, 0)).normalized())
			# Sidewall ring.
			kit.color = sidewall
			kit.quad(Vector3(hw * s, 0, 0) + d0 * r * 0.93, Vector3(hw * s, 0, 0) + d0 * r * 0.64, Vector3(hw * s, 0, 0) + d1 * r * 0.64, Vector3(hw * s, 0, 0) + d1 * r * 0.93, Vector3(s, 0, 0))
		# Hubcap on the outside, plain steel-grey disc on the inside.
		kit.color = hub
		kit.tri(Vector3(hw + 0.012, 0, 0), Vector3(hw + 0.004, 0, 0) + d0 * r * 0.64, Vector3(hw + 0.004, 0, 0) + d1 * r * 0.64, Vector3.RIGHT)
		kit.color = Color(0.2, 0.2, 0.21)
		kit.tri(Vector3(-hw, 0, 0), Vector3(-hw, 0, 0) + d0 * r * 0.64, Vector3(-hw, 0, 0) + d1 * r * 0.64, Vector3.LEFT)
		# Spokes painted on the hubcap: every third segment slightly darker.
		if i % 3 == 0:
			kit.color = hub.darkened(0.35)
			kit.tri(Vector3(hw + 0.013, 0, 0) + d0 * r * 0.15, Vector3(hw + 0.013, 0, 0) + d0 * r * 0.58, Vector3(hw + 0.013, 0, 0) + d1 * r * 0.58, Vector3.RIGHT)
	_wheel_mesh = kit.commit(null, paint_material())
	return _wheel_mesh

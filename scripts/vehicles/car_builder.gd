class_name CarBuilder
extends RefCounted
## Builds a car's mesh from a shape in CarModels: a lofted lower body, a
## glasshouse with pillars, lights, bumpers, plates and mirrors, plus
## optional touches (hood scoop, spoiler, racing stripes, a pickup's box).
## One body mesh with two surfaces (paint and glass) and one wheel mesh per
## wheel size (rubber and rim) shared by every car, so a car is ten draw calls. Colours are
## vertex colours, so all cars share the same two materials.
##
## Faces -Z (the front), wheels on the ground at y = 0.

static var _paint_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _rubber_mat: StandardMaterial3D
static var _rim_mat: StandardMaterial3D
static var _wheel_meshes := {}

var shape: Dictionary
var paint: Color
var trim := Color(0.13, 0.13, 0.14)
var glass := Color(0.06, 0.08, 0.1)


func _init(car_shape: Dictionary, body_colour: Color) -> void:
	shape = car_shape
	paint = body_colour


static func paint_material() -> StandardMaterial3D:
	if _paint_mat == null:
		_paint_mat = StandardMaterial3D.new()
		_paint_mat.vertex_color_use_as_albedo = true
		_paint_mat.vertex_color_is_srgb = true
		_paint_mat.roughness = 0.38
		_paint_mat.metallic = 0.2
		_paint_mat.metallic_specular = 0.6
		# A glossy clear coat over the colour, as on real paint (Forward+
		# only; the Compatibility renderer just skips it).
		_paint_mat.clearcoat_enabled = true
		_paint_mat.clearcoat = 0.8
		_paint_mat.clearcoat_roughness = 0.08
	return _paint_mat


static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.vertex_color_use_as_albedo = true
		_glass_mat.vertex_color_is_srgb = true
		_glass_mat.roughness = 0.04
		_glass_mat.metallic = 0.3
		_glass_mat.metallic_specular = 0.9
	return _glass_mat


func make_body() -> ArrayMesh:
	var kits := _kits()
	var mesh := (kits[0] as MeshKit).commit(null, paint_material())
	(kits[1] as MeshKit).commit(mesh, glass_material())
	return mesh


## A car parked along a curb, as one mesh of two surfaces: the body with
## simple wheels built in, and the glass. Build it in white: a MultiMesh
## colours each parked car with its instance colour, so a whole street of
## them draws in two calls.
func make_parked() -> ArrayMesh:
	var kits := _kits()
	var body: MeshKit = kits[0]
	var r := float(shape["wheel_radius"])
	var w := float(shape["wheel_width"])
	for z: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for side: float in [-1.0, 1.0]:
			_simple_wheel(body, Vector3(float(shape["track_half"]) * side, r, z), r, w, side)
	var mesh := body.commit(null, paint_material())
	(kits[1] as MeshKit).commit(mesh, glass_material())
	return mesh


## A plain ten-sided tyre with a grey wheel face on the outside.
func _simple_wheel(kit: MeshKit, c: Vector3, r: float, w: float, side: float) -> void:
	var segs := 10
	var inner := c.x - side * w * 0.5
	var outer := c.x + side * w * 0.5
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		var n := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		kit.color = Color(0.07, 0.07, 0.075)
		kit.quad(Vector3(inner, c.y + p0.y, c.z + p0.x), Vector3(outer, c.y + p0.y, c.z + p0.x),
			Vector3(outer, c.y + p1.y, c.z + p1.x), Vector3(inner, c.y + p1.y, c.z + p1.x), n)
		kit.color = Color(0.5, 0.5, 0.52)
		kit.tri(Vector3(outer, c.y, c.z), Vector3(outer, c.y + p0.y * 0.7, c.z + p0.x * 0.7), Vector3(outer, c.y + p1.y * 0.7, c.z + p1.x * 0.7), Vector3(side, 0, 0))
		kit.color = Color(0.07, 0.07, 0.075)
		kit.quad(Vector3(outer, c.y + p0.y * 0.7, c.z + p0.x * 0.7), Vector3(outer, c.y + p0.y, c.z + p0.x),
			Vector3(outer, c.y + p1.y, c.z + p1.x), Vector3(outer, c.y + p1.y * 0.7, c.z + p1.x * 0.7), Vector3(side, 0, 0))


## The body (paint) and window (glass) kits, before they become a mesh.
func _kits() -> Array:
	var body := MeshKit.new()
	body.use_color = true
	var win := MeshKit.new()
	win.use_color = true
	_lower_body(body)
	_cabin(body, win)
	if shape.has("bed"):
		_bed(body)
	_front_and_back(body)
	_mirrors(body)
	if shape.get("hood_scoop", false):
		_hood_scoop(body)
	if shape.get("spoiler", false):
		_spoiler(body)
	if shape.get("stripes", false):
		_stripes(body)
	return [body, win]


# --- lower body: a lofted shell, nose to tail ------------------------------------------

## Half a cross-section, from the middle of the underside round the right
## side to the middle of the top, as (fraction of half width, fraction of
## height). The sides bulge a little below the middle and tuck in toward
## the top, and the top has a slight crown, so the body reads as pressed
## steel rather than a box. Mirrored for the left side.
const HALF_SECTION := [
	[0.0, 0.0], [0.86, 0.0], [0.95, 0.05], [0.99, 0.17], [1.0, 0.36], [0.995, 0.56],
	[0.975, 0.74], [0.935, 0.87], [0.85, 0.955], [0.64, 0.995], [0.32, 1.012], [0.0, 1.018],
]
const LOFT_STEP := 0.1 ## metres between rings along the body
const ARCH_STEP := 0.04 ## closer over the wheel arches so they come out round
const SEAM := 0.009 ## half the width of a panel gap


static func _section(w: float, y0: float, y1: float) -> PackedVector2Array:
	var h := y1 - y0
	var pts := PackedVector2Array()
	for p: Array in HALF_SECTION:
		pts.append(Vector2(w * float(p[0]), y0 + h * float(p[1])))
	for i in range(HALF_SECTION.size() - 2, 0, -1):
		var p: Array = HALF_SECTION[i]
		pts.append(Vector2(-w * float(p[0]), y0 + h * float(p[1])))
	return pts


## The stations' [half width, bottom, top] at z, on a smooth curve through
## them that never overshoots (so a pickup's step behind the cab stays a step).
func _station_at(z: float) -> Vector3:
	var st: Array = shape["stations"]
	var n := st.size()
	if z <= float(st[0][0]):
		return Vector3(st[0][1], st[0][2], st[0][3])
	for i in range(n - 1):
		var z0 := float(st[i][0])
		var z1 := float(st[i + 1][0])
		if z > z1:
			continue
		var t := (z - z0) / maxf(0.0001, z1 - z0)
		var out := Vector3.ZERO
		for k in 3:
			var p0 := float(st[maxi(i - 1, 0)][k + 1])
			var p1 := float(st[i][k + 1])
			var p2 := float(st[i + 1][k + 1])
			var p3 := float(st[mini(i + 2, n - 1)][k + 1])
			var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			out[k] = clampf(v, minf(p1, p2), maxf(p1, p2))
		return out
	return Vector3(st[n - 1][1], st[n - 1][2], st[n - 1][3])


func _arch_radius() -> float:
	return float(shape["wheel_radius"]) + 0.055


## How high the bottom of the body sits at z: lifted into a round arch over
## each wheel.
func _arch_bottom(z: float, y0: float, y1: float) -> float:
	var wr: float = shape["wheel_radius"]
	var r := _arch_radius()
	for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		var dz := z - az
		if absf(dz) < r:
			y0 = maxf(y0, wr + sqrt(r * r - dz * dz))
	return minf(y0, y1 - 0.13)


## Where the panel gaps fall along the body: [z, true for the sides (doors),
## false for the top (hood and trunk lid)].
func _seams() -> Array:
	var cab: Dictionary = shape["cabin"]
	var st: Array = shape["stations"]
	var r := _arch_radius()
	var fa: float = shape["front_axle"]
	var ra: float = shape["rear_axle"]
	var za: float = cab["za"]
	var zb: float = cab["zb"]
	var zc: float = cab["zc"]
	var zd: float = cab["zd"]
	var doors: int = cab.get("doors", 4)
	var out := []
	var door_front := maxf(fa + r + 0.1, za - 0.02)
	out.append([door_front, true])
	if shape.has("bed"):
		out.append([lerpf(zb, zc, 0.42), true])
		out.append([zd - 0.05, true])
	elif doors == 4:
		out.append([lerpf(zb, zc, 0.42), true])
		out.append([minf(ra - r - 0.06, zd - 0.05), true])
	else:
		out.append([lerpf(zb, zc, 0.78) + 0.05, true])
	out.append([za - 0.05, false])
	out.append([float(st[1][0]) + 0.16, false])
	if not shape.has("bed"):
		out.append([zd + 0.07, false])
	return out


func _lower_body(kit: MeshKit) -> void:
	var st: Array = shape["stations"]
	var z_start := float(st[0][0])
	var z_end := float(st[st.size() - 1][0])
	var seams := _seams()
	var r_arch := _arch_radius()
	# Ring positions along the body: every station, close together over the
	# arches, and a pair either side of every panel gap.
	var zs: Array[float] = []
	var z := z_start
	while z < z_end:
		zs.append(z)
		var near_arch := false
		for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
			if absf(z - az) < r_arch + 0.06:
				near_arch = true
		z += ARCH_STEP if near_arch else LOFT_STEP
	zs.append(z_end)
	for stn: Array in st:
		zs.append(float(stn[0]))
	var seam_at := {}
	for sm: Array in seams:
		var zz: float = sm[0]
		zs.append(zz - SEAM)
		zs.append(zz + SEAM)
		seam_at[snappedf(zz - SEAM, 0.0001)] = sm[1]
	zs.sort()
	var clean: Array[float] = []
	for v in zs:
		if clean.is_empty() or v - clean[clean.size() - 1] > 0.004:
			clean.append(v)
	zs = clean

	var rings: Array[PackedVector3Array] = []
	for zz in zs:
		var sv := _station_at(zz)
		var y0 := _arch_bottom(zz, sv.y, sv.z)
		var sec := _section(sv.x, y0, sv.z)
		var ring := PackedVector3Array()
		for p in sec:
			ring.append(Vector3(p.x, p.y, zz))
		rings.append(ring)
	var n := rings[0].size()
	# Smooth normals from the neighbouring points round and along the body.
	var normals: Array[PackedVector3Array] = []
	for i in rings.size():
		var nr := PackedVector3Array()
		var prev := rings[maxi(i - 1, 0)]
		var next := rings[mini(i + 1, rings.size() - 1)]
		var mid_y := (rings[i][0].y + rings[i][n / 2].y) * 0.5
		for j in n:
			var t_round := rings[i][(j + 1) % n] - rings[i][(j - 1 + n) % n]
			var t_along := next[j] - prev[j]
			var nn := t_round.cross(t_along).normalized()
			var outward := rings[i][j] - Vector3(0.0, mid_y, rings[i][j].z)
			if nn.dot(outward) < 0.0:
				nn = -nn
			# Blend toward the plain outward direction near the ends, where
			# the rings bunch up.
			nr.append(nn if nn.length() > 0.5 else outward.normalized())
		normals.append(nr)
	var half := HALF_SECTION.size()
	for i in range(rings.size() - 1):
		var seam: Variant = seam_at.get(snappedf(zs[i], 0.0001), null)
		for j in n:
			var j1 := (j + 1) % n
			var a := rings[i][j]
			var b := rings[i][j1]
			var c := rings[i + 1][j1]
			var d := rings[i + 1][j]
			# Height fraction of this strip of the section, to pick its colour.
			var fa := _section_frac(j, half)
			var fb := _section_frac(j1, half)
			if fa < 0.01 and fb < 0.01:
				kit.color = trim.darkened(0.5) # underside
			elif minf(fa, fb) < 0.06:
				kit.color = trim # sill
			else:
				kit.color = paint
			if seam != null:
				var side_seam: bool = seam
				var on_side := minf(fa, fb) > 0.12 and maxf(fa, fb) < 0.9
				var on_top := minf(fa, fb) > 0.9
				if (side_seam and on_side) or (not side_seam and on_top):
					kit.color = paint.darkened(0.75)
			var mid := (a + b + c + d) * 0.25
			var face := Vector3(mid.x, mid.y - 0.6, 0.0)
			kit.quad_smooth(a, b, c, d, normals[i][j], normals[i][j1], normals[i + 1][j1], normals[i + 1][j], _face_normal(a, b, c, face))
		# A step in the top (a pickup's cab back) needs a wall to close it.
		var top_a := rings[i][half - 1].y
		var top_b := rings[i + 1][half - 1].y
		if absf(top_a - top_b) > 0.05:
			var hi := rings[i] if top_a > top_b else rings[i + 1]
			var lo := rings[i + 1] if top_a > top_b else rings[i]
			var nz := Vector3.BACK if top_a > top_b else Vector3.FORWARD
			kit.color = paint
			var y_lo := lo[half - 1].y
			for j in range(half - 4, n - half + 4):
				var p0 := hi[j % n]
				var p1 := hi[(j + 1) % n]
				if p0.y < y_lo and p1.y < y_lo:
					continue
				kit.quad(Vector3(p0.x, minf(p0.y, y_lo), p0.z), Vector3(p1.x, minf(p1.y, y_lo), p1.z), p1, p0, nz)
	_cap(kit, rings[0], Vector3.FORWARD)
	_cap(kit, rings[rings.size() - 1], Vector3.BACK)
	_wheel_wells(kit)
	_door_handles(kit, seams)


## Height fraction (0 underside .. 1 top) of point j of a section ring.
static func _section_frac(j: int, half: int) -> float:
	var k := j if j < half else 2 * (half - 1) - j
	return float(HALF_SECTION[k][1])


## Dark liners inside each wheel arch, so you can't see through the car.
func _wheel_wells(kit: MeshKit) -> void:
	kit.color = Color(0.03, 0.03, 0.03)
	var wr: float = shape["wheel_radius"]
	var r := _arch_radius()
	var x: float = float(shape["track_half"]) - float(shape["wheel_width"]) * 0.5 - 0.04
	for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for s: float in [-1.0, 1.0]:
			var c := Vector3(x * s, wr, az)
			for i in 12:
				var a0 := PI * float(i) / 12.0
				var a1 := PI * float(i + 1) / 12.0
				var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
				var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
				kit.quad(Vector3(c.x, 0.15, p0.z), p0, p1, Vector3(c.x, 0.15, p1.z), Vector3(s, 0, 0))
				# The arch's inner roof, from the liner out to the body side.
				var w: float = float(shape["width"]) * 0.5
				kit.quad(p0, p1, Vector3(w * s, p1.y, p1.z), Vector3(w * s, p0.y, p0.z), Vector3(0, -sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5)))


## A small dark pull just ahead of the back edge of each door.
func _door_handles(kit: MeshKit, seams: Array) -> void:
	var cab: Dictionary = shape["cabin"]
	var y := float(cab["belt"]) - 0.09
	var doors: Array[float] = []
	for sm: Array in seams:
		if sm[1]:
			doors.append(float(sm[0]))
	doors.sort()
	kit.color = trim.lightened(0.1)
	for k in range(1, doors.size()):
		var z: float = doors[k] - 0.14
		var sv := _station_at(z)
		var frac := clampf((y - sv.y) / maxf(0.01, sv.z - sv.y), 0.0, 1.0)
		var x := sv.x * (0.985 if frac > 0.7 else 1.0) + 0.006
		for s: float in [-1.0, 1.0]:
			_panel_side(kit, Vector3(x * s, y, z), 0.13, 0.025, Vector3(s, 0, 0))


## A flat rectangle on the side of the car (facing ±X), centred at c.
func _panel_side(kit: MeshKit, c: Vector3, length: float, h: float, n: Vector3) -> void:
	var hl := length * 0.5
	var hh := h * 0.5
	kit.quad(c + Vector3(0, -hh, -hl), c + Vector3(0, -hh, hl), c + Vector3(0, hh, hl), c + Vector3(0, hh, -hl), n)


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


## Top surface height of the lower body at z, near the middle (on the crown).
func _top_at(z: float) -> float:
	var sv := _station_at(z)
	var y0 := _arch_bottom(z, sv.y, sv.z)
	return y0 + (sv.z - y0) * 1.014


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
	# Roof: a gentle crown across, smooth shaded.
	kit.color = paint
	var xs := [-1.0, -0.55, 0.0, 0.55, 1.0]
	for k in range(xs.size() - 1):
		var x0: float = xs[k]
		var x1: float = xs[k + 1]
		var y0 := roof + 0.035 * (1.0 - x0 * x0)
		var y1 := roof + 0.035 * (1.0 - x1 * x1)
		var n0 := Vector3(x0 * 0.35, 1.0, 0.0).normalized()
		var n1 := Vector3(x1 * 0.35, 1.0, 0.0).normalized()
		kit.quad_smooth(Vector3(wr * x0, y0, zb), Vector3(wr * x1, y1, zb), Vector3(wr * x1, y1, zc), Vector3(wr * x0, y0, zc), n0, n1, n1, n0, Vector3.UP)
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
		var z := float(st[1][0]) + 0.05
		var z_end := float(st[st.size() - 2][0])
		while z < z_end:
			var z2 := minf(z + 0.1, z_end)
			var ya := _top_at(z) + 0.006
			var yb := _top_at(z2) + 0.006
			var in_cab := z2 > float(cab["za"]) - 0.01 and z < float(cab["zd"]) + 0.01
			# Only along the flat of the hood and trunk, not down the nose or tail.
			if not in_cab and absf(yb - ya) < 0.035 * (z2 - z) / 0.1:
				kit.quad(Vector3(x0, ya, z), Vector3(x1, ya, z), Vector3(x1, yb, z2), Vector3(x0, yb, z2), Vector3.UP)
			z = z2
		# Roof.
		var ry := float(cab["roof"]) + 0.035 * (1.0 - pow((x0 + x1) * 0.5 / float(cab["wr"]), 2.0)) + 0.006
		kit.quad(Vector3(x0, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zc"])), Vector3(x0, ry, float(cab["zc"])), Vector3.UP)


# --- wheels --------------------------------------------------------------------------------

## A wheel of the given size, axle along X, outer face on +X. Mirror it
## (scale.x = -1) for the left side. Two surfaces: the tyre (matte rubber,
## rounded shoulders and a sidewall) and the rim (five spokes on a dished
## face). Shared by every car with wheels this size.
const TYRE_PROFILE := [
	# [radius fraction, x fraction of half width] from inner bead to outer bead
	[0.66, -0.92], [0.86, -1.0], [0.95, -0.94], [0.995, -0.76], [1.0, -0.3],
	[1.0, 0.3], [0.995, 0.76], [0.95, 0.94], [0.86, 1.0], [0.66, 0.92],
]


static func wheel_mesh(r: float = 0.31, width: float = 0.2) -> ArrayMesh:
	var key := "%.3f/%.3f" % [r, width]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var segs := 24
	var hw := width * 0.5
	var tyre := MeshKit.new()
	tyre.use_color = true
	tyre.color = Color(0.045, 0.045, 0.047)
	var around := func(a: float) -> Vector3: return Vector3(0.0, sin(a), cos(a))
	for i in range(TYRE_PROFILE.size() - 1):
		var p0: Array = TYRE_PROFILE[i]
		var p1: Array = TYRE_PROFILE[i + 1]
		var r0 := float(p0[0]) * r
		var r1 := float(p1[0]) * r
		var x0 := float(p0[1]) * hw
		var x1 := float(p1[1]) * hw
		var n2 := Vector2(r1 - r0, -(x1 - x0)).normalized() # (x, radial) outward
		if n2.y < 0.0:
			n2 = -n2
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var d0: Vector3 = around.call(a0)
			var d1: Vector3 = around.call(a1)
			var n0 := (d0 * n2.y + Vector3.RIGHT * n2.x).normalized()
			var n1 := (d1 * n2.y + Vector3.RIGHT * n2.x).normalized()
			tyre.quad_smooth(Vector3(x0, 0, 0) + d0 * r0, Vector3(x0, 0, 0) + d1 * r0, Vector3(x1, 0, 0) + d1 * r1, Vector3(x1, 0, 0) + d0 * r1,
				n0, n1, n1, n0, ((d0 + d1).normalized() * n2.y + Vector3.RIGHT * n2.x).normalized())
	var rim := MeshKit.new()
	rim.use_color = true
	var metal := Color(0.66, 0.67, 0.68)
	var dark := Color(0.06, 0.06, 0.065)
	var face_x := hw * 0.86
	var rr := r * 0.66
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var d0: Vector3 = around.call(a0)
		var d1: Vector3 = around.call(a1)
		var mid := (d0 + d1).normalized()
		# Rim lip: a bright ring stepping in from the tyre.
		rim.color = metal
		rim.quad(Vector3(face_x, 0, 0) + d0 * rr, Vector3(face_x, 0, 0) + d1 * rr, Vector3(face_x - 0.015, 0, 0) + d1 * rr * 0.88, Vector3(face_x - 0.015, 0, 0) + d0 * rr * 0.88, (Vector3.RIGHT + mid * 0.3).normalized())
		# Between the spokes the face is open to the dark brake drum behind;
		# five spokes each cover a fifth of the circle's middle.
		var spoke := fmod(float(k) + 0.5, float(segs) / 5.0) < float(segs) / 5.0 * 0.4
		rim.color = metal.darkened(0.1) if spoke else dark
		var depth := 0.0 if spoke else 0.05
		rim.quad(Vector3(face_x - 0.015 - depth, 0, 0) + d0 * rr * 0.88, Vector3(face_x - 0.015 - depth, 0, 0) + d1 * rr * 0.88,
			Vector3(face_x - 0.005 - depth, 0, 0) + d1 * rr * 0.3, Vector3(face_x - 0.005 - depth, 0, 0) + d0 * rr * 0.3, Vector3.RIGHT)
		# Hub.
		rim.color = metal.lightened(0.1)
		rim.tri(Vector3(face_x + 0.01, 0, 0), Vector3(face_x - 0.005, 0, 0) + d0 * rr * 0.3, Vector3(face_x - 0.005, 0, 0) + d1 * rr * 0.3, Vector3.RIGHT)
		# Back of the wheel, closed off.
		rim.color = dark
		rim.tri(Vector3(-hw * 0.9, 0, 0), Vector3(-hw * 0.9, 0, 0) + d0 * rr, Vector3(-hw * 0.9, 0, 0) + d1 * rr, Vector3.LEFT)
	var mesh := tyre.commit(null, rubber_material())
	rim.commit(mesh, rim_material())
	_wheel_meshes[key] = mesh
	return mesh


static func rubber_material() -> StandardMaterial3D:
	if _rubber_mat == null:
		_rubber_mat = StandardMaterial3D.new()
		_rubber_mat.vertex_color_use_as_albedo = true
		_rubber_mat.vertex_color_is_srgb = true
		_rubber_mat.roughness = 0.88
		_rubber_mat.metallic_specular = 0.3
	return _rubber_mat


static func rim_material() -> StandardMaterial3D:
	if _rim_mat == null:
		_rim_mat = StandardMaterial3D.new()
		_rim_mat.vertex_color_use_as_albedo = true
		_rim_mat.vertex_color_is_srgb = true
		_rim_mat.roughness = 0.28
		_rim_mat.metallic = 0.85
	return _rim_mat

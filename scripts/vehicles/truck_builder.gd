class_name TruckBuilder
extends RefCounted
## Builds the working vehicles' meshes (TruckModels "look"): a tractor unit,
## a flatbed trailer, a rollback tow truck, a forklift. Like the cars they're
## built as detailed scale models, all from code: the cabs are hollow shells
## with real window openings and see-through glass, and inside there's a
## full interior to match the cars (a dash with a bank of gauges and
## switches, air-ride seats, door cards, headliner, visors, pedals, a gear
## lever). Outside: chrome grilles, bumpers and tanks, lamp units, curved
## fenders, mirrors on their arms, steps and grab handles, axles, air bags,
## driveshafts, air lines, mud flaps, landing gear, stake pockets and strap
## winches, the forklift's mast channels, chains and cylinders.
##
## The meshes use the cars' shared materials (CarBuilder.material), one
## surface each: paint (vertex colour is the actual colour, on a clear-coated
## paint), gloss (lamps, poly fenders), rough (plastics, rubber, cloth),
## satin (vinyl seats and dash), metal (chrome), steel (frames, plate,
## galvanised parts) and glass.
##
## Working parts (a tow truck's deck, a forklift's forks and mast, a
## trailer's landing legs) are separate meshes, built where they sit at
## rest; Car moves them (Car.set_part_transform).
##
## Faces -Z (the front), wheels on the ground at y = 0, driver on the left.

const DARK := Color(0.07, 0.07, 0.075)
const CHROME := Color(0.9, 0.9, 0.92)
const STEEL := Color(0.4, 0.41, 0.42)
const GALV := Color(0.6, 0.61, 0.6)
const RUBBER := Color(0.035, 0.035, 0.038)
const GLASS := Color(0.1, 0.13, 0.15, 0.34)
const MIRROR := Color(0.72, 0.76, 0.8)
const LAMP := Color(0.95, 0.95, 0.9)
const AMBER := Color(1.0, 0.52, 0.06)
const RED := Color(0.72, 0.04, 0.03)
const SURFACES := ["paint", "gloss", "rough", "satin", "metal", "steel", "glass"]

static var _materials := {}

var shape: Dictionary
var paint: Color

var _kits := {} # part name ("" for the body) -> {surface: MeshKit}
var _part := ""
## While true, the body's pieces go in the near-only detail mesh (ModelLod):
## the interior and small parts nobody sees from further off.
var _detail := false
const DETAIL := "~detail"
# The cab being built (see _cab).
var _hw := 1.2
var _cz0 := 0.0
var _cz1 := 0.0
var _y0 := 0.8
var _roof := 2.6
var _rake := 0.3
var _floor := 1.0
var _belt := 1.8
var _wb := 1.9
var _wt := 2.5
var _zb := 0.0
## The rear lamps' lenses, for lighting them (LampGlow).
var lamps: Array = []


func _init(truck_shape: Dictionary, body_colour: Color) -> void:
	shape = truck_shape
	paint = body_colour


## {"body": ArrayMesh, "detail": ArrayMesh (near only), "parts": {name: ArrayMesh}}
func build() -> Dictionary:
	match str(shape.get("look", "")):
		"tractor":
			_tractor()
		"flat_trailer":
			_flat_trailer()
		"rollback":
			_rollback()
		"forklift":
			_forklift()
	var parts := {}
	for name: String in _kits:
		if name != "" and name != DETAIL:
			parts[name] = _commit(name)
	var glow := {}
	for kind: String in [LampGlow.BRAKE, LampGlow.REVERSE]:
		var m := LampGlow.build(lamps, kind)
		if m != null:
			glow[kind] = m
	return {"body": _commit(""), "detail": _commit(DETAIL), "parts": parts, "lamps": glow}


func _commit(part: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var kits: Dictionary = _kits.get(part, {})
	for s: String in SURFACES:
		if kits.has(s) and not (kits[s] as MeshKit).is_empty():
			(kits[s] as MeshKit).commit_indexed(mesh, surface_material(s))
	return ModelLod.finish(mesh)


## The material for one of SURFACES.
static func surface_material(s: String) -> Material:
	match s:
		"paint":
			return CarBuilder.paint_material(Color.WHITE)
		"steel":
			if not _materials.has("steel"):
				var m := StandardMaterial3D.new()
				m.vertex_color_use_as_albedo = true
				m.vertex_color_is_srgb = true
				m.metallic = 0.65
				m.roughness = 0.5
				_materials["steel"] = m
			return _materials["steel"]
	return CarBuilder.material(s)


func _k(s: String) -> MeshKit:
	var key := DETAIL if _detail and _part == "" else _part
	if not _kits.has(key):
		_kits[key] = {}
	var kits: Dictionary = _kits[key]
	if not kits.has(s):
		var k := MeshKit.new()
		k.use_color = true
		kits[s] = k
	return kits[s]


# --- building blocks (static, also used by Cargo) -------------------------------------------

## A box: centre, full size.
static func box(kit: MeshKit, c: Vector3, s: Vector3, colour: Color) -> void:
	var h := s * 0.5
	block(kit, [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	], colour)


## Any eight-cornered block: the front face (bottom-left, bottom-right,
## top-right, top-left, seen from outside the front) then the back face in
## the same order. Lets a hood slope or a windshield lean back.
static func block(kit: MeshKit, p: Array, colour: Color) -> void:
	kit.color = colour
	var centre := Vector3.ZERO
	for v: Vector3 in p:
		centre += v
	centre /= 8.0
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var n := (c - a).cross(d - b)
		if n.length_squared() < 1e-10:
			n = (b - a).cross(d - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot((a + b + c + d) * 0.25 - centre) < 0.0:
			n = -n
		kit.quad(a, b, c, d, n)


## A block between two x positions with its side profile given as four
## (z, y) corners: bottom-front, bottom-back, top-back, top-front.
static func profile(kit: MeshKit, x0: float, x1: float, bf: Vector2, bb: Vector2, tb: Vector2, tf: Vector2, colour: Color, top_inset := 0.0) -> void:
	block(kit, [
		Vector3(x0, bf.y, bf.x), Vector3(x1, bf.y, bf.x), Vector3(x1 - top_inset, tf.y, tf.x), Vector3(x0 + top_inset, tf.y, tf.x),
		Vector3(x0, bb.y, bb.x), Vector3(x1, bb.y, bb.x), Vector3(x1 - top_inset, tb.y, tb.x), Vector3(x0 + top_inset, tb.y, tb.x),
	], colour)


## A closed cylinder from a to b.
static func cylinder(kit: MeshKit, a: Vector3, b: Vector3, r: float, colour: Color, segs := 12) -> void:
	cone(kit, a, b, r, r, colour, segs)


## A closed tapering cylinder from a (radius r0) to b (radius r1).
static func cone(kit: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, colour: Color, segs := 12) -> void:
	kit.color = colour
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var slope := (r0 - r1) / maxf(0.0001, a.distance_to(b))
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var n0 := (d0 + axis * slope).normalized()
		var n1 := (d1 + axis * slope).normalized()
		kit.quad_smooth(a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, n0, n1, n1, n0, (d0 + d1).normalized())
		if r0 > 0.0:
			kit.tri(a, a + d0 * r0, a + d1 * r0, -axis)
		if r1 > 0.0:
			kit.tri(b, b + d1 * r1, b + d0 * r1, axis)


# --- shorthand on this builder's kits ---------------------------------------------------------

func _box(s: String, c: Vector3, size: Vector3, col: Color) -> void:
	box(_k(s), c, size, col)


## A box with bevelled edges: centre, HALF size, bevel.
func _bev(s: String, c: Vector3, half: Vector3, b: float, col: Color, basis := Basis()) -> void:
	var k := _k(s)
	k.color = col
	CarBuilder._bbox(k, c, half, b, basis)


func _blk(s: String, p: Array, col: Color) -> void:
	block(_k(s), p, col)


func _prof(s: String, x0: float, x1: float, bf: Vector2, bb: Vector2, tb: Vector2, tf: Vector2, col: Color, inset := 0.0) -> void:
	profile(_k(s), minf(x0, x1), maxf(x0, x1), bf, bb, tb, tf, col, inset)


func _cyl(s: String, a: Vector3, b: Vector3, r: float, col: Color, segs := 12) -> void:
	cone(_k(s), a, b, r, r, col, segs)


func _cone(s: String, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, segs := 12) -> void:
	cone(_k(s), a, b, r0, r1, col, segs)


## An open tube (no end caps) from a to b.
func _tube(s: String, a: Vector3, b: Vector3, r: float, col: Color, segs := 8) -> void:
	var k := _k(s)
	k.color = col
	CarBuilder._tube(k, a, b, r, segs, false)


## A bent rod through a list of points, with a ball at each bend.
func _rod(s: String, pts: Array, r: float, col: Color, segs := 8) -> void:
	for i in range(pts.size() - 1):
		_tube(s, pts[i], pts[i + 1], r, col, segs)
	for i in range(1, pts.size() - 1):
		_bev(s, pts[i], Vector3(r, r, r), r * 0.95, col)


func _disc(s: String, c: Vector3, r: float, n: Vector3, col: Color, segs := 16) -> void:
	var k := _k(s)
	k.color = col
	CarBuilder._disc(k, c, r, n.normalized(), segs)


func _ring(s: String, c: Vector3, r0: float, r1: float, n: Vector3, col: Color, segs := 16) -> void:
	var k := _k(s)
	k.color = col
	CarBuilder._ring(k, c, r0, r1, n.normalized(), segs)


func _quad(s: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	var k := _k(s)
	k.color = col
	k.quad(a, b, c, d, n)


## A flat rectangle facing n (±x, ±y or ±z), centred at c: w across, h up
## (or along z for a face pointing up or down).
func _plate(s: String, c: Vector3, w: float, h: float, n: Vector3, col: Color) -> void:
	var u: Vector3
	var v: Vector3
	if absf(n.z) > 0.5:
		u = Vector3.RIGHT
		v = Vector3.UP
	elif absf(n.x) > 0.5:
		u = Vector3.BACK
		v = Vector3.UP
	else:
		u = Vector3.RIGHT
		v = Vector3.BACK
	_quad(s, c - u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 + v * h * 0.5, c - u * w * 0.5 + v * h * 0.5, n, col)


## A curved band over a wheel (a fender): from angle a0 to a1 round the
## axle at (z, cy), where 0 is level in front, PI/2 straight up and PI level
## behind; r0 is the underside, r1 the top; between x0 and x1.
func _arch(s: String, z: float, cy: float, r0: float, r1: float, x0: float, x1: float, a0: float, a1: float, col: Color, segs := 12) -> void:
	var k := _k(s)
	k.color = col
	var P := func(r: float, t: float, x: float) -> Vector3:
		return Vector3(x, cy + sin(t) * r, z - cos(t) * r)
	for i in segs:
		var ta := lerpf(a0, a1, float(i) / segs)
		var tb := lerpf(a0, a1, float(i + 1) / segs)
		var na := Vector3(0, sin(ta), -cos(ta))
		var nb := Vector3(0, sin(tb), -cos(tb))
		k.quad_smooth(P.call(r1, ta, x0), P.call(r1, ta, x1), P.call(r1, tb, x1), P.call(r1, tb, x0), na, na, nb, nb, (na + nb).normalized())
		k.quad_smooth(P.call(r0, ta, x0), P.call(r0, ta, x1), P.call(r0, tb, x1), P.call(r0, tb, x0), -na, -na, -nb, -nb, -(na + nb).normalized())
		for x: float in [x0, x1]:
			var n := Vector3(signf(x - (x0 + x1) * 0.5), 0, 0)
			k.quad(P.call(r0, ta, x), P.call(r1, ta, x), P.call(r1, tb, x), P.call(r0, tb, x), n)
	for t: float in [a0, a1]:
		var n := Vector3(0, -cos(t), -sin(t)) * (1.0 if t == a0 else -1.0)
		k.quad(P.call(r0, t, x0), P.call(r1, t, x0), P.call(r1, t, x1), P.call(r0, t, x1), n)


## A lamp: a bezel (chrome or black) with a lens on its face, facing n.
func _lamp(c: Vector3, w: float, h: float, n: Vector3, col: Color, bezel := CHROME, round := false) -> void:
	var bs := "metal" if bezel == CHROME else "rough"
	if n.z > 0.5 and not _detail:
		# A lamp facing back: brake (red) or reversing (white), to light up.
		LampGlow.note(lamps, LampGlow.kind_of(col), LampGlow.disc(c + n * 0.006, w * 0.5, n) if round else LampGlow.rect(c + n * 0.009, w, h, n), n)
	if round:
		_ring(bs, c, w * 0.5, w * 0.5 + 0.015, n, bezel, 18)
		_disc("gloss", c + n * 0.004, w * 0.5, n, col, 18)
		_ring("gloss", c + n * 0.006, w * 0.18, w * 0.2, n, col.lightened(0.3), 14)
		return
	var half := Vector3(w * 0.5 + 0.015, h * 0.5 + 0.015, 0.02)
	if absf(n.x) > 0.5:
		half = Vector3(0.02, h * 0.5 + 0.015, w * 0.5 + 0.015)
	elif absf(n.y) > 0.5:
		half = Vector3(w * 0.5 + 0.015, 0.02, h * 0.5 + 0.015)
	_bev(bs, c - n * 0.012, half, 0.008, bezel)
	_plate("gloss", c + n * 0.009, w, h, n, col)


## Diamond-plate tread: a steel plate with a pattern of ribs on it (flat
## quads, in the near-only detail).
func _tread(c: Vector3, w: float, d: float, col := GALV) -> void:
	_box("steel", c, Vector3(w, 0.012, d), col)
	_diamonds(c + Vector3(0, 0.0065, 0), Vector3.RIGHT * w, Vector3.BACK * d, Vector3.UP, col.lightened(0.12))


## The ribs of diamond plate on a face: centre c, edges u and v (full
## length), facing n. Two triangles a rib, near-only.
func _diamonds(c: Vector3, u: Vector3, v: Vector3, n: Vector3, col: Color) -> void:
	var was := _detail
	_detail = true
	var k := _k("steel")
	k.color = col
	var nu := maxi(1, int(u.length() / 0.05))
	var nv := maxi(1, int(v.length() / 0.05))
	var du := u.normalized()
	var dv := v.normalized()
	for i in nu:
		for j in nv:
			var p := c + u * ((i + 0.5) / nu - 0.5) + v * ((j + 0.5) / nv - 0.5) + n * 0.001
			var a := 0.6 if (i + j) % 2 == 0 else -0.6
			var along := du * cos(a) + dv * sin(a)
			var across := du * -sin(a) + dv * cos(a)
			k.quad(p - along * 0.012 - across * 0.004, p + along * 0.012 - across * 0.004, p + along * 0.012 + across * 0.004, p - along * 0.012 + across * 0.004, n)
	_detail = was


# --- a cab: shared by the tractor and the tow truck ------------------------------------------

## The front face of the cab, leaning back by `rake` between the cab's
## bottom and its roof: its z at height y.
func _zf(y: float) -> float:
	return _cz0 + _rake * (y - _y0) / (_roof - _y0)


## A hollow cab with real window openings, glass, doors, steps, mirrors and
## a full interior. c: hw (half width), cz0/cz1 (front and back at the
## bottom), y0 (bottom), roof, rake, floor (the floor's top), belt.
func _cab(c: Dictionary) -> void:
	_hw = c["hw"]
	_cz0 = c["cz0"]
	_cz1 = c["cz1"]
	_y0 = c["y0"]
	_roof = c["roof"]
	_rake = c["rake"]
	_floor = c["floor"]
	_belt = c["belt"]
	_wb = _belt + 0.08
	_wt = _roof - 0.13
	_zb = lerpf(_cz0, _cz1, float(c.get("door", 0.6)))
	var hw := _hw
	var t := 0.05
	var top := _roof - 0.07 # the underside of the roof
	var pz := 0.15 # how deep the A-pillar is, front to back
	# The lower front (the cowl, behind the hood).
	_blk("paint", [
		Vector3(-hw, _y0, _zf(_y0)), Vector3(hw, _y0, _zf(_y0)), Vector3(hw, _wb, _zf(_wb)), Vector3(-hw, _wb, _zf(_wb)),
		Vector3(-hw, _y0, _zf(_y0) + t), Vector3(hw, _y0, _zf(_y0) + t), Vector3(hw, _wb, _zf(_wb) + t), Vector3(-hw, _wb, _zf(_wb) + t),
	], paint)
	# A-pillars, the post between the two windshield panes and the header.
	for s: float in [-1.0, 1.0]:
		var xa := (hw - 0.09) * s
		var xb := hw * s
		_blk("paint", [
			Vector3(xa, _wb, _zf(_wb)), Vector3(xb, _wb, _zf(_wb)), Vector3(xb, _wt, _zf(_wt)), Vector3(xa, _wt, _zf(_wt)),
			Vector3(xa, _wb, _zf(_wb) + t), Vector3(xb, _wb, _zf(_wb) + pz), Vector3(xb, _wt, _zf(_wt) + pz), Vector3(xa, _wt, _zf(_wt) + t),
		], paint)
	_blk("paint", [
		Vector3(-0.03, _wb, _zf(_wb)), Vector3(0.03, _wb, _zf(_wb)), Vector3(0.03, _wt, _zf(_wt)), Vector3(-0.03, _wt, _zf(_wt)),
		Vector3(-0.03, _wb, _zf(_wb) + t), Vector3(0.03, _wb, _zf(_wb) + t), Vector3(0.03, _wt, _zf(_wt) + t), Vector3(-0.03, _wt, _zf(_wt) + t),
	], paint)
	_blk("paint", [
		Vector3(-hw, _wt, _zf(_wt)), Vector3(hw, _wt, _zf(_wt)), Vector3(hw, top, _zf(top)), Vector3(-hw, top, _zf(top)),
		Vector3(-hw, _wt, _zf(_wt) + 0.1), Vector3(hw, _wt, _zf(_wt) + 0.1), Vector3(hw, top, _zf(top) + 0.1), Vector3(-hw, top, _zf(top) + 0.1),
	], paint)
	# The roof, its edges rounded over.
	_prof("paint", -hw, hw, Vector2(_zf(top), top), Vector2(_cz1, top), Vector2(_cz1 - 0.03, _roof), Vector2(_zf(_roof) + 0.03, _roof), paint, 0.05)
	# Sides: the lower panel, the window frame behind the A-pillar, the
	# strip above the window and the panel behind the door.
	for s: float in [-1.0, 1.0]:
		var xo := hw * s
		var xi := (hw - t) * s
		_prof("paint", xi, xo, Vector2(_zf(_y0), _y0), Vector2(_cz1, _y0), Vector2(_cz1, _wb), Vector2(_zf(_wb), _wb), paint)
		_prof("paint", xi, xo, Vector2(_zf(_wt) + pz, _wt), Vector2(_cz1, _wt), Vector2(_cz1, top), Vector2(_zf(top) + pz, top), paint)
		_prof("paint", xi, xo, Vector2(_zb, _wb), Vector2(_cz1, _wb), Vector2(_cz1, _wt), Vector2(_zb, _wt), paint)
	# The back wall round its window.
	var bw := hw * 0.55
	var bb := _wb + 0.06
	var bt := _wt - 0.05
	_box("paint", Vector3(0, (_y0 + bb) * 0.5, _cz1 - t * 0.5), Vector3(hw * 2.0, bb - _y0, t), paint)
	_box("paint", Vector3(0, (bt + top) * 0.5, _cz1 - t * 0.5), Vector3(hw * 2.0, top - bt, t), paint)
	for s: float in [-1.0, 1.0]:
		_box("paint", Vector3((hw + bw) * 0.5 * s, (bb + bt) * 0.5, _cz1 - t * 0.5), Vector3(hw - bw, bt - bb, t), paint)
	# Floor.
	_box("rough", Vector3(0, _floor - 0.04, (_zf(_floor) + _cz1) * 0.5), Vector3(hw * 2.0 - 0.1, 0.08, _cz1 - _zf(_floor) - 0.1), DARK)
	# Glass: the two windshield panes, the side windows and the back window,
	# set in black rubber.
	for s: float in [-1.0, 1.0]:
		var xa := 0.03 * s
		var xb := (hw - 0.09) * s
		var g := 0.025
		_quad("glass", Vector3(xa, _wb, _zf(_wb) + g), Vector3(xb, _wb, _zf(_wb) + g), Vector3(xb, _wt, _zf(_wt) + g), Vector3(xa, _wt, _zf(_wt) + g), Vector3(0, _rake, -(_roof - _y0)).normalized(), GLASS)
		for y: float in [_wb + 0.012, _wt - 0.012]:
			_box("rough", Vector3((xa + xb) * 0.5, y, _zf(y) - 0.004), Vector3(absf(xb - xa), 0.025, 0.012), RUBBER)
		var x := (hw - t * 0.5) * s
		_quad("glass", Vector3(x, _wb, _zf(_wb) + pz), Vector3(x, _wb, _zb), Vector3(x, _wt, _zb), Vector3(x, _wt, _zf(_wt) + pz), Vector3(s, 0, 0), GLASS)
		_box("rough", Vector3(hw * s, _wb + 0.008, (_zf(_wb) + pz + _zb) * 0.5), Vector3(0.012, 0.018, _zb - _zf(_wb) - pz), RUBBER)
	_quad("glass", Vector3(-bw, bb, _cz1 - t * 0.5), Vector3(bw, bb, _cz1 - t * 0.5), Vector3(bw, bt, _cz1 - t * 0.5), Vector3(-bw, bt, _cz1 - t * 0.5), Vector3.BACK, GLASS)
	_cab_outside(c)
	_detail = true
	_cab_interior(c)
	_detail = false


## The cab's outside details: door seams and handles, grab handles, steps,
## mirrors, marker lamps, a visor and wipers.
func _cab_outside(c: Dictionary) -> void:
	var hw := _hw
	var seam := paint.darkened(0.5)
	var zd0 := _zf(_wb) + 0.04
	var zd1 := _zb + 0.02
	for s: float in [-1.0, 1.0]:
		var x := (hw + 0.002) * s
		var n := Vector3(s, 0, 0)
		_detail = true
		# The door's outline.
		_box("paint", Vector3(x, (_y0 + 0.06 + _wt + 0.05) * 0.5, zd1), Vector3(0.006, _wt + 0.05 - _y0 - 0.06, 0.008), seam)
		_box("paint", Vector3(x, (_y0 + 0.06 + _wb) * 0.5, zd0), Vector3(0.006, _wb - _y0 - 0.06, 0.008), seam)
		_box("paint", Vector3(x, _y0 + 0.06, (zd0 + zd1) * 0.5), Vector3(0.006, 0.008, zd1 - zd0), seam)
		_box("paint", Vector3(x, _wt + 0.05, (_zf(_wt) + 0.15 + zd1) * 0.5), Vector3(0.006, 0.008, zd1 - _zf(_wt) - 0.15), seam)
		# Handle, lock and a chrome trim strip under the window.
		_bev("metal", Vector3(x + 0.012 * s, _wb - 0.16, zd1 - 0.2), Vector3(0.012, 0.025, 0.09), 0.01, CHROME)
		_disc("metal", Vector3(x + 0.004 * s, _wb - 0.16, zd1 - 0.06), 0.014, n, CHROME, 10)
		_box("metal", Vector3(x + 0.004 * s, _wb - 0.01, (zd0 + zd1) * 0.5), Vector3(0.008, 0.018, zd1 - zd0 - 0.04), CHROME)
		_detail = false
		# Grab handles: one on the A-pillar, one behind the door.
		var gx := (hw + 0.05) * s
		_rod("metal", [Vector3(hw * s, _y0 + 0.35, zd1 + 0.12), Vector3(gx, _y0 + 0.35, zd1 + 0.12), Vector3(gx, _wb + 0.2, zd1 + 0.12), Vector3(hw * s, _wb + 0.2, zd1 + 0.12)], 0.016, CHROME)
		_rod("metal", [Vector3(hw * s, _wb + 0.05, _zf(_wb + 0.05) + 0.1), Vector3(gx, _wb + 0.05, _zf(_wb + 0.05) + 0.1), Vector3(gx, _wt - 0.1, _zf(_wt - 0.1) + 0.1), Vector3(hw * s, _wt - 0.1, _zf(_wt - 0.1) + 0.1)], 0.014, CHROME)
		# Steps up to the door, on brackets off the cab.
		var sz := (zd0 + zd1) * 0.5
		var steps: Array = c.get("steps", [0.45])
		for sy: float in steps:
			var sx := (hw - 0.12) * s
			_tread(Vector3(sx, sy, sz), 0.26, 0.42)
			_box("steel", Vector3(sx + 0.12 * s, (sy + _y0) * 0.5, sz), Vector3(0.025, _y0 - sy, 0.4), DARK)
		_box("rough", Vector3(x, _y0 + 0.02, (_zf(_y0) + _cz1) * 0.5), Vector3(0.02, 0.05, _cz1 - _zf(_y0)), DARK)
		# West-coast mirrors: two chrome arms off the door to a tall head,
		# and a round convex mirror under it.
		var mz := _zf(_wb) + 0.06
		var head := Vector3((hw + 0.33) * s, _wb + 0.32, mz - 0.02)
		_rod("metal", [Vector3(hw * s, _wb + 0.02, mz), Vector3((hw + 0.2) * s, _wb + 0.02, mz), Vector3(head.x, _wb + 0.08, mz)], 0.013, CHROME)
		_rod("metal", [Vector3(hw * s, _wt - 0.05, _zf(_wt) + 0.1), Vector3((hw + 0.2) * s, _wt - 0.05, mz), Vector3(head.x, _wt - 0.05, mz)], 0.013, CHROME)
		_bev("rough", head, Vector3(0.04, 0.24, 0.09), 0.02, RUBBER)
		_plate("metal", head + Vector3(0, 0, 0.0905), 0.07, 0.44, Vector3.BACK, MIRROR)
		_rod("metal", [Vector3(head.x, _wb + 0.06, mz), Vector3(head.x, _wb - 0.05, mz + 0.02)], 0.01, CHROME)
		_cone("rough", Vector3(head.x, _wb - 0.09, mz - 0.01), Vector3(head.x, _wb - 0.09, mz + 0.03), 0.04, 0.065, RUBBER, 14)
		_disc("metal", Vector3(head.x, _wb - 0.09, mz + 0.031), 0.058, Vector3.BACK, MIRROR, 14)
	# Wipers, parked along the bottom of the windshield.
	_detail = true
	for s: float in [-1.0, 1.0]:
		var a := Vector3((0.15 + (hw - 0.15) * 0.15) * s - 0.25, _wb + 0.03, _zf(_wb + 0.03) - 0.015)
		var b := a + Vector3(hw * 0.7, 0.03, _zf(_wb + 0.06) - _zf(_wb + 0.03))
		_tube("rough", a, b, 0.007, RUBBER, 5)
		_box("rough", (a + b) * 0.5 + Vector3(0, 0.012, -0.004), Vector3(hw * 0.72, 0.012, 0.01), RUBBER)
	_detail = false
	# Marker lamps along the front of the roof.
	for i in 5:
		var mx := (float(i) - 2.0) * 0.3
		_bev("gloss", Vector3(mx, _roof + 0.03, _zf(_roof) + 0.12), Vector3(0.05, 0.03, 0.035), 0.02, AMBER)
	if c.get("visor", false):
		# A sun visor over the windshield on brackets.
		var vz := _zf(_roof) - 0.1
		_blk("paint", [
			Vector3(-hw + 0.02, _roof - 0.05, vz - 0.24), Vector3(hw - 0.02, _roof - 0.05, vz - 0.24), Vector3(hw - 0.02, _roof - 0.02, vz - 0.24), Vector3(-hw + 0.02, _roof - 0.02, vz - 0.24),
			Vector3(-hw + 0.02, _roof - 0.02, vz + 0.12), Vector3(hw - 0.02, _roof - 0.02, vz + 0.12), Vector3(hw - 0.02, _roof + 0.04, vz + 0.12), Vector3(-hw + 0.02, _roof + 0.04, vz + 0.12),
		], paint.darkened(0.15))


## The cab's interior: dash with gauges and switches, seats, door cards,
## headliner, visors, pedals, the gear lever. Sized from the driver's seat.
func _cab_interior(c: Dictionary) -> void:
	var sp: Array = shape["seat"]
	var sx := float(sp[0])
	var sy := float(sp[1])
	var sz := float(sp[2])
	var iw := _hw - 0.06
	var fl := _floor
	var trim: Color = Color.html(str(c.get("trim", "#3b3d40")))
	var dash: Color = Color.html(str(c.get("dash", "#1e1f21")))
	var seat_col: Color = Color.html(str(c.get("seat", "#2b2b2e")))
	var cloth: Color = Color.html(str(c.get("cloth", "#4a4d52")))
	var head_col := Color(0.62, 0.6, 0.56)
	var top := _roof - 0.07
	var zfw := _zf(_wb) + 0.05 # just behind the windshield's foot
	# The dash: a padded top under the windshield, then a face that leans
	# toward the driver, wrapping round in front of them.
	var dt := _wb - 0.02 # dash top
	var dz := clampf(sz - 0.66, zfw + 0.22, sz - 0.5) # the dash's face
	var db := fl + 0.42 # where the face tucks back to the firewall
	_prof("satin", -iw, iw, Vector2(_zf(fl) + 0.06, db), Vector2(dz + 0.02, db), Vector2(dz, dt - 0.06), Vector2(zfw, dt), dash)
	_prof("satin", -iw, iw, Vector2(zfw, dt - 0.06), Vector2(dz, dt - 0.06), Vector2(dz - 0.03, dt), Vector2(zfw, dt), dash.lightened(0.04))
	# The cluster in front of the driver: a hooded black panel with two big
	# dials (speedo and tach) and a row of small ones (oil, water, air
	# pressure front and rear, fuel, volts).
	var face_n := Vector3(0, 0.25, 1).normalized()
	var cl := Vector3(sx, dt - 0.115, dz + 0.012)
	_bev("satin", Vector3(sx, dt + 0.008, dz - 0.03), Vector3(0.3, 0.02, 0.06), 0.018, dash.darkened(0.2))
	_plate("gloss", cl, 0.56, 0.2, Vector3.BACK, Color(0.02, 0.02, 0.025))
	for gx: float in [-0.12, 0.12]:
		_gauge(cl + Vector3(gx, 0.02, 0.004), 0.065, 0.4 if gx < 0.0 else -0.3)
	for i in 6:
		var gx2 := (float(i) - 2.5) * 0.085
		_gauge(cl + Vector3(gx2, -0.075, 0.004), 0.028, 0.3 * float(i % 3) - 0.3)
	# Warning lights across the top of the cluster.
	for i in 8:
		var lc: Color = [Color(0.9, 0.15, 0.1), AMBER, Color(0.2, 0.8, 0.3), Color(0.2, 0.45, 1.0)][i % 4]
		_plate("gloss", cl + Vector3(-0.21 + i * 0.06, 0.085, 0.005), 0.022, 0.012, Vector3.BACK, lc.darkened(0.45))
	# The centre panel: rows of rocker switches, the radio and a CB, vents,
	# and the air brake valves (the yellow diamond is the park brake, the red
	# octagon the trailer's).
	var cx := sx + 0.5 if absf(sx) > 0.3 else 0.35
	cx = minf(cx, iw - 0.25)
	var cp := Vector3(cx, dt - 0.16, dz + 0.012)
	_plate("gloss", cp, 0.36, 0.26, Vector3.BACK, Color(0.03, 0.03, 0.035))
	for row in 2:
		for i in 6:
			var swc := cp + Vector3(-0.15 + i * 0.06, 0.085 - row * 0.05, 0.006)
			_bev("rough", swc, Vector3(0.018, 0.012, 0.006), 0.004, RUBBER)
			_plate("gloss", swc + Vector3(0, 0.006, 0.007), 0.026, 0.005, Vector3.BACK, [AMBER, Color(0.3, 0.8, 0.4), Color(0.9, 0.9, 0.85)][(i + row) % 3])
	# Radio with a display and knobs.
	_bev("gloss", cp + Vector3(0, -0.035, 0.008), Vector3(0.12, 0.03, 0.008), 0.004, Color(0.02, 0.02, 0.022))
	_plate("gloss", cp + Vector3(0, -0.03, 0.017), 0.1, 0.022, Vector3.BACK, Color(0.15, 0.5, 0.6))
	for kx: float in [-0.1, 0.1]:
		_cyl("metal", cp + Vector3(kx, -0.035, 0.012), cp + Vector3(kx, -0.035, 0.026), 0.012, Color(0.7, 0.7, 0.72), 10)
	# The two air valves.
	var vb := cp + Vector3(-0.08, -0.1, 0.01)
	_cyl("metal", vb, vb + Vector3(0, 0, 0.04), 0.008, CHROME, 6)
	_bev("gloss", vb + Vector3(0, 0, 0.05), Vector3(0.026, 0.026, 0.012), 0.004, Color(0.95, 0.78, 0.1), Basis(Vector3.BACK, PI / 4.0))
	var vr := vb + Vector3(0.09, 0, 0)
	_cyl("metal", vr, vr + Vector3(0, 0, 0.04), 0.008, CHROME, 6)
	_cyl("gloss", vr + Vector3(0, 0, 0.04), vr + Vector3(0, 0, 0.058), 0.026, RED, 8)
	# Vents: at each end of the dash and either side of the centre panel.
	for vx: float in [-iw + 0.12, iw - 0.12, cx - 0.25, cx + 0.25]:
		if absf(vx - sx) < 0.3:
			continue
		var vc := Vector3(vx, dt - 0.09, dz + 0.012)
		_bev("metal", vc, Vector3(0.06, 0.035, 0.004), 0.003, Color(0.55, 0.56, 0.58))
		_plate("rough", vc + Vector3(0, 0, 0.005), 0.1, 0.055, Vector3.BACK, Color(0.02, 0.02, 0.022))
		for i in 4:
			_plate("rough", vc + Vector3(0, -0.02 + i * 0.013, 0.007), 0.1, 0.004, Vector3.BACK, dash.lightened(0.1))
	# A glovebox in front of the passenger.
	var gx := -sx * 0.9
	_bev("satin", Vector3(gx, dt - 0.24, dz + 0.01), Vector3(0.18, 0.08, 0.008), 0.006, dash.lightened(0.05))
	_bev("metal", Vector3(gx, dt - 0.19, dz + 0.02), Vector3(0.03, 0.008, 0.005), 0.003, Color(0.6, 0.6, 0.62))
	# Steering column from the dash up to the wheel (the wheel is Car's).
	var st := _steering_xform()
	var col := st.basis.z
	_tube("satin", st.origin - col * 0.06, st.origin - col * 0.6, 0.04, dash.darkened(0.2), 10)
	_bev("satin", st.origin - col * 0.16, Vector3(0.07, 0.06, 0.08), 0.025, dash.darkened(0.25), st.basis)
	for s: float in [-1.0, 1.0]:
		var root := st.origin - col * 0.14 + st.basis.x * 0.06 * s
		_tube("rough", root, root + st.basis.x * 0.13 * s + st.basis.y * 0.015, 0.007, RUBBER, 5)
		_bev("rough", root + st.basis.x * 0.13 * s + st.basis.y * 0.015, Vector3(0.01, 0.01, 0.01), 0.009, RUBBER)
	# Pedals: clutch, brake and the floor-hinged throttle.
	var pz := sz - 0.72
	for pd: Array in [[sx - 0.2, "clutch"], [sx - 0.05, "brake"], [sx + 0.12, "throttle"]]:
		var px: float = pd[0]
		if pd[1] == "throttle":
			var a := Vector3(px, fl + 0.02, pz + 0.12)
			var b := Vector3(px, fl + 0.2, pz - 0.08)
			_bev("rough", (a + b) * 0.5, Vector3(0.045, 0.012, 0.14), 0.006, RUBBER, Basis(Vector3.RIGHT, atan2(b.y - a.y, -(b.z - a.z))))
		else:
			if pd[1] == "clutch" and not c.get("clutch", true):
				continue
			var pc := Vector3(px, fl + 0.17, pz - 0.02)
			_tube("steel", pc, pc + Vector3(0, 0.25, -0.12), 0.01, DARK, 6)
			_bev("rough", pc, Vector3(0.045, 0.04, 0.01), 0.006, RUBBER, Basis(Vector3.RIGHT, -0.35))
	# Door cards: a padded panel with an armrest, a pull, a pocket and a
	# speaker; the door top; a kick panel.
	for s: float in [-1.0, 1.0]:
		var x := (iw + 0.012) * s
		var inward := Vector3(-s, 0, 0)
		var dz0 := _zf(_wb) + 0.17
		var dz1 := _zb
		var mid := (dz0 + dz1) * 0.5
		_box("satin", Vector3(x, (fl + _wb) * 0.5, mid), Vector3(0.02, _wb - fl, dz1 - dz0), trim)
		_box("rough", Vector3(x - 0.012 * s, (fl + 0.3 + _wb - 0.12) * 0.5, mid), Vector3(0.008, _wb - 0.12 - fl - 0.3, dz1 - dz0 - 0.1), cloth)
		_bev("satin", Vector3(x - 0.05 * s, sy + 0.16, mid + 0.05), Vector3(0.045, 0.03, (dz1 - dz0) * 0.32), 0.02, trim.lightened(0.08))
		_bev("metal", Vector3(x - 0.03 * s, sy + 0.32, dz1 - 0.15), Vector3(0.01, 0.02, 0.06), 0.008, Color(0.65, 0.66, 0.68))
		_bev("rough", Vector3(x - 0.03 * s, fl + 0.18, mid), Vector3(0.03, 0.1, (dz1 - dz0) * 0.35), 0.01, trim.darkened(0.2))
		_ring("metal", Vector3(x - 0.02 * s, fl + 0.18, dz0 + 0.12), 0.07, 0.08, inward, Color(0.55, 0.56, 0.58), 16)
		_disc("rough", Vector3(x - 0.021 * s, fl + 0.18, dz0 + 0.12), 0.07, inward, RUBBER, 16)
		_box("satin", Vector3((iw - 0.02) * s, _wb - 0.01, mid), Vector3(0.1, 0.02, dz1 - dz0), dash)
		# The wall behind the door, lined.
		_box("satin", Vector3(x, (fl + top) * 0.5, (_zb + _cz1) * 0.5 - 0.03), Vector3(0.02, top - fl, _cz1 - _zb - 0.06), trim)
		# A grab handle over the door.
		_rod("rough", [Vector3(x, _wt - 0.02, dz0 + 0.1), Vector3(x - 0.04 * s, _wt - 0.04, dz0 + 0.14), Vector3(x - 0.04 * s, _wt - 0.04, dz1 - 0.14), Vector3(x, _wt - 0.02, dz1 - 0.1)], 0.012, RUBBER)
	# The back wall and the headliner.
	_box("satin", Vector3(0, (fl + _wb + 0.06) * 0.5, _cz1 - 0.065), Vector3(iw * 2.0, _wb + 0.06 - fl, 0.02), trim)
	_box("rough", Vector3(0, top - 0.015, (_zf(top) + _cz1) * 0.5 + 0.05), Vector3(iw * 2.0, 0.03, _cz1 - _zf(top) - 0.1), head_col)
	# An overhead console: a CB radio, storage bins and map lights.
	var oz0 := _zf(top) + 0.12
	var oz1 := minf(oz0 + 0.55, _cz1 - 0.3)
	_prof("satin", -0.4, 0.4, Vector2(oz0, top - 0.12), Vector2(oz1, top - 0.1), Vector2(oz1, top - 0.03), Vector2(oz0 - 0.04, top - 0.03), dash, 0.02)
	var tilt := Basis(Vector3.RIGHT, -0.25)
	var fn := tilt * Vector3.BACK
	_bev("gloss", Vector3(-0.18, top - 0.08, oz0 + 0.008), Vector3(0.12, 0.028, 0.01), 0.005, Color(0.02, 0.02, 0.025), tilt)
	_plate("gloss", Vector3(-0.2, top - 0.077, oz0 + 0.02), 0.08, 0.018, fn, Color(0.85, 0.3, 0.1))
	for bx: float in [0.05, 0.25]:
		_bev("satin", Vector3(bx, top - 0.08, oz0 + 0.008), Vector3(0.08, 0.03, 0.008), 0.006, dash.lightened(0.08), tilt)
	for s: float in [-1.0, 1.0]:
		_bev("gloss", Vector3(0.32 * s, top - 0.1, oz1 - 0.06), Vector3(0.04, 0.006, 0.03), 0.005, Color(0.95, 0.93, 0.85))
	# Sun visors, folded up against the headliner.
	for s: float in [-1.0, 1.0]:
		_bev("rough", Vector3((iw * 0.5 + 0.02) * s, top - 0.035, _zf(top) + 0.18), Vector3(iw * 0.4, 0.012, 0.11), 0.008, head_col.darkened(0.12))
	# A doghouse over the engine between the seats on a big truck, or a
	# console on a smaller one.
	var hump_h := float(c.get("hump", 0.0))
	if hump_h > 0.0:
		_prof("rough", -0.3, 0.3, Vector2(_zf(fl) + 0.05, fl), Vector2(sz + 0.1, fl), Vector2(sz - 0.05, fl + hump_h), Vector2(dz + 0.05, fl + hump_h), DARK, 0.06)
	else:
		_bev("satin", Vector3(0.0, fl + 0.24, sz - 0.12), Vector3(0.13, 0.24, 0.32), 0.03, dash)
		_plate("rough", Vector3(0.0, fl + 0.485, sz - 0.22), 0.2, 0.3, Vector3.UP, RUBBER)
		for cx2: float in [-0.05, 0.05]:
			_disc("rough", Vector3(cx2, fl + 0.487, sz + 0.05), 0.035, Vector3.UP, Color(0.015, 0.015, 0.015), 12)
	# The gear lever: a tall stick out of the floor beside the driver (a
	# ten-speed's, with its splitter knob), or a column shifter.
	if c.get("stick", false):
		var g0 := Vector3(sx + 0.36, fl + hump_h, sz - 0.26)
		var g1 := g0 + Vector3(0.0, 0.62, 0.08)
		_bev("rough", g0 + Vector3(0, 0.03, 0), Vector3(0.07, 0.03, 0.07), 0.025, RUBBER)
		_tube("metal", g0, g1, 0.013, CHROME, 8)
		_bev("satin", g1 + Vector3(0, 0.035, 0), Vector3(0.026, 0.042, 0.03), 0.024, Color(0.06, 0.06, 0.07))
		_bev("gloss", g1 + Vector3(0, 0.05, -0.03), Vector3(0.01, 0.01, 0.004), 0.003, Color(0.85, 0.85, 0.8))
	else:
		var root := st.origin - col * 0.16 + st.basis.x * 0.07
		_tube("metal", root, root + st.basis.x * 0.2 - st.basis.y * 0.05, 0.008, Color(0.6, 0.6, 0.62), 6)
		_bev("satin", root + st.basis.x * 0.21 - st.basis.y * 0.05, Vector3(0.025, 0.015, 0.015), 0.012, RUBBER)
	# Seats: an air-ride seat for the driver and one for the passenger.
	for s: float in [-1.0, 1.0]:
		_truck_seat(Vector3(absf(sx) * s, sy, sz), fl, seat_col, cloth, s < 0.0)
	# Rubber mats.
	for s: float in [-1.0, 1.0]:
		_plate("rough", Vector3(absf(sx) * s, fl + 0.003, (_zf(fl) + sz) * 0.5), 0.5, sz - _zf(fl) - 0.12, Vector3.UP, Color(0.025, 0.025, 0.027))
	# A fire extinguisher by the passenger's seat, a clipboard on the dash.
	var fe := Vector3(-sx * 1.0 + 0.32 * signf(-sx), fl + 0.2, sz + 0.25)
	_cyl("gloss", fe, fe + Vector3(0, 0.32, 0), 0.055, RED, 10)
	_cyl("metal", fe + Vector3(0, 0.32, 0), fe + Vector3(0, 0.37, 0), 0.02, CHROME, 8)
	_bev("rough", Vector3(gx * 0.8, dt + 0.006, (zfw + dz) * 0.5), Vector3(0.11, 0.004, 0.15), 0.003, Color(0.5, 0.36, 0.2), Basis(Vector3.UP, 0.3))
	_bev("rough", Vector3(gx * 0.8, dt + 0.011, (zfw + dz) * 0.5), Vector3(0.1, 0.002, 0.13), 0.0015, Color(0.95, 0.95, 0.92), Basis(Vector3.UP, 0.3))
	# The mirror on the windshield header (big trucks have none: the
	# back window looks at the trailer's nose), the dome light.
	_bev("gloss", Vector3(0, top - 0.025, (_zf(top) + _cz1) * 0.5 + 0.2), Vector3(0.12, 0.012, 0.06), 0.006, Color(0.95, 0.93, 0.85))


## A dial: a dark face in a chrome ring, white ticks, an orange needle.
func _gauge(c: Vector3, r: float, needle: float) -> void:
	_ring("metal", c, r, r * 1.14, Vector3.BACK, CHROME, 20)
	_disc("gloss", c + Vector3(0, 0, 0.001), r, Vector3.BACK, Color(0.05, 0.05, 0.06), 20)
	var k := _k("gloss")
	k.color = Color(0.9, 0.9, 0.86)
	for t in 9:
		var tb := Basis(Vector3.BACK, deg_to_rad(-120.0 + 30.0 * float(t)))
		k.quad(c + tb * Vector3(-r * 0.035, r * 0.72, 0.002), c + tb * Vector3(r * 0.035, r * 0.72, 0.002), c + tb * Vector3(r * 0.035, r * 0.92, 0.002), c + tb * Vector3(-r * 0.035, r * 0.92, 0.002), Vector3.BACK)
	k.color = Color(0.98, 0.42, 0.08)
	var nb := Basis(Vector3.BACK, needle)
	k.quad(c + nb * Vector3(-r * 0.04, 0, 0.003), c + nb * Vector3(r * 0.04, 0, 0.003), c + nb * Vector3(r * 0.015, r * 0.85, 0.003), c + nb * Vector3(-r * 0.015, r * 0.85, 0.003), Vector3.BACK)


## Where Car puts the steering wheel, by the same rule (Car._steering_transform).
func _steering_xform() -> Transform3D:
	var sp: Array = shape["seat"]
	var c := Vector3(float(sp[0]), float(sp[1]) + float(shape.get("wheel_rise", 0.36)), float(sp[2]) - float(shape.get("wheel_reach", 0.42)))
	return Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(float(shape.get("column_degrees", 24.0)))), c)


## A truck seat: a high back with the headrest built in, side bolsters, a
## cloth insert with pleats, an armrest on the inboard side, on a pedestal
## (the driver's with the bellows of its air suspension), and a belt.
func _truck_seat(p: Vector3, fl: float, shell: Color, cloth: Color, air: bool) -> void:
	var top := p.y - 0.08
	var inboard := -signf(p.x)
	# Pedestal.
	if air:
		_bev("rough", Vector3(p.x, (fl + top - 0.1) * 0.5, p.z - 0.12), Vector3(0.2, maxf(0.03, (top - 0.1 - fl) * 0.5), 0.2), 0.03, RUBBER)
		var n := maxi(2, int((top - 0.1 - fl) / 0.05))
		for i in n:
			_bev("rough", Vector3(p.x, fl + (i + 0.5) * (top - 0.1 - fl) / n, p.z - 0.12), Vector3(0.215, 0.012, 0.215), 0.01, Color(0.06, 0.06, 0.065))
	else:
		_bev("steel", Vector3(p.x, (fl + top - 0.1) * 0.5, p.z - 0.12), Vector3(0.17, maxf(0.03, (top - 0.1 - fl) * 0.5), 0.17), 0.02, DARK)
	_bev("steel", Vector3(p.x, top - 0.11, p.z - 0.15), Vector3(0.24, 0.02, 0.25), 0.01, DARK)
	# Cushion.
	_bev("satin", Vector3(p.x, top - 0.05, p.z - 0.17), Vector3(0.26, 0.06, 0.28), 0.04, shell)
	_bev("rough", Vector3(p.x, top + 0.01, p.z - 0.18), Vector3(0.17, 0.012, 0.24), 0.01, cloth)
	for i in 4:
		_plate("rough", Vector3(p.x, top + 0.0225, p.z - 0.36 + i * 0.12), 0.34, 0.007, Vector3.UP, cloth.darkened(0.35))
	for s: float in [-1.0, 1.0]:
		_bev("satin", Vector3(p.x + 0.215 * s, top - 0.02, p.z - 0.16), Vector3(0.05, 0.07, 0.26), 0.04, shell)
	# Back, leaning back a little.
	var back := Basis(Vector3.RIGHT, 0.2)
	var base := Vector3(p.x, top - 0.03, p.z + 0.15)
	_bev("satin", base + back * Vector3(0, 0.42, 0.02), Vector3(0.25, 0.42, 0.06), 0.05, shell, back)
	_bev("rough", base + back * Vector3(0, 0.38, -0.045), Vector3(0.16, 0.3, 0.012), 0.01, cloth, back)
	for i in 6:
		var y := 0.12 + i * 0.1
		_bev("rough", base + back * Vector3(0, y, -0.058), Vector3(0.155, 0.004, 0.002), 0.0015, cloth.darkened(0.35), back)
	for s: float in [-1.0, 1.0]:
		_bev("satin", base + back * Vector3(0.21 * s, 0.38, -0.035), Vector3(0.05, 0.34, 0.07), 0.04, shell, back)
	# Headrest (built in, with a band across it) and the brand's tag.
	_bev("satin", base + back * Vector3(0, 0.93, 0.02), Vector3(0.16, 0.1, 0.06), 0.05, shell, back)
	_bev("rough", base + back * Vector3(0, 0.93, -0.035), Vector3(0.12, 0.06, 0.01), 0.008, cloth, back)
	# Armrest on the inboard side, folded down.
	var arm := Vector3(p.x + 0.29 * inboard, top + 0.14, p.z - 0.08)
	_bev("satin", arm, Vector3(0.035, 0.035, 0.18), 0.03, shell)
	_cyl("steel", arm + Vector3(0, 0, 0.17), arm + Vector3(-0.035 * inboard, 0.05, 0.22), 0.012, DARK, 6)
	# The belt, from the B-pillar over the seat to the buckle.
	var out := -inboard
	var pts: Array[Vector3] = [
		Vector3((_hw - 0.07) * out, p.y + 0.65, p.z + 0.26),
		base + back * Vector3(0.17 * out, 0.66, -0.08),
		base + back * Vector3(-0.04 * out, 0.34, -0.08),
		base + back * Vector3(-0.17 * out, 0.12, -0.08),
		Vector3(p.x + 0.24 * inboard, p.y - 0.03, p.z + 0.02),
	]
	var k := _k("rough")
	k.color = Color(0.06, 0.06, 0.065)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var along := (b - a).normalized()
		var n := back * Vector3.FORWARD
		var side := along.cross(n).normalized() * 0.022
		k.quad(a - side, a + side, b + side, b - side, n)
	_bev("metal", pts[0] + Vector3(0, 0.02, 0), Vector3(0.012, 0.03, 0.025), 0.005, Color(0.6, 0.6, 0.62))
	_bev("metal", pts[4], Vector3(0.018, 0.03, 0.012), 0.006, Color(0.6, 0.6, 0.62))
	_bev("rough", pts[4] + Vector3(0, 0.032, 0), Vector3(0.012, 0.006, 0.009), 0.003, RED)


# --- noses: the hood, grille, fenders, lamps and bumper --------------------------------------

## A conventional's front end. c: z0 (front of the bumper), hood_top, hw,
## fa (front axle), wr (wheel radius), style ("highway" or "medium").
func _nose(c: Dictionary) -> void:
	var hw: float = c["hw"]
	var z0: float = c["z0"]
	var ht: float = c["hood_top"]
	var fa: float = c["fa"]
	var wr: float = c["wr"]
	var big := str(c.get("style", "highway")) == "highway"
	# The hood is as wide as clears the front tyres; the fenders flare out
	# over them from there.
	var hood_w: float = c["hood_w"]
	var gz := z0 + (0.3 if big else 0.22) # the grille's face
	var by := 0.55 if big else 0.5 # bumper centre height
	var hb := by + 0.14 # the hood's bottom edge at the front
	_prof("paint", -hood_w, hood_w, Vector2(gz + 0.05, hb), Vector2(_cz0 + 0.02, hb + 0.1), Vector2(_cz0 + 0.02, ht + 0.12), Vector2(gz + 0.12, ht), paint, 0.1)
	var fr0 := wr + 0.07
	var fr1 := wr + 0.12
	var fy := wr + 0.04 # fender arch centre (a little above the axle)
	var front_t := 0.35 # where the arch starts, radians up from level in front
	var back_t := PI - 0.12
	var az := fa - cos(front_t) * fr1
	var ay := fy + sin(front_t) * fr1
	for s: float in [-1.0, 1.0]:
		var xi := (hood_w - 0.01) * s
		var xo := (hw - 0.01) * s
		var xm := (xi + xo) * 0.5
		_arch("paint", fa, fy, fr0, fr1, minf(xi, xo), maxf(xi, xo), front_t, back_t, paint, 18)
		_arch("rough", fa, fy, fr0 - 0.02, fr0, minf(xi, xo) + 0.01, maxf(xi, xo) - 0.01, front_t, back_t, RUBBER, 12)
		# The fender's nose, from the grille back to the arch, if there's room.
		var nose_top := ht - 0.3
		if az > gz + 0.15:
			_prof("paint", xi, xo, Vector2(gz + 0.06, hb), Vector2(az, ay - 0.06), Vector2(az + 0.03, fy + fr1 * 0.9), Vector2(gz + 0.1, nose_top), paint)
		# Behind the arch: a skirt down to the cab.
		var bz := fa - cos(back_t) * fr1
		_prof("paint", xi, xo, Vector2(bz - 0.04, fy + 0.03), Vector2(_cz0 + 0.02, fy + 0.03), Vector2(_cz0 + 0.02, fy + fr1 + 0.01), Vector2(bz - 0.04, fy + fr1 * 0.6), paint)
		# Headlamps.
		if big:
			# Pods on the fenders: a chrome bezel with a pair of round lamps,
			# the turn signal under them.
			var t := 1.05
			var pc := Vector3(xm, fy + sin(t) * fr1 + 0.06, fa - cos(t) * fr1)
			_bev("paint", pc, Vector3(absf(xo - xi) * 0.5 - 0.01, 0.1, 0.16), 0.04, paint)
			_bev("metal", pc + Vector3(0, 0, -0.16), Vector3(absf(xo - xi) * 0.5 - 0.015, 0.085, 0.015), 0.012, CHROME)
			for lx: float in [-0.045, 0.045]:
				_lamp(pc + Vector3(lx, 0.01, -0.178), 0.07, 0.07, Vector3.FORWARD, LAMP, CHROME, true)
			_lamp(pc + Vector3(0, -0.06, -0.178), 0.12, 0.025, Vector3.FORWARD, AMBER, CHROME)
			# A hood mirror on a stalk from the top of the fender.
			var hm := Vector3(xm, fy + fr1, fa)
			_rod("metal", [hm, hm + Vector3(0.1 * s, 0.25, 0), hm + Vector3(0.16 * s, 0.27, 0)], 0.01, CHROME)
			_bev("rough", hm + Vector3(0.19 * s, 0.27, 0), Vector3(0.025, 0.065, 0.065), 0.024, RUBBER)
			_disc("metal", hm + Vector3(0.19 * s, 0.27, 0.066), 0.055, Vector3.BACK, MIRROR, 14)
		else:
			var gwm := hood_w * 0.66 + 0.05
			var hl := Vector3((gwm + hood_w) * 0.5 * s, (hb + ht) * 0.5 + 0.06, gz + 0.04)
			var lw := hood_w - gwm - 0.03
			_bev("metal", hl, Vector3(lw * 0.5 + 0.015, 0.13, 0.02), 0.015, CHROME)
			_plate("gloss", hl + Vector3(0, 0.03, -0.022), lw, 0.14, Vector3.FORWARD, LAMP)
			_ring("metal", hl + Vector3(0, 0.03, -0.025), 0.035, 0.05, Vector3.FORWARD, Color(0.8, 0.82, 0.85), 14)
			_plate("gloss", hl + Vector3(0, -0.08, -0.022), lw, 0.05, Vector3.FORWARD, AMBER)
			_lamp(Vector3(xm, (hb + nose_top) * 0.5 + 0.05, gz + 0.055), absf(xo - xi) - 0.08, 0.06, Vector3.FORWARD, AMBER, CHROME)
		# Amber marker on the side of the fender.
		var mt := 0.75
		_lamp(Vector3(xo + 0.004 * s, fy + sin(mt) * (fr0 + fr1) * 0.5, fa - cos(mt) * (fr0 + fr1) * 0.5), 0.07, 0.03, Vector3(s, 0, 0), AMBER, CHROME)
	# Grille: a chrome surround, a dark mesh, and bars.
	var gw := hood_w - 0.08 if big else hood_w * 0.66
	var gb := hb + 0.02
	var gt := ht - 0.05
	_prof("rough", -gw, gw, Vector2(gz + 0.04, gb), Vector2(gz + 0.12, gb), Vector2(gz + 0.12, gt), Vector2(gz + 0.04, gt), Color(0.02, 0.02, 0.022))
	for s: float in [-1.0, 1.0]:
		_bev("metal", Vector3(gw * s, (gb + gt) * 0.5, gz + 0.03), Vector3(0.04, (gt - gb) * 0.5 + 0.04, 0.035), 0.02, CHROME)
	for y: float in [gb, gt]:
		_bev("metal", Vector3(0, y, gz + 0.03), Vector3(gw + 0.04, 0.04, 0.035), 0.02, CHROME)
	if big:
		var n := int(gw * 2.0 / 0.07)
		for i in n:
			var x := -gw + (i + 0.5) * gw * 2.0 / n
			_box("metal", Vector3(x, (gb + gt) * 0.5, gz + 0.045), Vector3(0.022, gt - gb, 0.03), CHROME)
		for y2: float in [gb + (gt - gb) * 0.33, gb + (gt - gb) * 0.66]:
			_box("metal", Vector3(0, y2, gz + 0.03), Vector3(gw * 2.0, 0.02, 0.02), CHROME.darkened(0.1))
		# The brand's emblem over the grille, and the hood ornament.
		_bev("metal", Vector3(0, gt + 0.09, gz + 0.09), Vector3(0.16, 0.05, 0.02), 0.03, CHROME)
		_bev("gloss", Vector3(0, gt + 0.09, gz + 0.071), Vector3(0.13, 0.035, 0.005), 0.025, Color(0.55, 0.05, 0.05))
	else:
		for i in 3:
			var y3 := gb + (gt - gb) * (float(i) + 1.0) / 4.0
			_bev("metal", Vector3(0, y3, gz + 0.035), Vector3(gw, 0.025, 0.025), 0.015, CHROME)
		_bev("metal", Vector3(0, (gb + gt) * 0.5, gz + 0.01), Vector3(0.13, 0.05, 0.02), 0.03, CHROME)
		_bev("gloss", Vector3(0, (gb + gt) * 0.5, gz - 0.009), Vector3(0.11, 0.035, 0.005), 0.025, Color(0.1, 0.2, 0.45))
	# Amber marker lamps on the hood's nose, and vents in its sides.
	for s: float in [-1.0, 1.0]:
		_bev("gloss", Vector3(0.2 * s, ht + 0.02, gz + 0.2), Vector3(0.04, 0.015, 0.025), 0.01, AMBER)
		if big:
			var vz := _cz0 - 0.5
			for i in 6:
				_box("rough", Vector3((hood_w + 0.004) * s, ht - 0.35 - i * 0.05, vz), Vector3(0.006, 0.018, 0.5), Color(0.02, 0.02, 0.022))
	# The bumper: chrome, wrapping round the corners, with tow hooks.
	_bev("metal", Vector3(0, by, z0 + 0.12), Vector3(hw - 0.22, 0.16 if big else 0.12, 0.12), 0.04, CHROME)
	for s: float in [-1.0, 1.0]:
		var rot := Basis(Vector3.UP, 0.45 * s)
		_bev("metal", Vector3((hw - 0.16) * s, by, z0 + 0.19), Vector3(0.13, 0.16 if big else 0.12, 0.1), 0.04, CHROME, rot)
		_rod("steel", [Vector3(0.45 * s, by - 0.14, z0 + 0.2), Vector3(0.45 * s, by - 0.2, z0 + 0.1), Vector3(0.45 * s, by - 0.12, z0 + 0.03)], 0.022, DARK)
	# Air dam and the radiator behind the grille, visible from below.
	_box("rough", Vector3(0, by - 0.19, z0 + 0.3), Vector3(hw * 1.5, 0.06, 0.3), DARK)
	_box("rough", Vector3(0, (gb + gt) * 0.5, gz + 0.2), Vector3(gw * 2.0, gt - gb, 0.08), Color(0.03, 0.03, 0.03))


## Leaf springs and an I-beam front axle under the nose, and the engine.
func _front_axle(fa: float, wr: float, track: float, frame_y: float, engine_z0: float, engine_z1: float) -> void:
	_box("steel", Vector3(0, wr - 0.05, fa), Vector3(track * 1.6, 0.1, 0.09), DARK)
	for s: float in [-1.0, 1.0]:
		var x := 0.45 * s
		for i in 4:
			var l := 1.2 - i * 0.18
			_box("steel", Vector3(x, wr + 0.02 + i * 0.022, fa), Vector3(0.08, 0.02, l), STEEL.darkened(0.4))
		for zz: float in [fa - 0.6, fa + 0.6]:
			_box("steel", Vector3(x, (wr + 0.02 + frame_y) * 0.5, zz), Vector3(0.06, frame_y - wr, 0.06), DARK)
		_cyl("steel", Vector3(x + 0.08 * s, wr, fa + 0.15), Vector3(x + 0.08 * s, frame_y - 0.05, fa + 0.05), 0.03, DARK, 8)
		# The steering knuckle out to the hub.
		_cyl("steel", Vector3((track - 0.25) * s, wr, fa), Vector3(x + 0.2 * s, wr - 0.02, fa), 0.05, DARK, 8)
	_tube("steel", Vector3(-track * 0.75, wr - 0.1, fa + 0.22), Vector3(track * 0.75, wr - 0.1, fa + 0.22), 0.025, DARK, 6)
	# The engine and transmission, dark lumps that show from below.
	_bev("rough", Vector3(0, frame_y - 0.25, (engine_z0 + engine_z1) * 0.5), Vector3(0.38, 0.35, (engine_z1 - engine_z0) * 0.5), 0.06, Color(0.12, 0.12, 0.13))
	_bev("rough", Vector3(0, frame_y - 0.38, engine_z1 + 0.35), Vector3(0.22, 0.2, 0.35), 0.06, Color(0.16, 0.16, 0.17))


## Two frame rails from z0 to z1, their top at y, with crossmembers.
func _frame(z0: float, z1: float, y: float, gap := 0.45) -> void:
	for s: float in [-1.0, 1.0]:
		# C-channel: a web and two flanges facing in.
		_box("steel", Vector3(gap * s, y - 0.14, (z0 + z1) * 0.5), Vector3(0.012, 0.28, z1 - z0), DARK)
		for fy: float in [y - 0.008, y - 0.272]:
			_box("steel", Vector3((gap - 0.035) * s, fy, (z0 + z1) * 0.5), Vector3(0.07, 0.016, z1 - z0), DARK)
	var z := z0 + 0.4
	while z < z1:
		_box("steel", Vector3(0.0, y - 0.14, z), Vector3(gap * 2.0, 0.2, 0.012), DARK)
		_box("steel", Vector3(0.0, y - 0.04, z), Vector3(gap * 2.0, 0.012, 0.08), DARK)
		z += 1.1


## A drive axle: the housing out to the wheels, the differential, air bags
## and shocks on trailing arms.
func _drive_axle(z: float, wr: float, track: float, frame_y: float, diff := true) -> void:
	_cyl("steel", Vector3(-track + 0.25, wr, z), Vector3(track - 0.25, wr, z), 0.075, DARK, 12)
	if diff:
		_bev("steel", Vector3(0, wr, z), Vector3(0.2, 0.2, 0.18), 0.12, Color(0.12, 0.12, 0.13))
		_cyl("steel", Vector3(0, wr + 0.02, z - 0.15), Vector3(0, wr + 0.04, z - 0.3), 0.07, Color(0.12, 0.12, 0.13), 10)
	for s: float in [-1.0, 1.0]:
		var x := 0.45 * s
		_box("steel", Vector3(x, wr - 0.04, z), Vector3(0.1, 0.1, 1.0), DARK)
		_cyl("rough", Vector3(x, wr + 0.06, z + 0.4), Vector3(x, frame_y - 0.28, z + 0.4), 0.12, RUBBER, 14)
		_cyl("steel", Vector3(x + 0.11 * s, wr, z - 0.2), Vector3(x + 0.08 * s, frame_y - 0.2, z - 0.05), 0.025, Color(0.75, 0.55, 0.1), 8)
		# Brake chamber.
		_cyl("steel", Vector3((track - 0.45) * s, wr + 0.1, z - 0.12), Vector3((track - 0.45) * s, wr + 0.1, z - 0.3), 0.08, DARK, 10)


## Tail lights at the back of a frame: round red lamps, amber turns, a white
## reverse lamp, on a black bar, and the plate.
func _tail(z: float, y: float, half_w: float) -> void:
	_box("steel", Vector3(0, y, z - 0.03), Vector3(half_w * 2.0, 0.18, 0.06), DARK)
	for s: float in [-1.0, 1.0]:
		_lamp(Vector3((half_w - 0.1) * s, y, z + 0.005), 0.1, 0.1, Vector3.BACK, RED, RUBBER, true)
		_lamp(Vector3((half_w - 0.25) * s, y, z + 0.005), 0.1, 0.1, Vector3.BACK, AMBER, RUBBER, true)
		_lamp(Vector3((half_w - 0.4) * s, y, z + 0.005), 0.07, 0.07, Vector3.BACK, LAMP, RUBBER, true)
	_plate("gloss", Vector3(0.25, y - 0.2, z + 0.004), 0.3, 0.15, Vector3.BACK, Color(0.92, 0.92, 0.88))
	_plate("gloss", Vector3(0.25, y - 0.2, z + 0.006), 0.26, 0.03, Vector3.BACK, Color(0.12, 0.28, 0.2))
	_box("steel", Vector3(0.25, y - 0.12, z), Vector3(0.05, 0.08, 0.04), DARK)


## A mud flap hanging behind a wheel, with a chrome weight along its foot.
func _flap(x: float, z: float, top: float, w: float) -> void:
	_box("rough", Vector3(x, top * 0.5 + 0.1, z), Vector3(w, top - 0.2, 0.012), RUBBER)
	_box("metal", Vector3(x, 0.24, z + 0.008), Vector3(w, 0.06, 0.006), CHROME)
	_plate("gloss", Vector3(x, top - 0.22, z + 0.007), w * 0.55, 0.06, Vector3.BACK, Color(0.8, 0.8, 0.78))


## A chrome fuel tank on two straps, with its cap.
func _fuel_tank(x: float, y: float, z0: float, z1: float, r: float) -> void:
	_cyl("metal", Vector3(x, y, z0), Vector3(x, y, z1), r, CHROME, 20)
	for zz: float in [z0 + 0.18, z1 - 0.18]:
		_ring("steel", Vector3(x, y, zz), r - 0.004, r + 0.012, Vector3.BACK, DARK, 20)
		_ring("steel", Vector3(x, y, zz + 0.04), r - 0.004, r + 0.012, Vector3.FORWARD, DARK, 20)
		_cyl("steel", Vector3(x, y, zz - 0.0), Vector3(x, y, zz + 0.04), r + 0.012, DARK, 20)
	_cyl("metal", Vector3(x, y + r - 0.01, (z0 + z1) * 0.5 + 0.2), Vector3(x, y + r + 0.03, (z0 + z1) * 0.5 + 0.2), 0.05, CHROME.darkened(0.1), 12)


## A coiled air line between a and b (radius of the coils r).
func _coil(a: Vector3, b: Vector3, r: float, turns: int, thick: float, col: Color) -> void:
	var ax := (b - a)
	var u := ax.normalized().cross(Vector3.UP if absf(ax.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var v := ax.normalized().cross(u)
	var n := turns * 10
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		var ang := TAU * turns * t
		pts.append(a + ax * t + (u * cos(ang) + v * sin(ang)) * r)
	for i in n:
		_tube("rough", pts[i], pts[i + 1], thick, col, 5)


# --- the vehicles -------------------------------------------------------------------------

func _tractor() -> void:
	var hw := float(shape["width"]) * 0.5
	var fa := -2.7
	var wr := 0.52
	_cab({"hw": hw, "cz0": -1.6, "cz1": 0.5, "y0": 0.95, "roof": 3.05, "rake": 0.3, "floor": 1.3, "belt": 2.1,
		"steps": [], "visor": true, "stick": true, "hump": 0.22, "trim": "#5b5650", "dash": "#2a2826",
		"seat": "#2c2a28", "cloth": "#6d655a"})
	_nose({"hw": hw, "z0": -3.6, "hood_top": 1.85, "fa": fa, "wr": wr, "hood_w": 0.8, "style": "highway"})
	_frame(-3.3, 3.55, 1.02)
	_front_axle(fa, wr, 1.03, 1.02, -3.1, -1.2)
	# Driveshafts to the drives, and between them.
	_cyl("steel", Vector3(0, 0.62, -0.5), Vector3(0, 0.55, 1.45), 0.05, STEEL, 10)
	_cyl("steel", Vector3(0, 0.56, 1.85), Vector3(0, 0.53, 2.75), 0.045, STEEL, 10)
	for az: float in [1.65, 2.95]:
		_drive_axle(az, wr, 0.92, 1.02)
	# Fuel tanks under the cab doors: a long one on the driver's side, a
	# shorter one and the DEF tank (blue cap) on the other.
	_fuel_tank(-0.95, 0.72, -1.4, 0.3, 0.32)
	_fuel_tank(0.95, 0.72, -1.4, -0.35, 0.32)
	_cyl("paint", Vector3(0.98, 0.65, -0.25), Vector3(0.98, 0.65, 0.3), 0.24, Color(0.9, 0.9, 0.9), 16)
	_cyl("gloss", Vector3(0.98, 0.88, 0.05), Vector3(0.98, 0.92, 0.05), 0.045, Color(0.1, 0.3, 0.8), 10)
	for s: float in [-1.0, 1.0]:
		_tread(Vector3(0.95 * s, 1.045, -0.75), 0.4, 0.6)
		# A step hung in front of the tank, up to the tank's tread and the door.
		_tread(Vector3(1.04 * s, 0.52, -1.5), 0.3, 0.16)
		_box("steel", Vector3(0.9 * s, 0.68, -1.5), Vector3(0.03, 0.34, 0.14), DARK)
		# Tank brackets to the frame.
		for zz: float in [-1.2, 0.1]:
			_box("steel", Vector3(0.66 * s, 0.82, zz), Vector3(0.22, 0.08, 0.06), DARK)
	# Exhaust stacks behind the cab: chrome pipes with perforated heat
	# shields, mitred tops and brackets to the cab.
	for s: float in [-1.0, 1.0]:
		var x := 1.0 * s
		_cyl("metal", Vector3(x, 1.05, 0.68), Vector3(x, 3.55, 0.68), 0.085, CHROME, 14)
		_cyl("steel", Vector3(x, 1.6, 0.68), Vector3(x, 2.55, 0.68), 0.11, Color(0.75, 0.76, 0.77), 16)
		_detail = true
		for i in 9:
			for j in 8:
				var a := TAU * j / 8.0
				var d := Vector3(cos(a), 0, sin(a))
				if d.dot(Vector3(0, 0, 1)) < -0.3:
					continue
				_disc("rough", Vector3(x, 1.68 + i * 0.1, 0.68) + d * 0.112, 0.012, d, Color(0.15, 0.15, 0.16), 4)
		_detail = false
		_blk("metal", [
			Vector3(x - 0.085, 3.55, 0.6), Vector3(x + 0.085, 3.55, 0.6), Vector3(x + 0.085, 3.72, 0.6), Vector3(x - 0.085, 3.72, 0.6),
			Vector3(x - 0.085, 3.55, 0.76), Vector3(x + 0.085, 3.55, 0.76), Vector3(x + 0.085, 3.62, 0.76), Vector3(x - 0.085, 3.62, 0.76),
		], CHROME)
		for y: float in [1.7, 2.9]:
			_box("steel", Vector3(x * 0.95, y, 0.57), Vector3(0.06, 0.06, 0.14), DARK)
	# Air horns on the roof.
	for s: float in [-1.0, 1.0]:
		_cone("metal", Vector3(0.32 * s, 3.1, -0.4), Vector3(0.32 * s, 3.1, -0.4 - 0.45 - 0.1 * s), 0.02, 0.06, CHROME, 12)
	_box("metal", Vector3(0, 3.07, -0.35), Vector3(0.8, 0.04, 0.08), CHROME)
	# The deck plate behind the cab, the pogo stick and its coiled air and
	# electrical lines (red, blue and green) out to their glad hands.
	_tread(Vector3(0, 1.045, 0.85), 0.92, 0.6)
	_rod("metal", [Vector3(0.2, 1.05, 0.62), Vector3(0.2, 2.0, 0.62), Vector3(0.2, 2.1, 0.75)], 0.018, CHROME)
	for i in 3:
		var col: Color = [RED, Color(0.1, 0.25, 0.7), Color(0.15, 0.45, 0.15)][i]
		var x := -0.35 + i * 0.25
		_coil(Vector3(x, 1.75, 0.63), Vector3(x, 1.45, 1.25), 0.06, 4, 0.012, col)
		_box("metal", Vector3(x, 1.43, 1.28), Vector3(0.06, 0.03, 0.06), GALV)
	# Battery box and a tool box behind the cab.
	_bev("steel", Vector3(-0.78, 0.82, 0.72), Vector3(0.22, 0.2, 0.2), 0.02, GALV)
	_bev("metal", Vector3(-1.0, 0.86, 0.72), Vector3(0.006, 0.02, 0.05), 0.004, CHROME)
	# The fifth wheel: a greased plate with its throat, jaws and release
	# handle, on brackets that slide on rails.
	var fw := Vector3(0, 1.17, 2.2)
	_box("steel", Vector3(0, 1.08, 2.2), Vector3(1.2, 0.06, 1.6), DARK)
	for s: float in [-1.0, 1.0]:
		_box("steel", Vector3(0.42 * s, 1.11, 2.2), Vector3(0.12, 0.08, 1.7), STEEL)
		for i in 6:
			_box("rough", Vector3(0.42 * s, 1.152, 1.55 + i * 0.25), Vector3(0.05, 0.003, 0.05), RUBBER)
		_bev("steel", Vector3(0.62 * s, 1.14, 2.2), Vector3(0.08, 0.06, 0.12), 0.02, Color(0.15, 0.15, 0.15))
	var k := _k("gloss")
	k.color = Color(0.05, 0.05, 0.05)
	# The plate as a disc-ish polygon with a V cut at the back.
	var pts: Array[Vector2] = []
	for i in 21:
		var a := PI * 0.12 + (PI * 1.76) * i / 20.0 # leave the back open
		pts.append(Vector2(sin(a) * 0.75, -cos(a) * 0.55))
	var ytop := 1.224
	for i in range(pts.size() - 1):
		var p0 := Vector3(pts[i].x, ytop, fw.z + pts[i].y)
		var p1 := Vector3(pts[i + 1].x, ytop, fw.z + pts[i + 1].y)
		k.tri(Vector3(0, ytop, fw.z), p0, p1, Vector3.UP)
		k.quad(p0, p1, p1 - Vector3(0, 0.1, 0), p0 - Vector3(0, 0.1, 0), Vector3(p0.x + p1.x, 0, p0.z + p1.z - 2.0 * fw.z).normalized())
	# The throat's walls and the locked jaw.
	for s: float in [-1.0, 1.0]:
		var a := Vector3(pts[0].x * s, ytop, fw.z + pts[0].y)
		k.tri(Vector3(0, ytop, fw.z), a, Vector3(0.05 * s, ytop, fw.z + 0.05), Vector3.UP)
	_box("steel", Vector3(0, 1.2, 2.2), Vector3(0.1, 0.03, 0.1), STEEL)
	_rod("metal", [Vector3(-0.5, 1.12, 2.3), Vector3(-0.85, 1.12, 2.3), Vector3(-0.9, 1.12, 2.22)], 0.014, CHROME)
	_bev("gloss", Vector3(-0.92, 1.12, 2.2), Vector3(0.03, 0.03, 0.05), 0.02, Color(0.9, 0.75, 0.1))
	# Ramps behind the plate, to lift a trailer's nose on.
	for s: float in [-1.0, 1.0]:
		_prof("steel", 0.15 * s if s > 0 else -0.7, 0.7 if s > 0 else -0.15, Vector2(2.75, 1.0), Vector2(3.25, 0.98), Vector2(3.25, 1.02), Vector2(2.75, 1.17), DARK)
	# Quarter fenders over the drives: black poly, joined across the top.
	for s: float in [-1.0, 1.0]:
		var x0 := 0.6 * s
		var x1 := 1.24 * s
		var cy := wr + 0.02
		_arch("gloss", 1.65, cy, wr + 0.08, wr + 0.11, minf(x0, x1), maxf(x0, x1), 0.5, PI * 0.5, Color(0.04, 0.04, 0.045), 8)
		_arch("gloss", 2.95, cy, wr + 0.08, wr + 0.11, minf(x0, x1), maxf(x0, x1), PI * 0.5, PI - 0.4, Color(0.04, 0.04, 0.045), 8)
		_box("gloss", Vector3((x0 + x1) * 0.5, cy + wr + 0.095, 2.3), Vector3(absf(x1 - x0), 0.03, 1.3), Color(0.04, 0.04, 0.045))
		for zz: float in [1.9, 2.7]:
			_box("steel", Vector3(0.52 * s, cy + wr - 0.08, zz), Vector3(0.18, 0.3, 0.04), DARK)
		_flap(0.92 * s, 3.62, 1.05, 0.6)
	_tail(3.58, 0.85, 1.0)


func _flat_trailer() -> void:
	var hw := float(shape["width"]) * 0.5
	var l := float(shape["length"])
	var zf := -l * 0.5
	var zr := l * 0.5
	var wood := Color(0.5, 0.36, 0.22)
	# Deck: hardwood boards running lengthwise, a little different each.
	var n := 11
	var bw := (hw * 2.0 - 0.18) / n
	for i in n:
		var x := -hw + 0.09 + (i + 0.5) * bw
		var c := wood.darkened(0.05 * ((i * 7) % 3)).lightened(0.03 * ((i * 5) % 2))
		_box("rough", Vector3(x, 1.475, 0.0), Vector3(bw - 0.008, 0.05, l - 0.04), c)
	_box("rough", Vector3(0, 1.46, 0), Vector3(hw * 2.0 - 0.18, 0.04, l - 0.05), Color(0.12, 0.1, 0.08))
	# A steel nose plate and tail sill across the ends of the boards.
	_tread(Vector3(0, 1.505, zf + 0.12), hw * 2.0 - 0.12, 0.22, STEEL)
	_box("steel", Vector3(0, 1.45, zr - 0.04), Vector3(hw * 2.0, 0.12, 0.08), paint.darkened(0.1))
	# Rub rails: a deep side rail with stake pockets, the winch track along
	# its foot with sliding strap winches, red-and-white reflective tape.
	for s: float in [-1.0, 1.0]:
		var x := (hw - 0.05) * s
		_box("paint", Vector3(x, 1.37, 0.0), Vector3(0.1, 0.26, l), paint)
		_box("paint", Vector3((hw - 0.005) * s, 1.48, 0.0), Vector3(0.03, 0.04, l), paint.lightened(0.05))
		var p := zf + 0.6
		var j := 0
		while p < zr - 0.3:
			_box("paint", Vector3((hw + 0.01) * s, 1.42, p), Vector3(0.03, 0.12, 0.13), paint.darkened(0.25))
			_box("rough", Vector3((hw - 0.03) * s, 1.48, p), Vector3(0.05, 0.006, 0.09), RUBBER)
			if j % 2 == 1:
				# A strap winch on the track: drum, ratchet and a square end.
				var wz := p + 0.46
				_detail = true
				_box("steel", Vector3((hw + 0.02) * s, 1.215, wz), Vector3(0.05, 0.05, 0.22), GALV)
				_cyl("steel", Vector3((hw + 0.07) * s, 1.17, wz - 0.07), Vector3((hw + 0.07) * s, 1.17, wz + 0.07), 0.045, GALV, 10)
				_box("steel", Vector3((hw + 0.07) * s, 1.17, wz - 0.1), Vector3(0.035, 0.035, 0.03), DARK)
				_cyl("steel", Vector3((hw + 0.07) * s, 1.17, wz - 0.055), Vector3((hw + 0.07) * s, 1.17, wz + 0.055), 0.048, Color(0.85, 0.55, 0.1), 10)
				_detail = false
			p += 0.92
			j += 1
		_box("steel", Vector3((hw - 0.01) * s, 1.23, 0.0), Vector3(0.06, 0.03, l - 0.4), GALV)
		# Conspicuity tape: red and white in turns along the rail.
		var tz := zf + 0.3
		var red := true
		while tz < zr - 0.3:
			_plate("gloss", Vector3((hw + 0.0015) * s, 1.32, tz + 0.15), 0.3, 0.05, Vector3(s, 0, 0), RED if red else Color(0.95, 0.95, 0.92))
			red = not red
			tz += 0.6 if red else 0.3
		# Side markers: amber at the front and middle, red at the back.
		for mz: float in [zf + 0.2, 0.0, zr - 0.2]:
			_lamp(Vector3((hw + 0.012) * s, 1.28, mz), 0.07, 0.035, Vector3(s, 0, 0), RED if mz > 1.0 else AMBER, RUBBER)
	# Main beams: I-beams, shallow over the tractor and deep in the middle,
	# their bottom flange tapering back up at the tail.
	var prof := [[zf + 0.1, 1.2], [-4.4, 1.2], [-3.0, 0.88], [3.8, 0.88], [zr - 0.25, 1.04]]
	for s: float in [-1.0, 1.0]:
		var x := 0.45 * s
		for i in range(prof.size() - 1):
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			_prof("steel", x - 0.006, x + 0.006, Vector2(a[0], a[1]), Vector2(b[0], b[1]), Vector2(b[0], 1.24), Vector2(a[0], 1.24), DARK)
			_prof("steel", x - 0.07, x + 0.07, Vector2(a[0], a[1]), Vector2(b[0], b[1]), Vector2(b[0], float(b[1]) + 0.018), Vector2(a[0], float(a[1]) + 0.018), DARK)
		_box("steel", Vector3(x, 1.232, 0), Vector3(0.16, 0.016, l - 0.1), DARK)
	# Cross members under the deck, out to the rails.
	var z := zf + 0.3
	while z < zr - 0.2:
		_box("steel", Vector3(0.0, 1.21, z), Vector3(hw * 2.0 - 0.1, 0.06, 0.05), DARK)
		_box("steel", Vector3(0.0, 1.238, z), Vector3(hw * 2.0 - 0.1, 0.006, 0.09), DARK)
		z += 0.4
	# The upper coupler plate and the kingpin.
	_box("steel", Vector3(0.0, 1.245, -6.2), Vector3(1.8, 0.02, 2.0), Color(0.2, 0.2, 0.2))
	_cyl("steel", Vector3(0.0, 1.24, -6.4), Vector3(0.0, 1.14, -6.4), 0.045, STEEL)
	_cyl("steel", Vector3(0.0, 1.17, -6.4), Vector3(0.0, 1.19, -6.4), 0.06, STEEL)
	# Glad hands and the electrical socket on the front, under the deck.
	for gx: float in [-0.25, -0.1]:
		_box("steel", Vector3(gx, 1.24, zf + 0.02), Vector3(0.06, 0.04, 0.05), RED if gx < -0.2 else Color(0.1, 0.25, 0.7))
	_cyl("rough", Vector3(0.12, 1.24, zf - 0.01), Vector3(0.12, 1.24, zf + 0.06), 0.045, RUBBER, 12)
	for s: float in [-1.0, 1.0]:
		_lamp(Vector3((hw - 0.08) * s, 1.38, zf - 0.006), 0.08, 0.04, Vector3.FORWARD, AMBER, RUBBER)
	# Landing gear: the outer legs, braced, with the crank and gearbox on
	# the curb side (the inner legs and feet go up and down: "legs").
	var lz := -4.8
	for s: float in [-1.0, 1.0]:
		var x := 0.95 * s
		_box("steel", Vector3(x, 0.86, lz), Vector3(0.13, 0.7, 0.13), GALV)
		_box("steel", Vector3(x, 1.16, lz), Vector3(0.2, 0.08, 0.22), GALV.darkened(0.2))
		_rod("steel", [Vector3(x, 0.62, lz + 0.05), Vector3(0.45 * s, 1.15, lz + 0.9)], 0.02, GALV)
		_rod("steel", [Vector3(x, 0.75, lz - 0.05), Vector3(0.45 * s, 1.18, lz - 0.55)], 0.02, GALV)
	_rod("steel", [Vector3(-0.95, 0.6, lz), Vector3(0.95, 1.05, lz)], 0.018, GALV)
	_rod("steel", [Vector3(0.95, 0.6, lz), Vector3(-0.95, 1.05, lz)], 0.018, GALV)
	_cyl("steel", Vector3(-0.95, 0.98, lz), Vector3(0.95, 0.98, lz), 0.025, GALV, 8)
	_box("steel", Vector3(1.1, 0.98, lz), Vector3(0.14, 0.2, 0.16), DARK)
	_rod("steel", [Vector3(1.17, 0.98, lz), Vector3(1.25, 0.98, lz), Vector3(1.25, 0.72, lz), Vector3(1.25, 0.72, lz + 0.25)], 0.014, GALV)
	_rod("rough", [Vector3(1.25, 0.72, lz + 0.25), Vector3(1.32, 0.72, lz + 0.25)], 0.02, RUBBER)
	# An underslung toolbox and two air tanks.
	_bev("steel", Vector3(-0.85, 1.0, -1.5), Vector3(0.28, 0.2, 0.6), 0.02, GALV)
	_bev("metal", Vector3(-1.13, 1.05, -1.5), Vector3(0.006, 0.03, 0.08), 0.004, CHROME)
	for az: float in [3.0, 3.5]:
		_cyl("steel", Vector3(-0.38, 1.0, az), Vector3(0.38, 1.0, az), 0.13, Color(0.75, 0.76, 0.77), 14)
	# Spread tandem: hangers, trailing arms, air bags, axle beams, brake
	# chambers.
	for az: float in [4.75, 6.0]:
		_drive_axle(az, 0.52, 0.92, 1.24, false)
		for s: float in [-1.0, 1.0]:
			_box("steel", Vector3(0.45 * s, 1.0, az - 0.55), Vector3(0.12, 0.35, 0.2), DARK)
	_cyl("steel", Vector3(-0.2, 0.92, 5.375), Vector3(0.2, 0.92, 5.375), 0.06, DARK, 10)
	# Mud flaps behind each axle, the rear bumper (red and white), tail lamps
	# in the sill, and the ID lamps.
	for s: float in [-1.0, 1.0]:
		_flap(0.92 * s, 6.65, 1.15, 0.62)
		_box("steel", Vector3(0.92 * s, 1.15, 6.65), Vector3(0.66, 0.04, 0.06), DARK)
		_box("steel", Vector3(0.9 * s, 0.85, zr - 0.15), Vector3(0.08, 0.6, 0.08), DARK)
	_box("steel", Vector3(0.0, 0.58, zr - 0.15), Vector3(2.2, 0.14, 0.12), DARK)
	var bt := -1.05
	var red := true
	while bt < 1.05:
		_plate("gloss", Vector3(bt + 0.075, 0.58, zr - 0.088), 0.15, 0.1, Vector3.BACK, RED if red else Color(0.95, 0.95, 0.92))
		red = not red
		bt += 0.15
	for s: float in [-1.0, 1.0]:
		for i in 3:
			_lamp(Vector3((hw - 0.15 - i * 0.16) * s, 1.37, zr + 0.002), 0.1, 0.1, Vector3.BACK, RED if i < 2 else AMBER, RUBBER, true)
	for i in 3:
		_lamp(Vector3((float(i) - 1.0) * 0.12, 1.37, zr + 0.002), 0.05, 0.03, Vector3.BACK, RED, RUBBER)
	_plate("gloss", Vector3(0.0, 1.2, zr - 0.02), 0.3, 0.15, Vector3.BACK, Color(0.92, 0.92, 0.88))
	_plate("gloss", Vector3(0.0, 1.2, zr - 0.018), 0.26, 0.03, Vector3.BACK, Color(0.12, 0.28, 0.2))
	# The moving part of the landing gear: inner legs, sand shoes.
	_part = "legs"
	for s: float in [-1.0, 1.0]:
		var x := 0.95 * s
		_box("steel", Vector3(x, 0.44, lz), Vector3(0.1, 0.72, 0.1), GALV.lightened(0.15))
		_box("steel", Vector3(x, 0.06, lz), Vector3(0.14, 0.06, 0.14), DARK)
		_bev("steel", Vector3(x, 0.02, lz), Vector3(0.16, 0.02, 0.16), 0.008, DARK)
	_part = ""


func _rollback() -> void:
	var hw := float(shape["width"]) * 0.5 - 0.02
	var fa := -3.5
	var wr := 0.42
	_cab({"hw": hw, "cz0": -2.95, "cz1": -1.25, "y0": 0.8, "roof": 2.6, "rake": 0.34, "floor": 0.85, "belt": 1.74,
		"door": 0.64, "steps": [0.45], "clutch": false, "trim": "#43464a", "dash": "#232427", "seat": "#2d2e31", "cloth": "#4f5359"})
	_nose({"hw": hw, "z0": -4.95, "hood_top": 1.52, "fa": fa, "wr": wr, "hood_w": 0.8, "style": "medium"})
	_frame(-4.6, 3.65, 0.95)
	_front_axle(fa, wr, 1.0, 0.95, -4.5, -3.0)
	_cyl("steel", Vector3(0, 0.55, -2.3), Vector3(0, 0.5, 1.2), 0.045, STEEL, 10)
	_drive_axle(1.35, wr, 0.86, 0.95)
	# Light bar on the roof: amber domes in a black housing on feet.
	_bev("rough", Vector3(0.0, 2.69, -2.2), Vector3(0.78, 0.05, 0.13), 0.03, DARK)
	for i in 6:
		var x := -0.62 + i * 0.248
		_bev("gloss", Vector3(x, 2.77, -2.2), Vector3(0.1, 0.05, 0.11), 0.04, AMBER if i % 2 == 0 else Color(0.95, 0.9, 0.8))
	for s: float in [-1.0, 1.0]:
		_box("steel", Vector3(0.6 * s, 2.63, -2.2), Vector3(0.06, 0.06, 0.2), DARK)
	# Tool boxes under the front of the deck: diamond plate, with latches.
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0.82 * s, 0.75, -0.25)
		_bev("steel", c, Vector3(0.31, 0.275, 0.65), 0.015, GALV)
		var face := Vector3(1.135 * s, 0.75, -0.25)
		_diamonds(face, Vector3.UP * 0.52, Vector3.BACK * 1.26, Vector3(s, 0, 0), GALV.lightened(0.1))
		for lz: float in [-0.65, 0.15]:
			_bev("metal", face + Vector3(0.008 * s, 0.17, lz + 0.25), Vector3(0.008, 0.03, 0.06), 0.005, CHROME)
		_box("steel", Vector3(1.13 * s, 0.75, -0.25), Vector3(0.006, 0.52, 0.006), DARK)
	# Fuel tank behind the cab on the driver's side, the exhaust pipe on the
	# other, and the battery box.
	_fuel_tank(-0.85, 0.55, -1.15, -0.6, 0.22)
	_cyl("steel", Vector3(0.75, 0.42, -2.6), Vector3(0.75, 0.42, 0.9), 0.05, STEEL, 8)
	_cyl("steel", Vector3(0.75, 0.42, -1.0), Vector3(0.75, 0.42, -0.4), 0.14, Color(0.7, 0.7, 0.72), 12)
	# The deck's controls behind the cab: a bank of levers with black
	# knobs, and a gauge.
	var cv := Vector3(-1.02, 1.05, -1.05)
	_bev("steel", cv, Vector3(0.06, 0.1, 0.18), 0.01, DARK)
	for i in 4:
		var lz := cv.z - 0.12 + i * 0.08
		_rod("metal", [Vector3(cv.x - 0.05, cv.y + 0.02, lz), Vector3(cv.x - 0.13, cv.y + 0.18, lz)], 0.008, CHROME)
		_bev("rough", Vector3(cv.x - 0.14, cv.y + 0.2, lz), Vector3(0.018, 0.022, 0.018), 0.016, RUBBER)
	_disc("gloss", Vector3(cv.x - 0.061, cv.y - 0.05, cv.z + 0.12), 0.03, Vector3.LEFT, Color(0.92, 0.92, 0.9), 12)
	# The tilt cylinders and the subframe the deck rides on.
	for s: float in [-1.0, 1.0]:
		_cyl("steel", Vector3(0.42 * s, 0.95, 0.2), Vector3(0.42 * s, 0.99, 1.4), 0.075, DARK, 10)
		_cyl("metal", Vector3(0.42 * s, 0.99, 1.4), Vector3(0.42 * s, 1.03, 2.4), 0.04, CHROME, 10)
		_box("steel", Vector3(0.52 * s, 1.0, 1.7), Vector3(0.1, 0.08, 4.0), DARK)
	# Fenders over the duals and their flaps, an underride bar, tail lamps.
	for s: float in [-1.0, 1.0]:
		var x0 := 0.56 * s
		var x1 := 1.18 * s
		_arch("gloss", 1.35, wr + 0.02, wr + 0.08, wr + 0.11, minf(x0, x1), maxf(x0, x1), 0.35, PI - 0.35, Color(0.04, 0.04, 0.045), 12)
		_flap(0.86 * s, 1.98, 0.95, 0.56)
		_box("steel", Vector3(0.45 * s, 0.6, 3.5), Vector3(0.08, 0.35, 0.08), DARK)
	_box("steel", Vector3(0, 0.45, 3.55), Vector3(2.0, 0.12, 0.1), DARK)
	_tail(3.66, 0.8, 1.0)
	# The deck itself (moves): a steel floor with tie-down slots, side rails
	# with stake pockets, a bevelled tail, the headboard with its light bar
	# and window grid, and the winch.
	_part = "deck"
	var floor_c := Color(0.24, 0.24, 0.25)
	_box("steel", Vector3(0.0, 1.16, 2.5), Vector3(2.3, 0.12, 6.1), floor_c)
	var z := -0.4
	while z < 5.4:
		_box("steel", Vector3(0.0, 1.222, z), Vector3(2.26, 0.006, 0.03), floor_c.lightened(0.12))
		z += 0.25
	for s: float in [-1.0, 1.0]:
		var p := 0.1
		while p < 5.3:
			_box("rough", Vector3(0.95 * s, 1.223, p), Vector3(0.05, 0.004, 0.16), RUBBER)
			p += 0.6
	for s: float in [-1.0, 1.0]:
		_box("paint", Vector3(1.17 * s, 1.17, 2.5), Vector3(0.07, 0.2, 6.1), paint)
		_box("paint", Vector3(1.2 * s, 1.26, 2.5), Vector3(0.03, 0.03, 6.1), paint.lightened(0.05))
		var p2 := 0.0
		while p2 < 5.4:
			_box("paint", Vector3(1.21 * s, 1.15, p2), Vector3(0.025, 0.12, 0.1), paint.darkened(0.25))
			p2 += 0.9
		_lamp(Vector3(1.21 * s, 1.12, 5.4), 0.08, 0.05, Vector3(s, 0, 0), RED, RUBBER)
		_lamp(Vector3(1.21 * s, 1.12, -0.3), 0.08, 0.05, Vector3(s, 0, 0), AMBER, RUBBER)
		# Long-runner rails under the deck, seen when it's tilted.
		_box("steel", Vector3(0.52 * s, 1.06, 2.5), Vector3(0.1, 0.08, 6.0), DARK)
		_lamp(Vector3(1.0 * s, 1.14, 5.56), 0.12, 0.06, Vector3.BACK, RED, RUBBER)
	z = 0.0
	while z < 5.4:
		_box("steel", Vector3(0, 1.06, z), Vector3(2.2, 0.06, 0.05), DARK)
		z += 0.6
	# A bevelled tail so a wheel can roll on.
	_prof("steel", -1.2, 1.2, Vector2(5.45, 1.1), Vector2(5.6, 1.1), Vector2(5.6, 1.12), Vector2(5.45, 1.22), floor_c)
	# Headboard: a frame with a grid over its window, lamps on top.
	var hb := -0.5
	_box("paint", Vector3(0.0, 1.27, hb), Vector3(2.4, 0.1, 0.1), paint)
	_box("paint", Vector3(0.0, 2.08, hb), Vector3(2.4, 0.1, 0.1), paint)
	for s: float in [-1.0, 1.0]:
		_box("paint", Vector3(1.15 * s, 1.67, hb), Vector3(0.1, 0.9, 0.1), paint)
	_box("steel", Vector3(0.0, 1.67, hb + 0.03), Vector3(2.2, 0.7, 0.01), Color(0.15, 0.15, 0.16))
	for i in 11:
		_box("steel", Vector3(-1.0 + i * 0.2, 1.67, hb - 0.01), Vector3(0.02, 0.72, 0.02), DARK)
	for i in 4:
		_box("steel", Vector3(0.0, 1.4 + i * 0.18, hb - 0.01), Vector3(2.2, 0.02, 0.02), DARK)
	_bev("rough", Vector3(0.0, 2.17, hb), Vector3(1.0, 0.05, 0.1), 0.03, DARK)
	for i in 5:
		_bev("gloss", Vector3(-0.8 + i * 0.4, 2.23, hb), Vector3(0.08, 0.04, 0.09), 0.035, AMBER)
	for s: float in [-1.0, 1.0]:
		_lamp(Vector3(0.9 * s, 1.95, hb + 0.06), 0.14, 0.08, Vector3.BACK, LAMP, RUBBER)
	# The winch at the foot of the headboard: drum with its cable wraps,
	# the hydraulic motor, and the hook stowed on the drum.
	_cyl("steel", Vector3(-0.35, 1.38, -0.32), Vector3(0.35, 1.38, -0.32), 0.14, DARK, 16)
	for i in 12:
		var wx := -0.3 + i * 0.055
		_cyl("steel", Vector3(wx, 1.38, -0.32), Vector3(wx + 0.045, 1.38, -0.32), 0.15, Color(0.3, 0.3, 0.31), 14)
	for s: float in [-1.0, 1.0]:
		_cyl("steel", Vector3(0.36 * s, 1.38, -0.32), Vector3(0.4 * s, 1.38, -0.32), 0.2, paint.darkened(0.2), 16)
	_cyl("steel", Vector3(0.4, 1.38, -0.32), Vector3(0.6, 1.38, -0.32), 0.09, Color(0.15, 0.15, 0.16), 12)
	_rod("steel", [Vector3(0.0, 1.52, -0.3), Vector3(0.0, 1.45, -0.12), Vector3(0.0, 1.28, -0.08)], 0.015, Color(0.3, 0.3, 0.31))
	_rod("steel", [Vector3(0.0, 1.28, -0.08), Vector3(0.0, 1.24, -0.03), Vector3(0.0, 1.27, 0.03), Vector3(0.0, 1.32, 0.02)], 0.018, Color(0.85, 0.6, 0.1))
	_part = ""


func _forklift() -> void:
	var yel := paint
	var dk := Color(0.13, 0.13, 0.14)
	# The frame: two side plates with the wheel openings, the operator's
	# floor, the hood over the engine (the seat sits on it), the counterweight.
	for s: float in [-1.0, 1.0]:
		var xo := 0.58 * s
		var xi := 0.5 * s
		_prof("paint", xi, xo, Vector2(-0.18, 0.24), Vector2(0.72, 0.24), Vector2(0.72, 0.86), Vector2(-0.2, 0.86), yel)
		_prof("paint", xi, xo, Vector2(-0.95, 0.66), Vector2(-0.18, 0.66), Vector2(-0.18, 0.86), Vector2(-0.95, 0.86), yel)
		# Fenders over the drive wheels.
		_arch("paint", -0.55, 0.33, 0.36, 0.4, minf(xi, xo), maxf(xi, xo), 0.3, PI - 0.25, yel, 12)
		_box("steel", Vector3(0.53 * s, 0.86, -0.55), Vector3(0.12, 0.02, 0.7), dk)
		# A step on the side, with tread.
		_tread(Vector3(0.55 * s, 0.35, -0.08), 0.12, 0.2, GALV)
	_box("steel", Vector3(0, 0.45, 0.25), Vector3(1.0, 0.42, 0.95), dk)
	# Operator's floor and the cowl in front of it.
	_tread(Vector3(0, 0.56, -0.25), 0.98, 0.5, Color(0.25, 0.25, 0.26))
	_plate("rough", Vector3(0, 0.575, -0.25), 0.7, 0.4, Vector3.UP, RUBBER)
	_prof("paint", -0.36, 0.36, Vector2(-0.75, 0.56), Vector2(-0.48, 0.56), Vector2(-0.52, 1.1), Vector2(-0.72, 1.08), yel, 0.04)
	_prof("rough", -0.5, 0.5, Vector2(-0.8, 0.3), Vector2(-0.48, 0.3), Vector2(-0.48, 0.57), Vector2(-0.8, 0.57), dk)
	# The display and key on the cowl's top, the horn button.
	_bev("gloss", Vector3(0.0, 1.11, -0.6), Vector3(0.12, 0.012, 0.07), 0.006, Color(0.02, 0.02, 0.025), Basis(Vector3.RIGHT, 0.4))
	_plate("gloss", Vector3(0.0, 1.122, -0.6), 0.14, 0.08, Vector3(0, 1, 0.4).normalized(), Color(0.15, 0.45, 0.3))
	_cyl("metal", Vector3(0.18, 1.08, -0.55), Vector3(0.18, 1.1, -0.53), 0.015, CHROME, 8)
	# Hood over the engine, seat on top with its belt and armrest.
	_prof("paint", -0.5, 0.5, Vector2(-0.05, 0.6), Vector2(0.72, 0.6), Vector2(0.72, 0.88), Vector2(-0.02, 0.88), yel, 0.03)
	_box("rough", Vector3(0.0, 0.88, 0.32), Vector3(0.9, 0.012, 0.75), dk)
	for i in 5:
		_box("rough", Vector3(0.0, 0.885, 0.0 + i * 0.03), Vector3(0.7, 0.008, 0.012), Color(0.02, 0.02, 0.02))
	var sp: Array = shape["seat"]
	var seat := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	var top := seat.y - 0.08
	_bev("steel", Vector3(0, (0.88 + top - 0.08) * 0.5, seat.z - 0.1), Vector3(0.2, maxf(0.02, (top - 0.08 - 0.88) * 0.5), 0.2), 0.01, dk)
	_bev("satin", Vector3(0, top - 0.04, seat.z - 0.15), Vector3(0.24, 0.05, 0.22), 0.04, Color(0.08, 0.08, 0.085))
	var back := Basis(Vector3.RIGHT, 0.18)
	var base := Vector3(0, top - 0.04, seat.z + 0.1)
	_bev("satin", base + back * Vector3(0, 0.27, 0.02), Vector3(0.23, 0.27, 0.06), 0.05, Color(0.08, 0.08, 0.085), back)
	for i in 4:
		_bev("satin", base + back * Vector3(0, 0.1 + i * 0.11, -0.04), Vector3(0.18, 0.004, 0.004), 0.002, Color(0.03, 0.03, 0.03), back)
	_bev("satin", Vector3(0.27, top + 0.14, seat.z - 0.05), Vector3(0.035, 0.03, 0.16), 0.025, Color(0.08, 0.08, 0.085))
	# The orange lap belt across the seat.
	_bev("rough", Vector3(0.0, top + 0.02, seat.z + 0.02), Vector3(0.24, 0.006, 0.025), 0.004, Color(0.95, 0.45, 0.08))
	# Pedals: inching, brake, accelerator.
	for pd: Array in [[-0.15, 0.0], [-0.02, 0.0], [0.13, 1.0]]:
		var px: float = pd[0]
		_bev("rough", Vector3(px, 0.64, -0.38), Vector3(0.045, 0.012, 0.07 if pd[1] > 0.5 else 0.05), 0.006, RUBBER, Basis(Vector3.RIGHT, 0.5))
	# Steering column to the wheel (the wheel itself is Car's), and the
	# hydraulic levers on the cowl's right with their black knobs.
	var st := _steering_xform()
	var col := st.basis.z
	_tube("satin", st.origin - col * 0.05, st.origin - col * 0.42, 0.035, dk, 10)
	_bev("satin", st.origin - col * 0.42, Vector3(0.08, 0.06, 0.08), 0.03, dk, st.basis)
	for i in 3:
		var lx := 0.22 + i * 0.06
		_rod("metal", [Vector3(lx, 1.02, -0.5), Vector3(lx, 1.2, -0.44)], 0.007, CHROME)
		_bev("rough", Vector3(lx, 1.22, -0.435), Vector3(0.018, 0.024, 0.018), 0.016, [RUBBER, RUBBER, Color(0.7, 0.08, 0.05)][i])
	_bev("rough", Vector3(0.28, 1.0, -0.52), Vector3(0.12, 0.04, 0.06), 0.015, dk)
	# The counterweight: a heavy rounded casting, with lamps, the tow pin
	# slot and the brand.
	_prof("paint", -0.58, 0.58, Vector2(0.7, 0.3), Vector2(1.36, 0.36), Vector2(1.3, 1.2), Vector2(0.72, 1.2), dk, 0.06)
	_bev("paint", Vector3(0, 1.2, 1.02), Vector3(0.54, 0.04, 0.31), 0.04, dk)
	_box("rough", Vector3(0, 0.55, 1.37), Vector3(0.18, 0.1, 0.04), Color(0.02, 0.02, 0.02))
	_cyl("steel", Vector3(0, 0.66, 1.33), Vector3(0, 0.44, 1.33), 0.025, CHROME, 8)
	for s: float in [-1.0, 1.0]:
		_lamp(Vector3(0.42 * s, 0.95, 1.335), 0.12, 0.08, Vector3(0, 0, 1).rotated(Vector3.RIGHT, 0.07), RED, RUBBER)
	_plate("paint", Vector3(0, 0.78, 1.348), 0.5, 0.1, Vector3(0, 0.07, 1).normalized(), yel)
	# The propane tank on its cradle behind the seat.
	var tz := 1.0
	_cyl("paint", Vector3(-0.38, 1.42, tz), Vector3(0.38, 1.42, tz), 0.17, Color(0.85, 0.86, 0.84), 18)
	for s: float in [-1.0, 1.0]:
		_cone("paint", Vector3(0.38 * s, 1.42, tz), Vector3(0.46 * s, 1.42, tz), 0.17, 0.08, Color(0.85, 0.86, 0.84), 18)
		_ring("steel", Vector3(0.22 * s, 1.42, tz), 0.168, 0.185, Vector3.RIGHT, dk, 18)
		_cyl("steel", Vector3(0.22 * s - 0.015, 1.42, tz), Vector3(0.22 * s + 0.015, 1.42, tz), 0.185, dk, 18)
		_box("steel", Vector3(0.22 * s, 1.27, tz), Vector3(0.04, 0.1, 0.3), dk)
	_cyl("metal", Vector3(0.45, 1.42, tz), Vector3(0.55, 1.42, tz), 0.03, Color(0.75, 0.6, 0.2), 8)
	_cyl("metal", Vector3(0.53, 1.42, tz), Vector3(0.53, 1.5, tz), 0.025, Color(0.75, 0.6, 0.2), 8)
	_rod("rough", [Vector3(0.53, 1.5, tz), Vector3(0.6, 1.45, tz - 0.1), Vector3(0.55, 1.0, tz - 0.25)], 0.012, RUBBER)
	# Overhead guard: posts leaning in a little, a frame and slats, a work
	# lamp at each corner and the beacon.
	var gt := 2.14
	for s: float in [-1.0, 1.0]:
		_rod("steel", [Vector3(0.53 * s, 0.86, -0.55), Vector3(0.52 * s, gt, -0.52)], 0.03, dk)
		_rod("steel", [Vector3(0.53 * s, 1.18, 0.75), Vector3(0.52 * s, gt, 0.72)], 0.03, dk)
		_box("steel", Vector3(0.52 * s, gt, 0.1), Vector3(0.07, 0.06, 1.32), dk)
	for zz: float in [-0.52, 0.72]:
		_box("steel", Vector3(0.0, gt, zz), Vector3(1.1, 0.06, 0.07), dk)
	for i in 8:
		_box("steel", Vector3(-0.42 + i * 0.12, gt + 0.01, 0.1), Vector3(0.05, 0.02, 1.24), dk)
	_rod("rough", [Vector3(-0.3, 1.9, 0.72), Vector3(-0.3, 1.95, 0.8), Vector3(0.3, 1.95, 0.8), Vector3(0.3, 1.9, 0.72)], 0.018, RUBBER)
	for s: float in [-1.0, 1.0]:
		_bev("rough", Vector3(0.5 * s, gt + 0.05, -0.55), Vector3(0.06, 0.05, 0.04), 0.02, dk)
		_lamp(Vector3(0.5 * s, gt + 0.05, -0.595), 0.09, 0.07, Vector3.FORWARD, LAMP, RUBBER)
		_bev("rough", Vector3(0.5 * s, gt + 0.05, 0.77), Vector3(0.06, 0.05, 0.04), 0.02, dk)
		_lamp(Vector3(0.5 * s, gt + 0.05, 0.815), 0.09, 0.07, Vector3.BACK, LAMP, RUBBER)
		# Mirrors on the front posts.
		_rod("steel", [Vector3(0.53 * s, 1.85, -0.53), Vector3(0.62 * s, 1.9, -0.53)], 0.008, dk)
		_bev("rough", Vector3(0.66 * s, 1.9, -0.53), Vector3(0.04, 0.06, 0.012), 0.01, RUBBER)
		_plate("metal", Vector3(0.66 * s, 1.9, -0.517), 0.07, 0.1, Vector3.BACK, MIRROR)
	_cyl("steel", Vector3(0.42, gt + 0.03, 0.66), Vector3(0.42, gt + 0.06, 0.66), 0.065, dk, 12)
	_cone("gloss", Vector3(0.42, gt + 0.06, 0.66), Vector3(0.42, gt + 0.17, 0.66), 0.06, 0.045, AMBER, 12)
	# Tilt cylinders from the frame to the mast.
	for s: float in [-1.0, 1.0]:
		_cyl("steel", Vector3(0.42 * s, 0.82, -0.45), Vector3(0.42 * s, 0.86, -0.7), 0.045, dk, 10)
	# Mast (tilts): two outer channels (a web and flanges), cross ties, the
	# lift cylinder's barrel, the tilt cylinders' rods.
	_part = "mast"
	for s: float in [-1.0, 1.0]:
		var x := 0.38 * s
		_box("steel", Vector3(x, 1.13, -0.9), Vector3(0.1, 2.05, 0.014), dk)
		for fz: float in [-0.84, -0.96]:
			_box("steel", Vector3(x, 1.13, fz), Vector3(0.1, 2.05, 0.014), dk)
		_box("steel", Vector3(x + 0.045 * s, 1.13, -0.9), Vector3(0.014, 2.05, 0.13), dk)
		_cyl("metal", Vector3(0.42 * s, 0.86, -0.7), Vector3(0.42 * s, 0.9, -0.83), 0.022, CHROME, 8)
	_box("steel", Vector3(0.0, 2.12, -0.9), Vector3(0.86, 0.08, 0.1), dk)
	_box("steel", Vector3(0.0, 0.25, -0.9), Vector3(0.86, 0.1, 0.1), dk)
	_box("steel", Vector3(0.0, 1.0, -0.86), Vector3(0.76, 0.06, 0.05), dk)
	_cyl("steel", Vector3(0.0, 0.3, -0.8), Vector3(0.0, 1.15, -0.8), 0.055, dk, 12)
	_rod("rough", [Vector3(0.08, 0.35, -0.76), Vector3(0.12, 0.6, -0.78), Vector3(0.12, 1.4, -0.8)], 0.012, RUBBER)
	# The inner mast (rises once the forks get near the top): channels, the
	# lift cylinder's chrome rod, the chain sheaves at the top.
	_part = "mast_inner"
	for s: float in [-1.0, 1.0]:
		_box("steel", Vector3(0.29 * s, 1.18, -0.97), Vector3(0.08, 1.95, 0.012), STEEL)
		_box("steel", Vector3(0.29 * s, 1.18, -0.92), Vector3(0.08, 1.95, 0.012), STEEL)
		_box("steel", Vector3(0.325 * s, 1.18, -0.945), Vector3(0.012, 1.95, 0.06), STEEL)
		_cyl("steel", Vector3(0.12 * s, 2.06, -0.82), Vector3(0.18 * s, 2.06, -0.82), 0.07, dk, 14)
	_box("steel", Vector3(0.0, 2.12, -0.95), Vector3(0.66, 0.07, 0.07), STEEL)
	_cyl("metal", Vector3(0.0, 1.15, -0.8), Vector3(0.0, 2.08, -0.8), 0.032, CHROME, 10)
	# Carriage, load backrest and the two forks (heel, shank and a tapered
	# blade), with the lift chains from the carriage up over the sheaves.
	_part = "forks"
	_box("steel", Vector3(0.0, 0.32, -1.03), Vector3(1.0, 0.36, 0.06), dk)
	for y: float in [0.16, 0.48]:
		_box("steel", Vector3(0.0, y, -1.07), Vector3(1.0, 0.04, 0.03), dk.lightened(0.05))
	for i in 6:
		_box("steel", Vector3(-0.45 + i * 0.18, 0.86, -1.03), Vector3(0.03, 0.72, 0.03), dk)
	_box("steel", Vector3(0.0, 1.2, -1.03), Vector3(1.0, 0.05, 0.05), dk)
	for s: float in [-1.0, 1.0]:
		_box("steel", Vector3(0.48 * s, 0.86, -1.03), Vector3(0.04, 0.72, 0.04), dk)
	for s: float in [-1.0, 1.0]:
		var x := 0.3 * s
		_box("steel", Vector3(x, 0.31, -1.085), Vector3(0.12, 0.54, 0.045), STEEL)
		_box("steel", Vector3(x, 0.5, -1.06), Vector3(0.13, 0.05, 0.05), STEEL.darkened(0.2))
		_box("steel", Vector3(x, 0.18, -1.06), Vector3(0.13, 0.04, 0.05), STEEL.darkened(0.2))
		# The heel: a rounded bend between the shank and the blade.
		_arch("steel", -1.12, 0.1, 0.0, 0.05, x - 0.06, x + 0.06, PI * 0.5, PI, STEEL, 4)
		_prof("steel", x - 0.06, x + 0.06, Vector2(-1.11, 0.0375), Vector2(-2.135, 0.055), Vector2(-2.135, 0.072), Vector2(-1.11, 0.0825), STEEL)
		_prof("steel", x - 0.06, x + 0.06, Vector2(-2.135, 0.055), Vector2(-2.135, 0.055), Vector2(-2.135, 0.072), Vector2(-2.135, 0.072), STEEL)
		# Chains: links up the carriage's back to the top of the mast.
		for i in 26:
			var cy := 0.55 + i * 0.065
			_box("steel", Vector3(0.12 * s, cy, -0.9), Vector3(0.03 if i % 2 == 0 else 0.018, 0.06, 0.012), Color(0.2, 0.2, 0.21))
	# The rollers that run in the mast.
	for s: float in [-1.0, 1.0]:
		for y: float in [0.2, 0.45]:
			_cyl("steel", Vector3(0.33 * s, y, -0.99), Vector3(0.36 * s, y, -0.99), 0.04, STEEL, 10)
	_part = ""

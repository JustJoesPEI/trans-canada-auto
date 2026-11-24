class_name TruckBuilder
extends RefCounted
## Builds the working vehicles' meshes (TruckModels "look"): a tractor unit,
## a flatbed trailer, a rollback tow truck, a forklift. Trucks are boxy, so
## they're made of blocks (boxes, and eight-cornered blocks for sloped
## hoods and raked windshields) and cylinders, in vertex colours on the
## same paint and glass materials as the cars.
##
## Working parts (a tow truck's deck, a forklift's forks and mast, a
## trailer's landing legs) are separate meshes, built where they sit at
## rest; Car moves them (Car.set_part_transform).
##
## Faces -Z (the front), wheels on the ground at y = 0.

var shape: Dictionary
var paint: Color
var dark := Color(0.08, 0.08, 0.085)
var chrome := Color(0.78, 0.79, 0.8)
var steel := Color(0.36, 0.37, 0.38)
var glass := Color(0.06, 0.08, 0.1)
var lamp := Color(1.0, 0.97, 0.86)
var amber := Color(1.0, 0.6, 0.1)
var red := Color(0.75, 0.05, 0.04)

var _body: MeshKit
var _win: MeshKit
var _parts := {}


func _init(truck_shape: Dictionary, body_colour: Color) -> void:
	shape = truck_shape
	paint = body_colour


## {"body": ArrayMesh, "parts": {name: ArrayMesh}}
func build() -> Dictionary:
	_body = MeshKit.new()
	_body.use_color = true
	_win = MeshKit.new()
	_win.use_color = true
	match str(shape.get("look", "")):
		"tractor":
			_tractor()
		"flat_trailer":
			_flat_trailer()
		"rollback":
			_rollback()
		"forklift":
			_forklift()
	var mesh := _body.commit(null, CarBuilder.paint_material(Color.WHITE))
	_win.commit(mesh, CarBuilder.material("glass"))
	var parts := {}
	for name: String in _parts:
		parts[name] = (_parts[name] as MeshKit).commit(null, CarBuilder.paint_material(Color.WHITE))
	return {"body": mesh, "parts": parts}


func _part(name: String) -> MeshKit:
	if not _parts.has(name):
		var k := MeshKit.new()
		k.use_color = true
		_parts[name] = k
	return _parts[name]


# --- building blocks ---------------------------------------------------------------------

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
	kit.color = colour
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		kit.quad_smooth(a + d0 * r, a + d1 * r, b + d1 * r, b + d0 * r, d0, d1, d1, d0, (d0 + d1).normalized())
		kit.tri(a, a + d0 * r, a + d1 * r, -axis)
		kit.tri(b, b + d1 * r, b + d0 * r, axis)


## A flat pane of glass on a face: four corners, slightly proud of it.
func _pane(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	_win.color = glass
	var o := out.normalized() * 0.012
	_win.quad(a + o, b + o, c + o, d + o, out)


# --- a cab and chassis, shared by the tractor and the tow truck -----------------------------

## Bumper, grille, hood, fenders, cab with glass, mirrors, steps.
## z0 is the front of the bumper; the cab runs from cab_z0 to cab_z1.
func _cab(z0: float, hood_top: float, cab_z0: float, cab_z1: float, roof: float, half_w: float, front_axle: float, wheel_r: float) -> void:
	var k := _body
	var hood_w := half_w * 0.86
	# Bumper.
	box(k, Vector3(0.0, 0.55, z0 + 0.12), Vector3(half_w * 2.0 - 0.04, 0.34, 0.24), chrome)
	# Grille, standing up at the front of the hood.
	var gz := z0 + 0.3
	profile(k, -hood_w * 0.62, hood_w * 0.62, Vector2(gz, 0.72), Vector2(gz + 0.12, 0.72), Vector2(gz + 0.14, hood_top - 0.02), Vector2(gz + 0.02, hood_top - 0.04), chrome)
	for i in 9:
		var y := 0.8 + (hood_top - 0.9) * float(i) / 8.0
		box(k, Vector3(0.0, y, gz - 0.005), Vector3(hood_w * 1.18, 0.035, 0.02), dark)
	# Hood: rises a little toward the cab and narrows at the top.
	profile(k, -hood_w, hood_w, Vector2(gz + 0.1, 0.75), Vector2(cab_z0, 0.8), Vector2(cab_z0, hood_top + 0.12), Vector2(gz + 0.12, hood_top), paint, 0.12)
	# Fenders over the front wheels.
	for s: float in [-1.0, 1.0]:
		var x_in := hood_w * s
		var x_out := (half_w - 0.02) * s
		var fz0 := front_axle - wheel_r - 0.25
		var fz1 := front_axle + wheel_r + 0.2
		var top := wheel_r * 2.0 + 0.12
		profile(k, minf(x_in, x_out), maxf(x_in, x_out), Vector2(fz0, top - 0.25), Vector2(fz1, top - 0.1), Vector2(fz1, top + 0.08), Vector2(fz0 + 0.3, top + 0.06), paint)
		# Headlights at the front of the fender.
		box(k, Vector3((half_w - 0.3) * s, top - 0.08, fz0 + 0.03), Vector3(0.36, 0.16, 0.06), lamp)
		box(k, Vector3((half_w - 0.08) * s, top - 0.08, fz0 + 0.06), Vector3(0.1, 0.1, 0.06), amber)
		# A step and the fuel tank under the cab door.
		box(k, Vector3((half_w - 0.25) * s, 0.55, cab_z0 + 0.55), Vector3(0.42, 0.05, 0.4), steel)
	# The cab: the windshield leans back.
	var belt := hood_top + 0.25
	var cab_w := half_w
	var rake := 0.32
	profile(k, -cab_w, cab_w, Vector2(cab_z0, 0.8), Vector2(cab_z1, 0.8), Vector2(cab_z1, roof), Vector2(cab_z0 + rake, roof), paint, 0.05)
	# Windshield (two panes) on the raked face.
	var wb := belt + 0.1
	var wt := roof - 0.1
	for s: float in [-1.0, 1.0]:
		var xa := 0.04 * s
		var xb := (cab_w - 0.16) * s
		var za := cab_z0 + rake * (wb - 0.8) / (roof - 0.8) - 0.002
		var zt := cab_z0 + rake * (wt - 0.8) / (roof - 0.8) - 0.002
		_pane(Vector3(xa, wb, za), Vector3(xb, wb, za), Vector3(xb * 0.98, wt, zt), Vector3(xa, wt, zt), Vector3(0, rake, -(roof - 0.8)))
	# Side windows and the door line.
	for s: float in [-1.0, 1.0]:
		var x := (cab_w - 0.002) * s
		var zf := cab_z0 + rake + 0.08
		var zb := lerpf(cab_z0, cab_z1, 0.72)
		_pane(Vector3(x, wb, zf), Vector3(x, wb, zb), Vector3(x, wt, zb), Vector3(x, wt, zf + 0.05), Vector3(s, 0, 0))
		box(k, Vector3(x, (0.8 + wb) * 0.5, zb + 0.02), Vector3(0.01, wb - 0.8, 0.02), paint.darkened(0.35))
		box(k, Vector3(x + 0.02 * s, wb - 0.25, zb - 0.18), Vector3(0.03, 0.04, 0.16), chrome)
		# Mirror on an arm.
		box(k, Vector3((cab_w + 0.18) * s, wb + 0.05, zf + 0.05), Vector3(0.36, 0.04, 0.04), chrome)
		box(k, Vector3((cab_w + 0.34) * s, wb + 0.05, zf + 0.05), Vector3(0.06, 0.42, 0.18), dark)
	# Rear window.
	_pane(Vector3(-cab_w * 0.6, wb + 0.05, cab_z1 + 0.002), Vector3(cab_w * 0.6, wb + 0.05, cab_z1 + 0.002),
		Vector3(cab_w * 0.6, wt - 0.05, cab_z1 + 0.002), Vector3(-cab_w * 0.6, wt - 0.05, cab_z1 + 0.002), Vector3.BACK)
	# Sun visor and the marker lights along the top of the windshield.
	box(k, Vector3(0.0, roof + 0.02, cab_z0 + rake - 0.12), Vector3(cab_w * 2.0 - 0.1, 0.05, 0.3), paint.darkened(0.2))
	for i in 5:
		box(k, Vector3((float(i) - 2.0) * 0.32, roof + 0.07, cab_z0 + rake - 0.2), Vector3(0.1, 0.05, 0.06), amber)


## Two frame rails from z0 to z1, their top at y.
func _frame(z0: float, z1: float, y: float, gap := 0.45) -> void:
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3(gap * s, y - 0.14, (z0 + z1) * 0.5), Vector3(0.1, 0.28, z1 - z0), dark)
	var z := z0 + 0.4
	while z < z1:
		box(_body, Vector3(0.0, y - 0.14, z), Vector3(gap * 2.0, 0.2, 0.08), dark)
		z += 1.1


## Tail lights at the back of a frame.
func _tail(z: float, y: float, half_w: float) -> void:
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3((half_w - 0.15) * s, y, z), Vector3(0.24, 0.12, 0.05), red)
		box(_body, Vector3((half_w - 0.4) * s, y, z), Vector3(0.12, 0.12, 0.05), amber)


## A fender and mud flap over a set of rear wheels.
func _rear_fender(z0: float, z1: float, top: float, x: float, w: float) -> void:
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3(x * s, top, (z0 + z1) * 0.5), Vector3(w, 0.05, z1 - z0), dark)
		box(_body, Vector3(x * s, top - 0.45, z1 + 0.03), Vector3(w, 0.8, 0.02), dark)


# --- the vehicles -------------------------------------------------------------------------

func _tractor() -> void:
	var hw := float(shape["width"]) * 0.5
	_cab(-3.6, 1.85, -1.6, 0.5, 3.05, hw, -2.7, 0.52)
	_frame(-3.3, 3.55, 1.02)
	# Fuel tanks and battery box under the cab.
	for s: float in [-1.0, 1.0]:
		cylinder(_body, Vector3(0.95 * s, 0.72, -1.55), Vector3(0.95 * s, 0.72, 0.25), 0.32, chrome, 16)
		# Exhaust stacks behind the cab.
		cylinder(_body, Vector3(1.0 * s, 1.05, 0.68), Vector3(1.0 * s, 3.7, 0.68), 0.085, chrome)
		box(_body, Vector3(1.0 * s, 2.0, 0.68), Vector3(0.24, 0.9, 0.24), chrome.darkened(0.15))
	# Fifth wheel: a dark plate with its slot, and the ramps behind it.
	box(_body, Vector3(0.0, 1.17, 2.2), Vector3(1.5, 0.1, 1.1), Color(0.12, 0.12, 0.12))
	box(_body, Vector3(0.0, 1.224, 2.55), Vector3(0.12, 0.012, 0.6), Color(0.02, 0.02, 0.02))
	for s: float in [-1.0, 1.0]:
		profile(_body, 0.15 * s if s > 0 else -0.7, 0.7 if s > 0 else -0.15, Vector2(2.75, 1.0), Vector2(3.25, 0.98), Vector2(3.25, 1.02), Vector2(2.75, 1.17), Color(0.12, 0.12, 0.12))
	# Air lines coiled behind the cab.
	cylinder(_body, Vector3(-0.3, 1.6, 0.62), Vector3(0.3, 1.6, 0.62), 0.05, Color(0.1, 0.25, 0.6))
	cylinder(_body, Vector3(-0.3, 1.45, 0.62), Vector3(0.3, 1.45, 0.62), 0.05, red)
	_rear_fender(1.0, 3.6, 1.2, 0.92, 0.62)
	_tail(3.58, 0.85, 1.0)


func _flat_trailer() -> void:
	var hw := float(shape["width"]) * 0.5
	var l := float(shape["length"])
	var wood := Color(0.48, 0.34, 0.2)
	# Deck boards and the steel rub rails down each side.
	box(_body, Vector3(0.0, 1.475, 0.0), Vector3(hw * 2.0 - 0.16, 0.05, l), wood)
	var z := -l * 0.5
	while z < l * 0.5:
		box(_body, Vector3(0.0, 1.502, z + 0.15), Vector3(hw * 2.0 - 0.17, 0.004, 0.01), wood.darkened(0.3))
		z += 0.3
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3((hw - 0.05) * s, 1.37, 0.0), Vector3(0.1, 0.26, l), paint)
		# Stake pockets along the rail.
		var p := -l * 0.5 + 0.6
		while p < l * 0.5:
			box(_body, Vector3((hw - 0.005) * s, 1.42, p), Vector3(0.02, 0.1, 0.12), paint.darkened(0.3))
			p += 0.92
	# Main beams: shallow over the tractor, deep behind it.
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3(0.45 * s, 1.3, -l * 0.25 - 0.15), Vector3(0.1, 0.18, l * 0.5 - 0.3), dark)
		profile(_body, 0.45 * s - 0.05, 0.45 * s + 0.05, Vector2(-3.4, 1.22), Vector2(l * 0.5 - 0.2, 1.05), Vector2(l * 0.5 - 0.2, 1.24), Vector2(-3.8, 1.24), dark)
	# Cross members under the deck.
	z = -l * 0.5 + 0.3
	while z < l * 0.5:
		box(_body, Vector3(0.0, 1.27, z), Vector3(hw * 2.0 - 0.2, 0.08, 0.06), dark)
		z += 0.6
	# Kingpin plate and the pin.
	box(_body, Vector3(0.0, 1.245, -6.2), Vector3(1.8, 0.02, 2.0), Color(0.2, 0.2, 0.2))
	cylinder(_body, Vector3(0.0, 1.24, -6.4), Vector3(0.0, 1.14, -6.4), 0.045, steel)
	# Suspension hangers over the tandem, a rear bumper and lights.
	for az: float in [4.75, 6.0]:
		for s: float in [-1.0, 1.0]:
			box(_body, Vector3(0.92 * s, 0.98, az), Vector3(0.12, 0.3, 0.2), dark)
		cylinder(_body, Vector3(-1.2, 0.52, az), Vector3(1.2, 0.52, az), 0.07, dark)
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3(0.9 * s, 0.85, l * 0.5 - 0.15), Vector3(0.08, 0.6, 0.08), dark)
		box(_body, Vector3(0.92 * s, 0.7, 6.65), Vector3(0.62, 0.7, 0.02), dark) # mud flaps
	box(_body, Vector3(0.0, 0.58, l * 0.5 - 0.15), Vector3(2.2, 0.14, 0.12), dark)
	_tail(l * 0.5 + 0.01, 1.34, hw + 0.1)
	# Landing legs (fold up when hitched): a tube each side with a foot.
	var legs := _part("legs")
	for s: float in [-1.0, 1.0]:
		box(legs, Vector3(0.95 * s, 0.75, -4.8), Vector3(0.13, 0.95, 0.13), steel)
		box(legs, Vector3(0.95 * s, 0.31, -4.8), Vector3(0.1, 0.5, 0.1), steel.lightened(0.15))
		box(legs, Vector3(0.95 * s, 0.035, -4.8), Vector3(0.3, 0.05, 0.3), dark)
	box(legs, Vector3(0.0, 0.9, -4.8), Vector3(1.9, 0.08, 0.08), steel)
	box(legs, Vector3(1.1, 0.95, -4.8), Vector3(0.22, 0.22, 0.12), dark) # the crank box


func _rollback() -> void:
	var hw := float(shape["width"]) * 0.5
	_cab(-4.95, 1.52, -2.95, -1.25, 2.6, hw - 0.02, -3.5, 0.42)
	_frame(-4.6, 3.65, 0.95)
	# Light bar on the roof.
	box(_body, Vector3(0.0, 2.68, -2.2), Vector3(1.5, 0.12, 0.25), dark)
	for s: float in [-1.0, -0.33, 0.33, 1.0]:
		box(_body, Vector3(0.6 * s, 2.69, -2.2), Vector3(0.28, 0.13, 0.26), amber)
	# Tool boxes under the front of the deck.
	for s: float in [-1.0, 1.0]:
		box(_body, Vector3(0.82 * s, 0.75, -0.25), Vector3(0.62, 0.55, 1.3), steel)
		box(_body, Vector3(1.135 * s, 0.75, -0.25), Vector3(0.01, 0.5, 1.2), steel.darkened(0.2))
		cylinder(_body, Vector3(0.8 * s, 0.6, -1.15), Vector3(0.8 * s, 0.6, -0.95), 0.25, chrome)
	# The tilt cylinders and the subframe the deck rides on.
	for s: float in [-1.0, 1.0]:
		cylinder(_body, Vector3(0.42 * s, 0.95, 0.2), Vector3(0.42 * s, 1.03, 2.4), 0.07, chrome)
	_rear_fender(0.8, 1.95, 1.0, 0.86, 0.6)
	_tail(3.66, 0.8, 1.0)
	# The deck itself (moves): steel floor, side rails, tail and headboard.
	var d := _part("deck")
	var floor_c := Color(0.22, 0.22, 0.23)
	box(d, Vector3(0.0, 1.16, 2.5), Vector3(2.4, 0.12, 6.1), floor_c)
	var z := -0.4
	while z < 5.5:
		box(d, Vector3(0.0, 1.222, z), Vector3(2.3, 0.006, 0.03), floor_c.lightened(0.15))
		z += 0.25
	for s: float in [-1.0, 1.0]:
		box(d, Vector3(1.17 * s, 1.17, 2.5), Vector3(0.07, 0.2, 6.1), paint)
		box(d, Vector3(1.17 * s, 1.08, 5.5), Vector3(0.1, 0.1, 0.1), red)
	# A bevelled tail so a wheel can roll on.
	profile(d, -1.2, 1.2, Vector2(5.45, 1.1), Vector2(5.6, 1.1), Vector2(5.6, 1.12), Vector2(5.45, 1.22), floor_c)
	box(d, Vector3(0.0, 1.67, -0.5), Vector3(2.4, 0.9, 0.1), paint)
	box(d, Vector3(0.0, 2.15, -0.5), Vector3(2.0, 0.1, 0.2), dark)
	for s: float in [-1.0, 1.0]:
		box(d, Vector3(0.7 * s, 2.21, -0.5), Vector3(0.3, 0.07, 0.18), amber)
	# The winch drum behind the headboard's foot.
	cylinder(d, Vector3(-0.35, 1.38, -0.32), Vector3(0.35, 1.38, -0.32), 0.14, dark)


func _forklift() -> void:
	var b := _body
	var yel := paint
	# Body and counterweight.
	profile(b, -0.56, 0.56, Vector2(-0.7, 0.3), Vector2(0.75, 0.3), Vector2(0.75, 0.86), Vector2(-0.55, 0.86), yel, 0.02)
	profile(b, -0.58, 0.58, Vector2(0.7, 0.32), Vector2(1.38, 0.38), Vector2(1.32, 1.22), Vector2(0.72, 1.22), Color(0.2, 0.2, 0.21), 0.06)
	# Wheel covers over the front wheels.
	for s: float in [-1.0, 1.0]:
		box(b, Vector3(0.48 * s, 0.72, -0.55), Vector3(0.26, 0.05, 0.75), dark)
	# Seat, steering column and wheel.
	box(b, Vector3(0.0, 0.98, 0.35), Vector3(0.48, 0.12, 0.45), dark)
	profile(b, -0.24, 0.24, Vector2(0.55, 1.0), Vector2(0.62, 1.0), Vector2(0.66, 1.55), Vector2(0.59, 1.55), dark)
	cylinder(b, Vector3(0.0, 0.88, -0.35), Vector3(0.0, 1.32, -0.18), 0.04, dark)
	cylinder(b, Vector3(0.0, 1.34, -0.2), Vector3(0.0, 1.38, -0.16), 0.18, dark, 16)
	# Overhead guard: four posts and a grid roof.
	for sx: float in [-1.0, 1.0]:
		for pz: float in [-0.52, 0.72]:
			box(b, Vector3(0.52 * sx, 1.5, pz), Vector3(0.06, 1.3, 0.06), dark)
	for gx in 5:
		box(b, Vector3(-0.52 + gx * 0.26, 2.14, 0.1), Vector3(0.04, 0.04, 1.32), dark)
	for gz in 2:
		box(b, Vector3(0.0, 2.14, -0.52 + gz * 1.24), Vector3(1.1, 0.05, 0.06), dark)
	box(b, Vector3(0.0, 1.25, 1.36), Vector3(0.3, 0.1, 0.03), amber) # beacon plate
	cylinder(b, Vector3(0.45, 2.16, 0.7), Vector3(0.45, 2.28, 0.7), 0.06, amber)
	# Mast (tilts): two outer uprights and their cross bars, the lift ram.
	var mast := _part("mast")
	for s: float in [-1.0, 1.0]:
		box(mast, Vector3(0.38 * s, 1.13, -0.9), Vector3(0.1, 2.05, 0.13), dark)
	box(mast, Vector3(0.0, 2.12, -0.9), Vector3(0.86, 0.08, 0.1), dark)
	box(mast, Vector3(0.0, 0.25, -0.9), Vector3(0.86, 0.1, 0.1), dark)
	cylinder(mast, Vector3(0.0, 0.3, -0.84), Vector3(0.0, 1.9, -0.84), 0.05, chrome)
	# Inner mast (rises once the forks get near the top).
	var inner := _part("mast_inner")
	for s: float in [-1.0, 1.0]:
		box(inner, Vector3(0.29 * s, 1.18, -0.97), Vector3(0.08, 1.95, 0.08), steel)
	box(inner, Vector3(0.0, 2.12, -0.97), Vector3(0.66, 0.07, 0.07), steel)
	# Carriage, backrest and the two forks.
	var f := _part("forks")
	box(f, Vector3(0.0, 0.32, -1.03), Vector3(1.0, 0.36, 0.06), dark)
	for i in 6:
		box(f, Vector3(-0.45 + i * 0.18, 0.86, -1.03), Vector3(0.03, 0.72, 0.03), dark)
	box(f, Vector3(0.0, 1.2, -1.03), Vector3(1.0, 0.05, 0.05), dark)
	for s: float in [-1.0, 1.0]:
		box(f, Vector3(0.3 * s, 0.31, -1.085), Vector3(0.12, 0.54, 0.045), steel)
		box(f, Vector3(0.3 * s, 0.06, -1.6), Vector3(0.12, 0.045, 1.07), steel)

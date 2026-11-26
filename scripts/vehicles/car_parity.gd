class_name CarParity
extends RefCounted
## Checks the native car physics (TcaCar) against the GDScript it replaces
## (Car._springs_and_tyres_gd), for tools/native_check.gd: while `on`, each
## car's step runs both from the same state, keeping the forces each would
## apply rather than applying them, compares everything (the forces, every
## per-wheel array, the engine and ground values), and then applies the
## native version's forces. The first difference is kept in `first` (and
## printed). `-- --car-parity` turns it on for any tool.

static var on := OS.get_cmdline_user_args().has("--car-parity")
static var steps := 0
static var differences := 0
static var first := ""

const ARRAYS := ["_hits", "_loads", "_anchor", "_anchor_on", "_compress", "_wheel_drop", "_ground_y", "_kind", "_sink", "_wheel_spin", "_slide"]
const VALUES := ["wheels_down", "skid", "rpm", "gear", "_shift_timer", "ground", "ground_soft", "bogged", "dirt", "dirt_colour"]


static func step(car: Car, delta: float, found: Array, legs_down: bool) -> void:
	var before := _state(car)
	# The GDScript version, its forces kept.
	car._forces_out = []
	car._springs_and_tyres_gd(delta, found, legs_down)
	var gd_forces: Array = car._forces_out
	car._forces_out = null
	var gd_state := _state(car)
	# Back as it was, in place (the native version holds the same arrays).
	_restore(car, before)
	# The native version, its forces kept.
	car._native.call("set_recording", true)
	car._native.call("step", delta, found, legs_down)
	car._native.call("set_recording", false)
	var nat_forces: Array = car._native.call("take_forces")
	var nat_state := _state(car)
	steps += 1
	var diff := _compare(gd_forces, nat_forces, gd_state, nat_state)
	if diff != "":
		differences += 1
		if first == "":
			first = "%s at %s after %d steps: %s" % [car.name, car.global_position, steps, diff]
			print("CARPARITY first difference: ", first)
	# What the native version worked out, applied.
	for f: Array in nat_forces:
		match str(f[0]):
			"force":
				car.apply_force(f[1], f[2])
			"on":
				(f[3] as RigidBody3D).apply_force(f[1], f[2])
			"central":
				car.apply_central_force(f[1])
	car._tyre_fx()


static func _state(car: Car) -> Dictionary:
	var s := {}
	for a: String in ARRAYS:
		s[a] = (car.get(a) as Array).duplicate()
	for v: String in VALUES:
		s[v] = car.get(v)
	return s


static func _restore(car: Car, s: Dictionary) -> void:
	for a: String in ARRAYS:
		var arr: Array = car.get(a)
		var was: Array = s[a]
		for i in arr.size():
			arr[i] = was[i]
	for v: String in VALUES:
		car.set(v, s[v])


static func _compare(gf: Array, nf: Array, gs: Dictionary, ns: Dictionary) -> String:
	if gf.size() != nf.size():
		return "%d forces against %d" % [gf.size(), nf.size()]
	for i in gf.size():
		if not _same(gf[i], nf[i]):
			return "force %d: %s against %s" % [i, gf[i], nf[i]]
	for k: String in gs:
		if not _same(gs[k], ns[k]):
			return "%s: %s against %s" % [k, gs[k], ns[k]]
	return ""


## Exactly the same (NAN the same as NAN; a ray hit by what's in it).
static func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float and is_nan(a) and is_nan(b):
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		return a == b
	if typeof(a) != typeof(b):
		# An int against the same float (a property set from C++).
		if (a is int or a is float) and (b is int or b is float):
			return float(a) == float(b)
		return false
	return a == b

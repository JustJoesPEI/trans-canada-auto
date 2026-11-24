class_name ForkliftTool
extends VehicleTool
## A forklift's mast: the forks go up and down the mast, and the whole mast
## tilts forward (to slide under a load or set it down) and back (to cradle
## it while driving).
##
## The forks and the carriage behind them are real collision on the
## forklift's body, so a pallet is picked up by being pushed up from
## underneath, sits on the forks by friction, and its weight bears on the
## front axle. Lift too much and the counterweight can't hold it: the back
## wheels go light and it noses over, as a real one would.

var lift := 0.0 ## m the forks are above their lowest
var tilt := 0.0 ## radians, + is tilted back

var _pivot := Vector3.ZERO
var _max_lift := 3.0
var _lift_speed := 0.4
var _tilt_fwd := 0.1
var _tilt_back := 0.17
var _tilt_speed := 0.07
var _capacity := 2300.0
var _lift_rate := 0.0 # m/s the forks are moving now (eased)
var _tilt_rate := 0.0
## Lowering is quicker than lifting: the load's weight pushes the oil out.
const LOWER_SPEED := 1.3


func setup(owner_car: Car) -> void:
	super.setup(owner_car)
	var f: Dictionary = car.shape["forklift"]
	var p: Array = f["pivot"]
	_pivot = Vector3(p[0], p[1], p[2])
	_max_lift = float(f["max_lift"])
	_lift_speed = float(f["lift_speed"])
	_tilt_fwd = deg_to_rad(float(f["tilt_forward"]))
	_tilt_back = deg_to_rad(float(f["tilt_back"]))
	_tilt_speed = deg_to_rad(float(f["tilt_speed"]))
	_capacity = float(f.get("capacity", 2300.0))


func mast_xform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _pivot) * Transform3D(Basis(Vector3.RIGHT, tilt), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_pivot)


func physics(delta: float) -> void:
	var up := _axis("work_down", "work_up")
	var back := _axis("aux_out", "aux_in")
	var want_lift := up * _lift_speed * (LOWER_SPEED if up < 0.0 else 1.0)
	_lift_rate = ease_rate(_lift_rate, want_lift, _lift_speed, delta)
	_tilt_rate = ease_rate(_tilt_rate, back * _tilt_speed, _tilt_speed, delta)
	if _lift_rate == 0.0 and _tilt_rate == 0.0:
		return
	var new_lift := clampf(lift + _lift_rate * delta, 0.0, _max_lift)
	if new_lift != lift + _lift_rate * delta and _lift_rate != 0.0:
		# At the top or bottom of the mast.
		_lift_rate = 0.0
		stops += 1
	var new_tilt := clampf(tilt + _tilt_rate * delta, -_tilt_fwd, _tilt_back)
	if new_tilt != tilt + _tilt_rate * delta and _tilt_rate != 0.0:
		_tilt_rate = 0.0
		stops += 1
	lift = new_lift
	tilt = new_tilt
	_place()


func _place() -> void:
	var mast := mast_xform()
	car.set_part_transform("mast", mast)
	car.set_part_transform("forks", mast * Transform3D(Basis.IDENTITY, Vector3(0.0, lift, 0.0)))
	# The inner mast rises with the forks once they're past the top of the outer one.
	car.set_part_transform("mast_inner", mast * Transform3D(Basis.IDENTITY, Vector3(0.0, maxf(0.0, lift - 0.9), 0.0)))


## Set the forks directly (for tests and placing a forklift).
func set_pose(new_lift: float, new_tilt_degrees: float) -> void:
	lift = clampf(new_lift, 0.0, _max_lift)
	tilt = clampf(deg_to_rad(new_tilt_degrees), -_tilt_fwd, _tilt_back)
	_lift_rate = 0.0
	_tilt_rate = 0.0
	_place()


func motion() -> float:
	return clampf(maxf(absf(_lift_rate) / _lift_speed * (0.6 if _lift_rate < 0.0 else 1.0), absf(_tilt_rate) / _tilt_speed * 0.7), 0.0, 1.0)


## What's sitting on the forks: {"mass": kg, "names": [...]} of the loads
## resting on the tines (not one they're merely pushing along the ground).
func load_on_forks() -> Dictionary:
	var out := {"mass": 0.0, "count": 0, "name": ""}
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	# Over the tines, from just above them up a load's height.
	box.size = Vector3(1.0, 0.25, 1.1)
	q.shape = box
	q.collision_mask = Layers.CARGO
	var forks := car.global_transform * mast_xform() * Transform3D(Basis.IDENTITY, Vector3(0.0, lift, 0.0))
	q.transform = Transform3D(forks.basis, forks * Vector3(0.0, 0.2, -1.6))
	var seen := {}
	for r: Dictionary in space.intersect_shape(q, 32):
		var b := r["collider"] as RigidBody3D
		# (One entry per collision box, and a pallet has several.)
		if b == null or b.freeze or seen.has(b):
			continue
		seen[b] = true
		# Riding on the forks: lifted clear of the ground with them.
		if lift < 0.04:
			continue
		out["mass"] = float(out["mass"]) + b.mass
		out["count"] = int(out["count"]) + 1
		out["name"] = (b as Cargo).display_name() if b is Cargo else "load"
	return out


## The back wheels have lifted: the load is tipping it onto its nose.
func tipping() -> bool:
	for i in car._n:
		if not car._is_front[i] and car._hits[i] != null:
			return false
	return true


func capacity() -> float:
	return _capacity


func controls() -> Array:
	return [[["work_up", "work_down"], "forks up / down"], [["aux_in", "aux_out"], "tilt back / forward"]]


func status() -> String:
	var s := "Forks %.1f m" % lift
	if absf(rad_to_deg(tilt)) >= 0.5:
		s += ", tilted %s %.0f°" % ["back" if tilt > 0.0 else "forward", absf(rad_to_deg(tilt))]
	var l := load_on_forks()
	if int(l["count"]) > 0:
		var kg := float(l["mass"])
		s += "  ·  %s, %s kg" % [str(l["name"]) if int(l["count"]) == 1 else "%d loads" % int(l["count"]), _thousands(kg)]
		if kg > _capacity:
			s += "  ·  OVER ITS %s kg RATING" % _thousands(_capacity)
	if tipping():
		s += "  ·  TIPPING: lower the load"
	return s


static func _thousands(kg: float) -> String:
	var n := roundi(kg)
	return "%d,%03d" % [n / 1000, n % 1000] if n >= 1000 else str(n)

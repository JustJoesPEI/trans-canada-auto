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


func mast_xform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _pivot) * Transform3D(Basis(Vector3.RIGHT, tilt), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_pivot)


func physics(delta: float) -> void:
	var up := _axis("work_down", "work_up")
	var back := _axis("aux_out", "aux_in")
	if up == 0.0 and back == 0.0:
		return
	lift = clampf(lift + up * _lift_speed * delta, 0.0, _max_lift)
	tilt = clampf(tilt + back * _tilt_speed * delta, -_tilt_fwd, _tilt_back)
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
	_place()


func hint() -> String:
	return "R/G forks up/down  ·  Y/H tilt back/forward"


func status() -> String:
	return "Forks %.1f m, tilted %s%.0f°" % [lift, "back " if tilt > 0.001 else ("forward " if tilt < -0.001 else ""), absf(rad_to_deg(tilt))]

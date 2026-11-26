class_name Coupling
extends RefCounted
## Hitching a trailer to a tractor.
##
## The tractor's fifth wheel ("hitch" in its model) and the trailer's kingpin
## ("kingpin") are points on each body. Back the tractor under the trailer's
## nose until they line up and the jaws lock (or press the hitch key when
## close): the two are then joined by a physics joint at that point. A fifth
## wheel lets the trailer swing round freely and pitch over crests, but
## holds it against rolling, so a trailer leaning in a corner leans the
## tractor too. Jackknifing, the trailer cutting in on a tight turn, and a
## heavy load pushing the tractor on a downhill all come out of the physics.
##
## Coupled, the trailer's landing legs fold away and its brakes follow the
## tractor's (Car._read_controls).

## How close the kingpin has to be to the fifth wheel to couple (m).
const REACH := 0.35
const REACH_UP := 0.3
## The jaws lock by themselves as you back under, once the kingpin is this
## close front to back; the plate's V-shaped throat guides it in from as
## far as THROAT to either side.
const AUTO_LOCK := 0.12
const THROAT := 0.35


## The uncoupled trailer whose kingpin is nearest this tractor's fifth wheel,
## with how far off it is: {"trailer": Car, "gap": float, "rise": float},
## or {} if none is within `within` metres.
static func nearest(tractor: Car, within := 4.0) -> Dictionary:
	var hp: Variant = tractor.model_point("hitch")
	if hp == null or tractor.towing != null:
		return {}
	var kind := str(tractor.shape["hitch"].get("kind", ""))
	var best := {}
	var best_gap := within
	for t: Car in Car.couplers:
		if t == tractor or t.towed_by != null or not t.listed():
			continue
		var kp: Variant = t.model_point("kingpin")
		if kp == null or str(t.shape["kingpin"].get("kind", "")) != kind:
			continue
		var d: Vector3 = (kp as Vector3) - (hp as Vector3)
		var gap := Vector2(d.x, d.z).length()
		if gap < best_gap:
			best_gap = gap
			best = {"trailer": t, "gap": gap, "rise": d.y}
	return best


## Lock the jaws if the trailer's kingpin is over the fifth wheel.
## Returns true if it coupled.
static func try_couple(tractor: Car, reach := REACH) -> bool:
	var n := nearest(tractor)
	if n.is_empty() or absf(float(n["rise"])) > REACH_UP:
		return false
	var trailer: Car = n["trailer"]
	if reach <= AUTO_LOCK:
		# Backing under: in the throat, and right at the jaws front to back.
		var off := tractor.global_transform.basis.inverse() * ((trailer.model_point("kingpin") as Vector3) - (tractor.model_point("hitch") as Vector3))
		if absf(off.x) > THROAT or absf(off.z) > reach:
			return false
	elif float(n["gap"]) > reach:
		return false
	# Facing within a quarter turn of each other.
	if tractor.global_basis.z.dot(trailer.global_basis.z) < 0.5:
		return false
	couple(tractor, trailer)
	return true


## Backing under a trailer: over the last metre the plate's throat pushes
## the kingpin toward the slot (and the tractor the other way), so it
## arrives lined up. Called by the tractor each physics step while it
## reverses with nothing hitched.
static func guide(tractor: Car) -> void:
	var n := nearest(tractor)
	if n.is_empty() or float(n["gap"]) > 1.5 or absf(float(n["rise"])) > REACH_UP:
		return
	var trailer: Car = n["trailer"]
	var hp: Vector3 = tractor.model_point("hitch")
	var kp: Vector3 = trailer.model_point("kingpin")
	var off := tractor.global_transform.basis.inverse() * (kp - hp)
	# Only in the throat: behind the jaws (the pin still coming forward), within its width.
	if absf(off.x) > THROAT or off.z < -0.05 or off.z > 1.2:
		return
	var side := tractor.global_basis.x
	var v_rel := (trailer.linear_velocity - tractor.linear_velocity).dot(side)
	var m := trailer.mass * tractor.mass / (trailer.mass + tractor.mass)
	var push := side * (-off.x * m * 40.0 - v_rel * m * 8.0)
	trailer.apply_force(push, kp - trailer.global_position)
	tractor.apply_force(-push, hp - tractor.global_position)


static func couple(tractor: Car, trailer: Car) -> void:
	# The jaws close on the pin: bring it the last few centimetres over the
	# middle of the plate, so the joint holds it there and not off to one side.
	var hp: Vector3 = tractor.model_point("hitch")
	trailer.global_position += hp - (trailer.model_point("kingpin") as Vector3)
	trailer.reset_physics_interpolation()
	var j := Generic6DOFJoint3D.new()
	j.name = "Hitch"
	tractor.add_child(j)
	j.global_transform = Transform3D(tractor.global_basis, tractor.model_point("hitch"))
	# Fixed together at the point; free to swing round, a little pitch, and
	# almost no roll (a fifth wheel is a flat plate).
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-14.0))
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(14.0))
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-1.5))
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(1.5))
	j.exclude_nodes_from_collision = true
	j.node_a = j.get_path_to(tractor)
	j.node_b = j.get_path_to(trailer)
	tractor.towing = trailer
	tractor.dropped = null
	trailer.towed_by = tractor
	trailer.freeze = false
	tractor.hitched.emit(true)


static func uncouple(tractor: Car) -> void:
	var j := tractor.get_node_or_null("Hitch")
	if j != null:
		tractor.remove_child(j)
		j.queue_free()
	var was := tractor.towing
	if tractor.towing != null:
		tractor.towing.towed_by = null
	tractor.towing = null
	tractor.dropped = was
	if was != null:
		tractor.hitched.emit(false)

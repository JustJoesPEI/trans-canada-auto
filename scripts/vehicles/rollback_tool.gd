class_name RollbackTool
extends VehicleTool
## A rollback tow truck's deck and winch.
##
## The deck tilts back about the end of the frame and then slides back down
## its own length until its tail rests on the road, making a ramp. The deck
## is real collision: a car's wheels roll up it, and the car's weight goes
## into the truck (Car's wheels stand on other vehicles).
##
## The winch is a steel cable from the front of the deck to a car's tow
## point. It only pulls (a slack cable does nothing), as hard as the winch
## can (it stalls past WINCH_FORCE), and pulls the truck just as hard the
## other way. A hooked car has its brakes off so it rolls, as a tow driver
## would leave it in neutral.

const DECK_SPEED := 0.16 ## of the full travel per second (about six seconds down)
const TILT_PART := 0.3 ## the first part of the travel tilts, the rest slides
const WINCH_SPEED := 0.7 ## m/s reeling in
const PAYOUT_SPEED := 1.2 ## m/s paying out
const WINCH_FORCE := 55000.0 ## N the winch can pull before it stalls
const CABLE_K := 160000.0 ## N per metre of stretch
const HOOK_REACH := 16.0 ## m from the winch to something to hook

## 0 stowed (level, forward) to 1 all the way down.
var deck := 0.0
var hooked: RigidBody3D = null
var cable_length := 0.0
var tension := 0.0
## How fast the deck is moving now (of its travel per second, eased) and
## the drum turning (m/s of cable, + reeling in).
var _deck_rate := 0.0
var _reel_rate := 0.0
var _shown_tension := 0.0

var _pivot := Vector3.ZERO
var _slide := 3.0
var _tilt := 0.2 # radians, worked out so the tail reaches the road
var _winch_local := Vector3.ZERO # on the deck, in the truck's frame at rest
var _hook_local := Vector3.ZERO # on the hooked body
var _cable: MeshInstance3D


func setup(owner_car: Car) -> void:
	super.setup(owner_car)
	var rb: Dictionary = car.shape["rollback"]
	var p: Array = rb["pivot"]
	_pivot = Vector3(p[0], p[1], p[2])
	_slide = float(rb["slide"])
	var w: Array = rb["winch"]
	_winch_local = Vector3(w[0], w[1], w[2])
	# The tilt that puts the deck's tail just on the road once slid back.
	var dy := float(rb["deck_bottom"]) - _pivot.y
	var dz := float(rb["deck_rear"]) + _slide - _pivot.z
	var target := 0.03 - _pivot.y
	var t := 0.0
	for i in 40:
		# y(t) = dy cos t - dz sin t; Newton's method for y(t) = target.
		var y := dy * cos(t) - dz * sin(t)
		var dydt := -dy * sin(t) - dz * cos(t)
		t -= (y - target) / dydt
	_tilt = t
	_cable = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.19)
	mat.metallic = 0.6
	mat.roughness = 0.4
	cyl.material = mat
	_cable.mesh = cyl
	_cable.top_level = true
	_cable.visible = false
	car.add_child(_cable)


## The deck's transform from its rest position, for a travel of u (0..1).
func deck_xform(u: float) -> Transform3D:
	var tilt := _tilt * clampf(u / TILT_PART, 0.0, 1.0)
	var slide := _slide * clampf((u - TILT_PART) / (1.0 - TILT_PART), 0.0, 1.0)
	var about := Transform3D(Basis.IDENTITY, _pivot) * Transform3D(Basis(Vector3.RIGHT, tilt), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_pivot)
	return about * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, slide))


func winch_point() -> Vector3:
	return car.global_transform * (deck_xform(deck) * _winch_local)


func physics(delta: float) -> void:
	var move := _axis("work_up", "work_down")
	_deck_rate = ease_rate(_deck_rate, move * DECK_SPEED, DECK_SPEED, delta)
	if _deck_rate != 0.0:
		var want := deck + _deck_rate * delta
		deck = clampf(want, 0.0, 1.0)
		if deck != want:
			# Stowed, or the tail's on the road.
			_deck_rate = 0.0
			stops += 1
		car.set_part_transform("deck", deck_xform(deck))
	_winch(delta)


func _winch(delta: float) -> void:
	if hooked == null:
		tension = 0.0
		return
	if not is_instance_valid(hooked) or not hooked.is_inside_tree():
		_unhook()
		return
	var wp := winch_point()
	var hp := hooked.global_transform * _hook_local
	var span := hp - wp
	var d := span.length()
	var dir := span / maxf(d, 0.001) # from the winch toward the hook
	var lever := _axis("aux_out", "aux_in")
	_reel_rate = ease_rate(_reel_rate, lever * (WINCH_SPEED if lever > 0.0 else PAYOUT_SPEED), WINCH_SPEED, delta)
	var reel := _reel_rate / WINCH_SPEED if _reel_rate > 0.0 else _reel_rate / PAYOUT_SPEED
	if reel < 0.0:
		cable_length += PAYOUT_SPEED * -reel * delta
	var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	var v_hook := hooked.linear_velocity + hooked.angular_velocity.cross(hp - hooked.global_transform * hooked.center_of_mass)
	var v_rel := v_hook - state.get_velocity_at_local_position(wp - car.global_position)
	var stretch_rate := v_rel.dot(dir)
	var m := hooked.mass * car.mass / (hooked.mass + car.mass)
	var c := 2.0 * 0.7 * sqrt(CABLE_K * m)
	tension = 0.0
	if d > cable_length:
		tension = maxf(0.0, CABLE_K * (d - cable_length) + c * stretch_rate)
	if reel > 0.0 and tension < WINCH_FORCE * 0.95:
		cable_length = maxf(0.5, cable_length - WINCH_SPEED * reel * delta)
	if tension > WINCH_FORCE:
		# Stalled: the drum slips rather than pulling harder.
		tension = WINCH_FORCE
		cable_length = maxf(cable_length, d - WINCH_FORCE / CABLE_K)
	# What the HUD shows: steadied, so it reads like a gauge, not a flicker.
	_shown_tension = lerpf(_shown_tension, tension, 1.0 - exp(-delta / 0.4))
	if tension > 0.0:
		hooked.apply_force(-dir * tension, hp - hooked.global_position)
		car.apply_force(dir * tension, wp - car.global_position)


func _process(_delta: float) -> void:
	if hooked == null or not is_instance_valid(hooked):
		_cable.visible = false
		return
	var a := winch_point()
	var b := hooked.global_transform * _hook_local
	var span := b - a
	var l := span.length()
	if l < 0.01:
		_cable.visible = false
		return
	_cable.visible = true
	var y := span / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_cable.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


func holds_still() -> bool:
	return deck > 0.02


func hitch_action() -> String:
	if hooked != null:
		var what := _name_of(hooked)
		_unhook()
		return "Winch unhooked from the %s" % what
	var wp := winch_point()
	var best: RigidBody3D = null
	var best_local := Vector3.ZERO
	var best_d := HOOK_REACH
	var best_score := INF
	var too_big := ""
	var deck_len := float(car.shape["length"])
	var payload := float(car.spec["body"].get("payload", 4500.0))
	for n in car.get_tree().get_nodes_in_group("vehicles") + car.get_tree().get_nodes_in_group("cargo"):
		var b := n as RigidBody3D
		if b == null or b == car or (b is Car and (b as Car).driver != null) or b.freeze:
			continue
		for local: Vector3 in _tow_points(b):
			var p := b.global_transform * local
			# Behind the truck, roughly in line with the deck: what you've
			# backed up to, not something parked off to one side.
			var rel := car.global_transform.affine_inverse() * p
			if rel.z < -1.0 or absf(rel.x) > 2.5 + maxf(0.0, rel.z - 4.0) * 0.4:
				continue
			var d := p.distance_to(wp)
			if d > HOOK_REACH:
				continue
			if b is Car and (float((b as Car).shape["length"]) > deck_len * 0.7 or b.mass > payload * 1.2):
				# A trailer or another truck: far too big for the deck.
				too_big = (b as Car).display_name()
				continue
			var score := d + absf(rel.x) * 2.0
			if score < best_score:
				best_score = score
				best_d = d
				best = b
				best_local = local
	if best == null:
		if too_big != "":
			return "The %s is too big for the deck" % too_big
		return "Nothing to hook: back up within %d m of a car" % int(HOOK_REACH)
	hooked = best
	_hook_local = best_local
	cable_length = best_d + 0.05
	if hooked is Car:
		(hooked as Car).free_rolling = true
	return "Winch hooked to the %s" % _name_of(hooked)


func _unhook() -> void:
	if is_instance_valid(hooked) and hooked is Car:
		(hooked as Car).free_rolling = false
	hooked = null
	tension = 0.0
	_shown_tension = 0.0
	_reel_rate = 0.0


func motion() -> float:
	return clampf(absf(_deck_rate) / DECK_SPEED, 0.0, 1.0)


## The winch drum turning, 0 to 1 (either way).
func reel_motion() -> float:
	if hooked == null:
		return 0.0
	return clampf(absf(_reel_rate) / WINCH_SPEED, 0.0, 1.0)


## Where a cable can go on a body: a car's front and back tow eyes, a
## load's front and back.
func _tow_points(b: RigidBody3D) -> Array[Vector3]:
	if b is Car:
		var half := float((b as Car).shape["length"]) * 0.5
		return [Vector3(0.0, 0.4, -half + 0.1), Vector3(0.0, 0.4, half - 0.1)]
	if b is Cargo:
		var s := (b as Cargo).size
		return [Vector3(0.0, 0.15, -s.z * 0.5), Vector3(0.0, 0.15, s.z * 0.5)]
	return [Vector3.ZERO]


func _name_of(b: RigidBody3D) -> String:
	if b is Car:
		return (b as Car).display_name()
	if b is Cargo:
		return (b as Cargo).display_name()
	return "load"


func controls() -> Array:
	return [[["work_down", "work_up"], "deck down / up"], [["hitch"], "unhook the winch" if hooked != null else "hook the winch"],
		[["aux_in", "aux_out"], "winch in / out"], [["strap"], "strap the load / undo"], [["horn"], "horn", "pad"]]


func status() -> String:
	var s := "Deck stowed" if deck <= 0.0 else ("Deck down" if deck >= 1.0 else "Deck %d%%" % roundi(deck * 100.0))
	if hooked != null:
		s += "  ·  winch on the %s" % _name_of(hooked)
		if _shown_tension >= WINCH_FORCE * 0.97:
			s += ", STALLED: lighten the load"
		elif _shown_tension > 1500.0:
			s += ", pulling %.0f kN" % (_shown_tension / 1000.0)
	return s

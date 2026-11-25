class_name RollbackTool
extends VehicleTool
## A rollback tow truck's deck and winch.
##
## The deck tilts back about the end of the frame and then slides back down
## its own length until its tail rests on the road, making a ramp. The deck
## is real collision: a car's wheels roll up it, and the car's weight goes
## into the truck (Car's wheels stand on other vehicles).
##
## The winch is a steel cable (a TowLine) from the front of the deck to a
## car's tow point. It only pulls (a slack cable does nothing), as hard as
## the winch can (it stalls past WINCH_FORCE), and pulls the truck just as
## hard the other way. A hooked car has its brakes off so it rolls, as a
## tow driver would leave it in neutral.

const DECK_SPEED := 0.16 ## of the full travel per second (about six seconds down)
const TILT_PART := 0.3 ## the first part of the travel tilts, the rest slides
const WINCH_SPEED := 0.7 ## m/s reeling in
const PAYOUT_SPEED := 1.2 ## m/s paying out
const WINCH_FORCE := 55000.0 ## N the winch can pull before it stalls
const HOOK_REACH := 16.0 ## m from the winch to something to hook

## 0 stowed (level, forward) to 1 all the way down.
var deck := 0.0
## The winch cable, while it's hooked to something.
var line: TowLine = null
## What the cable's hooked to (null when it isn't).
var hooked: RigidBody3D:
	get:
		return line.other as RigidBody3D if line != null else null
## Tension in the cable (N).
var tension: float:
	get:
		return line.tension if line != null else 0.0
## How fast the deck is moving now (of its travel per second, eased).
var _deck_rate := 0.0

var _pivot := Vector3.ZERO
var _slide := 3.0
var _tilt := 0.2 # radians, worked out so the tail reaches the road
var _winch_local := Vector3.ZERO # on the deck, in the truck's frame at rest


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
	if line == null:
		return
	if not line.valid():
		_unhook()
		return
	# The cable leaves the drum on the deck, wherever the deck is now.
	line.a_local = deck_xform(deck) * _winch_local
	line.lever = _axis("aux_out", "aux_in")
	line.physics(delta)


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
	var best_score := INF
	var too_big := ""
	var deck_len := float(car.shape["length"])
	var payload := float(car.spec["body"].get("payload", 4500.0))
	for n in car.get_tree().get_nodes_in_group("vehicles") + car.get_tree().get_nodes_in_group("cargo"):
		var b := n as RigidBody3D
		if b == null or b == car or (b is Car and (b as Car).driver != null) or b.freeze:
			continue
		for local: Vector3 in Car.tow_points(b):
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
				best = b
				best_local = local
	if best == null:
		if too_big != "":
			return "The %s is too big for the deck" % too_big
		return "Nothing to hook: back up within %d m of a car" % int(HOOK_REACH)
	line = TowLine.make(car, deck_xform(deck) * _winch_local, best, best.global_transform * best_local)
	line.max_force = WINCH_FORCE
	line.reel_speed = WINCH_SPEED
	line.payout_speed = PAYOUT_SPEED
	if best is Car:
		(best as Car).free_rolling = true
	return "Winch hooked to the %s" % _name_of(best)


func _unhook() -> void:
	if line == null:
		return
	if is_instance_valid(line.other) and line.other is Car:
		(line.other as Car).free_rolling = false
	line.queue_free()
	line = null


func motion() -> float:
	return clampf(absf(_deck_rate) / DECK_SPEED, 0.0, 1.0)


## The winch drum turning, 0 to 1 (either way).
func reel_motion() -> float:
	if line == null:
		return 0.0
	return clampf(absf(line.reel_rate) / WINCH_SPEED, 0.0, 1.0)


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
		if line.shown_tension >= WINCH_FORCE * 0.97:
			s += ", STALLED: lighten the load"
		elif line.shown_tension > 1500.0:
			s += ", pulling %.0f kN" % (line.shown_tension / 1000.0)
	return s

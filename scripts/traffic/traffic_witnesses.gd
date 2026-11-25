class_name TrafficWitnesses
extends RefCounted
## Traffic drivers as witnesses. When the player paints someone or
## something, or takes a car, the traffic drivers who could see it
## (real cars near the player, a clear line from their seat) react like
## people: a moment later they brake, honk, some speed off, some stop and
## get out to look. A few of them "call it in": a few seconds later, if
## they can still see the player, they tell the police where (Wanted.
## witness_report), and the search goes there, not to where the player is
## by the time the police arrive. Getting out of their sight before then,
## or painting the witness's car, stops the call.
##
## Cheap: only physical traffic cars within SEE_RANGE of the crime are
## looked at, once per crime; a pending call checks its sight line twice a
## second.

## Drivers this close to a crime who can see it are witnesses (m).
const SEE_RANGE := 60.0
## A witness can keep the player in sight this far off (m).
const KEEP_RANGE := 120.0
## Share of witnesses who call it in, at most CALLERS_MAX per crime.
static var call_odds := 0.45
const CALLERS_MAX := 2
## Seconds from seeing it to getting through.
const CALL_DELAY := Vector2(3.0, 6.0)
## Reactions: share who speed off, share who stop and get out to look.
const FLEE_ODDS := 0.25
const OUT_ODDS := 0.15

var manager: TrafficManager
## Calls waiting to go through: {driver, at (where they last saw the
## player), due, check}.
var pending: Array[Dictionary] = []
## Counts, for tests: witnesses who saw a crime, calls made, calls stopped
## (lost sight, or scared off by paint).
var witnessed := 0
var calls := 0
var stopped := 0


func _init(m: TrafficManager) -> void:
	manager = m


## A crime by the player at `at` (kind as Wanted.report_crime).
func crime(kind: String, at: Vector3) -> void:
	var player := manager.player
	if player == null:
		return
	var callers := 0
	for d: TrafficDriver in manager.drivers:
		if d.car == null or d.state != TrafficDriver.State.DRIVE:
			continue
		if d.car == player.get("vehicle"):
			continue
		var eye := d.car.global_position + Vector3.UP * 1.2
		if eye.distance_to(at) > SEE_RANGE or not _clear(eye, at + Vector3.UP * 0.8, d.car):
			continue
		witnessed += 1
		_react(d)
		if callers < CALLERS_MAX and d.rng.randf() < call_odds:
			callers += 1
			var due := manager.clock() + d.rng.randf_range(CALL_DELAY.x, CALL_DELAY.y)
			pending.append({"driver": d, "at": _player_pos(), "due": due, "check": 0.0, "kind": kind})
			d.civil.hazard = "witness_calling"


## What a witness does, a human moment after seeing it.
func _react(d: TrafficDriver) -> void:
	var c := d.civil
	c.hazard = "witness"
	var r := d.rng.randf()
	if r < FLEE_ODDS:
		c.rush(1.4, 15.0)
		c._honk(0.6 + c.temper * 0.5)
	elif r < FLEE_ODDS + OUT_ODDS and not d.getting_out:
		d.getting_out = true
		c.hold_for(30.0, "witness", true)
	else:
		# Brake hard for a moment, and honk by temper.
		c.hold_for(c.reaction + d.rng.randf_range(0.8, 2.0), "startled")
		if d.rng.randf() < 0.3 + c.temper:
			c._honk(0.5 + c.temper * 0.6)


## The witness's car was painted: they're not calling anyone now.
func scared(d: TrafficDriver) -> void:
	for p: Dictionary in pending.duplicate():
		if p["driver"] == d:
			pending.erase(p)
			stopped += 1
			d.civil.hazard = "scared_off"


func tick(delta: float) -> void:
	if pending.is_empty():
		return
	var now := manager.clock()
	for p: Dictionary in pending.duplicate():
		var d: TrafficDriver = p["driver"]
		if d.car == null or not is_instance_valid(d.car) or d.state == TrafficDriver.State.GONE:
			pending.erase(p)
			continue
		p["check"] = float(p["check"]) - delta
		if float(p["check"]) <= 0.0:
			p["check"] = 0.5
			var pp := _player_pos()
			var eye := d.car.global_position + Vector3.UP * 1.2
			if eye.distance_to(pp) < KEEP_RANGE and _clear(eye, pp + Vector3.UP * 0.8, d.car):
				p["at"] = pp
				p["unseen"] = 0.0
			else:
				p["unseen"] = float(p.get("unseen", 0.0)) + 0.5
				if float(p["unseen"]) >= 1.0:
					# Out of their sight for a second: they lost you.
					pending.erase(p)
					stopped += 1
					d.civil.hazard = "lost_sight"
					continue
		if now >= float(p["due"]):
			pending.erase(p)
			calls += 1
			d.civil.hazard = "called_it_in"
			var w := manager.get_node_or_null("/root/Wanted")
			if w != null:
				w.call("witness_report", p["at"])


func _player_pos() -> Vector3:
	var pl := manager.player
	var v: Node3D = pl.get("vehicle")
	return v.global_position if v != null else pl.global_position


func _clear(from: Vector3, to: Vector3, car: Car) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	var ex: Array[RID] = [car.get_rid()]
	var pv: Variant = manager.player.get("vehicle")
	if pv is Car:
		ex.append((pv as Car).get_rid())
	q.exclude = ex
	return manager.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

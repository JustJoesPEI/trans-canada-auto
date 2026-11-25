class_name TrafficWitnesses
extends RefCounted
## Traffic drivers as witnesses. When the player paints someone or
## something, or takes a car, the traffic drivers who could see it
## (real cars near the player, a clear line from their seat) react like
## people: a moment later they brake (or, with someone close behind, ease
## off), honk, some speed off, some stop and get out to look. A few of them
## "call it in": finding the phone and getting through takes CALL_DELAY,
## and then they tell the police (Wanted.witness_report) where the crime
## was, or, if they lost sight of the player on the way, where they last
## saw them. Never the player's live position. Out of their sight within
## LOSE_WINDOW of the crime (off round a corner, out of KEEP_RANGE) and they
## don't call at all; painting the witness's car stops the call too.
##
## Cheap: only physical traffic cars within SEE_RANGE of the crime are
## looked at, once per crime; a pending call checks its sight line twice a
## second.

## Drivers this close to a crime who can see it are witnesses (m).
const SEE_RANGE := 60.0
## A witness can keep the player in sight this far off (m).
const KEEP_RANGE := 65.0
## Share of witnesses who call it in, at most CALLERS_MAX per crime.
static var call_odds := 0.45
const CALLERS_MAX := 2
## Seconds from seeing it to getting through.
const CALL_DELAY := Vector2(6.0, 10.0)
## Gone from their sight within this of the crime (s): no call.
const LOSE_WINDOW := 5.5
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
var _rng := RandomNumberGenerator.new()
var calls := 0
var stopped := 0


func _init(m: TrafficManager) -> void:
	manager = m
	_rng.randomize() # reactions vary crime to crime, not just driver to driver


## A crime by the player at `at` (kind as Wanted.report_crime); `target`
## (the car painted or taken) isn't its own witness.
func crime(kind: String, at: Vector3, target: Node = null) -> void:
	var player := manager.player
	if player == null:
		return
	var callers := 0
	for d: TrafficDriver in manager.drivers:
		if d.car == null or d.state != TrafficDriver.State.DRIVE:
			continue
		if d.car == player.get("vehicle") or d.car == target:
			continue
		var eye := d.car.global_position + Vector3.UP * 1.2
		if eye.distance_to(at) > SEE_RANGE or not _clear(eye, at + Vector3.UP * 0.8, d.car):
			continue
		witnessed += 1
		_react(d)
		if callers < CALLERS_MAX and _rng.randf() < call_odds:
			callers += 1
			var now := manager.clock()
			var due := now + _rng.randf_range(CALL_DELAY.x, CALL_DELAY.y)
			pending.append({"driver": d, "crime_at": at, "last_seen": _player_pos(), "lost": false, "since": now, "due": due, "check": 0.0, "kind": kind})
			d.civil.hazard = "witness_calling"


## What a witness does, a human moment after seeing it.
func _react(d: TrafficDriver) -> void:
	var c := d.civil
	c.hazard = "witness"
	var r := _rng.randf()
	if r < FLEE_ODDS:
		c.rush(1.4, 15.0)
		c._honk(0.6 + c.temper * 0.5)
	elif r < FLEE_ODDS + OUT_ODDS and not d.getting_out and not c.close_behind:
		d.getting_out = true
		c.hold_for(30.0, "witness", true)
	else:
		# Brake for a moment (or ease off, with someone close behind), and
		# honk by temper.
		c.startle(_rng.randf_range(0.8, 2.0))
		if _rng.randf() < 0.3 + c.temper:
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
			if bool(p["lost"]):
				pass # they've lost you: they'll say where they last saw you
			elif eye.distance_to(pp) < KEEP_RANGE and _clear(eye, pp + Vector3.UP * 0.8, d.car):
				p["last_seen"] = pp
				p["unseen"] = 0.0
			else:
				p["unseen"] = float(p.get("unseen", 0.0)) + 0.5
				if float(p["unseen"]) >= 1.0:
					if now - float(p["since"]) < LOSE_WINDOW:
						# Gone almost at once: nothing worth calling in.
						pending.erase(p)
						stopped += 1
						d.civil.hazard = "lost_sight"
						continue
					p["lost"] = true
		if now >= float(p["due"]):
			pending.erase(p)
			calls += 1
			d.civil.hazard = "called_it_in"
			var w := manager.get_node_or_null("/root/Wanted")
			if w != null:
				# Where they last saw you if they lost you, else where it happened.
				w.call("witness_report", p["last_seen"] if bool(p["lost"]) else p["crime_at"])


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

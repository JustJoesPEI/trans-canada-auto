class_name TrafficHeat
extends RefCounted
## How traffic takes a big police chase (Wanted level BIG_LEVEL and up, with
## sirens about). People hear it coming and get out of the way:
##
##   * some of the drivers ahead of the player, or near a siren, turn off:
##     they pick a driveway or lot just ahead (TrafficDestinations, the way
##     they're facing) and pull in there, and are taken away once nobody
##     can see them (some stay parked in it, if someone can). Each driver
##     decides once per chase (TURN_ODDS), so it's some, not all;
##   * fewer cars come out: the share of the cap eases down to
##     SHARE[level] (never below it: the streets thin, they don't empty),
##     and no new car is placed in the cone ahead of the player while it
##     lasts; the furthest ones ahead go first when there are too many;
##   * people on foot (traffic drivers out of their cars) scatter from
##     paintball fire nearby (TrafficBystander.scatter).
##
## It all eases back when the chase is over: the share climbs back up over
## a minute or so, and drivers placed afterwards drive as normal.

## Wanted level from which traffic clears out of the way.
const BIG_LEVEL := 3
## A siren car this close to the player makes it a big chase (m).
const SIREN_NEAR := 320.0
## Share of the usual traffic in a big chase, by Wanted level.
const SHARE := [1.0, 1.0, 1.0, 0.6, 0.45]
## How fast the share moves (per second): down quicker than back up.
const EASE_DOWN := 0.03
const EASE_UP := 0.012
## Share of drivers ahead (or near a siren) who turn off.
const TURN_ODDS := 0.5
## Ahead of the player: this far (m), within this cone (cos of half-angle).
const AHEAD_MIN := 35.0
const AHEAD_MAX := 260.0
const AHEAD_COS := 0.45
## A driver this close to a siren car turns off too, if it rolls to (m).
const SIREN_TURN := 140.0
## Where it turns in: a driveway this far (straight) ahead of it (m).
const TURN_IN := Vector2(18.0, 120.0)
## No new car placed ahead of the player this far in a big chase (m).
const NO_SPAWN_AHEAD := 360.0
## People on foot within this of a paintball landing scatter (m).
const SCATTER_RANGE := 16.0
const CHECK_EVERY := 0.5

var manager: TrafficManager
## In a big chase now.
var on := false
## Share of the usual traffic now (eases to SHARE[level] and back).
var share := 1.0
## Counts, for tests: drivers who turned off, ones who rolled and kept on,
## people who scattered.
var turned_off := 0
var kept_on := 0
var scattered := 0
var no_place := 0
## The player's heading on the ground (unit, or zero when barely moving).
var heading := Vector2.ZERO
var _check := 0.0
var _episode := 0
var _rolled := {} ## driver id -> episode it rolled in
var _sirens: Array[Vector2] = []


func _init(m: TrafficManager) -> void:
	manager = m


func tick(delta: float) -> void:
	var target: float = float(SHARE[mini(_level(), SHARE.size() - 1)]) if on else 1.0
	share = move_toward(share, float(target), (EASE_DOWN if float(target) < share else EASE_UP) * delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_EVERY
	var fp := _player_pos()
	var fp2 := Vector2(fp.x, fp.z)
	_sirens.clear()
	for c: Car in Car.all:
		if c.police != null and c.police.mode == PoliceGear.Mode.SIREN and c.listed():
			var q := Vector2(c.global_position.x, c.global_position.z)
			if q.distance_to(fp2) < SIREN_NEAR:
				_sirens.append(q)
	var was := on
	on = _level() >= BIG_LEVEL and not _sirens.is_empty()
	if on and not was:
		_episode += 1
	var v := _player_vel()
	heading = v.normalized() if v.length() > 6.0 else (heading if on else Vector2.ZERO)
	if on:
		_turn_offs(fp2)


## No new car here now (a big chase is coming this way).
func keep_clear(p: Vector2, fp2: Vector2) -> bool:
	if not on or heading == Vector2.ZERO:
		return false
	var rel := p - fp2
	var d := rel.length()
	return d < NO_SPAWN_AHEAD and rel.dot(heading) > d * AHEAD_COS


## How far "ahead of the chase" a point is, for picking which to take
## away first (bigger: sooner).
func ahead_score(p: Vector2, fp2: Vector2) -> float:
	if not on or heading == Vector2.ZERO:
		return 0.0
	var rel := p - fp2
	return maxf(0.0, rel.dot(heading) / maxf(rel.length(), 1.0)) * 150.0


func _turn_offs(fp2: Vector2) -> void:
	for d: TrafficDriver in manager.drivers:
		if d.car == null or d.pilot == null or d.state != TrafficDriver.State.DRIVE:
			continue
		if d.bus_route >= 0 or d.turned_in or int(_rolled.get(d.id, -1)) == _episode:
			continue
		var p := Vector2(d.car.global_position.x, d.car.global_position.z)
		var rel := p - fp2
		var dist := rel.length()
		var ahead := heading != Vector2.ZERO and dist > AHEAD_MIN and dist < AHEAD_MAX and rel.dot(heading) > dist * AHEAD_COS
		var by_siren := false
		for s in _sirens:
			by_siren = by_siren or s.distance_to(p) < SIREN_TURN
		if not ahead and not by_siren:
			continue
		_rolled[d.id] = _episode
		if d.rng.randf() >= TURN_ODDS:
			kept_on += 1
			continue
		var f3 := -d.car.global_basis.z
		var f := Vector2(f3.x, f3.z).normalized()
		var dest := manager.dests.pick(d.rng, p, TURN_IN.x, TURN_IN.y, f)
		if dest.is_empty():
			kept_on += 1
			no_place += 1
			continue
		turned_off += 1
		d.dest = dest
		manager._set_dest(d, dest)
		d.pilot.drive_to(d.dest3)
		d.civil.hazard = "sirens_turn_off"
		d.cleared_off = true


## A paintball landed at p (anything the player shot): people on foot near
## it run.
func shots_at(p: Vector3) -> void:
	for b: TrafficBystander in manager.bystanders():
		if b.global_position.distance_to(p) < SCATTER_RANGE and b.scatter(p):
			scattered += 1


func _level() -> int:
	var w := manager.get_node_or_null("/root/Wanted")
	return int(w.get("level")) if w != null else 0


func _player_pos() -> Vector3:
	return manager.focus_point()


func _player_vel() -> Vector2:
	var pl := manager.player
	if pl == null or not is_instance_valid(pl):
		return Vector2.ZERO
	var v: Variant = pl.get("vehicle")
	if v is Car:
		return (v as Car).plane_velocity
	var vel: Variant = pl.get("velocity")
	return Vector2((vel as Vector3).x, (vel as Vector3).z) if vel is Vector3 else Vector2.ZERO

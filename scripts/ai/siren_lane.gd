class_name SirenLane
extends RefCounted
## A car with its siren on (police chasing or responding) getting by the
## traffic that's stopped or pulled over for it: it moves out toward the
## middle of the road, or over it into the other lane (which pulls over
## too), past them at a speed it could stop from, and back in once by.
## Without it, a chase routed down the right-hand lane sits behind a queue
## at a red light, nosing at the bumpers in front.
##
## CarAutopilot uses it while the car's PoliceGear is on SIREN and civil
## driving is off: `lateral` (metres left of the route's line) shifts its
## aim, and `cap` (m/s) limits its speed past them.

const LOOK := 45.0
const SCAN_EVERY := 0.15
## The most it moves over (m).
const MOST := 5.0
## Past stopped traffic no faster than this plus GAP_SPEED per metre of
## room in front of what's being passed (m/s).
const PAST_SPEED := 7.0
const GAP_SPEED := 0.5

var lateral := 0.0
var cap := INF
## What it's going round (for tests and debugging).
var passing: Node3D = null
var _target := 0.0
var _scan := 0.0


func update(car: Car, route: StreetRoute, along: float, delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_look(car, route, along)
	lateral = move_toward(lateral, _target, 2.2 * delta)


func aim_shift(route: StreetRoute, at: float) -> Vector2:
	if absf(lateral) < 0.02:
		return Vector2.ZERO
	var d := route.dir_at(at)
	return Vector2(d.y, -d.x) * lateral


func _look(car: Car, route: StreetRoute, along: float) -> void:
	var hl := float(car.shape.get("length", 4.6)) * 0.5
	var hw := float(car.shape.get("width", 1.8)) * 0.5
	var me := Vector2(car.global_position.x, car.global_position.z)
	var v := maxf(car.speed, 0.0)
	var target := 0.0
	var lim := INF
	passing = null
	for u: RoadUsers.User in RoadUsers.near(car.get_tree(), me, LOOK):
		if u.node == car or u.person:
			continue
		if u.pos.distance_squared_to(me) > LOOK * LOOK:
			continue
		var au := route.project(u.pos, along, LOOK + 10.0)
		if au <= along - hl:
			continue
		# Moving along with us: the chase deals with it as it always has.
		if u.speed > maxf(3.0, v * 0.6):
			continue
		var p := route.sample(au)
		var dir := route.dir_at(au)
		var lat := (u.pos - p).dot(Vector2(dir.y, -dir.x))
		var reach := u.half_wid + hw + 0.5
		# In our way where we are, or where we'd be going round something else.
		if absf(lat - lateral) > reach and absf(lat - _target) > reach:
			continue
		var need := lat + u.half_wid + hw + 0.7
		if need > MOST:
			continue # no way round it on the left: the chase backs and turns as before
		target = maxf(target, need)
		var gap := au - along - hl - u.half_len
		lim = minf(lim, PAST_SPEED + GAP_SPEED * maxf(gap, 0.0))
		if passing == null:
			passing = u.node
	_target = target
	cap = lim

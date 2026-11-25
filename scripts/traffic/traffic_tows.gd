class_name TrafficTows
extends RefCounted
## Rollbacks for cars left dead in the street. A car that can't go on its
## own (stalled by paint, on its roof, or left by a driver who ran off), out
## on a street with nobody in it, gets a tow truck sent for it after a while:
##
##   * a traffic car: TRAFFIC_AFTER seconds (one nobody can see is just
##     taken away, as before);
##   * one of the player's (owner "local", or any car the player took and
##     left), stalled: PLAYER_AFTER seconds after they walked away from it,
##     and not while they're wanted (the police deal with that one:
##     PoliceDispatcher impounds a chase car). It goes to the impound lot
##     (ImpoundLot.impound) and the player has to go and get it back.
##
## The truck (TruckModels "rollback") is a traffic driver placed out of
## sight within the physics radius, which drives to the car by the streets
## and pulls up just past it. Then: the deck tilts and slides down
## (RollbackTool.deck_xform), the car is winched up onto it, the deck comes
## back up, and the truck drives off (towards the impound lot with the
## player's car) and is taken away once nobody can see it, the car with it.
## The winching is played, not simulated: the car is held (frozen, no
## collision) and moved along the ramp, and rides the deck from then on.
## If the player gets back into the car before it's on the deck, the tow's
## off: the truck drives away empty.
##
## A car away from the player, out of everyone's sight, is simply gone when
## its time's up (towed while nobody was looking).

## Seconds a dead car waits for its tow.
static var traffic_after := 25.0
static var player_after := 40.0
## The player has to be this far from their car for it to be left (m).
const LEFT_BY := 25.0
## Further than this from the player, a car due a tow is just taken away
## when nobody can see it (m).
const TOW_NEAR := 140.0
## Where the truck comes from: this far (straight) from the car, and from
## the player (m).
const FROM := Vector2(90.0, 200.0)
## A job not done in this long is given up (the truck drives off).
const GIVE_UP := 150.0
## The truck stops this far past the car's front (m): its deck's tail
## reaches the road about 8.5 m behind its middle.
const STOP_PAST := 9.0
## Seconds for the deck to go down (or up), and to winch the car on.
const DECK_TIME := 6.0
const WINCH_TIME := 7.0
const JOBS_MAX := 1
const SCAN_EVERY := 2.0

enum Step { SENT, LOWER, WINCH, RAISE, AWAY, DONE }


class Job:
	var car: Car
	var player_car := false
	var truck: TrafficDriver = null
	var step := Step.SENT
	var t := 0.0
	var age := 0.0
	## The car's place on the deck (in the deck's frame), once on.
	var on_deck := Transform3D.IDENTITY
	var from := Transform3D.IDENTITY
	var layers := 0
	var mask := 0
	var ride := 0.4
	var stop := Vector3.ZERO


var manager: TrafficManager
var jobs: Array[Job] = []
## Car -> seconds it has been dead and left.
var _dead := {}
var _scan := 0.0
## Counts, for tests: trucks sent, cars towed off, cars to the impound,
## jobs given up or called off, cars taken away unseen.
var sent := 0
var towed := 0
var impounded := 0
var called_off := 0
var quietly := 0


func _init(m: TrafficManager) -> void:
	manager = m


func tick(delta: float) -> void:
	for j: Job in jobs.duplicate():
		_work(j, delta)
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_EVERY
	var fp := manager.focus_point()
	var fp2 := Vector2(fp.x, fp.z)
	var seen_now := {}
	for car: Car in _candidates():
		seen_now[car] = true
		var t := float(_dead.get(car, 0.0)) + SCAN_EVERY
		_dead[car] = t
		var mine := _players(car)
		if t < (player_after if mine else traffic_after) or _job_for(car) != null:
			continue
		var p := Vector2(car.global_position.x, car.global_position.z)
		if p.distance_to(fp2) > TOW_NEAR:
			if not TrafficSight.seen(manager.get_tree(), car.global_position, fp):
				_take_away(car, mine)
				quietly += 1
				_dead.erase(car)
			continue
		if jobs.size() < JOBS_MAX:
			_send(car, mine, fp)
	for car: Variant in _dead.keys():
		if not seen_now.has(car):
			_dead.erase(car)


## Cars dead in the street, nobody in them.
func _candidates() -> Array[Car]:
	var out: Array[Car] = []
	var pl := manager.player
	var pv: Variant = pl.get("vehicle") if pl != null else null
	var wanted := manager.get_node_or_null("/root/Wanted")
	var level := int(wanted.get("level")) if wanted != null else 0
	for n: Node in manager.get_tree().get_nodes_in_group("vehicles"):
		var c := n as Car
		if c == null or c.driver != null or c == pv or c.police != null or TruckModels.MODELS.has(c.model_id):
			continue
		if manager._car_of.has(c):
			var d: TrafficDriver = manager._car_of[c]
			if d.truck or d.bus_route >= 0:
				continue
			if c.stalled or d.abandoned or d.upside_down > 3.0:
				out.append(c)
			continue
		if c.ai_controls != null or not c.stalled or level > 0:
			continue
		if pl != null and pl.global_position.distance_to(c.global_position) < LEFT_BY:
			continue
		var p := Vector2(c.global_position.x, c.global_position.z)
		var hit := manager.net.nearest_on_streets(p, 12.0)
		if hit.is_empty() or float(hit["dist"]) > (hit["edge"] as RoadNetwork.RoadEdge).half_width + 1.0:
			continue # in a lot or a driveway: not in anyone's way
		out.append(c)
	return out


## The player's own car (main.gd LOCAL_PLAYER_ID): to the impound. A car
## they took and left is towed off, not impounded in their name.
func _players(car: Car) -> bool:
	return car.owner_id == "local" and not manager._car_of.has(car)


func _job_for(car: Car) -> Job:
	for j: Job in jobs:
		if j.car == car:
			return j
	return null


## The truck the job's truck driver is (null once gone).
func _truck_car(j: Job) -> Car:
	if j.truck == null or j.truck.car == null or not is_instance_valid(j.truck.car):
		return null
	return j.truck.car


func _send(car: Car, mine: bool, fp: Vector3) -> void:
	var p := Vector2(car.global_position.x, car.global_position.z)
	var fp2 := Vector2(fp.x, fp.z)
	var radius := float(TrafficDensity.PHYSICS_RADIUS[TrafficDensity.level()])
	# A start out of sight, on a street near the car.
	var net := manager.net
	var edges := net.edges_near(Rect2(p - Vector2(FROM.y, FROM.y), Vector2(FROM.y, FROM.y) * 2.0))
	edges.shuffle()
	var tries := 0
	# Bigger streets first: a tow truck comes along the main roads.
	edges.sort_custom(func(a: RoadNetwork.RoadEdge, b: RoadNetwork.RoadEdge) -> bool: return TrafficDensity.class_weight(a) > TrafficDensity.class_weight(b))
	for e in edges:
		if TrafficDensity.class_weight(e) <= 0.0 or e.bridge or e.length < 24.0:
			continue
		var along := manager.rng.randf_range(8.0, e.length - 8.0)
		var sp: Array = RoadNetwork.sample(e.points, along)
		var q: Vector2 = sp[0]
		var dq := q.distance_to(p)
		if dq < FROM.x or dq > FROM.y or q.distance_to(fp2) < TrafficDensity.SPAWN_MIN or q.distance_to(fp2) > radius - 15.0:
			continue
		tries += 1
		if tries > 10:
			return # try again next scan
		# Whichever way along the street gets there sooner, by a fairly
		# direct route (a 10 m truck going round the houses gets stuck).
		var r: StreetRoute = null
		var dir := Vector2.ZERO
		var start := Vector2.ZERO
		for forward: bool in [true, false]:
			if (e.oneway == 1 and not forward) or (e.oneway == -1 and forward):
				continue
			var dv: Vector2 = (sp[1] as Vector2) * (1.0 if forward else -1.0)
			var st: Vector2 = q + Vector2(-dv.y, dv.x) * StreetRoute._lane_offset(e, forward)
			var rr := StreetRoute.plan(net, st, p, TrafficManager.plan_options(dv))
			if rr.is_empty() or rr.partial or rr.length > dq * 1.5 + 60.0:
				continue
			if r == null or rr.length < r.length:
				r = rr
				dir = dv
				start = st
		if r == null:
			continue
		var p3 := Vector3(start.x, manager.world.terrain.h2(start), start.y)
		if TrafficSight.seen(manager.get_tree(), p3, fp):
			continue
		# Pull up just past the car, the way the truck comes along.
		var h := r.dir_at(r.length)
		var half := float(car.shape.get("length", 4.6)) * 0.5
		var stop := p + h * (half + STOP_PAST)
		var j := Job.new()
		j.car = car
		j.player_car = mine
		j.stop = Vector3(stop.x, car.global_position.y, stop.y)
		var d := manager.spawn_tow(p3, dir, j.stop)
		if d == null:
			continue
		j.truck = d
		jobs.append(j)
		sent += 1
		if not mine:
			_claim(car)
		return


## A traffic car the tow's taken on: no longer its driver's.
func _claim(car: Car) -> void:
	var d: TrafficDriver = manager._car_of.get(car)
	if d == null:
		return
	manager._release_car(d)


## The truck's at the car (TrafficManager._car_arrived).
func arrived(d: TrafficDriver) -> void:
	for j: Job in jobs:
		if j.truck == d and j.step == Step.SENT:
			var truck := _truck_car(j)
			if truck == null or not is_instance_valid(j.car):
				_off(j)
				return
			# The car should be behind the truck, near enough in line.
			var rel := truck.global_transform.affine_inverse() * j.car.global_position
			if rel.z < 3.0 or rel.z > 22.0 or absf(rel.x) > 4.5:
				_off(j)
				return
			d.state = TrafficDriver.State.OUT # at work: not stuck, not driving
			d.civil.hold_for(600.0, "towing")
			d.civil.hazard = "towing"
			j.step = Step.LOWER
			j.t = 0.0
			return


func _work(j: Job, delta: float) -> void:
	j.age += delta
	var truck := _truck_car(j)
	if truck == null:
		# The truck's gone (taken away, or taken by the player).
		if j.step == Step.WINCH or j.step == Step.RAISE or j.step == Step.AWAY:
			_drop(j)
		jobs.erase(j)
		return
	if not is_instance_valid(j.car):
		_off(j)
		return
	if j.car.driver != null:
		# The player's back in it: tow's off (on the deck already, it's let
		# go there, and the deck holds it like any car on it).
		if j.step >= Step.WINCH:
			_drop(j)
		if j.step == Step.AWAY:
			jobs.erase(j)
			called_off += 1
		else:
			_off(j)
		return
	var tool := truck.tool as RollbackTool
	j.t += delta
	match j.step:
		Step.SENT:
			if j.age > GIVE_UP:
				_off(j)
		Step.LOWER:
			_deck(truck, tool, clampf(j.t / DECK_TIME, 0.0, 1.0))
			if j.t >= DECK_TIME:
				_hold(j)
				j.step = Step.WINCH
				j.t = 0.0
		Step.WINCH:
			# Up to the ramp's tail, then up the ramp to its place on the deck.
			var u := clampf(j.t / WINCH_TIME, 0.0, 1.0)
			var deck := truck.global_transform * tool.deck_xform(1.0)
			var tail := deck * Transform3D(Basis.IDENTITY, _tail_local(j, truck))
			var place := deck * j.on_deck
			var xf: Transform3D
			if u < 0.35:
				xf = j.from.interpolate_with(tail, smoothstep(0.0, 1.0, u / 0.35))
			else:
				xf = tail.interpolate_with(place, (u - 0.35) / 0.65)
			j.car.global_transform = xf
			if j.t >= WINCH_TIME:
				j.step = Step.RAISE
				j.t = 0.0
		Step.RAISE:
			var u := 1.0 - clampf(j.t / DECK_TIME, 0.0, 1.0)
			_deck(truck, tool, u)
			j.car.global_transform = truck.global_transform * tool.deck_xform(u) * j.on_deck
			if j.t >= DECK_TIME:
				j.step = Step.AWAY
				j.t = 0.0
				_drive_off(j)
		Step.AWAY:
			j.car.global_transform = truck.global_transform * tool.deck_xform(0.0) * j.on_deck


func _deck(truck: Car, tool: RollbackTool, u: float) -> void:
	tool.deck = u
	truck.set_part_transform("deck", tool.deck_xform(u))


## The car's held: no physics of its own, nothing to bump (and not on the
## road for anyone to drive round) until it's put down again.
func _hold(j: Job) -> void:
	var car := j.car
	j.from = car.global_transform
	j.layers = car.collision_layer
	j.mask = car.collision_mask
	car.collision_layer = 0
	car.collision_mask = 0
	car.freeze = true
	car.set_physics_process(false)
	car.remove_from_group("vehicles")
	# Its place on the deck: in line, its wheels on the deck's top.
	var rb: Dictionary = (_truck_car(j) as Car).shape["rollback"]
	var gy := manager._ground_at(car.global_position)
	j.ride = clampf(car.global_position.y - gy, 0.2, 0.8) if not is_nan(gy) and car.global_basis.y.y > 0.7 else 0.4
	var ride := j.ride
	var length := float(car.shape.get("length", 4.6))
	var deck_top := float(rb["deck_bottom"]) + 0.12
	var z := float(rb["deck_rear"]) - length * 0.5 - 0.4
	var turn := 0.0 if j.from.basis.z.dot(_truck_car(j).global_basis.z) > -0.2 else PI # front first or back first, as it was
	j.on_deck = Transform3D(Basis(Vector3.UP, turn), Vector3(0.0, deck_top + ride, z))


func _tail_local(j: Job, truck: Car) -> Vector3:
	var rb: Dictionary = truck.shape["rollback"]
	var length := float(j.car.shape.get("length", 4.6))
	return Vector3(0.0, float(rb["deck_bottom"]) + 0.12 + j.ride, float(rb["deck_rear"]) + length * 0.5)


## Let a held car go where it is now.
func _drop(j: Job) -> void:
	var car := j.car
	if not is_instance_valid(car):
		return
	car.collision_layer = j.layers
	car.collision_mask = j.mask
	car.set_physics_process(true)
	car.freeze = false
	if not car.is_in_group("vehicles"):
		car.add_to_group("vehicles")


func _drive_off(j: Job) -> void:
	var d := j.truck
	var truck := _truck_car(j)
	d.state = TrafficDriver.State.DRIVE
	d.civil.release_hold()
	d.civil.hazard = "towing_away"
	var p := Vector2(truck.global_position.x, truck.global_position.z)
	var f := -truck.global_basis.z
	var dest := {}
	if j.player_car:
		var lot := ImpoundLot.find(manager.get_tree())
		if lot != null:
			var lp := Vector2(lot.global_position.x, lot.global_position.z)
			dest = {"street": lp, "inside": lp, "kind": "impound"}
	if dest.is_empty():
		dest = manager.dests.pick(d.rng, p, 400.0, 1500.0, Vector2(f.x, f.z).normalized())
	if dest.is_empty():
		dest = {"street": p + Vector2(f.x, f.z) * 500.0, "inside": p, "kind": ""}
	manager._set_dest(d, dest)
	d.turned_in = true # no driveway: it's taken away once out of sight
	d.pilot.drive_to(d.dest3)


## The job's off: the truck drives away (empty).
func _off(j: Job) -> void:
	if j.step == Step.AWAY:
		return
	called_off += 1
	jobs.erase(j)
	j.step = Step.DONE
	var truck := _truck_car(j)
	if truck != null:
		var tool := truck.tool as RollbackTool
		if tool != null:
			_deck(truck, tool, 0.0)
		_drive_off_empty(j)
	if is_instance_valid(j.car) and not j.player_car:
		_dead.erase(j.car)


func _drive_off_empty(j: Job) -> void:
	var d := j.truck
	if d.pilot == null:
		return
	d.state = TrafficDriver.State.DRIVE
	d.civil.release_hold()
	var truck := d.car
	var p := Vector2(truck.global_position.x, truck.global_position.z)
	var f := -truck.global_basis.z
	var dest := manager.dests.pick(d.rng, p, 300.0, 1200.0, Vector2(f.x, f.z).normalized())
	if not dest.is_empty():
		manager._set_dest(d, dest)
		d.turned_in = true
		d.pilot.drive_to(d.dest3)


## The truck's being taken away (out of sight): the car on it goes too.
func truck_gone(d: TrafficDriver) -> void:
	for j: Job in jobs.duplicate():
		if j.truck != d:
			continue
		jobs.erase(j)
		if j.step == Step.AWAY and is_instance_valid(j.car):
			_drop(j)
			_take_away(j.car, j.player_car)
			towed += 1


## A car towed off: the player's to the impound lot, anyone else's just gone.
func _take_away(car: Car, mine: bool) -> void:
	_dead.erase(car)
	if mine:
		var lot := ImpoundLot.find(manager.get_tree())
		if lot != null:
			lot.impound(car)
			impounded += 1
			var hud := manager.hud
			if hud != null and hud.has_method("show_title"):
				hud.call("show_title", "Your %s was towed" % car.display_name(), "it's at the impound lot")
			return
	if manager._car_of.has(car):
		var d: TrafficDriver = manager._car_of[car]
		manager._remove(d, manager.focus_point())
		return
	manager._drop_car(car)
	car.queue_free()

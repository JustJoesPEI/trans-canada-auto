class_name TrafficBuses
extends RefCounted
## The town buses (Charlatown Transit, TruckModels "transit_bus") on the
## routes and stops of data/transit.json (TransitStops: modelled on T3
## Transit's Charlottetown routes), each given as the junctions it passes:
## out to the end and back. A bus stops only at a stop, and only when
## someone's waiting on its side of the street or someone on board wants
## off (OFF_ODDS); it pulls in to the curb and waits while they get on and
## off (CivilDriving.hold_for, aside: longer the more there are), then
## pulls out. The people waiting walk to its front door and get on
## (PedestrianManager, through waiting_hook and arrived_hook).
##
## Like the trucks, a bus is only ever a real vehicle near the player (it
## has no far version): when the player is within NEAR of a route and no
## bus on it is about, one is placed on the route out of sight within the
## physics radius, heading on to its next junction; it's
## taken away unseen once out of range. At most BUSES_MAX at once.
##
## A bus makes a very good wall: it's 12 m long, slow to get going, and
## other traffic queues behind it at stops (it isn't "waiting its turn",
## so they go round it when the other lane's clear).

const MODEL := "transit_bus"
const DWELL := Vector2(8.0, 14.0)
## At a stop: this long to open up and close again (s), and this much more
## for each person getting on or off.
const DWELL_BASE := 5.0
const DWELL_EACH := Vector2(2.2, 1.8)
const DWELL_MAX := 22.0
## It waits up to this much longer for people still walking up (s).
const WAIT_FOR_BOARDING := 20.0
## Share of stops where someone on board wants off, and how many.
const OFF_ODDS := 0.4
const OFF_MAX := 2
## A bus pulls in to the curb at a stop, across any lanes between (the
## curb lane of a four-lane street), stopping this far short of it (m): a
## bus's wheels on the curb tip it.
const CURB_GAP := 1.0
## A stop this close to a junction is moved on out of it (m).
const JUNCTION_CLEAR := 12.0
## Something at the curb at the sign (nobody parks at a stop:
## StreetProps keeps it clear, but a car left there, say): it looks this
## many times 15 m further on for free curb before stopping in the lane.
const CURB_SEARCH := 1
## It starts pulling in this far before a stop (m).
const PULL_AHEAD := 45.0
## A stop counts for a leg when the leg's line passes this close (m): the
## stop is on the street's middle, the line in the lane.
const ON_LEG := 11.0
## A route this close to the player gets a bus (m).
const NEAR := 320.0
const BUSES_MAX := 3
const CHECK_EVERY := 1.5

## How many are waiting at stop si on side s (PedestrianManager sets it).
static var waiting_hook := Callable()
## A bus has stopped at stop si, side s, with `off` getting off: how many
## get on (PedestrianManager sets it).
static var arrived_hook := Callable()
## How many are walking up to a bus's door (PedestrianManager sets it).
static var boarding_hook := Callable()
## Every bus stops at every stop (tools/traffic_check.gd).
static var always_stop := false

var manager: TrafficManager
var transit: TransitStops
## Each: {"name", "via": Array[Vector2] out and back, "stops": stop
## indexes, "path": the line along the streets so far (planned a leg at
## a time once the player's near), "path_leg": the leg of each point, "planned": legs
## planned}.
var routes: Array[Dictionary] = []
var _check := 0.0


func _init(m: TrafficManager) -> void:
	manager = m
	transit = TransitStops.of(m.net, m.data)
	for tr: Dictionary in transit.routes:
		var via: Array[Vector2] = tr["via"]
		# Out and back.
		var loop: Array[Vector2] = via.duplicate()
		for i in range(via.size() - 2, -1, -1):
			loop.append(via[i])
		routes.append({"name": "%s %s" % [tr["number"], tr["name"]], "via": loop, "stops": tr["stops"], "one_way": via.size(),
			"path": PackedVector2Array(), "path_leg": PackedInt32Array(), "planned": 0})


## Buses on the route near the player, as needed (called by the manager).
func tick(delta: float, fp: Vector3) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_EVERY
	var fp2 := Vector2(fp.x, fp.z)
	var buses := 0
	var on := {}
	for d: TrafficDriver in manager.drivers:
		if d.bus_route >= 0:
			buses += 1
			on[d.bus_route] = true
	if buses >= BUSES_MAX:
		return
	var order := range(routes.size())
	order.shuffle()
	var planned_one := false
	for ri: int in order:
		if on.has(ri):
			continue
		var r: Dictionary = routes[ri]
		var via: Array = r["via"]
		var n_one: int = r["one_way"]
		# Near the route at all (its junctions, roughly)?
		var near := false
		for k in n_one - 1:
			near = near or Geometry2D.get_closest_point_to_segment(fp2, via[k], via[k + 1]).distance_to(fp2) < NEAR
		if not near:
			continue
		if int(r["planned"]) < n_one - 1:
			# The line along the streets, a leg per check (one route at a
			# time), so it's never one long stop.
			if not planned_one:
				planned_one = true
				_plan_leg(r)
				_check = 0.3 # the next leg soon
			continue
		# A spot on the route 80 m to the physics radius off, out of sight.
		var radius := TrafficDensity.PHYSICS_RADIUS
		var path: PackedVector2Array = r["path"]
		var cands: Array[int] = []
		for i in range(0, path.size(), 4):
			var d := path[i].distance_to(fp2)
			if d > TrafficDensity.SPAWN_MIN + 10.0 and d < radius - 15.0:
				cands.append(i)
		cands.shuffle()
		for i: int in cands.slice(0, 12):
			if _place(ri, i, fp):
				return


## Plans the next leg of route r's line.
func _plan_leg(r: Dictionary) -> void:
	var via: Array = r["via"]
	var k: int = r["planned"]
	r["planned"] = k + 1
	var leg := StreetRoute.plan(manager.net, via[k], via[k + 1], TrafficManager.plan_options((via[k + 1] - via[k]).normalized()))
	if leg.is_empty():
		return
	# (Packed arrays are values: change a copy and put it back.)
	var path: PackedVector2Array = r["path"]
	var legs: PackedInt32Array = r["path_leg"]
	path.append_array(leg.points)
	for i in leg.points.size():
		legs.append(k)
	r["path"] = path
	r["path_leg"] = legs


func _place(ri: int, i: int, fp: Vector3) -> bool:
	var r: Dictionary = routes[ri]
	var path: PackedVector2Array = r["path"]
	var p := path[i]
	var p3 := Vector3(p.x, manager.world.terrain.h2(p), p.y)
	if TrafficSight.seen(manager.get_tree(), p3, fp):
		return false
	if manager.heat.keep_clear(p, Vector2(fp.x, fp.z)):
		return false
	for u: RoadUsers.User in RoadUsers.near(manager.get_tree(), p, 20.0):
		if u.pos.distance_to(p) < 20.0:
			return false
	# Never two buses near each other (one left behind, taken by the
	# player, or still going on another leg).
	for n: Node in manager.get_tree().get_nodes_in_group("vehicles"):
		var c := n as Car
		if c != null and c.model_id == MODEL and Vector2(c.global_position.x, c.global_position.z).distance_to(p) < NEAR:
			return false
	# Out or back along the route, heading on to the next junction of it
	# that way.
	var via: Array = r["via"]
	var n_one: int = r["one_way"]
	var k: int = (r["path_leg"] as PackedInt32Array)[i]
	var out := randf() < 0.5
	var next := k + 1 if out else 2 * (n_one - 1) - k
	var goal: Vector2 = via[next]
	var dir := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
	if not out:
		dir = -dir
	var d := manager.spawn_bus(p3, dir, ri, next, goal)
	return d != null


## Someone on board wants off at the next stop: how many (0 for nobody).
static func getting_off(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, OFF_MAX) if rng.randf() < OFF_ODDS else 0


## Whether a bus coming up to stop si pulls in: someone's waiting on its
## side, or someone on it wants off.
static func wants_stop(si: int, bus: Car, off: int) -> bool:
	if always_stop or off > 0:
		return true
	var ts := TransitStops.current
	if ts == null or si < 0 or si >= ts.stops.size():
		return false
	var side := ts.right_side(si, _fwd(bus))
	if side == 0 or not waiting_hook.is_valid():
		return false
	return int(waiting_hook.call(si, side)) > 0


## A bus has stopped at stop si: who gets on and off, and how long that
## takes (s).
static func at_stop(si: int, bus: Car, off: int, rng: RandomNumberGenerator) -> float:
	var ts := TransitStops.current
	var on := 0
	if ts != null and si >= 0 and si < ts.stops.size() and arrived_hook.is_valid():
		var side := ts.right_side(si, _fwd(bus))
		if side != 0:
			on = int(arrived_hook.call(si, side, bus, off))
	if always_stop and on == 0 and off == 0:
		return rng.randf_range(DWELL.x, DWELL.y)
	return minf(DWELL_BASE + rng.randf_range(0.0, 1.5) + on * DWELL_EACH.x + off * DWELL_EACH.y, DWELL_MAX)


## How many are walking up to bus's door.
static func boarding(bus: Node3D) -> int:
	return int(boarding_hook.call(bus)) if boarding_hook.is_valid() else 0


## Where people get on and off a bus: outside its front door.
static func door(bus: Node3D) -> Vector3:
	var shape := CarModels.shape_for(MODEL)
	var f := -bus.global_basis.z
	var r := bus.global_basis.x
	return bus.global_position + f * (float(shape.get("length", 12.0)) * 0.5 - 1.4) + r * (float(shape.get("width", 2.6)) * 0.5 + 0.45)


static func _fwd(bus: Node3D) -> Vector2:
	var f := -bus.global_basis.z
	return Vector2(f.x, f.z).normalized()


## The next junction on a bus's route after it reaches one.
func next_stop(d: TrafficDriver) -> Vector2:
	var via: Array = routes[d.bus_route]["via"]
	d.bus_leg = (d.bus_leg + 1) % via.size()
	if d.bus_leg == 0:
		d.bus_leg = 1
	return via[d.bus_leg]


## Where on a leg's route route ri's stops are: [metres along it, stop
## index], in order.
static func stops_on(r: StreetRoute, ri: int) -> Array:
	var out := []
	var ts := TransitStops.current
	if ts == null or ri < 0 or ri >= ts.routes.size():
		return out
	for si: int in ts.routes[ri]["stops"]:
		var p: Vector2 = ts.stops[si]["p"]
		var along := r.project(p)
		if along > 25.0 and along < r.length - 18.0 and r.off_line(p, along) < ON_LEG:
			out.append([along, si])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	return out


## Whether the curb at a stop just ahead is free of parked cars (and
## anything else), so the bus can pull right in to it on a street that
## has parking.
static func stop_clear(bus: Car, r: StreetRoute, along: float, net: RoadNetwork) -> bool:
	# From just short of the stop to well past where it'll stand (it stops
	# a bus length or so on, and pulls out past what's ahead of it there).
	var p := r.sample(along + 23.0)
	var dir := r.dir_at(along + 23.0)
	var hit := net.nearest_on_streets(p, 20.0)
	if hit.is_empty():
		return false
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var right := Vector2(-dir.y, dir.x)
	var c: Vector2 = (hit["pos"] as Vector2) + right * (e.half_width - 1.2)
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.4, 46.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.SOLID | Layers.VEHICLES
	q.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(c.x, bus.global_position.y + 0.3, c.y))
	q.exclude = [bus.get_rid()]
	return bus.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

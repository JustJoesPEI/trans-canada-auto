class_name TrafficBuses
extends RefCounted
## The town buses (Charlatown Transit, TruckModels "transit_bus") on two
## real routes along the town's main streets, given as the junctions they
## pass (by street names, RoadNetwork.find_junction): out to the end and
## back. A bus pulls in to the curb at a stop every STOP_EVERY metres and
## waits there a while (CivilDriving.hold_for, aside), then pulls out.
##
## Like the trucks, a bus is only ever a real vehicle near the player (it
## has no far version): when the player is within NEAR of a route and no
## bus on it is about, one is placed on the route out of sight within the
## physics radius, heading on to its next junction; it's taken away unseen
## once out of range. At most BUSES_MAX at once.
##
## A bus makes a very good wall: it's 12 m long, slow to get going, and
## other traffic queues behind it at stops (it isn't "waiting its turn",
## so they go round it when the other lane's clear).

const ROUTES := [
	{"name": "1 University", "via": [["Water Street", "Queen Street"], ["Grafton Street", "Queen Street"],
		["Queen Street", "Euston Street"], ["University Avenue", "Euston Street"], ["University Avenue", "Allen Street"],
		["University Avenue", "Belvedere Avenue"]]},
	{"name": "3 Belvedere", "via": [["North River Road", "Belvedere Avenue"], ["University Avenue", "Belvedere Avenue"],
		["Belvedere Avenue", "Mount Edward Road"]]},
]
const MODEL := "transit_bus"
const STOP_EVERY := 320.0
const DWELL := Vector2(8.0, 14.0)
## How far in to the curb a bus pulls at a stop, at most (m): a bus's
## wheels on the curb tip it.
const PULL_IN := 1.2
## A route this close to the player gets a bus (m).
const NEAR := 320.0
const BUSES_MAX := 2
const CHECK_EVERY := 1.5

var manager: TrafficManager
## Each: {"name", "via": Array[Vector2] out and back, "path": PackedVector2Array}.
var routes: Array[Dictionary] = []
var _check := 0.0


func _init(m: TrafficManager) -> void:
	manager = m
	var net := m.net
	for r: Dictionary in ROUTES:
		var via: Array[Vector2] = []
		for pr: Array in r["via"]:
			var nid := net.find_junction(pr[0], pr[1])
			if nid != "":
				via.append(net.nodes[nid])
		if via.size() < 2:
			continue
		var path := PackedVector2Array()
		for i in range(via.size() - 1):
			var leg := StreetRoute.plan(net, via[i], via[i + 1], TrafficManager.plan_options(Vector2.ZERO))
			if not leg.is_empty():
				path.append_array(leg.points)
		# Out and back.
		var loop: Array[Vector2] = via.duplicate()
		for i in range(via.size() - 2, -1, -1):
			loop.append(via[i])
		routes.append({"name": r["name"], "via": loop, "path": path})


## Buses on the route near the player, as needed (called by the manager).
func tick(delta: float, fp: Vector3, lvl: int) -> void:
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
	for ri in routes.size():
		if on.has(ri):
			continue
		var r: Dictionary = routes[ri]
		var path: PackedVector2Array = r["path"]
		var best := -1
		var radius := float(TrafficDensity.PHYSICS_RADIUS[lvl])
		var near := false
		# A spot on the route 80 m to the physics radius off, out of sight.
		var cands: Array[int] = []
		for i in range(0, path.size(), 4):
			var d := path[i].distance_to(fp2)
			near = near or d < NEAR
			if d > TrafficDensity.SPAWN_MIN + 10.0 and d < radius - 15.0:
				cands.append(i)
		if not near or cands.is_empty():
			continue
		cands.shuffle()
		for i: int in cands:
			if _place(ri, i, fp):
				return


func _place(ri: int, i: int, fp: Vector3) -> bool:
	var r: Dictionary = routes[ri]
	var path: PackedVector2Array = r["path"]
	var p := path[i]
	var dir := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
	var p3 := Vector3(p.x, manager.world.terrain.h2(p), p.y)
	if TrafficSight.seen(manager.get_tree(), p3, fp):
		return false
	for u: RoadUsers.User in RoadUsers.all(manager.get_tree()):
		if u.pos.distance_to(p) < 20.0:
			return false
	# Heading on to whichever junction of the route is next along its path.
	var via: Array = r["via"]
	var next := 1
	var best := INF
	for k in range(1, via.size()):
		var v: Vector2 = via[k]
		var ahead := (v - p).dot(dir)
		if ahead > 20.0 and v.distance_to(p) < best:
			best = v.distance_to(p)
			next = k
	var d := manager.spawn_bus(p3, dir, ri, next, via[next])
	return d != null


## The next junction on a bus's route after it reaches one.
func next_stop(d: TrafficDriver) -> Vector2:
	var via: Array = routes[d.bus_route]["via"]
	d.bus_leg = (d.bus_leg + 1) % via.size()
	if d.bus_leg == 0:
		d.bus_leg = 1
	return via[d.bus_leg]


## Where on a leg's route the stops are (metres along it).
static func stops_on(r: StreetRoute) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var a := STOP_EVERY * 0.5
	while a < r.length - 60.0:
		out.append(a)
		a += STOP_EVERY
	return out

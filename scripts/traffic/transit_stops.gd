class_name TransitStops
extends RefCounted
## The town's bus routes and stops (Charlatown Transit), read from
## data/transit.json: the routes as the junctions they pass (by street
## names, or a point in game metres for a dead end) and their stops, each on a real street. A stop is either near a
## junction ("on" a street, "at" a cross street: it stands STOP_OFFSET metres
## (or "offset") past the junction along "on", the way the buses' own far-side stops do,
## and for the bus going the other way it's just short of it), or near a
## place ("lonlat", or "xz" in game metres, on the nearest ordinary street,
## or the one named "on").
##
## Each stop has a pole and sign at each curb with a sidewalk
## (StreetClutter draws them), and a spot on that sidewalk where people wait
## (Pedestrian, PedestrianManager). The buses (TrafficBuses) stop at them,
## when someone's waiting on their side or wants off.
##
## Worked out once per network on the main thread (RoadMesher.prepare), so
## the chunk builders can read it from their threads. No route planning
## here: it's a junction lookup and a nearest-street search per stop.

const PATH := "res://data/transit.json"
## How far past the junction a stop stands (m).
const STOP_OFFSET := 35.0
## Two routes' stops this close together on the same street are one stop.
const MERGE := 25.0
## A place stop looks this far for its street (m).
const PLACE_REACH := 220.0

## The stops of the network the game is on.
static var current: TransitStops = null

var net: RoadNetwork
## Each {"number", "name", "via": Array[Vector2] one way, "stops": Array[int]}.
var routes: Array[Dictionary] = []
## Each {"name", "edge", "along", "p": the street's middle, "dir": along the
## edge, "sides": [1, -1] (those with a sidewalk), "sign": {side: Vector3
## (on the ground)}, "wait": {side: Vector2}, "routes": [route indexes],
## "t3": named as on the real T3 route}.
var stops: Array[Dictionary] = []


## Reads the routes for `n` (RoadMesher.prepare calls it).
static func prepare(n: RoadNetwork, data: StreetData) -> void:
	current = TransitStops.new(n, data)


## The stops for `n` (worked out now if prepare wasn't called for it).
static func of(n: RoadNetwork, data: StreetData = null) -> TransitStops:
	if current == null or current.net != n:
		current = TransitStops.new(n, data)
	return current


func _init(n: RoadNetwork, data: StreetData) -> void:
	net = n
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		push_warning("TransitStops: couldn't read %s" % PATH)
		return
	for r: Dictionary in (parsed as Dictionary).get("routes", []):
		var via: Array[Vector2] = []
		for pr: Array in r.get("via", []):
			if pr.size() == 2 and (pr[0] is float or pr[0] is int):
				via.append(Vector2(float(pr[0]), float(pr[1]))) # a point (a dead end: game metres)
				continue
			var nid := net.find_junction(str(pr[0]), str(pr[1]))
			if nid != "":
				via.append(net.nodes[nid])
			else:
				push_warning("TransitStops: route %s: no junction of %s and %s" % [r.get("number", "?"), pr[0], pr[1]])
		if via.size() < 2:
			continue
		var ri := routes.size()
		var route := {"number": str(r.get("number", "")), "name": str(r.get("name", "")), "via": via, "stops": [] as Array[int]}
		routes.append(route)
		for s: Dictionary in r.get("stops", []):
			var at := _resolve(s, via, data)
			if at.is_empty():
				push_warning("TransitStops: route %s: couldn't place stop %s" % [route["number"], s.get("name", "?")])
				continue
			var si := _add_stop(at, str(s.get("name", "")), bool(s.get("t3", false)))
			if not (stops[si]["routes"] as Array).has(ri):
				(stops[si]["routes"] as Array).append(ri)
			if not (route["stops"] as Array[int]).has(si):
				(route["stops"] as Array[int]).append(si)


## Where a stop goes: {"edge", "along"}, or empty.
func _resolve(s: Dictionary, via: Array[Vector2], data: StreetData) -> Dictionary:
	var on := str(s.get("on", ""))
	if s.has("at"):
		var nid := net.find_junction(on, str(s["at"]))
		if nid == "":
			return {}
		var j: Vector2 = net.nodes[nid]
		# Which way along "on": toward the named street, else the way the
		# route runs (its first junction to its last).
		var want := via[via.size() - 1] - via[0]
		if s.has("toward"):
			var t := net.find_junction(on, str(s["toward"]))
			if t != "":
				want = (net.nodes[t] as Vector2) - j
		var best: RoadNetwork.Incident = null
		var best_dot := -INF
		for inc: RoadNetwork.Incident in net.incidents.get(nid, []):
			if inc.edge.name != on:
				continue
			var dd := inc.dir.dot(want.normalized())
			if dd > best_dot:
				best_dot = dd
				best = inc
		if best == null:
			return {}
		var e := best.edge
		var off := clampf(float(s.get("offset", STOP_OFFSET)), 8.0, e.length * 0.5)
		return {"edge": e, "along": off if best.at_start else e.length - off}
	var p := Vector2.INF
	if s.has("lonlat") and data != null:
		var ll: Array = s["lonlat"]
		p = data.projection.to_ground(float(ll[0]), float(ll[1]))
	elif s.has("xz"):
		var xz: Array = s["xz"]
		p = Vector2(float(xz[0]), float(xz[1]))
	if p == Vector2.INF:
		return {}
	var best_e: RoadNetwork.RoadEdge = null
	var best_d := PLACE_REACH
	var best_along := 0.0
	for e in net.edges_near(Rect2(p - Vector2(PLACE_REACH, PLACE_REACH), Vector2(PLACE_REACH, PLACE_REACH) * 2.0)):
		if e.minor or e.is_highway() or e.roundabout or (on != "" and e.name != on):
			continue
		if not Pedestrian.walkable(e, 1) and not Pedestrian.walkable(e, -1):
			continue
		var along := 0.0
		for i in range(e.points.size() - 1):
			var a := e.points[i]
			var b := e.points[i + 1]
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := q.distance_to(p)
			if d < best_d:
				best_d = d
				best_e = e
				best_along = along + a.distance_to(q)
			along += a.distance_to(b)
	if best_e == null:
		return {}
	# Clear of the junctions at its ends.
	var lo := minf(20.0, best_e.length * 0.4)
	return {"edge": best_e, "along": clampf(best_along, lo, best_e.length - lo)}


## Adds a stop (or finds the one already there): its index.
func _add_stop(at: Dictionary, stop_name: String, t3: bool) -> int:
	var e: RoadNetwork.RoadEdge = at["edge"]
	var along: float = at["along"]
	var s: Array = RoadNetwork.sample(e.points, along)
	var p: Vector2 = s[0]
	for i in stops.size():
		var o: Dictionary = stops[i]
		if o["edge"] == e and absf(float(o["along"]) - along) < MERGE:
			o["t3"] = bool(o["t3"]) or t3
			return i
	var dir: Vector2 = s[1]
	var sides: Array[int] = []
	var sign := {}
	var wait := {}
	for side: int in [1, -1]:
		if not Pedestrian.walkable(e, side):
			continue
		sides.append(side)
		var perp := RoadNetwork._perp(dir) * float(side)
		var curb := p + perp * net.offset_for(e, RoadNetwork.Level.PROP, side)
		sign[side] = curb
		# Waiting a little to the curb side of the sidewalk's middle.
		var walk := p + perp * net.offset_for(e, RoadNetwork.Level.WALK, side)
		wait[side] = walk.lerp(curb, 0.35)
	stops.append({"name": stop_name, "edge": e, "along": along, "p": p, "dir": dir, "sides": sides,
		"sign": sign, "wait": wait, "routes": [], "t3": t3})
	return stops.size() - 1


## The stops within r of p (indexes).
func near(p: Vector2, r: float) -> Array[int]:
	var out: Array[int] = []
	for i in stops.size():
		if (stops[i]["p"] as Vector2).distance_squared_to(p) < r * r:
			out.append(i)
	return out


## Which side of stop si a vehicle at p heading `fwd` has on its right (the
## side it pulls in to), or 0 if that side has no sidewalk.
func right_side(si: int, fwd: Vector2) -> int:
	var st: Dictionary = stops[si]
	var right := Vector2(-fwd.y, fwd.x)
	var side := 1 if RoadNetwork._perp(st["dir"]).dot(right) > 0.0 else -1
	return side if (st["sides"] as Array).has(side) else 0

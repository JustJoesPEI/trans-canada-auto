class_name Gps
extends Node
## The waypoint: one spot the player picked on the map (WorldMap), and the
## way there along the streets. The minimap draws the route and the pin,
## the HUD shows how far it is and puts a marker on the screen over it.
##
##   Gps.find(get_tree())        the one on the HUD (or null)
##   set_waypoint(at, name)      a world point (and what's there, "" for
##                               a spot on the map); routes to it at once
##   clear()
##   active, target, place       what's set
##   route                       PackedVector2Array (x, z): from the
##                               street beside you to the waypoint, the
##                               part behind you trimmed off as you go
##   remaining                   m left along it (straight if no route)
##
## The route is the shortest along RoadNetwork's streets (A* over its
## junctions), one-way streets kept to while you drive and lanes and
## parking aisles taken only when they save a lot. It's worked out when the
## waypoint is set and again when you leave it by more than OFF_ROUTE; in
## between it's only trimmed (a few hundred points, four times a second).

signal changed ## the waypoint was set or cleared, or the route changed
signal arrived(place: String)

## m from the waypoint that counts as there (in a car, on foot).
const ARRIVE_CAR := 28.0
const ARRIVE_FOOT := 12.0
## m off the route before it's worked out again, and how often at most (s).
const OFF_ROUTE := 40.0
const REROUTE_GAP := 2.0
## How much longer a lane or parking aisle counts, and a highway (cheaper).
const MINOR_COST := 2.5
const HIGHWAY_COST := 0.85
## How far from a street a waypoint or the player can be and still route (m).
const SNAP := 400.0

var active := false
var target := Vector3.ZERO
var place := ""
var route := PackedVector2Array()
var remaining := 0.0

var world: Node
var player: Node3D
var _timer := 0.0
var _since_route := 0.0
var _cum := PackedFloat32Array() ## distance along route at each point
var _head := 0 ## the route segment you're on


static func find(tree: SceneTree) -> Gps:
	return tree.get_first_node_in_group("gps") as Gps if tree != null else null


func _ready() -> void:
	add_to_group("gps")


func setup(w: Node, who: Node3D) -> void:
	world = w
	player = who


func set_waypoint(at: Vector3, name := "") -> void:
	active = true
	target = at
	place = name
	_reroute()


func clear() -> void:
	if not active:
		return
	active = false
	place = ""
	route = PackedVector2Array()
	_cum = PackedFloat32Array()
	remaining = 0.0
	changed.emit()


## What to call it on screen: the place, or "Waypoint".
func title() -> String:
	return place if place != "" else "Waypoint"


func _driving() -> bool:
	return player != null and player.get("vehicle") != null


func _process(delta: float) -> void:
	_since_route += delta
	_timer -= delta
	if not active or player == null or not is_instance_valid(player) or _timer > 0.0:
		return
	_timer = 0.25
	var p := player.global_position
	var here := Vector2(p.x, p.z)
	var straight := here.distance_to(Vector2(target.x, target.z))
	if straight < (ARRIVE_CAR if _driving() else ARRIVE_FOOT):
		var was := place
		clear()
		arrived.emit(was)
		return
	if route.size() < 2:
		remaining = straight
		if _since_route > REROUTE_GAP * 2.0:
			_reroute()
		return
	# Trim what's behind: the nearest segment, looking a little way back
	# and ahead of the last one (a route can pass near itself).
	var best := INF
	var best_i := _head
	var best_q := route[_head]
	for i in range(maxi(0, _head - 4), mini(route.size() - 1, _head + 60)):
		var q := Geometry2D.get_closest_point_to_segment(here, route[i], route[i + 1])
		var d := q.distance_squared_to(here)
		if d < best:
			best = d
			best_i = i
			best_q = q
	if sqrt(best) > OFF_ROUTE and _since_route > REROUTE_GAP:
		_reroute()
		return
	var old := _head
	_head = best_i
	remaining = _cum[_cum.size() - 1] - (_cum[best_i] + route[best_i].distance_to(best_q)) + sqrt(best)
	if _head != old:
		changed.emit()


## The route from where you are now, for drawing: the point beside you,
## then the rest of the route.
func route_ahead() -> PackedVector2Array:
	if route.size() < 2:
		return PackedVector2Array()
	var out := PackedVector2Array()
	if player != null and is_instance_valid(player):
		var p := player.global_position
		out.append(Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), route[_head], route[mini(_head + 1, route.size() - 1)]))
	out.append_array(route.slice(_head + 1))
	return out


func _reroute() -> void:
	_since_route = 0.0
	_head = 0
	route = PackedVector2Array()
	_cum = PackedFloat32Array()
	var net: RoadNetwork = world.get("network") if world != null else null
	if net != null and player != null and is_instance_valid(player):
		var p := player.global_position
		route = find_route(net, Vector2(p.x, p.z), Vector2(target.x, target.z), _driving())
		if route.is_empty() and _driving():
			route = find_route(net, Vector2(p.x, p.z), Vector2(target.x, target.z), false)
	_cum.resize(route.size())
	var total := 0.0
	for i in route.size():
		if i > 0:
			total += route[i - 1].distance_to(route[i])
		_cum[i] = total
	if player != null and is_instance_valid(player):
		var p := player.global_position
		remaining = total if route.size() > 1 else Vector2(p.x, p.z).distance_to(Vector2(target.x, target.z))
	changed.emit()


# --- routing -----------------------------------------------------------------------------------

## The shortest way along the streets from `from` to `to` (both x, z), from
## the street nearest `from` to the one nearest `to`, as a polyline; empty
## if either is too far from a street or there's no way through.
## `one_way` keeps to one-way streets' direction.
static func find_route(net: RoadNetwork, from: Vector2, to: Vector2, one_way: bool) -> PackedVector2Array:
	var s := net.nearest_on_streets(from, SNAP)
	var t := net.nearest_on_streets(to, SNAP)
	if s.is_empty() or t.is_empty():
		return PackedVector2Array()
	var se: RoadNetwork.RoadEdge = s["edge"]
	var te: RoadNetwork.RoadEdge = t["edge"]
	var s_along: float = s["along"]
	var t_along: float = t["along"]
	var s_len := RoadNetwork.polyline_length(se.points)
	var t_len := RoadNetwork.polyline_length(te.points)
	# Both on one street, and its way runs from here to there: straight along it.
	if se == te:
		var fwd := t_along >= s_along
		if not one_way or se.oneway == 0 or (se.oneway == 1) == fwd:
			var direct := _slice(se.points, s_along, t_along)
			if t["dist"] > 15.0:
				direct.append(to)
			return direct
	# The goal: reached from te.a (along it to t_along) or te.b.
	var goal_cost := {}
	if not one_way or te.oneway != -1:
		goal_cost[te.a] = t_along * _cost(te)
	if not one_way or te.oneway != 1:
		goal_cost[te.b] = (t_len - t_along) * _cost(te)
	# A* from both ends of the start street.
	var g := {}
	var prev := {} # node -> Incident used to get there
	var heap: Array = [] # [f, node]
	if not one_way or se.oneway != 1:
		g[se.a] = s_along * _cost(se)
		_push(heap, float(g[se.a]) + (net.nodes[se.a] as Vector2).distance_to(to), se.a)
	if not one_way or se.oneway != -1:
		var cb := (s_len - s_along) * _cost(se)
		if cb < float(g.get(se.b, INF)):
			g[se.b] = cb
			_push(heap, cb + (net.nodes[se.b] as Vector2).distance_to(to), se.b)
	var done := {}
	var best_end := ""
	var best_total := INF
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var cur: String = top[1]
		if float(top[0]) >= best_total:
			break
		if done.has(cur):
			continue
		done[cur] = true
		var gc: float = g[cur]
		if goal_cost.has(cur) and gc + float(goal_cost[cur]) < best_total:
			best_total = gc + float(goal_cost[cur])
			best_end = cur
		for inc: RoadNetwork.Incident in net.incidents.get(cur, []):
			var e := inc.edge
			if one_way and ((inc.at_start and e.oneway == -1) or (not inc.at_start and e.oneway == 1)):
				continue
			var nxt := e.b if inc.at_start else e.a
			if done.has(nxt):
				continue
			var d := gc + e.length * _cost(e)
			if d < float(g.get(nxt, INF)):
				g[nxt] = d
				prev[nxt] = inc
				_push(heap, d + (net.nodes[nxt] as Vector2).distance_to(to), nxt)
	if best_end == "":
		return PackedVector2Array()
	# Walk back from the goal end to whichever end of the start street.
	var parts: Array[PackedVector2Array] = []
	var at := best_end
	while prev.has(at):
		var inc: RoadNetwork.Incident = prev[at]
		var pts := inc.edge.points.duplicate()
		if not inc.at_start:
			pts.reverse()
		parts.push_front(pts)
		at = inc.edge.a if inc.at_start else inc.edge.b
	var out := _slice(se.points, s_along, 0.0 if at == se.a else s_len)
	for pts in parts:
		_join(out, pts)
	_join(out, _slice(te.points, 0.0 if best_end == te.a else t_len, t_along))
	if float(t["dist"]) > 15.0:
		out.append(to)
	return out


static func _cost(e: RoadNetwork.RoadEdge) -> float:
	if e.minor:
		return MINOR_COST
	return HIGHWAY_COST if e.is_highway() else 1.0


## Adds `pts` to `out`, without doubling the point where they meet.
static func _join(out: PackedVector2Array, pts: PackedVector2Array) -> void:
	for i in pts.size():
		if i == 0 and not out.is_empty() and out[out.size() - 1].distance_squared_to(pts[0]) < 0.25:
			continue
		out.append(pts[i])


## The part of a polyline from `d0` to `d1` m along it (reversed if d1 < d0).
static func _slice(pts: PackedVector2Array, d0: float, d1: float) -> PackedVector2Array:
	var lo := minf(d0, d1)
	var hi := maxf(d0, d1)
	var out := PackedVector2Array()
	out.append(RoadNetwork.sample(pts, lo)[0])
	var along := 0.0
	for i in range(pts.size() - 1):
		along += pts[i].distance_to(pts[i + 1])
		if along > lo and along < hi:
			out.append(pts[i + 1])
	out.append(RoadNetwork.sample(pts, hi)[0])
	if d1 < d0:
		out.reverse()
	return out


# A small binary heap of [cost, node].
static func _push(heap: Array, f: float, node: String) -> void:
	heap.append([f, node])
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= f:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = [f, node]


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var c := l
		if l + 1 < n and float(heap[l + 1][0]) < float(heap[l][0]):
			c = l + 1
		if float(heap[c][0]) >= float(last[0]):
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top

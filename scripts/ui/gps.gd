class_name Gps
extends Node
## The waypoint: one spot the player picked on the map (WorldMap), and the
## way there along the streets. The minimap draws the route and the pin,
## the HUD shows how far it is and puts a marker on the screen over it.
##
##   Gps.find(get_tree())        the one on the HUD (or null)
##   set_waypoint(at, name, mode)
##                               a world point (and what's there, "" for
##                               a spot on the map); routes to it at once.
##                               `mode` is how much help you get (the GPS
##                               modes in docs/design.md section 6, for
##                               delivery jobs; your own waypoints are
##                               "route"): "route" the way drawn on the
##                               minimap and map, the turns and the pin;
##                               "directions" the turns by street name and
##                               the pin, no drawn way; "address" only the
##                               place's name: you find it
##   clear()
##   active, target, place       what's set
##   route                       PackedVector2Array (x, z): from the
##                               street beside you to the waypoint, the
##                               part behind you trimmed off as you go
##   remaining                   m left along it (straight if no route)
##   next_turn                   what to do next along it, for the HUD:
##                               {turn, dist, onto, angle}; turn is "left",
##                               "right", "sharp left", "sharp right",
##                               "u-turn", "roundabout", "continue" (nothing
##                               within TURN_LOOK) or "arrive"
##
## The route is the shortest along RoadNetwork's streets (A* over its
## junctions), one-way streets kept to while you drive and lanes and
## parking aisles taken only when they save a lot. It's worked out when the
## waypoint is set and again when you leave it by more than OFF_ROUTE; in
## between it's only trimmed (a few hundred points, four times a second).
## Worked out again while you drive, it's on a worker (the search is up to
## 20 ms, a hitch on the main thread): the old route shows until the new
## one is in, a frame or two later.

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
## A bend sharper than this (radians, over TURN_SPAN either side) is a turn;
## sharper than SHARP is a sharp one, and U_TURN a U-turn.
const TURN_MIN := 0.6
const SHARP := 2.0
const U_TURN := 2.7
const TURN_SPAN := 12.0
## How far ahead along the route turns are looked for (m).
const TURN_LOOK := 900.0

var active := false
var mode := "route"
var target := Vector3.ZERO
var place := ""
var route := PackedVector2Array()
var remaining := 0.0
var next_turn := {}

var world: Node
var player: Node3D
var _timer := 0.0
var _since_route := 0.0
var _cum := PackedFloat32Array() ## distance along route at each point
var _head := 0 ## the route segment you're on
## A reroute being worked out on a worker (WorkerThreadPool task id, -1 for
## none), its answer when done ([route]), and which waypoint it was for:
## one set or cleared since makes its answer stale.
var _task := -1
var _answer: Array = []
var _gen := 0
var _task_gen := -1


static func find(tree: SceneTree) -> Gps:
	return tree.get_first_node_in_group("gps") as Gps if tree != null else null


func _ready() -> void:
	add_to_group("gps")


func setup(w: Node, who: Node3D) -> void:
	world = w
	player = who


func set_waypoint(at: Vector3, name := "", help := "route") -> void:
	active = true
	target = at
	place = name
	if has_meta("job"):
		remove_meta("job") # yours now, not a job's (Jobs sets it again after)
	mode = help if help in ["route", "directions", "address"] else "route"
	_gen += 1
	_reroute()


## What the mode shows: the way drawn, the turns, the pin and distance.
func shows_route() -> bool:
	return active and mode == "route"


func shows_turns() -> bool:
	return active and mode != "address"


func shows_pin() -> bool:
	return active and mode != "address"


func clear() -> void:
	if has_meta("job"):
		remove_meta("job")
	_gen += 1
	if not active:
		return
	active = false
	place = ""
	route = PackedVector2Array()
	_cum = PackedFloat32Array()
	remaining = 0.0
	next_turn = {}
	changed.emit()


## What to call it on screen: the place, or "Waypoint".
func title() -> String:
	return place if place != "" else "Waypoint"


func _driving() -> bool:
	return player != null and player.get("vehicle") != null


func _process(delta: float) -> void:
	_since_route += delta
	_timer -= delta
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _task_gen == _gen and active and not _answer.is_empty():
			_use_route(_answer[0])
	if not active or player == null or not is_instance_valid(player) or _timer > 0.0:
		return
	_timer = 0.25
	var p := player.global_position
	var here := Vector2(p.x, p.z)
	var straight := here.distance_to(Vector2(target.x, target.z))
	# A job's stop (Jobs) isn't done just by getting near: the job says when.
	if straight < (ARRIVE_CAR if _driving() else ARRIVE_FOOT) and not has_meta("job"):
		var was := place
		clear()
		arrived.emit(was)
		return
	if route.size() < 2:
		remaining = straight
		if _since_route > REROUTE_GAP * 2.0:
			_reroute_later()
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
		_reroute_later()
	var old := _head
	_head = best_i
	remaining = _cum[_cum.size() - 1] - (_cum[best_i] + route[best_i].distance_to(best_q)) + sqrt(best)
	next_turn = find_turn(route_ahead(), world.get("network") if world != null else null, remaining)
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


## Works the route out now (a waypoint just set: it shows at once).
func _reroute() -> void:
	_since_route = 0.0
	var found := PackedVector2Array()
	var net: RoadNetwork = world.get("network") if world != null else null
	if net != null and player != null and is_instance_valid(player):
		var p := player.global_position
		found = _route_for(net, Vector2(p.x, p.z), Vector2(target.x, target.z), _driving())
	_use_route(found)


## Works the route out again on a worker (off the route while driving);
## _process puts it in when it's done.
func _reroute_later() -> void:
	_since_route = 0.0
	if _task >= 0:
		return
	var net: RoadNetwork = world.get("network") if world != null else null
	if net == null or player == null or not is_instance_valid(player):
		return
	var p := player.global_position
	_answer = []
	_task_gen = _gen
	_task = _start(net, Vector2(p.x, p.z), Vector2(target.x, target.z), _driving(), _answer)


## The search on a worker, writing its route into `answer`. Static, so the
## task holds nothing of this node (the network is only read).
static func _start(net: RoadNetwork, from: Vector2, to: Vector2, driving: bool, answer: Array) -> int:
	return WorkerThreadPool.add_task(func() -> void: answer.append(_route_for(net, from, to, driving)), false, "GPS route")


## The route, keeping to one-way streets while driving if there's a way.
static func _route_for(net: RoadNetwork, from: Vector2, to: Vector2, driving: bool) -> PackedVector2Array:
	var found := find_route(net, from, to, driving)
	if found.is_empty() and driving:
		found = find_route(net, from, to, false)
	return found


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _use_route(found: PackedVector2Array) -> void:
	_head = 0
	route = found
	_cum = PackedFloat32Array()
	_cum.resize(route.size())
	var total := 0.0
	for i in route.size():
		if i > 0:
			total += route[i - 1].distance_to(route[i])
		_cum[i] = total
	if player != null and is_instance_valid(player):
		var p := player.global_position
		remaining = total if route.size() > 1 else Vector2(p.x, p.z).distance_to(Vector2(target.x, target.z))
	next_turn = find_turn(route_ahead(), world.get("network") if world != null else null, remaining)
	changed.emit()


# --- turns -------------------------------------------------------------------------------------

## The first turn along `pts` (a route from where you are): where the way
## bends by more than TURN_MIN over TURN_SPAN m either side of a point. A
## bend onto a roundabout reads "roundabout", with the street you leave it
## by. `onto` is the street just after the turn ("" if unnamed). Nothing
## within TURN_LOOK: "continue"; nothing before the end: "arrive".
static func find_turn(pts: PackedVector2Array, net: RoadNetwork, left: float) -> Dictionary:
	if pts.size() < 2:
		return {"turn": "arrive", "dist": left, "onto": "", "angle": 0.0}
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var total := 0.0
	for i in pts.size():
		if i > 0:
			total += pts[i - 1].distance_to(pts[i])
		cum[i] = total
	for i in range(1, pts.size() - 1):
		var a := cum[i]
		if a < 4.0:
			continue
		if a > TURN_LOOK:
			break
		var din := pts[i] - point_at(pts, cum, a - TURN_SPAN)
		var dout := point_at(pts, cum, a + TURN_SPAN) - pts[i]
		if din.length() < 1.0 or dout.length() < 1.0:
			continue
		var ang := din.angle_to(dout) # + is to the right (x east, z south)
		if absf(ang) < TURN_MIN:
			continue
		if net != null and not _at_junction(net, pts[i]):
			continue # a bend in the road, not a turn
		var turn := "right" if ang > 0.0 else "left"
		if absf(ang) > U_TURN:
			turn = "u-turn"
		elif absf(ang) > SHARP:
			turn = "sharp " + turn
		var onto := ""
		if net != null:
			var here := net.nearest_on_streets(pts[i], 6.0)
			var round_ := not here.is_empty() and (here["edge"] as RoadNetwork.RoadEdge).roundabout
			var after := a + 20.0
			if round_:
				turn = "roundabout"
				# Round it to the street you leave by.
				while after < a + 250.0 and after < total:
					var h := net.nearest_on_streets(point_at(pts, cum, after), 6.0)
					if h.is_empty() or not (h["edge"] as RoadNetwork.RoadEdge).roundabout:
						break
					after += 8.0
				after += 15.0
			var next := net.nearest_on_streets(point_at(pts, cum, minf(after, total)), 8.0)
			if not next.is_empty():
				onto = (next["edge"] as RoadNetwork.RoadEdge).name
		return {"turn": turn, "dist": a, "onto": onto, "angle": ang}
	if total > TURN_LOOK:
		return {"turn": "continue", "dist": TURN_LOOK, "onto": "", "angle": 0.0}
	return {"turn": "arrive", "dist": left, "onto": "", "angle": 0.0}


## A junction (three or more ways) within JUNCTION_REACH of `p`.
const JUNCTION_REACH := 20.0
static func _at_junction(net: RoadNetwork, p: Vector2) -> bool:
	for e in net.edges_near(Rect2(p - Vector2.ONE * JUNCTION_REACH, Vector2.ONE * JUNCTION_REACH * 2.0)):
		for nid: String in [e.a, e.b]:
			if (net.nodes[nid] as Vector2).distance_to(p) <= JUNCTION_REACH and net.degree(nid) >= 3:
				return true
	return false


## The point `d` m along a polyline whose running lengths are `cum`.
static func point_at(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	if d <= 0.0:
		return pts[0]
	if d >= cum[cum.size() - 1]:
		return pts[pts.size() - 1]
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	return pts[lo].lerp(pts[hi], (d - cum[lo]) / seg if seg > 0.0 else 0.0)


## What the HUD says for a turn: "Turn right", "Roundabout".
static func turn_text(t: Dictionary) -> String:
	match str(t.get("turn", "")):
		"left": return "Turn left"
		"right": return "Turn right"
		"sharp left": return "Sharp left"
		"sharp right": return "Sharp right"
		"u-turn": return "Make a U-turn"
		"roundabout": return "Roundabout"
		"continue": return "Continue"
		"arrive": return "Arrive"
	return ""


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

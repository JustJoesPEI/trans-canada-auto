class_name StreetRoute
extends RefCounted
## A way to drive from one point to another along the streets, ready for a
## computer driver: the line to steer along (in the right-hand lane, corners
## rounded), and how fast each bit of it can be taken.
##
## Planned on the RoadNetwork graph with A* (the network's own `route` is a
## plain shortest path between junctions that ignores one-way streets; this
## starts and ends anywhere along a street, can obey one-way streets, and
## avoids starting off with a U-turn).
##
## The map isn't perfect, so the plan copes:
##   * pieces of street that should join but don't (an end left a few
##     metres short of the next street, a road split into separate pieces)
##     are bridged straight across, up to GAP_MAX (see _gap_links);
##   * if the goal can't be reached along the streets at all, the route goes
##     to the reachable junction nearest the goal (`partial`);
##   * with `off_road` (a pursuit), a start or goal off the street is joined
##     to it by a straight leg, a partial route carries straight on to the
##     goal, and no street anywhere near means one straight line (`direct`).
##     Without it (responding, patrolling) the route stays on the streets:
##     it ends on the street beside the goal, never across a field.
##
## The line is resampled every STEP metres. `limit` is the top speed at each
## sample: the cornering speed from the line's curvature, brought down ahead
## of every corner (and the end, when it stops there) by what the brakes can
## do, so a driver only has to look at the limit where it is now.
##
## Ground plane is Vector2(x, z), as in RoadNetwork.

const STEP := 2.0
## Cost (metres) added to a way that starts by going back the way the car is
## pointing, so a short U-turn only wins when going round is much longer.
const UTURN_COST := 120.0
## A street end this close to another piece of street it isn't joined to is
## a gap in the map, driven straight across (metres).
const GAP_MAX := 40.0
## Bridging a gap counts as this many times its length.
const GAP_COST := 3.0
## Searching for the street nearest a point goes this far (metres).
const NEAR_STREET := 200.0
## Off the street by up to this much past the curb (a car parked on the
## verge, a goal on the sidewalk) still joins the lane in a short straight
## leg without `off_road`.
const CURB_REACH := 8.0

## Gap links per network (see _gap_links), worked out once each.
static var _gap_cache := {}

var points := PackedVector2Array()
var limit := PackedFloat32Array() ## m/s at each point
var length := 0.0
## The street edges the route runs along, in order (for debugging and for
## a dispatcher wanting to know the streets a unit will take).
var edges: Array[RoadNetwork.RoadEdge] = []
## The point asked for.
var goal := Vector2.ZERO
## The streets don't reach the goal: this goes as near as they do (and, off
## road, straight on).
var partial := false
## The whole thing is one straight line.
var direct_line := false
## It starts or ends off the street, with a straight leg to or from it.
var off_street_start := false
var off_street_end := false
## How many gaps in the map it bridges.
var gaps := 0


func is_empty() -> bool:
	return points.size() < 2


## Plans a route. Options:
##   obey_oneway (true)    keep to one-way streets' direction (falls back to
##                         ignoring them if there's no legal way)
##   off_road (false)      may leave the streets (see above)
##   heading (Vector2)     the way the car points now (avoids a U-turn start)
##   lane (1.0)            1 = centre of the right-hand lane, 0 = the middle
##                         of the road (a pursuit straddles the line)
##   lat_accel (5.5)       m/s^2 allowed in corners
##   brake_accel (5.0)     m/s^2 used to slow for corners and the end
##   stop_at_end (true)    the limit falls to 0 at the end
##   top_speed (40)        m/s cap on the limit
## Empty only when there's no street near either point and not off_road.
static func plan(net: RoadNetwork, from: Vector2, to: Vector2, opts := {}) -> StreetRoute:
	var r := StreetRoute.new()
	r.goal = to
	var obey := bool(opts.get("obey_oneway", true))
	var off_road := bool(opts.get("off_road", false))
	var heading: Vector2 = opts.get("heading", Vector2.ZERO)
	var s0 := net.nearest_on_streets(from, NEAR_STREET)
	var g0 := net.nearest_on_streets(to, NEAR_STREET)
	if s0.is_empty() or g0.is_empty():
		return direct(from, to, opts) if off_road else r
	if off_road:
		# Across open ground from off the street to off the street, near
		# enough: straight there (the driver steers round what's in the way).
		var s_off := float(s0["dist"]) - (s0["edge"] as RoadNetwork.RoadEdge).half_width
		var g_off := float(g0["dist"]) - (g0["edge"] as RoadNetwork.RoadEdge).half_width
		var span := from.distance_to(to)
		if span < 12.0 or (s_off > 6.0 and g_off > 6.0 and span < 200.0):
			return direct(from, to, opts)
	var found := _search(net, s0, g0, obey, heading)
	if found["partial"] and obey:
		var loose := _search(net, s0, g0, false, heading)
		if not loose["partial"]:
			found = loose
	var pieces: Array = found["pieces"]
	r.partial = found["partial"]
	var lane := float(opts.get("lane", 1.0))
	var raw := PackedVector2Array()
	for pc: Array in pieces:
		var e: RoadNetwork.RoadEdge = pc[0]
		var pts: PackedVector2Array = pc[1]
		var forward: bool = pc[2]
		var shifted := pts
		if e != null:
			r.edges.append(e)
			shifted = _offset_line(pts, _lane_offset(e, forward) * lane)
		else:
			r.gaps += 1
		for p in shifted:
			if raw.is_empty() or raw[raw.size() - 1].distance_squared_to(p) > 0.04:
				raw.append(p)
	if raw.size() < 2:
		if off_road:
			return direct(from, to, opts)
		# Already on the street as near the goal as it goes.
		var sp: Vector2 = s0["pos"]
		raw = PackedVector2Array([sp, sp + (s0["dir"] as Vector2) * 0.5])
	# From where the car is onto the lane.
	var s_edge: RoadNetwork.RoadEdge = s0["edge"]
	var lead := from.distance_to(raw[0])
	if lead > 0.5 and (off_road or float(s0["dist"]) < s_edge.half_width + CURB_REACH):
		r.off_street_start = float(s0["dist"]) > s_edge.half_width + 1.0
		raw.insert(0, from)
		if raw.size() > 2 and (raw[2] - raw[1]).dot(raw[1] - raw[0]) < 0.0 and raw[0].distance_to(raw[1]) < 8.0:
			raw.remove_at(1) # don't step back to the lane only to turn round
	# From the lane to the goal, when it's off the street.
	var g_edge: RoadNetwork.RoadEdge = g0["edge"]
	var off_by := float(g0["dist"]) - g_edge.half_width
	if off_road and (r.partial or off_by > 1.0):
		r.off_street_end = true
		raw.append(to)
	elif not r.partial and off_by > 1.0 and off_by < CURB_REACH:
		raw.append(to) # onto the sidewalk or a driveway beside the street
	r._finish(raw, opts)
	return r


## One straight line, for open ground.
static func direct(from: Vector2, to: Vector2, opts := {}) -> StreetRoute:
	var r := StreetRoute.new()
	r.goal = to
	r.direct_line = true
	r.off_street_start = true
	r.off_street_end = true
	if from.distance_to(to) < 0.5:
		to = from + Vector2(0.0, 0.5)
	r._finish(PackedVector2Array([from, to]), opts)
	return r


## A route along a given line (already in the lane): for tests and for
## anything that wants to drive a drawn path.
static func along(line: PackedVector2Array, opts := {}) -> StreetRoute:
	var r := StreetRoute.new()
	if line.size() >= 2:
		r.goal = line[line.size() - 1]
		r._finish(line, opts)
	return r


func _finish(raw: PackedVector2Array, opts: Dictionary) -> void:
	points = _resample(raw, STEP)
	points = _smooth(points, 3, 2)
	length = STEP * (points.size() - 1)
	var lat := float(opts.get("lat_accel", 5.5))
	var brake := float(opts.get("brake_accel", 5.0))
	var top := float(opts.get("top_speed", 40.0))
	var n := points.size()
	limit.resize(n)
	const SPAN := 3 # samples each side for the curvature
	for i in n:
		var a := points[maxi(i - SPAN, 0)]
		var b := points[i]
		var c := points[mini(i + SPAN, n - 1)]
		var d1 := b - a
		var d2 := c - b
		var k := 0.0
		if d1.length() > 0.1 and d2.length() > 0.1:
			k = absf(d1.angle_to(d2)) / ((d1.length() + d2.length()) * 0.5)
		limit[i] = minf(top, sqrt(lat / maxf(k, 0.0001)))
	if bool(opts.get("stop_at_end", true)):
		limit[n - 1] = 0.0
	# Slow down ahead of each corner by what the brakes can do.
	for i in range(n - 2, -1, -1):
		limit[i] = minf(limit[i], sqrt(limit[i + 1] * limit[i + 1] + 2.0 * brake * STEP))


# --- queries -------------------------------------------------------------------

## Position at a distance along the line (clamped to its ends).
func sample(d: float) -> Vector2:
	var f := clampf(d / STEP, 0.0, points.size() - 1.0)
	var i := mini(int(f), points.size() - 2)
	return points[i].lerp(points[i + 1], f - i)


## Direction of travel at a distance along the line.
func dir_at(d: float) -> Vector2:
	var i := clampi(int(d / STEP), 0, points.size() - 2)
	return (points[i + 1] - points[i]).normalized()


## The speed limit (m/s) at a distance along the line.
func limit_at(d: float) -> float:
	var f := clampf(d / STEP, 0.0, points.size() - 1.0)
	var i := mini(int(f), points.size() - 2)
	return lerpf(limit[i], limit[i + 1], f - i)


## Distance along the line nearest p, searching from `hint` (the last
## answer) a little back and further forward, so a route that doubles back
## past itself isn't confused. A negative hint searches the whole line.
func project(p: Vector2, hint := -1.0, ahead := 60.0) -> float:
	var i0 := 0
	var i1 := points.size() - 2
	if hint >= 0.0:
		i0 = maxi(0, int((hint - 10.0) / STEP))
		i1 = mini(points.size() - 2, int((hint + ahead) / STEP) + 1)
	var best := INF
	var best_d := 0.0
	for i in range(i0, i1 + 1):
		var a := points[i]
		var b := points[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var dd := p.distance_squared_to(q)
		if dd < best:
			best = dd
			best_d = i * STEP + a.distance_to(q)
	return best_d


## How far p is from the line near distance d.
func off_line(p: Vector2, d: float) -> float:
	return p.distance_to(sample(d))


# --- planning ------------------------------------------------------------------

## A* from the start projection to the goal projection. Returns
## {"pieces": [[edge, or null for a gap, points in travel order, forward]],
##  "partial": true if the goal wasn't reached (the pieces then go to the
##  reachable junction nearest it, or are empty if that's no nearer)}.
static func _search(net: RoadNetwork, s0: Dictionary, g0: Dictionary, obey: bool, heading: Vector2) -> Dictionary:
	var gap_links := _gap_links(net)
	var se: RoadNetwork.RoadEdge = s0["edge"]
	var s_along: float = s0["along"]
	var ge: RoadNetwork.RoadEdge = g0["edge"]
	var g_along: float = g0["along"]
	var goal_p: Vector2 = g0["pos"]
	var start_dir: Vector2 = s0["dir"] # a->b direction at the start point
	var cost := {}
	var how := {} # node -> [prev node, edge or null, forward, gap points]
	var heap := _Heap.new()
	var GOAL := "@goal"
	var START := "@start"
	# Off the start edge, either way it allows.
	for forward: bool in [true, false]:
		if obey and not _allowed(se, forward):
			continue
		var c := (se.length - s_along) if forward else s_along
		var back := heading != Vector2.ZERO and heading.dot(start_dir * (1.0 if forward else -1.0)) < -0.2
		if back:
			c += UTURN_COST
		var nid := se.b if forward else se.a
		if c < float(cost.get(nid, INF)):
			cost[nid] = c
			how[nid] = [START, se, forward, null]
			heap.push(c + goal_p.distance_to(net.nodes[nid]), nid)
		# Start and goal on the same street, the goal ahead this way.
		if se == ge and ((forward and g_along >= s_along) or (not forward and g_along <= s_along)):
			var cg := absf(g_along - s_along) + (UTURN_COST if back else 0.0)
			if cg < float(cost.get(GOAL, INF)):
				cost[GOAL] = cg
				how[GOAL] = [START, se, forward, null]
				heap.push(cg, GOAL)
	var done := {}
	var nearest := ""
	var nearest_d := INF
	while not heap.is_empty():
		var cur: String = heap.pop()
		if cur == GOAL:
			break
		if done.has(cur):
			continue
		done[cur] = true
		var cd := goal_p.distance_to(net.nodes[cur])
		if cd < nearest_d:
			nearest_d = cd
			nearest = cur
		var cc := float(cost[cur])
		# Onto the goal street and along it to the goal.
		if cur == ge.a or cur == ge.b:
			var forward := cur == ge.a
			if not obey or _allowed(ge, forward):
				var cg := cc + (g_along if forward else ge.length - g_along)
				if cg < float(cost.get(GOAL, INF)):
					cost[GOAL] = cg
					how[GOAL] = [cur, ge, forward, null]
					heap.push(cg, GOAL)
		for inc: RoadNetwork.Incident in net.incidents.get(cur, []):
			var e := inc.edge
			if obey and not _allowed(e, inc.at_start):
				continue
			var nxt := e.b if inc.at_start else e.a
			var c := cc + e.length
			if c < float(cost.get(nxt, INF)):
				cost[nxt] = c
				how[nxt] = [cur, e, inc.at_start, null]
				heap.push(c + goal_p.distance_to(net.nodes[nxt]), nxt)
		for link: Array in gap_links.get(cur, []):
			# [to node, cost, points, edge driven after the gap, forward]
			var le: RoadNetwork.RoadEdge = link[3]
			if obey and not _allowed(le, link[4]):
				continue
			var nxt: String = link[0]
			var c := cc + float(link[1])
			if c < float(cost.get(nxt, INF)):
				cost[nxt] = c
				how[nxt] = [cur, null, true, link[2]]
				heap.push(c + goal_p.distance_to(net.nodes[nxt]), nxt)
	var partial := not how.has(GOAL)
	var end := GOAL
	if partial:
		if nearest == "" or nearest_d >= goal_p.distance_to(s0["pos"]):
			return {"pieces": [], "partial": true}
		end = nearest
	var steps: Array = []
	var at := end
	while at != START:
		var h: Array = how[at]
		steps.push_front(h)
		at = h[0]
	var pieces: Array = []
	for k in steps.size():
		var e: RoadNetwork.RoadEdge = steps[k][1]
		if e == null:
			pieces.append([null, steps[k][3], true])
			continue
		var forward: bool = steps[k][2]
		var from_along := 0.0 if forward else e.length
		var to_along := e.length if forward else 0.0
		if k == 0:
			from_along = s_along
		if k == steps.size() - 1 and not partial:
			to_along = g_along
		pieces.append([e, _sub(e, from_along, to_along), forward])
	return {"pieces": pieces, "partial": partial}


## Gaps in the map: each street end (a node with one street) that comes
## within GAP_MAX of a street in another piece of the network (one it has
## no way to along the graph) is linked straight across to that street's
## nearest point and on to both of its ends, and back. Only between pieces
## that aren't joined anywhere, so it never cuts through a block between
## two streets that do meet, and it's always a short hop between streets,
## never a long run across open ground.
## node -> Array of [to node, cost, points, edge driven after the gap, forward].
static func _gap_links(net: RoadNetwork) -> Dictionary:
	var key := "%d/%d/%d" % [net.get_instance_id(), net.edges.size(), net.nodes.size()]
	if _gap_cache.has(key):
		return _gap_cache[key]
	var comp := components(net)
	var links := {}
	for nid: String in net.nodes:
		if net.degree(nid) > 1:
			continue
		var p: Vector2 = net.nodes[nid]
		var mine: int = comp.get(nid, -1)
		var best := {} # component -> [dist, edge, along, point]
		for e in net.edges_near(Rect2(p - Vector2(GAP_MAX, GAP_MAX), Vector2(GAP_MAX, GAP_MAX) * 2.0)):
			var ce: int = comp.get(e.a, -1)
			if ce == mine:
				continue
			var along := 0.0
			for i in range(e.points.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(p, e.points[i], e.points[i + 1])
				var d := p.distance_to(q)
				if d < GAP_MAX and d < float((best.get(ce, [INF]) as Array)[0]):
					best[ce] = [d, e, along + e.points[i].distance_to(q), q]
				along += e.points[i].distance_to(e.points[i + 1])
		for ce: int in best:
			var b: Array = best[ce]
			var e: RoadNetwork.RoadEdge = b[1]
			var at: float = b[2]
			var q: Vector2 = b[3]
			for forward: bool in [true, false]:
				var end_id := e.b if forward else e.a
				var there := PackedVector2Array([p, q])
				there.append_array(_sub(e, at, e.length if forward else 0.0))
				var cost := float(b[0]) * GAP_COST + (e.length - at if forward else at)
				_add_link(links, nid, [end_id, cost, there, e, forward])
				var back := there.duplicate()
				back.reverse()
				_add_link(links, end_id, [nid, cost, back, e, not forward])
	_gap_cache[key] = links
	return links


static func _add_link(links: Dictionary, from_id: String, link: Array) -> void:
	if not links.has(from_id):
		links[from_id] = []
	(links[from_id] as Array).append(link)


## Which connected piece of the street graph each node is in (node -> int).
static func components(net: RoadNetwork) -> Dictionary:
	var comp := {}
	var n := 0
	for start: String in net.nodes:
		if comp.has(start):
			continue
		var stack: Array[String] = [start]
		comp[start] = n
		while not stack.is_empty():
			var cur: String = stack.pop_back()
			for inc: RoadNetwork.Incident in net.incidents.get(cur, []):
				var o := inc.edge.b if inc.at_start else inc.edge.a
				if not comp.has(o):
					comp[o] = n
					stack.append(o)
		n += 1
	return comp


static func _allowed(e: RoadNetwork.RoadEdge, forward: bool) -> bool:
	return e.oneway == 0 or (e.oneway == 1) == forward


## The part of an edge's line between two distances along it, in the order
## from -> to (reversed when to < from).
static func _sub(e: RoadNetwork.RoadEdge, from_along: float, to_along: float) -> PackedVector2Array:
	var lo := minf(from_along, to_along)
	var hi := maxf(from_along, to_along)
	var out := PackedVector2Array()
	var run := 0.0
	var pts := e.points
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		var t0 := run
		var t1 := run + seg
		if t1 >= lo and t0 <= hi and seg > 0.0001:
			var a := pts[i].lerp(pts[i + 1], clampf((lo - t0) / seg, 0.0, 1.0))
			var b := pts[i].lerp(pts[i + 1], clampf((hi - t0) / seg, 0.0, 1.0))
			if out.is_empty():
				out.append(a)
			if out[out.size() - 1].distance_squared_to(b) > 0.0001:
				out.append(b)
		run = t1
	if out.is_empty():
		out.append(e.points[0] if lo <= 0.0 else e.points[e.points.size() - 1])
	if out.size() == 1:
		out.append(out[0])
	if to_along < from_along:
		out.reverse()
	return out


## How far right of the centreline (metres) to drive along e: the middle of
## the inside lane on our side of a two-way street, the middle of a one-way
## street (or of a two-way one driven against a one-way sign, in a chase).
static func _lane_offset(e: RoadNetwork.RoadEdge, forward: bool) -> float:
	if e.oneway != 0:
		# One lane of traffic: the middle of what the parked cars leave. On a
		# narrow one-way with cars along one curb (Kent Street: 6.5 m, parked
		# on the right) the middle of the street is only a hand's width from
		# their mirrors, so keep to the free side.
		var right := 1 if forward else -1
		var shift := 0.0
		if curb_parking(e, right):
			shift -= PARKING_LANE * 0.5
		if curb_parking(e, -right):
			shift += PARKING_LANE * 0.5
		return clampf(shift, -maxf(0.0, e.half_width - 1.1), maxf(0.0, e.half_width - 1.1))
	# Clear of the cars parked along our curb, where there are any.
	var usable := e.half_width - (PARKING_LANE if curb_parking(e, 1 if forward else -1) else 0.4)
	var per_side := maxi(1, e.lanes / 2)
	return maxf(usable / per_side * 0.5, minf(1.0, e.half_width * 0.4))


## The width of the strip parked cars take along a curb (they stand 1.15 m
## in from it, StreetProps._curb_parking), with room to pass.
const PARKING_LANE := 2.4


## Whether StreetProps parks cars along this side of a street (+1 the right
## driving a->b): the same rule it uses, by class and width.
static func curb_parking(e: RoadNetwork.RoadEdge, side: int) -> bool:
	if e.is_highway() or e.bridge or e.roundabout:
		return false
	if not (e.highway in ["residential", "unclassified", "tertiary", "secondary"]):
		return false
	var width := e.half_width * 2.0
	if e.oneway != 0:
		return width >= 9.5 or (width >= 6.0 and side == 1)
	if width >= 10.5:
		return true
	if width >= 8.0:
		return side == (1 if (e.name.hash() & 1) == 0 else -1)
	return false


static func _offset_line(pts: PackedVector2Array, off: float) -> PackedVector2Array:
	if is_zero_approx(off) or pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d0 := (pts[i] - pts[maxi(i - 1, 0)]).normalized()
		var d1 := (pts[mini(i + 1, n - 1)] - pts[i]).normalized()
		if i == 0:
			d0 = d1
		if i == n - 1:
			d1 = d0
		var d := (d0 + d1).normalized()
		if d == Vector2.ZERO:
			d = d1
		# Mitered, but never more than twice the offset at a sharp bend.
		var m := 1.0 / maxf(0.5, d.dot(d1))
		out.append(pts[i] + Vector2(-d.y, d.x) * off * m)
	return out


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	var last := pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(last) > step * 0.25:
		out.append(last)
	if out.size() < 2:
		out.append(last)
	return out


## Rounds the corners: a moving average over +-half samples, `passes` times,
## ends held where they are.
static func _smooth(pts: PackedVector2Array, half: int, passes: int) -> PackedVector2Array:
	var cur := pts
	var n := pts.size()
	for _p in passes:
		var nxt := cur.duplicate()
		for i in range(1, n - 1):
			var h := mini(half, mini(i, n - 1 - i))
			var sum := Vector2.ZERO
			for j in range(i - h, i + h + 1):
				sum += cur[j]
			nxt[i] = sum / float(2 * h + 1)
		cur = nxt
	return cur


## A small binary min-heap of [priority, key].
class _Heap:
	var _p := PackedFloat64Array()
	var _k: Array[String] = []

	func is_empty() -> bool:
		return _k.is_empty()

	func push(pri: float, key: String) -> void:
		_p.append(pri)
		_k.append(key)
		var i := _k.size() - 1
		while i > 0:
			var up := (i - 1) / 2
			if _p[up] <= _p[i]:
				break
			_swap(i, up)
			i = up

	func pop() -> String:
		var top := _k[0]
		var last := _k.size() - 1
		_swap(0, last)
		_p.resize(last)
		_k.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and _p[l] < _p[m]:
				m = l
			if r < last and _p[r] < _p[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tp := _p[a]
		_p[a] = _p[b]
		_p[b] = tp
		var tk := _k[a]
		_k[a] = _k[b]
		_k[b] = tk

class_name RoadNetwork
extends RefCounted
## The drivable street network as a graph, plus the geometry helpers that
## turn it into curbs and sidewalks.
##
## Nodes are OSM junctions and road ends; edges are the stretches of street
## between them (OSM polylines, unchanged). Everything that needs to know
## "where is the curb" or "where is the sidewalk" asks this class, so roads,
## sidewalks, markings, props, pedestrians and the minimap all line up.
##
## Conventions (ground plane Vector2(x, z), +x east, +z south):
##   * At a node, each incident edge has a unit direction `dir` pointing away
##     from the node. Incidents are sorted by angle.
##   * perp(d) = Vector2(-d.y, d.x) is the RIGHT-hand side when travelling
##     along d. Side +1 of an edge means the right side driving from a to b.

enum Level { CURB, WALK, PROP, BACK }

## Height of the sidewalk top above the road surface.
const SIDEWALK_HEIGHT := 0.12


class RoadEdge:
	var index: int
	var name: String
	var highway: String
	var oneway: int ## 0 two-way, 1 one-way a->b, -1 one-way b->a
	var a: String
	var b: String
	var points: PackedVector2Array
	var half_width: float
	var sidewalk: float
	var length: float


class Incident:
	var edge: RoadEdge
	var at_start: bool
	var dir: Vector2
	var angle: float


var nodes: Dictionary = {} ## node id -> Vector2
var incidents: Dictionary = {} ## node id -> Array[Incident], sorted by angle
var edges: Array[RoadEdge] = []


func _init(data: StreetData) -> void:
	_build(data)


# --- construction -------------------------------------------------------------

func _build(data: StreetData) -> void:
	var classes: Array = data.config.get("drivable_classes", [])
	var usable: Array[StreetData.Road] = []
	var use_count: Dictionary = {}
	for r in data.roads:
		if not classes.has(r.highway):
			continue
		usable.append(r)
		var last := r.nodes.size() - 1
		for i in r.nodes.size():
			var bump := 2 if (i == 0 or i == last) else 1
			use_count[r.nodes[i]] = int(use_count.get(r.nodes[i], 0)) + bump

	for r in usable:
		var style := data.road_style(r.name, r.highway)
		var start := 0
		for i in range(1, r.nodes.size()):
			var is_split := int(use_count.get(r.nodes[i], 0)) >= 2 or i == r.nodes.size() - 1
			if not is_split:
				continue
			var pts := r.points.slice(start, i + 1)
			_add_edge(r, r.nodes[start], r.nodes[i], pts, style)
			start = i

	for nid: String in incidents:
		var list: Array = incidents[nid]
		list.sort_custom(func(x: Incident, y: Incident) -> bool: return x.angle < y.angle)


func _add_edge(r: StreetData.Road, a: String, b: String, pts: PackedVector2Array, style: Vector2) -> void:
	if a == b or pts.size() < 2:
		return
	var e := RoadEdge.new()
	e.index = edges.size()
	e.name = r.name
	e.highway = r.highway
	e.oneway = r.oneway
	e.a = a
	e.b = b
	e.points = pts
	e.half_width = style.x * 0.5
	e.sidewalk = style.y
	e.length = polyline_length(pts)
	if e.length < 0.5:
		return
	edges.append(e)
	nodes[a] = pts[0]
	nodes[b] = pts[pts.size() - 1]
	_add_incident(a, e, true)
	_add_incident(b, e, false)


func _add_incident(nid: String, e: RoadEdge, at_start: bool) -> void:
	var inc := Incident.new()
	inc.edge = e
	inc.at_start = at_start
	inc.dir = _leaving_dir(e.points, at_start)
	inc.angle = atan2(inc.dir.y, inc.dir.x)
	if not incidents.has(nid):
		incidents[nid] = []
	incidents[nid].append(inc)


## Direction leaving the end of a polyline, measured over the first few metres
## so a tiny kink in the OSM line does not swing the whole intersection.
static func _leaving_dir(pts: PackedVector2Array, from_start: bool) -> Vector2:
	var n := pts.size()
	var origin := pts[0] if from_start else pts[n - 1]
	for k in range(1, n):
		var q := pts[k] if from_start else pts[n - 1 - k]
		if origin.distance_to(q) >= 4.0 or k == n - 1:
			return (q - origin).normalized()
	return Vector2.RIGHT


# --- queries -------------------------------------------------------------------

func degree(nid: String) -> int:
	return (incidents.get(nid, []) as Array).size()


## Offset from the road centreline (metres) for a given level along edge e.
func offset_for(e: RoadEdge, level: int) -> float:
	match level:
		Level.CURB:
			return e.half_width
		Level.WALK:
			return e.half_width + e.sidewalk * 0.6
		Level.PROP:
			return e.half_width + minf(0.55, e.sidewalk * 0.3)
		_:
			return e.half_width + e.sidewalk


func incident_index(nid: String, e: RoadEdge, at_start: bool) -> int:
	var list: Array = incidents.get(nid, [])
	for k in list.size():
		var inc: Incident = list[k]
		if inc.edge == e and inc.at_start == at_start:
			return k
	return -1


## The corner point in the sector between incident k and incident k+1 at
## node nid: `offset_for(level)` metres from each of the two streets.
## This is the right-hand side of incident k.
func corner_right(nid: String, k: int, level: int) -> Vector2:
	var list: Array = incidents[nid]
	var center: Vector2 = nodes[nid]
	var inc_i: Incident = list[k]
	var hi := offset_for(inc_i.edge, level)
	if list.size() == 1:
		return center + _perp(inc_i.dir) * hi
	var inc_j: Incident = list[(k + 1) % list.size()]
	return center + _solve_corner(inc_i.dir, hi, inc_j.dir, offset_for(inc_j.edge, level))


## The left-hand side of incident k (= the right-hand corner of incident k-1).
func corner_left(nid: String, k: int, level: int) -> Vector2:
	var list: Array = incidents[nid]
	if list.size() == 1:
		var inc: Incident = list[0]
		return (nodes[nid] as Vector2) - _perp(inc.dir) * offset_for(inc.edge, level)
	return corner_right(nid, (k - 1 + list.size()) % list.size(), level)


## Offset v from the node such that v is hi to the right of street i and hj to
## the left of street j (j is the next street counter-clockwise... in angle order).
static func _solve_corner(di: Vector2, hi: float, dj: Vector2, hj: float) -> Vector2:
	var p_i := _perp(di)
	var pj := _perp(dj)
	# dot(v, p_i) = hi and dot(v, pj) = -hj
	var det := p_i.x * pj.y - p_i.y * pj.x
	if absf(det) < 0.08:
		# The two streets are (nearly) in line: the corner just sits beside them.
		return p_i * (hi + hj) * 0.5
	var v := Vector2((hi * pj.y + p_i.y * hj) / det, (-p_i.x * hj - pj.x * hi) / det)
	var limit := maxf(hi, hj) * 4.0
	if v.length() > limit:
		v = v.normalized() * limit
	return v


static func _perp(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## A line running alongside edge e at the given level, from node a to node b.
## side = +1 for the right-hand side driving a->b, -1 for the left. The ends
## are the junction corners, so lines from neighbouring streets meet exactly.
func side_line(e: RoadEdge, side: int, level: int) -> PackedVector2Array:
	var ka := incident_index(e.a, e, true)
	var kb := incident_index(e.b, e, false)
	var off := offset_for(e, level) * float(side)
	var out := PackedVector2Array()
	out.append(corner_right(e.a, ka, level) if side > 0 else corner_left(e.a, ka, level))
	for i in range(1, e.points.size() - 1):
		out.append(_miter(e.points[i - 1], e.points[i], e.points[i + 1], off))
	# At b the edge points back towards a, so its right/left are swapped.
	out.append(corner_left(e.b, kb, level) if side > 0 else corner_right(e.b, kb, level))
	return out


static func _miter(prev: Vector2, cur: Vector2, next: Vector2, off: float) -> Vector2:
	var n1 := _perp((cur - prev).normalized())
	var n2 := _perp((next - cur).normalized())
	var m := (n1 + n2)
	if m.length() < 0.001:
		return cur + n1 * off
	m = m.normalized()
	return cur + m * (off / maxf(m.dot(n1), 0.3))


## How far from the node, along incident k, the road leaves the junction box.
func mouth_distance(nid: String, k: int) -> float:
	if degree(nid) < 3:
		return 0.0
	var inc: Incident = incidents[nid][k]
	var center: Vector2 = nodes[nid]
	var l := corner_left(nid, k, Level.CURB) - center
	var r := corner_right(nid, k, Level.CURB) - center
	return maxf(0.0, maxf(l.dot(inc.dir), r.dot(inc.dir)))


## Curb corners around a junction, in angle order.
func junction_polygon(nid: String, level: int = Level.CURB) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in degree(nid):
		out.append(corner_right(nid, k, level))
	return out


## Junction where two named streets meet (the busiest one if several match).
func find_junction(street_a: String, street_b: String) -> String:
	var best := ""
	var best_deg := 0
	for nid: String in incidents:
		var has_a := false
		var has_b := false
		for inc: Incident in incidents[nid]:
			has_a = has_a or inc.edge.name == street_a
			has_b = has_b or inc.edge.name == street_b
		if has_a and has_b and degree(nid) > best_deg:
			best = nid
			best_deg = degree(nid)
	return best


## Closest point on any street centreline. Returns {edge, pos, dist, along, dir}.
func nearest_on_streets(p: Vector2, max_dist: float = INF) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for e in edges:
		var along := 0.0
		for i in range(e.points.size() - 1):
			var s0 := e.points[i]
			var s1 := e.points[i + 1]
			var q := Geometry2D.get_closest_point_to_segment(p, s0, s1)
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = {"edge": e, "pos": q, "dist": d, "along": along + s0.distance_to(q), "dir": (s1 - s0).normalized()}
			along += s0.distance_to(s1)
	return best


# --- polyline helpers -----------------------------------------------------------

static func polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


## Position and direction at a distance along a polyline.
static func sample(pts: PackedVector2Array, dist: float) -> Array:
	var remaining := dist
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if remaining <= seg or i == pts.size() - 2:
			var d := (pts[i + 1] - pts[i]).normalized()
			return [pts[i] + d * clampf(remaining, 0.0, seg), d]
		remaining -= seg
	return [pts[0], Vector2.RIGHT]

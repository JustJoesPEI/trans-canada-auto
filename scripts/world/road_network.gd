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
##
## Each side of a street has its own sidewalk width: highways have none, and
## the inner side of a divided road (two one-way carriageways side by side,
## like University Avenue or the Arterial Highway) has only a median curb.

enum Level { CURB, WALK, PROP, BACK }

## Height of the sidewalk top above the road surface.
const SIDEWALK_HEIGHT := 0.12


## Two streets leaving a node closer together than this (the cosine of the
## angle between them, about 45 degrees) are a shallow fork: see line_corner.
const SHALLOW_DOT := 0.7

## Width of the median curb on the inner side of a divided road.
const MEDIAN_CURB := 0.6
## A divided road's median narrower than twice this is paved all the way
## across instead of being two curbs with a strip of grass between.
const MEDIAN_FILL := 1.8


class RoadEdge:
	var index: int
	var name: String
	var highway: String
	var oneway: int ## 0 two-way, 1 one-way a->b, -1 one-way b->a
	var a: String
	var b: String
	var points: PackedVector2Array
	var half_width: float
	var sidewalk: float ## the usual sidewalk width (both sides unless set below)
	var sidewalk_right := -1.0 ## right side driving a->b; -1 = same as sidewalk
	var sidewalk_left := -1.0
	var shoulder := 0.0 ## paved strip outside the edge line (highway style)
	var length: float
	var bridge := false
	var roundabout := false
	var lanes := 0
	var bounds: Rect2 ## centreline bounds, for quick area tests

	## Sidewalk width on side +1 (right, a->b) or -1.
	func walk(side: int) -> float:
		var w := sidewalk_right if side > 0 else sidewalk_left
		return sidewalk if w < 0.0 else w

	## Highways and ramps: shoulders, no sidewalks, edge lines.
	func is_highway() -> bool:
		return shoulder > 0.0


class Incident:
	var edge: RoadEdge
	var at_start: bool
	var dir: Vector2
	var angle: float


var nodes: Dictionary = {} ## node id -> Vector2
var incidents: Dictionary = {} ## node id -> Array[Incident], sorted by angle
var edges: Array[RoadEdge] = []
## Edges paved in brick (Victoria Row), set by RoadMesher.find_brick_edges.
var brick_edges: Dictionary = {}
## Where the zebra crossings are: RoadEdge -> Array of distances along it
## (their middles), set by RoadMesher.find_crosswalks.
var crosswalks: Dictionary = {}
## Curb polygon of every junction of three or more streets (node id -> poly),
## worked out once so worker threads only ever read it.
var junction_polys: Dictionary = {}
## Raised islands in the middle of roundabouts (polygons).
var islands: Array[PackedVector2Array] = []

## Edges by grid cell, for nearest-street and area queries.
const GRID := 100.0
var _grid: Dictionary = {} ## Vector2i -> Array[RoadEdge]


## How many pairs of junctions were merged because they were too close to
## fit both (see _close_pairs).
var merged_junctions := 0


func _init(data: StreetData) -> void:
	var usable := _usable(data)
	_build(data, usable)
	# Junctions too close together to fit both are merged into one, and the
	# network built again.
	var groups := _close_pairs()
	if not groups.is_empty():
		merged_junctions = groups.size()
		var roads := _merge_roads(usable, groups)
		nodes.clear()
		incidents.clear()
		edges.clear()
		_grid.clear()
		junction_polys.clear()
		islands.clear()
		_build(data, roads)


# --- construction -------------------------------------------------------------

func _usable(data: StreetData) -> Array[StreetData.Road]:
	var classes: Array = data.config.get("drivable_classes", [])
	var usable: Array[StreetData.Road] = []
	for r in data.roads:
		if classes.has(r.highway):
			usable.append(r)
	return usable


## Junction pairs joined by a stretch of street too short to hold both
## junction boxes (the curbs would cross). Roundabouts are left alone: their
## shape matters more. Returns {node id: id of the node it merges into}.
func _close_pairs() -> Dictionary:
	var parent := {}
	var find := func(x: String) -> String:
		while parent.has(x) and parent[x] != x:
			x = parent[x]
		return x
	for e in edges:
		if e.roundabout or degree(e.a) < 3 or degree(e.b) < 3:
			continue
		if _touches_roundabout(e.a) or _touches_roundabout(e.b):
			continue
		var need := mouth_distance(e.a, incident_index(e.a, e, true)) + mouth_distance(e.b, incident_index(e.b, e, false))
		if need > e.length + 0.5:
			var ra: String = find.call(e.a)
			var rb: String = find.call(e.b)
			if ra != rb:
				parent[rb] = ra
				parent[ra] = ra
	var out := {}
	for x: String in parent:
		var r: String = find.call(x)
		if r != x:
			out[x] = r
	return out


func _touches_roundabout(nid: String) -> bool:
	for inc: Incident in incidents.get(nid, []):
		if inc.edge.roundabout:
			return true
	return false


## Copies of the roads with merged junctions moved to their shared middle.
func _merge_roads(usable: Array[StreetData.Road], merge_into: Dictionary) -> Array[StreetData.Road]:
	var members := {}
	for nid: String in merge_into:
		var rep: String = merge_into[nid]
		if not members.has(rep):
			members[rep] = [rep]
		members[rep].append(nid)
	var where := {}
	for rep: String in members:
		var sum := Vector2.ZERO
		for m: String in members[rep]:
			sum += nodes[m]
		where[rep] = sum / float((members[rep] as Array).size())
	var out: Array[StreetData.Road] = []
	for r in usable:
		var c := StreetData.Road.new()
		c.id = r.id
		c.name = r.name
		c.highway = r.highway
		c.oneway = r.oneway
		c.tags = r.tags
		for i in r.nodes.size():
			var nid := r.nodes[i]
			var p := r.points[i]
			if merge_into.has(nid):
				nid = merge_into[nid]
			if where.has(nid):
				p = where[nid]
			if c.nodes.size() > 0 and c.nodes[c.nodes.size() - 1] == nid:
				continue
			c.nodes.append(nid)
			c.points.append(p)
		if c.nodes.size() >= 2:
			out.append(c)
	return out


func _build(data: StreetData, usable: Array[StreetData.Road]) -> void:
	var use_count: Dictionary = {}
	for r in usable:
		var last := r.nodes.size() - 1
		for i in r.nodes.size():
			var bump := 2 if (i == 0 or i == last) else 1
			use_count[r.nodes[i]] = int(use_count.get(r.nodes[i], 0)) + bump

	var pieces: Array[Piece] = []
	for r in usable:
		var style := data.road_style(r.name, r.highway, r.tags)
		var start := 0
		for i in range(1, r.nodes.size()):
			var is_split := int(use_count.get(r.nodes[i], 0)) >= 2 or i == r.nodes.size() - 1
			if not is_split:
				continue
			var pc := Piece.new()
			pc.road = r
			pc.a = r.nodes[start]
			pc.b = r.nodes[i]
			pc.pts = r.points.slice(start, i + 1)
			pc.style = style
			pc.oneway = r.oneway
			pieces.append(pc)
			start = i
	for pc in _join_pieces(pieces):
		_add_edge(pc.road, pc.a, pc.b, pc.pts, pc.style, pc.oneway)

	for nid: String in incidents:
		var list: Array = incidents[nid]
		list.sort_custom(func(x: Incident, y: Incident) -> bool: return x.angle < y.angle)
	for e in edges:
		_index_edge(e)
	_find_medians()
	_find_roundabouts()
	for nid: String in incidents:
		if degree(nid) >= 3:
			junction_polys[nid] = junction_polygon(nid)


## A stretch of one OSM way between two split points, before it becomes an edge.
class Piece:
	var road: StreetData.Road
	var a: String
	var b: String
	var pts: PackedVector2Array
	var style: Vector3
	var oneway: int


## OSM splits a street into several ways wherever a tag changes (a bus
## route, a speed limit, a bridge), and every split would otherwise be a
## node where two edges meet end to end: a break in the paint, a seam in the
## curb and a place where each roadway hides the other. Where exactly two
## pieces meet and they would be built the same, they are joined into one.
func _join_pieces(pieces: Array[Piece]) -> Array[Piece]:
	var at := {} ## node id -> Array[Piece]
	for pc in pieces:
		for nid: String in [pc.a, pc.b]:
			if not at.has(nid):
				at[nid] = []
			at[nid].append(pc)
	var alive := {}
	for pc in pieces:
		alive[pc] = true
	for nid: String in at:
		var list: Array = at[nid]
		if list.size() != 2:
			continue
		var p: Piece = list[0]
		var q: Piece = list[1]
		if p == q or not alive.has(p) or not alive.has(q) or not _same_build(p, q):
			continue
		# Orient p to end at nid and q to start there.
		if p.a == nid:
			_flip(p)
		if q.b == nid:
			_flip(q)
		if p.b != nid or q.a != nid or p.a == q.b:
			continue # a closed loop (a whole roundabout) stays in two pieces
		if p.oneway != q.oneway:
			continue # one-way in opposite directions: not one street
		var bend := (p.pts[p.pts.size() - 1] - p.pts[p.pts.size() - 2]).normalized().dot((q.pts[1] - q.pts[0]).normalized())
		if bend < 0.0:
			continue # doubles back on itself: leave the node in
		var joined := p.pts.duplicate()
		joined.append_array(q.pts.slice(1))
		p.pts = joined
		p.b = q.b
		alive.erase(q)
		# q's far end now belongs to p.
		var far: Array = at[q.b]
		far[far.find(q)] = p
	var out: Array[Piece] = []
	for pc in pieces:
		if alive.has(pc):
			out.append(pc)
	return out


static func _flip(pc: Piece) -> void:
	var t := pc.a
	pc.a = pc.b
	pc.b = t
	var r := pc.pts.duplicate()
	r.reverse()
	pc.pts = r
	pc.oneway = -pc.oneway


static func _same_build(p: Piece, q: Piece) -> bool:
	if p.road.name != q.road.name or p.road.highway != q.road.highway or not p.style.is_equal_approx(q.style):
		return false
	if (p.oneway == 0) != (q.oneway == 0):
		return false
	for tag: String in ["bridge", "junction", "lanes", "sidewalk", "service"]:
		if str(p.road.tags.get(tag, "")) != str(q.road.tags.get(tag, "")):
			return false
	return true


func _add_edge(r: StreetData.Road, a: String, b: String, pts: PackedVector2Array, style: Vector3, oneway: int) -> void:
	if a == b or pts.size() < 2:
		return
	var e := RoadEdge.new()
	e.index = edges.size()
	e.name = r.name
	e.highway = r.highway
	e.oneway = oneway
	e.a = a
	e.b = b
	e.points = pts
	e.half_width = style.x * 0.5
	e.sidewalk = maxf(style.y, 0.0)
	e.shoulder = style.z
	e.bridge = str(r.tags.get("bridge", "no")) not in ["no", ""]
	e.roundabout = str(r.tags.get("junction", "")) in ["roundabout", "circular"]
	e.lanes = str(r.tags.get("lanes", "")).to_int()
	e.length = polyline_length(pts)
	e.bounds = Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		e.bounds = e.bounds.expand(p)
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


## Offset from the road centreline (metres) for a given level along edge e,
## on side +1 (right, driving a->b) or -1.
func offset_for(e: RoadEdge, level: int, side: int = 1) -> float:
	var w := e.walk(side)
	match level:
		Level.CURB:
			return e.half_width
		Level.WALK:
			return e.half_width + w * 0.6
		Level.PROP:
			if w <= 0.0:
				return e.half_width + 1.2 # on the verge beside a highway
			return e.half_width + minf(0.55, w * 0.3)
		_:
			return e.half_width + w


## Which side of its edge (+1 right / -1 left, driving a->b) is on the
## right of an incident (looking out from the junction along it).
static func _right_side(inc: Incident) -> int:
	return 1 if inc.at_start else -1


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
	var hi := offset_for(inc_i.edge, level, _right_side(inc_i))
	if list.size() == 1:
		return center + _perp(inc_i.dir) * hi
	var inc_j: Incident = list[(k + 1) % list.size()]
	return center + _solve_corner(inc_i.dir, hi, inc_j.dir, offset_for(inc_j.edge, level, -_right_side(inc_j)))


## The left-hand side of incident k (= the right-hand corner of incident k-1).
func corner_left(nid: String, k: int, level: int) -> Vector2:
	var list: Array = incidents[nid]
	if list.size() == 1:
		var inc: Incident = list[0]
		return (nodes[nid] as Vector2) - _perp(inc.dir) * offset_for(inc.edge, level, -_right_side(inc))
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
	# Very shallow angles (a ramp joining a highway) would put the corner far
	# down the road; keep it within a couple of road widths and let the two
	# roadways themselves cover the rest.
	var limit := maxf(hi, hj) * 2.5
	if v.length() > limit:
		v = v.normalized() * limit
	return v


static func _perp(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## A line running alongside edge e at the given level, from node a to node b.
## side = +1 for the right-hand side driving a->b, -1 for the left. The ends
## are the junction corners, so lines from neighbouring streets meet exactly.
## Where the street carries straight on into a wider or narrower one, the
## wider of the two tapers to meet the narrower instead of stepping out.
func side_line(e: RoadEdge, side: int, level: int) -> PackedVector2Array:
	var ka := incident_index(e.a, e, true)
	var kb := incident_index(e.b, e, false)
	var own := offset_for(e, level, side)
	# At b the edge points back towards a, so its right/left are swapped.
	var seam_a := _seam(e.a, ka, level, side > 0)
	var seam_b := _seam(e.b, kb, level, side < 0)
	var la := taper_length(e, e.a, ka)
	var lb := taper_length(e, e.b, kb)
	var out := PackedVector2Array()
	out.append(line_corner(e.a, ka, level, side > 0))
	for st in stations(e):
		var along := st.x
		var o := own
		if seam_a >= 0.0 and along < la:
			o = lerpf(seam_a, own, along / la)
		if seam_b >= 0.0 and e.length - along < lb:
			o = lerpf(seam_b, own, (e.length - along) / lb)
		var i := int(st.y)
		if i > 0:
			out.append(_miter(e.points[i - 1], e.points[i], e.points[i + 1], o * float(side)))
		else:
			var sp := sample(e.points, along)
			out.append((sp[0] as Vector2) + _perp(sp[1]) * o * float(side))
	out.append(line_corner(e.b, kb, level, side < 0))
	return out


## Where a side line of incident k starts: the junction corner it shares
## with the next street round (right) or the one before (left). Two streets
## leaving at a shallow angle (a ramp, a road forking) have no sensible
## shared corner: their curbs only cross far down the road. There each
## street starts square across its own end and the two roadways overlap.
func line_corner(nid: String, k: int, level: int, right: bool) -> Vector2:
	var list: Array = incidents[nid]
	var n := list.size()
	if n >= 2:
		var inc: Incident = list[k]
		var center: Vector2 = nodes[nid]
		var seam := _seam(nid, k, level, right)
		if seam >= 0.0:
			return center + _perp(inc.dir) * seam * (1.0 if right else -1.0)
		var other: Incident = list[(k + 1) % n] if right else list[(k - 1 + n) % n]
		if inc.dir.dot(other.dir) > SHALLOW_DOT:
			var side := _right_side(inc) if right else -_right_side(inc)
			return center + _perp(inc.dir) * offset_for(inc.edge, level, side) * (1.0 if right else -1.0)
	return corner_right(nid, k, level) if right else corner_left(nid, k, level)


## Where incident k carries straight on through node nid into another street
## (with nothing crossing on that side, though a ramp may fork off), the
## offset both streets' side lines share at the node: the narrower of the
## two, so the wider one tapers in to meet it. -1 if there is no such street.
func _seam(nid: String, k: int, level: int, right: bool) -> float:
	var list: Array = incidents.get(nid, [])
	var n := list.size()
	if n < 2:
		return -1.0
	var inc: Incident = list[k]
	var t := _through(nid, k)
	if t < 0 or _through(nid, t) != k:
		return -1.0
	var thru: Incident = list[t]
	var step := 1 if right else -1
	var m := (k + step + n) % n
	while m != t:
		var mid: Incident = list[m]
		if mid.dir.dot(inc.dir) <= SHALLOW_DOT and mid.dir.dot(thru.dir) <= SHALLOW_DOT:
			return -1.0 # a street crosses on this side: a real corner
		m = (m + step + n) % n
	var own := offset_for(inc.edge, level, _right_side(inc) if right else -_right_side(inc))
	var other := offset_for(thru.edge, level, -_right_side(thru) if right else _right_side(thru))
	return minf(own, other)


## The incident at node nid that incident k carries straight on into: one
## heading the opposite way (within about 20 degrees), the same street by
## preference (so a highway carries on into the highway, not a ramp beside
## it), else the most nearly straight. -1 if none.
func _through(nid: String, k: int) -> int:
	var list: Array = incidents[nid]
	var inc: Incident = list[k]
	var t := -1
	var best := INF
	for j in list.size():
		if j == k:
			continue
		var o: Incident = list[j]
		var d := inc.dir.dot(o.dir)
		if d > -0.94:
			continue
		var score := d - (1.0 if o.edge.name == inc.edge.name and o.edge.highway == inc.edge.highway else 0.0)
		if score < best:
			best = score
			t = j
	return t


## How long the taper is at the end of e at node nid (0 if it doesn't
## narrow there): longer for a bigger change, never more than half the street.
func taper_length(e: RoadEdge, nid: String, k: int) -> float:
	var delta := 0.0
	for level: int in [Level.CURB, Level.BACK]:
		for right: bool in [true, false]:
			var seam := _seam(nid, k, level, right)
			if seam >= 0.0:
				var side := _right_side(incidents[nid][k]) if right else -_right_side(incidents[nid][k])
				delta = maxf(delta, offset_for(e, level, side) - seam)
	if delta < 0.05:
		return 0.0
	return minf(clampf(delta * 10.0, 6.0, 40.0), e.length * 0.45)


## The points along edge e that its side lines bend at, as (distance along,
## point index), or index 0 for an extra point where a taper ends. Points
## that lie inside a junction's corners (OSM often puts a crossing a few
## metres from the junction) are left out: the curb would run out to the
## corner and then fold back to them. Every side line of an edge uses the
## same stations, so the lines still pair up point for point.
func stations(e: RoadEdge) -> Array[Vector2]:
	var ka := incident_index(e.a, e, true)
	var kb := incident_index(e.b, e, false)
	var reach_a := _corner_reach(e.a, ka)
	var reach_b := _corner_reach(e.b, kb)
	var out: Array[Vector2] = []
	var along := 0.0
	for i in range(1, e.points.size() - 1):
		along += e.points[i - 1].distance_to(e.points[i])
		if along > reach_a + 0.5 and e.length - along > reach_b + 0.5:
			out.append(Vector2(along, i))
	for s: float in [taper_length(e, e.a, ka), e.length - taper_length(e, e.b, kb)]:
		if s <= 0.5 or s >= e.length - 0.5:
			continue
		var clash := false
		for st in out:
			clash = clash or absf(st.x - s) < 0.5
		if not clash:
			out.append(Vector2(s, 0))
	out.sort()
	return out


## How far along incident k the corners of node nid reach (the furthest of
## the curb and back-of-sidewalk corners on both sides).
func _corner_reach(nid: String, k: int) -> float:
	if degree(nid) < 2:
		return 0.0
	var inc: Incident = incidents[nid][k]
	var center: Vector2 = nodes[nid]
	var reach := 0.0
	for level: int in [Level.CURB, Level.BACK]:
		reach = maxf(reach, (line_corner(nid, k, level, false) - center).dot(inc.dir))
		reach = maxf(reach, (line_corner(nid, k, level, true) - center).dot(inc.dir))
	return reach


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
## Only looks in the grid cells within max_dist (or 200 m if unlimited).
func nearest_on_streets(p: Vector2, max_dist: float = INF) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var reach := minf(max_dist, 200.0)
	for e in edges_near(Rect2(p - Vector2(reach, reach), Vector2(reach, reach) * 2.0)):
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


## Edges whose centreline bounds come within `area` (each edge once).
func edges_near(area: Rect2) -> Array[RoadEdge]:
	var out: Array[RoadEdge] = []
	var seen := {}
	var c0 := Vector2i(floori(area.position.x / GRID), floori(area.position.y / GRID))
	var c1 := Vector2i(floori(area.end.x / GRID), floori(area.end.y / GRID))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for e: RoadEdge in _grid.get(Vector2i(cx, cz), []):
				if seen.has(e):
					continue
				seen[e] = true
				if e.bounds.grow(e.half_width + e.walk(1) + e.walk(-1) + 2.0).intersects(area):
					out.append(e)
	return out


func _index_edge(e: RoadEdge) -> void:
	var r := e.bounds.grow(e.half_width + e.sidewalk + 2.0)
	for cx in range(floori(r.position.x / GRID), floori(r.end.x / GRID) + 1):
		for cz in range(floori(r.position.y / GRID), floori(r.end.y / GRID) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(e)


## Divided roads: a one-way edge with a same-named one-way edge running the
## other way close beside it. The side facing its twin gets a median curb
## instead of a sidewalk.
func _find_medians() -> void:
	for e in edges:
		if e.oneway == 0 or e.roundabout or e.name == "" or e.length < 8.0:
			continue
		var sp: Array = sample(e.points, e.length * 0.5)
		var mid: Vector2 = sp[0]
		var dir: Vector2 = sp[1] * float(e.oneway)
		for o in edges_near(Rect2(mid - Vector2(45, 45), Vector2(90, 90))):
			if o == e or o.oneway == 0 or o.name != e.name:
				continue
			var hit := Geometry2D.get_closest_point_to_segment(mid, o.points[0], o.points[o.points.size() - 1])
			var best_d := INF
			var odir := Vector2.ZERO
			for i in range(o.points.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(mid, o.points[i], o.points[i + 1])
				if mid.distance_to(q) < best_d:
					best_d = mid.distance_to(q)
					hit = q
					odir = (o.points[i + 1] - o.points[i]).normalized() * float(o.oneway)
			if best_d > 40.0 or dir.dot(odir) > -0.8:
				continue
			# Which side of e (a->b) the twin is on.
			var side_ab := 1 if (hit - mid).dot(_perp(sp[1])) > 0.0 else -1
			# A narrow median is paved over curb to curb (each side builds its
			# half), rather than leaving a sliver of grass between two curbs.
			var half_gap := (best_d - e.half_width - o.half_width) * 0.5
			var inner := MEDIAN_CURB
			if half_gap < MEDIAN_FILL:
				inner = clampf(half_gap + 0.15, MEDIAN_CURB, MEDIAN_FILL)
			if side_ab > 0:
				e.sidewalk_right = inner
			else:
				e.sidewalk_left = inner
			break


## Roundabouts: the inner side of the ring gets a curb, and the middle a
## raised island. Traffic goes round counter-clockwise, so the inner side
## is on the driver's left.
func _find_roundabouts() -> void:
	var ring_edges: Array[RoadEdge] = []
	for e in edges:
		if e.roundabout:
			ring_edges.append(e)
			if e.oneway > 0:
				e.sidewalk_left = MEDIAN_CURB
			elif e.oneway < 0:
				e.sidewalk_right = MEDIAN_CURB
	# Group the ring pieces that share nodes into whole roundabouts.
	var group := {}
	var next := 0
	for e in ring_edges:
		var ga: int = group.get(e.a, -1)
		var gb: int = group.get(e.b, -1)
		if ga < 0 and gb < 0:
			group[e.a] = next
			group[e.b] = next
			next += 1
		elif ga < 0:
			group[e.a] = gb
		elif gb < 0:
			group[e.b] = ga
		elif ga != gb:
			for k: String in group.keys():
				if int(group[k]) == gb:
					group[k] = ga
	var pts := {}
	for e in ring_edges:
		var g: int = group[e.a]
		if not pts.has(g):
			pts[g] = [PackedVector2Array(), 0.0]
		(pts[g][0] as PackedVector2Array).append_array(e.points)
		pts[g][1] = maxf(float(pts[g][1]), e.half_width)
	for g: int in pts:
		var hull := Geometry2D.convex_hull(pts[g][0])
		if hull.size() < 4:
			continue
		var inset := float(pts[g][1]) + MEDIAN_CURB
		for d: float in [-inset, inset]:
			var shrunk := Geometry2D.offset_polygon(hull, d)
			if shrunk.size() == 1 and absf(_poly_area(shrunk[0])) < absf(_poly_area(hull)) and absf(_poly_area(shrunk[0])) > 12.0:
				islands.append(shrunk[0])
				break


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Distance from p to an edge's centreline.
static func distance_to_edge(e: RoadEdge, p: Vector2) -> float:
	var best := INF
	for i in range(e.points.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, e.points[i], e.points[i + 1])))
	return best


## Distance from p to an edge's centreline, measured square across it: a
## point past either end of the street (beyond the junction it ends at, or
## on the next street along) is not beside it at all, so it's INF there.
## The roadway is a flat-ended strip, not one with round caps.
static func distance_across_edge(e: RoadEdge, p: Vector2) -> float:
	var best := INF
	var last := e.points.size() - 2
	for i in range(last + 1):
		var s0 := e.points[i]
		var s1 := e.points[i + 1]
		var d := s1 - s0
		var l2 := d.length_squared()
		if l2 < 0.0001:
			continue
		var t := (p - s0).dot(d) / l2
		if (i == 0 and t < 0.0) or (i == last and t > 1.0):
			continue
		best = minf(best, p.distance_to(s0 + d * clampf(t, 0.0, 1.0)))
	return best


## A street whose roadway covers p: within its half width less `inset`
## (a negative inset reaches past the curb). `skip` is left out. Null if none.
func road_at(p: Vector2, skip: RoadEdge = null, inset := 0.0) -> RoadEdge:
	for o in edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		if o == skip:
			continue
		if distance_across_edge(o, p) < o.half_width - inset:
			return o
	return null


## True if p is inside the curb polygon of a junction (other than the ones
## in `except`, e.g. the ends of the street being built).
func in_junction(p: Vector2, except: Array = []) -> bool:
	for o in edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		for nid: String in [o.a, o.b]:
			if except.has(nid) or not junction_polys.has(nid):
				continue
			if Geometry2D.is_point_in_polygon(p, junction_polys[nid]):
				return true
	return false


## Which points of a grid over `rect` (every `spacing` metres, row by row,
## (n+1) x (n+1) of them) lie under a street, its sidewalks or a highway's
## verge, with `margin` metres kept clear inside their edges. 1 = covered.
## The ground is carved down there so it never pokes up through the street.
func street_mask(rect: Rect2, spacing: float, margin := 0.4) -> PackedByteArray:
	var n := int(round(rect.size.x / spacing))
	var cols := n + 1
	var mask := PackedByteArray()
	mask.resize(cols * cols)
	for e in edges_near(rect.grow(30.0)):
		var reach := e.half_width + maxf(maxf(e.walk(1), e.walk(-1)), 1.8 if e.is_highway() else 0.0) - margin
		if e.bridge or reach <= 0.0:
			continue
		for i in range(e.points.size() - 1):
			var s0 := e.points[i]
			var s1 := e.points[i + 1]
			var lo := Vector2(minf(s0.x, s1.x), minf(s0.y, s1.y)) - Vector2(reach, reach) - rect.position
			var hi := Vector2(maxf(s0.x, s1.x), maxf(s0.y, s1.y)) + Vector2(reach, reach) - rect.position
			for r in range(maxi(0, ceili(lo.y / spacing)), mini(n, floori(hi.y / spacing)) + 1):
				for c in range(maxi(0, ceili(lo.x / spacing)), mini(n, floori(hi.x / spacing)) + 1):
					if mask[r * cols + c] != 0:
						continue
					var p := rect.position + Vector2(c, r) * spacing
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s0, s1)) < reach:
						mask[r * cols + c] = 1
	return mask


## True if a post or tree at p would stand clear of every street and
## junction (at least `clearance` metres past the curb).
func clear_of_roads(p: Vector2, clearance := 0.35) -> bool:
	return road_at(p, null, -clearance) == null and not in_junction(p)


## Which of two overlapping roadways is drawn: roundabouts first, then
## highways, then town streets, then ramps; lower index on a tie.
static func outranks(o: RoadEdge, e: RoadEdge) -> bool:
	var ro := _rank(o)
	var re := _rank(e)
	return ro < re or (ro == re and o.index < e.index)


static func _rank(e: RoadEdge) -> int:
	if e.roundabout:
		return 0
	if e.highway.ends_with("_link"):
		return 3
	if e.is_highway():
		return 1
	return 2


## Shortest route between two junctions along streets whose names are in
## `names` (or any street if empty), as a polyline. Empty if there is none.
func route(from_id: String, to_id: String, names: Array = []) -> PackedVector2Array:
	var dist := {from_id: 0.0}
	var prev := {}
	var open := [from_id]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var cur: String = open[bi]
		open.remove_at(bi)
		if cur == to_id:
			break
		if done.has(cur):
			continue
		done[cur] = true
		for inc: Incident in incidents.get(cur, []):
			var e := inc.edge
			if not names.is_empty() and not names.has(e.name):
				continue
			var nxt := e.b if inc.at_start else e.a
			var d := float(dist[cur]) + e.length
			if d < float(dist.get(nxt, INF)):
				dist[nxt] = d
				prev[nxt] = inc
				open.append(nxt)
	var out := PackedVector2Array()
	if not prev.has(to_id) and from_id != to_id:
		return out
	var at := to_id
	var parts: Array[PackedVector2Array] = []
	while at != from_id:
		var inc: Incident = prev[at]
		var pts := inc.edge.points.duplicate()
		if not inc.at_start:
			pts.reverse()
		parts.push_front(pts)
		at = inc.edge.a if inc.at_start else inc.edge.b
	for pts in parts:
		out.append_array(pts)
	return out


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

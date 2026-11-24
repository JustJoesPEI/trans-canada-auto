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
	## Painted bike lane each side, metres from the curb to its line (0 = none):
	## OSM cycleway=lane or cycleway:both=lane, width tca:bike_lane or 1.6 m.
	var bike_lane := 0.0
	var bounds: Rect2 ## centreline bounds, for quick area tests
	## Width before any fit to the buildings beside it (street_fit.json):
	## half width, sidewalk right (a->b) and left.
	var base: Vector3
	## Lane, campus road or track (see map_config.json "minor_roads"): no
	## curbs, sidewalks or paint, and drawn under the streets it meets.
	var minor := false
	## Width or sidewalk set by hand in the map editor (tca:width,
	## tca:sidewalk): never fitted.
	var hand_set := false

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
## Junctions run by traffic lights (node id -> true), set by
## RoadMesher.find_signal_nodes.
var signal_nodes: Dictionary = {}
## Curb polygon of every junction of three or more streets (node id -> poly),
## worked out once so worker threads only ever read it.
var junction_polys: Dictionary = {}
## Deck height at each end of a bridge (node id -> metres), set by
## RoadMesher.seat_bridges from the top of the embankment it stands on.
var bridge_end_h: Dictionary = {}
## Raised islands in the middle of roundabouts (polygons).
var islands: Array[PackedVector2Array] = []
## Where a two-way street divides into two one-way carriageways (or two
## join back into one), node id -> Split. No junction box: the outer curbs
## carry straight on and the median starts from a point (see _find_splits).
var splits: Dictionary = {}

## Half width of the tip of the median where a divided road begins.
const NOSE := 0.15


class Split:
	var t: Incident ## the two-way street
	var pair: Array[Incident] = [] ## the two carriageways
	var taper: Dictionary = {} ## Incident -> metres the carriageway takes to reach its own width

## Edges by grid cell, for nearest-street and area queries.
const GRID := 100.0
var _grid: Dictionary = {} ## Vector2i -> Array[RoadEdge]


## How many pairs of junctions were merged because they were too close to
## fit both (see _close_pairs).
var merged_junctions := 0

## Widths fitted to the buildings along each stretch of street, from
## map_config.json "street_fit" (written by tools/fit_streets.gd): edge key
## ("a>b") -> {"base": [half width, walk right, walk left], "fit": [...]}.
## A fit is only used while the street's own width is still the one it was
## worked out from, so changing a width by hand (tca:width) drops it.
var _fit: Dictionary = {}


func _init(data: StreetData, fit: Variant = null) -> void:
	_fit = data.street_fit if fit == null else fit
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
		splits.clear()
		_build(data, roads)


# --- construction -------------------------------------------------------------

func _usable(data: StreetData) -> Array[StreetData.Road]:
	var usable: Array[StreetData.Road] = []
	for r in data.roads:
		if builds(data, r):
			usable.append(r)
	return usable


## True if the game builds road r: a street in "drivable_classes", or a
## lane, campus road or named track listed in "minor_roads".
static func builds(data: StreetData, r: StreetData.Road) -> bool:
	if (data.config.get("drivable_classes", []) as Array).has(r.highway):
		return true
	return is_minor(data, r)


static func is_minor(data: StreetData, r: StreetData.Road) -> bool:
	var minor: Dictionary = data.config.get("minor_roads", {})
	if str(r.tags.get("layer", "0")).to_int() < 0 or str(r.tags.get("tunnel", "no")) not in ["no", ""]:
		return false
	if r.highway == "service":
		return (minor.get("service", []) as Array).has(str(r.tags.get("service", "")))
	if r.highway == "track":
		return bool(minor.get("named_track", false)) and r.name != ""
	return false


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


## True if node nid is only where a lane or campus road meets a street (at
## most two of the streets through it are proper streets).
func _minor_only(nid: String) -> bool:
	return major_degree(nid) < 3


## How many proper streets (not lanes, campus roads or tracks) meet at nid.
func major_degree(nid: String) -> int:
	var n := 0
	for inc: Incident in incidents.get(nid, []):
		if not inc.edge.minor:
			n += 1
	return n


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
		# A lane or campus road joining a street right by a junction is
		# pulled onto it; the street junction itself doesn't move.
		var keep: Array = (members[rep] as Array).filter(func(m: String) -> bool: return not _minor_only(m))
		if keep.is_empty():
			keep = members[rep]
		var sum := Vector2.ZERO
		for m: String in keep:
			sum += nodes[m]
		where[rep] = sum / float(keep.size())
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
	pieces = _join_pieces(pieces)
	_round_joins(pieces, data)
	pieces = _drop_stubs(pieces)
	_detach_splits(pieces)
	for pc in pieces:
		_add_edge(pc.road, pc.a, pc.b, pc.pts, pc.style, pc.oneway)

	for nid: String in incidents:
		var list: Array = incidents[nid]
		list.sort_custom(func(x: Incident, y: Incident) -> bool: return x.angle < y.angle)
	for e in edges:
		_index_edge(e)
	_find_medians()
	_find_roundabouts()
	_find_splits()
	for nid: String in incidents:
		if degree(nid) >= 3 and not splits.has(nid):
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


## Where a street carries on into another way round a corner (two ways that
## couldn't be joined, being built differently), the corner is rounded off
## like any bend (round_bends) and the node moved to the middle of the arc,
## half of it going to each. A lane or lot entrance meeting the street on
## the corner moves with it.
func _round_joins(pieces: Array[Piece], data: StreetData) -> void:
	var at := {} ## node id -> Array[Piece]
	for pc in pieces:
		for nid: String in [pc.a, pc.b]:
			if not at.has(nid):
				at[nid] = []
			at[nid].append(pc)
	for nid: String in at:
		var list: Array = []
		var lanes: Array = []
		for pc: Piece in at[nid]:
			if is_minor(data, pc.road):
				lanes.append(pc)
			else:
				list.append(pc)
		if list.size() != 2 or list[0] == list[1]:
			continue
		var p: Piece = list[0]
		var q: Piece = list[1]
		var skip := false
		for pc: Piece in [p, q]:
			skip = skip or pc.pts.size() < 2 or str(pc.road.tags.get("junction", "")) in ["roundabout", "circular"] or str(pc.road.tags.get("bridge", "no")) not in ["no", ""]
		if skip:
			continue
		var pp := p.pts if p.b == nid else _reversed(p.pts)
		var qq := q.pts if q.a == nid else _reversed(q.pts)
		var radius := maxf(_class_radius(p.road.highway), _class_radius(q.road.highway))
		var offset := maxf(p.style.x * 0.5 + maxf(p.style.y, 0.0), q.style.x * 0.5 + maxf(q.style.y, 0.0))
		var arc := _fillet(pp[pp.size() - 2], pp[pp.size() - 1], qq[1], radius, offset)
		if arc.size() < 3:
			continue
		var mid := arc.size() / 2
		var np := pp.slice(0, pp.size() - 1)
		np.append_array(arc.slice(0, mid + 1))
		var nq := arc.slice(mid)
		nq.append_array(qq.slice(1))
		p.pts = np if p.b == nid else _reversed(np)
		q.pts = nq if q.a == nid else _reversed(nq)
		for pc: Piece in lanes:
			if pc.a == nid:
				pc.pts[0] = arc[mid]
			if pc.b == nid:
				pc.pts[pc.pts.size() - 1] = arc[mid]


## A dead end shorter than this sticking out of a junction is a scrap of
## the map (the end of a lot aisle, a way drawn a touch past the street it
## joins), not a street: a stub of curb and paint going nowhere.
const STUB := 8.0


func _drop_stubs(pieces: Array[Piece]) -> Array[Piece]:
	var count := {}
	for pc in pieces:
		for nid: String in [pc.a, pc.b]:
			count[nid] = int(count.get(nid, 0)) + 1
	var out: Array[Piece] = []
	for pc in pieces:
		var dead_a := int(count[pc.a]) == 1
		var dead_b := int(count[pc.b]) == 1
		var stub := (dead_a and int(count[pc.b]) >= 3) or (dead_b and int(count[pc.a]) >= 3)
		if stub and polyline_length(pc.pts) < STUB:
			continue
		out.append(pc)
	return out


## Where a divided road begins at a junction (the two carriageways and the
## two-way street meeting a side street at one point), the carriageways
## would meet the junction box side by side with blunt ends. Instead the
## two-way street carries on through the junction a little way to a node of
## its own where the carriageways split (see _find_splits), clear of the box.
func _detach_splits(pieces: Array[Piece]) -> void:
	var at := {}
	for pc in pieces:
		for nid: String in [pc.a, pc.b]:
			if not at.has(nid):
				at[nid] = []
			at[nid].append(pc)
	for nid: String in at:
		var list: Array = at[nid]
		if list.size() < 4:
			continue
		var t: Piece = null
		var pair: Array[Piece] = []
		var dirs := {}
		for pc: Piece in list:
			if pc.a == pc.b:
				continue
			dirs[pc] = _leaving_dir(pc.pts, pc.a == nid)
		for i in list.size():
			for j in range(i + 1, list.size()):
				var p: Piece = list[i]
				var q: Piece = list[j]
				if p.oneway == 0 or q.oneway == 0 or not dirs.has(p) or not dirs.has(q):
					continue
				if (dirs[p] as Vector2).dot(dirs[q]) < 0.5:
					continue
				# One leaves the node, the other comes into it.
				if ((p.oneway == 1) == (p.a == nid)) == ((q.oneway == 1) == (q.a == nid)):
					continue
				var mid := ((dirs[p] as Vector2) + (dirs[q] as Vector2)).normalized()
				for o: Piece in list:
					if o.oneway == 0 and dirs.has(o) and (dirs[o] as Vector2).dot(mid) < -0.85:
						t = o
				if t != null:
					pair = [p, q]
					break
			if t != null:
				break
		if t == null:
			continue
		# Past the junction box: about the width of the widest street there.
		var reach := 0.0
		for pc: Piece in list:
			reach = maxf(reach, pc.style.x * 0.5 + maxf(pc.style.y, 0.0))
		var d := reach * 1.6 + 4.0
		var ok := true
		for pc in pair:
			ok = ok and polyline_length(pc.pts) > d * 2.5
		if not ok:
			continue
		var split_id := nid + "~split"
		var ends: Array[Vector2] = []
		for pc in pair:
			var from_here := pc.a == nid
			var pts := pc.pts if from_here else _reversed(pc.pts)
			var cut := _cut(pts, d)
			ends.append(cut[0])
		var mid_pt := (ends[0] + ends[1]) * 0.5
		for pc in pair:
			var from_here := pc.a == nid
			var pts := pc.pts if from_here else _reversed(pc.pts)
			var rest: PackedVector2Array = _cut(pts, d)
			rest[0] = mid_pt
			if from_here:
				pc.pts = rest
				pc.a = split_id
			else:
				pc.pts = _reversed(rest)
				pc.b = split_id
		var x := Piece.new()
		x.road = t.road
		x.a = nid
		x.b = split_id
		x.pts = PackedVector2Array([at_point(pieces, nid), mid_pt])
		x.style = t.style
		x.oneway = 0
		pieces.append(x)


## Where node nid lies, from the pieces ending there.
static func at_point(pieces: Array[Piece], nid: String) -> Vector2:
	for pc in pieces:
		if pc.a == nid:
			return pc.pts[0]
		if pc.b == nid:
			return pc.pts[pc.pts.size() - 1]
	return Vector2.ZERO


## The polyline from `dist` along it to its end (its first point the cut).
static func _cut(pts: PackedVector2Array, dist: float) -> PackedVector2Array:
	var remaining := dist
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if remaining < seg:
			var out := PackedVector2Array([pts[i].lerp(pts[i + 1], remaining / seg)])
			out.append_array(pts.slice(i + 1))
			return out
		remaining -= seg
	return PackedVector2Array([pts[pts.size() - 1]])


static func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var r := pts.duplicate()
	r.reverse()
	return r


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
	for tag: String in ["bridge", "junction", "lanes", "sidewalk", "service", "cycleway", "cycleway:both"]:
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
	if oneway == 0 and (str(r.tags.get("cycleway", "")) == "lane" or str(r.tags.get("cycleway:both", "")) == "lane"):
		e.bike_lane = str(r.tags.get("tca:bike_lane", "1.6")).to_float()
	e.minor = r.highway in ["service", "track"]
	e.hand_set = r.tags.has("tca:width") or r.tags.has("tca:sidewalk")
	e.base = Vector3(e.half_width, e.sidewalk, e.sidewalk)
	_apply_fit(e)
	if not e.roundabout and not e.bridge:
		pts = round_bends(pts, _bend_radius(e), e.half_width + maxf(e.walk(1), e.walk(-1)))
		e.points = pts
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


## How tight a bend a street of e's class takes: OSM draws a corner as a
## single point, where the real street sweeps round.
static func _bend_radius(e: RoadEdge) -> float:
	return _class_radius(e.highway)


static func _class_radius(highway: String) -> float:
	match highway:
		"motorway", "trunk":
			return 80.0
		"primary":
			return 40.0
		"secondary":
			return 25.0
		"tertiary":
			return 15.0
		"motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link":
			return 30.0
	return 10.0


## Furthest a rounded bend moves the street off the mapped corner.
const BEND_SHIFT := 3.0


## The polyline with every bend in it rounded off into an arc of the given
## radius, kept to within BEND_SHIFT of the mapped corner, but never
## tighter than `offset` plus a metre (the inside of the sidewalk would fold
## back on itself) and only as far as the straights either side allow (half
## of each, so neighbouring bends don't overlap); a bend that can't be
## rounded keeps its corner. The ends stay put.
static func round_bends(pts: PackedVector2Array, radius: float, offset: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	# Points OSM puts along a straight (a crossing, a driveway, where a way
	# was split) would leave only a short straight either side of a corner.
	pts = simplify(pts, 0.25)
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var arc := _fillet(pts[i - 1], pts[i], pts[i + 1], radius, offset)
		if arc.is_empty():
			arc.append(pts[i])
		for q in arc:
			# Two bends sharing a short straight meet at its middle.
			if q.distance_to(out[out.size() - 1]) > 0.05:
				out.append(q)
	if pts[pts.size() - 1].distance_to(out[out.size() - 1]) > 0.05:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


## The polyline with the points that lie within `tolerance` of the line
## through their neighbours left out (Douglas-Peucker). The ends stay.
static func simplify(pts: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, pts.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1.0
		var at := -1
		for i in range(span.x + 1, span.y):
			var d := pts[i].distance_to(Geometry2D.get_closest_point_to_segment(pts[i], pts[span.x], pts[span.y]))
			if d > worst:
				worst = d
				at = i
		if at >= 0 and worst > tolerance:
			keep[at] = 1
			stack.append(Vector2i(span.x, at))
			stack.append(Vector2i(at, span.y))
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] != 0:
			out.append(pts[i])
	return out


## The arc rounding off corner p between prev and next (see round_bends),
## from where it leaves the straight before to where it joins the one
## after; empty if the corner stays sharp.
static func _fillet(prev: Vector2, p: Vector2, next: Vector2, radius: float, offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d0 := p - prev
	var d1 := next - p
	var l0 := d0.length()
	var l1 := d1.length()
	if l0 < 0.05 or l1 < 0.05:
		return out
	d0 /= l0
	d1 /= l1
	var turn := absf(d0.angle_to(d1))
	if turn < deg_to_rad(4.0) or turn > deg_to_rad(150.0):
		return out
	var half := turn * 0.5
	# Tighter than the offset and the inside curb would fold back: a
	# bend that can't be rounded that wide keeps its sharp corner.
	var least := offset + 1.0
	var r := maxf(minf(radius, BEND_SHIFT / (1.0 / cos(half) - 1.0)), least)
	var tl := minf(r * tan(half), minf(l0, l1) * 0.5)
	r = tl / tan(half)
	if r < least:
		return out
	var a := p - d0 * tl
	var steps := maxi(2, ceili(rad_to_deg(turn) / 10.0))
	# The arc's centre is r to the inside of both straights.
	var side := signf(d0.cross(d1))
	var c := a + Vector2(-d0.y, d0.x) * side * r
	var a0 := (a - c).angle()
	for k in steps + 1:
		out.append(c + Vector2.from_angle(a0 + turn * side * float(k) / float(steps)) * r)
	return out


## Narrows e to the width tools/fit_streets.gd fitted between the buildings
## along it, if there is one and it was fitted from e's present width.
func _apply_fit(e: RoadEdge) -> void:
	var f: Variant = _fit.get(edge_key(e.a, e.b))
	var flip := false
	if f == null:
		f = _fit.get(edge_key(e.b, e.a))
		flip = true
	if not (f is Dictionary):
		return
	var b: Array = f.get("base", [])
	var w: Array = f.get("fit", [])
	if b.size() != 3 or w.size() != 3:
		return
	var r := 2 if flip else 1
	var l := 1 if flip else 2
	if absf(float(b[0]) - e.base.x) > 0.01 or absf(float(b[r]) - e.base.y) > 0.01 or absf(float(b[l]) - e.base.z) > 0.01:
		return
	e.half_width = float(w[0])
	e.sidewalk_right = float(w[r])
	e.sidewalk_left = float(w[l])


static func edge_key(a: String, b: String) -> String:
	return "%s>%s" % [a, b]


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
	_unfold(out)
	return out


## On the inside of a bend tighter than the line's offset, the offset line
## loops back on itself (a bow tie of curb or sidewalk standing out of the
## corner). Each loop is pinched shut: the points on it all move to where
## the line crosses itself, so the line keeps its point count and still
## pairs up with the street's other side lines.
static func _unfold(line: PackedVector2Array) -> void:
	var n := line.size()
	var i := 0
	while i < n - 3:
		var cut := -1
		var at := Vector2.ZERO
		for j in range(mini(n - 2, i + 16), i + 1, -1):
			var x: Variant = Geometry2D.segment_intersects_segment(line[i], line[i + 1], line[j], line[j + 1])
			if x != null:
				cut = j
				at = x
				break
		if cut < 0:
			i += 1
			continue
		for k in range(i + 1, cut + 1):
			line[k] = at
		i = cut


## Where a side line of incident k starts: the junction corner it shares
## with the next street round (right) or the one before (left). Two streets
## leaving at a shallow angle (a ramp, a road forking) have no sensible
## shared corner: their curbs only cross far down the road. There each
## street starts square across its own end and the two roadways overlap.
func line_corner(nid: String, k: int, level: int, right: bool) -> Vector2:
	var list: Array = incidents[nid]
	var n := list.size()
	if splits.has(nid):
		return _split_corner(nid, list[k], level, right)
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
	if splits.has(nid):
		var sp: Split = splits[nid]
		if inc == sp.t:
			return -1.0
		var c := _split_corner(nid, inc, level, right) - (nodes[nid] as Vector2)
		return absf(c.dot(_perp(inc.dir)))
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
	if splits.has(nid):
		return float((splits[nid] as Split).taper.get(incidents[nid][k], 0.0))
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
	if degree(nid) < 3 or splits.has(nid):
		return 0.0
	var inc: Incident = incidents[nid][k]
	var center: Vector2 = nodes[nid]
	var l := corner_left(nid, k, Level.CURB) - center
	var r := corner_right(nid, k, Level.CURB) - center
	return maxf(0.0, maxf(l.dot(inc.dir), r.dot(inc.dir)))


## Curb corners around a junction, in angle order.
func junction_polygon(nid: String, level: int = Level.CURB) -> PackedVector2Array:
	# The same corners the streets' side lines start from, so the box meets
	# every street exactly. Between two streets that each start square across
	# their own end (a shallow fork, or one carrying straight on) the two
	# corners differ and both go in.
	var out := PackedVector2Array()
	var n := degree(nid)
	for k in n:
		var r := line_corner(nid, k, level, true)
		var l := line_corner(nid, (k + 1) % n, level, false)
		out.append(r)
		if l.distance_to(r) > 0.05:
			out.append(l)
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


## Where a side line of incident inc starts at split node nid. The two-way
## street ends square across; each carriageway's outer side starts at the
## two-way street's corner on that side, its inner side at the median's tip.
func _split_corner(nid: String, inc: Incident, level: int, right: bool) -> Vector2:
	var sp: Split = splits[nid]
	var center: Vector2 = nodes[nid]
	if inc == sp.t:
		var side := _right_side(inc) if right else -_right_side(inc)
		return center + _perp(inc.dir) * offset_for(inc.edge, level, side) * (1.0 if right else -1.0)
	var twin: Incident = sp.pair[1] if inc == sp.pair[0] else sp.pair[0]
	var twin_right := twin.dir.dot(_perp(inc.dir)) > 0.0
	if right == twin_right:
		return center + _perp(inc.dir) * NOSE * (1.0 if right else -1.0)
	# Looking out along the carriageway its right is the two-way street's left.
	return _split_corner(nid, sp.t, level, not right)


## Divided roads beginning or ending: a node where exactly a two-way street
## and two one-way carriageways meet, the carriageways leaving side by side
## (less than 60 degrees apart) in the opposite direction to the street,
## one carrying traffic away and the other towards it. OSM joins the three
## centrelines at one point, which as an ordinary junction would draw two
## blunt ends overlapping a junction box. Instead each carriageway flares
## out of the street: its outer curb carries on from the street's curb, and
## its inner curb starts at the median's tip and widens to its own width
## over the distance the two carriageways take to get clear of each other.
func _find_splits() -> void:
	for nid: String in incidents:
		var list: Array = incidents[nid]
		if list.size() != 3:
			continue
		var t: Incident = null
		var pair: Array[Incident] = []
		for inc: Incident in list:
			if inc.edge.roundabout or inc.edge.minor:
				t = null
				pair.clear()
				break
			if inc.edge.oneway == 0:
				t = inc
			else:
				pair.append(inc)
		if t == null or pair.size() != 2:
			continue
		var a := pair[0]
		var b := pair[1]
		if a.edge.bridge != b.edge.bridge or a.edge.bridge != t.edge.bridge:
			continue
		if a.dir.dot(b.dir) < 0.5 or t.dir.dot((a.dir + b.dir).normalized()) > -0.85:
			continue
		# One carries traffic away from the node, the other towards it.
		if ((a.edge.oneway == 1) == a.at_start) == ((b.edge.oneway == 1) == b.at_start):
			continue
		var sp := Split.new()
		sp.t = t
		sp.pair = pair
		var clear := maxf(_clear_of(a, b), _clear_of(b, a))
		for inc: Incident in pair:
			sp.taper[inc] = clampf(clear, 8.0, inc.edge.length * 0.5)
		splits[nid] = sp


## How far along carriageway a (from the split) it gets clear of b: its
## centreline far enough from b's for both roadways and a median.
func _clear_of(a: Incident, b: Incident) -> float:
	var need := a.edge.half_width + b.edge.half_width + MEDIAN_CURB * 2.0
	var pts := a.edge.points
	if not a.at_start:
		pts = pts.duplicate()
		pts.reverse()
	var along := 2.0
	while along < a.edge.length:
		var p: Vector2 = sample(pts, along)[0]
		var best := INF
		var q := b.edge.points
		for i in q.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, q[i], q[i + 1])))
		if best >= need:
			return along
		along += 2.0
	return a.edge.length


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
			# A divided highway mapped tighter than its full width first gives
			# up shoulder (see _fit_beside_twin).
			if e.is_highway():
				_fit_beside_twin(e, o)
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


## A divided highway whose two carriageways OSM maps closer together than
## their full width (lanes and a shoulder each side): the shoulders are
## trimmed, never the lanes, until there is MEDIAN_GAP of median between
## them at the usual spacing along the edge, so the two don't overlap in a
## sliver of doubled asphalt.
const MEDIAN_GAP := 2.0

func _fit_beside_twin(e: RoadEdge, o: RoadEdge) -> void:
	var gaps: Array[float] = []
	for k in 5:
		var p: Vector2 = sample(e.points, e.length * (0.1 + 0.2 * k))[0]
		gaps.append(distance_to_edge(o, p))
	gaps.sort()
	var apart: float = gaps[2] # the usual spacing, not where they meet
	var lanes_half := e.half_width - e.shoulder
	var want := (apart - MEDIAN_GAP) * 0.5
	if want >= e.half_width:
		return
	var trimmed := maxf(want, lanes_half + 0.3)
	e.shoulder = maxf(0.3, e.shoulder - (e.half_width - trimmed))
	e.half_width = trimmed


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
## With `same_level`, only roads on skip's own level count: a bridge and the
## road passing under it never cover each other.
func road_at(p: Vector2, skip: RoadEdge = null, inset := 0.0, same_level := false) -> RoadEdge:
	for o in edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		if o == skip or (skip != null and same_split(o, skip)):
			continue
		if same_level and skip != null and o.bridge != skip.bridge:
			continue
		if distance_across_edge(o, p) < o.half_width - inset:
			return o
	return null


## True if e and o meet at a split (see _find_splits): their roadways are
## shaped to meet edge to edge there, so neither covers the other.
func same_split(e: RoadEdge, o: RoadEdge) -> bool:
	for nid: String in [e.a, e.b]:
		if (nid == o.a or nid == o.b) and splits.has(nid):
			return true
	return false


## True if p is under a bridge deck (parapets and deck edge included, plus
## `pad` metres): nothing tall stands there, it would come up through it.
func under_bridge(p: Vector2, pad := 1.0) -> bool:
	for o in edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4)).grow(pad)):
		if o.bridge and distance_across_edge(o, p) < o.half_width + maxf(maxf(o.walk(1), o.walk(-1)), 0.5) + pad:
			return true
	return false


## True if p is inside the curb polygon of a junction (other than the ones
## in `except`, e.g. the ends of the street being built). With `level`
## (0 on the ground, 1 on a bridge) only junctions of streets on that level
## count.
func in_junction(p: Vector2, except: Array = [], level := -1) -> bool:
	for o in edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		if level >= 0 and int(o.bridge) != level:
			continue
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
	if e.minor:
		return 4
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

class_name RoadMesher
extends RefCounted
## Turns a RoadNetwork into visible streets: asphalt, raised sidewalks with
## curbs, centre lines, lane and edge lines, crosswalks (from OSM crossing
## points), bridges with parapets, and the ground collision everything walks
## and drives on.
##
## It builds one chunk at a time: every street that comes near the chunk is
## worked out in full (so curbs and corners match their neighbours exactly)
## and only the triangles whose middle falls inside the chunk are kept.
##
## Everything follows the real terrain: each vertex takes its height from
## Terrain, long stretches are split every STEP metres so streets follow the
## grade, and roads carry a centreline row so the crown of the street is kept.
## Bridges are the exception: their deck runs straight from one end to the
## other, over whatever is underneath.
##
## Highway-style roads (the bypass, Riverside Drive, ramps) have paved
## shoulders with a white edge line and a gravel verge instead of curbs and
## sidewalks. With `lod` set it builds the light version for distant
## chunks: just the asphalt and sidewalk tops, no paint or collision.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT
const MARK_Y := 0.03
const STEP := 3.0 ## metres between rows of vertices along a street
const CROSSWALK_DEPTH := 3.0
const LANE_W := 3.6
const VERGE := 2.2 ## gravel strip beside a highway shoulder
const PARAPET_H := 0.95
## How far below the street surface a roadway hidden under another one sits
## (still above the open ground, which is Terrain.GROUND_DROP down).
const SUNK := -0.03
## How far below the street the back edge of a sidewalk (and the outer edge
## of a verge) reaches down, past the ground carved away under the street.
const BACK_DEPTH := -0.45

var net: RoadNetwork
var data: StreetData
var terrain: Terrain
var rect: Rect2
var lod := false

var _asphalt := MeshKit.new()
var _brick := MeshKit.new()
var _brick_edges: Dictionary = {} ## RoadEdge -> true
var _concrete := MeshKit.new()
var _gravel := MeshKit.new()
var _yellow := MeshKit.new()
var _white := MeshKit.new()
var _red := MeshKit.new() ## the red blocks of downtown's red-and-white crosswalks
var _parapets := MeshKit.new()
var _bridge: RoadNetwork.RoadEdge = null ## the bridge being built, if any
var _paint_edge: RoadNetwork.RoadEdge = null ## the street being painted
var _island := MeshKit.new()
var _in_crosswalk := false ## painting crosswalk stripes (not stopped by crosswalks)
var _bridge_h := Vector2.ZERO ## its deck height at a and at b


func _init(network: RoadNetwork, street_data: StreetData, ground: Terrain, chunk: Rect2, low_detail := false) -> void:
	net = network
	data = street_data
	terrain = ground
	rect = chunk
	lod = low_detail
	for kit: MeshKit in [_asphalt, _brick, _concrete, _gravel, _yellow, _white, _red, _parapets, _island]:
		kit.clip = rect
		kit.use_clip = true


## Height of the street surface at ground point p: the terrain, or the
## straight deck of the bridge being built.
func _h(p: Vector2) -> float:
	if _bridge != null:
		var hit := Geometry2D.get_closest_point_to_segment(p, net.nodes[_bridge.a], net.nodes[_bridge.b])
		var ab: Vector2 = (net.nodes[_bridge.b] as Vector2) - (net.nodes[_bridge.a] as Vector2)
		var t := 0.0
		if ab.length_squared() > 0.01:
			t = clampf((hit - (net.nodes[_bridge.a] as Vector2)).dot(ab) / ab.length_squared(), 0.0, 1.0)
		return lerpf(_bridge_h.x, _bridge_h.y, t)
	return terrain.h2(p)


## A ground point at the street height plus `lift`.
func _v(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, _h(p) + lift, p.y)


## Two matching lines (same point count) resampled so no step along them is
## longer than STEP, keeping them matched point for point.
static func _densify(a: PackedVector2Array, b: PackedVector2Array) -> Array:
	var na := PackedVector2Array([a[0]])
	var nb := PackedVector2Array([b[0]])
	for i in range(a.size() - 1):
		var n := maxi(1, ceili(maxf(a[i].distance_to(a[i + 1]), b[i].distance_to(b[i + 1])) / STEP))
		for k in range(1, n + 1):
			var t := float(k) / float(n)
			na.append(a[i].lerp(a[i + 1], t))
			nb.append(b[i].lerp(b[i + 1], t))
	return [na, nb]


## A vertical strip along ground points p0-p1, from `lo` to `hi` above the street.
## UV = (metres along, metres up).
func _wall(kit: MeshKit, p0: Vector2, p1: Vector2, lo: float, hi: float, n: Vector3) -> void:
	var l := p0.distance_to(p1)
	kit.quad(_v(p0, lo), _v(p1, lo), _v(p1, hi), _v(p0, hi), n, Vector2(0.0, lo), Vector2(l, lo), Vector2(l, hi), Vector2(0.0, hi))


func _set_bridge(e: RoadNetwork.RoadEdge) -> void:
	_bridge = e if e.bridge else null
	if _bridge != null:
		_bridge_h = Vector2(terrain.h2(net.nodes[e.a]), terrain.h2(net.nodes[e.b]))


## Builds this chunk's streets under a new Node3D and returns it.
func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Streets"
	_brick_edges = net.brick_edges
	_asphalt.use_uv2 = true
	_concrete.use_uv2 = true
	var near := net.edges_near(rect.grow(4.0))
	for e in near:
		_set_bridge(e)
		_road_strip(e)
		_sidewalks(e)
		if not lod:
			_paint_edge = e
			_markings(e)
			_paint_edge = null
			if e.bridge:
				_bridge_sides(e)
	_bridge = null
	var done := {}
	for e in near:
		for nid: String in [e.a, e.b]:
			if done.has(nid) or net.degree(nid) < 3:
				continue
			done[nid] = true
			_junction_fill(nid)
	if not lod:
		_crosswalks()
	_islands()

	var mats := Materials.get_shared()
	_add_mesh(root, "Asphalt", _asphalt, mats.asphalt, false)
	_add_mesh(root, "BrickStreets", _brick, mats.brick_road, false)
	_add_mesh(root, "Sidewalks", _concrete, mats.concrete, not lod)
	_add_mesh(root, "Verges", _gravel, mats.lot_ground, false)
	_add_mesh(root, "CentreLines", _yellow, mats.paint_yellow, false)
	_add_mesh(root, "LaneLines", _white, mats.paint_white, false)
	_add_mesh(root, "RedCrosswalks", _red, mats.paint_red, false)
	_add_mesh(root, "Parapets", _parapets, mats.concrete, true)
	_add_mesh(root, "Islands", _island, mats.grass, false)
	if lod:
		return root

	var faces := PackedVector3Array()
	faces.append_array(_asphalt.faces())
	faces.append_array(_brick.faces())
	faces.append_array(_concrete.faces())
	faces.append_array(_island.faces())
	if not faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "StreetCollision"
		body.collision_layer = Layers.GROUND
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
	if not _parapets.is_empty():
		var walls := StaticBody3D.new()
		walls.name = "BridgeWalls"
		walls.collision_layer = Layers.SOLID
		walls.collision_mask = 0
		var shape2 := ConcavePolygonShape3D.new()
		shape2.backface_collision = true
		shape2.set_faces(_parapets.faces())
		var cs2 := CollisionShape3D.new()
		cs2.shape = shape2
		walls.add_child(cs2)
		root.add_child(walls)
	return root


func _add_mesh(root: Node3D, mesh_name: String, kit: MeshKit, mat: Material, shadows: bool) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = kit.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# --- asphalt -----------------------------------------------------------------------

## Worked out once at startup, after the network: brick streets and where the
## crosswalks go.
static func prepare(net: RoadNetwork, data: StreetData) -> void:
	find_brick_edges(net, data)
	find_crosswalks(net, data)


## Zebra crossings from the OSM crossing points, as distances along their
## streets (net.crosswalks). Each is kept out of the junction box, and two
## that would overlap are made one.
static func find_crosswalks(net: RoadNetwork, data: StreetData) -> void:
	net.crosswalks.clear()
	for p in data.points_of_type("highway=crossing"):
		var kind := str(p.tags.get("crossing", ""))
		if kind == "unmarked" or kind == "no":
			continue
		var hit := net.nearest_on_streets(p.pos, 1.5)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		if e.is_highway() or e.roundabout:
			continue
		var lo := net.mouth_distance(e.a, net.incident_index(e.a, e, true)) + CROSSWALK_DEPTH * 0.5 + 0.3
		var hi := e.length - net.mouth_distance(e.b, net.incident_index(e.b, e, false)) - CROSSWALK_DEPTH * 0.5 - 0.3
		if hi < lo:
			continue
		var along := clampf(float(hit["along"]), lo, hi)
		var list: Array = net.crosswalks.get(e, [])
		var clash := false
		for d: float in list:
			clash = clash or absf(d - along) < CROSSWALK_DEPTH + 1.0
		if not clash:
			list.append(along)
			net.crosswalks[e] = list

## Stretches of street paved in brick, from map_config.json "brick_streets":
## each entry names a street and the two cross streets it runs between.
## Worked out once at startup into net.brick_edges.
static func find_brick_edges(net: RoadNetwork, data: StreetData) -> void:
	for spec: Dictionary in data.config.get("brick_streets", []):
		var street := str(spec.get("street", ""))
		var a := net.find_junction(street, str(spec.get("from", "")))
		var b := net.find_junction(street, str(spec.get("to", "")))
		if a == "" or b == "":
			push_warning("RoadMesher: brick street %s not found" % street)
			continue
		var pa: Vector2 = net.nodes[a]
		var pb: Vector2 = net.nodes[b]
		var ab := pb - pa
		for e in net.edges_near(Rect2(pa, Vector2.ZERO).expand(pb).grow(10.0)):
			if e.name != street:
				continue
			var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
			var t := (mid - pa).dot(ab) / ab.length_squared()
			if t > 0.0 and t < 1.0:
				net.brick_edges[e] = true


## The roadway between the curbs. UV2 tells the asphalt shader where across
## the street each point is: x = metres from the right-hand curb, y = the
## street's half width (negative on one-way streets), so it can wear the
## wheel paths and dirty the gutters.
func _road_strip(e: RoadNetwork.RoadEdge) -> void:
	var lines := _densify(net.side_line(e, 1, RoadNetwork.Level.CURB), net.side_line(e, -1, RoadNetwork.Level.CURB))
	var right: PackedVector2Array = lines[0]
	var left: PackedVector2Array = lines[1]
	var kit := _brick if _brick_edges.has(e) else _asphalt
	var hw := e.half_width * (-1.0 if e.oneway != 0 else 1.0)
	for i in range(right.size() - 1):
		var m0 := (right[i] + left[i]) * 0.5
		var m1 := (right[i + 1] + left[i + 1]) * 0.5
		var w0 := right[i].distance_to(left[i])
		var w1 := right[i + 1].distance_to(left[i + 1])
		# Where another roadway (or a junction box) is drawn on top, this one
		# still goes in, a little lower, so a ragged edge of the one on top
		# never leaves a hole down to the grass.
		var lr := SUNK if _roadway_covered((right[i] + right[i + 1] + m0 + m1) * 0.25, e) else 0.0
		_ground_quad2(kit, right[i], right[i + 1], m1, m0, Vector2(0.0, hw), Vector2(0.0, hw), Vector2(w1 * 0.5, hw), Vector2(w0 * 0.5, hw), lr)
		var ll := SUNK if _roadway_covered((left[i] + left[i + 1] + m0 + m1) * 0.25, e) else 0.0
		_ground_quad2(kit, m0, m1, left[i + 1], left[i], Vector2(w0 * 0.5, hw), Vector2(w1 * 0.5, hw), Vector2(w1, hw), Vector2(w0, hw), ll)


## Where two roadways overlap (a roundabout and the roads flaring into it,
## two carriageways meeting, a ramp joining a highway), only one is drawn,
## so the two surfaces don't flicker through each other.
func _roadway_covered(c: Vector2, e: RoadNetwork.RoadEdge) -> bool:
	var o := net.road_at(c, e, 0.8)
	if o != null and RoadNetwork.outranks(o, e):
		return true
	# Inside any junction (its own ends included) the junction's own surface
	# is the only one drawn.
	return net.in_junction(c)


## A stretch of sidewalk is left out where it would lie on another street,
## in a junction, on a roundabout island, or over a sidewalk that's
## already there.
func _walk_covered(c: Vector2, e: RoadNetwork.RoadEdge) -> bool:
	if net.road_at(c, e, -0.05) != null or net.in_junction(c, [e.a, e.b]):
		return true
	for o in net.edges_near(Rect2(c - Vector2(2, 2), Vector2(4, 4))):
		if o == e or not RoadNetwork.outranks(o, e) or _corner_neighbours(e, o):
			continue
		var d := RoadNetwork.distance_across_edge(o, c)
		if d < o.half_width + maxf(o.walk(1), o.walk(-1)):
			return true
	for isl in net.islands:
		if Geometry2D.is_point_in_polygon(c, isl):
			return true
	return false


## True if e and o leave a shared node at a clear angle: their sidewalks
## meet exactly at the junction's corners, so neither hides the other.
## (Streets meeting at a shallow angle, like a ramp joining a highway, do
## overlap, and are left to the overlap rules.)
func _corner_neighbours(e: RoadNetwork.RoadEdge, o: RoadNetwork.RoadEdge) -> bool:
	for nid: String in [e.a, e.b]:
		if nid != o.a and nid != o.b:
			continue
		var de: Vector2 = net.incidents[nid][net.incident_index(nid, e, nid == e.a)].dir
		var do: Vector2 = net.incidents[nid][net.incident_index(nid, o, nid == o.a)].dir
		if de.dot(do) < RoadNetwork.SHALLOW_DOT:
			return true
	return false


## A flat quad on the ground with UV = metres * 0.25 and the given UV2s.
func _ground_quad2(kit: MeshKit, a: Vector2, b: Vector2, c: Vector2, d: Vector2, u2a: Vector2, u2b: Vector2, u2c: Vector2, u2d: Vector2, lift := 0.0) -> void:
	kit.quad_uv2(_v(a, lift), _v(b, lift), _v(c, lift), _v(d, lift), Vector3.UP, a * 0.25, b * 0.25, c * 0.25, d * 0.25, u2a, u2b, u2c, u2d)


func _junction_fill(nid: String) -> void:
	var c: Vector2 = net.nodes[nid]
	var poly := net.junction_polygon(nid)
	# UV2 x = -1 marks the junction box: worn all over, no wheel paths.
	var j := Vector2(-1.0, 0.0)
	for k in poly.size():
		var p0 := poly[k]
		var p1 := poly[(k + 1) % poly.size()]
		_asphalt.quad_uv2(_v(c, 0.0), _v(p0, 0.0), _v(p1, 0.0), _v(p1, 0.0), Vector3.UP, c * 0.25, p0 * 0.25, p1 * 0.25, p1 * 0.25, j, j, j, j)


# --- sidewalks and curbs ---------------------------------------------------------------

func _sidewalks(e: RoadNetwork.RoadEdge) -> void:
	for side: int in [1, -1]:
		if e.walk(side) <= 0.0:
			if e.is_highway() and not e.bridge:
				_verge(e, side)
			continue
		var lines := _densify(net.side_line(e, side, RoadNetwork.Level.CURB), net.side_line(e, side, RoadNetwork.Level.BACK))
		var curb: PackedVector2Array = lines[0]
		var back: PackedVector2Array = lines[1]
		# UV2 for the sidewalk shader: x = metres along the curb (slab joints),
		# y = metres in from the curb, or -1 on the curb face, -2 on the back edge.
		var along := 0.0
		for i in range(curb.size() - 1):
			var step := curb[i].distance_to(curb[i + 1])
			var a0 := along
			var a1 := along + step
			along = a1
			# Top surface.
			var wd0 := curb[i].distance_to(back[i])
			var wd1 := curb[i + 1].distance_to(back[i + 1])
			if _walk_covered((curb[i] + curb[i + 1] + back[i] + back[i + 1]) * 0.25, e):
				continue
			_concrete.quad_uv2(_v(curb[i], SW_H), _v(curb[i + 1], SW_H), _v(back[i + 1], SW_H), _v(back[i], SW_H), Vector3.UP,
				curb[i] * 0.25, curb[i + 1] * 0.25, back[i + 1] * 0.25, back[i] * 0.25,
				Vector2(a0, 0.0), Vector2(a1, 0.0), Vector2(a1, wd1), Vector2(a0, wd0))
			if lod:
				continue
			# Curb face, looking back toward the road.
			var t := (curb[i + 1] - curb[i]).normalized()
			var right := Vector2(-t.y, t.x) * float(side)
			_concrete.uv2 = Vector2(a0, -1.0)
			_wall(_concrete, curb[i], curb[i + 1], 0.0, SW_H, Vector3(-right.x, 0.0, -right.y))
			# Back edge, down to the lot.
			var tb := (back[i + 1] - back[i]).normalized()
			var rb := Vector2(-tb.y, tb.x) * float(side)
			_concrete.uv2 = Vector2(a0, -2.0)
			_wall(_concrete, back[i], back[i + 1], BACK_DEPTH, SW_H, Vector3(rb.x, 0.0, rb.y))
		# Dead ends (where the data stops): close the end of the slab.
		if not lod and net.degree(e.a) == 1:
			_end_cap(curb[0], back[0])
		if not lod and net.degree(e.b) == 1:
			_end_cap(curb[curb.size() - 1], back[back.size() - 1])


## Gravel beside a highway: from the edge of the asphalt, sloping down
## into the ground.
func _verge(e: RoadNetwork.RoadEdge, side: int) -> void:
	var edge := net.side_line(e, side, RoadNetwork.Level.CURB)
	var n := edge.size()
	var outer := PackedVector2Array()
	outer.resize(n)
	for i in n:
		var d := (edge[mini(i + 1, n - 1)] - edge[maxi(i - 1, 0)]).normalized()
		outer[i] = edge[i] + Vector2(-d.y, d.x) * float(side) * VERGE
	var lines := _densify(edge, outer)
	var a: PackedVector2Array = lines[0]
	var b: PackedVector2Array = lines[1]
	for i in range(a.size() - 1):
		var o0 := Vector3(b[i].x, terrain.h2(b[i]) - 0.12, b[i].y)
		var o1 := Vector3(b[i + 1].x, terrain.h2(b[i + 1]) - 0.12, b[i + 1].y)
		_gravel.ground_quad(_v(a[i], -0.005), _v(a[i + 1], -0.005), o1, o0)
		# A lip down into the ground along the outer edge, so the dip where
		# the ground is carved under the road never shows a gap.
		if not lod:
			var t := (b[i + 1] - b[i]).normalized()
			var out := Vector3(-t.y, 0.0, t.x) * float(side)
			_gravel.quad(o0, o1, o1 + Vector3(0, BACK_DEPTH, 0), o0 + Vector3(0, BACK_DEPTH, 0), out)


func _end_cap(p0: Vector2, p1: Vector2) -> void:
	_concrete.uv2 = Vector2(0.0, -2.0)
	var t := (p1 - p0).normalized()
	var n := Vector3(-t.y, 0.0, t.x)
	_wall(_concrete, p0, p1, BACK_DEPTH, SW_H, n)
	_wall(_concrete, p0, p1, BACK_DEPTH, SW_H, -n)


## Bridges: a concrete parapet along each side and the deck's edge showing
## below it.
func _bridge_sides(e: RoadNetwork.RoadEdge) -> void:
	for side: int in [1, -1]:
		var line := net.side_line(e, side, RoadNetwork.Level.BACK)
		var lines := _densify(line, line)
		var pts: PackedVector2Array = lines[0]
		var lift := SW_H if e.walk(side) > 0.0 else 0.0
		for i in range(pts.size() - 1):
			var t := (pts[i + 1] - pts[i]).normalized()
			var out := Vector2(-t.y, t.x) * float(side)
			var o3 := Vector3(out.x, 0.0, out.y)
			var inner0 := pts[i] - out * 0.3
			var inner1 := pts[i + 1] - out * 0.3
			_parapets.uv2 = Vector2.ZERO
			_wall(_parapets, inner0, inner1, lift, lift + PARAPET_H, -o3)
			_wall(_parapets, pts[i], pts[i + 1], -1.2, lift + PARAPET_H, o3)
			_parapets.quad(_v(inner0, lift + PARAPET_H), _v(inner1, lift + PARAPET_H), _v(pts[i + 1], lift + PARAPET_H), _v(pts[i], lift + PARAPET_H), Vector3.UP)


## Roundabout islands: a raised lawn with a curb round it.
func _islands() -> void:
	var area := rect.grow(2.0)
	for isl in net.islands:
		var box := Rect2(isl[0], Vector2.ZERO)
		for q in isl:
			box = box.expand(q)
		if not box.intersects(area):
			continue
		var idx := Geometry2D.triangulate_polygon(isl)
		for k in range(0, idx.size(), 3):
			var a := isl[idx[k]]
			var b := isl[idx[k + 1]]
			var c := isl[idx[k + 2]]
			_island.ground_tri(_v(a, SW_H), _v(b, SW_H), _v(c, SW_H))
		if lod:
			continue
		var centre := box.get_center()
		for k in isl.size():
			var p0 := isl[k]
			var p1 := isl[(k + 1) % isl.size()]
			var mid := (p0 + p1) * 0.5
			var out := (mid - centre).normalized()
			_concrete.uv2 = Vector2(0.0, -1.0)
			_wall(_concrete, p0, p1, -0.02, SW_H, Vector3(out.x, 0.0, out.y))


# --- paint ----------------------------------------------------------------------------------

## Centre lines on two-way streets; on highways and wide streets lane lines
## and edge lines too.
func _markings(e: RoadNetwork.RoadEdge) -> void:
	if _brick_edges.has(e):
		return
	var ka := net.incident_index(e.a, e, true)
	var kb := net.incident_index(e.b, e, false)
	var start := net.mouth_distance(e.a, ka) + _paint_gap(e, e.a)
	var stop := e.length - net.mouth_distance(e.b, kb) - _paint_gap(e, e.b)
	if stop <= start:
		return
	var carriage := e.half_width * 2.0 - e.shoulder * 2.0
	if e.oneway == 0 and e.half_width >= 4.0:
		if e.is_highway() or e.half_width >= 6.5:
			# Solid double yellow down the middle of a highway or main road.
			_paint_line(_yellow, e.points, start, stop, -0.12, 0.1, 0.0)
			_paint_line(_yellow, e.points, start, stop, 0.12, 0.1, 0.0)
		else:
			_paint_line(_yellow, e.points, start, stop, 0.0, 0.12, 3.0)
	# Lane and edge lines start once the street has tapered out to its full
	# width (the centre line carries straight on).
	start = maxf(start, net.taper_length(e, e.a, ka))
	stop = minf(stop, e.length - net.taper_length(e, e.b, kb))
	# Lanes each way.
	var lanes := e.lanes
	if lanes <= 0:
		lanes = maxi(1, int(round(carriage / LANE_W)))
	if e.oneway != 0 and lanes >= 2 and not e.roundabout:
		var lw := carriage / float(lanes)
		for k in range(1, lanes):
			_paint_line(_white, e.points, start, stop, -carriage * 0.5 + lw * k, 0.12, 3.0)
	elif e.oneway == 0 and lanes >= 4 and e.half_width >= 6.0:
		var per := lanes / 2
		var lw2 := carriage * 0.5 / float(per)
		for k in range(1, per):
			_paint_line(_white, e.points, start, stop, lw2 * k, 0.12, 3.0)
			_paint_line(_white, e.points, start, stop, -lw2 * k, 0.12, 3.0)
	# Edge lines at the shoulders.
	if e.shoulder > 0.0:
		var off := e.half_width - e.shoulder
		_paint_line(_white, e.points, start, stop, off, 0.15, 0.0)
		_paint_line(_white, e.points, start, stop, -off, 0.15, 0.0)


## How far short of node nid the paint on e stops: room for a crosswalk at
## a town junction, a little at a highway junction or a dead end, and none
## where the street just carries on into the next stretch of itself.
func _paint_gap(e: RoadNetwork.RoadEdge, nid: String) -> float:
	var deg := net.degree(nid)
	if deg == 2:
		return 0.0
	if deg == 1 or e.is_highway():
		return 1.5
	return CROSSWALK_DEPTH + 1.5


## A line painted from distance d0 to d1 along a polyline, `lateral` metres
## to the right of it. dash > 0 makes dashes that long with equal gaps.
func _paint_line(kit: MeshKit, pts: PackedVector2Array, d0: float, d1: float, lateral: float, width: float, dash: float) -> void:
	if dash > 0.0:
		var d := d0
		while d + dash <= d1:
			_paint_bar(kit, pts, d, d + dash, lateral, width)
			d += dash * 2.0
		return
	# A solid line is broken exactly at each crosswalk.
	var spans := [Vector2(d0, d1)]
	if _paint_edge != null:
		for c: float in net.crosswalks.get(_paint_edge, []):
			var gap := Vector2(c - CROSSWALK_DEPTH * 0.5 - 1.0, c + CROSSWALK_DEPTH * 0.5 + 1.0)
			var cut := []
			for sp: Vector2 in spans:
				if gap.y <= sp.x or gap.x >= sp.y:
					cut.append(sp)
					continue
				if gap.x - sp.x > 0.5:
					cut.append(Vector2(sp.x, gap.x - 0.01))
				if sp.y - gap.y > 0.5:
					cut.append(Vector2(gap.y + 0.01, sp.y))
			spans = cut
	for sp: Vector2 in spans:
		var d := sp.x
		while d < sp.y:
			var nxt := minf(sp.y, d + STEP * 2.0)
			_paint_bar(kit, pts, d, nxt, lateral, width)
			d = nxt


## A painted rectangle from distance d0 to d1 along a polyline, centred
## `lateral` metres to the right of it, `width` wide.
func _paint_bar(kit: MeshKit, pts: PackedVector2Array, d0: float, d1: float, lateral: float, width: float) -> void:
	var s0: Array = RoadNetwork.sample(pts, d0)
	var s1: Array = RoadNetwork.sample(pts, d1)
	var p0: Vector2 = s0[0]
	var p1: Vector2 = s1[0]
	var r0 := Vector2(-(s0[1] as Vector2).y, (s0[1] as Vector2).x)
	var r1 := Vector2(-(s1[1] as Vector2).y, (s1[1] as Vector2).x)
	# Lines stop short of a crosswalk and start again past it.
	if _paint_edge != null and not _in_crosswalk:
		for c: float in net.crosswalks.get(_paint_edge, []):
			if d1 > c - CROSSWALK_DEPTH * 0.5 - 1.0 and d0 < c + CROSSWALK_DEPTH * 0.5 + 1.0:
				return
	# Paint stops where this street runs into another one's roadway.
	if _paint_edge != null:
		var mid := (p0 + p1) * 0.5 + (r0 + r1) * 0.5 * lateral
		if _roadway_covered(mid, _paint_edge) or net.road_at(mid, _paint_edge, 0.3) != null:
			return
	var hw := width * 0.5
	kit.ground_quad(_v(p0 + r0 * (lateral - hw), MARK_Y), _v(p1 + r1 * (lateral - hw), MARK_Y),
		_v(p1 + r1 * (lateral + hw), MARK_Y), _v(p0 + r0 * (lateral + hw), MARK_Y))


## Zebra crosswalks wherever OSM maps a marked crossing on a street.
## Downtown (within "red_crosswalks_m" of the origin in map_config.json) they
## are Charlottetown's red-and-white ones: red blocks between the white
## stripes, edged by a thin white line each side.
func _crosswalks() -> void:
	_in_crosswalk = true
	var red_r := float(data.config.get("red_crosswalks_m", 0.0))
	for e in net.edges_near(rect.grow(20.0)):
		if not net.crosswalks.has(e):
			continue
		_set_bridge(e)
		_paint_edge = e
		for along: float in net.crosswalks[e]:
			# Stripes evenly spread across the street, the same gap at each curb.
			var stripe := 0.5
			var usable := e.half_width * 2.0 - 0.8
			var n := maxi(1, int((usable + stripe) / (stripe * 2.0)))
			var lateral := -(n * 2 - 1) * stripe * 0.5
			var a0 := along - CROSSWALK_DEPTH * 0.5
			var a1 := along + CROSSWALK_DEPTH * 0.5
			var red := (RoadNetwork.sample(e.points, along)[0] as Vector2).length() < red_r
			for k in n:
				_paint_bar(_white, e.points, a0, a1, lateral + stripe * 0.5, stripe)
				if red and k < n - 1:
					_paint_bar(_red, e.points, a0 + 0.12, a1 - 0.12, lateral + stripe * 1.5, stripe)
				lateral += stripe * 2.0
			if red:
				var span := (n * 2 - 1) * stripe
				_paint_bar(_white, e.points, a0, a0 + 0.12, 0.0, span)
				_paint_bar(_white, e.points, a1 - 0.12, a1, 0.0, span)
	_in_crosswalk = false
	_bridge = null
	_paint_edge = null

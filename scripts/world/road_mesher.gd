class_name RoadMesher
extends RefCounted
## Turns a RoadNetwork into visible streets: asphalt, raised sidewalks with
## curbs, centre lines, crosswalks (from OSM crossing points), and the ground
## collision everything walks and drives on.
##
## Everything follows the real terrain: each vertex takes its height from
## Terrain, long stretches are split every STEP metres so streets follow the
## grade, and roads carry a centreline row so the crown of the street is kept.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT
const MARK_Y := 0.03
const STEP := 3.0 ## metres between rows of vertices along a street
const CROSSWALK_DEPTH := 3.0

var net: RoadNetwork
var data: StreetData
var terrain: Terrain

var _asphalt := MeshKit.new()
var _brick := MeshKit.new()
var _brick_edges: Dictionary = {} ## RoadEdge -> true
var _concrete := MeshKit.new()
var _yellow := MeshKit.new()
var _white := MeshKit.new()
var _ground_faces := PackedVector3Array()


func _init(network: RoadNetwork, street_data: StreetData, ground: Terrain) -> void:
	net = network
	data = street_data
	terrain = ground


## A ground point at the real terrain height plus `lift`.
func _v(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, terrain.h2(p) + lift, p.y)


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


## A vertical strip along ground points p0-p1, from `lo` to `hi` above the terrain.
func _wall(kit: MeshKit, p0: Vector2, p1: Vector2, lo: float, hi: float, n: Vector3) -> void:
	kit.quad(_v(p0, lo), _v(p1, lo), _v(p1, hi), _v(p0, hi), n)


## Builds everything under a new Node3D and returns it.
func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Streets"
	_find_brick_edges()
	for e in net.edges:
		_road_strip(e)
		_sidewalks(e)
		if e.oneway == 0 and e.half_width >= 4.0 and not _brick_edges.has(e):
			_centre_line(e)
	for nid: String in net.incidents:
		if net.degree(nid) >= 3:
			_junction_fill(nid)
	_crosswalks()

	var mats := Materials.get_shared()
	_add_mesh(root, "Asphalt", _asphalt, mats.asphalt, false)
	_add_mesh(root, "BrickStreets", _brick, mats.brick_road, false)
	_add_mesh(root, "Sidewalks", _concrete, mats.concrete, true)
	_add_mesh(root, "CentreLines", _yellow, mats.paint_yellow, false)
	_add_mesh(root, "Crosswalks", _white, mats.paint_white, false)

	_ground_faces.append_array(_asphalt.faces())
	_ground_faces.append_array(_brick.faces())
	_ground_faces.append_array(_concrete.faces())
	var body := StaticBody3D.new()
	body.name = "StreetCollision"
	body.collision_layer = Layers.GROUND
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_ground_faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
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

## Stretches of street paved in brick, from map_config.json "brick_streets":
## each entry names a street and the two cross streets it runs between.
func _find_brick_edges() -> void:
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
		for e in net.edges:
			if e.name != street:
				continue
			var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
			var t := (mid - pa).dot(ab) / ab.length_squared()
			if t > 0.0 and t < 1.0:
				_brick_edges[e] = true


func _road_strip(e: RoadNetwork.RoadEdge) -> void:
	var lines := _densify(net.side_line(e, 1, RoadNetwork.Level.CURB), net.side_line(e, -1, RoadNetwork.Level.CURB))
	var right: PackedVector2Array = lines[0]
	var left: PackedVector2Array = lines[1]
	var kit := _brick if _brick_edges.has(e) else _asphalt
	for i in range(right.size() - 1):
		var m0 := (right[i] + left[i]) * 0.5
		var m1 := (right[i + 1] + left[i + 1]) * 0.5
		kit.ground_quad(_v(right[i], 0.0), _v(right[i + 1], 0.0), _v(m1, 0.0), _v(m0, 0.0))
		kit.ground_quad(_v(m0, 0.0), _v(m1, 0.0), _v(left[i + 1], 0.0), _v(left[i], 0.0))


func _junction_fill(nid: String) -> void:
	var c: Vector2 = net.nodes[nid]
	var poly := net.junction_polygon(nid)
	for k in poly.size():
		_asphalt.ground_tri(_v(c, 0.0), _v(poly[k], 0.0), _v(poly[(k + 1) % poly.size()], 0.0))


# --- sidewalks and curbs ---------------------------------------------------------------

func _sidewalks(e: RoadNetwork.RoadEdge) -> void:
	for side: int in [1, -1]:
		var lines := _densify(net.side_line(e, side, RoadNetwork.Level.CURB), net.side_line(e, side, RoadNetwork.Level.BACK))
		var curb: PackedVector2Array = lines[0]
		var back: PackedVector2Array = lines[1]
		for i in range(curb.size() - 1):
			# Top surface.
			_concrete.ground_quad(_v(curb[i], SW_H), _v(curb[i + 1], SW_H), _v(back[i + 1], SW_H), _v(back[i], SW_H))
			# Curb face, looking back toward the road.
			var t := (curb[i + 1] - curb[i]).normalized()
			var right := Vector2(-t.y, t.x) * float(side)
			_wall(_concrete, curb[i], curb[i + 1], 0.0, SW_H, Vector3(-right.x, 0.0, -right.y))
			# Back edge, down to the lot.
			var tb := (back[i + 1] - back[i]).normalized()
			var rb := Vector2(-tb.y, tb.x) * float(side)
			_wall(_concrete, back[i], back[i + 1], -0.2, SW_H, Vector3(rb.x, 0.0, rb.y))
		# Dead ends (where the data stops): close the end of the slab.
		if net.degree(e.a) == 1:
			_end_cap(curb[0], back[0])
		if net.degree(e.b) == 1:
			_end_cap(curb[curb.size() - 1], back[back.size() - 1])


func _end_cap(p0: Vector2, p1: Vector2) -> void:
	var t := (p1 - p0).normalized()
	var n := Vector3(-t.y, 0.0, t.x)
	_wall(_concrete, p0, p1, -0.2, SW_H, n)
	_wall(_concrete, p0, p1, -0.2, SW_H, -n)


# --- paint ----------------------------------------------------------------------------------

func _centre_line(e: RoadNetwork.RoadEdge) -> void:
	var ka := net.incident_index(e.a, e, true)
	var kb := net.incident_index(e.b, e, false)
	var start := net.mouth_distance(e.a, ka) + CROSSWALK_DEPTH + 1.5
	var stop := e.length - net.mouth_distance(e.b, kb) - CROSSWALK_DEPTH - 1.5
	var dash := 3.0
	var gap := 3.0
	var d := start
	while d + dash <= stop:
		_paint_bar(_yellow, e.points, d, d + dash, 0.0, 0.12)
		d += dash + gap


## A painted rectangle from distance d0 to d1 along a polyline, centred
## `lateral` metres to the right of it, `width` wide.
func _paint_bar(kit: MeshKit, pts: PackedVector2Array, d0: float, d1: float, lateral: float, width: float) -> void:
	var s0: Array = RoadNetwork.sample(pts, d0)
	var s1: Array = RoadNetwork.sample(pts, d1)
	var p0: Vector2 = s0[0]
	var p1: Vector2 = s1[0]
	var dir: Vector2 = s0[1]
	var r := Vector2(-dir.y, dir.x)
	var hw := width * 0.5
	kit.ground_quad(_v(p0 + r * (lateral - hw), MARK_Y), _v(p1 + r * (lateral - hw), MARK_Y),
		_v(p1 + r * (lateral + hw), MARK_Y), _v(p0 + r * (lateral + hw), MARK_Y))


## Zebra crosswalks wherever OSM maps a marked crossing on a street.
func _crosswalks() -> void:
	for p in data.points_of_type("highway=crossing"):
		var kind := str(p.tags.get("crossing", ""))
		if kind == "unmarked" or kind == "no":
			continue
		var hit := net.nearest_on_streets(p.pos, 1.5)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var along: float = hit["along"]
		# Keep the stripes out of the junction box itself.
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var lo := net.mouth_distance(e.a, ka) + CROSSWALK_DEPTH * 0.5 + 0.3
		var hi := e.length - net.mouth_distance(e.b, kb) - CROSSWALK_DEPTH * 0.5 - 0.3
		if hi < lo:
			continue
		along = clampf(along, lo, hi)
		var stripe := 0.5
		var lateral := -e.half_width + 0.6
		while lateral + stripe <= e.half_width - 0.4:
			_paint_bar(_white, e.points, along - CROSSWALK_DEPTH * 0.5, along + CROSSWALK_DEPTH * 0.5, lateral + stripe * 0.5, stripe)
			lateral += stripe * 2.0

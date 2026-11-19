class_name RoadMesher
extends RefCounted
## Turns a RoadNetwork into visible streets: asphalt, raised sidewalks with
## curbs, centre lines, crosswalks (from OSM crossing points), and the ground
## collision everything walks and drives on.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT
const MARK_Y := 0.012
const CROSSWALK_DEPTH := 3.0

var net: RoadNetwork
var data: StreetData

var _asphalt := MeshKit.new()
var _concrete := MeshKit.new()
var _yellow := MeshKit.new()
var _white := MeshKit.new()
var _ground_faces := PackedVector3Array()


func _init(network: RoadNetwork, street_data: StreetData) -> void:
	net = network
	data = street_data


## Builds everything under a new Node3D and returns it.
func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Streets"
	for e in net.edges:
		_road_strip(e)
		_sidewalks(e)
		if e.oneway == 0 and e.half_width >= 4.0:
			_centre_line(e)
	for nid: String in net.incidents:
		if net.degree(nid) >= 3:
			_junction_fill(nid)
	_crosswalks()

	var mats := Materials.get_shared()
	_add_mesh(root, "Asphalt", _asphalt, mats.asphalt, false)
	_add_mesh(root, "Sidewalks", _concrete, mats.concrete, true)
	_add_mesh(root, "CentreLines", _yellow, mats.paint_yellow, false)
	_add_mesh(root, "Crosswalks", _white, mats.paint_white, false)

	_ground_faces.append_array(_asphalt.faces())
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

func _road_strip(e: RoadNetwork.RoadEdge) -> void:
	var right := net.side_line(e, 1, RoadNetwork.Level.CURB)
	var left := net.side_line(e, -1, RoadNetwork.Level.CURB)
	for i in range(right.size() - 1):
		_asphalt.ground_quad(MeshKit.v3(right[i], 0.0), MeshKit.v3(right[i + 1], 0.0),
			MeshKit.v3(left[i + 1], 0.0), MeshKit.v3(left[i], 0.0))


func _junction_fill(nid: String) -> void:
	var c: Vector2 = net.nodes[nid]
	var poly := net.junction_polygon(nid)
	for k in poly.size():
		_asphalt.ground_tri(MeshKit.v3(c, 0.0), MeshKit.v3(poly[k], 0.0), MeshKit.v3(poly[(k + 1) % poly.size()], 0.0))


# --- sidewalks and curbs ---------------------------------------------------------------

func _sidewalks(e: RoadNetwork.RoadEdge) -> void:
	for side: int in [1, -1]:
		var curb := net.side_line(e, side, RoadNetwork.Level.CURB)
		var back := net.side_line(e, side, RoadNetwork.Level.BACK)
		for i in range(curb.size() - 1):
			# Top surface.
			_concrete.ground_quad(MeshKit.v3(curb[i], SW_H), MeshKit.v3(curb[i + 1], SW_H),
				MeshKit.v3(back[i + 1], SW_H), MeshKit.v3(back[i], SW_H))
			# Curb face, looking back toward the road.
			var t := (curb[i + 1] - curb[i]).normalized()
			var right := Vector2(-t.y, t.x) * float(side)
			_concrete.wall(curb[i], curb[i + 1], 0.0, SW_H, Vector3(-right.x, 0.0, -right.y))
			# Back edge, down to the lot.
			var tb := (back[i + 1] - back[i]).normalized()
			var rb := Vector2(-tb.y, tb.x) * float(side)
			_concrete.wall(back[i], back[i + 1], -0.06, SW_H, Vector3(rb.x, 0.0, rb.y))
		# Dead ends (where the data stops): close the end of the slab.
		if net.degree(e.a) == 1:
			_end_cap(curb[0], back[0])
		if net.degree(e.b) == 1:
			_end_cap(curb[curb.size() - 1], back[back.size() - 1])


func _end_cap(p0: Vector2, p1: Vector2) -> void:
	var t := (p1 - p0).normalized()
	var n := Vector3(-t.y, 0.0, t.x)
	_concrete.wall(p0, p1, -0.06, SW_H, n)
	_concrete.wall(p0, p1, -0.06, SW_H, -n)


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
	kit.ground_quad(MeshKit.v3(p0 + r * (lateral - hw), MARK_Y), MeshKit.v3(p1 + r * (lateral - hw), MARK_Y),
		MeshKit.v3(p1 + r * (lateral + hw), MARK_Y), MeshKit.v3(p0 + r * (lateral + hw), MARK_Y))


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

class_name WorldBuilder
extends Node3D
## Builds the town at startup from data/map_config.json.
##
## Order: load data -> road graph -> ground -> streets -> buildings -> props ->
## play-area boundary. Other systems (player spawn, minimap, NPCs, missions)
## read `data`, `network` and `play_area` from here once `built` has fired.

signal built

## Height of the open lots between streets (just under the sidewalks' back edge).
const GROUND_Y := -0.06

@export_file("*.json") var config_path := "res://data/map_config.json"

var data: StreetData
var network: RoadNetwork
## The four play-area corner junctions, in order.
var play_area := PackedVector2Array()
## The invisible wall line, margin_m outside play_area.
var boundary := PackedVector2Array()
var is_built := false


func _ready() -> void:
	build()


func build() -> void:
	var t0 := Time.get_ticks_msec()
	data = StreetData.load_from(config_path)
	if data.roads.is_empty():
		push_error("WorldBuilder: no roads loaded from %s. See data/README.md." % config_path)
		return
	network = RoadNetwork.new(data)
	_find_play_area()

	add_child(_ground())
	add_child(GroundAreas.new(data).build())
	add_child(RoadMesher.new(network, data).build())
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	var count := BuildingGenerator.new(data, network).build(buildings)
	add_child(StreetProps.new(network, data).build())
	add_child(_boundary())

	is_built = true
	print("WorldBuilder: %d street segments, %d junctions, %d buildings in %d ms. Map data %s." % [
		network.edges.size(), network.nodes.size(), count, Time.get_ticks_msec() - t0,
		str(data.metadata.get("attribution", "")),
	])
	built.emit()


# --- play area ----------------------------------------------------------------------

func _find_play_area() -> void:
	var cfg: Dictionary = data.config.get("play_area", {})
	for pair: Array in cfg.get("corners", []):
		var nid := network.find_junction(str(pair[0]), str(pair[1]))
		if nid == "":
			push_error("WorldBuilder: no junction of %s and %s in the data." % [pair[0], pair[1]])
			continue
		play_area.append(network.nodes[nid])
	if play_area.size() < 3:
		push_warning("WorldBuilder: play area corners missing, using the whole map.")
		var first_node: Vector2 = network.nodes.values()[0]
		var r := Rect2(first_node, Vector2.ZERO)
		for p: Vector2 in network.nodes.values():
			r = r.expand(p)
		play_area = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var margin := float(cfg.get("margin_m", 30.0))
	boundary = _grow_convex(play_area, margin)


## Push every edge of a convex polygon `by` metres away from its centre and
## join the moved edges at their crossings. Works whichever way the corners
## are listed (Geometry2D.offset_polygon shrinks clockwise polygons instead).
static func _grow_convex(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= float(poly.size())
	var n := poly.size()
	var lines: Array = [] # [point on moved edge, edge direction]
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var dir := (b - a).normalized()
		var out := Vector2(-dir.y, dir.x)
		if out.dot((a + b) * 0.5 - center) < 0.0:
			out = -out
		lines.append([a + out * by, dir])
	var result := PackedVector2Array()
	for i in n:
		var prev: Array = lines[(i - 1 + n) % n]
		var cur: Array = lines[i]
		var hit: Variant = Geometry2D.line_intersects_line(prev[0], prev[1], cur[0], cur[1])
		result.append(hit if hit is Vector2 else (cur[0] as Vector2))
	return result


func play_area_center() -> Vector2:
	var c := Vector2.ZERO
	for p in play_area:
		c += p
	return c / maxf(1.0, play_area.size())


func is_in_play_area(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, play_area)


## Where the player starts: on the sidewalk at the junction named in the config.
func get_spawn() -> Transform3D:
	var s: Dictionary = data.config.get("spawn", {})
	var streets: Array = s.get("streets", [])
	var nid := ""
	if streets.size() >= 2:
		nid = network.find_junction(str(streets[0]), str(streets[1]))
	if nid == "":
		var c := play_area_center()
		return Transform3D(Basis.IDENTITY, Vector3(c.x, 1.0, c.y))
	var deg := network.degree(nid)
	var first := int(s.get("corner", 0)) % deg
	var pos := network.corner_right(nid, first, RoadNetwork.Level.WALK)
	for i in deg:
		var k := (first + i) % deg
		var p := network.corner_right(nid, k, RoadNetwork.Level.WALK)
		if is_in_play_area(p):
			pos = p
			break
	# Face the middle of the play area.
	var to_center := play_area_center() - pos
	var yaw := atan2(-to_center.x, -to_center.y)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, RoadNetwork.SIDEWALK_HEIGHT + 0.05, pos.y))


## Where the player's car starts: parked against the right-hand curb of the
## street named in the config, a set distance from a junction.
func get_car_spawn() -> Transform3D:
	var c: Dictionary = data.config.get("car_spawn", {})
	var street := str(c.get("street", ""))
	var nid := network.find_junction(street, str(c.get("from", "")))
	if nid == "":
		var g := get_spawn()
		return Transform3D(g.basis, g.origin + g.basis.x * 4.0)
	# Of the stretches of that street leaving the junction, take the one
	# heading toward the "toward" street (or the first one).
	var choice: RoadNetwork.Incident = null
	var toward_id := network.find_junction(street, str(c.get("toward", "")))
	var best := -INF
	for inc: RoadNetwork.Incident in network.incidents[nid]:
		if inc.edge.name != street:
			continue
		var score := 0.0
		if toward_id != "":
			score = inc.dir.dot(((network.nodes[toward_id] as Vector2) - (network.nodes[nid] as Vector2)).normalized())
		if score > best:
			best = score
			choice = inc
	for inc: RoadNetwork.Incident in [choice] if choice != null else []:
		var e := inc.edge
		var pts := e.points if inc.at_start else _reversed(e.points)
		var d := minf(float(c.get("distance_m", 15.0)), e.length - 6.0)
		var sp: Array = RoadNetwork.sample(pts, d)
		var at: Vector2 = sp[0]
		var dir: Vector2 = sp[1]
		var right := Vector2(-dir.y, dir.x)
		var pos := at + right * (e.half_width - 1.15)
		return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(pos.x, 0.05, pos.y))
	var g2 := get_spawn()
	return Transform3D(g2.basis, g2.origin)


static func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.reverse()
	return out


## Name of the street nearest a ground position, or "" if none is close.
func street_name_at(p: Vector2, max_dist := 25.0) -> String:
	var hit := network.nearest_on_streets(p, max_dist)
	if hit.is_empty():
		return ""
	var e: RoadNetwork.RoadEdge = hit["edge"]
	return e.name


# --- ground ------------------------------------------------------------------------------

func _ground() -> Node3D:
	var c := play_area_center()
	var size := 1200.0
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.GROUND
	body.collision_mask = 0
	body.position = Vector3(c.x, GROUND_Y, c.y)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	# PlaneMesh UVs run 0..1 over the whole plane; scale so the noise matches the streets.
	var mat: StandardMaterial3D = Materials.get_shared().lot_ground.duplicate()
	mat.uv1_scale = Vector3(size / 8.0, size / 8.0, 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 1.0, size)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)
	return body


# --- boundary -----------------------------------------------------------------------------

func _boundary() -> Node3D:
	var root := Node3D.new()
	root.name = "Boundary"
	var walls := StaticBody3D.new()
	walls.name = "InvisibleWalls"
	walls.collision_layer = Layers.BOUNDARY
	walls.collision_mask = 0
	root.add_child(walls)
	for i in boundary.size():
		var a := boundary[i]
		var b := boundary[(i + 1) % boundary.size()]
		var shape := BoxShape3D.new()
		shape.size = Vector3(a.distance_to(b) + 2.0, 30.0, 1.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var mid := (a + b) * 0.5
		cs.position = Vector3(mid.x, 10.0, mid.y)
		cs.rotation.y = StreetProps.yaw_along((b - a).normalized())
		walls.add_child(cs)

	# A row of road-closed barriers wherever a street crosses the boundary,
	# so the edge of the world reads as "this road is closed", not a glitch.
	for e in network.edges:
		for i in range(e.points.size() - 1):
			for j in boundary.size():
				var hit: Variant = Geometry2D.segment_intersects_segment(e.points[i], e.points[i + 1], boundary[j], boundary[(j + 1) % boundary.size()])
				if hit is Vector2:
					var dir := (e.points[i + 1] - e.points[i]).normalized()
					_barricade(root, hit, dir, e.half_width + e.sidewalk)
	return root


func _barricade(root: Node3D, at: Vector2, road_dir: Vector2, half_span: float) -> void:
	var mats := Materials.get_shared()
	var orange := mats.plain(Color(0.92, 0.42, 0.08), 0.6)
	var white := mats.plain(Color(0.92, 0.92, 0.9), 0.6)
	var across := Vector2(-road_dir.y, road_dir.x)
	var holder := Node3D.new()
	holder.position = Vector3(at.x, 0.0, at.y)
	holder.rotation.y = StreetProps.yaw_along(across)
	root.add_child(holder)
	var board := BoxMesh.new()
	board.size = Vector3(1.0, 0.25, 0.06)
	var leg := BoxMesh.new()
	leg.size = Vector3(0.06, 1.1, 0.06)
	leg.material = white
	var n := int(ceil(half_span * 2.0))
	for k in n:
		var x := -half_span + 0.5 + k
		var stripe := MeshInstance3D.new()
		stripe.mesh = board
		stripe.material_override = orange if k % 2 == 0 else white
		stripe.position = Vector3(x, 0.95, 0.0)
		holder.add_child(stripe)
		if k % 3 == 0:
			var l := MeshInstance3D.new()
			l.mesh = leg
			l.position = Vector3(x, 0.55, 0.0)
			holder.add_child(l)

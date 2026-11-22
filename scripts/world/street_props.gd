class_name StreetProps
extends RefCounted
## Street furniture placed from the data:
##   * a street-name sign at every junction (real street names),
##   * stop signs where OSM maps highway=stop,
##   * traffic lights at junctions OSM marks with traffic signals,
##   * trees where OSM maps natural=tree.
##   * black heritage lamp posts along the sidewalks, like downtown's.
## Benches and parked cars come in Milestone 3.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT

var net: RoadNetwork
var data: StreetData
var terrain: Terrain
var _mats: Materials

# Shared meshes, built once.
var _pole: CylinderMesh
var _blade: BoxMesh
var _stop_face: CylinderMesh
var _trunk: CylinderMesh
var _crowns: Array[SphereMesh] = []
var _signal_box: BoxMesh
var _lamp: SphereMesh


func _init(network: RoadNetwork, street_data: StreetData, ground: Terrain) -> void:
	terrain = ground
	net = network
	data = street_data
	_mats = Materials.get_shared()
	_pole = CylinderMesh.new()
	_pole.top_radius = 0.045
	_pole.bottom_radius = 0.05
	_pole.height = 3.0
	_pole.radial_segments = 8
	_pole.material = _mats.plain(Color(0.35, 0.37, 0.38), 0.5, 0.6)
	_blade = BoxMesh.new()
	_blade.size = Vector3(1.6, 0.3, 0.025)
	_blade.material = _mats.plain(Color(0.08, 0.36, 0.2), 0.5)
	_stop_face = CylinderMesh.new()
	_stop_face.top_radius = 0.38
	_stop_face.bottom_radius = 0.38
	_stop_face.height = 0.03
	_stop_face.radial_segments = 8
	_stop_face.material = _mats.plain(Color(0.75, 0.08, 0.07), 0.5)
	_trunk = CylinderMesh.new()
	_trunk.top_radius = 0.14
	_trunk.bottom_radius = 0.22
	_trunk.height = 4.0
	_trunk.radial_segments = 6
	_trunk.material = _mats.plain(Color(0.33, 0.25, 0.18), 0.95)
	for c in [Color(0.24, 0.4, 0.18), Color(0.29, 0.45, 0.2), Color(0.2, 0.35, 0.17)]:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 1.7
		s.radial_segments = 8
		s.rings = 5
		s.material = _mats.plain(c, 0.9)
		_crowns.append(s)
	_signal_box = BoxMesh.new()
	_signal_box.size = Vector3(0.32, 0.95, 0.25)
	_signal_box.material = _mats.plain(Color(0.12, 0.12, 0.1), 0.6)
	_lamp = SphereMesh.new()
	_lamp.radius = 0.1
	_lamp.height = 0.2
	_lamp.radial_segments = 8
	_lamp.rings = 4


func build() -> Node3D:
	var root := Node3D.new()
	root.name = "StreetProps"
	_street_name_signs(root)
	_stop_signs(root)
	_traffic_signals(root)
	_trees(root)
	_lamps(root)
	return root


# --- street name signs ------------------------------------------------------------------

static func short_name(street: String) -> String:
	return street.replace(" Street", " St").replace(" Avenue", " Ave").replace(" Road", " Rd")


func _street_name_signs(root: Node3D) -> void:
	for nid: String in net.incidents:
		if net.degree(nid) < 3:
			continue
		var list: Array = net.incidents[nid]
		# Choose a corner whose two streets have different names.
		for k in list.size():
			var a: RoadNetwork.Incident = list[k]
			var b: RoadNetwork.Incident = list[(k + 1) % list.size()]
			if a.edge.name == b.edge.name or a.edge.name == "" or b.edge.name == "":
				continue
			var pos := net.corner_right(nid, k, RoadNetwork.Level.PROP)
			var post := _post(root, pos, 3.0)
			_name_blade(post, a.edge.name, a.dir, 2.75)
			_name_blade(post, b.edge.name, b.dir, 2.5)
			break


func _post(root: Node3D, pos: Vector2, height: float) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	body.position = terrain.at(pos, SW_H)
	var mi := MeshInstance3D.new()
	mi.mesh = _pole
	mi.scale = Vector3(1.0, height / 3.0, 1.0)
	mi.position.y = height * 0.5
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.08
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	body.add_child(cs)
	root.add_child(body)
	return body


## Yaw that turns local +X to point along ground direction d.
static func yaw_along(d: Vector2) -> float:
	return atan2(-d.y, d.x)


## Yaw that turns local +Z (the side Label3D and our sign faces show) to face
## ground direction n.
static func yaw_facing(n: Vector2) -> float:
	return atan2(n.x, n.y)


func _name_blade(post: Node3D, street: String, dir: Vector2, y: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0, y, 0)
	holder.rotation.y = yaw_along(dir)
	# Shift the blade so it hangs out over the street it names.
	var blade := MeshInstance3D.new()
	blade.mesh = _blade
	blade.position.x = 0.75
	holder.add_child(blade)
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = short_name(street)
		label.font_size = 64
		label.pixel_size = 0.004
		label.outline_size = 0
		label.modulate = Color(0.95, 0.97, 0.95)
		label.double_sided = false
		label.position = Vector3(0.75, 0.0, 0.016 * side)
		if side < 0.0:
			label.rotation.y = PI
		holder.add_child(label)
	post.add_child(holder)


# --- stop signs -----------------------------------------------------------------------------

func _stop_signs(root: Node3D) -> void:
	for p in data.points_of_type("highway=stop"):
		var hit := net.nearest_on_streets(p.pos, 2.0)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var along: float = hit["along"]
		var dir: Vector2 = hit["dir"]
		# Traffic stops as it reaches the nearer end of the street.
		var travel := dir if along > e.length * 0.5 else -dir
		var right := Vector2(-travel.y, travel.x)
		var pos: Vector2 = hit["pos"] + right * (e.half_width + 0.5)
		var post := _post(root, pos, 2.4)
		# The sign faces the cars coming toward it.
		var facing := -travel
		var normal := Vector3(facing.x, 0.0, facing.y)
		var face := MeshInstance3D.new()
		face.mesh = _stop_face
		# The octagon is a flat cylinder: point its axis at oncoming traffic.
		face.basis = Basis(Vector3.UP, normal, Vector3.UP.cross(normal))
		face.position = Vector3(0.0, 2.15, 0.0) + normal * 0.05
		post.add_child(face)
		var label := Label3D.new()
		label.text = "STOP"
		label.font_size = 40
		label.pixel_size = 0.004
		label.outline_size = 0
		label.double_sided = false
		label.modulate = Color(1, 1, 1)
		label.position = Vector3(0.0, 2.15, 0.0) + normal * 0.075
		label.rotation.y = yaw_facing(facing)
		post.add_child(label)


# --- traffic signals -----------------------------------------------------------------------

func _traffic_signals(root: Node3D) -> void:
	var junctions := {}
	var sources := data.points_of_type("highway=traffic_signals")
	for p in data.points_of_type("highway=crossing"):
		if str(p.tags.get("crossing", "")) == "traffic_signals":
			sources.append(p)
	for p in sources:
		var best := ""
		var best_d := 30.0
		for nid: String in net.incidents:
			if net.degree(nid) < 3:
				continue
			var d := p.pos.distance_to(net.nodes[nid])
			if d < best_d:
				best_d = d
				best = nid
		if best != "":
			junctions[best] = true
	for nid: String in junctions:
		var controller := TrafficSignal.new()
		controller.name = "Signals_%s" % nid
		root.add_child(controller)
		var list: Array = net.incidents[nid]
		for k in list.size():
			var inc: RoadNetwork.Incident = list[k]
			# One signal head per approach, on the corner to the right of the
			# cars coming in (the left side of the incident, seen from the junction).
			var pos := net.corner_left(nid, k, RoadNetwork.Level.PROP)
			var post := _post(root, pos, 3.4)
			var head := Node3D.new()
			head.position = Vector3(0.0, 2.9, 0.0)
			head.rotation.y = yaw_facing(inc.dir) # lamps face out along the approach
			var box := MeshInstance3D.new()
			box.mesh = _signal_box
			head.add_child(box)
			var lamps: Array[MeshInstance3D] = []
			for i in 3:
				var lamp := MeshInstance3D.new()
				lamp.mesh = _lamp
				lamp.position = Vector3(0.0, 0.3 - 0.3 * i, 0.13)
				head.add_child(lamp)
				lamps.append(lamp)
			post.add_child(head)
			# Approaches alternate between two phases by direction.
			var phase := 0 if absf(inc.dir.x) >= absf(inc.dir.y) else 1
			controller.add_head(lamps, phase)


# --- trees ------------------------------------------------------------------------------------

func _trees(root: Node3D) -> void:
	for p in data.points_of_type("natural=tree"):
		var hit := net.nearest_on_streets(p.pos, 12.0)
		if not hit.is_empty():
			var e: RoadNetwork.RoadEdge = hit["edge"]
			if float(hit["dist"]) < e.half_width + 0.3:
				continue # mapped in the roadway: skip rather than block traffic
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(p.id)
		var body := StaticBody3D.new()
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		body.position = terrain.at(p.pos, -0.05)
		var size := rng.randf_range(0.9, 1.35)
		var trunk := MeshInstance3D.new()
		trunk.mesh = _trunk
		trunk.position.y = 2.0 * size
		trunk.scale = Vector3(size, size, size)
		body.add_child(trunk)
		for i in 3:
			var crown := MeshInstance3D.new()
			crown.mesh = _crowns[rng.randi() % _crowns.size()]
			var r := rng.randf_range(2.2, 3.1) * size
			crown.scale = Vector3(r, r, r)
			crown.position = Vector3(rng.randf_range(-1.4, 1.4), (5.2 + i * 1.3) * size, rng.randf_range(-1.4, 1.4))
			crown.set_meta("radius", r)
			crown.add_to_group("camera_fade_props")
			body.add_child(crown)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.22 * size
		shape.height = 4.0 * size
		cs.shape = shape
		cs.position.y = 2.0 * size
		body.add_child(cs)
		root.add_child(body)


# --- heritage lamp posts ------------------------------------------------------------------------

const LAMP_SPACING := 24.0


## Black cast-iron style lamp posts along both sides of every street, kept
## clear of the junctions. Drawn as three MultiMeshes (base, post, lantern) so
## hundreds of them cost three draw calls, with one static body for collision.
func _lamps(root: Node3D) -> void:
	var spots: Array[Vector2] = []
	for e in net.edges:
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 6.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 6.0
		if stop - start < 4.0:
			continue
		for side: int in [1, -1]:
			var line := net.side_line(e, side, RoadNetwork.Level.PROP)
			var d := start + (LAMP_SPACING * 0.5 if side < 0 else 0.0)
			var line_len := RoadNetwork.polyline_length(line)
			var scale := line_len / e.length
			while d < stop:
				var sp: Array = RoadNetwork.sample(line, d * scale)
				spots.append(sp[0])
				d += LAMP_SPACING
	if spots.is_empty():
		return
	var black := _mats.plain(Color(0.07, 0.07, 0.07), 0.45, 0.3)
	var base := CylinderMesh.new()
	base.top_radius = 0.1
	base.bottom_radius = 0.16
	base.height = 0.6
	base.radial_segments = 8
	base.material = black
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.07
	post.height = 3.4
	post.radial_segments = 8
	post.material = black
	var lantern := CylinderMesh.new()
	lantern.top_radius = 0.24
	lantern.bottom_radius = 0.13
	lantern.height = 0.5
	lantern.radial_segments = 6
	lantern.material = _mats.glow(Color(1.0, 0.9, 0.7), 0.4)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.02
	cap.bottom_radius = 0.28
	cap.height = 0.22
	cap.radial_segments = 6
	cap.material = black
	var parts := [[base, 0.3], [post, 2.0], [lantern, 3.95], [cap, 4.31]]
	for part: Array in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, terrain.at(spots[i], SW_H + float(part[1]))))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	var body := StaticBody3D.new()
	body.name = "LampPosts"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = 4.0
	for p in spots:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = terrain.at(p, SW_H + 2.0)
		body.add_child(cs)
	root.add_child(body)

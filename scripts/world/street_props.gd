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
var _trunks: Array[ArrayMesh] = []
var _crowns: Array[ArrayMesh] = []
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
	var bark := _mats.plain(Color(0.3, 0.26, 0.22), 0.95)
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/foliage.gdshader")
	var palette := [Color(0.22, 0.36, 0.15), Color(0.27, 0.41, 0.17), Color(0.19, 0.32, 0.15), Color(0.3, 0.4, 0.16)]
	for v in 4:
		_crowns.append(_crown_mesh(v, palette[v], leaves))
	for v in 3:
		_trunks.append(_trunk_mesh(v, bark))
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
	# Trunks are drawn as one MultiMesh per trunk shape; each crown is its
	# own mesh instance so the camera can fade it when it's in the way.
	var trunk_xforms: Array[Array] = [[], [], []]
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
		var turn := rng.randf() * TAU
		var basis := Basis(Vector3.UP, turn).scaled(Vector3(size, size, size))
		trunk_xforms[rng.randi() % _trunks.size()].append(Transform3D(basis, body.position))
		var crown := MeshInstance3D.new()
		crown.mesh = _crowns[rng.randi() % _crowns.size()]
		crown.transform = Transform3D(basis, Vector3(0.0, CROWN_Y * size, 0.0))
		crown.set_meta("radius", CROWN_R * size)
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
	for v in _trunks.size():
		var list: Array = trunk_xforms[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _trunks[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trunks%d" % v
		mmi.multimesh = mm
		root.add_child(mmi)


const CROWN_Y := 6.4 ## height of the middle of the crown, metres (before scaling)
const CROWN_R := 3.4 ## rough radius of the crown, for camera fading


## A crown: a cluster of lumpy blobs in a rounded, slightly flattened mass.
## Normals point out from the crown's middle (blended with each blob's own)
## so light falls across it softly; the shade inside the crown is baked into
## the vertex colours.
static func _crown_mesh(variant: int, leaf: Color, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var noise := FastNoiseLite.new()
	noise.seed = variant * 31 + 5
	noise.frequency = 0.9
	var blobs := 13 + variant
	var rings := 5
	var segs := 7
	for b in blobs:
		# Spread blobs over the surface of an ellipsoid, a few inside.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1.0), rng.randf_range(-1, 1)).normalized()
		var at := dir * Vector3(2.1, 1.6, 2.1) * rng.randf_range(0.55, 1.0)
		var r := rng.randf_range(1.0, 1.45)
		var tint := leaf * rng.randf_range(0.88, 1.12)
		var grid: Array[PackedVector3Array] = []
		var nrm: Array[PackedVector3Array] = []
		for i in rings + 1:
			var lat := PI * float(i) / float(rings)
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			for j in segs:
				var lon := TAU * float(j) / float(segs)
				var d := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
				var rr := r * (0.85 + 0.3 * noise.get_noise_3dv(at + d * 1.5))
				var pt := at + d * rr * Vector3(1.0, 0.85, 1.0)
				row.append(pt)
				var out := pt.normalized()
				nrow.append((out * 0.75 + d * 0.35).normalized())
			grid.append(row)
			nrm.append(nrow)
		for i in rings:
			for j in segs:
				var j1 := (j + 1) % segs
				var a := grid[i][j]
				var bb := grid[i][j1]
				var c := grid[i + 1][j1]
				var dd := grid[i + 1][j]
				var face := ((a + bb + c + dd) * 0.25 - at).normalized()
				kit.color = tint
				kit.quad_smooth(a, bb, c, dd, nrm[i][j], nrm[i][j1], nrm[i + 1][j1], nrm[i + 1][j], face)
	# Shade each vertex: darker low down and deep inside the crown.
	for k in kit.verts.size():
		var pt := kit.verts[k]
		var lift := clampf((pt.y + 2.6) / 4.6, 0.0, 1.0)
		var depth := clampf(pt.length() / 3.0, 0.0, 1.0)
		kit.colors[k] = (kit.colors[k] * (0.45 + 0.35 * lift + 0.3 * depth)).srgb_to_linear()
	return kit.commit(null, mat)


## A trunk that forks into a few limbs reaching up into the crown.
static func _trunk_mesh(variant: int, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * (variant + 1)
	var kit := MeshKit.new()
	_limb(kit, Vector3(0, -0.2, 0), Vector3(rng.randf_range(-0.2, 0.2), 4.2, rng.randf_range(-0.2, 0.2)), 0.26, 0.16)
	var fork := Vector3(0, 3.6, 0)
	for k in 3 + variant % 2:
		var ang := TAU * float(k) / float(3 + variant % 2) + rng.randf() * 0.8
		var tip := Vector3(cos(ang) * rng.randf_range(1.2, 2.0), rng.randf_range(5.6, 6.8), sin(ang) * rng.randf_range(1.2, 2.0))
		_limb(kit, fork, tip, 0.12, 0.05)
	return kit.commit(null, mat)


## A tapered six-sided limb from a to b, smooth shaded.
static func _limb(kit: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var n := 6
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		kit.quad_smooth(a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, d0, d1, d1, d0, (d0 + d1).normalized())


# --- heritage lamp posts ------------------------------------------------------------------------

const LAMP_SPACING := 24.0

## The cast-iron post as (radius, height) going up, turned round the post.
const LAMP_IRON := [
	[0.0, 0.0], [0.17, 0.0], [0.17, 0.08], [0.14, 0.11], [0.14, 0.27], [0.1, 0.34], [0.115, 0.48],
	[0.075, 0.6], [0.09, 0.66], [0.06, 0.74], [0.052, 3.36], [0.078, 3.42], [0.078, 3.5],
	[0.1, 3.56], [0.15, 3.64], [0.15, 3.68], [0.0, 3.68],
]
## The lantern's roof and finial, above the glass.
const LAMP_CAP := [
	[0.0, 4.12], [0.27, 4.12], [0.27, 4.17], [0.13, 4.31], [0.05, 4.4], [0.065, 4.45], [0.03, 4.52], [0.0, 4.54],
]


## One lamp post with two surfaces, iron and the lantern glass, so every
## lamp in town draws in two calls through one MultiMesh.
func _lamp_mesh() -> ArrayMesh:
	var iron := MeshKit.new()
	_lathe(iron, LAMP_IRON, 12)
	_lathe(iron, LAMP_CAP, 6)
	# Six thin glazing bars up the corners of the lantern.
	for k in 6:
		var a := TAU * float(k) / 6.0
		var lo := Vector3(cos(a) * 0.15, 3.68, sin(a) * 0.15)
		var hi := Vector3(cos(a) * 0.24, 4.12, sin(a) * 0.24)
		StreetProps._limb(iron, lo, hi, 0.012, 0.012)
	var glass := MeshKit.new()
	_lathe(glass, [[0.0, 3.68], [0.145, 3.68], [0.235, 4.12], [0.0, 4.12]], 6)
	var mesh := iron.commit(null, _mats.plain(Color(0.06, 0.065, 0.065), 0.4, 0.5))
	glass.commit(mesh, _mats.glow(Color(1.0, 0.88, 0.66), 0.7))
	return mesh


## Turns a (radius, height) profile round the Y axis. Smooth round the
## post, a crisp edge at each step of the profile.
static func _lathe(kit: MeshKit, profile: Array, segs: int) -> void:
	for i in range(profile.size() - 1):
		var r0 := float(profile[i][0])
		var y0 := float(profile[i][1])
		var r1 := float(profile[i + 1][0])
		var y1 := float(profile[i + 1][1])
		if absf(r0 - r1) < 0.0001 and absf(y0 - y1) < 0.0001:
			continue
		# Outward normal of this step of the profile, in (radius, height).
		var n2 := Vector2(y1 - y0, r0 - r1).normalized()
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var c0 := Vector3(cos(a0), 0.0, sin(a0))
			var c1 := Vector3(cos(a1), 0.0, sin(a1))
			var n0 := (c0 * n2.x + Vector3.UP * n2.y).normalized()
			var n1 := (c1 * n2.x + Vector3.UP * n2.y).normalized()
			var face := ((c0 + c1).normalized() * n2.x + Vector3.UP * n2.y).normalized()
			kit.quad_smooth(c0 * r0 + Vector3.UP * y0, c1 * r0 + Vector3.UP * y0, c1 * r1 + Vector3.UP * y1, c0 * r1 + Vector3.UP * y1, n0, n1, n1, n0, face)


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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _lamp_mesh()
	mm.instance_count = spots.size()
	for i in spots.size():
		var turn := Basis(Vector3.UP, float(i % 6) * 0.17)
		mm.set_instance_transform(i, Transform3D(turn, terrain.at(spots[i], SW_H)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Lamps"
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

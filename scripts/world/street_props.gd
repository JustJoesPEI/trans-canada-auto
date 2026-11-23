class_name StreetProps
extends RefCounted
## Street furniture and trees placed from the data, one chunk at a time:
##   * a street-name sign at every junction (real street names),
##   * stop signs where OSM maps highway=stop,
##   * traffic lights at junctions OSM marks with traffic signals,
##   * trees where OSM maps natural=tree (each crown its own node so the
##     camera can fade it), plus woods filled in where OSM maps a wood or
##     forest, a few trees in parks, and yard trees along residential streets
##     (lighter leafy crowns and spruces, drawn through MultiMeshes),
##   * black heritage lamp posts along downtown's sidewalks, and plain
##     street lights on wooden poles everywhere else.
## Benches and parked cars come in Milestone 3.
##
## The shared meshes are made once (prepare(), on the main thread) and every
## chunk reuses them, so chunks can be built on worker threads.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT

var net: RoadNetwork
var data: StreetData
var terrain: Terrain
var rect: Rect2
var chunk: StreetData.Chunk
var lod := false
var _mats: Materials

# Shared meshes, built once by prepare().
static var _ready_shared := false
static var _pole: CylinderMesh
static var _blade: BoxMesh
static var _stop_face: CylinderMesh
static var _trunks: Array[ArrayMesh] = []
static var _crowns: Array[ArrayMesh] = []
static var _light_crowns: Array[ArrayMesh] = []
static var _spruces: Array[ArrayMesh] = []
static var _signal_box: BoxMesh
static var _lamp: SphereMesh
static var _heritage_lamp: ArrayMesh
static var _street_light: ArrayMesh
static var _trunk_shape: CylinderShape3D
static var _lamp_shape: CylinderShape3D
static var _pole_shape: CylinderShape3D


## Builds the shared meshes. Call once on the main thread before any chunk.
static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	var mats := Materials.get_shared()
	_pole = CylinderMesh.new()
	_pole.top_radius = 0.045
	_pole.bottom_radius = 0.05
	_pole.height = 3.0
	_pole.radial_segments = 8
	_pole.material = mats.plain(Color(0.35, 0.37, 0.38), 0.5, 0.6)
	_blade = BoxMesh.new()
	_blade.size = Vector3(1.6, 0.3, 0.025)
	_blade.material = mats.plain(Color(0.08, 0.36, 0.2), 0.5)
	_stop_face = CylinderMesh.new()
	_stop_face.top_radius = 0.38
	_stop_face.bottom_radius = 0.38
	_stop_face.height = 0.03
	_stop_face.radial_segments = 8
	_stop_face.material = mats.plain(Color(0.75, 0.08, 0.07), 0.5)
	var bark: Material = mats.plain(Color(0.3, 0.26, 0.22), 0.95)
	if BuildingGenerator.facade_relief:
		var photo_bark := ShaderMaterial.new()
		photo_bark.shader = load("res://shaders/bark.gdshader")
		photo_bark.set_shader_parameter("bark", load("res://textures/foliage/bark.jpg"))
		bark = photo_bark
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/foliage.gdshader")
	var palette := [Color(0.22, 0.36, 0.15), Color(0.27, 0.41, 0.17), Color(0.19, 0.32, 0.15), Color(0.3, 0.4, 0.16)]
	var cards := ShaderMaterial.new()
	cards.shader = load("res://shaders/foliage_cards.gdshader")
	cards.set_shader_parameter("leaves", load("res://textures/foliage/leaf_cluster.png"))
	for v in 4:
		if BuildingGenerator.facade_relief:
			_crowns.append(_branchy_crown(v, palette[v], cards, bark, 7, 4, 1.0))
			_light_crowns.append(_branchy_crown(v + 10, palette[v], cards, bark, 5, 3, 1.25))
		else:
			_crowns.append(_crown_mesh(v, palette[v], leaves, 13 + v, 5, 7))
			_light_crowns.append(_crown_mesh(v + 10, palette[v], leaves, 5, 3, 5))
	for v in 3:
		_trunks.append(_trunk_mesh(v, bark, BuildingGenerator.facade_relief))
	var needles := [Color(0.12, 0.22, 0.13), Color(0.15, 0.25, 0.14), Color(0.11, 0.19, 0.12)]
	var needle_cards := ShaderMaterial.new()
	needle_cards.shader = cards.shader
	needle_cards.set_shader_parameter("leaves", load("res://textures/foliage/needle_branch.png"))
	for v in 3:
		if BuildingGenerator.facade_relief:
			_spruces.append(_card_spruce(v, needles[v], needle_cards, bark))
		else:
			_spruces.append(_spruce_mesh(v, needles[v], leaves, bark))
	_signal_box = BoxMesh.new()
	_signal_box.size = Vector3(0.32, 0.95, 0.25)
	_signal_box.material = mats.plain(Color(0.12, 0.12, 0.1), 0.6)
	_lamp = SphereMesh.new()
	_lamp.radius = 0.1
	_lamp.height = 0.2
	_lamp.radial_segments = 8
	_lamp.rings = 4
	_heritage_lamp = _lamp_mesh(mats)
	_street_light = _street_light_mesh(mats)
	_trunk_shape = CylinderShape3D.new()
	_trunk_shape.radius = 0.25
	_trunk_shape.height = 4.0
	_lamp_shape = CylinderShape3D.new()
	_lamp_shape.radius = 0.12
	_lamp_shape.height = 4.0
	_pole_shape = CylinderShape3D.new()
	_pole_shape.radius = 0.15
	_pole_shape.height = 8.0
	if BuildingGenerator.facade_relief:
		StreetClutter.prepare()


func _init(network: RoadNetwork, street_data: StreetData, ground: Terrain, area: Rect2, chunk_data: StreetData.Chunk, low_detail := false) -> void:
	terrain = ground
	net = network
	data = street_data
	rect = area
	chunk = chunk_data
	lod = low_detail
	_mats = Materials.get_shared()


func inside_area(p: Vector2) -> bool:
	return _inside(p)


func _inside(p: Vector2) -> bool:
	return p.x >= rect.position.x and p.x < rect.end.x and p.y >= rect.position.y and p.y < rect.end.y


## Junctions (3 or more streets) whose middle is in this chunk.
func _junctions() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for e in net.edges_near(rect):
		for nid: String in [e.a, e.b]:
			if seen.has(nid):
				continue
			seen[nid] = true
			if net.degree(nid) >= 3 and _inside(net.nodes[nid]):
				out.append(nid)
	return out


func build() -> Node3D:
	var root := Node3D.new()
	root.name = "StreetProps"
	if not lod:
		_street_name_signs(root)
		_stop_signs(root)
		_traffic_signals(root)
		_lamps(root)
		_parking_stalls(root)
		if BuildingGenerator.facade_relief:
			StreetClutter.new(self).build(root)
	_trees(root)
	return root


# --- parking lots -----------------------------------------------------------------------

const STALL_W := 2.75 ## metres between stall lines
const STALL_FROM := 3.0 ## from the aisle's middle to the start of a stall
const STALL_LEN := 5.4

## White stall lines either side of every mapped parking aisle, where the
## stall lies inside a mapped parking lot (or commercial land) and clear of
## buildings and streets.
func _parking_stalls(root: Node3D) -> void:
	var lots: Array[PackedVector2Array] = []
	# Mapped lots, and commercial and industrial land (drawn as asphalt):
	# plenty of big stores have their aisles mapped but not the lot itself.
	for a in chunk.areas:
		if a.type in ["amenity=parking", "landuse=commercial", "landuse=retail", "landuse=industrial"]:
			lots.append(a.ring)
	if lots.is_empty():
		return
	var kit := MeshKit.new()
	kit.clip = rect
	kit.use_clip = true
	var aisle_lines: Array[PackedVector2Array] = []
	var mapped := data.aisles_near(rect.grow(12.0))
	for r: StreetData.Road in mapped:
		aisle_lines.append(r.points)
	# Lots with no aisle mapped through them get rows laid out along their
	# length: stalls either side of an aisle, every 16.8 m across the lot.
	for a in chunk.areas:
		if a.type != "amenity=parking" or absf(BuildingGenerator._signed_area(a.ring)) < 500.0:
			continue
		var has_aisle := false
		for r: StreetData.Road in mapped:
			for q in r.points:
				if Geometry2D.is_point_in_polygon(q, a.ring):
					has_aisle = true
					break
			if has_aisle:
				break
		if has_aisle:
			continue
		var obb := BuildingGenerator._obb(a.ring)
		var c: Vector2 = obb["center"]
		var u: Vector2 = obb["u"]
		var v: Vector2 = obb["v"]
		var hu: float = obb["half_u"]
		var hv: float = obb["half_v"]
		# Rows of stall + aisle + stall, packed across the lot and centred.
		var module := (STALL_FROM + STALL_LEN) * 2.0
		var rows := int(floor(hv * 2.0 / module))
		for k in rows:
			var off := (float(k) - float(rows - 1) * 0.5) * module
			aisle_lines.append(PackedVector2Array([c + v * off - u * hu, c + v * off + u * hu]))
	for line in aisle_lines:
		var length := RoadNetwork.polyline_length(line)
		var d := 4.0
		while d < length - 4.0:
			var sp: Array = RoadNetwork.sample(line, d)
			var at: Vector2 = sp[0]
			var dir: Vector2 = sp[1]
			var side_v := Vector2(-dir.y, dir.x)
			for sd: float in [1.0, -1.0]:
				var p0 := at + side_v * sd * STALL_FROM
				var p1 := at + side_v * sd * (STALL_FROM + STALL_LEN)
				if not (rect.grow(1.0).has_point(p0) or rect.grow(1.0).has_point(p1)):
					continue
				if not _in_any(p0, lots) or not _in_any(p1, lots):
					continue
				var mid := (p0 + p1) * 0.5
				if _in_building(mid, 0.5) or _in_building(p1, 0.5) or not net.clear_of_roads(mid, 0.5):
					continue
				var hw := dir * 0.05
				kit.ground_quad(terrain.at(p0 - hw, -0.05), terrain.at(p1 - hw, -0.05), terrain.at(p1 + hw, -0.05), terrain.at(p0 + hw, -0.05))
			d += STALL_W
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "ParkingStalls"
	mi.mesh = kit.commit(null, _mats.paint_white)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _in_any(p: Vector2, rings: Array[PackedVector2Array]) -> bool:
	for ring in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


# --- street name signs ------------------------------------------------------------------

static func short_name(street: String) -> String:
	return street.replace(" Street", " St").replace(" Avenue", " Ave").replace(" Road", " Rd")


func _street_name_signs(root: Node3D) -> void:
	for nid: String in _junctions():
		var list: Array = net.incidents[nid]
		# Choose a corner whose two streets have different names.
		for k in list.size():
			var a: RoadNetwork.Incident = list[k]
			var b: RoadNetwork.Incident = list[(k + 1) % list.size()]
			if a.edge.name == b.edge.name or a.edge.name == "" or b.edge.name == "" or a.edge.is_highway() or b.edge.is_highway():
				continue
			var pos := net.corner_right(nid, k, RoadNetwork.Level.PROP)
			if not net.clear_of_roads(pos):
				continue
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
		if not _inside(p.pos):
			continue
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
		if not net.clear_of_roads(pos):
			continue
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
		if not rect.grow(30.0).has_point(p.pos):
			continue
		var best := ""
		var best_d := 30.0
		for e in net.edges_near(Rect2(p.pos - Vector2(30, 30), Vector2(60, 60))):
			for nid: String in [e.a, e.b]:
				if net.degree(nid) < 3:
					continue
				var d := p.pos.distance_to(net.nodes[nid])
				if d < best_d:
					best_d = d
					best = nid
		if best != "" and _inside(net.nodes[best]):
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
			if not net.clear_of_roads(pos):
				continue
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
	# Mapped trees: trunks through one MultiMesh per trunk shape; each crown
	# is its own mesh instance so the camera can fade it when it's in the way.
	var trunk_xforms: Array[Array] = [[], [], []]
	var light_xforms: Array[Array] = [[], [], [], []]
	var spruce_xforms: Array[Array] = [[], [], []]
	var trunk_spots := PackedVector3Array()
	for p in chunk.points_of_type("natural=tree"):
		if _on_road(p.pos, 0.3):
			continue # mapped in the roadway: skip rather than block traffic
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(p.id)
		var at := terrain.at(p.pos, -0.05)
		var size := rng.randf_range(0.9, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size))
		trunk_xforms[rng.randi() % _trunks.size()].append(Transform3D(basis, at))
		if lod:
			light_xforms[rng.randi() % 4].append(Transform3D(basis, at + Vector3(0, CROWN_Y * size, 0)))
			continue
		var body := StaticBody3D.new()
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		body.position = at
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

	# The lidar's trees, where they really stand (or, without lidar data,
	# planted ones in woods, parks and yards).
	if data.has_lidar:
		_lidar_trees(root, trunk_xforms, light_xforms, spruce_xforms, trunk_spots)
	for spot: Vector4 in ([] as Array[Vector4]) if data.has_lidar else _planted():
		var at := terrain.at(Vector2(spot.x, spot.y), -0.05)
		var size := spot.z
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(int(spot.x * 10.0), int(spot.y * 10.0)))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size))
		if spot.w > 0.5:
			spruce_xforms[rng.randi() % _spruces.size()].append(Transform3D(basis, at))
		else:
			trunk_xforms[rng.randi() % _trunks.size()].append(Transform3D(basis, at))
			light_xforms[rng.randi() % 4].append(Transform3D(basis, at + Vector3(0, CROWN_Y * size, 0)))
		trunk_spots.append(at)
	_multi(root, "Trunks", _trunks, trunk_xforms, true)
	_multi(root, "Crowns", _light_crowns, light_xforms, true)
	_multi(root, "Spruces", _spruces, spruce_xforms, true)
	if not lod and not trunk_spots.is_empty():
		# All the chunk's trunks as one shape (six-sided posts), built here on
		# the worker thread, so a wooded chunk joins the scene in one go.
		var faces := PackedVector3Array()
		for at in trunk_spots:
			for k in 6:
				var a0 := TAU * float(k) / 6.0
				var a1 := TAU * float(k + 1) / 6.0
				var p0 := at + Vector3(cos(a0), 0.0, sin(a0)) * 0.25
				var p1 := at + Vector3(cos(a1), 0.0, sin(a1)) * 0.25
				var up := Vector3(0, 4.0, 0)
				faces.append_array([p0, p1, p1 + up, p0, p1 + up, p0 + up])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.name = "TreeTrunks"
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


## Trees from the lidar survey: each at its real spot, scaled to its real
## height and crown. A tree whose top hangs over a street gets its trunk
## moved back to the edge of the sidewalk, as real street trees stand. Trees
## mapped one by one in OSM (already planted above) aren't doubled.
func _lidar_trees(root: Node3D, trunk_xforms: Array[Array], light_xforms: Array[Array], spruce_xforms: Array[Array], trunk_spots: PackedVector3Array) -> void:
	var mapped: Array[Vector2] = []
	for p in chunk.points_of_type("natural=tree"):
		mapped.append(p.pos)
	var t := chunk.trees
	for i in range(0, t.size() - 4, 5):
		var p := Vector2(t[i], t[i + 1])
		var h := t[i + 2]
		var r := t[i + 3]
		var conifer := t[i + 4] > 0.5
		if lod and h < 6.0:
			continue
		var skip := false
		for q in mapped:
			if q.distance_to(p) < 3.0:
				skip = true
				break
		if skip:
			continue
		var hit := net.nearest_on_streets(p, 25.0)
		if not hit.is_empty():
			var e: RoadNetwork.RoadEdge = hit["edge"]
			var reach := e.half_width + maxf(e.walk(1), e.walk(-1)) + 0.7
			var d: float = hit["dist"]
			if d < reach:
				var away: Vector2 = p - (hit["pos"] as Vector2)
				if away.length() < 0.01:
					continue
				p = (hit["pos"] as Vector2) + away.normalized() * reach
		if not _inside(p) or _on_road(p, 0.3):
			continue
		var at := terrain.at(p, -0.05)
		var turn := Basis(Vector3.UP, fposmod(p.x * 7.13 + p.y * 3.71, TAU))
		if conifer:
			var sy := clampf(h / 10.5, 0.3, 2.6)
			var sx := clampf(r / 2.4, 0.4, 1.8)
			spruce_xforms[int(absf(p.x * 3.0 + p.y)) % spruce_xforms.size()].append(Transform3D(turn.scaled(Vector3(sx, sy, sx)), at))
		else:
			var vy := clampf(h / 9.0, 0.35, 2.4)
			var vx := clampf(r / 3.4, 0.4, 2.0)
			var b := turn.scaled(Vector3(vx, vy, vx))
			var k := int(absf(p.x * 5.0 + p.y * 3.0))
			trunk_xforms[k % trunk_xforms.size()].append(Transform3D(b, at))
			light_xforms[k % light_xforms.size()].append(Transform3D(b, at + Vector3(0, CROWN_Y * vy, 0)))
		if not lod:
			trunk_spots.append(at)


## One MultiMeshInstance3D per mesh variant that has any instances.
func _multi(root: Node3D, label: String, meshes: Array[ArrayMesh], xforms: Array[Array], shadows: bool) -> void:
	if lod:
		# Far off one shape of each kind is plenty, and it saves draw calls.
		for v in range(1, xforms.size()):
			xforms[0].append_array(xforms[v])
			xforms[v].clear()
	for v in meshes.size():
		var list: Array = xforms[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%d" % [label, v]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not lod else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


## True if p is on a street or its sidewalk (plus `pad` metres), or in a
## junction or on a roundabout island.
func _on_road(p: Vector2, pad: float) -> bool:
	if not net.clear_of_roads(p, pad):
		return true
	for e in net.edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		if RoadNetwork.distance_to_edge(e, p) < e.half_width + maxf(e.walk(1), e.walk(-1)) + pad:
			return true
	return false


func _in_building(p: Vector2, pad: float) -> bool:
	for b in chunk.buildings:
		if _building_box(b).grow(pad).has_point(p) and (pad > 0.0 or Geometry2D.is_point_in_polygon(p, b.ring)):
			return true
	return false


var _boxes: Dictionary = {}


func _building_box(b: StreetData.Building) -> Rect2:
	if not _boxes.has(b):
		var r := Rect2(b.ring[0], Vector2.ZERO)
		for q in b.ring:
			r = r.expand(q)
		_boxes[b] = r
	return _boxes[b]


## Where to plant trees in this chunk: Vector4(x, z, size, 1 for a spruce).
## Woods are filled in on a jittered grid, parks get a few, and residential
## streets get a yard tree behind the sidewalk every so often. Seeded by
## position, so the same trees grow every time.
func _planted() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rect.position)
	var woods: Array[PackedVector2Array] = []
	var parks: Array[PackedVector2Array] = []
	# Downtown's park trees are mapped one by one in OSM; don't add more.
	var downtown := rect.get_center().length() < float(data.config.get("heritage_district_m", 900.0))
	for a in chunk.areas:
		if a.type in ["natural=wood", "landuse=forest"]:
			woods.append(a.ring)
		elif a.type in ["leisure=park", "landuse=cemetery", "landuse=recreation_ground"] and not downtown:
			parks.append(a.ring)
	var wood_step := 9.0 if lod else 7.0
	if not woods.is_empty() or not parks.is_empty():
		for kind: int in [0, 1]:
			var rings: Array[PackedVector2Array] = woods if kind == 0 else parks
			if rings.is_empty():
				continue
			var step := wood_step if kind == 0 else 22.0
			var y := rect.position.y + step * 0.5
			while y < rect.end.y:
				var x := rect.position.x + step * 0.5
				while x < rect.end.x:
					var p := Vector2(x + rng.randf_range(-0.4, 0.4) * step, y + rng.randf_range(-0.4, 0.4) * step)
					var keep := kind == 0 or rng.randf() < 0.45
					if keep and _inside(p):
						for r in rings:
							if Geometry2D.is_point_in_polygon(p, r):
								if not _on_road(p, 2.5) and not _in_building(p, 1.5):
									var spruce := 1.0 if (kind == 0 and rng.randf() < 0.55) else 0.0
									out.append(Vector4(p.x, p.y, rng.randf_range(0.8, 1.3), spruce))
								break
					x += step
				y += step
	# Yard trees along residential streets.
	for e in net.edges_near(rect):
		if e.highway not in ["residential", "living_street", "unclassified", "tertiary"] or e.walk(1) <= 0.0:
			continue
		var d := 9.0 + rng.randf() * 10.0
		while d < e.length - 9.0:
			for side: int in [1, -1]:
				if rng.randf() > 0.45:
					continue
				var sp: Array = RoadNetwork.sample(e.points, d)
				var dir: Vector2 = sp[1]
				var p: Vector2 = (sp[0] as Vector2) + Vector2(-dir.y, dir.x) * float(side) * (e.half_width + e.walk(side) + rng.randf_range(2.5, 6.0))
				if _inside(p) and not _on_road(p, 1.5) and not _in_building(p, 2.0):
					out.append(Vector4(p.x, p.y, rng.randf_range(0.75, 1.2), 1.0 if rng.randf() < 0.2 else 0.0))
			d += rng.randf_range(16.0, 30.0)
	return out


const CROWN_Y := 6.4 ## height of the middle of the crown, metres (before scaling)
const CROWN_R := 3.4 ## rough radius of the crown, for camera fading


## A crown: a cluster of lumpy blobs in a rounded, slightly flattened mass.
## Normals point out from the crown's middle (blended with each blob's own)
## so light falls across it softly; the shade inside the crown is baked into
## the vertex colours.
static func _crown_mesh(variant: int, leaf: Color, mat: Material, blobs: int, rings: int, segs: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var noise := FastNoiseLite.new()
	noise.seed = variant * 31 + 5
	noise.frequency = 0.9
	# Fewer, bigger blobs for the light crowns used in woods and yards.
	var grow := 1.0 if blobs >= 10 else 1.45
	for b in blobs:
		# Spread blobs over the surface of an ellipsoid, a few inside.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1.0), rng.randf_range(-1, 1)).normalized()
		var at := dir * Vector3(2.1, 1.6, 2.1) * rng.randf_range(0.55, 1.0) / sqrt(grow)
		var r := rng.randf_range(1.0, 1.45) * grow
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


## A crown built like a real one: a few main branches climbing out from
## where the trunk's limbs end, each forking into smaller ones, with clumps
## of leaves at their ends and along their outer halves. Each clump is
## three crossed cards from the leaf atlas, so it looks full from any
## angle; the clumps sit near the outside, so the middle stays open and dark
## and sky shows between them. Two surfaces: bark, then leaves.
## Origin at the crown's middle (CROWN_Y up the tree).
static func _branchy_crown(variant: int, leaf: Color, leaves: Material, bark: Material, primaries: int, secondaries: int, grow: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 11)
	var wood := MeshKit.new()
	var kit := MeshKit.new()
	kit.use_color = true
	var radii := Vector3(2.4, 1.9, 2.4) * grow
	var hue := Color(leaf.r, leaf.g, leaf.b) / maxf(0.01, leaf.get_luminance())
	var spots: Array[Vector4] = [] # clump centre and size
	var base_angle := rng.randf() * TAU
	for p in primaries:
		var a := base_angle + TAU * float(p) / float(primaries) + rng.randf_range(-0.4, 0.4)
		var start := Vector3(cos(a) * 0.6, -1.3, sin(a) * 0.6)
		var dir := Vector3(cos(a), rng.randf_range(0.1, 0.9), sin(a)).normalized()
		var end := dir * radii * rng.randf_range(0.7, 0.85)
		_limb(wood, start, end, 0.07 * grow, 0.035 * grow)
		spots.append(Vector4(end.x, end.y, end.z, rng.randf_range(1.1, 1.4)))
		var pm := start.lerp(end, 0.65)
		spots.append(Vector4(pm.x, pm.y, pm.z, rng.randf_range(1.0, 1.3)))
		for k in secondaries:
			var from := start.lerp(end, rng.randf_range(0.45, 0.85))
			var b := a + rng.randf_range(-0.8, 0.8)
			var dir2 := Vector3(cos(b), rng.randf_range(-0.2, 1.0), sin(b)).normalized()
			var tip := dir2 * radii * rng.randf_range(0.85, 1.0)
			_limb(wood, from, tip, 0.035 * grow, 0.015 * grow)
			spots.append(Vector4(tip.x, tip.y, tip.z, rng.randf_range(1.0, 1.3)))
			for f: float in [0.35, 0.7]:
				var mid := from.lerp(tip, f) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.3, 0.3))
				spots.append(Vector4(mid.x, mid.y, mid.z, rng.randf_range(0.9, 1.2)))
	# Some inside, so the middle isn't empty, and a few on top so the crown
	# is rounded, not a ring.
	for k in 5:
		var inner := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.5, 0.5)) * radii
		spots.append(Vector4(inner.x, inner.y, inner.z, rng.randf_range(1.1, 1.4)))
	for k in 5:
		var a := rng.randf() * TAU
		var top := Vector3(cos(a) * 0.8, 0.85, sin(a) * 0.8) * radii
		spots.append(Vector4(top.x, top.y, top.z, rng.randf_range(1.2, 1.5)))
	for sp in spots:
		var c := Vector3(sp.x, sp.y, sp.z)
		var size := sp.w * grow
		var basis := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
		var cell := Vector2(float(rng.randi() % 2), float(rng.randi() % 2)) * 0.5
		var out := c.normalized() if c.length() > 0.01 else Vector3.UP
		# Shade: darker low down and further in; a little hue per clump.
		var lift := clampf((c.y / radii.y + 1.0) * 0.5, 0.0, 1.0)
		var depth := clampf(c.length() / radii.x, 0.0, 1.0)
		var shade := (0.35 + 0.45 * lift + 0.3 * depth) * rng.randf_range(0.9, 1.1)
		kit.color = Color(lerpf(1.0, hue.r, 0.25), lerpf(1.0, hue.g, 0.25), lerpf(1.0, hue.b, 0.25)) * shade
		for axis in 3:
			var u: Vector3 = basis[(axis + 1) % 3] * size * 0.5
			var v: Vector3 = basis[(axis + 2) % 3] * size * 0.5
			var face: Vector3 = basis[axis]
			var corners: Array[Vector3] = [c - u - v, c + u - v, c + u + v, c - u + v]
			var uv: Array[Vector2] = [cell + Vector2(0, 0.5), cell + Vector2(0.5, 0.5), cell + Vector2(0.5, 0), cell]
			var ns: Array[Vector3] = []
			for q in corners:
				ns.append((q.normalized() * 0.7 + out * 0.3).normalized())
			kit.tri_full(corners[0], corners[1], corners[2], face, ns[0], ns[1], ns[2], uv[0], uv[1], uv[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			kit.tri_full(corners[0], corners[2], corners[3], face, ns[0], ns[2], ns[3], uv[0], uv[2], uv[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	for k in kit.colors.size():
		kit.colors[k] = kit.colors[k].srgb_to_linear()
	var mesh := wood.commit(null, bark)
	return kit.commit(mesh, leaves)


## A trunk that forks into a few limbs reaching up into the crown.
static func _trunk_mesh(variant: int, mat: Material, slim := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * (variant + 1)
	var kit := MeshKit.new()
	if slim:
		# A slimmer, slightly leaning trunk with a flare at the root; the
		# crown carries its own branches.
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		_limb(kit, Vector3(0, -0.2, 0), Vector3(0, 0.35, 0), 0.3, 0.19)
		_limb(kit, Vector3(0, 0.35, 0), Vector3(0, 2.4, 0) + lean * 0.5, 0.19, 0.16)
		_limb(kit, Vector3(0, 2.4, 0) + lean * 0.5, Vector3(0, 4.6, 0) + lean, 0.16, 0.11)
		for k in 3:
			var ang := TAU * float(k) / 3.0 + rng.randf() * 0.8
			var tip := Vector3(cos(ang) * rng.randf_range(0.7, 1.1), rng.randf_range(5.0, 5.6), sin(ang) * rng.randf_range(0.7, 1.1))
			_limb(kit, Vector3(0, 3.6, 0) + lean * 0.8, tip, 0.1, 0.06)
		return kit.commit(null, mat)
	_limb(kit, Vector3(0, -0.2, 0), Vector3(rng.randf_range(-0.2, 0.2), 4.2, rng.randf_range(-0.2, 0.2)), 0.26, 0.16)
	var fork := Vector3(0, 3.6, 0)
	for k in 3 + variant % 2:
		var ang := TAU * float(k) / float(3 + variant % 2) + rng.randf() * 0.8
		var tip := Vector3(cos(ang) * rng.randf_range(1.2, 2.0), rng.randf_range(5.6, 6.8), sin(ang) * rng.randf_range(1.2, 2.0))
		_limb(kit, fork, tip, 0.12, 0.05)
	return kit.commit(null, mat)


## A spruce: a short trunk under stacked cones of dark needles, about as
## tall as a leafy street tree.
static func _spruce_mesh(variant: int, needle: Color, leaves: Material, bark: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15485863 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var tiers := 4
	var height := rng.randf_range(9.0, 12.0)
	var segs := 7
	for t in tiers:
		var f := float(t) / float(tiers)
		var y0 := 1.2 + f * (height - 2.0) * 0.82
		var y1 := y0 + (height - 1.2) * 0.42
		var r := (1.0 - f * 0.78) * rng.randf_range(2.2, 2.7)
		var tint := needle * rng.randf_range(0.9, 1.1)
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var c0 := Vector3(cos(a0), 0.0, sin(a0))
			var c1 := Vector3(cos(a1), 0.0, sin(a1))
			var n0 := (c0 * 0.8 + Vector3.UP * 0.6).normalized()
			var n1 := (c1 * 0.8 + Vector3.UP * 0.6).normalized()
			kit.color = (tint * 0.7).srgb_to_linear()
			var top := Vector3(0, y1, 0)
			var b0 := c0 * r + Vector3(0, y0, 0)
			var b1 := c1 * r + Vector3(0, y0, 0)
			kit.tri_full(b0, b1, top, (c0 + c1).normalized() + Vector3.UP * 0.5, n0, n1, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			kit.color = (tint * 0.35).srgb_to_linear()
			kit.tri(b0, b1, Vector3(0, y0 + 0.3, 0), Vector3.DOWN)
	var mesh := kit.commit(null, leaves)
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.2, 0), Vector3(0, 2.0, 0), 0.2, 0.14)
	wood.commit(mesh, bark)
	return mesh


## A spruce built from its branches: whorls of drooping branch cards up a
## tapering trunk, long at the bottom and short at the top, each branch two
## crossed cards of the needle-branch texture so it has thickness from any
## side. Inner ends are shaded darker, as the inside of a spruce is.
static func _card_spruce(variant: int, needle: Color, mat: Material, bark: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15485863 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var height := rng.randf_range(9.0, 12.0)
	var base := 0.9
	var step := 0.5
	var whorls := int((height - base - 0.6) / step)
	var hue := Color(needle.r, needle.g, needle.b) / maxf(0.01, needle.get_luminance())
	var tint := Color(lerpf(1.0, hue.r, 0.2), lerpf(1.0, hue.g, 0.2), lerpf(1.0, hue.b, 0.2))
	for w in whorls:
		var f := float(w) / float(whorls)
		var y := base + w * step + rng.randf_range(-0.1, 0.1)
		var count := 5 if f < 0.7 else 4
		var spin := rng.randf() * TAU
		for k in count:
			var a := spin + TAU * float(k) / float(count) + rng.randf_range(-0.25, 0.25)
			var length := (1.0 - f) * rng.randf_range(2.4, 2.9) + 0.45
			var dir := Vector3(cos(a), -0.18 - 0.12 * (1.0 - f), sin(a)).normalized()
			var side := Vector3(-sin(a), 0.0, cos(a))
			var root := Vector3(0, y, 0)
			var tip := root + dir * length
			var half := length * 0.28
			var shade_in := 0.35 + 0.25 * f
			for c in 2:
				# One card lying flat, one tilted up along the branch.
				var wv := side * half if c == 0 else (side * 0.5 + Vector3.UP * 0.86).normalized() * half * 0.8
				var corners: Array[Vector3] = [root - wv, tip - wv, tip + wv, root + wv]
				var uv: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
				var face := dir.cross(wv).normalized()
				if face.y < 0.0:
					face = -face
				var ns: Array[Vector3] = []
				for q in corners:
					var o := Vector3(q.x, 0.0, q.z)
					ns.append((o.normalized() * 0.8 + Vector3.UP * 0.5).normalized() if o.length() > 0.05 else Vector3.UP)
				var cols: Array[Color] = []
				for q in 4:
					var outer := q == 1 or q == 2
					cols.append((tint * (1.0 if outer else shade_in) * rng.randf_range(0.92, 1.05)).srgb_to_linear())
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					kit.color = cols[tri[0]]
					var i0: int = tri[0]
					var i1: int = tri[1]
					var i2: int = tri[2]
					kit.tri_full(corners[i0], corners[i1], corners[i2], face, ns[i0], ns[i1], ns[i2], uv[i0], uv[i1], uv[i2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					# Per-corner shade: patch the colours just added.
					# (tri_full may have swapped the last two to fix the winding.)
					var n := kit.colors.size()
					for m in range(n - 3, n):
						for q: int in [i0, i1, i2]:
							if kit.verts[m] == corners[q]:
								kit.colors[m] = cols[q]
	# The leader at the very top: two crossed upright cards.
	var top := Vector3(0, height - 0.9, 0)
	for c in 2:
		var wv := (Vector3.RIGHT if c == 0 else Vector3.BACK) * 0.35
		var tipv := top + Vector3.UP * 1.3
		kit.color = tint.srgb_to_linear()
		kit.quad(top - wv, top + wv, tipv + wv, tipv - wv, Vector3.BACK if c == 0 else Vector3.RIGHT,
			Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	var mesh := kit.commit(null, mat)
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.2, 0), Vector3(0, height * 0.75, 0), 0.22, 0.05)
	wood.commit(mesh, bark)
	return mesh


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
const STREET_LIGHT_SPACING := 40.0

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
static func _lamp_mesh(mats: Materials) -> ArrayMesh:
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
	var mesh := iron.commit(null, mats.plain(Color(0.06, 0.065, 0.065), 0.4, 0.5))
	glass.commit(mesh, mats.glow(Color(1.0, 0.88, 0.66), 0.7))
	return mesh


## An ordinary street light: a creosoted wooden pole with a grey arm
## reaching out over the road and a cobra-head lamp on the end. Local +X
## points at the road.
static func _street_light_mesh(mats: Materials) -> ArrayMesh:
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.3, 0), Vector3(0, 8.6, 0), 0.15, 0.11)
	var metal := MeshKit.new()
	_limb(metal, Vector3(0.0, 7.6, 0), Vector3(1.4, 8.15, 0), 0.04, 0.035)
	_limb(metal, Vector3(1.4, 8.15, 0), Vector3(2.3, 8.2, 0), 0.035, 0.035)
	# The head: a shallow rounded box.
	var hx := 2.75
	var head := [Vector3(hx - 0.45, 8.12, -0.17), Vector3(hx + 0.4, 8.12, -0.15), Vector3(hx + 0.4, 8.12, 0.15), Vector3(hx - 0.45, 8.12, 0.17)]
	var top := [Vector3(hx - 0.45, 8.3, -0.14), Vector3(hx + 0.35, 8.24, -0.12), Vector3(hx + 0.35, 8.24, 0.12), Vector3(hx - 0.45, 8.3, 0.14)]
	for k in 4:
		var a: Vector3 = head[k]
		var b: Vector3 = head[(k + 1) % 4]
		var c: Vector3 = top[(k + 1) % 4]
		var d: Vector3 = top[k]
		var out := ((a + b) * 0.5 - Vector3(hx, 8.12, 0)).normalized()
		metal.quad(a, b, c, d, out)
	metal.quad(top[0], top[1], top[2], top[3], Vector3.UP)
	var glass := MeshKit.new()
	glass.quad(head[0] + Vector3(0.08, -0.02, 0.03), head[1] + Vector3(-0.08, -0.02, 0.03), head[2] + Vector3(-0.08, -0.02, -0.03), head[3] + Vector3(0.08, -0.02, -0.03), Vector3.DOWN)
	var mesh := wood.commit(null, mats.plain(Color(0.27, 0.21, 0.16), 0.95))
	metal.commit(mesh, mats.plain(Color(0.55, 0.57, 0.58), 0.45, 0.6))
	glass.commit(mesh, mats.glow(Color(1.0, 0.9, 0.72), 0.5))
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


## Lamps along the streets, kept clear of the junctions. Downtown (within
## "heritage_district_m" of the origin in map_config.json) gets black
## cast-iron lamp posts on both sides every LAMP_SPACING metres; elsewhere a
## street light on a wooden pole every STREET_LIGHT_SPACING metres, on
## alternating sides. Highways have none. Each kind is one MultiMesh per
## chunk, with one static body for their collision.
func _lamps(root: Node3D) -> void:
	var heritage_r := float(data.config.get("heritage_district_m", 900.0))
	var spots: Array[Vector2] = []
	var lights: Array[Transform3D] = []
	for e in net.edges_near(rect):
		if e.is_highway() or e.walk(1) + e.walk(-1) <= 1.2:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 6.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 6.0
		if stop - start < 4.0:
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		var heritage := mid.length() < heritage_r
		for side: int in [1, -1]:
			if e.walk(side) < 1.0:
				continue
			var line := net.side_line(e, side, RoadNetwork.Level.PROP)
			var line_len := RoadNetwork.polyline_length(line)
			var scale := line_len / e.length
			if heritage:
				var d := start + (LAMP_SPACING * 0.5 if side < 0 else 0.0)
				while d < stop:
					var sp: Array = RoadNetwork.sample(line, d * scale)
					if _inside(sp[0]) and net.clear_of_roads(sp[0], 0.2):
						spots.append(sp[0])
					d += LAMP_SPACING
			else:
				var d2 := start + (STREET_LIGHT_SPACING * 0.5 if side < 0 else 0.0)
				while d2 < stop:
					var sp2: Array = RoadNetwork.sample(line, d2 * scale)
					var at: Vector2 = sp2[0]
					if _inside(at) and net.clear_of_roads(at, 0.2):
						var dir: Vector2 = sp2[1]
						var to_road := -Vector2(-dir.y, dir.x) * float(side)
						lights.append(Transform3D(Basis(Vector3.UP, StreetProps.yaw_along(to_road)), terrain.at(at, SW_H)))
					d2 += STREET_LIGHT_SPACING * 2.0
	if spots.is_empty() and lights.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "LampPosts"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	if not spots.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _heritage_lamp
		mm.instance_count = spots.size()
		for i in spots.size():
			var turn := Basis(Vector3.UP, float(i % 6) * 0.17)
			mm.set_instance_transform(i, Transform3D(turn, terrain.at(spots[i], SW_H)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lamps"
		mmi.multimesh = mm
		root.add_child(mmi)
		for p in spots:
			var cs := CollisionShape3D.new()
			cs.shape = _lamp_shape
			cs.position = terrain.at(p, SW_H + 2.0)
			body.add_child(cs)
	if not lights.is_empty():
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = _street_light
		mm2.instance_count = lights.size()
		for i in lights.size():
			mm2.set_instance_transform(i, lights[i])
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.name = "StreetLights"
		mmi2.multimesh = mm2
		root.add_child(mmi2)
		for t in lights:
			var cs2 := CollisionShape3D.new()
			cs2.shape = _pole_shape
			cs2.position = t.origin + Vector3(0, 4.0, 0)
			body.add_child(cs2)
	root.add_child(body)

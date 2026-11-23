class_name WorldBuilder
extends Node3D
## Builds the town from data/map_config.json.
##
## At startup (spread over frames, see build()): load the map data -> street graph -> elevation -> the
## play-area ring and its invisible wall -> the ground, water and safety floor
## for the whole map -> the chunks round the spawn point. After that the
## ChunkStreamer builds and drops chunks round the player as they move.
## Other systems (player spawn, minimap, NPCs, missions) read `data`,
## `network`, `terrain` and `play_area` from here once `built` has fired.

signal built

## Height of the open lots between streets (just under the sidewalks' back edge).
const GROUND_Y := -0.06
## Chunks within this distance of the spawn are built before the game starts.
const PRIME_RADIUS := 150.0

@export_file("*.json") var config_path := "res://data/map_config.json"

var data: StreetData
var network: RoadNetwork
## The real shape of the ground (heights in metres above sea level).
var terrain: Terrain
var streamer: ChunkStreamer
## The playable area: the bypass ring and the shore, in order round the edge.
var play_area := PackedVector2Array()
## The invisible wall line, margin_m outside play_area.
var boundary := PackedVector2Array()
var is_built := false


func _ready() -> void:
	build()


## What the town is being built from right now, for the loading screen.
var loading_step := "Starting"


## Builds the town a step at a time, letting a frame through between steps
## so the window (and in a browser, the page) never stops responding.
## Fires `built` when the streets round the spawn are ready.
func build() -> void:
	var t0 := Time.get_ticks_msec()
	loading_step = "Reading the map"
	await _breathe()
	data = StreetData.load_from(config_path)
	if data.roads.is_empty():
		push_error("WorldBuilder: no roads loaded from %s. See data/README.md." % config_path)
		return
	loading_step = "Joining up the streets"
	await _breathe()
	network = RoadNetwork.new(data)
	await _breathe()
	RoadMesher.find_brick_edges(network, data)
	var t_data := Time.get_ticks_msec()
	loading_step = "Laying out the ground"
	await _breathe()
	terrain = Terrain.load_from(str(data.config.get("elevation", "res://data/elevation.json")))
	loading_step = "Finding the bypass"
	await _breathe()
	_find_play_area()
	var t_ground := Time.get_ticks_msec()
	await _breathe()

	# Shared things the chunk builders use, made here on the main thread
	# before any worker thread starts.
	Materials.get_shared()
	Terrain.ground_shader()
	StreetProps.prepare()
	ChunkBuilder.coarse_mask = load(str(data.config.get("ground_mask", "res://data/ground_mask.png"))) as Texture2D
	await _breathe()

	if terrain.is_flat():
		add_child(_ground())
	else:
		add_child(terrain.build_global(ChunkBuilder.coarse_mask))
	await _breathe()
	add_child(_boundary())
	loading_step = "Building downtown"
	await _breathe()
	for c: Dictionary in data.config.get("parked_cars", []):
		var at := get_car_spawn(c).origin
		data.keep_clear.append(Vector2(at.x, at.z))
	streamer = ChunkStreamer.new()
	streamer.name = "Chunks"
	streamer.setup(data, network, terrain)
	add_child(streamer)
	var spawn := get_spawn().origin
	await streamer.prime(Vector2(spawn.x, spawn.z), PRIME_RADIUS)

	is_built = true
	loading_step = "Ready"
	print("WorldBuilder: %d street segments, %d junctions, %d chunks of map data; %d chunks built round the spawn in %d ms (data %d ms, elevation and ring %d ms). Map data %s." % [
		network.edges.size(), network.nodes.size(), data.chunk_keys.size(), streamer.near_count(),
		Time.get_ticks_msec() - t0, t_data - t0, t_ground - t_data,
		str(data.metadata.get("attribution", "")),
	])
	built.emit()


func _breathe() -> void:
	await get_tree().process_frame


## Waits (over frames) until the chunks round the camera have all loaded.
## For screenshots and tests; the game itself never waits.
func wait_until_settled(max_seconds := 60.0) -> void:
	var t := 0.0
	streamer.refresh()
	while not streamer.is_settled() and t < max_seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
	# Let the last chunks draw once.
	await get_tree().process_frame


# --- play area ----------------------------------------------------------------------

## The play area follows the ring roads and the shore. map_config.json lists
## the way round in order: junctions named by two streets (the edge follows
## the shortest way between them along the streets named in "follow"), and
## points out in the water (latitude, longitude) where the shore closes it.
func _find_play_area() -> void:
	var cfg: Dictionary = data.config.get("play_area", {})
	var follow: Array = cfg.get("follow", [])
	var ring: Array = cfg.get("ring", [])
	var prev_junction := ""
	for item: Dictionary in ring:
		if item.has("streets"):
			var pair: Array = item["streets"]
			var nid := network.find_junction(str(pair[0]), str(pair[1]))
			if nid == "":
				push_error("WorldBuilder: no junction of %s and %s in the data." % [pair[0], pair[1]])
				continue
			if prev_junction != "":
				var path := network.route(prev_junction, nid, follow)
				if path.is_empty():
					push_warning("WorldBuilder: no way along %s to the junction of %s and %s." % [str(follow), pair[0], pair[1]])
				play_area.append_array(path)
			play_area.append(network.nodes[nid])
			prev_junction = nid
		elif item.has("water"):
			var ll: Array = item["water"]
			play_area.append(data.projection.to_ground(float(ll[1]), float(ll[0])))
			prev_junction = ""
	play_area = _dedupe(play_area)
	if play_area.size() < 3:
		push_warning("WorldBuilder: play area corners missing, using the whole map.")
		var first_node: Vector2 = network.nodes.values()[0]
		var r := Rect2(first_node, Vector2.ZERO)
		for p: Vector2 in network.nodes.values():
			r = r.expand(p)
		play_area = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var margin := float(cfg.get("margin_m", 30.0))
	boundary = _grow(play_area, margin)


static func _dedupe(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.5:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.5:
		out.remove_at(out.size() - 1)
	return out


## Push the edge of a polygon `by` metres outward (whichever way round its
## points are listed), with rounded corners, then thin out the points.
static func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	# offset_polygon grows counter-clockwise polygons (in its own sense) and
	# shrinks clockwise ones, so try both and keep the bigger.
	var best := poly
	var best_area := absf(_area(poly))
	for d: float in [by, -by]:
		for out: PackedVector2Array in Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND):
			var a := absf(_area(out))
			if a > best_area:
				best_area = a
				best = out
	# Fewer, longer wall pieces: drop points closer than 8 m to the last kept.
	var thin := PackedVector2Array()
	for p in best:
		if thin.is_empty() or thin[thin.size() - 1].distance_to(p) > 8.0:
			thin.append(p)
	return thin


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func play_area_center() -> Vector2:
	var c := Vector2.ZERO
	for p in play_area:
		c += p
	return c / maxf(1.0, play_area.size())


## Inside the invisible wall.
func is_in_play_area(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, boundary)


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
	# Face the junction named in "face_toward" (or the middle of the play area).
	var target := play_area_center()
	var face: Array = s.get("face_toward", [])
	if face.size() >= 2:
		var fid := network.find_junction(str(face[0]), str(face[1]))
		if fid != "":
			target = network.nodes[fid]
	var to_center := target - pos
	var yaw := atan2(-to_center.x, -to_center.y)
	return Transform3D(Basis(Vector3.UP, yaw), terrain.at(pos, RoadNetwork.SIDEWALK_HEIGHT + 0.05))


## Where a parked car starts: against the right-hand curb of the street
## named in its config entry, a set distance from a junction.
func get_car_spawn(c: Dictionary) -> Transform3D:
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
		return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), terrain.at(pos, 0.05))
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

## Flat ground, only used if data/elevation.json is missing.
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
	var box := Rect2(boundary[0], Vector2.ZERO)
	for p in boundary:
		box = box.expand(p)
	for e in network.edges:
		if box.encloses(e.bounds) and Geometry2D.is_point_in_polygon(e.points[0], boundary) and Geometry2D.is_point_in_polygon(e.points[e.points.size() - 1], boundary):
			continue
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
	holder.position = terrain.at(at)
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

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
## The map editor's edits were saved and the town was rebuilt with them.
signal edits_reloaded(ms: int)
## The map editor's "Test here" spot was set while the game was running.
signal test_spot_moved(spot: Dictionary)

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
	# The map data and the street network on a worker (some 300 ms and
	# 700 ms), the loading screen drawing meanwhile, as reload_edits does.
	var path := config_path
	var got := {}
	await _on_worker(func() -> void: got["data"] = StreetData.load_from(path), "read the map")
	data = got["data"]
	if data.roads.is_empty():
		push_error("WorldBuilder: no roads loaded from %s. See data/README.md." % config_path)
		return
	loading_step = "Joining up the streets"
	var d0 := data
	await _on_worker(func() -> void:
		var n := RoadNetwork.new(d0)
		RoadMesher.prepare(n, d0)
		got["net"] = n, "join the streets")
	network = got["net"]
	var t_data := Time.get_ticks_msec()
	loading_step = "Laying out the ground"
	await _breathe()
	# The shipped game loads the ground already shaped (GroundCache, made by
	# tools/bake_ground.gd) when it's for this map data; run from the editor
	# it's always worked out, since live edits re-shape it (`-- --baked-ground`
	# uses it anyway, to try it).
	var baked := not _watch or OS.get_cmdline_user_args().has("--baked-ground")
	var ground_key := GroundCache.key(data) if baked else ""
	var cached := ground_key != "" and GroundCache.has(ground_key)
	terrain = Terrain.load_from(str(data.config.get("elevation", "res://data/elevation.json")), not cached)
	if cached and not GroundCache.apply(terrain, network, ground_key):
		# Unreadable after all: shape it the slow way.
		cached = false
		terrain = Terrain.load_from(str(data.config.get("elevation", "res://data/elevation.json")))
	if _watch:
		terrain.keep_raw()
	if not cached:
		RoadMesher.seat_bridges(network, terrain)
		loading_step = "Smoothing the streets"
		await _breathe()
		await _smooth_streets(network, terrain)
	_flatten_garages(network, terrain, data)
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
	for c: Dictionary in car_starts() + yard_starts():
		var at: Vector3 = (c["xform"] as Transform3D).origin
		data.keep_clear.append(Vector2(at.x, at.z))
	var monuments := Monuments.new()
	monuments.name = "Monuments"
	add_child(monuments)
	monuments.setup(data, terrain)
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
	_edits_md5 = _md5(str(data.config.get("edits", "")))
	_test_md5 = _md5(TEST_START)
	built.emit()


# --- live edits ----------------------------------------------------------------------------
# Run from Godot, the game watches data/edits.json and data/test_start.json.
# When the map editor saves, the town is rebuilt round the player with the
# new edits (a second or two, no restart); when it sets a test spot, the
# player is moved there.

const TEST_START := "res://data/test_start.json"
const WATCH_EVERY := 0.7
var _watch := OS.has_feature("editor")
var _watch_timer := 0.0
var _edits_md5 := ""
var _test_md5 := ""
var _reloading := false


static func _md5(path: String) -> String:
	return FileAccess.get_md5(path) if path != "" and FileAccess.file_exists(path) else ""


func _process(delta: float) -> void:
	if not _watch or not is_built or _reloading:
		return
	_watch_timer += delta
	if _watch_timer < WATCH_EVERY:
		return
	_watch_timer = 0.0
	var m := _md5(str(data.config.get("edits", "")))
	if m != _edits_md5:
		_edits_md5 = m
		reload_edits()
		return
	var t := _md5(TEST_START)
	if t != _test_md5:
		_test_md5 = t
		_test_start = null
		var spot := test_start()
		if not spot.is_empty():
			test_spot_moved.emit(spot)


## Reads the map data and edits again and rebuilds just the chunks the
## changes touch. The data and street network are made on a worker thread;
## each changed chunk is rebuilt beside the one showing and swapped in when
## it's ready, so nothing disappears.
func reload_edits() -> void:
	if _reloading:
		return
	_reloading = true
	var t0 := Time.get_ticks_msec()
	var result := {}
	var path := config_path
	var old_terrain := terrain
	# The ground as it was loaded, fixed up again for the new streets (bridge
	# ends filled, streets smoothed) on a copy, then swapped in whole, so a
	# chunk being built meanwhile never sees it half done. All but the garages
	# and the swap on workers: the game carries on meanwhile.
	await _on_worker(func() -> void:
		var d := StreetData.load_from(path)
		if d.roads.is_empty():
			return
		var n := RoadNetwork.new(d)
		RoadMesher.prepare(n, d)
		var fresh := old_terrain.raw_copy()
		if fresh != null:
			RoadMesher.seat_bridges(n, fresh)
		result["fresh"] = fresh
		result["data"] = d
		result["net"] = n, "reload the map")
	if not result.has("data"):
		push_warning("WorldBuilder: couldn't read the map again; keeping the old one")
		_reloading = false
		return
	var d: StreetData = result["data"]
	var n: RoadNetwork = result["net"]
	var fresh: Terrain = result["fresh"]
	if fresh != null:
		await _smooth_streets(n, fresh)
		_flatten_garages(n, fresh, d) # on the main thread: it resets Parkade's list the chunk builders read
		terrain.take_heights(fresh)
	else:
		RoadMesher.seat_bridges(n, terrain)
	d.keep_clear = data.keep_clear
	d.feature_chunks = data.feature_chunks_copy()
	var cells := _changed_cells(data, d)
	data = d
	network = n
	streamer.replace_data(d, n, cells)
	while streamer.redo_pending() > 0:
		await get_tree().process_frame
	_reloading = false
	var ms := Time.get_ticks_msec() - t0
	print("WorldBuilder: map edits reloaded in %d ms (%d chunks changed)" % [ms, cells.size()])
	edits_reloaded.emit(ms)


## The chunks a change of edits (old data to new) touches: round every
## street point, outline, prop, line, tree and erased spot that differs.
## Streets reach 40 m past their points (junction boxes, curbs, the props
## along them); everything else 8 m.
func _changed_cells(old: StreetData, new: StreetData) -> Dictionary:
	var cells := {}
	var a: Dictionary = old.edits
	var b: Dictionary = new.edits
	var old_roads := {}
	for r in old.roads:
		old_roads[r.id] = r
	var new_roads := {}
	for r in new.roads:
		new_roads[r.id] = r
	var mark := func(p: Vector2, pad: float) -> void:
		var size := new.chunk_size
		for cx in range(floori((p.x - pad) / size), floori((p.x + pad) / size) + 1):
			for cz in range(floori((p.y - pad) / size), floori((p.y + pad) / size) + 1):
				cells[Vector2i(cx, cz)] = true
	var mark_road := func(id: String) -> void:
		for roads: Dictionary in [old_roads, new_roads]:
			if roads.has(id):
				for p in (roads[id] as StreetData.Road).points:
					mark.call(p, 40.0)
	var mark_ll := func(c: Variant, pad: float) -> void:
		if c is Array and (c as Array).size() >= 2 and not (c[0] is Array):
			mark.call(new.projection.to_ground(float(c[0]), float(c[1])), pad)
		elif c is Array:
			for q: Variant in c:
				if q is Array and (q as Array).size() >= 2:
					mark.call(new.projection.to_ground(float(q[0]), float(q[1])), pad)
	# Moved street points: every street through them, before and after.
	var na: Dictionary = a.get("nodes", {})
	var nb: Dictionary = b.get("nodes", {})
	for nid: String in _keys_differing(na, nb):
		for roads: Dictionary in [old_roads, new_roads]:
			for r: StreetData.Road in roads.values():
				if r.nodes.has(nid):
					mark_road.call(r.id)
	for id: String in _keys_differing(a.get("roads", {}), b.get("roads", {})):
		mark_road.call(id)
	for id: String in _keys_differing(_by_id(a.get("new_roads", [])), _by_id(b.get("new_roads", []))):
		mark_road.call(id)
	# Buildings, areas and points: where they were loaded, and any new shape.
	var fa: Dictionary = a.get("features", {})
	var fb: Dictionary = b.get("features", {})
	for key: String in _keys_differing(fa, fb):
		for ck: Variant in old.feature_chunks.get(key, []):
			var xz := str(ck).split("_")
			cells[Vector2i(int(xz[0]), int(xz[1]))] = true
		for p in old.points:
			if "point:" + p.id == key:
				mark.call(p.pos, 30.0)
		for e: Variant in [fa.get(key), fb.get(key)]:
			if e is Dictionary:
				mark_ll.call((e as Dictionary).get("ring", (e as Dictionary).get("pos")), 8.0)
	var xa := _by_id(a.get("new_features", []))
	var xb := _by_id(b.get("new_features", []))
	for id: String in _keys_differing(xa, xb):
		for e: Variant in [xa.get(id), xb.get(id)]:
			if e is Dictionary:
				var pad := 30.0 if str((e as Dictionary).get("tags", {}).get("type", "")).begins_with("highway=") else 8.0
				mark_ll.call((e as Dictionary).get("ring", (e as Dictionary).get("pos")), pad)
	var la := _by_id(a.get("lines", []))
	var lb := _by_id(b.get("lines", []))
	for id: String in _keys_differing(la, lb):
		for e: Variant in [la.get(id), lb.get(id)]:
			if e is Dictionary:
				mark_ll.call((e as Dictionary).get("pts"), 8.0)
	# Trees and erased spots: anything in one list and not the other.
	for list_key: String in ["removed_trees", "erased_props"]:
		var ta: Array = a.get(list_key, [])
		var tb: Array = b.get(list_key, [])
		for t: Variant in ta + tb:
			if (t in ta) != (t in tb) and t is Array:
				mark.call(Vector2(float(t[0]), float(t[1])), 8.0)
	return cells


static func _by_id(list: Variant) -> Dictionary:
	var out := {}
	if list is Array:
		for e: Variant in list:
			if e is Dictionary:
				out[str((e as Dictionary).get("id", ""))] = e
	return out


## Keys whose entries differ between two dictionaries (added, removed or changed).
static func _keys_differing(x: Variant, y: Variant) -> Array[String]:
	var a: Dictionary = x if x is Dictionary else {}
	var b: Dictionary = y if y is Dictionary else {}
	var out: Array[String] = []
	for k: Variant in a:
		if not b.has(k) or b[k] != a[k]:
			out.append(str(k))
	for k: Variant in b:
		if not a.has(k):
			out.append(str(k))
	return out


## A spot from the map editor as a transform `lift` metres above the ground.
## RoadMesher.smooth_streets on a worker thread (a few seconds for the whole
## city), letting frames through meanwhile.
## Then the ground under the parkades is lowered below their ground floors.
func _smooth_streets(net: RoadNetwork, t: Terrain) -> void:
	var task := WorkerThreadPool.add_task(RoadMesher.smooth_streets.bind(net, t), false, "smooth streets")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)


## Parking dug into the ground. Not in GroundCache: it also clears props
## and keeps spots clear in the map data, and it's quick.
static func _flatten_garages(net: RoadNetwork, t: Terrain, d: StreetData) -> void:
	Parkade.flatten(d, net, t)
	UndergroundGarage.flatten(d, t)


func edit_xform(spot: Dictionary, lift: float) -> Transform3D:
	return _edit_xform(spot, lift)


func _breathe() -> void:
	await get_tree().process_frame


## Runs `job` on a worker thread, letting frames through until it's done.
func _on_worker(job: Callable, what: String) -> void:
	var task := WorkerThreadPool.add_task(job, false, what)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)


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


## The map editor's "Test here" spot (data/test_start.json, never
## committed), or {} when there isn't one.
func test_start() -> Dictionary:
	if _test_start == null:
		_test_start = {}
		var path := "res://data/test_start.json"
		if FileAccess.file_exists(path):
			var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if t is Dictionary and (t as Dictionary).has("pos"):
				_test_start = t
				print("WorldBuilder: starting at the map editor's test spot (delete data/test_start.json to start normally)")
	return _test_start

var _test_start: Variant = null


## A spot from the map editor ({"pos": [lon, lat], "direction": compass
## degrees}) as a transform `lift` metres above the ground.
func _edit_xform(d: Dictionary, lift: float) -> Transform3D:
	var c: Array = d["pos"]
	var g := data.projection.to_ground(float(c[0]), float(c[1]))
	var yaw := -deg_to_rad(float(d.get("direction", 0.0)))
	return Transform3D(Basis(Vector3.UP, yaw), terrain.at(g, lift))


## Where the player starts: the map editor's test spot, else home (a
## property you own, made home: Properties), else the editor's start spot
## (edits.json "spawn"), else the config's (a parkade's aisle, or the
## sidewalk at the junction named).
func get_spawn() -> Transform3D:
	var t := test_start()
	if not t.is_empty():
		var x := _edit_xform(t, 0.6)
		if bool(t.get("car", false)):
			# Beside the test car, on the driver's side.
			x.origin += x.basis.x * -2.6
		return x
	# Home, if you've made a place yours (Properties).
	var home := Properties.home_spawn(self)
	if not home.is_empty():
		return home["xform"]
	var es: Variant = data.edits.get("spawn")
	if es is Dictionary and (es as Dictionary).has("pos"):
		return _edit_xform(es, 0.6)
	var s: Dictionary = data.config.get("spawn", {})
	if s.has("parkade"):
		var lay := Parkade.find(data, network, terrain, str(s["parkade"]))
		if not lay.is_empty():
			return Parkade.aisle_xform(lay, int(s.get("level", 0)), int(s.get("side", 1)), int(s.get("stall", 0)))
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


## The player's cars at the start, each {"model", "colour", "xform"}: the
## ones placed in the map editor (edits.json "player_cars") if there are
## any, else map_config.json "parked_cars"; plus a car at the test spot
## when the editor's test start asks for one.
func car_starts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var placed: Array = data.edits.get("player_cars", [])
	if not placed.is_empty():
		for c: Variant in placed:
			if c is Dictionary and (c as Dictionary).has("pos"):
				out.append({"model": str(c.get("model", "civique")), "colour": str(c.get("colour", "")), "xform": _edit_xform(c, 0.35)})
	else:
		for c: Dictionary in data.config.get("parked_cars", []):
			out.append({"model": str(c.get("model", "civique")), "colour": str(c.get("colour", "")), "xform": get_car_spawn(c)})
	# Fleets (the police) keep their own spots, whatever else is placed.
	for c: Dictionary in data.config.get("fleet_cars", []):
		if c.has("pos"):
			out.append({"model": str(c.get("model", "civique")), "colour": str(c.get("colour", "")), "livery": str(c.get("livery", "")),
				"unit": int(c.get("unit", 0)), "xform": _edit_xform(c, 0.35)})
	var t := test_start()
	if bool(t.get("car", false)):
		out.append({"model": str(t.get("model", "civique")), "colour": "", "xform": _edit_xform(t, 0.35)})
	return out


## The truck yard (map_config.json "work_yard"): its vehicles, each
## {"model", "colour", "xform"}, and its loads, each {"cargo", "xform"}.
## Places in the yard are in metres from its middle: x to the right and z
## back, facing the yard's "direction"; "heading" turns a thing from there
## (degrees clockwise) and "lift" raises it (a load on a trailer's deck).
func yard_starts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var y: Variant = data.config.get("work_yard")
	if not (y is Dictionary) or not (y as Dictionary).has("pos"):
		return out
	var base := _edit_xform(y, 0.0)
	for v: Dictionary in y.get("vehicles", []):
		out.append({"model": str(v.get("model", "civique")), "colour": str(v.get("colour", "")), "xform": _yard_xform(base, v, 0.05)})
	for c: Dictionary in y.get("loads", []):
		out.append({"cargo": str(c.get("kind", "pallet_boxes")), "xform": _yard_xform(base, c, 0.05)})
	return out


func _yard_xform(base: Transform3D, d: Dictionary, lift: float) -> Transform3D:
	var at: Array = d.get("at", [0.0, 0.0])
	var p := base * Vector3(float(at[0]), 0.0, float(at[1]))
	var yaw := base.basis.get_euler().y - deg_to_rad(float(d.get("heading", 0.0)))
	return Transform3D(Basis(Vector3.UP, yaw), terrain.at(Vector2(p.x, p.z), lift + float(d.get("lift", 0.0))))


## Where a parked car starts: against the right-hand curb of the street
## named in its config entry, a set distance from a junction.
func get_car_spawn(c: Dictionary) -> Transform3D:
	if c.has("parkade"):
		var lay := Parkade.find(data, network, terrain, str(c["parkade"]))
		if not lay.is_empty():
			return Parkade.stall_xform(lay, int(c.get("level", 0)), int(c.get("side", 1)), int(c.get("stall", 0)))
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

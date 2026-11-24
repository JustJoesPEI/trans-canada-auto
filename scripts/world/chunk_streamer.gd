class_name ChunkStreamer
extends Node3D
## Keeps the town built round the player, a square chunk at a time.
##
## Chunks within Graphics.detail_radius() of the camera are built in full
## detail (with collision); chunks out to Graphics.distant_radius() in low
## detail. Full chunks within Graphics.facade_radius() also get close-up
## building facades: a second building mesh built on a worker and swapped
## in for the plain one, and swapped back when the player moves off. A chunk's full version replaces its low one when it's ready, and
## the low one comes back when the player moves away. Building happens on
## worker threads (ChunkBuilder), nearest chunks first, and finished chunks
## join the scene a few per frame, so there's no long wait or stutter.
##
## The camera is the focus (so screenshots and the driving camera both
## work), checked a few times a second.

## Extra distance before a chunk is dropped, so chunks don't flicker in and
## out at the edge.
const KEEP_EXTRA := 90.0
const CHECK_EVERY := 0.2
## Most chunk builds running at once, and most finished chunks added per frame.
const MAX_JOBS := 3
const ATTACH_PER_FRAME := 2
const DROP_PER_CHECK := 2
## Extra distance before close-up facades are swapped back out.
const FACADE_EXTRA := 40.0

var data: StreetData
var net: RoadNetwork
var terrain: Terrain
## Chunk grid bounds (inclusive), from the elevation survey.
var c_min := Vector2i.ZERO
var c_max := Vector2i.ZERO

var _near: Dictionary = {} ## Vector2i -> Node3D (full detail, in the scene)
var _far: Dictionary = {} ## Vector2i -> Node3D (low detail, in the scene)
var _facade: Dictionary = {} ## Vector2i -> true (close-up buildings swapped in)
var _jobs: Dictionary = {} ## [Vector2i, lod] key string -> task id
var _done: Array = [] ## [cell, lod, node] waiting to be added
var _mutex := Mutex.new()
var _timer := 0.0
var _focus := Vector2.ZERO
var _has_focus := false
## Live edits: each replace_data() is a new generation; a chunk changed by
## it must be built from that generation's data or later.
var _gen := 0
var _cell_gen: Dictionary = {} ## Vector2i -> generation it must be built from
var _redo: Dictionary = {} ## [cell, lod] key -> task id (rebuilds of shown chunks)


func setup(street_data: StreetData, network: RoadNetwork, ground: Terrain) -> void:
	data = street_data
	net = network
	terrain = ground
	var size := data.chunk_size
	var lo := terrain.origin
	var hi := terrain.origin + Vector2((terrain.nx - 1) * terrain.spacing, (terrain.nz - 1) * terrain.spacing)
	c_min = Vector2i(floori(lo.x / size), floori(lo.y / size))
	c_max = Vector2i(floori(hi.x / size) - 1, floori(hi.y / size) - 1)


## Builds the full-detail chunks within `radius` of `at` first (on all
## cores, a frame at a time so the window keeps responding), so the player
## has streets under their feet at the start. Everything else streams in
## after. Await it.
func prime(at: Vector2, radius: float) -> void:
	_focus = at
	_has_focus = true
	var cells := _cells_within(at, radius)
	for c in cells:
		_start(c, false)
	# Wait a frame at a time (never blocking the window) until they're done.
	while true:
		var done := true
		for key: String in _jobs.keys():
			if not WorkerThreadPool.is_task_completed(_jobs[key]):
				done = false
				break
		if done:
			break
		await get_tree().process_frame
	_reap()
	_attach_finished(1000)


## True once every chunk that should be showing round the focus is in.
func is_settled() -> bool:
	if not _has_focus:
		return false
	for c in _cells_within(_focus, _detail()):
		if not _near.has(c):
			return false
	if BuildingGenerator.facade_relief:
		for c in _cells_within(_focus, _facade_r()):
			if not _facade.has(c):
				return false
	for c in _cells_within(_focus, _distant()):
		if not _near.has(c) and not _far.has(c):
			return false
	return _jobs.is_empty() and _done.is_empty()


func near_count() -> int:
	return _near.size()


func far_count() -> int:
	return _far.size()


## On the way out (quitting, or a new scene), let running builds finish
## and free what they made, so no thread is left using freed data.
func _exit_tree() -> void:
	for key: String in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(_jobs[key])
	_jobs.clear()
	for key: String in _redo.keys():
		WorkerThreadPool.wait_for_task_completion(_redo[key])
	_redo.clear()
	_mutex.lock()
	for item: Array in _done:
		if item[2] is Node3D:
			(item[2] as Node3D).free()
	_done.clear()
	_mutex.unlock()


## Switches to new map data (the map editor's edits were saved) and
## rebuilds the shown chunks in `cells` from it. Each old chunk stays up
## until its replacement is ready, so nothing disappears. Chunks not in
## `cells` are kept; chunks built later use the new data.
func replace_data(new_data: StreetData, new_net: RoadNetwork, cells: Dictionary) -> void:
	_gen += 1
	data = new_data
	net = new_net
	for c: Vector2i in cells:
		_cell_gen[c] = _gen
		if _near.has(c):
			_start_redo(c, false)
		if _far.has(c):
			_start_redo(c, true)


## How many changed chunks are still being rebuilt.
func redo_pending() -> int:
	return _redo.size()


func _start_redo(c: Vector2i, lod: bool) -> void:
	var key := _key(c, lod) + "_redo"
	if _redo.has(key):
		return # already rebuilding; the generation check catches a stale result
	_redo[key] = WorkerThreadPool.add_task(_redo_job.bind(c, lod, _gen), false, "rebuild %s" % key)


func _redo_job(c: Vector2i, lod: bool, gen: int) -> void:
	var node := ChunkBuilder.build(data, net, terrain, c.x, c.y, lod)
	_mutex.lock()
	_done.append([c, lod, node, gen, true])
	_mutex.unlock()


## Look at the camera now rather than at the next check (after a jump).
func refresh() -> void:
	_timer = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_focus = Vector2(cam.global_position.x, cam.global_position.z)
		_has_focus = true
		_update()


## The Graphics setting (an autoload), looked up by path so this works even
## before the streamer is in the scene.
func _graphics() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Graphics") if tree != null else null


func _detail() -> float:
	var g := _graphics()
	return g.detail_radius() if g != null else 330.0


func _facade_r() -> float:
	var g := _graphics()
	return g.facade_radius() if g != null else 150.0


func _distant() -> float:
	var g := _graphics()
	return g.distant_radius() if g != null else 1000.0


func _process(delta: float) -> void:
	_reap()
	_attach_finished(ATTACH_PER_FRAME)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	_focus = Vector2(p.x, p.z)
	_has_focus = true
	_update()


func _update() -> void:
	var detail := _detail()
	var distant := _distant()
	# Drop what's now too far, a couple at a time (freeing a chunk isn't free).
	var drops := 0
	for c: Vector2i in _near.keys():
		if drops < DROP_PER_CHECK and _dist(c, _focus) > detail + KEEP_EXTRA:
			drops += 1
			var n: Node3D = _near[c]
			_near.erase(c)
			_facade.erase(c)
			n.queue_free()
			if _far.has(c):
				(_far[c] as Node3D).visible = true
	for c: Vector2i in _far.keys():
		if drops < DROP_PER_CHECK and _dist(c, _focus) > distant + KEEP_EXTRA:
			drops += 1
			(_far[c] as Node3D).queue_free()
			_far.erase(c)
	# Close-up facades off again for chunks the player has left.
	var facade := _facade_r()
	for c: Vector2i in _facade.keys():
		if _dist(c, _focus) > facade + FACADE_EXTRA:
			_facade.erase(c)
			if _near.has(c):
				_swap_buildings(_near[c], null)
	# Start the nearest missing chunks.
	if _jobs.size() >= MAX_JOBS:
		return
	var want: Array = [] # [distance, cell, lod] (lod: true far, false near, "fac" facade)
	if BuildingGenerator.facade_relief:
		for c in _cells_within(_focus, facade):
			if _near.has(c) and not _facade.has(c) and not _jobs.has(_fac_key(c)):
				want.append([_dist(c, _focus) + 1.0, c, "fac"])
	for c in _cells_within(_focus, distant):
		var d := _dist(c, _focus)
		if d <= detail:
			if not _near.has(c) and not _jobs.has(_key(c, false)):
				want.append([d, c, false])
		elif not _far.has(c) and not _near.has(c) and not _jobs.has(_key(c, true)):
			# Distant chunks wait behind the near ones.
			want.append([d + 10000.0, c, true])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for w: Array in want:
		if _jobs.size() >= MAX_JOBS:
			break
		_start(w[1], w[2])


func _start(c: Vector2i, lod: Variant) -> void:
	if lod is String:
		var fk := _fac_key(c)
		if not _jobs.has(fk):
			_jobs[fk] = WorkerThreadPool.add_task(_facade_job.bind(c), false, "facade %s" % fk)
		return
	var key := _key(c, lod)
	if _jobs.has(key):
		return
	_jobs[key] = WorkerThreadPool.add_task(_build_job.bind(c, lod), false, "chunk %s" % key)


func _facade_job(c: Vector2i) -> void:
	var gen := _gen
	var mesh := ChunkBuilder.build_detail(data, net, terrain, c.x, c.y)
	_mutex.lock()
	_done.append([c, "fac", mesh, gen])
	_mutex.unlock()


## Puts the close-up `meshes` ({tile name: ArrayMesh}; or, with null, each
## tile's own plain mesh back) on a full chunk's merged building tiles.
func _swap_buildings(chunk: Node3D, meshes: Variant) -> void:
	var holder := chunk.get_node_or_null("Buildings")
	if holder == null:
		return
	for c in holder.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not str(mi.name).begins_with("Buildings"):
			continue # posters on the walls
		if not mi.has_meta("plain_mesh"):
			mi.set_meta("plain_mesh", mi.mesh)
		var m: Variant = (meshes as Dictionary).get(str(mi.name)) if meshes != null else null
		mi.mesh = m if m != null else mi.get_meta("plain_mesh")


func _build_job(c: Vector2i, lod: bool) -> void:
	var gen := _gen
	var node := ChunkBuilder.build(data, net, terrain, c.x, c.y, lod)
	_mutex.lock()
	_done.append([c, lod, node, gen, false])
	_mutex.unlock()


## Clears finished tasks from the pool's books.
func _reap() -> void:
	for key: String in _jobs.keys():
		var id: int = _jobs[key]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_jobs.erase(key)
	for key: String in _redo.keys():
		var id: int = _redo[key]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_redo.erase(key)


func _attach_finished(limit: int) -> void:
	_mutex.lock()
	var ready := _done.slice(0, limit)
	_done = _done.slice(limit)
	_mutex.unlock()
	for item: Array in ready:
		var c: Vector2i = item[0]
		if item[1] is String:
			var fmesh: Dictionary = item[2]
			if int(item[3]) < int(_cell_gen.get(c, 0)):
				continue # built before an edit to this chunk; _update asks again
			if not fmesh.is_empty() and _near.has(c) and not _facade.has(c) and _dist(c, _focus) <= _facade_r() + FACADE_EXTRA:
				_swap_buildings(_near[c], fmesh)
				_facade[c] = true
			continue
		var lod: bool = item[1]
		var node: Node3D = item[2]
		var d := _dist(c, _focus)
		var stale := int(item[3]) < int(_cell_gen.get(c, 0))
		if bool(item[4]):
			# A rebuild of a changed chunk: swap it for the one showing.
			var shown: Dictionary = _far if lod else _near
			if stale or not shown.has(c):
				node.free()
				if stale and shown.has(c):
					_start_redo(c, lod)
				continue
			var was: Node3D = shown[c]
			shown[c] = node
			if lod:
				node.visible = was.visible
			else:
				_facade.erase(c) # the close-up facade is built again from the new data
			add_child(node)
			was.queue_free()
			continue
		if stale:
			# Built from data older than an edit to this chunk: show it (no
			# hole) and rebuild it from the new data.
			_start_redo.call_deferred(c, lod)
		if lod:
			if _far.has(c) or d > _distant() + KEEP_EXTRA:
				node.free()
				continue
			_far[c] = node
			node.visible = not _near.has(c)
		else:
			if _near.has(c) or d > _detail() + KEEP_EXTRA:
				node.free()
				continue
			_near[c] = node
			if _far.has(c):
				(_far[c] as Node3D).visible = false
		add_child(node)


func _fac_key(c: Vector2i) -> String:
	return "%d_%d_fac" % [c.x, c.y]


func _key(c: Vector2i, lod: bool) -> String:
	return "%d_%d_%s" % [c.x, c.y, "far" if lod else "near"]


## Distance from p to the nearest point of chunk c.
func _dist(c: Vector2i, p: Vector2) -> float:
	var r := ChunkBuilder.chunk_rect(data, c.x, c.y)
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


func _cells_within(p: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := data.chunk_size
	var lo := Vector2i(floori((p.x - radius) / size), floori((p.y - radius) / size))
	var hi := Vector2i(floori((p.x + radius) / size), floori((p.y + radius) / size))
	for cx in range(maxi(lo.x, c_min.x), mini(hi.x, c_max.x) + 1):
		for cz in range(maxi(lo.y, c_min.y), mini(hi.y, c_max.y) + 1):
			var c := Vector2i(cx, cz)
			if _dist(c, p) <= radius:
				out.append(c)
	return out

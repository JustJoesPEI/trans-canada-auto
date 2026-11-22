class_name ChunkStreamer
extends Node3D
## Keeps the town built round the player, a square chunk at a time.
##
## Chunks within Graphics.detail_radius() of the camera are built in full
## detail (with collision); chunks out to Graphics.distant_radius() in low
## detail. A chunk's full version replaces its low one when it's ready, and
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

var data: StreetData
var net: RoadNetwork
var terrain: Terrain
## Chunk grid bounds (inclusive), from the elevation survey.
var c_min := Vector2i.ZERO
var c_max := Vector2i.ZERO

var _near: Dictionary = {} ## Vector2i -> Node3D (full detail, in the scene)
var _far: Dictionary = {} ## Vector2i -> Node3D (low detail, in the scene)
var _jobs: Dictionary = {} ## [Vector2i, lod] key string -> task id
var _done: Array = [] ## [cell, lod, node] waiting to be added
var _mutex := Mutex.new()
var _timer := 0.0
var _focus := Vector2.ZERO
var _has_focus := false


func setup(street_data: StreetData, network: RoadNetwork, ground: Terrain) -> void:
	data = street_data
	net = network
	terrain = ground
	var size := data.chunk_size
	var lo := terrain.origin
	var hi := terrain.origin + Vector2((terrain.nx - 1) * terrain.spacing, (terrain.nz - 1) * terrain.spacing)
	c_min = Vector2i(floori(lo.x / size), floori(lo.y / size))
	c_max = Vector2i(floori(hi.x / size) - 1, floori(hi.y / size) - 1)


## Builds the full-detail chunks within `radius` of `at` right away (on
## all cores, waiting for them), so the player has streets under their feet
## at the start. Everything else streams in after.
func prime(at: Vector2, radius: float) -> void:
	_focus = at
	_has_focus = true
	var cells := _cells_within(at, radius)
	for c in cells:
		_start(c, false)
	for key: String in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(_jobs[key])
	_jobs.clear()
	_attach_finished(1000)


## True once every chunk that should be showing round the focus is in.
func is_settled() -> bool:
	if not _has_focus:
		return false
	for c in _cells_within(_focus, _detail()):
		if not _near.has(c):
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
	_mutex.lock()
	for item: Array in _done:
		(item[2] as Node3D).free()
	_done.clear()
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
			n.queue_free()
			if _far.has(c):
				(_far[c] as Node3D).visible = true
	for c: Vector2i in _far.keys():
		if drops < DROP_PER_CHECK and _dist(c, _focus) > distant + KEEP_EXTRA:
			drops += 1
			(_far[c] as Node3D).queue_free()
			_far.erase(c)
	# Start the nearest missing chunks.
	if _jobs.size() >= MAX_JOBS:
		return
	var want: Array = [] # [distance, cell, lod]
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


func _start(c: Vector2i, lod: bool) -> void:
	var key := _key(c, lod)
	if _jobs.has(key):
		return
	_jobs[key] = WorkerThreadPool.add_task(_build_job.bind(c, lod), false, "chunk %s" % key)


func _build_job(c: Vector2i, lod: bool) -> void:
	var node := ChunkBuilder.build(data, net, terrain, c.x, c.y, lod)
	_mutex.lock()
	_done.append([c, lod, node])
	_mutex.unlock()


## Clears finished tasks from the pool's books.
func _reap() -> void:
	for key: String in _jobs.keys():
		var id: int = _jobs[key]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_jobs.erase(key)


func _attach_finished(limit: int) -> void:
	_mutex.lock()
	var ready := _done.slice(0, limit)
	_done = _done.slice(limit)
	_mutex.unlock()
	for item: Array in ready:
		var c: Vector2i = item[0]
		var lod: bool = item[1]
		var node: Node3D = item[2]
		var d := _dist(c, _focus)
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

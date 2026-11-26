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
## work), checked a few times a second. `extra_foci` are other places the
## town has to be built round (other players, on a server: their streets
## and buildings, for collision, out to EXTRA_RADIUS).

## Extra distance before a chunk is dropped, so chunks don't flicker in and
## out at the edge.
const KEEP_EXTRA := 90.0
const CHECK_EVERY := 0.2
## Most chunk builds running at once, and most finished chunks added per
## frame: of those, at most HEAVY_PER_FRAME full-detail chunks or close-up
## facade swaps (each is milliseconds on the main thread). Chunks left
## behind are hidden at once and freed one a frame, never in a frame that
## added a heavy one.
const MAX_JOBS := 3
const ATTACH_PER_FRAME := 4
const HEAVY_PER_FRAME := 1
const DROP_PER_CHECK := 2
## A full chunk's collision bodies (some forty: streets, ground, buildings,
## trees, posts) are most of what adding it costs the main thread (8 ms of
## 9: each joins the physics). So a chunk is built with them switched off
## and they're switched on a few a frame, nearest chunk first, within this
## much time (ms). A chunk joins at the detail radius, hundreds of metres
## off, so its collision is there long before anyone reaches it.
const WAKE_MS := 2.0
## Most chunks left waiting to be freed; past this they go at once.
const RETIRED_WAIT := 2
const RETIRED_MAX := 4
## Extra distance before close-up facades are swapped back out.
const FACADE_EXTRA := 40.0
## Full chunks are kept built this far round each of `extra_foci`.
const EXTRA_RADIUS := 220.0

## Other places to keep built round (ground positions), besides the camera.
var extra_foci := PackedVector2Array()

## Run with --headless, Godot draws with a stand-in renderer whose tables of
## meshes, materials and MultiMeshes aren't safe to use from two threads at
## once (the real renderers' are): a chunk built on a worker while the main
## thread makes or frees anything that draws can corrupt them ("Initializing
## already initialized RID", "Parameter "m" is null", a crash in malloc).
## There chunks are built on the main thread, MAX_JOBS per check, instead
## (`-- --threaded-chunks` builds them on workers anyway, to look for it:
## tools/stream_stress.gd).
static var on_main_thread := DisplayServer.get_name() == "headless" \
		and not OS.get_cmdline_user_args().has("--threaded-chunks")

var data: StreetData
var net: RoadNetwork
var terrain: Terrain
## Chunk grid bounds (inclusive), from the elevation survey.
var c_min := Vector2i.ZERO
var c_max := Vector2i.ZERO

## Chunks added to the scene so far (full detail, distant) and close-up
## facades swapped in, for the hitch log (Graphics).
static var added_near := 0
static var added_far := 0
static var facades_swapped := 0
static var dropped := 0
## Chunks left behind, hidden, waiting to be freed.
var _retired: Array[Node3D] = []
## Chunks in the scene whose collision is still being switched on:
## [cell, bodies (Array of CollisionObject3D)].
var _waking: Array = []
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
	_wake_bodies(INF) # loading: all of it now


## True once every chunk that should be showing round the focus is in.
func is_settled() -> bool:
	if not _has_focus:
		return false
	if not _waking.is_empty():
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
	return extras_ready() and _jobs.is_empty() and _done.is_empty()


## True once the full chunks round every one of `extra_foci` are in.
func extras_ready() -> bool:
	for f: Vector2 in extra_foci:
		for c in _cells_within(f, EXTRA_RADIUS):
			if not _near.has(c):
				return false
	return true


## Whether full chunk c is wanted round one of `extra_foci` (within r).
func _near_extra(c: Vector2i, r: float) -> bool:
	for f: Vector2 in extra_foci:
		if _dist(c, f) <= r:
			return true
	return false


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
	if on_main_thread:
		_redo_job(c, lod, _gen)
		return
	_redo[key] = WorkerThreadPool.add_task(_redo_job.bind(c, lod, _gen), false, "rebuild %s" % key)


func _redo_job(c: Vector2i, lod: bool, gen: int) -> void:
	var node := ChunkBuilder.build(data, net, terrain, c.x, c.y, lod)
	var bodies := [] if lod else _hold_bodies(node)
	_mutex.lock()
	_done.append([c, lod, node, gen, true, bodies])
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
	var heavy := _attach_finished(ATTACH_PER_FRAME, HEAVY_PER_FRAME)
	_wake_bodies(WAKE_MS)
	# One a frame, in a frame that added nothing heavy, unless they're
	# piling up (driving on into new town, every frame adds one).
	if heavy == 0 or _retired.size() > RETIRED_WAIT:
		_free_one_retired()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		_focus = Vector2(p.x, p.z)
		_has_focus = true
	elif extra_foci.is_empty():
		return
	_update()


func _update() -> void:
	var detail := _detail()
	var distant := _distant()
	# Drop what's now too far, a couple at a time (freeing a chunk isn't free).
	var drops := 0
	for c: Vector2i in _near.keys():
		if drops < DROP_PER_CHECK and _dist(c, _focus) > detail + KEEP_EXTRA and not _near_extra(c, EXTRA_RADIUS + KEEP_EXTRA):
			drops += 1
			var n: Node3D = _near[c]
			_near.erase(c)
			_facade.erase(c)
			_retire(n)
			if _far.has(c):
				(_far[c] as Node3D).visible = true
	for c: Vector2i in _far.keys():
		if drops < DROP_PER_CHECK and _dist(c, _focus) > distant + KEEP_EXTRA:
			drops += 1
			_retire(_far[c])
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
	# Built and waiting to join the scene: not missing, so not built again.
	var waiting := {}
	_mutex.lock()
	for item: Array in _done:
		var lod: Variant = item[1]
		waiting[_fac_key(item[0]) if lod is String else _key(item[0], lod)] = true
	_mutex.unlock()
	var want: Array = [] # [distance, cell, lod] (lod: true far, false near, "fac" facade)
	if BuildingGenerator.facade_relief:
		for c in _cells_within(_focus, facade):
			if _near.has(c) and not _facade.has(c) and not _jobs.has(_fac_key(c)) and not waiting.has(_fac_key(c)):
				want.append([_dist(c, _focus) + 1.0, c, "fac"])
	for c in _cells_within(_focus, distant):
		var d := _dist(c, _focus)
		if d <= detail:
			if not _near.has(c) and not _jobs.has(_key(c, false)) and not waiting.has(_key(c, false)):
				want.append([d, c, false])
		elif not _far.has(c) and not _near.has(c) and not _jobs.has(_key(c, true)) and not waiting.has(_key(c, true)):
			# Distant chunks wait behind the near ones.
			want.append([d + 10000.0, c, true])
	# Round the other places: after the camera's own near chunks, before
	# its distant ones.
	var queued := {}
	for w: Array in want:
		if not (w[2] is String) and not bool(w[2]):
			queued[w[1]] = true
	for f: Vector2 in extra_foci:
		for c in _cells_within(f, EXTRA_RADIUS):
			if not _near.has(c) and not queued.has(c) and not _jobs.has(_key(c, false)) and not waiting.has(_key(c, false)):
				queued[c] = true
				want.append([_dist(c, f) + 5000.0, c, false])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var built_here := 0
	for w: Array in want:
		if _jobs.size() + built_here >= MAX_JOBS:
			break
		_start(w[1], w[2])
		if on_main_thread:
			built_here += 1


func _start(c: Vector2i, lod: Variant) -> void:
	if lod is String:
		var fk := _fac_key(c)
		if on_main_thread:
			_facade_job(c)
		elif not _jobs.has(fk):
			_jobs[fk] = WorkerThreadPool.add_task(_facade_job.bind(c), false, "facade %s" % fk)
		return
	var key := _key(c, lod)
	if _jobs.has(key):
		return
	if on_main_thread:
		_build_job(c, lod)
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
	var bodies := [] if lod else _hold_bodies(node)
	_mutex.lock()
	_done.append([c, lod, node, gen, false, bodies])
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


## Finished chunks into the scene: up to `limit` of them, of which at most
## `heavy_limit` full-detail chunks or close-up facade swaps (each of those
## is milliseconds on the main thread: its bodies join the physics, its
## meshes and instances the renderer). Returns how many heavy ones it added.
func _attach_finished(limit: int, heavy_limit := 1000) -> int:
	var heavy := 0
	var taken := 0
	while taken < limit:
		_mutex.lock()
		if _done.is_empty():
			_mutex.unlock()
			break
		var item: Array = _done[0]
		var is_heavy: bool = item[1] is String or not bool(item[1])
		if is_heavy and heavy >= heavy_limit:
			_mutex.unlock()
			break
		_done.remove_at(0)
		_mutex.unlock()
		taken += 1
		if is_heavy:
			heavy += 1
		_attach_one(item)
	return heavy


## Switches a new chunk's collision bodies off (they join the physics later,
## a few a frame: _wake_bodies). Safe on a worker: the chunk isn't in the
## scene yet.
static func _hold_bodies(node: Node) -> Array:
	var out := []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			out.append(n)
		stack.append_array(n.get_children())
	return out


## Switches on held collision bodies, nearest chunk first, until `budget_ms`
## is used (at least one a frame while there are any).
func _wake_bodies(budget_ms: float) -> void:
	if _waking.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var best := 0
	var best_d := INF
	for i in _waking.size():
		var d := _dist(_waking[i][0], _focus)
		if d < best_d:
			best_d = d
			best = i
	var entry: Array = _waking[best]
	var bodies: Array = entry[1]
	while not bodies.is_empty():
		var b: Variant = bodies.pop_back()
		if is_instance_valid(b) and (b as Node).is_inside_tree():
			(b as Node).process_mode = Node.PROCESS_MODE_INHERIT
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	if bodies.is_empty():
		_waking.remove_at(best)
		if budget_ms == INF:
			_wake_bodies(INF)


## A chunk left behind: hidden now, freed later (_free_one_retired).
func _retire(n: Node3D) -> void:
	n.visible = false
	_retired.append(n)
	while _retired.size() > RETIRED_MAX:
		_free_one_retired()


func _free_one_retired() -> void:
	while not _retired.is_empty():
		var n: Node3D = _retired.pop_front()
		if is_instance_valid(n):
			n.queue_free()
			dropped += 1
			return


func _attach_one(item: Array) -> void:
	var c: Vector2i = item[0]
	if item[1] is String:
		var fmesh: Dictionary = item[2]
		if int(item[3]) < int(_cell_gen.get(c, 0)):
			return # built before an edit to this chunk; _update asks again
		if _near.has(c) and not _facade.has(c) and _dist(c, _focus) <= _facade_r() + FACADE_EXTRA:
			if not fmesh.is_empty():
				_swap_buildings(_near[c], fmesh)
				facades_swapped += 1
			# Marked done even with no buildings to swap: otherwise an
			# empty chunk is asked for again at every check, and its
			# facade jobs (first in line) keep every other chunk waiting.
			_facade[c] = true
		return
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
			return
		var was: Node3D = shown[c]
		shown[c] = node
		if lod:
			node.visible = was.visible
		else:
			_facade.erase(c) # the close-up facade is built again from the new data
		add_child(node)
		# (Straight away: the old one, collision and all, goes now. Edits
		# are rare and a car may be standing on it.)
		if item.size() > 5:
			for body: Variant in item[5]:
				(body as Node).process_mode = Node.PROCESS_MODE_INHERIT
		was.queue_free()
		return
	if stale:
		# Built from data older than an edit to this chunk: show it (no
		# hole) and rebuild it from the new data.
		_start_redo.call_deferred(c, lod)
	if lod:
		if _far.has(c) or d > _distant() + KEEP_EXTRA:
			node.free()
			return
		_far[c] = node
		node.visible = not _near.has(c)
	else:
		if _near.has(c) or (d > _detail() + KEEP_EXTRA and not _near_extra(c, EXTRA_RADIUS + KEEP_EXTRA)):
			node.free()
			return
		_near[c] = node
		if _far.has(c):
			(_far[c] as Node3D).visible = false
	if lod:
		added_far += 1
	else:
		added_near += 1
	add_child(node)
	_queue_bodies(c, item)


func _queue_bodies(c: Vector2i, item: Array) -> void:
	if item.size() > 5 and not (item[5] as Array).is_empty():
		_waking.append([c, item[5]])


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

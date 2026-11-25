extends SceneTree
## Streams the town in as hard as it goes, to catch thread-safety trouble in
## the chunk builders (they run on worker threads while the main thread adds
## finished chunks to the scene):
##
##   godot --headless --log-file /dev/null --fixed-fps 60 --path . --script res://tools/stream_stress.gd -- [--jumps=40] [--seed=1] [--threaded-chunks]
##
## Headless, chunks are built on the main thread (ChunkStreamer.on_main_thread);
## --threaded-chunks builds them on workers as the real game does, which on
## the stand-in renderer prints a storm of errors (keep the log off and
## filter the output: it can run to gigabytes).
##
## Jumps the focus to random spots across the whole map and, as the checks'
## _hold_for_streets does, calls the streamer's _update, _reap and
## _attach_finished in a tight loop until the streets round it are in, while
## the main thread also makes and frees a few things that draw (as a police
## car being spawned does). Prints "STRESS done" at the end; any engine
## error in the log ("RID", "is null", "already initialized") is the failure.

const RADIUS := 140.0

var _world: WorldBuilder
var _cam := Camera3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var jumps := int(args.get("jumps", "40"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.get("seed", "1"))
	TrafficManager.autostart = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	_world = main.get_node("World")
	if not _world.is_built:
		await _world.built
	var player: Node3D = main.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_cam)
	_cam.make_current()
	var s := _world.streamer
	var size := s.data.chunk_size
	var lo := Vector2(s.c_min) * size
	var hi := Vector2(s.c_max + Vector2i.ONE) * size
	# Mostly where the town is (its chunks of map data), sometimes anywhere.
	var cells: Array = s.data.chunk_keys.keys()
	var t0 := Time.get_ticks_msec()
	var attached := 0
	for j in jumps:
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if not cells.is_empty() and rng.randf() < 0.8:
			var k: PackedStringArray = str(cells[rng.randi() % cells.size()]).split("_")
			if k.size() >= 2:
				p = Vector2((float(k[0]) + rng.randf()) * size, (float(k[1]) + rng.randf()) * size)
		_cam.global_position = Vector3(p.x, 60.0, p.y)
		var tj := Time.get_ticks_msec()
		while not _ready_at(s, p) and Time.get_ticks_msec() - tj < 30000:
			s._focus = p
			s._has_focus = true
			s._update()
			s._reap()
			var before := s.near_count() + s.far_count()
			s._attach_finished(4)
			attached += maxi(0, s.near_count() + s.far_count() - before)
			_churn(rng)
			OS.delay_msec(1)
		# A few real frames between jumps, so freed chunks really go.
		for f in 3:
			await process_frame
		# Objects, resources and nodes should level off, not keep growing
		# (a leak would, jump after jump).
		print("STRESS jump %d at (%.0f, %.0f): %d near, %d far, %d ms; %d objects, %d resources, %d nodes" % [j, p.x, p.y,
			s.near_count(), s.far_count(), Time.get_ticks_msec() - tj, Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("STRESS done: %d jumps, %d chunks attached, %.1f s" % [jumps, attached, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _ready_at(s: ChunkStreamer, p: Vector2) -> bool:
	for c in s._cells_within(p, RADIUS):
		if not s._near.has(c):
			return false
	return true


## Things the main thread makes and frees while chunks build: a label, a
## mesh and a material, as spawning a car does.
func _churn(rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	var label := Label3D.new()
	label.text = "POLICE %d" % rng.randi_range(0, 99)
	n.add_child(label)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(rng.randf(), rng.randf(), rng.randf())
	bm.material = m
	mi.mesh = bm
	n.add_child(mi)
	root.add_child(n)
	n.queue_free()

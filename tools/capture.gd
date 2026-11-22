extends SceneTree
## Loads the game, measures it, and saves screenshots from set viewpoints.
## For checking changes without playing. Run it with a real renderer, e.g.:
##
##   godot --path . --rendering-driver vulkan --resolution 1600x900 \
##       --script res://tools/capture.gd -- --out=/tmp/shots \
##       --shot=spawn:0,0,0,-12 --shot=name:x,z,yaw_deg,pitch_deg[,lift]
##
## A shot is "name:x,z,yaw,pitch" with an optional lift above the ground
## (default 1.7 m). yaw 0 looks north, 90 looks west. --walk=x,z moves the
## player there first so the town streams in around it (done for every
## shot automatically). --frames=N sets how many frames to time (default 120).
## Prints one "CAPTURE ..." line per measurement.

var _args := {}
var _shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "shot":
			_shots.append(kv[1])
		elif kv.size() == 2:
			_args[kv[0]] = kv[1]
		else:
			_args[kv[0]] = "1"
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: Node = main.get_node("World")
	if not world.is_built:
		await world.built
	# Wait for the streamed chunks round the spawn, if the world streams.
	if world.has_method("wait_until_settled"):
		await world.wait_until_settled()
	var startup := Time.get_ticks_msec() - t0
	print("CAPTURE startup_ms=%d" % startup)
	await _measure("spawn", int(_args.get("frames", "120")))

	var out := str(_args.get("out", "user://shots"))
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	for s: String in _shots:
		var parts := s.split(":")
		var nm := parts[0]
		var v := parts[1].split_floats(",")
		var pos := Vector2(v[0], v[1])
		var lift := v[4] if v.size() > 4 else 1.7
		var player: Node3D = main.get_node("Player")
		player.global_position = world.terrain.at(pos, 0.5)
		if world.has_method("wait_until_settled"):
			await world.wait_until_settled()
		cam.global_position = world.terrain.at(pos, lift)
		cam.rotation = Vector3(deg_to_rad(v[3]), deg_to_rad(v[2]), 0.0)
		cam.make_current()
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, nm])
		await _measure(nm, 30)
	print("CAPTURE done")
	quit()


func _measure(label: String, frames: int) -> void:
	var t := Time.get_ticks_usec()
	var worst := 0
	var last := t
	var draws := 0
	var prims := 0
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var avg := float(Time.get_ticks_usec() - t) / frames / 1000.0
	# Whole-process memory (Linux only): resident now and the peak so far.
	var rss := ""
	var out: Array = []
	if OS.execute("grep", ["-E", "VmRSS|VmHWM", "/proc/%d/status" % OS.get_process_id()], out) == 0:
		for line in str(out[0]).split("\n"):
			if line.contains(":"):
				rss += " %s=%dMB" % [line.get_slice(":", 0), line.get_slice(":", 1).strip_edges().to_int() / 1024]
	print("CAPTURE %s frame_ms=%.1f worst_ms=%.1f draw_calls=%d primitives=%d objects=%d nodes=%d static_mem_mb=%.0f video_mem_mb=%.0f%s" % [
		label, avg, worst / 1000.0, draws, prims,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, rss,
	])

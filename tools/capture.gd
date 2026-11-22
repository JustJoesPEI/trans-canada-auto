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
## --fade also fades the building straight ahead (as the camera does when
## one hides the player) and saves NAME_faded.png.
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
	# Playable: the scene is up and the streets round the spawn are built.
	print("CAPTURE startup_ms=%d" % (Time.get_ticks_msec() - t0))
	# Wait for the streamed chunks round the spawn, if the world streams.
	if world.has_method("wait_until_settled"):
		await world.wait_until_settled()
		print("CAPTURE settled_ms=%d (every chunk in view range loaded; slow here because software rendering draws about one frame a second)" % (Time.get_ticks_msec() - t0))
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
		# The player stands a few metres behind the camera, out of shot.
		var player: Node3D = main.get_node("Player")
		var back := Vector2(sin(deg_to_rad(v[2])), cos(deg_to_rad(v[2]))) * 6.0
		player.global_position = world.terrain.at(pos + back, 0.5)
		cam.global_position = world.terrain.at(pos, lift)
		cam.rotation = Vector3(deg_to_rad(v[3]), deg_to_rad(v[2]), 0.0)
		cam.make_current()
		if world.has_method("wait_until_settled"):
			await world.wait_until_settled()
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, nm])
		if _args.has("fade"):
			# Fade the first building straight ahead of the camera, the way the
			# game camera does, and shoot again.
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 200.0, 2)
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and (hit["collider"] as Object).has_meta("fade_mesh"):
				var h: Object = (hit["collider"] as Object).get_meta("fade_mesh")
				if h.has_method("set_camera_fade"):
					h.set_camera_fade(0.75)
				for i in 4:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_faded.png" % [out, nm])
				if h.has_method("set_camera_fade"):
					h.set_camera_fade(0.0)
				print("CAPTURE faded %s" % (hit["collider"] as Node).name)
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

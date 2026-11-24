extends SceneTree
## Keeps the game running and takes screenshots on request, so checking a
## change doesn't mean loading the town again for every picture. Started
## and fed by tools/shot.sh; see there for how to use it.
##
## Requests are files in --dir (default /tmp/tca-shots): NAME.req holding
## one shot per line, "name:x,z,yaw,pitch[,lift]" as in tools/capture.gd
## (yaw 0 looks north, 90 west; lift is metres above the ground, default
## 1.7). Each picture is saved as name.png in the same folder, then NAME.done
## lists them with how long each took. A request reading "quit" stops it.
##
## Why it's quick where capture.gd is slow: on a computer with no graphics
## card every frame is drawn in software, about one a second, and the town
## streams in a few chunks per frame. Here nothing is drawn while the town
## round the camera streams in (the frames fly by and the chunk builders get
## every core); drawing comes back on for the few frames each picture needs.
##
## The game watches data/edits.json as usual, so map editor changes show up
## in the next picture without a restart. Changes to scripts, shaders,
## scenes or map_config.json need a fresh start, which shot.sh does by itself.

const POLL := 0.2
## Frames drawn before each picture is saved: lets the sky, shadows and
## screen-space effects settle.
const DRAW_FRAMES := 3

var _dir := "/tmp/tca-shots"
var _main: Node
var _world: Node
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.trim_prefix("--dir=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	RenderingServer.render_loop_enabled = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 4000.0
	root.add_child(_cam)
	_write("server.ready", "%d\n" % (Time.get_ticks_msec() - t0))
	print("SHOTS ready in %d ms, watching %s" % [Time.get_ticks_msec() - t0, _dir])
	while true:
		var reqs := Array(DirAccess.get_files_at(_dir)).filter(func(f: String) -> bool: return f.ends_with(".req"))
		reqs.sort()
		for f: String in reqs:
			var path := _dir.path_join(f)
			var text := FileAccess.get_file_as_string(path)
			DirAccess.remove_absolute(path)
			if text.strip_edges() == "quit":
				_write("server.stopped", "")
				quit()
				return
			var report := PackedStringArray()
			for line in text.split("\n", false):
				line = line.strip_edges()
				if line != "":
					report.append(await _shot(line))
			_write(f.get_basename() + ".done", "\n".join(report) + "\n")
		await create_timer(POLL).timeout


func _shot(spec: String) -> String:
	var t := Time.get_ticks_msec()
	var parts := spec.split(":", true, 1)
	if parts.size() != 2:
		return "ERROR bad shot '%s' (want name:x,z,yaw,pitch[,lift])" % spec
	var nm := parts[0]
	var v := parts[1].split_floats(",")
	if v.size() < 4:
		return "ERROR bad shot '%s' (want name:x,z,yaw,pitch[,lift])" % spec
	var pos := Vector2(v[0], v[1])
	var lift := v[4] if v.size() > 4 else 1.7
	# The player stands a few metres behind the camera, out of shot.
	var player: Node3D = _main.get_node("Player")
	var back := Vector2(sin(deg_to_rad(v[2])), cos(deg_to_rad(v[2]))) * 6.0
	player.global_position = _world.terrain.at(pos + back, 0.5)
	_cam.global_position = _world.terrain.at(pos, lift)
	_cam.rotation = Vector3(deg_to_rad(v[3]), deg_to_rad(v[2]), 0.0)
	_cam.make_current()
	# Stream the town in round the camera without drawing it.
	RenderingServer.render_loop_enabled = false
	await process_frame
	await _world.wait_until_settled(120.0)
	var settled := Time.get_ticks_msec() - t
	RenderingServer.render_loop_enabled = true
	for i in DRAW_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := _dir.path_join(nm + ".png")
	root.get_texture().get_image().save_png(out)
	RenderingServer.render_loop_enabled = false
	return "%s  (%.1f s: %.1f s streaming the town in, %.1f s drawing)" % [
		out, (Time.get_ticks_msec() - t) / 1000.0, settled / 1000.0, (Time.get_ticks_msec() - t - settled) / 1000.0]


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(_dir.path_join(file), FileAccess.WRITE)
	f.store_string(text)
	f.close()

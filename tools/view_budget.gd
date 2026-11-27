extends SceneTree
## What a frame really costs to draw at the busiest spots in town, on one
## graphics setting, with the traffic and the people on foot out, and
## whether it fits that setting's budget (docs/world_art.md, "Draw calls
## per setting"). world_budget.gd counts one chunk at a time; this counts
## what the camera sees: every chunk round it, near and distant, the cars,
## the people and the sun's shadows, as the game draws them.
##
##   godot --path . --rendering-driver vulkan --resolution 960x540 \
##       --script res://tools/view_budget.gd -- --graphics=low [--budget] [--why] [--spots=name:x,z;...]
##
## (In the cloud: VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a ...)
##
## At each spot it lets the town stream in and the streets fill (--secs of
## game time, nothing drawn), then looks round from a driving camera's
## height in four directions and keeps the worst. --why breaks the worst
## one down: each kind of thing is hidden in turn and the frame drawn
## again, so the difference is exactly what that kind costs.
## The draw calls don't depend on the resolution, so a small window does.
##
## One "VIEW" line per spot, "VIEW FAIL" and a non-zero exit code for a
## spot over budget with --budget.

## Busy spots, [name, x, z] in game metres: downtown at Great George and
## Richmond, Grafton Street's shops, the mall lot on University Avenue,
## the big stores beside it, UPEI's quad and the farmers' market.
const SPOTS := [
	["downtown", 0.0, 60.0],
	["grafton", 260.0, -480.0],
	["mall lot", -2140.0, -3115.0],
	["buymart", -2060.0, -2960.0],
	["upei", -1150.0, -2450.0],
	["farmers market", -760.0, -2160.0],
]
## The driving camera: a few metres up, looking a little down the road.
const LIFT := 3.5
const PITCH := -8.0
const FOV := 60.0

var _main: Node
var _world: Node
var _cam: Camera3D
var _secs := 10.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_secs = float(args.get("secs", "20"))
	var spots: Array = SPOTS
	if args.has("spots"):
		spots = []
		for s in str(args["spots"]).split(";", false):
			var p := s.split(":")
			var xz := p[1].split_floats(",")
			spots.append([p[0], xz[0], xz[1]])
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
	var g: Node = root.get_node("Graphics")
	var level: int = g.level
	var budget: int = g.DRAW_CALL_BUDGET[level]
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 900.0
	root.add_child(_cam)
	var fails := 0
	for s: Array in spots:
		var r := await _spot(str(s[0]), Vector2(s[1], s[2]), args.has("why"))
		var over: bool = int(r["calls"]) > budget
		print("VIEW%s %-16s %s  calls=%d (shadows %d) objects=%d tris=%.2fM worst heading %d  budget %d" % [
			" FAIL" if over else "", s[0], g.level_name(), r["calls"], r["shadows"], r["objects"], float(r["tris"]) / 1e6, r["yaw"], budget])
		if args.has("why"):
			for line: String in r["why"]:
				print("    " + line)
		if over:
			fails += 1
	print("VIEW %s" % ("all within budget" if fails == 0 else "%d spot(s) over budget" % fails))
	quit(1 if fails > 0 and args.has("budget") else 0)


## Streams the town in round `pos`, runs the streets for a while, and
## measures the four headings. Returns the worst.
func _spot(spot_name: String, pos: Vector2, why: bool) -> Dictionary:
	var player: Node3D = _main.get_node("Player")
	player.global_position = _world.terrain.at(pos, 0.5)
	_cam.global_position = _world.terrain.at(pos, LIFT)
	_cam.rotation = Vector3(deg_to_rad(PITCH), 0.0, 0.0)
	_cam.make_current()
	await _settle()
	# Under a tool the traffic and the people on foot stay idle; here
	# they're the point.
	for n in _main.get_children():
		if n is TrafficManager or n is PedestrianManager:
			n.set("running", true)
	# Let the traffic and the people on foot come out round the player.
	var t0 := Time.get_ticks_msec()
	var game := 0.0
	while game < _secs and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
		game += _main.get_process_delta_time()
	await _settle()
	var worst := {"calls": -1}
	for yaw in [0, 90, 180, 270]:
		_cam.rotation = Vector3(deg_to_rad(PITCH), deg_to_rad(yaw), 0.0)
		var m := await _measure()
		if int(m["calls"]) > int(worst["calls"]):
			worst = m
			worst["yaw"] = yaw
	if why:
		_cam.rotation = Vector3(deg_to_rad(PITCH), deg_to_rad(int(worst["yaw"])), 0.0)
		# Let the town catch up with the turn (it hides what's behind the
		# camera as it goes), then hold everything still, so the only change
		# between frames is what's hidden.
		await _measure()
		paused = true
		var still := await _measure()
		worst["why"] = await _why(int(still["calls"]))
		paused = false
	return worst


## Draws a couple of frames and reads what the last one drew.
func _measure() -> Dictionary:
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport_rid()
	var out := {
		"calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"tris": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"shadows": RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}
	RenderingServer.render_loop_enabled = false
	return out


## What each kind of thing costs: hidden in turn, the frame drawn again.
func _why(total: int) -> Array[String]:
	var groups := {}
	_group(_main, groups)
	var rows: Array = []
	_main.visible = false
	var bare := await _measure()
	_main.visible = true
	rows.append([int(bare["calls"]), "(drawn with the whole scene hidden)", 0])
	rows.append([total, "(the frame, held still)", 0])
	# What's drawn outside the 3D scene: the HUD, menus and overlays, by
	# canvas layer (a CanvasLayer's own visible hides all of it).
	for layer in _canvas_layers(root):
		if not layer.visible:
			continue
		layer.visible = false
		var m := await _measure()
		layer.visible = true
		if total - int(m["calls"]) < 3:
			continue
		rows.append([total - int(m["calls"]), "2D: %s" % layer.get_path(), 0])
		if total - int(m["calls"]) < 20:
			continue
		for c in layer.get_children():
			if c is CanvasItem and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				var mc := await _measure()
				(c as CanvasItem).visible = true
				if total - int(mc["calls"]) >= 5:
					rows.append([total - int(mc["calls"]), "2D: %s/%s" % [layer.name, c.name], 0])
	for k: String in groups:
		var nodes: Array = groups[k]
		var was := nodes.map(func(n: Node3D) -> bool: return n.visible)
		for n: Node3D in nodes:
			n.visible = false
		var m := await _measure()
		for i in nodes.size():
			(nodes[i] as Node3D).visible = was[i]
		var d := total - int(m["calls"])
		if d > 0:
			rows.append([d, k, nodes.size()])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[String] = []
	for r: Array in rows:
		out.append("%-48s calls=%4d  (%d nodes)" % [r[1], r[0], r[2]])
	return out


func _canvas_layers(n: Node) -> Array[CanvasLayer]:
	var out: Array[CanvasLayer] = []
	for c in n.get_children():
		if c is CanvasLayer:
			out.append(c)
		out.append_array(_canvas_layers(c))
	return out


## Sorts what draws into kinds: in a chunk, by its kind of prop (its
## "label", or its name without the tile); outside the chunks, by the
## node under the scene's root (the traffic, the people on foot, the
## player...).
func _group(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if not c is Node3D:
			continue
		var nm := str(c.name)
		if n == _main and nm != "World":
			_add(out, _kind(nm), c)
		elif nm.begins_with("Near_"):
			_add(out, "= all the full-detail chunks", c)
			_chunk_parts(c, "near ", out)
		elif nm.begins_with("Far_"):
			_add(out, "distant town (Far chunks)", c)
		elif nm == "World" or nm == "Chunks":
			_group(c, out)
		elif c.get_child_count() > 5:
			# A manager (traffic, people on foot): by what it holds.
			for k in c.get_children():
				if k is Node3D:
					_add(out, "%s/%s" % [nm, _kind(str(k.name))], k)
		else:
			_add(out, _kind(nm), c)


func _chunk_parts(n: Node, prefix: String, out: Dictionary) -> void:
	for c in n.get_children():
		if not c is Node3D:
			continue
		if c is GeometryInstance3D or c.get_child_count() == 0:
			_add(out, prefix + _kind(str(c.get_meta("label", c.name))), c)
		elif str(c.name) in ["StreetProps", "Streets", "Buildings"] or prefix.count("/") < 1:
			_chunk_parts(c, prefix + str(c.name) + "/", out)
		else:
			_add(out, prefix + _kind(str(c.name)), c)


## A name without its numbers (tiles, instance counters).
func _kind(nm: String) -> String:
	var re := RegEx.create_from_string("(_t)?-?\\d+(_-?\\d+)*|@")
	return re.sub(nm, "", true)


func _add(out: Dictionary, key: String, n: Node) -> void:
	if not out.has(key):
		out[key] = []
	(out[key] as Array).append(n)


## Waits, nothing drawn, until every chunk round the camera is built.
func _settle() -> void:
	var st: Node = _world.streamer
	st.refresh()
	var t0 := Time.get_ticks_msec()
	var last := t0
	while not st.is_settled():
		await process_frame
		var now := Time.get_ticks_msec()
		if now - last > 100:
			last = now
			st.refresh()
		if now - t0 > 180000:
			print("VIEW gave up waiting for the town after 180 s")
			return
	await process_frame

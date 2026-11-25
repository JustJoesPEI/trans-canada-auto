extends SceneTree
## Checks the native library (native/README.md) against its GDScript twins,
## in the real town with traffic about, and times both:
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/native_check.gd -- [--secs=30]
##
## Every physics step, for every car with physics, each native function is
## asked the same thing as its GDScript twin and the answers must match
## exactly. Fails (exit code 1) on any difference, or if the library isn't
## loaded. Prints "NATIVE ..." lines.

var _main: Node
var _world: WorldBuilder
var _cam := Camera3D.new()
var _calls := 0
var _diffs := 0
var _first_diff := ""
var _us_native := 0
var _us_gd := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var secs := 30.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
	if not ClassDB.class_exists("TcaWheels"):
		print("NATIVE FAIL: the library isn't loaded (build it: native/README.md)")
		quit(1)
		return
	TrafficManager.autostart = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	var net := _world.network
	var player: Node3D = _main.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.remove_from_group(RoadUsers.PEOPLE_GROUP)
	var corner := ""
	var best_d := INF
	for nid: String in net.signal_nodes:
		var d := (net.nodes[nid] as Vector2).length()
		if d < best_d:
			best_d = d
			corner = nid
	var cp: Vector2 = net.nodes[corner]
	var eye := Vector3(cp.x, _world.terrain.h2(cp) + 1.7, cp.y)
	root.add_child(_cam)
	_cam.global_position = eye
	_cam.make_current()
	_world.streamer._focus = cp
	await _world.wait_until_settled()
	var tm: TrafficManager = _main.get_node("Traffic")
	tm.focus = eye
	tm.running = true
	physics_frame.connect(_step)
	var t := 0.0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	physics_frame.disconnect(_step)
	print("NATIVE wheel probe: %d calls compared, %d different%s" % [_calls, _diffs, (" (first: %s)" % _first_diff) if _diffs > 0 else ""])
	print("NATIVE wheel probe time: native %.1f us a call, GDScript %.1f us (%.1fx)" % [
		_us_native / maxf(_calls, 1.0), _us_gd / maxf(_calls, 1.0), float(_us_gd) / maxf(_us_native, 1.0)])
	var ok := _diffs == 0 and _calls > 100
	print("NATIVE %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)


func _step() -> void:
	for n: Node in get_nodes_in_group("vehicles"):
		var car := n as Car
		if car == null or car.freeze or car._p_mounts.size() != car._n or car._n == 0:
			continue
		var space := car.get_world_3d().direct_space_state
		var xf := car.global_transform
		var u0 := Time.get_ticks_usec()
		var a: Array = ClassDB.class_call_static("TcaWheels", "probe", space, car._ray, xf, car._p_mounts, car._p_half, car._p_reach, car._p_skip, Layers.GROUND)
		var u1 := Time.get_ticks_usec()
		var b: Array = WheelProbe.probe_gd(space, car._ray, xf, car._p_mounts, car._p_half, car._p_reach, car._p_skip)
		var u2 := Time.get_ticks_usec()
		_us_native += u1 - u0
		_us_gd += u2 - u1
		_calls += 1
		var diff := _compare(a, b)
		if diff != "":
			_diffs += 1
			if _first_diff == "":
				_first_diff = "%s: %s" % [car.name, diff]


func _compare(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "%d wheels against %d" % [a.size(), b.size()]
	for i in a.size():
		if (a[i] == null) != (b[i] == null):
			return "wheel %d: %s against %s" % [i, a[i], b[i]]
		if a[i] == null:
			continue
		var ha: Dictionary = a[i]
		var hb: Dictionary = b[i]
		for k: String in ["position", "normal", "collider", "shape"]:
			if ha.get(k) != hb.get(k):
				return "wheel %d %s: %s against %s" % [i, k, ha.get(k), hb.get(k)]
	return ""

extends SceneTree
## Watches the people on foot downtown (PedestrianManager) for glitches, and
## runs one ride (RideFares) from hail to pay:
##
##   godot --headless --path . --script res://tools/pedestrian_check.gd -- [--secs=90] [--no-ride]
##
## With a screen (not --headless), --shot=DIR also saves pictures of the
## nearest few people to DIR (shot_1.png ...) after the watch.
##
## Every physics step it looks at each person for jumps (moving further
## than they could), walking in the road when they aren't crossing, being
## stuck, and being placed or taken away where the camera could see. It
## counts crossings, chats, thoughts and dodges, and lists the states they
## spent their time in. Then (unless --no-ride) it puts the player in a car,
## has someone hail it, pulls up, drives them (by teleport) to their place
## and checks they got in, got out and paid. One "PEDS" line per result;
## it fails (exit code 1) on a broken ride or people walking in the road.

var _main: Node
var _world: WorldBuilder
var _cam := Camera3D.new()
var _t := 0.0
var _prev := {} ## Pedestrian -> [position, state]
var _issues := {} ## kind -> [count, first example]
var _states := {} ## state name -> seconds
var _crossings := 0
var _chats := 0
var _thoughts := 0
var _road_t := 0.0
var _still := {} ## Pedestrian -> [where, since]
var _fail := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var secs := 90.0
	var ride := true
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a == "--no-ride":
			ride = false
		elif a.begins_with("--shot="):
			shots = a.trim_prefix("--shot=")
	TrafficManager.autostart = false
	PedestrianManager.autostart = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	while _main.get_node_or_null("Pedestrians") == null:
		await process_frame
	var net := _world.network
	var player: Node3D = _main.get_node("Player")
	root.add_child(_cam)
	_cam.make_current()
	var corner := ""
	var best_d := INF
	for nid: String in net.signal_nodes:
		var d := (net.nodes[nid] as Vector2).length()
		if d < best_d:
			best_d = d
			corner = nid
	var cp: Vector2 = net.nodes[corner]
	var eye := Vector3(cp.x, _world.terrain.h2(cp) + 1.7, cp.y)
	_cam.global_position = eye
	player.place(Transform3D(Basis.IDENTITY, eye - Vector3.UP * 1.6))
	await _load_streets(cp, 220.0)
	var tm: TrafficManager = _main.get_node("Traffic")
	tm.focus = eye
	tm.running = true
	var pm: PedestrianManager = _main.get_node("Pedestrians")
	pm.focus = eye
	pm.running = true
	physics_frame.connect(_step.bind(pm))
	var most := 0
	while _t < secs:
		await process_frame
		most = maxi(most, pm.people.size())
		# Look round now and then, so placing and taking away out of sight
		# is tested from every side.
		if shots == "":
			_cam.rotation.y = fmod(_t * 0.15, TAU)
	print("PEDS people: most %d at once (want %d), placed %d, taken away %d" % [most, pm._target(eye), pm.placed, pm.removed])
	var st := []
	for k: String in _states:
		st.append("%s %.0f%%" % [k, 100.0 * _states[k] / maxf(_total_state(), 0.001)])
	print("PEDS time spent: " + ", ".join(st))
	print("PEDS crossings %d, chats %d, thoughts %d, dodges %d" % [_crossings, _chats, _thoughts, pm.dodges])
	for k: String in _issues:
		print("PEDS ISSUE %s: %d (first: %s)" % [k, _issues[k][0], _issues[k][1]])
	if _issues.has("in the road") and int(_issues["in the road"][0]) > 3:
		_fail = true
	if shots != "":
		await _shots(pm, shots)
	if ride:
		await _ride(pm, player)
	print("PEDS %s" % ("FAIL" if _fail else "OK"))
	quit(1 if _fail else 0)


## Pictures of the three people nearest the camera, from a few metres off.
func _shots(pm: PedestrianManager, dir: String) -> void:
	var list := pm.people.duplicate()
	list.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool:
		return a.global_position.distance_to(_cam.global_position) < b.global_position.distance_to(_cam.global_position))
	for i in mini(3, list.size()):
		var p: Pedestrian = list[i]
		if i == 0:
			p.think("Did I leave the stove on?")
		var f := -p.global_basis.z
		_cam.global_position = p.global_position + f * 6.0 + Vector3.UP * 2.2 + p.global_basis.x * 2.0
		_cam.look_at(p.global_position + Vector3.UP * 1.3)
		for k in 8:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/shot_%d.png" % [dir, i + 1]
		img.save_png(path)
		print("PEDS shot %s: %s (%s, %s)" % [path, p.name, p.kind, Pedestrian.State.keys()[p.state]])


func _total_state() -> float:
	var s := 0.0
	for k: String in _states:
		s += _states[k]
	return s


func _ride(pm: PedestrianManager, player: Node3D) -> void:
	var fares := pm.fares
	# A car beside the curb, 60 m from someone walking.
	var who: Pedestrian = null
	for p: Pedestrian in pm.people:
		if p.state == Pedestrian.State.WALK and p.kind != "jogger" and not p.in_road():
			who = p
			break
	if who == null:
		print("PEDS RIDE: nobody walking to hail")
		_fail = true
		return
	var hit := pm.net.nearest_on_streets(who.position2(), 40.0)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along := clampf(float(hit["along"]) + 60.0, 5.0, e.length - 5.0)
	var s: Array = RoadNetwork.sample(e.points, along)
	var car := Car.new()
	car.model_id = "civique"
	_main.add_child(car)
	var at: Vector2 = s[0]
	var dir: Vector2 = s[1]
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(at.x, _world.terrain.h2(at) + 0.6, at.y))
	car.reset_physics_interpolation()
	player.enter_vehicle(car)
	for i in 30:
		await physics_frame
	fares._hail_in = 0.0
	# Only `who` can hail: everyone else is busy for a moment.
	for p: Pedestrian in pm.people:
		if p != who:
			p.fare = {"busy": true}
	who.global_position = who.global_position # (stays where it is)
	var t0 := _t
	while fares.hailer == null and _t - t0 < 10.0:
		car.global_position = Vector3(who.global_position.x, car.global_position.y, who.global_position.z) + (car.global_basis.z * 60.0)
		await physics_frame
	for p: Pedestrian in pm.people:
		if p.fare.has("busy"):
			p.fare = {}
	if fares.hailer == null:
		print("PEDS RIDE: nobody hailed")
		_fail = true
		return
	var h := fares.hailer
	print("PEDS RIDE: %s (%s) hails: \"%s\"" % [h.name, h.kind, h._label.text])
	# Pull up beside them and stop.
	var door_off := PassengerSeat.door_point(car) - car.global_position
	car.freeze = true
	car.global_position = h.global_position - door_off + Vector3.UP * 0.3
	car.reset_physics_interpolation()
	t0 = _t
	while fares.rider == null and _t - t0 < 10.0:
		await physics_frame
	if fares.rider == null:
		print("PEDS RIDE: they didn't get in (state %s)" % Pedestrian.State.keys()[h.state])
		_fail = true
		return
	print("PEDS RIDE: in the passenger seat: %s; says \"%s\"" % [h.get_parent().name, h._label.text])
	var gps := Gps.find(self)
	print("PEDS RIDE: GPS: %s, %.0f m" % [gps.place if gps != null else "none", gps.remaining if gps != null else 0.0])
	# There (the drive itself is the player's).
	var dest: Vector2 = h.fare["dest"]["street"]
	for i in 30:
		await physics_frame
	var gs := root.get_node("GameState")
	var money: int = gs.money
	car.global_position = Vector3(dest.x, _world.terrain.h2(dest) + 1.0, dest.y)
	car.reset_physics_interpolation()
	t0 = _t
	while fares.rider != null and _t - t0 < 5.0:
		await physics_frame
	if fares.rider != null:
		print("PEDS RIDE: didn't get out at the place")
		_fail = true
		return
	print("PEDS RIDE: out and paid %s (%d rides, %s made); says \"%s\"; now %s" % [CarModels.dollars(gs.money - money), fares.rides, CarModels.dollars(fares.earned), h._label.text, Pedestrian.State.keys()[h.state]])
	if gs.money <= money:
		_fail = true
	gs.add_money(money - gs.money) # leave the save as it was


func _load_streets(p: Vector2, radius: float) -> void:
	var s := _world.streamer
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		s._focus = p
		s._has_focus = true
		s._update()
		s._reap()
		s._attach_finished(4)
		var ready := true
		for c in s._cells_within(p, radius):
			if s._dist(c, p) <= radius and not s._near.has(c):
				ready = false
				break
		if ready:
			break
		OS.delay_msec(3)
	await _world.wait_until_settled()


func _issue(kind: String, text: String) -> void:
	if not _issues.has(kind):
		_issues[kind] = [0, text]
	_issues[kind][0] += 1


func _step(pm: PedestrianManager) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_t += dt
	_road_t -= dt
	var check_road := _road_t <= 0.0
	if check_road:
		_road_t = 0.5
	var net := pm.net
	for p: Pedestrian in pm.people:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var sname: String = Pedestrian.State.keys()[p.state]
		_states[sname] = float(_states.get(sname, 0.0)) + dt
		var pos := p.global_position
		if _prev.has(p):
			var was: Array = _prev[p]
			var moved := Vector2(pos.x, pos.z).distance_to(Vector2(was[0].x, was[0].z))
			if moved > 6.0 * dt + 0.05 and p.state != Pedestrian.State.RIDE and was[1] != Pedestrian.State.RIDE:
				_issue("jump", "%s %.2f m in a step at %s (%s)" % [p.name, moved, pos, sname])
			if absf(pos.y - was[0].y) > 0.5:
				_issue("height jump", "%s %.2f m at %s" % [p.name, pos.y - was[0].y, pos])
			if p._crossing and not was[2]:
				_crossings += 1
			if p.state == Pedestrian.State.CHAT and was[1] != Pedestrian.State.CHAT:
				_chats += 1
			if p.saying and not was[3] and p._label.modulate.b > p._label.modulate.r + 0.1:
				_thoughts += 1
		_prev[p] = [pos, p.state, p._crossing, p.saying]
		if check_road and p.state in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.CHAT] and not p.in_road():
			var hit := net.nearest_on_streets(Vector2(pos.x, pos.z), 20.0)
			if not hit.is_empty():
				var e: RoadNetwork.RoadEdge = hit["edge"]
				if float(hit["dist"]) < e.half_width - 0.6 and not e.minor:
					_issue("in the road", "%s %.1f m from the middle of %s (half width %.1f) at %s, %s" % [p.name, hit["dist"], e.name, e.half_width, pos, sname])
		if check_road and p.state == Pedestrian.State.WALK:
			var s: Array = _still.get(p, [pos, _t])
			if pos.distance_to(s[0]) > 1.0:
				_still[p] = [pos, _t]
			elif _t - float(s[1]) > 30.0:
				_issue("stuck", "%s at %s" % [p.name, pos])
				_still[p] = [pos, _t]
			else:
				_still[p] = s

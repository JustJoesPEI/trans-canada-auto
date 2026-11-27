extends SceneTree
## Runs the Island Boo-Boo Bus and the Island Wee-Woo Brigade downtown
## (EmergencyServices) and checks they do their jobs:
##
##   godot --headless --path . --script res://tools/emergency_check.gd -- [--secs=150]
##
## With a screen (not --headless), --shot=DIR saves pictures along the way
## (struck.png, scene_N.png, hosed.png).
##
## It drives the player's car into someone on the sidewalk (they should be
## thrown and lie there; the wanted level goes to 1), paints someone else
## three times (down too), and watches: the call, a Boo-Boo Bus out of
## sight and on its way, its paramedics seeing to both and patching them
## up, the Brigade if it comes, and everyone leaving. Then it stalls one of
## the player's cars with police paint and leaves it: the Brigade should
## hose it down. Then a truck going by on another call. One "EMS" line per
## result; it fails (exit code 1) if nobody's hit, nobody comes, or
## nobody's seen to.

var _main: Node
var _world: WorldBuilder
var _cam := Camera3D.new()
var _fail := false
var _shots := ""
var _shot_n := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var secs := 150.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--shot="):
			_shots = a.trim_prefix("--shot=")
	TrafficManager.autostart = false
	PedestrianManager.autostart = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	while _main.get_node_or_null("EmergencyServices") == null:
		await process_frame
	var net := _world.network
	var player: Node3D = _main.get_node("Player")
	root.add_child(_cam)
	_cam.make_current()
	# Downtown: the signalled junction nearest the middle.
	var corner := ""
	var best_d := INF
	for nid: String in net.signal_nodes:
		var d := (net.nodes[nid] as Vector2).length()
		if d < best_d:
			best_d = d
			corner = nid
	var cp: Vector2 = net.nodes[corner]
	var eye := Vector3(cp.x, _world.terrain.h2(cp) + 1.7, cp.y)
	player.place(Transform3D(Basis.IDENTITY, eye - Vector3.UP * 1.6))
	_cam.global_position = eye + Vector3(0.0, 6.0, 8.0)
	await _load_streets(cp, 230.0)
	var tm: TrafficManager = _main.get_node("Traffic")
	tm.running = true
	var pm: PedestrianManager = _main.get_node("Pedestrians")
	pm.running = true
	var es: EmergencyServices = _main.get_node("EmergencyServices")
	es.running = true
	es._ambient_t = 1.0e9 # (the passing truck is tested at the end)
	var wanted := root.get_node_or_null("Wanted")
	# People about first.
	var t := 0.0
	while t < 25.0 and pm.people.size() < 8:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	print("EMS people about: %d" % pm.people.size())
	if OS.get_cmdline_user_args().has("--wanted-only"):
		# For comparing hitches: the same wanted level from an ordinary crime.
		wanted.call("report_crime", "paint_bystander", player.global_position)
		for i in 600:
			await physics_frame
		_finish(false)
		return
	# 1. The player's car into someone walking.
	var victim := _walker(pm, player.global_position, [])
	if victim == null:
		print("EMS FAIL nobody walking to hit")
		_finish(true)
		return
	var car := Car.new()
	car.model_id = "civique"
	car.paint = Color(0.6, 0.1, 0.1)
	car.owner_id = "local"
	_main.add_child(car)
	var vp := victim.global_position
	var h := victim._heading
	var at := vp - Vector3(h.x, 0.0, h.y) * 6.0
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-h.x, -h.y)), at + Vector3.UP * 0.6)
	car.reset_physics_interpolation()
	var cars: Variant = _main.get("cars")
	if cars is Array:
		(cars as Array).append(car)
	await physics_frame
	player.call("enter_vehicle", car)
	await physics_frame
	victim.reaction = 5.0 # (looking at their phone: they don't see it coming)
	var no_strike := OS.get_cmdline_user_args().has("--no-strike")
	for i in 40:
		if no_strike:
			break
		car.linear_velocity = -car.global_basis.z * 11.0
		await physics_frame
		if victim.state == Pedestrian.State.DOWN:
			break
	print("EMS struck: %s (state %s, kind '%s'), wanted level %d" % [victim.state == Pedestrian.State.DOWN and victim.down_kind == "struck",
		Pedestrian.State.keys()[victim.state], victim.down_kind, int(wanted.get("level")) if wanted != null else -1])
	if victim.state != Pedestrian.State.DOWN:
		_fail = true
	car.linear_velocity = Vector3.ZERO
	player.call("exit_vehicle", _main)
	_cam.global_position = victim.global_position + Vector3(6.0, 4.0, 6.0)
	_cam.look_at(victim.global_position)
	await _shot("struck")
	if OS.get_cmdline_user_args().has("--time-hit"):
		# Frame by frame for ten seconds after the hit: the slow ones.
		var last := Time.get_ticks_usec()
		for i in 600:
			await process_frame
			var now := Time.get_ticks_usec()
			if now - last > 150000:
				print("EMS slow frame %.0f ms at %d: units %d, pending %d, victim %s phase %d" % [(now - last) / 1000.0, i, es.units.size(), es._pending.size(),
					Pedestrian.State.keys()[victim.state], victim.down_phase])
			last = now
		_finish(false)
		return
	# 2. Someone else painted out.
	var painted := _walker(pm, victim.global_position, [victim], 60.0)
	if painted != null:
		for i in 3:
			painted.take_paint_hit(1, player, painted.global_position + Vector3.UP * 1.1)
		print("EMS painted out: %s" % (painted.state == Pedestrian.State.DOWN and painted.down_kind == "painted"))
	# 3. Watch the call.
	var sent_at := -1.0
	var arrived_at := -1.0
	var brigade := false
	var lines := {}
	t = 0.0
	var scene_shots := 0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		for u: EmergencyUnit in es.units:
			if u.kind == "iwwb":
				brigade = true
			if sent_at < 0.0 and u.kind == "ibbb":
				sent_at = t
				print("EMS bus sent at %.0f s, from %.0f m away" % [t, u.car.global_position.distance_to(victim.global_position) if u.car != null else -1.0])
			if arrived_at < 0.0 and u.kind == "ibbb" and u.step == EmergencyUnit.Step.SCENE:
				arrived_at = t
				print("EMS bus on scene at %.0f s" % t)
			for r: Responder in u.crew:
				if is_instance_valid(r) and r._label.visible and not lines.has(r._label.text):
					lines[r._label.text] = true
					print("EMS   %s: %s" % [r.role, r._label.text])
		if arrived_at > 0.0 and scene_shots < 3 and int(t) % 8 == 0 and _shots != "":
			scene_shots += 1
			var u0: EmergencyUnit = es.units[0] if es.units.size() > 0 else null
			if u0 != null and u0.car != null:
				_cam.global_position = u0.scene + Vector3(7.0, 4.0, 7.0)
				_cam.look_at(u0.scene + Vector3.UP)
				await _shot("scene_%d" % scene_shots)
		var done := es.treated >= (2 if painted != null else 1)
		if done and es.units.filter(func(u: EmergencyUnit) -> bool: return u.job != "ambient" and u.step != EmergencyUnit.Step.LEAVE).is_empty():
			break
	print("EMS treated %d, sent %s, brigade came: %s, calls %d" % [es.treated, str(es.sent), brigade, es.calls])
	print("EMS patients now: %s %s" % [_desc(victim), _desc(painted)])
	if sent_at < 0.0 or arrived_at < 0.0 or es.treated == 0:
		_fail = true
	# 4. The player's own car, stalled by police paint and left.
	var mine := Car.new()
	mine.model_id = "pious"
	mine.paint = Color(0.2, 0.3, 0.6)
	mine.owner_id = "local"
	_main.add_child(mine)
	var street := net.nearest_on_streets(Vector2(player.global_position.x, player.global_position.z) + Vector2(30.0, 0.0), 60.0)
	var sp: Vector2 = street["pos"] if not street.is_empty() else Vector2(player.global_position.x + 30.0, player.global_position.z)
	mine.global_transform = Transform3D(Basis.IDENTITY, Vector3(sp.x, _world.terrain.h2(sp) + 0.6, sp.y))
	mine.reset_physics_interpolation()
	if wanted != null:
		wanted.call("clear")
	await physics_frame
	PaintCoverage.of(mine).add_coverage(1.0, Vector3.ZERO, PaintWeapons.POLICE_COLOUR, true)
	for i in 30:
		await physics_frame
	print("EMS own car stalled: %s" % mine.stalled)
	t = 0.0
	var engine_sent := -1.0
	while t < 120.0 and es.hosed_cars == 0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if engine_sent < 0.0 and es.units.any(func(u: EmergencyUnit) -> bool: return u.job == "car"):
			engine_sent = t
			print("EMS engine sent for the car at %.0f s" % t)
	print("EMS own car hosed down: %s after %.0f s, stalled now: %s" % [es.hosed_cars > 0, t, mine.stalled])
	if es.hosed_cars > 0:
		_cam.global_position = mine.global_position + Vector3(8.0, 4.0, 8.0)
		_cam.look_at(mine.global_position)
		await _shot("hosed")
	# 5. A truck going by on another call.
	es._ambient_t = 0.0
	t = 0.0
	var passing := false
	while t < 20.0 and not passing:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		for u: EmergencyUnit in es.units:
			if u.job == "ambient":
				passing = true
	print("EMS one going by on another call: %s" % passing)
	_finish(_fail)


func _desc(p: Pedestrian) -> String:
	if p == null or not is_instance_valid(p):
		return "(gone)"
	return "[%s %s patch '%s']" % [Pedestrian.State.keys()[p.state], p.down_kind, p.patch]


## Someone walking on the sidewalk near `near`, not one of `not_these`.
func _walker(pm: PedestrianManager, near: Vector3, not_these: Array, within := 120.0) -> Pedestrian:
	var best: Pedestrian = null
	var best_d := within
	for p: Pedestrian in pm.people:
		if not is_instance_valid(p) or not_these.has(p) or p.state != Pedestrian.State.WALK or p.leader != null or p.companion != null:
			continue
		var d := p.global_position.distance_to(near)
		if d < best_d:
			best_d = d
			best = p
	return best


func _shot(name_: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	for i in 4:
		await process_frame
	DirAccess.make_dir_recursive_absolute(_shots)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name_])
	_shot_n += 1


func _finish(fail: bool) -> void:
	print("EMS %s" % ("FAIL" if fail else "ok"))
	quit(1 if fail else 0)


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

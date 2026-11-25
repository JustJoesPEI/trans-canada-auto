extends SceneTree
## Watches town traffic for glitches and the frame time for hitches, in the
## real town, downtown:
##
##   godot --headless --path . --script res://tools/traffic_watch.gd -- [--secs=90] [--trace=Traffic_pious_3]
##
## (Leave out --fixed-fps to time frames as they really run; with
## --fixed-fps 60 a run is the same every time, for following one car.)
##
## Every physics step it looks at each traffic car with physics for a body
## stretched or squashed, tipped past 60 degrees, spinning, under the ground
## or high in the air, jumping further than its speed allows, a velocity
## change too sudden for its tyres, and tyres sliding (what makes them
## squeal), sorted by what the car was doing. Far-off cars (RoadFollower)
## are checked for jumps and snapped headings. It counts the car sounds
## playing, notes each crash, and lists every frame over 40 ms with what
## happened just before it. --trace prints one car's state each step, with
## the car nearest it. One "WATCH" line per result; it doesn't fail.

var _main: Node
var _world: WorldBuilder
var _cam := Camera3D.new()
var _t := 0.0
var _trace := ""
var _prev := {} ## Car or follower id -> [position, velocity, basis]
var _issues := {} ## kind -> [count, first example]
var _frame_us: Array[int] = []
var _events: Array = [] ## [time, text]
var _cars_seen := {} ## Car -> time first seen
var _voices_max := 0
var _voices_sum := 0.0
var _steps := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var secs := 90.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--trace="):
			_trace = a.trim_prefix("--trace=")
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
	root.add_child(_cam)
	_cam.make_current()
	# The signalled junction nearest the middle of town.
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
	await _load_streets(cp, 200.0)
	var tm: TrafficManager = _main.get_node("Traffic")
	tm.focus = eye
	tm.running = true
	physics_frame.connect(_step.bind(tm))
	var last := Time.get_ticks_usec()
	while _t < secs:
		await process_frame
		var now := Time.get_ticks_usec()
		_frame_us.append(now - last)
		if now - last > 40000:
			_events.append([_t, "HITCH %.0f ms (%d drivers)" % [(now - last) / 1000.0, tm.drivers.size()]])
		last = now
	_report(tm)
	quit()


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


func _step(tm: TrafficManager) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_t += dt
	var alive := {}
	var voices := 0
	for d: TrafficDriver in tm.drivers:
		var car := d.car
		if car == null or not is_instance_valid(car):
			continue
		alive[car] = true
		if not _cars_seen.has(car):
			_cars_seen[car] = _t
			_events.append([_t, "%s placed" % car.name])
			car.crashed.connect(func(j: float) -> void:
				_events.append([_t, "CRASH %s, jolt %.1f m/s at %s" % [car.name, j, car.global_position]]))
		_check_car(d, car, dt)
		for a in car.find_children("*", "AudioStreamPlayer3D", true, false):
			if (a as AudioStreamPlayer3D).playing:
				voices += 1
	for k: Variant in _prev.keys():
		if typeof(k) == TYPE_OBJECT and (not is_instance_valid(k) or not alive.has(k)):
			_prev.erase(k)
	for d: TrafficDriver in tm.drivers:
		if d.follower != null and is_instance_valid(d.follower):
			_check_follower(d, d.follower, dt)
	_voices_max = maxi(_voices_max, voices)
	_voices_sum += voices
	_steps += 1


func _check_car(d: TrafficDriver, car: Car, dt: float) -> void:
	var b := car.global_basis
	var p := car.global_position
	var v := car.linear_velocity
	var where := "%s at (%.0f, %.0f), t=%.1f" % [car.name, p.x, p.z, _t]
	var sc := b.get_scale()
	if absf(sc.x - 1.0) > 0.02 or absf(sc.y - 1.0) > 0.02 or absf(sc.z - 1.0) > 0.02:
		_issue("body stretched or squashed", "%s, scale %s" % [where, sc])
	if b.y.y < 0.5:
		_issue("tipped past 60 degrees", where)
	if car.angular_velocity.length() > 4.0:
		_issue("spinning over 4 rad/s", "%s, %s rad/s" % [where, car.angular_velocity])
	var gy := _world.terrain.h2(Vector2(p.x, p.z))
	if p.y < gy - 1.0:
		_issue("below the ground", "%s, %.1f m under" % [where, gy - p.y])
	if p.y > gy + 4.0 and car.wheels_down == 0:
		_issue("in the air over 4 m up", where)
	if _prev.has(car):
		var pr: Array = _prev[car]
		var moved := p.distance_to(pr[0])
		var expect := ((pr[1] as Vector3).length() + v.length()) * 0.5 * dt
		if moved > expect + 0.5:
			_issue("jumped", "%s, %.2f m in a step (speed allows %.2f)" % [where, moved, expect])
		var dv := (v - (pr[1] as Vector3)).length()
		if dv > 4.0:
			_issue("velocity changed over 4 m/s in a step", "%s, %.1f m/s" % [where, dv])
		if (pr[2] as Basis).get_rotation_quaternion().angle_to(b.get_rotation_quaternion()) > 0.15:
			_issue("turned over 8 degrees in a step", where)
	_prev[car] = [p, v, b]
	if car.skid > 0.25:
		var why := "just placed" if _t - float(_cars_seen[car]) < 1.5 else ("braking" if car._brake > 0.3 else ("turning" if absf(car.steer_angle) > 0.05 else "going straight"))
		_issue("tyres sliding (skid > 0.25), " + why, "%s, skid %.2f at %.0f km/h" % [where, car.skid, v.length() * 3.6])
	if car.name == _trace:
		var nearest := ""
		var nd := INF
		for o in _main.get_children():
			if o is Car and o != car and (o as Car).global_position.distance_to(p) < nd:
				nd = (o as Car).global_position.distance_to(p)
				nearest = "%s %.1f m off" % [o.name, nd]
		print("WATCH trace t=%.2f at (%.1f, %.2f, %.1f) %.1f km/h spin %s up %.2f skid %.2f brake %.2f throttle %.2f steer %.2f wheels down %d, %s; nearest %s" % [
			_t, p.x, p.y, p.z, v.length() * 3.6, car.angular_velocity, b.y.y, car.skid, car._brake,
			car.throttle_input(), car.steer_angle, car.wheels_down, d.pilot.state if d.pilot != null else "-", nearest])


func _check_follower(d: TrafficDriver, f: RoadFollower, dt: float) -> void:
	var key := f.get_instance_id()
	var p := f.global_position
	if _prev.has(key):
		var pr: Array = _prev[key]
		var moved := p.distance_to(pr[0])
		var where := "%s %d (far) at (%.0f, %.0f), t=%.1f" % [d.model_id, d.id, p.x, p.z, _t]
		if moved > f.speed * dt + 1.0:
			_issue("far car jumped", "%s, %.1f m" % [where, moved])
		if (pr[2] as Basis).get_rotation_quaternion().angle_to(f.global_basis.get_rotation_quaternion()) > 0.25:
			_issue("far car's heading snapped over 14 degrees", "%s at %.0f km/h" % [where, f.speed * 3.6])
	_prev[key] = [p, Vector3.ZERO, f.global_basis]


func _report(tm: TrafficManager) -> void:
	var ft := _frame_us.duplicate()
	ft.sort()
	var n := ft.size()
	var over := 0
	for us in ft:
		if us > 50000:
			over += 1
	print("WATCH frames %d: %.1f ms typical, %.1f at the 99th percentile, worst %.1f; %d over 50 ms" % [
		n, ft[n / 2] / 1000.0, ft[int(n * 0.99)] / 1000.0, ft[n - 1] / 1000.0, over])
	print("WATCH traffic: %d drivers (most %d), %d cars with physics in all; car sounds playing: up to %d, %.1f on average" % [
		tm.drivers.size(), tm.most, _cars_seen.size(), _voices_max, _voices_sum / maxf(1.0, _steps)])
	for e: Array in _events:
		if str(e[1]).begins_with("CRASH"):
			print("WATCH t=%.1f %s" % e)
		elif str(e[1]).begins_with("HITCH"):
			var before: Array = []
			for e2: Array in _events:
				if float(e2[0]) > float(e[0]) - 0.5 and float(e2[0]) <= float(e[0]) and not str(e2[1]).begins_with("HITCH"):
					before.append(e2[1])
			print("WATCH t=%.1f %s, after: %s" % [e[0], e[1], ", ".join(before) if not before.is_empty() else "nothing in the traffic"])
	if _issues.is_empty():
		print("WATCH no glitches")
	for k: String in _issues:
		print("WATCH %s: %d steps, first: %s" % [k, _issues[k][0], _issues[k][1]])

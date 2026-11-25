extends "res://tools/traffic_check.gd"
## Pictures of traffic doing things, for checking how it looks (the
## things a headless check can't judge). Stages each scene with the same
## helpers as traffic_check.gd, runs it without drawing, and draws only the
## frames it saves:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --path . \
##       --resolution 1280x720 --fixed-fps 60 --script res://tools/traffic_look.gd -- [--only=a,b] [--dir=/tmp/tca-shots]
##
## (on a machine with a screen, leave out xvfb-run). Scenes:
##   swap      a far car coming down a long street, just before and just
##             after it turns from a follower into a real car
##   bridge    a far car crossing a bridge
##   pullover  a car pulling over for a siren on a street with parked cars
##   pass      a car going round one stopped in its lane
##   out       a painted car's driver out staring at it, then complaining
##             when it's taken
##   driveway  a car turning into its driveway
## Each picture is saved as DIR/traffic_<scene>_<n>.png.

var _dir := "/tmp/tca-shots"


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_dir = str(args.get("dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var only: Array = str(args.get("only", "swap,bridge,pullover,pass,out,driveway")).split(",")
	RenderingServer.render_loop_enabled = false
	TrafficManager.autostart = false
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
	_net = _world.network
	_rules = JunctionRules.of(_net, _world.data)
	var player: Node3D = _main.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.remove_from_group(RoadUsers.PEOPLE_GROUP)
	_police = _main.get_node_or_null("Police") as PoliceDispatcher
	if _police != null:
		_police.patrols = false
		for u in _police.units.duplicate():
			_police.drop_unit(u)
	_cam.fov = 60.0
	_cam.far = 3000.0
	root.add_child(_cam)
	_cam.make_current()
	physics_frame.connect(_track_look)
	await _wait(0.5)
	for scene: String in ["swap", "bridge", "pullover", "pass", "out", "driveway"]:
		if scene in only:
			await call("_look_%s" % scene)
	print("LOOK done")
	quit(0)


func _track_look() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	if _hold_clock >= 0.0:
		TrafficSignal.clock = _hold_clock
	if _focus != null and is_instance_valid(_focus):
		_hold_for_streets(Vector2(_focus.global_position.x, _focus.global_position.z))


## The camera at `eye` looking at `at`; draws and saves a picture.
func _snap(scene: String, n: int, eye: Vector3, at: Vector3, note := "") -> void:
	_cam.global_position = eye
	_cam.look_at(at, Vector3.UP)
	_hold_for_streets(Vector2(eye.x, eye.z), 200.0)
	RenderingServer.render_loop_enabled = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := _dir.path_join("traffic_%s_%d.png" % [scene, n])
	root.get_texture().get_image().save_png(out)
	RenderingServer.render_loop_enabled = false
	print("LOOK %s %s" % [out, note])


func _chase_cam(car: Node3D, back := 9.0, up := 3.5) -> Array:
	var f := -car.global_basis.z
	return [car.global_position - f * back + Vector3.UP * up, car.global_position + f * 6.0 + Vector3.UP * 0.8]


func _long_straight(classes: Array, min_len: float, two_way := true) -> RoadNetwork.RoadEdge:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if (two_way and e.oneway != 0) or e.bridge or not _in_town(e) or not (e.highway in classes) or e.length < min_len:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.95 and (best == null or e.length > best.length):
			best = e
	return best


func _look_swap() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var e := _long_straight(["primary", "secondary", "trunk", "tertiary"], 320.0)
	if e == null:
		print("LOOK swap: no long street")
		return
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	# The camera at the far end looking back down the street; the car
	# comes toward it.
	var eye2 := r.sample(r.length - 10.0) + Vector2(-r.dir_at(r.length - 10.0).y, r.dir_at(r.length - 10.0).x) * 4.0
	var eye := _v3(eye2) + Vector3.UP * 1.8
	await _settle_at(eye2)
	tm.focus = eye
	var d := _traffic_on(tm, r, r.length - 175.0)
	_cam.global_position = eye
	var shots := 0
	while _t < 1e9 and shots < 3:
		await physics_frame
		var p := d.position()
		var dist := Vector2(p.x, p.z).distance_to(eye2)
		tm._physics_lod(eye2, TrafficDensity.level())
		if shots == 0 and dist < 158.0:
			await _snap("swap", 0, eye, p, "follower at %.0f m (%s)" % [dist, "car" if d.car != null else "follower"])
			shots = 1
		elif shots == 1 and d.car != null:
			await _snap("swap", 1, eye, d.position(), "just became a car at %.0f m" % dist)
			shots = 2
		elif shots == 2 and dist < 60.0:
			await _snap("swap", 2, eye, d.position(), "the car at %.0f m" % dist)
			shots = 3
		if d.state == TrafficDriver.State.GONE:
			break
	_clear_traffic(tm)


func _look_bridge() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.bridge and _in_town(e) and e.length > 40.0 and (best == null or e.length > best.length):
			best = e
	if best == null:
		print("LOOK bridge: no bridge")
		return
	var mid: Vector2 = RoadNetwork.sample(best.points, best.length * 0.5)[0]
	var r := StreetRoute.plan(_net, best.points[0] - (best.points[1] - best.points[0]).normalized() * 60.0, best.points[best.points.size() - 1] + (best.points[best.points.size() - 1] - best.points[best.points.size() - 2]).normalized() * 60.0, TrafficManager.plan_options(Vector2.ZERO))
	if r.is_empty():
		print("LOOK bridge: no route over %s" % best.name)
		return
	var side := Vector2(-(best.points[1] - best.points[0]).normalized().y, (best.points[1] - best.points[0]).normalized().x)
	var eye2 := mid + side * 60.0
	var eye := _v3(eye2) + Vector3.UP * 12.0
	await _settle_at(mid)
	tm.focus = Vector3(eye.x, eye.y, eye.z) + Vector3(side.x, 0, side.y) * 400.0 # far: it stays a follower
	var d := _traffic_on(tm, r, 0.0)
	var shot := false
	var t0 := _t
	while _t - t0 < 40.0 and not shot:
		await physics_frame
		var p := d.position()
		if p != Vector3.INF and Vector2(p.x, p.z).distance_to(mid) < 6.0:
			await _snap("bridge", 0, eye, p, "follower on %s at y %.1f (terrain %.1f)" % [best.name, p.y, _world.terrain.h2(Vector2(p.x, p.z))])
			shot = true
	_clear_traffic(tm)


func _look_pullover() -> void:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or e.length < 260.0 or not StreetRoute.curb_parking(e, 1):
			continue
		if best == null or e.length > best.length:
			best = e
	if best == null:
		print("LOOK pullover: no street with curb parking")
		return
	var line := StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(80.0))
	var me := _car("corollary", r.sample(70.0), r.dir_at(70.0))
	var cop := _car("jaunt", r.sample(20.0), r.dir_at(20.0), false, "cps")
	_focus = me
	await _wait(0.8)
	_ap(me).drive_route(r, 70.0, _v3(r.goal))
	await _wait(5.0)
	cop.police.set_mode(PoliceGear.Mode.SIREN)
	_ap(cop).cruise_speed_kmh = 70.0
	_ap(cop).drive_route(StreetRoute.along(line, {}), _ap(cop).along, _v3(r.goal))
	var n := 0
	var t0 := _t
	while _t - t0 < 20.0 and n < 2:
		await physics_frame
		var c := _ap(me).civil
		if n == 0 and c.lateral < -1.0:
			var v: Array = _chase_cam(me, 12.0, 4.0)
			await _snap("pullover", 0, v[0], v[1], "pulled %.1f m right at %.0f km/h, %s" % [-c.lateral, me.speed * 3.6, best.name])
			n = 1
		elif n == 1 and (cop.global_position - me.global_position).dot(-me.global_basis.z) > 2.0:
			var f := -me.global_basis.z
			await _snap("pullover", 1, me.global_position + f * 14.0 + me.global_basis.x * -3.0 + Vector3.UP * 2.0, me.global_position, "as the police car goes by")
			n = 2
	await _clear_cars([me, cop])


func _look_pass() -> void:
	var e := _long_straight(["residential", "tertiary", "unclassified"], 220.0)
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(90.0))
	var block := _car("haulux", r.sample(90.0), r.dir_at(90.0), false)
	var me := _car("civique", r.sample(40.0), r.dir_at(40.0))
	_focus = me
	await _wait(1.0)
	_ap(me).drive_route(r, 40.0, _v3(r.goal))
	var n := 0
	var t0 := _t
	while _t - t0 < 40.0 and n < 2:
		await physics_frame
		var c := _ap(me).civil
		if n == 0 and c.lateral > 1.2 and _ap(me).along > 80.0:
			var v: Array = _chase_cam(me, 10.0, 4.0)
			await _snap("pass", 0, v[0], v[1], "going round at %.1f m out, %.0f km/h" % [c.lateral, me.speed * 3.6])
			n = 1
		elif n == 1 and _ap(me).along > 100.0:
			var v: Array = _chase_cam(me, 10.0, 4.0)
			await _snap("pass", 1, v[0], v[1], "past it, lateral %.1f" % c.lateral)
			n = 2
	await _clear_cars([me, block])


func _look_out() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var e := _long_straight(["residential", "tertiary"], 250.0)
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	await _settle_at(r.sample(40.0))
	var d := _traffic_on(tm, r, 20.0)
	tm._to_car(d)
	var car := d.car
	_focus = car
	await _wait(6.0)
	d.rng.seed = 3 # one that gets out
	var shots := get_first_node_in_group("paint_shots")
	var t0 := _t
	while _t - t0 < 15.0 and d.state != TrafficDriver.State.OUT:
		if not d.getting_out and d.state == TrafficDriver.State.DRIVE:
			tm._on_paint_hit({"target": car, "point": car.global_position, "shooter": null, "kind": "car"})
		await physics_frame
	await _wait(1.5)
	if d.bystander != null:
		var b := d.bystander
		var side := (b.global_position - car.global_position).normalized()
		await _snap("out", 0, b.global_position + side * 5.0 + (-car.global_basis.z) * 4.0 + Vector3.UP * 1.7, b.global_position + Vector3.UP * 1.2, "staring: \"%s\"" % b._label.text)
	var player: Node3D = _main.get_node("Player")
	car.driver = player
	await _wait(1.2)
	for b: TrafficBystander in tm._bystanders:
		if is_instance_valid(b) and b.mode == TrafficBystander.Mode.COMPLAIN:
			var side := (b.global_position - car.global_position).normalized()
			await _snap("out", 1, b.global_position + side * 5.0 + (-car.global_basis.z) * 4.0 + Vector3.UP * 1.7, b.global_position + Vector3.UP * 1.2, "complaining: \"%s\"" % b._label.text)
	car.driver = null
	await _clear_cars([car])
	for b: TrafficBystander in tm._bystanders.duplicate():
		if is_instance_valid(b):
			b.queue_free()
	tm._bystanders.clear()


func _look_driveway() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	# A driveway on a residential street near the middle of town.
	var place := {}
	for pl: Dictionary in tm.dests.places:
		var s: Vector2 = pl["street"]
		var hit := _net.nearest_on_streets(s, 20.0)
		if hit.is_empty() or str(pl["kind"]) != "driveway" or (hit["edge"] as RoadNetwork.RoadEdge).highway != "residential" or s.length() > 900.0 or not _world.is_in_play_area(s):
			continue
		place = pl
		break
	if place.is_empty():
		print("LOOK driveway: none")
		return
	var s: Vector2 = place["street"]
	var hit := _net.nearest_on_streets(s, 20.0)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along: float = hit["along"]
	var fwd := e.oneway != -1
	var back := clampf(along - 70.0 if fwd else along + 70.0, 2.0, e.length - 2.0)
	var sp: Array = RoadNetwork.sample(e.points, back)
	var dir: Vector2 = (sp[1] as Vector2) * (1.0 if fwd else -1.0)
	var start: Vector2 = (sp[0] as Vector2) + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, fwd)
	await _settle_at(s)
	var r := StreetRoute.plan(_net, start, s, TrafficManager.plan_options(dir))
	var d := tm._new_driver(place)
	var rf := tm._make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(start)))
	rf.set_route(r)
	tm._to_car(d)
	_focus = d.car
	var t0 := _t
	var n := 0
	while _t - t0 < 50.0 and n < 2:
		await physics_frame
		if d.car == null:
			break
		if n == 0 and d.turned_in:
			var v: Array = _chase_cam(d.car, 10.0, 5.0)
			await _snap("driveway", 0, v[0], v[1], "turning in (%s)" % place["kind"])
			n = 1
		elif d.state == TrafficDriver.State.ARRIVED:
			var inside: Vector2 = place["inside"]
			var p := d.car.global_position
			var off := p - _v3(s)
			await _snap("driveway", 1, _v3(s) - Vector3(off.x, 0, off.z).normalized() * 10.0 + Vector3.UP * 4.0, p, "parked %.1f m from the inside point, turned in: %s" % [Vector2(p.x, p.z).distance_to(inside), d.turned_in])
			n = 2
	_clear_traffic(tm)

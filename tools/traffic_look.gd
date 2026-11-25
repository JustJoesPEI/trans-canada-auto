extends "res://tools/traffic_check.gd"
## Pictures of traffic doing things, for checking how it looks (the
## things a headless check can't judge). Stages each scene with the same
## helpers as traffic_check.gd, runs it without drawing, and draws only the
## frames it saves:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility \
##       --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 60 \
##       --script res://tools/traffic_look.gd -- --graphics=low [--only=a,b] [--dir=/tmp/tca-shots]
##
## (On a machine with a screen, leave out xvfb-run. In a cloud container
## the OpenGL renderer does all six scenes in a few minutes; software
## Vulkan, and High graphics' close-up facades, take an hour or more.)
## Scenes:
##   swap      a far car coming down a long street, just before and just
##             after it turns from a follower into a real car
##   bridge    a far car crossing a bridge
##   pullover  a car pulling over for a siren on a street with parked cars
##   pass      a car going round one stopped in its lane
##   out       a painted car's driver out staring at it, then complaining
##             when it's taken
##   driveway  a car turning into its driveway
##   bus       a town bus pulled in at a stop on University Avenue
##   queue     a police car with its siren on going by traffic queued at a
##             red light (as traffic_check's queue)
##   tow       a rollback comes for a stalled car: deck down, winching it
##             on, deck up, driving off with it
##   scatter   a driver out looking at their car runs from paintballs
## Each picture is saved as DIR/traffic_<scene>_<n>.png.

var _dir := "/tmp/tca-shots"


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_dir = str(args.get("dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var only: Array = str(args.get("only", "swap,bridge,pullover,pass,out,driveway,queue,bus,tow,scatter")).split(",")
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
	_player = player as PlayerController
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
	for scene: String in ["swap", "bridge", "pullover", "pass", "out", "driveway", "queue", "bus", "tow", "scatter"]:
		if scene in only:
			await call("_look_%s" % scene)
	print("LOOK done")
	quit(0)


var _note_t := 0.0
var _look_at := Vector2.INF


func _track_look() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	if _t > _note_t:
		_note_t = _t + 5.0
		print("LOOK t=%.0f wall %d s" % [_t, Time.get_ticks_msec() / 1000])
	if _hold_clock >= 0.0:
		TrafficSignal.clock = _hold_clock
	# The streets round each scene are loaded once, in _settle_at (building
	# more as a car moves is slow when drawing in software), and kept: the
	# streamer stays focused on the scene, not on the parked player.
	if _focus != null and is_instance_valid(_focus):
		_look_at = Vector2(_focus.global_position.x, _focus.global_position.z)
		# Its streets built before it gets there (else it drops to the
		# safety floor under the town).
		_hold_for_streets(_look_at, 90.0)
	if _look_at != Vector2.INF:
		_world.streamer._focus = _look_at
		_world.streamer._has_focus = true


## As traffic_check's, but waiting on the wall clock as shot_server.gd
## does: with nothing drawn the game's own clock barely moves.
func _settle_at(p: Vector2) -> void:
	_focus = null
	_cam.global_position = Vector3(p.x, _world.terrain.h2(p) + 3.0, p.y)
	var st := _world.streamer
	_look_at = p
	st._focus = p
	st._has_focus = true
	st.refresh()
	var t0 := Time.get_ticks_msec()
	var last := t0
	while not st.is_settled() and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
		if Time.get_ticks_msec() - last > 100:
			last = Time.get_ticks_msec()
			st._focus = p
			st.refresh()
	await _wait(0.3)


## The camera at `eye` looking at `at`; draws and saves a picture.
func _snap(scene: String, n: int, eye: Vector3, at: Vector3, note := "") -> void:
	_cam.global_position = eye
	_cam.look_at(at, Vector3.UP)
	_hold_for_streets(Vector2(eye.x, eye.z), 120.0)
	if DisplayServer.get_name() == "headless":
		print("LOOK (headless, no picture) %s %d %s" % [scene, n, note])
		return
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
		tm._physics_lod(eye2)
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
			var f := d.follower
			var on := d.civil.edge_at(f.along) if f != null else null
			await _snap("bridge", 0, eye, p, "follower on %s at y %.1f (terrain %.1f), drawn %.1f m up (target %.1f), on %s (bridge %s), surface %.1f" % [best.name, p.y, _world.terrain.h2(Vector2(p.x, p.z)), d.lift, d.lift_target, on.name if on else "?", on.bridge if on else false, tm.surface_y(p, on)])
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
	print("LOOK pullover on %s (%.0f m)" % [best.name, best.length])
	await _settle_at(r.sample(80.0))
	print("LOOK pullover settled")
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
	while _t - t0 < 25.0 and n < 2:
		await physics_frame
		var c := _ap(me).civil
		if n == 0 and c.lateral < -0.3 and absf(me.speed) < 2.0:
			var v: Array = _chase_cam(me, 12.0, 4.0)
			await _snap("pullover", 0, v[0], v[1], "pulled %.1f m right and stopped, %s (room %.1f m)" % [-c.lateral, best.name, c._room_right(_ap(me).along)])
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
	var player: Node3D = _player
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


func _look_queue() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 150.0)
		if x.is_empty() or (x[0] as RoadNetwork.Incident).edge.oneway != 0 or (x[0] as RoadNetwork.Incident).edge.half_width < 4.0:
			continue
		pick = {"nid": nid, "x": x}
		break
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	var phase := TrafficSignal.phase_of(inc.dir)
	for k in 160:
		if TrafficSignal.lamp_for(phase, k * 0.25 + float(absi(hash("Signals_%s" % nid)) % 30)) == 0:
			_hold_clock = k * 0.25 + 1.0
			break
	await _settle_at(_net.nodes[nid])
	var queue: Array[TrafficDriver] = []
	for dist: float in [45.0, 60.0, 75.0]:
		var a: Array = _lane_point(nid, inc, dist, true)
		var g: Array = _lane_point(nid, opp, minf(80.0, opp.edge.length - 8.0), false)
		var d := _traffic_on(tm, StreetRoute.plan(_net, a[0], g[0], TrafficManager.plan_options(a[1])), 0.0)
		tm._to_car(d)
		queue.append(d)
	await _wait(14.0)
	var rs: Array = _lane_point(nid, opp, 25.0, false)
	var runner := _runner_car(rs[0], rs[1])
	var goal: Array = _lane_point(nid, opp, minf(120.0, opp.edge.length - 8.0), false)
	var wanted := root.get_node("Wanted")
	wanted.call("debug_set_level", 2)
	var ps: Array = _lane_point(nid, inc, minf(175.0, inc.edge.length - 5.0), true)
	var unit := _police.new_unit("city")
	unit.place_physical(Transform3D(Basis(Vector3.UP, atan2(-(ps[1] as Vector2).x, -(ps[1] as Vector2).y)), _v3(ps[0]) + Vector3.UP * 0.35), _main)
	await _wait(0.3)
	_ap(runner).cruise_speed_kmh = 30.0
	_ap(runner).drive_to(_v3(goal[0]))
	unit.order(PoliceUnit.Role.CHASE, runner.global_position, _police.clock)
	wanted.call("debug_watch", true)
	var np: Vector2 = _net.nodes[nid]
	var t0 := _t
	var n := 0
	# Looking back down the queue from beside the junction.
	var side := Vector2(-inc.dir.y, inc.dir.x)
	var eye := _v3(np + inc.dir * 18.0 - side * 9.0) + Vector3.UP * 4.5
	while _t - t0 < 30.0 and n < 2 and unit.car != null:
		await physics_frame
		var pp := Vector2(unit.car.global_position.x, unit.car.global_position.z)
		var to := (pp - np).dot(inc.dir)
		if n == 0 and to < 80.0:
			await _snap("queue", 0, eye, _v3(np + inc.dir * 60.0), "police coming up the queue at %.0f km/h, %.0f m out" % [unit.car.speed * 3.6, to])
			n = 1
		elif n == 1 and to < 62.0:
			await _snap("queue", 1, eye, unit.car.global_position, "going by the queue at %.0f km/h, %.1f m out (siren lane)" % [unit.car.speed * 3.6, unit.pilot.siren_lane.lateral if unit.pilot.siren_lane != null else 0.0])
			n = 2
	_hold_clock = -1.0
	_drop_police()
	_end_runner(runner)
	_clear_traffic(tm)


func _look_bus() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var spot: Vector2 = _net.nodes[_net.find_junction("University Avenue", "Allen Street")]
	await _settle_at(spot)
	var eye := _v3(spot) + Vector3.UP * 2.0
	tm.focus = eye
	tm.running = true
	var t0 := _t
	var shot := false
	while _t - t0 < 150.0 and not shot:
		await physics_frame
		for d: TrafficDriver in tm.drivers:
			if d.bus_route >= 0 and d.car != null and _focus == null:
				_focus = d.car # keep its streets built (Low graphics' full-detail circle is small)
			if d.bus_route >= 0 and d.car != null and d.civil.reason == "bus_stop" and absf(d.car.speed) < 0.5:
				var c := d.car
				var f := -c.global_basis.z
				var side := c.global_basis.x
				await _snap("bus", 0, c.global_position - f * 18.0 - side * 4.0 + Vector3.UP * 3.0, c.global_position + Vector3.UP * 1.5, "at a stop, %.1f m in to the curb (from behind, in the road); roll %.1f, pitch %.1f, wheels down %d, y %.2f, ground %.2f, terrain %.2f at (%.0f, %.0f)" % [-d.civil.lateral, rad_to_deg(asin(c.global_basis.x.y)), rad_to_deg(asin(c.global_basis.z.y)), c.wheels_down, c.global_position.y, _ground_y(Vector2(c.global_position.x, c.global_position.z)), _world.terrain.h2(Vector2(c.global_position.x, c.global_position.z)), c.global_position.x, c.global_position.z])
				shot = true
				break
	tm.running = false
	_clear_traffic(tm)
	tm.focus = Vector3.INF


func _look_tow() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var e := _long_straight(["residential", "tertiary"], 250.0)
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	var at := r.sample(r.length * 0.5)
	await _settle_at(at)
	var dir := r.dir_at(r.length * 0.5)
	var car := Car.new()
	car.model_id = "corollary"
	car.paint = Color(0.2, 0.35, 0.7)
	car.name = "Dead"
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(at) + Vector3.UP * 0.3)
	car.reset_physics_interpolation()
	(_main.get("cars") as Array).append(car)
	car.stalled = true
	TrafficTows.player_after = 2.0
	TrafficTows.traffic_after = 2.0
	tm.focus = _v3(at)
	_look_at = at
	var shot := {}
	var t0 := _t
	while _t - t0 < 200.0:
		await physics_frame
		var j: TrafficTows.Job = null
		for x: TrafficTows.Job in tm.tows.jobs:
			if x.car == car:
				j = x
		if j == null:
			if tm.tows.sent > 0 and not shot.has("gone"):
				break
			continue
		var truck := tm.tows._truck_car(j)
		if truck == null:
			break
		_focus = truck
		var side := truck.global_basis.x
		var mid := truck.global_position.lerp(car.global_position, 0.5)
		var key := "%d" % j.step
		var wait := {TrafficTows.Step.SENT: -1.0, TrafficTows.Step.LOWER: 4.0, TrafficTows.Step.WINCH: 3.0, TrafficTows.Step.RAISE: 5.5, TrafficTows.Step.AWAY: 1.5}
		if j.step == TrafficTows.Step.SENT and truck.global_position.distance_to(car.global_position) < 30.0 and not shot.has("near"):
			shot["near"] = true
			await _snap("tow", 0, car.global_position + side * 9.0 - truck.global_basis.z * 6.0 + Vector3.UP * 2.5, truck.global_position + Vector3.UP, "the rollback coming up")
		elif float(wait.get(j.step, -1.0)) >= 0.0 and j.t > float(wait[j.step]) and not shot.has(key):
			shot[key] = true
			await _snap("tow", 1 + j.step, mid + side * 11.0 + Vector3.UP * 3.0, mid + Vector3.UP * 1.0, "step %d" % j.step)
			if j.step == TrafficTows.Step.AWAY:
				break
	tm.focus = Vector3.INF
	_focus = null
	_clear_traffic(tm)


func _look_scatter() -> void:
	var tm: TrafficManager = _main.get_node("Traffic")
	var e := _long_straight(["residential", "tertiary"], 250.0)
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	await _settle_at(r.sample(40.0))
	var d := _traffic_on(tm, r, 20.0)
	tm._to_car(d)
	var car := d.car
	_focus = car
	await _wait(5.0)
	d.getting_out = true
	d.civil.hold_for(30.0, "paint", true)
	var t0 := _t
	while _t - t0 < 15.0 and d.bystander == null:
		await physics_frame
	await _wait(1.0)
	var b := d.bystander
	if b == null:
		return
	var p0 := b.global_position
	tm.heat.shots_at(p0 + (-car.global_basis.z) * 5.0)
	await _wait(1.2)
	var side := (p0 - car.global_position).normalized()
	await _snap("scatter", 0, p0 + side * 7.0 + car.global_basis.z * 3.0 + Vector3.UP * 2.0, b.global_position + Vector3.UP * 1.0, "running: \"%s\"" % b._label.text)
	await _wait(3.0)
	await _snap("scatter", 1, p0 + side * 7.0 + Vector3.UP * 2.0, car.global_position, "left the car: %s" % d.abandoned)
	_focus = null
	_clear_traffic(tm)

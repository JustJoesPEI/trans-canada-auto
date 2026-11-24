extends SceneTree
## Drives police cars with CarAutopilot round the real town and checks they
## drive well enough to chase someone:
##
##   godot --headless --path . --script res://tools/autopilot_check.gd -- [--only=drive,follow,box,pit,follower]
##
## (add --fixed-fps 60 before --script to run faster than real time)
##
##   drive     a police car drive_to()s a point about 1 km away along the
##             streets, within a time limit, without getting stuck
##   follow    a police car follow()s a car being driven along a route by
##             another autopilot and keeps within FOLLOW_MAX of it
##   box       a car slows and stops; box_in() pins it (police stopped across
##             its nose, its way ahead blocked, for 3 s)
##   pit       a car at about 60 km/h; pit() makes it yaw sharply
##   offroad   a car drives off the street into an open field: a police car
##             pursuing it close follows it off the road within FOLLOW_MAX,
##             while one sent from 300+ m away comes by the streets (never
##             off the road) until it's close enough to pursue
##   gap       a link in the street graph is taken out (as the map's gaps
##             are): drive_to a street beyond it gets there anyway
##   corner    a police car nosed into a building corner backs out and is
##             on its way within CORNER_MAX seconds
##   follower  a RoadFollower moves along the streets without physics and
##             hands over to a real car, which drives on and arrives
## One "AUTOPILOT" line per result; exits 1 if any fails.

const POLICE_MODEL := "jaunt"
const POLICE_LIVERY := "cps"
const TARGET_MODEL := "civique"
const FOLLOW_MAX := 40.0
const CORNER_MAX := 6.0 ## "about 5 s"
## A responding car counts as on the street within this of the curb.
const CURB_MARGIN := 1.5

var _main: Node
var _world: WorldBuilder
var _net: RoadNetwork
var _cam := Camera3D.new()
var _focus: Node3D = null
## Other cars whose streets have to be there too (a second unit further off).
var _also: Array[Node3D] = []
var _failed: Array[String] = []
var _t := 0.0 # simulated seconds
var _trace := false
var _held_ms := 0
## Full-detail chunks (with collision) within this of the car before the
## clock moves on.
const STREETS_READY := 140.0
var _trace_next := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_trace = args.has("trace")
	var only: Array = str(args.get("only", "drive,follow,box,pit,follower,offroad,gap,corner")).split(",")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	_net = _world.network
	# The player isn't part of this: out of the way, out of the physics.
	var player: Node3D = _main.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_cam)
	_cam.make_current()
	physics_frame.connect(_track)
	if "drive" in only:
		await _drive_test()
	if "follow" in only:
		await _follow_test()
	if "box" in only:
		await _box_test()
	if "pit" in only:
		await _pit_test()
	if "follower" in only:
		await _follower_test()
	if "offroad" in only:
		await _offroad_test()
	if "gap" in only:
		await _gap_test()
	if "corner" in only:
		await _corner_test()
	print("AUTOPILOT %.0f s simulated; %.1f s spent waiting for the streets to load" % [_t, _held_ms / 1000.0])
	if _failed.is_empty():
		print("AUTOPILOT all passed")
		quit(0)
	else:
		print("AUTOPILOT FAILED: %s" % ", ".join(_failed))
		quit(1)


func _track() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	if _focus != null and is_instance_valid(_focus):
		_cam.global_position = _focus.global_position + Vector3(0, 3, 0)
		_hold_for_streets(Vector2(_focus.global_position.x, _focus.global_position.z))
	for n in _also:
		if is_instance_valid(n):
			_hold_for_streets(Vector2(n.global_position.x, n.global_position.z), 70.0)


## Run faster than real time (--fixed-fps), the chunk streamer can fall
## behind the car and leave it driving on the safety floor. So the clock
## waits here, between physics steps, until the full-detail chunks round the
## car are in (the game itself never waits: at real speed they keep up).
func _hold_for_streets(p: Vector2, radius := STREETS_READY) -> void:
	var s := _world.streamer
	if _streets_ready(s, p, radius):
		return
	var t0 := Time.get_ticks_msec()
	while not _streets_ready(s, p, radius) and Time.get_ticks_msec() - t0 < 20000:
		s._focus = p
		s._has_focus = true
		s._update()
		s._reap()
		s._attach_finished(4)
		OS.delay_msec(3)
	_held_ms += Time.get_ticks_msec() - t0


func _streets_ready(s: ChunkStreamer, p: Vector2, radius: float) -> bool:
	for c in s._cells_within(p, radius):
		if s._dist(c, p) <= radius and not s._near.has(c):
			return false
	return true


## With --trace, a line a second about how a car's autopilot is doing.
func _log(tag: String, car: Car) -> void:
	if not _trace or _t < _trace_next:
		return
	_trace_next = _t + 1.0
	var ap: CarAutopilot = car.get_node("Autopilot")
	var p := car.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 4.0, Layers.GROUND)
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	var under := "nothing" if hit.is_empty() else str((hit["collider"] as Node).name)
	print("  %s t=%.0f (%.0f, %.0f) y %.1f (terrain %.1f, on %s) %.0f km/h %s along %.0f/%.0f thr %.2f brk %.2f st %.2f hb %s ahead %s" % [
		tag, _t, p.x, p.z, p.y, _world.terrain.h2(Vector2(p.x, p.z)), under, car.speed * 3.6, ap.state,
		ap.along, ap.route.length if ap.route != null else 0.0, ap.throttle, ap.brake, ap.steer, ap.handbrake, "%s wheels %d gear %d rpm %.0f" % [ap.blocker, car.wheels_down, car.gear, car.rpm]])


func _result(name: String, ok: bool, text: String) -> void:
	print("AUTOPILOT %s %s: %s" % [name, "ok" if ok else "FAIL", text])
	if not ok:
		_failed.append(name)


# --- the tests ------------------------------------------------------------------

func _drive_test() -> void:
	var spawn := _world.get_spawn().origin
	var start := _on_street(Vector2(spawn.x, spawn.z))
	var plan := _find_destination(start[0], 1000.0, 1400.0)
	if plan == null:
		_result("drive", false, "no destination 1-1.4 km away")
		return
	await _settle_at(start[0])
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, start[0], plan.dir_at(4.0))
	var ap := _pilot(cop)
	await _wait(1.0)
	var dest := Vector3(plan.goal.x, 0.0, plan.goal.y)
	var t0 := _t
	var arrived := [false]
	ap.arrived.connect(func() -> void: arrived[0] = true)
	ap.cruise_speed_kmh = 50.0
	ap.drive_to(dest)
	var limit := plan.length / (25.0 / 3.6) + 20.0
	var recoveries := 0
	var turns := 0
	var was := ""
	var top := 0.0
	var worst_off := 0.0
	var dist := 0.0
	var last := cop.global_position
	while not arrived[0] and _t - t0 < limit:
		await physics_frame
		if ap.state != was:
			if ap.state == "reverse":
				recoveries += 1
			elif ap.state == "turn":
				turns += 1
			was = ap.state
		_log("drive", cop)
		top = maxf(top, cop.speed * 3.6)
		dist += cop.global_position.distance_to(last)
		last = cop.global_position
		if ap.route != null and not ap.route.is_empty():
			worst_off = maxf(worst_off, ap.route.off_line(Vector2(cop.global_position.x, cop.global_position.z), ap.along))
	var secs := _t - t0
	var miss := Vector2(cop.global_position.x, cop.global_position.z).distance_to(plan.goal)
	var ok: bool = arrived[0] and miss < 10.0 and recoveries <= 2
	_result("drive", ok, "to %s, route %.0f m (%d streets), drove %.0f m in %.1f s (limit %.0f s), avg %.0f km/h, top %.0f km/h, %.1f m from the goal, worst %.1f m off the line, %d back-outs, %d K-turns" % [
		_world.street_name_at(plan.goal), plan.length, plan.edges.size(), dist, secs, limit, dist / maxf(secs, 0.1) * 3.6, top, miss, worst_off, recoveries, turns])
	cop.queue_free()
	await _wait(0.2)


func _follow_test() -> void:
	# The target's way: from a street near the spawn to somewhere ~800 m off.
	var spawn := _world.get_spawn().origin
	var start := _on_street(Vector2(spawn.x, spawn.z) + Vector2(250, -150))
	var plan := _find_destination(start[0], 700.0, 1000.0, 7)
	if plan == null:
		_result("follow", false, "no route for the target")
		return
	await _settle_at(plan.sample(30.0))
	var runner := _spawn(TARGET_MODEL, "", plan.sample(30.0), plan.dir_at(30.0))
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, plan.sample(6.0), plan.dir_at(6.0))
	var rap := _pilot(runner)
	var cap := _pilot(cop)
	await _wait(1.0)
	rap.cruise_speed_kmh = 45.0
	var arrived := [false]
	rap.arrived.connect(func() -> void: arrived[0] = true)
	rap.drive_to(Vector3(plan.goal.x, 0.0, plan.goal.y))
	cap.follow(runner)
	var t0 := _t
	var worst := 0.0
	var sum := 0.0
	var n := 0
	var direct := 0
	var after_stop := 0.0
	while _t - t0 < 120.0:
		await physics_frame
		if arrived[0]:
			after_stop += 1.0 / Engine.physics_ticks_per_second
			if after_stop > 4.0:
				break
		if _trace and Engine.get_physics_frames() % 60 == 0:
			print("  runner (%.0f, %.0f) %.0f km/h %s" % [runner.global_position.x, runner.global_position.z, runner.speed * 3.6, rap.state])
		_log("follow", cop)
		var d := cop.global_position.distance_to(runner.global_position)
		if _t - t0 > 4.0:
			worst = maxf(worst, d)
			sum += d
			n += 1
			if cap.state == "direct":
				direct += 1
	var final_d := cop.global_position.distance_to(runner.global_position)
	var ok: bool = arrived[0] and worst < FOLLOW_MAX
	_result("follow", ok, "target drove %.0f m at %.0f km/h in %.1f s; distance worst %.1f m, mean %.1f m, at the end %.1f m; straight at it %.0f%% of the time" % [
		plan.length, rap.cruise_speed_kmh, _t - t0, worst, sum / maxi(n, 1), final_d, 100.0 * direct / maxi(n, 1)])
	runner.queue_free()
	cop.queue_free()
	await _wait(0.2)


func _box_test() -> void:
	var e := _long_street("Belvedere Avenue", 350.0)
	if e.is_empty():
		_result("box", false, "no long straight street")
		return
	var line: PackedVector2Array = e["line"]
	var plan := StreetRoute.along(line)
	await _settle_at(plan.sample(60.0))
	var runner := _spawn(TARGET_MODEL, "", plan.sample(40.0), plan.dir_at(40.0))
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, plan.sample(12.0), plan.dir_at(12.0))
	var rap := _pilot(runner)
	var cap := _pilot(cop)
	await _wait(1.0)
	rap.cruise_speed_kmh = 40.0
	rap.drive_to(Vector3(plan.goal.x, 0, plan.goal.y))
	cap.box_in(runner)
	var t0 := _t
	var pinned := 0.0
	var best_pin := 0.0
	var slowed := false
	var stopped := false
	var gap := INF
	while _t - t0 < 40.0:
		await physics_frame
		var el := _t - t0
		if el > 6.0 and not slowed:
			slowed = true
			rap.cruise_speed_kmh = 18.0
			rap.drive_to(Vector3(plan.goal.x, 0, plan.goal.y))
		if el > 10.0 and not stopped:
			stopped = true
			rap.stop()
		gap = _clear_ahead(runner, 6.0)
		var held: bool = absf(runner.speed) * 3.6 < 5.0 and gap < 1.5 and absf(cop.speed) < 1.0
		if held:
			pinned += 1.0 / Engine.physics_ticks_per_second
			best_pin = maxf(best_pin, pinned)
			if pinned >= 3.0:
				break
		else:
			pinned = 0.0
	var ok := best_pin >= 3.0
	_result("box", ok, "pinned (stopped, police %.1f m ahead of its nose) for %.1f s after %.1f s; police state %s" % [
		gap, best_pin, _t - t0, cop.get_node("Autopilot").state])
	runner.queue_free()
	cop.queue_free()
	await _wait(0.2)


func _pit_test() -> void:
	var e := _long_street("University Avenue", 450.0)
	if e.is_empty():
		e = _long_street("Riverside Drive", 450.0)
	if e.is_empty():
		_result("pit", false, "no long straight street")
		return
	var line: PackedVector2Array = e["line"]
	var plan := StreetRoute.along(line)
	await _settle_at(plan.sample(80.0))
	var runner := _spawn(TARGET_MODEL, "", plan.sample(45.0), plan.dir_at(45.0))
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, plan.sample(15.0), plan.dir_at(15.0))
	var rap := _pilot(runner)
	var cap := _pilot(cop)
	await _wait(1.0)
	rap.cruise_speed_kmh = 62.0
	rap.drive_to(Vector3(plan.goal.x, 0, plan.goal.y))
	cap.follow(runner)
	var t0 := _t
	var ordered := false
	var t_order := 0.0
	var kmh_at := 0.0
	var tap_at := -1.0
	var worst_yaw := 0.0
	var worst_turn := 0.0
	while _t - t0 < 35.0:
		await physics_frame
		if not ordered and runner.speed * 3.6 > 50.0:
			ordered = true
			t_order = _t
			cap.pit(runner)
		if ordered and tap_at < 0.0 and cap.state == "tap":
			tap_at = _t
			kmh_at = runner.speed * 3.6
		if _trace and ordered and Engine.get_physics_frames() % 6 == 0 and (tap_at < 0.0 or _t - tap_at < 3.0):
			var rel := runner.global_transform.affine_inverse() * cop.global_position
			print("  pit t=%.1f %s police at x %.1f z %.1f from it, %.0f vs %.0f km/h, steer %.2f, its yaw rate %.2f" % [
				_t, cap.state, rel.x, rel.z, cop.speed * 3.6, runner.speed * 3.6, cap.steer, runner.yaw_rate])
		if tap_at >= 0.0:
			worst_yaw = maxf(worst_yaw, absf(runner.yaw_rate))
			var f := -runner.global_basis.z
			var road := plan.dir_at(plan.project(Vector2(runner.global_position.x, runner.global_position.z)))
			worst_turn = maxf(worst_turn, rad_to_deg(absf(Vector2(f.x, f.z).angle_to(road))))
			if _t - tap_at > 5.0:
				break
	var ok := tap_at >= 0.0 and (worst_yaw > 1.2 or worst_turn > 40.0)
	_result("pit", ok, "%s; target at %.0f km/h, yaw rate up to %.2f rad/s, turned up to %.0f deg off the road" % [
		("tap %.1f s after the order" % (tap_at - t_order)) if tap_at >= 0.0 else "never lined up", kmh_at, worst_yaw, worst_turn])
	runner.queue_free()
	cop.queue_free()
	await _wait(0.2)


func _follower_test() -> void:
	var spawn := _world.get_spawn().origin
	var start := _on_street(Vector2(spawn.x, spawn.z) + Vector2(-200, 100))
	var plan := _find_destination(start[0], 300.0, 450.0)
	if plan == null:
		_result("follower", false, "no route")
		return
	var rf := RoadFollower.new()
	rf.network = _net
	rf.terrain = _world.terrain
	rf.speed_kmh = 45.0
	_main.add_child(rf)
	rf.global_position = Vector3(start[0].x, 0, start[0].y)
	rf.look_at(rf.global_position + Vector3(plan.dir_at(2.0).x, 0, plan.dir_at(2.0).y))
	var dest := Vector3(plan.goal.x, 0, plan.goal.y)
	rf.go_to(dest)
	var t0 := _t
	while rf.along < rf.route.length * 0.5 and _t - t0 < 60.0:
		await physics_frame
	var at := rf.along
	var kmh := rf.speed * 3.6
	var moved_secs := _t - t0
	# Hold it there while the streets round it are built (in the game, the
	# hand-over happens where they already are: near the player).
	rf.set_physics_process(false)
	await _settle_at(Vector2(rf.global_position.x, rf.global_position.z))
	var car := Car.new()
	car.model_id = POLICE_MODEL
	car.livery = POLICE_LIVERY
	car.paint = Color.from_string(str(CarModels.LIVERIES[POLICE_LIVERY]["colour"]), Color.WHITE)
	car.name = "HandedOver"
	rf.set_physics_process(true)
	var ap := rf.hand_over(car, _main)
	_focus = car
	var arrived := [false]
	ap.arrived.connect(func() -> void: arrived[0] = true)
	var t1 := _t
	while not arrived[0] and _t - t1 < 60.0:
		await physics_frame
	var miss := Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(dest.x, dest.z))
	var ok: bool = arrived[0] and miss < 12.0
	_result("follower", ok, "moved %.0f m of %.0f m without physics in %.1f s (%.0f km/h at hand-over), then the car drove the rest in %.1f s and stopped %.1f m from the goal" % [
		at, plan.length, moved_secs, kmh, _t - t1, miss])
	car.queue_free()
	await _wait(0.2)


# --- helpers --------------------------------------------------------------------

func _spawn(model: String, livery: String, p: Vector2, dir: Vector2) -> Car:
	var car := Car.new()
	car.model_id = model
	car.livery = livery
	if livery != "":
		car.paint = Color.from_string(str(CarModels.LIVERIES[livery]["colour"]), Color.WHITE)
	else:
		car.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	car.name = "%s_%s" % [model, livery if livery != "" else "car"]
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.25, p.y))
	car.reset_physics_interpolation()
	_focus = car if livery != "" else _focus
	return car


func _pilot(car: Car) -> CarAutopilot:
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = _net
	car.add_child(ap)
	ap.stop()
	return ap


func _ground_y(p: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	var h := _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 6.0, p.y), Vector3(p.x, h - 3.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return h if hit.is_empty() else (hit["position"] as Vector3).y


func _settle_at(p: Vector2) -> void:
	_focus = null
	_cam.global_position = Vector3(p.x, _world.terrain.h2(p) + 3.0, p.y)
	await _world.wait_until_settled()
	await _wait(0.3)


func _wait(secs: float) -> void:
	var until := _t + secs
	while _t < until:
		await physics_frame


## [point on the nearest street's right lane, its direction].
func _on_street(p: Vector2) -> Array:
	var hit := _net.nearest_on_streets(p, 400.0)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along: float = clampf(hit["along"], 10.0, maxf(10.0, e.length - 10.0))
	var sp: Array = RoadNetwork.sample(e.points, along)
	return [sp[0], sp[1]]


## A route from p to a junction whose route length is between lo and hi
## metres (the n-th one found, in a fixed order, so runs are repeatable).
func _find_destination(p: Vector2, lo: float, hi: float, skip := 0) -> StreetRoute:
	var ids := _net.nodes.keys()
	ids.sort()
	for nid: String in ids:
		var q: Vector2 = _net.nodes[nid]
		var d := q.distance_to(p)
		# Well short of the route's length as the crow flies: a way with
		# corners in it, not one long street.
		if d < lo * 0.4 or d > lo * 0.85 or not _world.is_in_play_area(q):
			continue
		var r := StreetRoute.plan(_net, p, q)
		if r.is_empty() or r.length < lo or r.length > hi:
			continue
		if skip > 0:
			skip -= 1
			continue
		return r
	return null


## The longest straight-ish two-way stretch of a street, as its right-lane
## line: {"line": PackedVector2Array} or {}.
func _long_street(street: String, min_len: float) -> Dictionary:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.name != street or e.oneway != 0 or e.length < min_len:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.95 and (best == null or e.length > best.length):
			best = e
	if best == null:
		return {}
	var off := StreetRoute._lane_offset(best, true)
	return {"line": StreetRoute._offset_line(best.points, off)}


## How far ahead of a car's nose is clear (to anything but itself), up to
## `reach`: three rays, the shortest.
func _clear_ahead(car: Car, reach: float) -> float:
	var space := car.get_world_3d().direct_space_state
	var xf := car.global_transform
	var hl := float(car.shape.get("length", 4.4)) * 0.5
	var best := INF
	for x: float in [-0.7, 0.0, 0.7]:
		var from := xf * Vector3(x, 0.6, -hl + 0.2)
		var to := xf * Vector3(x, 0.6, -hl - reach)
		var q := PhysicsRayQueryParameters3D.create(from, to, Layers.VEHICLES | Layers.SOLID)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, from.distance_to(hit["position"]) - 0.2)
	return best


# --- off the road, gaps in the map, building corners -----------------------------

func _offroad_test() -> void:
	var field := await _find_field()
	if field.is_empty():
		_result("offroad", false, "no open field found to test in")
		return
	var s: Vector2 = field["street"] # in the lane beside the field
	var sdir: Vector2 = field["dir"] # the lane's way along the street
	var into: Vector2 = field["into"] # from the street into the field
	var f1: Vector2 = s + into * 45.0
	var f2: Vector2 = f1 + into * 35.0 + sdir * 25.0
	# The responder: on the streets, 300+ m away by road.
	var far := _find_destination(s, 400.0, 700.0)
	if far == null:
		_result("offroad", false, "no street 300 m away for the responder")
		return
	var rhit := _net.nearest_on_streets(far.goal, 50.0)
	var rdir: Vector2 = rhit["dir"]
	var lane := StreetRoute.along(PackedVector2Array([s - sdir * 60.0, s]))
	var runner := _spawn(TARGET_MODEL, "", lane.sample(25.0), sdir)
	var chaser := _spawn(POLICE_MODEL, POLICE_LIVERY, lane.sample(2.0), sdir)
	var responder := _spawn(POLICE_MODEL, POLICE_LIVERY, rhit["pos"], rdir)
	_focus = chaser
	_also = [responder]
	var rap := _pilot(runner)
	var cap := _pilot(chaser)
	var fap := _pilot(responder)
	await _wait(1.0)
	rap.cruise_speed_kmh = 35.0
	var leg := [0]
	rap.arrived.connect(func() -> void: leg[0] += 1)
	rap.drive_to(Vector3(f1.x, 0, f1.y), true)
	cap.follow(runner)
	fap.follow(runner)
	var t0 := _t
	var worst := 0.0
	var chaser_off := 0.0
	var runner_off := 0.0
	var resp_worst := 0.0
	var resp_secs := 0.0
	var resp_switched := -1.0
	var resp_closest := INF
	var done_at := -1.0
	while _t - t0 < 150.0:
		await physics_frame
		_log("offroad", runner)
		if leg[0] == 1:
			leg[0] = 2
			rap.drive_to(Vector3(f2.x, 0, f2.y), true)
		if leg[0] >= 3 and done_at < 0.0:
			done_at = _t
		if done_at >= 0.0 and _t - done_at > 6.0 and (fap.pursuit or _t - done_at > 60.0):
			break
		var d := chaser.global_position.distance_to(runner.global_position)
		if _t - t0 > 4.0:
			worst = maxf(worst, d)
		chaser_off = maxf(chaser_off, _curb_dist(chaser))
		runner_off = maxf(runner_off, _curb_dist(runner))
		resp_closest = minf(resp_closest, responder.global_position.distance_to(runner.global_position))
		if not fap.pursuit:
			resp_secs += 1.0 / Engine.physics_ticks_per_second
			resp_worst = maxf(resp_worst, _curb_dist(responder))
		elif resp_switched < 0.0:
			resp_switched = responder.global_position.distance_to(runner.global_position)
	_also = []
	var ok_chase := done_at >= 0.0 and runner_off > 20.0 and worst < FOLLOW_MAX and chaser_off > 15.0
	var ok_resp := resp_secs > 5.0 and resp_worst <= CURB_MARGIN and far.length > 300.0 and resp_switched >= 0.0
	_result("offroad", ok_chase and ok_resp, "field at least %.0f m from other streets; target went %.0f m off the road, %s; pursuer worst %.1f m behind it, went %.0f m off the road; responder started %.0f m away by road, came by the streets for %.0f s, at most %.1f m past the curb, %s" % [
		field["off"], runner_off, "got there" if done_at >= 0.0 else "never got there", worst, chaser_off,
		far.length, resp_secs, resp_worst,
		("switched to pursuit %.0f m from it" % resp_switched) if resp_switched >= 0.0 else "never pursued (closest %.0f m)" % resp_closest])
	for c: Car in [runner, chaser, responder]:
		c.queue_free()
	await _wait(0.2)


func _gap_test() -> void:
	var cut := _make_gap()
	if cut.is_empty():
		_result("gap", false, "no dead-end street to cut")
		return
	var goal: Vector2 = cut["goal"]
	var start := _find_start_toward(goal, 250.0, 500.0)
	if start.is_empty():
		_undo_gap(cut)
		_result("gap", false, "no start for the gap test")
		return
	var plan := StreetRoute.plan(_net, start["pos"], goal)
	var comp := StreetRoute.components(_net)
	var cut_off: bool = comp[(cut["new"] as RoadNetwork.RoadEdge).a] != comp[(_net.nearest_on_streets(start["pos"])["edge"] as RoadNetwork.RoadEdge).a]
	await _settle_at(start["pos"])
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, start["pos"], start["dir"])
	var ap := _pilot(cop)
	await _wait(1.0)
	var arrived := [false]
	ap.arrived.connect(func() -> void: arrived[0] = true)
	ap.drive_to(Vector3(goal.x, 0, goal.y))
	var t0 := _t
	while not arrived[0] and _t - t0 < 120.0:
		await physics_frame
		_log("gap", cop)
	var miss := Vector2(cop.global_position.x, cop.global_position.z).distance_to(goal)
	_undo_gap(cut)
	var ok: bool = arrived[0] and miss < 12.0 and plan.gaps > 0 and cut_off
	_result("gap", ok, "cut %s %.0f m short of its junction (the graph alone %s); the plan bridged %d gap(s), %.0f m%s; drove there in %.1f s, stopped %.1f m from the goal, %d back-outs" % [
		cut["name"], cut["gap"], "can't get there" if cut_off else "still gets there",
		plan.gaps, plan.length, " (partial)" if plan.partial else "", _t - t0, miss, ap.recoveries])
	cop.queue_free()
	await _wait(0.2)


func _corner_test() -> void:
	var spawn := _world.get_spawn().origin
	await _settle_at(Vector2(spawn.x, spawn.z))
	var hl := float(CarModels.shape_for(POLICE_MODEL, POLICE_LIVERY, 0).get("length", 4.9)) * 0.5
	var space := _cam.get_world_3d().direct_space_state
	# A corner with room to back out: nosed into the wall just short of the
	# corner, at 55 degrees to it, as if it had cut the corner too tight.
	var place := Vector2.INF
	var face := Vector2.ZERO
	var corner := {}
	for c: Dictionary in _find_building_corners(Vector2(spawn.x, spawn.z)):
		var at: Vector2 = c["corner"]
		var c_along: Vector2 = c["along"] # the street's way past the corner
		var out: Vector2 = c["out"] # from the wall toward the street
		face = (c_along * sin(deg_to_rad(35.0)) - out * cos(deg_to_rad(35.0))).normalized()
		for k in range(0, 6):
			var nose := at - c_along * (1.0 + k * 0.7)
			var from := nose - face * (hl + 1.5)
			var y := _ground_y(nose) + 1.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(from.x, y, from.y), Vector3(nose.x + face.x * 2.0, y, nose.y + face.y * 2.0), Layers.SOLID)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or not str((hit["collider"] as Node).get_path()).contains("Building"):
				continue
			var hp: Vector3 = hit["position"]
			var p := Vector2(hp.x, hp.z) - face * (hl + 1.5)
			var side := Vector2(-face.y, face.x)
			# Room to back out and turn: clear behind, and either side along
			# the car's length (no parked car tucked in beside it).
			var room := _strip_clear(p, p - face * 10.0, 1.5)
			for f: float in [-hl, -hl * 0.3]:
				room = room and _strip_clear(p + face * f - side * 3.5, p + face * f + side * 3.5, 0.0)
			if room:
				place = p
				corner = c
				break
		if place != Vector2.INF:
			break
	if place == Vector2.INF:
		_result("corner", false, "no building corner with room round it found")
		return
	var along: Vector2 = corner["along"]
	var cop := _spawn(POLICE_MODEL, POLICE_LIVERY, place, face)
	var ap := _pilot(cop)
	await _wait(1.0)
	# Drive it into the wall, as if it cut the corner too tight.
	var foot := Pedals.new()
	foot.throttle = 0.5
	cop.ai_controls = foot
	await _wait(1.8)
	foot.throttle = 0.0
	foot.handbrake = true
	await _wait(0.5)
	var wall_gap := _clear_ahead(cop, 6.0)
	var start := cop.global_position
	var goal: Vector2 = (corner["street"] as Vector2) + along * 60.0
	ap.drive_to(Vector3(goal.x, 0, goal.y))
	var t0 := _t
	var free_at := -1.0
	while _t - t0 < 15.0:
		await physics_frame
		_log("corner", cop)
		if cop.global_position.distance_to(start) > 2.0 and cop.speed > 2.0 and _clear_ahead(cop, 4.0) > 4.0:
			free_at = _t - t0
			break
	var ok := free_at >= 0.0 and free_at <= CORNER_MAX
	_result("corner", ok, "nosed into a building corner %.1f m off the wall; %s, %d back-outs" % [
		wall_gap, ("on its way after %.1f s" % free_at) if free_at >= 0.0 else "still stuck after 15 s", ap.recoveries])
	cop.queue_free()
	await _wait(0.2)


## Plain controls for a car, set by hand.
class Pedals:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false


## How far outside the nearest street's curb a car is.
func _curb_dist(car: Node3D) -> float:
	var p := Vector2(car.global_position.x, car.global_position.z)
	var hit := _net.nearest_on_streets(p, 100.0)
	if hit.is_empty():
		return 100.0
	return maxf(0.0, float(hit["dist"]) - (hit["edge"] as RoadNetwork.RoadEdge).half_width)


## An open field beside a street: flat, dry ground well away from any other
## street, nothing solid in a car-wide strip from the street in.
## {"street", "dir", "into", "off"} or {}.
func _find_field() -> Dictionary:
	var tried := 0
	var c0 := _world.play_area_center()
	var order: Array = []
	for e in _net.edges:
		if e.oneway == 0 and e.length > 120.0 and not e.is_highway() and not e.bridge:
			order.append(e)
	order.sort_custom(func(a: RoadNetwork.RoadEdge, b: RoadNetwork.RoadEdge) -> bool:
		return (RoadNetwork.sample(a.points, a.length * 0.5)[0] as Vector2).distance_to(c0) < (RoadNetwork.sample(b.points, b.length * 0.5)[0] as Vector2).distance_to(c0))
	for e: RoadNetwork.RoadEdge in order:
		var sp: Array = RoadNetwork.sample(e.points, e.length * 0.5)
		var mid: Vector2 = sp[0]
		var dir: Vector2 = sp[1]
		for side: float in [1.0, -1.0]:
			var into := Vector2(-dir.y, dir.x) * side
			var ok := true
			var off := INF
			var h0 := _world.terrain.h2(mid)
			for k in range(2, 11):
				var p := mid + into * (k * 10.0)
				var hp := _world.terrain.h2(p)
				if hp < Terrain.WATER_Y + 1.0 or absf(hp - h0) > 5.0 or not _world.is_in_play_area(p):
					ok = false
					break
				if k >= 5:
					var hit := _net.nearest_on_streets(p, 60.0)
					var dd := 60.0 if hit.is_empty() else float(hit["dist"])
					if dd < 35.0:
						ok = false
						break
					off = minf(off, dd)
			if not ok:
				continue
			# Now look properly: the chunks there built, rays across it.
			tried += 1
			if tried > 14:
				return {}
			await _settle_at(mid + into * 40.0)
			var s := mid + into * StreetRoute._lane_offset(e, true)
			if _strip_clear(s + into * 3.0, mid + into * 100.0, 3.0):
				var right := Vector2(-dir.y, dir.x)
				var lane_dir := dir if into.dot(right) > 0.0 else -dir
				return {"street": s, "dir": lane_dir, "into": into, "off": off}
	return {}


## Nothing solid in a strip `half` m either side of a line, and ground all
## the way with no big steps.
func _strip_clear(a: Vector2, b: Vector2, half: float) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var n := (b - a).normalized()
	var side := Vector2(-n.y, n.x)
	for o: float in [-half, 0.0, half]:
		for y: float in [0.5, 1.4]:
			var pa := a + side * o
			var pb := b + side * o
			var q := PhysicsRayQueryParameters3D.create(Vector3(pa.x, _ground_y(pa) + y, pa.y), Vector3(pb.x, _ground_y(pb) + y, pb.y), Layers.SOLID | Layers.VEHICLES)
			if not space.intersect_ray(q).is_empty():
				return false
	var last := _ground_y(a)
	var steps := int(a.distance_to(b) / 5.0)
	for i in range(1, steps + 1):
		var p := a + n * (i * 5.0)
		var y := _ground_y(p)
		if absf(y - last) > 1.2:
			return false
		last = y
	return true


## Makes a gap in the map the way OSM data has them: a dead-end street is
## cut loose from its junction, its first GAP m gone, so it ends just short
## of the street it should join. Returns what's needed to undo it, with
## "goal" (near the far end of the cut street), or {}.
const GAP := 22.0

func _make_gap() -> Dictionary:
	var spawn := _world.get_spawn().origin
	var sp := Vector2(spawn.x, spawn.z)
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or e.length < 90.0 or e.length > 400.0:
			continue
		if not ((_net.degree(e.b) == 1) != (_net.degree(e.a) == 1)):
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		if not _world.is_in_play_area(mid) or mid.distance_to(sp) > 1500.0:
			continue
		if best == null or mid.distance_to(sp) < (RoadNetwork.sample(best.points, best.length * 0.5)[0] as Vector2).distance_to(sp):
			best = e
	if best == null:
		return {}
	var e := best
	# Oriented junction -> dead end.
	var pts := e.points.duplicate()
	var junction := e.a
	var dead := e.b
	if _net.degree(e.a) == 1:
		pts.reverse()
		junction = e.b
		dead = e.a
	var cut_pts := StreetRoute._sub(_sub_edge(pts), GAP, e.length)
	var ne := RoadNetwork.RoadEdge.new()
	ne.index = e.index
	ne.name = e.name
	ne.highway = e.highway
	ne.oneway = 0
	ne.a = "gap_test"
	ne.b = dead
	ne.points = cut_pts
	ne.half_width = e.half_width
	ne.sidewalk = e.sidewalk
	ne.lanes = e.lanes
	ne.length = RoadNetwork.polyline_length(cut_pts)
	var lo := cut_pts[0]
	var hi := cut_pts[0]
	for p in cut_pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	ne.bounds = Rect2(lo, hi - lo)
	var keep := _remove_edge(e)
	_net.nodes["gap_test"] = cut_pts[0]
	var i0 := RoadNetwork.Incident.new()
	i0.edge = ne
	i0.at_start = true
	i0.dir = (cut_pts[1] - cut_pts[0]).normalized()
	i0.angle = i0.dir.angle()
	var i1 := RoadNetwork.Incident.new()
	i1.edge = ne
	i1.at_start = false
	i1.dir = (cut_pts[cut_pts.size() - 2] - cut_pts[cut_pts.size() - 1]).normalized()
	i1.angle = i1.dir.angle()
	_net.incidents["gap_test"] = [i0]
	(_net.incidents[dead] as Array).append(i1)
	_net.edges.append(ne)
	_net._index_edge(ne)
	var goal: Vector2 = RoadNetwork.sample(cut_pts, ne.length * 0.7)[0]
	var gdir: Vector2 = RoadNetwork.sample(cut_pts, ne.length * 0.7)[1]
	goal += Vector2(-gdir.y, gdir.x) * StreetRoute._lane_offset(ne, true)
	return {"edge": e, "new": ne, "keep": keep, "dead": dead, "goal": goal, "name": e.name, "gap": GAP}


## A throwaway edge carrying a polyline, so StreetRoute._sub can cut it.
func _sub_edge(pts: PackedVector2Array) -> RoadNetwork.RoadEdge:
	var t := RoadNetwork.RoadEdge.new()
	t.points = pts
	t.length = RoadNetwork.polyline_length(pts)
	return t


func _undo_gap(cut: Dictionary) -> void:
	var ne: RoadNetwork.RoadEdge = cut["new"]
	_remove_edge(ne)
	_net.incidents.erase("gap_test")
	_net.nodes.erase("gap_test")
	_restore_edge(cut["edge"], cut["keep"])


## A point in a lane lo..hi metres by road from a goal (before any cut).
func _find_start_toward(goal: Vector2, lo: float, hi: float) -> Dictionary:
	var ids := _net.nodes.keys()
	ids.sort()
	for nid: String in ids:
		var q: Vector2 = _net.nodes[nid]
		var d := q.distance_to(goal)
		if d < lo * 0.5 or d > hi * 0.8 or not _world.is_in_play_area(q):
			continue
		for inc: RoadNetwork.Incident in _net.incidents[nid]:
			if inc.edge.length < 40.0 or inc.edge.oneway != 0:
				continue
			var pts := inc.edge.points.duplicate()
			if not inc.at_start:
				pts.reverse()
			var sp: Array = RoadNetwork.sample(pts, 20.0)
			var p: Vector2 = sp[0]
			var r := StreetRoute.plan(_net, p, goal)
			if r.is_empty() or r.length < lo or r.length > hi:
				continue
			var dir: Vector2 = sp[1]
			p += Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(inc.edge, true)
			return {"pos": p, "dir": dir}
	return {}


## Takes an edge out of the network (graph and lookups); returns what's
## needed to put it back.
func _remove_edge(e: RoadNetwork.RoadEdge) -> Dictionary:
	var keep := {"a": (_net.incidents[e.a] as Array).duplicate(), "b": (_net.incidents[e.b] as Array).duplicate(), "cells": []}
	for nid: String in [e.a, e.b]:
		var list: Array = _net.incidents[nid]
		for i in range(list.size() - 1, -1, -1):
			if (list[i] as RoadNetwork.Incident).edge == e:
				list.remove_at(i)
	for cell: Vector2i in _net._grid:
		var list: Array = _net._grid[cell]
		if list.has(e):
			list.erase(e)
			(keep["cells"] as Array).append(cell)
	_net.edges.erase(e)
	return keep


func _restore_edge(e: RoadNetwork.RoadEdge, keep: Dictionary) -> void:
	_net.incidents[e.a] = keep["a"]
	_net.incidents[e.b] = keep["b"]
	for cell: Vector2i in keep["cells"]:
		(_net._grid[cell] as Array).append(e)
	_net.edges.append(e)


## Building corners beside streets near p: rays from the street out to the
## side every 2 m; where a wall close past the curb stops, that's a corner.
## Each {"corner", "along", "out", "street"}.
func _find_building_corners(p: Vector2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var space := _cam.get_world_3d().direct_space_state
	for e in _net.edges_near(Rect2(p - Vector2(250, 250), Vector2(500, 500))):
		if e.length < 40.0:
			continue
		for side: float in [1.0, -1.0]:
			var prev := INF
			var run := 0 # samples in a row along the same wall
			var d := 6.0
			while d < e.length - 6.0:
				var sp: Array = RoadNetwork.sample(e.points, d)
				var c: Vector2 = sp[0]
				var dir: Vector2 = sp[1]
				var out := Vector2(-dir.y, dir.x) * side
				var y := _ground_y(c) + 1.0
				var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, y, c.y), Vector3(c.x + out.x * 16.0, y, c.y + out.y * 16.0), Layers.SOLID)
				var hit := space.intersect_ray(q)
				var dist := INF
				if not hit.is_empty() and str((hit["collider"] as Node).get_path()).contains("Building"):
					var hp: Vector3 = hit["position"]
					dist = c.distance_to(Vector2(hp.x, hp.z))
				var hw := e.half_width + 1.0
				var ends := run >= 4 and prev > hw + 1.5 and prev < hw + 6.0 and dist > prev + 5.0
				run = run + 1 if dist < INF and absf(dist - prev) < 0.8 else 0
				if ends:
					var back: Vector2 = RoadNetwork.sample(e.points, d - 2.0)[0]
					found.append({"corner": back + out * prev, "along": dir, "out": -out, "street": c})
				prev = dist
				d += 2.0
	return found

extends SceneTree
## Checks the police (scripts/police/, docs/design.md section 7) in the
## real town, headless:
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/police_check.gd -- [--only=patrol,lights,respond,sight,force,box,out,stall,search,escape] [--trace]
##
## The getaway (escape) for tuning runs:
##   --level=3 (or --levels=2,3)  which wanted levels (default 1,2,3,4)
##   --runs=12                    runs per level (default 1)
##   --seed=7                     start points and dice (default 1): each run
##                                starts on a different street, the same for
##                                the same seed
##   --start=x,z                  start every run near this point instead
##   --limit=600                  seconds before a run counts as timed out
##                                (default 90 / 240 / 360 / 900 by level)
## Each run prints one line to parse:
##   GETAWAY level=3 run=2 seed=7 start=x,z result=escaped secs=211 ...
## result: escaped (level 0), caught (how=boxed_in, painted_out, ...),
## stalled (the car stalled by paint), timeout (still wanted at the limit).
##
##   patrol    not wanted, patrols appear near the player and their cars
##             stay on the streets
##   lights    a patrol arriving at a red light stops short of the junction
##             and only goes through on green (or an amber it can't stop for)
##   respond   a crime brings a responder: placed 300-600 m off out of
##             sight, it comes by road and reaches the player
##   sight     an officer sees the player in the open, and doesn't see
##             them behind a building
##   force     each level gets its force (1 / 4 / 8 / 8 and the Paint
##             Tank), every unit placed 300-600 m off out of sight
##   box       a police car boxes in the stopped player's car: caught
##   out       an officer painted out puts on the vest, hands up, leaves
##             the targets and can't be hit; both out and the unit's
##             replaced
##   stall     a police car painted to 100% stalls and both officers go on
##             on foot
##   search    after losing sight, the units search the circle
##   escape    a scripted getaway at each level from a car driven by a
##             fleeing driver: time to escape (or caught), printed for
##             tuning the difficulty
## One "POLICE" line per result; exits 1 if any fails.

var _main: Node
var _world: WorldBuilder
var _net: RoadNetwork
var _police: PoliceDispatcher
var _player: PlayerController
var _failed: Array[String] = []
var _t := 0.0
var _held_ms := 0
var _trace := false
var _focus: Node3D = null
## The getaway's levels (--levels=1,2), seed, fixed start and time limit.
var _levels: Array = [1, 2, 3, 4]
var _seed := 1
var _start := Vector2.INF
var _limit := 0.0
var _rng := RandomNumberGenerator.new()
## The Wanted autoload (a script run with --script can't name autoloads).
var W: Node
const STREETS_READY := 150.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_trace = args.has("trace")
	var only: Array = str(args.get("only", "patrol,lights,respond,sight,force,box,out,stall,search,escape")).split(",")
	var runs := int(args.get("runs", "1"))
	_levels = Array(str(args.get("levels", args.get("level", "1,2,3,4"))).split(",")).map(func(x: String) -> int: return int(x))
	_seed = int(args.get("seed", "1"))
	_limit = float(args.get("limit", "0"))
	if args.has("start"):
		var xz: PackedStringArray = str(args["start"]).split(",")
		_start = Vector2(float(xz[0]), float(xz[1]))
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	W = root.get_node("Wanted")
	W.play_panels = false
	W.clear()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	await process_frame
	await process_frame
	_net = _world.network
	_police = _main.get_node("Police")
	_player = _main.get_node("Player")
	_focus = _player
	physics_frame.connect(_track)
	await _world.wait_until_settled()
	if "patrol" in only:
		await _patrol_test()
	if "lights" in only:
		await _lights_test()
	if "respond" in only:
		await _respond_test()
	if "sight" in only:
		await _sight_test()
	if "force" in only:
		await _force_test()
	if "box" in only:
		await _box_test()
	if "out" in only:
		await _out_test()
	if "stall" in only:
		await _stall_test()
	if "search" in only:
		await _search_test()
	if "escape" in only:
		await _escape_test(runs)
	print("POLICE %.0f s simulated; %.1f s waiting for the streets to load" % [_t, _held_ms / 1000.0])
	if _failed.is_empty():
		print("POLICE all passed")
		quit(0)
	else:
		print("POLICE FAILED: %s" % ", ".join(_failed))
		quit(1)


func _track() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	var f := _focus if _focus != null and is_instance_valid(_focus) else _player
	var p := _player.global_position if f == _player else f.global_position
	_hold_for_streets(Vector2(p.x, p.z), STREETS_READY)
	# Real police cars near the player need their streets too; ones further
	# off are beyond the full-detail radius anyway, and holding for them
	# would unload the player's streets and load them back, over and over.
	for u in _police.units:
		if is_instance_valid(u) and u.car != null:
			var q := u.car.global_position
			if q.distance_to(p) < 250.0:
				_hold_for_streets(Vector2(q.x, q.z), 60.0)


## Run faster than real time, the streamer can fall behind: the clock
## waits for the full-detail chunks round the player (the game never waits).
func _hold_for_streets(p: Vector2, radius: float) -> void:
	var s := _world.streamer
	if Time.get_ticks_msec() < _hold_off_until:
		return # a hold timed out lately: don't stall frame after frame
	if _streets_ready(s, p, radius):
		return
	var t0 := Time.get_ticks_msec()
	s._focus = p
	s._has_focus = true
	while not _streets_ready(s, p, radius) and Time.get_ticks_msec() - t0 < 20000:
		s._update()
		s._reap()
		s._attach_finished(4)
		OS.delay_msec(3)
	_held_ms += Time.get_ticks_msec() - t0
	if not _streets_ready(s, p, radius):
		# A chunk that won't come: say which, and stop waiting for it (a
		# hold every frame would freeze the run).
		var missing: Array[Vector2i] = []
		for c in s._cells_within(p, radius):
			if s._dist(c, p) <= radius and not s._near.has(c):
				missing.append(c)
				_gave_up[c] = true
		print("POLICE streets near (%.0f, %.0f) not ready after 20 s; going on without %s (no holds for a minute)" % [p.x, p.y, missing])
		_hold_off_until = Time.get_ticks_msec() + 60000


## Wanted.seen_in_chase when the last getaway ended (before it's cleared).
var _seen_in_chase_at_end := 0.0


## Chunks that didn't load after a 20 s hold: not waited for again.
var _gave_up := {}
## A getaway run is cut short after this much real time (ms).
const WALL_LIMIT_MS := 45 * 60 * 1000
## Wall clock (ms) before which streets aren't waited for (after a timeout).
var _hold_off_until := 0


func _streets_ready(s: ChunkStreamer, p: Vector2, radius: float) -> bool:
	for c in s._cells_within(p, radius):
		if s._dist(c, p) <= radius and not s._near.has(c) and not _gave_up.has(c):
			return false
	return true


func _result(name: String, ok: bool, text: String) -> void:
	print("POLICE %s %s: %s" % [name, "ok" if ok else "FAIL", text])
	if not ok:
		_failed.append(name)


func _wait(secs: float) -> void:
	var until := _t + secs
	while _t < until:
		await physics_frame


# --- helpers --------------------------------------------------------------------------------

## Clears everything: not wanted, no units, the player on foot at p.
func _reset(p: Vector2, dir := Vector2(0, -1)) -> void:
	_police.patrols = false
	W.debug_watch(false)
	W.clear()
	for u in _police.units.duplicate():
		_police.drop_unit(u)
	for rb in _police.roadblocks:
		if is_instance_valid(rb):
			rb.clear()
	_police.roadblocks.clear()
	for s in get_nodes_in_group("paint_strips"):
		s.queue_free()
	if _player.vehicle != null:
		var car := _player.vehicle
		_player.exit_vehicle(_main)
		_player.model.visible = true
		_main.cars.erase(car)
		car.queue_free()
	_player.body_paint.revive()
	_player.input_enabled = false
	_player.place(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.1, p.y)))
	_player.set_physics_process(true)
	_main.camera_rig.target = _player
	_main.camera_rig.snap_to_target()
	_world.streamer.refresh()
	_focus = _player
	_police.stats["caught_by"] = ""
	_police.stats["officers_out"] = 0
	_police.stats["replaced"] = 0
	for k: String in _police.stats:
		if _police.stats[k] is int:
			_police.stats[k] = 0
	_police.spawn_log.clear()
	await _wait(0.3)
	await _world.wait_until_settled()


func _ground_y(p: Vector2) -> float:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var h := _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 8.0, p.y), Vector3(p.x, h - 4.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return h if hit.is_empty() else (hit["position"] as Vector3).y


## [point in the right-hand lane of the nearest street, its direction].
func _on_street(p: Vector2) -> Array:
	var hit := _net.nearest_on_streets(p, 400.0)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along: float = clampf(hit["along"], 10.0, maxf(10.0, e.length - 10.0))
	var sp: Array = RoadNetwork.sample(e.points, along)
	var dir: Vector2 = sp[1]
	var fwd := e.oneway != -1
	if not fwd:
		dir = -dir
	return [(sp[0] as Vector2) + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, fwd), dir, e]


## Puts the player in a fresh car at p facing dir.
func _player_car(p: Vector2, dir: Vector2, model := "civique") -> Car:
	var car := Car.new()
	car.model_id = model
	car.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	car.name = "TestRunner"
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.3, p.y))
	car.reset_physics_interpolation()
	_main.cars.append(car)
	_player.enter_vehicle(car)
	_main.camera_rig.target = car
	_main.camera_rig.set_vehicle_mode(true)
	_main.camera_rig.snap_to_target()
	return car


## A physical unit of a force standing at p facing dir.
func _unit_at(force: String, p: Vector2, dir: Vector2) -> PoliceUnit:
	var u := _police.new_unit(force)
	u.place_physical(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.35, p.y)), _main)
	return u


func _curb_dist(n: Node3D) -> float:
	var p := Vector2(n.global_position.x, n.global_position.z)
	var hit := _net.nearest_on_streets(p, 100.0)
	if hit.is_empty():
		return 100.0
	return maxf(0.0, float(hit["dist"]) - (hit["edge"] as RoadNetwork.RoadEdge).half_width)


func _spawn_point() -> Vector2:
	var s := _world.get_spawn().origin
	return Vector2(s.x, s.z)


# --- the tests -------------------------------------------------------------------------------

func _patrol_test() -> void:
	var st := _on_street(_spawn_point())
	await _reset(st[0], st[1])
	_police.patrols = true
	# One patrol car right here too, so there's always one to watch.
	var here := _unit_at("city", st[0] + (st[1] as Vector2) * 15.0, st[1])
	here.order(PoliceUnit.Role.PATROL, _police._patrol_point("city", st[0]), _police.clock)
	var worst := 0.0
	var seen_units := {}
	var phys_time := 0.0
	var t0 := _t
	while _t - t0 < 70.0:
		await physics_frame
		for u in _police.units:
			if not is_instance_valid(u):
				continue
			seen_units[u.name] = u.force
			if u.car != null and u.role == PoliceUnit.Role.PATROL:
				phys_time += 1.0 / 60.0
				worst = maxf(worst, _curb_dist(u.car))
	var city := 0
	var fip := 0
	for k: String in seen_units:
		if seen_units[k] == "city":
			city += 1
		else:
			fip += 1
	var near_ring := _police._near_ring(st[0], 900.0)
	var ok := city >= PoliceDispatcher.PATROL_CITY and worst < 3.5 and (fip >= 1 or not near_ring)
	_result("patrol", ok, "%d city and %d FIP patrols (ring %s); %.0f s of patrol cars driving near the player, worst %.1f m past the curb" % [
		city, fip, "near" if near_ring else "far", phys_time, worst])


func _lights_test() -> void:
	# A signalled junction in town with a long two-way approach.
	var best_nid := ""
	var best_inc: RoadNetwork.Incident = null
	var sp := _spawn_point()
	var ids := _net.signal_nodes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return (_net.nodes[a] as Vector2).distance_to(sp) < (_net.nodes[b] as Vector2).distance_to(sp))
	for nid: String in ids:
		if not _world.is_in_play_area(_net.nodes[nid]):
			continue
		var opp: RoadNetwork.Incident = null
		for inc: RoadNetwork.Incident in _net.incidents[nid]:
			if inc.edge.oneway == 0 and inc.edge.length > 110.0 and not inc.edge.bridge:
				# One straight on through the junction.
				for o: RoadNetwork.Incident in _net.incidents[nid]:
					if o != inc and o.dir.dot(inc.dir) < -0.9 and o.edge.length > 60.0 and o.edge.oneway == 0:
						opp = o
				if opp != null:
					best_inc = inc
					break
		if best_inc != null:
			best_nid = nid
			break
	if best_nid == "":
		_result("lights", false, "no signalled junction with a long approach")
		return
	var c: Vector2 = _net.nodes[best_nid]
	var start := c + best_inc.dir * 95.0
	var lane := _on_street(start)
	var dir := -best_inc.dir
	var start_p: Vector2 = start + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(best_inc.edge, true)
	# Keep the player out of it, nearby.
	await _reset(c + best_inc.dir * 40.0 + Vector2(-dir.y, dir.x) * 25.0)
	_police.patrols = false
	var phase := TrafficSignal.phase_of(best_inc.dir)
	# Wait for its light to go amber, so it arrives on red.
	var wait0 := _t
	while TrafficSignal.lamp_at(best_nid, phase) != 1 and _t - wait0 < 60.0:
		await physics_frame
	var u := _unit_at("city", start_p, dir)
	var goal: Vector2 = c - best_inc.dir * 80.0
	u.order(PoliceUnit.Role.PATROL, Vector3(goal.x, 0, goal.y), _police.clock)
	var stopped := 0.0
	var max_stop := 0.0
	var entered_on := -1
	var was_inside := false
	var stop_gap := INF
	var t0 := _t
	while _t - t0 < 60.0 and is_instance_valid(u) and u.car != null:
		await physics_frame
		var cp := Vector2(u.car.global_position.x, u.car.global_position.z)
		var dist := cp.distance_to(c)
		var inside := dist < 7.0
		if absf(u.car.speed) < 0.4 and dist < 40.0 and not was_inside and entered_on < 0:
			stopped += 1.0 / 60.0
			max_stop = maxf(max_stop, stopped)
			stop_gap = minf(stop_gap, dist)
		if inside and not was_inside and entered_on < 0:
			entered_on = TrafficSignal.lamp_at(best_nid, phase)
		was_inside = inside
		if _trace and Engine.get_physics_frames() % 30 == 0:
			print("  lights t=%.1f dist %.1f speed %.1f hold %.1f along %.1f state %s lamp %d route %s" % [_t - t0, dist, u.car.speed, u.pilot.hold_at, u.pilot.along, u.pilot.state, TrafficSignal.lamp_at(best_nid, phase), u.pilot.route != null])
		if entered_on >= 0 and dist > 25.0:
			break
	var lamp: String = ["red", "amber", "green", "not yet"][entered_on if entered_on >= 0 else 3]
	var ok := max_stop > 2.0 and entered_on == 2
	_result("lights", ok, "at %s: waited %.1f s at the red, %.1f m from the junction's middle, went through on %s" % [
		_world.street_name_at(c, 30.0), max_stop, stop_gap, lamp])
	_police.drop_unit(u)
	_police.patrols = true


func _respond_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(150, 80))
	await _reset(st[0], st[1])
	_police.patrols = false
	var car := _player_car(st[0], st[1])
	await _wait(1.0)
	W.report_crime("paint_car", car.global_position)
	var t0 := _t
	var first: PoliceUnit = null
	var worst_off := 0.0
	var arrived := -1.0
	var spawn_d := 0.0
	var hidden := ""
	var again := _t + 12.0
	while _t - t0 < 120.0:
		await physics_frame
		# Still at it, so the call stays open (level 1 lapses in 20 s unseen).
		if _t > again:
			again = _t + 12.0
			W.report_crime("paint_car", car.global_position)
		if first == null and not _police.units.is_empty():
			first = _police.units[0]
			spawn_d = float(_police.spawn_log[0]["dist"])
			hidden = str(_police.spawn_log[0]["hidden_by"])
		if _trace and Engine.get_physics_frames() % 120 == 0:
			for uu in _police.units:
				print("  respond t=%.0f %s %s %s at %.0f m, physical %s, state %s" % [_t - t0, uu.name, uu.role_name(), uu.follower != null, uu.position().distance_to(car.global_position), uu.car != null, uu.pilot.state if uu.pilot != null else "-"])
		if first == null or not is_instance_valid(first):
			continue
		var p := first.position()
		if first.car != null and first.role == PoliceUnit.Role.RESPOND:
			worst_off = maxf(worst_off, _curb_dist(first.car))
		if p.distance_to(car.global_position) < 30.0:
			arrived = _t - t0
			break
	var ok := first != null and arrived > 0.0 and spawn_d >= PoliceDispatcher.SPAWN_L1.x - 1.0 and spawn_d <= PoliceDispatcher.SPAWN_MAX + 1.0 and hidden != "" and worst_off < 3.5
	_result("respond", ok, "a %s unit placed %.0f m off (hidden: %s), %s; worst %.1f m past the curb while responding" % [
		first.force if first != null else "-", spawn_d, hidden, ("within 30 m after %.1f s" % arrived) if arrived > 0.0 else "never arrived", worst_off])


func _sight_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(-120, 60))
	await _reset(st[0], st[1])
	_police.patrols = false
	var dir: Vector2 = st[1]
	var u := _unit_at("city", st[0], dir)
	W.debug_set_level(2)
	# In the open: on the street ahead.
	var ahead: Vector2 = st[0] + dir * 35.0
	_player.place(Transform3D(Basis.IDENTITY, Vector3(ahead.x, _ground_y(ahead), ahead.y)))
	await _wait(0.6)
	var seen_open := u.sees
	# Behind a building: find one beside the street and stand past it (its
	# chunks loaded first: the rays look ~90 m out from the unit).
	var ucp := Vector2(u.car.global_position.x, u.car.global_position.z)
	_hold_for_streets(ucp, 90.0)
	await _wait(0.2) # new bodies join the physics space on a step
	var spot := _behind_building(u)
	if spot == Vector3.INF:
		# Facades and their collision come after the streets: give them a
		# moment more.
		await _world.wait_until_settled()
		await _wait(0.5)
		spot = _behind_building(u)
	var seen_behind := true
	if spot != Vector3.INF:
		_player.place(Transform3D(Basis.IDENTITY, spot))
		await _wait(0.6)
		seen_behind = u.sees
	var ok := seen_open and spot != Vector3.INF and not seen_behind
	_result("sight", ok, "seen in the open 35 m ahead: %s; behind a building%s: %s" % [
		seen_open, (" (%.0f m off)" % spot.distance_to(u.car.global_position)) if spot != Vector3.INF else " (none found)", "seen" if seen_behind else "not seen"])
	W.clear()
	_police.drop_unit(u)


## A point on the ground past a building from the unit's eye, inside its
## cone and sight range, or INF.
func _behind_building(u: PoliceUnit) -> Vector3:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var eye := u.car.global_transform * Vector3(0, 1.35, -0.4)
	var fwd := -u.car.global_basis.z
	for k in 24:
		var a := deg_to_rad(-55.0 + 110.0 * float(k) / 23.0)
		var d := fwd.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(eye, eye + d * 60.0, Layers.SOLID)
		q.exclude = [u.car.get_rid()]
		var h := space.intersect_ray(q)
		if h.is_empty() or not str((h["collider"] as Node).get_path()).contains("Building"):
			continue
		var near := eye.distance_to(h["position"])
		if near < 6.0 or near > 45.0:
			continue
		# Back from beyond: the building's far wall.
		for far: float in [near + 14.0, near + 22.0, near + 32.0]:
			var from := eye + d * far
			var back := PhysicsRayQueryParameters3D.create(from, eye, Layers.SOLID)
			var hb := space.intersect_ray(back)
			if hb.is_empty():
				continue
			var wall: Vector3 = hb["position"]
			if wall.distance_to(eye) < near + 2.0:
				continue
			var p := wall + d * 2.5
			var gp := Vector2(p.x, p.z)
			var gy := _ground_y(gp)
			var stand := Vector3(p.x, gy, p.z)
			# Standing room, not inside anything.
			var up := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.3, stand + Vector3.UP * 2.0, Layers.SOLID)
			if space.intersect_ray(up).is_empty() and stand.distance_to(eye) < 85.0:
				return stand
	return Vector3.INF


func _force_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(60, -40))
	await _reset(st[0], st[1])
	_police.patrols = false
	var car := _player_car(st[0], st[1])
	await _wait(0.5)
	var lines: Array[String] = []
	var ok := true
	for lvl in range(1, 5):
		W.debug_set_level(lvl)
		W.debug_watch(true)
		var t0 := _t
		var got := {}
		while _t - t0 < 30.0:
			await physics_frame
			got = _counts()
			if _force_ok(lvl, got):
				break
		var good := _force_ok(lvl, got)
		var bad_spawns := 0
		var near := INF
		var far := 0.0
		for s: Dictionary in _police.spawn_log:
			var d := float(s["dist"])
			near = minf(near, d)
			far = maxf(far, d)
			var rng: Vector2 = _police._spawn_range() if int(s.get("level", 0)) == _police.level else (PoliceDispatcher.SPAWN_L1 if int(s.get("level", 0)) == 1 else Vector2(PoliceDispatcher.SPAWN_MIN, PoliceDispatcher.SPAWN_MAX))
			if d < rng.x - 1.0 or d > rng.y + 1.0 or str(s["hidden_by"]) == "":
				bad_spawns += 1
		good = good and bad_spawns == 0
		ok = ok and good
		lines.append("level %d: %d city, %d FIP%s in %.1f s (%s)" % [lvl, int(got.get("city", 0)), int(got.get("fip", 0)), ", the Paint Tank" if int(got.get("tactical", 0)) > 0 else "", _t - t0, "ok" if good else "WRONG"])
	var spawns := _police.spawn_log.size()
	var reasons := {}
	for s: Dictionary in _police.spawn_log:
		reasons[s["hidden_by"]] = int(reasons.get(s["hidden_by"], 0)) + 1
	_result("force", ok, "%s; %d placed, all 300-600 m off (240-360 at level 1) and out of sight (%s)" % ["; ".join(lines), spawns, str(reasons)])
	W.debug_watch(false)
	W.clear()
	await _wait(0.5)


func _counts() -> Dictionary:
	var out := {"city": 0, "fip": 0, "tactical": 0}
	for u in _police.units:
		if is_instance_valid(u) and not u.spent and u.role != PoliceUnit.Role.LEAVE and u.roadblock == null:
			out[u.force] = int(out[u.force]) + 1
	return out


func _force_ok(lvl: int, got: Dictionary) -> bool:
	var mix: Dictionary = PoliceDispatcher.MIX[lvl]
	return int(got.get("city", 0)) == int(mix.get("city", 0)) and int(got.get("fip", 0)) == int(mix.get("fip", 0)) and (int(got.get("tactical", 0)) == (1 if lvl >= 4 else 0))


func _box_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(-60, -120))
	await _reset(st[0], st[1])
	_police.patrols = false
	var dir: Vector2 = st[1]
	var car := _player_car(st[0] + dir * 30.0, dir)
	# Sitting there with a foot on the brake.
	var foot := Pedals.new()
	foot.handbrake = true
	car.ai_controls = foot
	await _wait(1.0)
	var u := _unit_at("city", st[0] - dir * 10.0, dir)
	W.debug_set_level(2)
	W.debug_watch(true)
	var caught := [false]
	var cb := func(_r: Dictionary) -> void: caught[0] = true
	W.arrested.connect(cb)
	var t0 := _t
	while _t - t0 < 40.0 and not caught[0]:
		await physics_frame
		if _trace and Engine.get_physics_frames() % 60 == 0 and u.pilot != null:
			var rel := car.global_transform.affine_inverse() * u.car.global_position
			print("  box t=%.0f state %s dist %.1f rel %s touching %s kmh %.1f boxt %.1f level %d" % [_t - t0, u.pilot.state, u.car.global_position.distance_to(car.global_position), rel, _police._touching, car.speed * 3.6, _police._box_t, W.level])
	W.arrested.disconnect(cb)
	var how := str(_police.stats["caught_by"])
	_result("box", caught[0] and how == "boxed_in", "%s after %.1f s (police: %s)" % ["caught, " + how if caught[0] else "not caught", _t - t0, u.pilot.state if is_instance_valid(u) and u.pilot != null else "-"])
	W.debug_watch(false)


func _out_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(100, 100))
	await _reset(st[0], st[1])
	_police.patrols = false
	var dir: Vector2 = st[1]
	W.debug_set_level(2)
	await _wait(0.5)
	var u := _unit_at("city", st[0], dir)
	u.order(PoliceUnit.Role.CHASE, _player.global_position, _police.clock)
	await _wait(0.5)
	u.dismount()
	await _wait(1.0)
	var o: Officer = u.officers[0]
	var in_aim_before := o.is_in_group(AimAssist.GROUP)
	for i in 3:
		o.take_paint_hit(1, _player, o.global_position + Vector3.UP * 1.2)
	await _wait(0.5)
	var vest := o._vest != null and o._held_marker != null
	var out_ok := o.is_out() and vest and not o.is_in_group(AimAssist.GROUP) and o.collision_layer == 0 and o.model.hands_up > 0.5
	# A ball at it now passes through.
	var shots := PaintShots.find(self)
	var hits := [0]
	var cb := func(info: Dictionary) -> void:
		if info.get("target") == o:
			hits[0] += 1
	shots.hit.connect(cb)
	var from := o.global_position + o.facing() * 6.0 + Vector3.UP * 1.3
	shots.fire(from, (o.global_position + Vector3.UP * 1.2 - from), _player, PaintWeapons.ISLANDER)
	await _wait(0.5)
	shots.hit.disconnect(cb)
	# The other one out too: the unit's spent and a replacement is sent.
	var active_before := _police._active().size()
	var o2: Officer = u.officers[1]
	for i in 3:
		o2.take_paint_hit(1, _player, o2.global_position + Vector3.UP * 1.2)
	var t0 := _t
	var replaced := false
	while _t - t0 < 15.0:
		await physics_frame
		if int(_police.stats["replaced"]) > 0:
			replaced = true
			break
	var said: Array = []
	for l: Array in _police.radio.log:
		said.append(l[1])
	if _trace:
		print("  out: level %d, exit clock %.1f, state %d, clock %.1f, spawn tries rejected %d" % [W.level, o._exit_t, o.state, _police.clock, int(_police.stats["spawn_rejected"])])
	var ok: bool = in_aim_before and out_ok and hits[0] == 0 and u.spent and replaced
	_result("out", ok, "out: %s, vest and marker up: %s, hands up %.1f, in the targets: %s, hits after: %d; both out: unit spent %s, replacement sent %s (active %d before); exit: \"%s\"" % [
		o.is_out(), vest, o.model.hands_up, o.is_in_group(AimAssist.GROUP), hits[0], u.spent, replaced, active_before, str(o._exit.get("say", ""))])
	W.clear()


func _stall_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(-150, -40))
	await _reset(st[0], st[1])
	_police.patrols = false
	var dir: Vector2 = st[1]
	W.debug_set_level(2)
	var u := _unit_at("fip", st[0], dir)
	u.order(PoliceUnit.Role.SEARCH, Vector3(st[0].x, 0, st[0].y) + Vector3(dir.x, 0, dir.y) * 200.0, _police.clock)
	await _wait(2.0)
	# Paint from the player: on a police car it counts as police paint.
	var pc := PaintCoverage.of(u.car)
	for i in 30:
		pc.add_coverage(0.05, Vector3(0, 1.0, 0), PaintWeapons.COLOURS[0], true)
	await _wait(2.0)
	var on_foot := u.foot_officers().size()
	var ok := u.car.stalled and u.dismounted and on_foot == 2
	_result("stall", ok, "police paint %.0f%%: stalled %s, officers on foot %d" % [pc.police_coverage * 100.0, u.car.stalled, on_foot])
	W.clear()


func _search_test() -> void:
	var st := _on_street(_spawn_point() + Vector2(40, 140))
	await _reset(st[0], st[1])
	_police.patrols = false
	var dir: Vector2 = st[1]
	var car := _player_car(st[0], dir)
	_police.stats["caught_by"] = ""
	W.clear()
	await _wait(0.2)
	W.debug_set_level(2)
	W.debug_watch(true)
	# Let them come and see the player.
	var t0 := _t
	var stepped := false
	while _t - t0 < 90.0 and not _police.seen_recently(0.5):
		await physics_frame
		# Still unseen after a while (they came in quietly, or stopped short
		# round a corner): step into the nearest one's street, ahead of it.
		if _t - t0 > 45.0 and not stepped:
			stepped = true
			_step_in_front(car)
		if W.level != 2:
			# Something ended it (left over from an earlier test): say what,
			# and start it again.
			print("POLICE search: level went to %d at t=%.1f (caught_by '%s', player in car %s); setting 2 again" % [W.level, _t - t0, _police.stats["caught_by"], _player.vehicle == car])
			W.debug_set_level(2)
			W.debug_watch(true)
	var saw := _police.seen_recently(0.5)
	W.debug_watch(false)
	# Gone: the player's car somewhere else entirely, out of sight.
	var lost_at: Vector3 = W.last_known_position
	var away := _on_street(st[0] + Vector2(500, -400))
	_hold_for_streets(away[0], 60.0)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-away[1].x, -away[1].y)), Vector3(away[0].x, _ground_y(away[0]) + 0.3, away[0].y))
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3.ZERO
	# First they go where you'd be by now, on your last heading.
	await _wait(PoliceDispatcher.LOST_AFTER + 2.0)
	var guessing := 0
	for u in _police.units:
		if u.role == PoliceUnit.Role.RESPOND:
			guessing += 1
	await _wait(PoliceDispatcher.PREDICT_TIME + 4.0)
	var searching := 0
	var inside := 0
	var r: float = W.search_radius
	for u in _police.units:
		if u.role == PoliceUnit.Role.SEARCH:
			searching += 1
			if u.goal.distance_to(lost_at) <= r + 60.0:
				inside += 1
	var ok: bool = saw and guessing >= 3 and searching >= 3 and inside == searching and W.level == 2
	_result("search", ok, "seen first: %s; %d units heading for where it would be by now; %d s after losing them, %d of %d units searching, %d with a point inside the %.0f m circle" % [
		saw, guessing, int(PoliceDispatcher.LOST_AFTER + PoliceDispatcher.PREDICT_TIME + 6.0), searching, _police._active().size(), inside, r])
	W.clear()


## Puts the car 35 m ahead of the nearest police car, on its street.
func _step_in_front(car: Car) -> void:
	var best: PoliceUnit = null
	for u in _police._active():
		if u.car != null and (best == null or u.car.global_position.distance_to(car.global_position) < best.car.global_position.distance_to(car.global_position)):
			best = u
	if best == null:
		return
	var fwd := -best.car.global_basis.z
	var st := _on_street(Vector2(best.car.global_position.x, best.car.global_position.z) + Vector2(fwd.x, fwd.z).normalized() * 35.0)
	_hold_for_streets(st[0], 60.0)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-st[1].x, -st[1].y)), Vector3(st[0].x, _ground_y(st[0]) + 0.3, st[0].y))
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3.ZERO


# --- the getaway ------------------------------------------------------------------------------

## A fleeing driver: the player's car, driven by an autopilot to somewhere
## far off and away from the police, picking a new place when it gets
## there or when police are ahead on the way. Like a decent player who
## knows the town: fast, against one-way streets, never stopping.
func _escape_test(runs: int) -> void:
	var limits := [0.0, 90.0, 240.0, 360.0, 900.0]
	var report: Array[String] = []
	for lvl: int in _levels:
		for run in runs:
			_rng.seed = hash("%d/%d/%d" % [_seed, lvl, run])
			seed(_rng.randi())
			_police._rng.seed = _rng.randi()
			var near := _start if _start != Vector2.INF else _random_start()
			var limit := _limit if _limit > 0.0 else float(limits[lvl])
			var res := await _getaway(lvl, near, limit)
			var line := "GETAWAY level=%d run=%d seed=%d start=%.0f,%.0f %s" % [lvl, run + 1, _seed, near.x, near.y, res]
			report.append(line)
			print(line)
	_result("escape", true, "\n    " + "\n    ".join(report))


## A street inside the bypass 200-1300 m from the spawn, by the seed.
func _random_start() -> Vector2:
	var sp := _spawn_point()
	var ids := _net.nodes.keys()
	ids.sort()
	for tries in 200:
		var nid: String = ids[_rng.randi() % ids.size()]
		var q: Vector2 = _net.nodes[nid]
		var d := q.distance_to(sp)
		if q.distance_to(Vector2(-760, -1343)) < 60.0 or q.distance_to(Vector2(815, -765)) < 60.0:
			continue # starts that wedge the test driver off the road at once
		if d > 200.0 and d < 1300.0 and _world.is_in_play_area(q) and _net.degree(nid) >= 2:
			return q
	return sp


func _getaway(lvl: int, near: Vector2, limit: float) -> String:
	var st := _on_street(near)
	await _reset(st[0], st[1])
	_police.patrols = false
	var car := _player_car(st[0], st[1], "civique")
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = _net
	ap.obey_oneway = false
	# As fast as the car goes, less a little (a decent driver).
	ap.cruise_speed_kmh = minf(car.full_top_speed() * 3.6 * 0.9, 150.0) if car.has_method("full_top_speed") else 110.0
	ap.chase_speed_kmh = 150.0
	car.add_child(ap)
	await _wait(0.5)
	var caught := [false]
	var cb := func(_r: Dictionary) -> void: caught[0] = true
	W.arrested.connect(cb)
	W.debug_set_level(lvl)
	# A chase from level 2 starts with someone on you: a unit 70 m behind, the rest on
	# their way (they're told where you are for the first few seconds, then
	# it's their own eyes).
	# (Level 1 is a phone call: the cruiser comes from wherever it is.)
	if lvl >= 2:
		var behind: Vector2 = st[0] - (st[1] as Vector2) * 70.0
		var lead := _unit_at("city" if lvl < 3 else "fip", _on_street(behind)[0], st[1])
		lead.order(PoliceUnit.Role.CHASE, car.global_position, _police.clock)
	W.debug_watch(true)
	var t0 := _t
	_seen_in_chase_at_end = 0.0
	var dest := _flee_point(car)
	ap.drive_to(dest)
	var next_pick := _t + 25.0
	var top := lvl
	var seen_time := 0.0
	var hits := 0.0
	var max_cov := 0.0
	var slow := 0.0
	var backing := 0.0
	var washed := false
	var washed_clear := false
	var last_level := lvl
	var to_wash := false
	var wash_spot := {}
	var wash_start := Vector2.INF
	var wash_in := false
	var washes := _main.get_node_or_null("CarWashes") as CarWashes
	var avoid_at := -100.0
	var reverse := Pedals.new()
	reverse.brake = 0.8 # stopped, the brake pedal reverses
	var wall0 := Time.get_ticks_msec()
	var wall_out := false
	while _t - t0 < limit and not caught[0] and W.level > 0:
		await physics_frame
		# A run that's taken this long in real time is stuck somewhere: end
		# it rather than hold the whole batch up.
		if Time.get_ticks_msec() - wall0 > WALL_LIMIT_MS:
			print("POLICE run stopped after %d min of real time at t=%.0f s, car at (%.0f, %.0f)" % [WALL_LIMIT_MS / 60000, _t - t0, car.global_position.x, car.global_position.z])
			wall_out = true
			break
		if W.debug_watching and _t - t0 > (1.0 if lvl == 1 else 8.0):
			W.debug_watch(false)
		if W.level > 0:
			last_level = W.level
		if _police.seen_recently(0.3):
			seen_time += 1.0 / 60.0
		_seen_in_chase_at_end = maxf(_seen_in_chase_at_end, W.seen_in_chase)
		top = maxi(top, W.level)
		var pc := car.get_node_or_null("PaintCoverage") as PaintCoverage
		if pc != null:
			max_cov = maxf(max_cov, pc.police_coverage)
		# Wedged (a dead end, a tight corner, a cruiser in the way): a player
		# backs straight out for a couple of seconds, then picks a way.
		if backing > 0.0:
			backing -= 1.0 / 60.0
			if backing <= 0.0:
				# Off the street (a yard, a lot)? Back onto it first, then run.
				var here := Vector2(car.global_position.x, car.global_position.z)
				var hit := _net.nearest_on_streets(here, 120.0)
				if not hit.is_empty() and float(hit["dist"]) > (hit["edge"] as RoadNetwork.RoadEdge).half_width + 1.0:
					var onto: Vector2 = _on_street(here)[0]
					dest = Vector3(onto.x, 0, onto.y)
					ap.drive_to(dest, true)
					next_pick = _t + 8.0
				else:
					dest = _flee_point(car)
					ap.drive_to(dest)
					next_pick = _t + 25.0
			continue
		var arrived := (car.global_position.distance_to(dest) < 30.0 or ap.state == "arrived") and not to_wash
		var waiting: bool = to_wash and not wash_in and Vector2(car.global_position.x, car.global_position.z).distance_to(wash_start) < 12.0 and W.wash_too_soon()
		# Lining up for the bay is slow on purpose: not wedged.
		var lining_up: bool = to_wash and (wash_in or waiting)
		slow = slow + 1.0 / 60.0 if not waiting and absf(car.speed) < (0.6 if lining_up else 2.5) and not (to_wash and washes.bay_at(car.global_position) >= 0) else 0.0
		if slow > 1.5:
			slow = 0.0
			backing = 2.0
			to_wash = false
			car.ai_controls = reverse
			continue
		# Out of sight at level 3 or 4 with a car wash near: go for it (the
		# pay-and-spray, if nobody sees you go in).
		if lvl >= 3 and not to_wash and washes != null and not _police.seen_recently(4.0) and W.level > 0:
			var spot := _nearest_wash(washes, car.global_position, 700.0)
			var mouth := CarWashes.way_in(spot, 8.0) if not spot.is_empty() else Vector3.INF
			var near_mouth := _net.nearest_on_streets(Vector2(mouth.x, mouth.z), 120.0) if mouth != Vector3.INF else {}
			if not near_mouth.is_empty():
				# To the street by its way in, then along a drawn line in.
				to_wash = true
				wash_spot = spot
				wash_in = false
				wash_start = near_mouth["pos"]
				dest = Vector3(wash_start.x, car.global_position.y, wash_start.y)
				ap.drive_to(dest, true)
				next_pick = _t + 60.0
		if to_wash and not wash_in and Vector2(car.global_position.x, car.global_position.z).distance_to(wash_start) < 12.0 and W.wash_too_soon():
			# Lie low by the wash until it would count.
			if ap.mode != CarAutopilot.Mode.IDLE:
				ap.stop()
			next_pick = maxf(next_pick, _t + 5.0)
		elif to_wash and not wash_in and Vector2(car.global_position.x, car.global_position.z).distance_to(wash_start) < 12.0:
			wash_in = true
			var o: Vector3 = (wash_spot["xform"] as Transform3D).origin
			var flat := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
			var line := PackedVector2Array([Vector2(car.global_position.x, car.global_position.z), flat.call(CarWashes.way_in(wash_spot, 8.0)), flat.call(CarWashes.way_in(wash_spot, 1.0)), flat.call(o)])
			ap.drive_route(StreetRoute.along(line, {"top_speed": 4.0}), 0.0, o)
			dest = o
			next_pick = _t + 60.0 # (the lie-low wait left it seconds away)
		if to_wash and _police.seen_recently(0.3) and washes.bay_at(car.global_position) < 0:
			to_wash = false # seen on the way: run instead
			arrived = true
		if washes != null and washes.bay_at(car.global_position) >= 0 and W.level > 0:
			washed = true
		# A roadblock ahead: a player sees it and turns off.
		if not to_wash and _roadblock_ahead(car):
			arrived = true
			avoid_at = _t
		if arrived or _t > next_pick or car.stalled:
			if car.stalled:
				break
			to_wash = false
			dest = _flee_point(car)
			ap.drive_to(dest)
			next_pick = _t + 25.0
		if _trace and Engine.get_physics_frames() % (30 if OS.has_environment("FINE") else 120) == 0:
			print("  run L%d at (%.0f, %.0f) t=%.1f level %d seen %s %.0f km/h units %d near %.0f m %s touching %d box %.1f backing %.1f" % [lvl, car.global_position.x, car.global_position.z, _t - t0, W.level, _police.seen_recently(0.3), car.speed * 3.6, _police._active().size(), _nearest_unit(car.global_position), ap.state, _police._touching, _police._box_t, backing])
			for u in _police.units:
				if is_instance_valid(u) and u.car != null and u.position().distance_to(car.global_position) < 300.0:
					print("    %s %s %.0f m %.0f km/h %s sees %s ahead %s at (%.0f, %.0f)" % [u.name, u.role_name(), u.position().distance_to(car.global_position), u.car.speed * 3.6, u.pilot.state if u.pilot != null else "-", u.sees, u.pilot.blocker if u.pilot != null else "", u.position().x, u.position().z])
				elif is_instance_valid(u) and u.follower != null and u.position() != Vector3.INF and u.position().distance_to(car.global_position) < 900.0:
					print("    %s %s %.0f m %.0f km/h virtual goal %.0f m off, %.0f m from the car, at (%.0f, %.0f)" % [u.name, u.role_name(), u.position().distance_to(car.global_position), u.follower.speed * 3.6, u.position().distance_to(u.goal) if u.goal != Vector3.INF else -1.0, u.goal.distance_to(car.global_position) if u.goal != Vector3.INF else -1.0, u.position().x, u.position().z])
	# A wash clears to 0 from wherever you were; the escape clock goes 1 -> 0.
	washed_clear = W.level == 0 and not caught[0] and last_level > 1
	W.arrested.disconnect(cb)
	W.debug_watch(false)
	var secs := _t - t0
	var result := "wall_timeout" if wall_out else "timeout"
	var how := ""
	if caught[0]:
		result = "caught"
		how = str(_police.stats["caught_by"]) if str(_police.stats["caught_by"]) != "" else "painted_out"
	elif W.level == 0:
		result = "escaped"
		# A wash clears to 0 at once; the escape clock drops a level at a time.
		how = "car_wash" if washed_clear else ("clock_in_bay" if washes != null and washes.bay_at(car.global_position) >= 0 else "lost_them")
	elif car.stalled:
		result = "stalled"
	var sts: Dictionary = _police.stats
	return "result=%s secs=%.0f how=%s end_level=%d top_level=%d seen=%.0f paint=%.0f strips=%d slicks=%d roadblocks=%d pits=%d pit_spins=%d tank_shots=%d tank_hits=%d washed=%d officers_out=%d missed_turns=%d cutoffs=%d stakeouts=%d blockers_sent=%d blockers_brought=%d pull_outs=%d height_fixes=%d seen_in_chase=%.0f" % [
		result, secs, how if how != "" else "-", W.level, top, seen_time, max_cov * 100.0, int(sts["strips"]), int(sts["slicks"]),
		int(sts["roadblocks"]), int(sts["pits"]), int(sts["pit_spins"]), int(sts["tank_shots"]), int(sts["tank_hits"]), 1 if washed else 0, int(sts["officers_out"]), int(sts["missed_turns"]), int(sts["cutoffs"]), int(sts["stakeouts"]), int(sts["blockers_sent"]), int(sts["blockers_brought"]), int(sts["pull_outs"]), int(sts["height_fixes"]), _seen_in_chase_at_end]


func _nearest_unit(p: Vector3) -> float:
	var best := INF
	for u in _police.units:
		if is_instance_valid(u):
			best = minf(best, u.position().distance_to(p))
	return best


## A roadblock within 160 m, roughly ahead of the car (that it hasn't
## just turned away from).
func _roadblock_ahead(car: Car) -> bool:
	var fwd := -car.global_basis.z
	for rb in _police.roadblocks:
		if not is_instance_valid(rb):
			continue
		var to := rb.global_position - car.global_position
		to.y = 0.0
		if to.length() < 160.0 and to.normalized().dot(fwd) > 0.8 and car.speed > 3.0:
			return true
	return false


## The nearest car wash bay's spot within `r`, or {}.
func _nearest_wash(w: CarWashes, p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for sp: Dictionary in w.spots:
		var o: Vector3 = (sp["xform"] as Transform3D).origin
		if o.distance_to(p) < bd:
			best = sp
			bd = o.distance_to(p)
	return best


## Somewhere 500-900 m off by road, inside the bypass, away from the police.
func _flee_point(car: Car) -> Vector3:
	var p := Vector2(car.global_position.x, car.global_position.z)
	var police := Vector2.ZERO
	var n := 0
	for u in _police.units:
		var q := u.position()
		if q != Vector3.INF and q.distance_to(car.global_position) < 500.0:
			police += Vector2(q.x, q.z)
			n += 1
	var away := Vector2.ZERO
	if n > 0:
		away = (p - police / n).normalized()
	var best := Vector2.INF
	var best_score := -INF
	var ids := _net.nodes.keys()
	for i in 60:
		var nid: String = ids[randi() % ids.size()]
		var q: Vector2 = _net.nodes[nid]
		var d := q.distance_to(p)
		# Inside the bypass itself (the play area's ring, not the margin round it).
		if d < 450.0 or d > 950.0 or not Geometry2D.is_point_in_polygon(q, _world.play_area) or _net.degree(nid) < 2:
			continue
		var score := (q - p).normalized().dot(away) * 2.0 + randf()
		for rb in _police.roadblocks:
			if is_instance_valid(rb):
				var rp := Vector2(rb.global_position.x, rb.global_position.z)
				if (q - p).normalized().dot((rp - p).normalized()) > 0.7:
					score -= 3.0
		if score > best_score:
			best_score = score
			best = q
	if best == Vector2.INF:
		best = p + Vector2(300, 0)
	return Vector3(best.x, 0, best.y)


## Controls set by hand (a player holding the brake).
class Pedals:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false

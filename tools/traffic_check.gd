extends SceneTree
## Checks town traffic's road manners and its spawning, in the real town:
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/traffic_check.gd -- [--only=a,b] [--trace]
##
##   signal    a car comes up to a red light: stops at the line, goes on green
##   left      a left turn on a green, with cars coming the other way: waits
##             for a gap, turns without touching anyone
##   merge     a car on a side street joins a main road with a car coming
##             along it: gives way, gets on, no collision
##   follow    behind a car at 30 then 60 km/h: the gap holds and grows with
##             speed, and the pedals don't flick between throttle and brake
##   box       the street past a junction is blocked just beyond it: the car
##             waits at the line, not in the junction
##   siren     a police car with its siren on comes up behind: the car pulls
##             right and slows
##   blocked   a car stopped in the lane: driven round
##   spun      a car spun round in the road gets going again the right way
##   react     a traffic car is painted: its driver stops and gets out to
##             stare (no crime counted here: main.gd counts paint); then the
##             player gets in: the driver complains, and it's one "take_car"
##   chase     a wanted chase over 2 km of town (or until the player gets away) (level 2, the police dispatcher, an
##             autopilot driving the player's car away) through traffic:
##             traffic pulls over for the sirens, the police don't plough
##             through it or sit stuck behind it, and it doesn't hold the
##             player up
##   heat      a level 3 chase with sirens (TrafficHeat): some drivers
##             ahead turn off into driveways and pull in (not all of them),
##             the streets thin out but don't empty, no car is placed in
##             the cone ahead of the player; then a driver out of their car
##             scatters from paintballs landing near and leaves it there
##   queue     three traffic cars queued at a red light, the player's car
##             fleeing past them and a police car with its siren after it:
##             the queue edges right, the police car gets by without
##             ploughing into anyone
##   patrol    police patrols on the civil layer among traffic, not wanted:
##             no crashes with it, nobody stuck, nobody through a red
##   witness   the player paints a car with a traffic car watching: the
##             driver reacts and calls it in (the search circle goes where
##             they saw the player); out of their sight quickly, or their
##             car painted, and the call never comes
##   truck     a traffic tow truck and a tractor unit (the odd truck, near
##             the player only) drive a street and through a junction
##   bus       traffic running by University Avenue: a bus appears on its
##             route out of sight, pulls in to the curb at a stop (within a
##             metre of it, not tipped on it), waits and pulls out
##   tow       a traffic car stalled in the street, then the player's own
##             car stalled and left: a rollback comes, pulls up past it,
##             lowers its deck, winches it on, and drives off with it (the
##             player's to the impound lot: ImpoundLot.impound)
##   town      a minute of traffic downtown (TrafficManager): nobody stuck
##             more than STUCK_MAX, nobody inside a building, placed and taken
##             away only out of sight, never more than the cap
## One "TRAFFIC" line per result, with the numbers; exits 1 if any fails.

## "About 20 s". Waiting at a red light (20.5 s at most, TrafficSignal) or
## in the queue for one isn't being stuck (TrafficDriver.stuck_for).
const STUCK_MAX := 20.0
const STREETS_READY := 140.0

var _main: Node
var _world: WorldBuilder
var _net: RoadNetwork
var _rules: JunctionRules
var _cam := Camera3D.new()
var _focus: Node3D = null
var _failed: Array[String] = []
var _t := 0.0
var _trace := false
var _held_ms := 0
var _hold_clock := -1.0
var _crashes: Array = [] # [car name, jolt, time]
var _buildings := {} # chunk key -> Array[PackedVector2Array]
var _police: PoliceDispatcher = null
var _player: PlayerController = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_trace = args.has("trace")
	var only: Array = str(args.get("only", "signal,left,merge,follow,box,siren,blocked,spun,react,witness,chase,heat,queue,patrol,truck,bus,tow,town")).split(",")
	TrafficManager.autostart = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	_net = _world.network
	_rules = JunctionRules.of(_net, _world.data)
	var player: Node3D = _main.get_node("Player")
	_player = player as PlayerController
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.remove_from_group(RoadUsers.PEOPLE_GROUP)
	# No police unless a test asks for them.
	_police = _main.get_node_or_null("Police") as PoliceDispatcher
	if _police != null:
		_police.patrols = false
		for u in _police.units.duplicate():
			_police.drop_unit(u)
	var wanted := root.get_node_or_null("Wanted")
	if wanted != null:
		wanted.set("play_panels", false)
	root.add_child(_cam)
	_cam.make_current()
	physics_frame.connect(_track)
	await _wait(0.5)
	for test: String in ["signal", "left", "merge", "follow", "box", "siren", "blocked", "spun", "react", "witness", "chase", "heat", "queue", "patrol", "truck", "bus", "tow", "town"]:
		if test in only:
			await call("_%s_test" % test)
			_hold_clock = -1.0
	print("TRAFFIC %.0f s simulated; %.1f s waiting for the streets to load" % [_t, _held_ms / 1000.0])
	if _failed.is_empty():
		print("TRAFFIC all passed")
		quit(0)
	else:
		print("TRAFFIC FAILED: %s" % ", ".join(_failed))
		quit(1)


func _track() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	if _hold_clock >= 0.0:
		TrafficSignal.clock = _hold_clock
	if _focus != null and is_instance_valid(_focus):
		_cam.global_position = _focus.global_position + Vector3(0, 3, 0)
		_hold_for_streets(Vector2(_focus.global_position.x, _focus.global_position.z))


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


func _result(name: String, ok: bool, text: String) -> void:
	print("TRAFFIC %s %s: %s" % [name, "ok" if ok else "FAIL", text])
	if not ok:
		_failed.append(name)


# --- helpers ------------------------------------------------------------------------

func _wait(secs: float) -> void:
	var until := _t + secs
	while _t < until:
		await physics_frame


func _settle_at(p: Vector2) -> void:
	_focus = null
	_cam.global_position = Vector3(p.x, _world.terrain.h2(p) + 3.0, p.y)
	_hold_for_streets(p, 200.0)
	await _world.wait_until_settled()
	await _wait(0.3)


func _ground_y(p: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	var h := _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 6.0, p.y), Vector3(p.x, h - 3.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return h if hit.is_empty() else (hit["position"] as Vector3).y


## A car at p facing dir. With `civil`, driven by an autopilot with road
## manners (an ordinary, steady driver: no randomness in the checks).
func _car(model: String, p: Vector2, dir: Vector2, civil := true, livery := "") -> Car:
	var car := Car.new()
	car.model_id = model
	car.livery = livery
	if livery != "":
		car.paint = Color.from_string(str(CarModels.LIVERIES[livery]["colour"]), Color.WHITE)
	else:
		car.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	car.name = "%s_%d" % [model, randi() % 10000]
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.3, p.y))
	car.reset_physics_interpolation()
	car.crashed.connect(func(j: float) -> void:
		if j > 4.0:
			_crashes.append([car.name, j, _t]))
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = _net
	car.add_child(ap)
	if civil:
		ap.corner_accel = 3.2
		ap.brake_accel = 3.0
		ap.cruise_speed_kmh = 90.0
		var c := ap.use_civil_driving(true)
		c.speed_factor = 0.95
		c.reaction = 0.5
		c.patience = 12.0
		c.temper = 0.3
	ap.stop()
	return car


func _ap(car: Car) -> CarAutopilot:
	return car.get_node("Autopilot") as CarAutopilot


func _inbound(inc: RoadNetwork.Incident) -> bool:
	return inc.edge.oneway == 0 or (inc.edge.oneway == 1) != inc.at_start


func _outbound(inc: RoadNetwork.Incident) -> bool:
	return inc.edge.oneway == 0 or (inc.edge.oneway == 1) == inc.at_start


## A point in the right lane `dist` metres from junction nid along incident
## inc, travelling toward the junction (in) or away from it: [pos, dir].
func _lane_point(nid: String, inc: RoadNetwork.Incident, dist: float, toward: bool) -> Array:
	var e := inc.edge
	var along := dist if inc.at_start else e.length - dist
	var sp: Array = RoadNetwork.sample(e.points, clampf(along, 0.5, e.length - 0.5))
	var ab: Vector2 = sp[1]
	# Toward the node: from b to a if the node is a.
	var travel := (-ab if inc.at_start else ab) if toward else (ab if inc.at_start else -ab)
	var forward := travel.dot(ab) > 0.0
	var pos: Vector2 = (sp[0] as Vector2) + Vector2(-travel.y, travel.x) * StreetRoute._lane_offset(e, forward)
	return [pos, travel]


func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, _world.terrain.h2(p), p.y)


## Clean for a street a test uses: ordinary town street, not a bridge,
## nothing odd.
func _plain(e: RoadNetwork.RoadEdge) -> bool:
	return _in_town(e) and not e.bridge and not e.roundabout and not e.is_highway() and e.highway in ["primary", "secondary", "tertiary", "residential", "unclassified", "trunk"]


## Junction nid's degree-4 crossroads ways: [in, opposite (straight on),
## left], or [] if it isn't a clean crossroads.
func _crossroads(nid: String, min_in: float) -> Array:
	var list: Array = _net.incidents[nid]
	if list.size() != 4:
		return []
	for inc: RoadNetwork.Incident in list:
		if not _inbound(inc) or inc.edge.length < min_in or not _plain(inc.edge) or inc.edge.a == inc.edge.b:
			continue
		var opp: RoadNetwork.Incident = null
		var left: RoadNetwork.Incident = null
		var din := -inc.dir
		for o: RoadNetwork.Incident in list:
			if o == inc or not _plain(o.edge) or o.edge.length < 45.0:
				continue
			if o.dir.dot(din) > 0.85:
				opp = o
			elif o.dir.dot(Vector2(-din.y, din.x)) < -0.8:
				left = o
		if opp != null and left != null:
			return [inc, opp, left]
	return []


## Every point of it inside the play area (the streets there get built).
func _in_town(e: RoadNetwork.RoadEdge) -> bool:
	for p in e.points:
		if not _world.is_in_play_area(p):
			return false
	return true


func _nodes_sorted(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	return ids


## Whereabouts on its route the car's front is, and the line it stops at
## for junction nid.
func _line_of(car: Car, nid: String) -> float:
	var ap := _ap(car)
	if ap.civil == null:
		return INF
	for j: Dictionary in ap.civil._junctions:
		if j["nid"] == nid:
			return float(j["line"])
	return INF


func _front(car: Car) -> float:
	return _ap(car).along + float(car.shape.get("length", 4.6)) * 0.5


func _clear_cars(list: Array) -> void:
	for c: Variant in list:
		if c is Node and is_instance_valid(c):
			(_main.get("cars") as Array).erase(c)
			(c as Node).queue_free()
	await _wait(0.3)


func _trace_car(tag: String, car: Car) -> void:
	if not _trace or Engine.get_physics_frames() % 30 != 0:
		return
	var ap := _ap(car)
	var c := ap.civil
	print("  %s t=%.1f %.0f km/h along %.0f state %s thr %.2f brk %.2f hold %s %s lead %.1f lat %.2f %s" % [tag, _t, car.speed * 3.6, ap.along, ap.state, ap.throttle, ap.brake,
		c.holding if c else false, c.reason if c else "", c.leader_gap if c else 0.0, c.lateral if c else 0.0, c.debug_text() if c else ""])


# --- the tests ------------------------------------------------------------------------

## A signalled crossroads, approached straight on at a red light.
func _signal_test() -> void:
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 110.0)
		if not x.is_empty():
			pick = {"nid": nid, "x": x}
			break
	if pick.is_empty():
		_result("signal", false, "no signalled crossroads with a 110 m way in")
		return
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	var phase := TrafficSignal.phase_of(inc.dir)
	var s: Array = _lane_point(nid, inc, 95.0, true)
	var g: Array = _lane_point(nid, opp, 40.0, false)
	await _settle_at(_net.nodes[nid])
	# The light turns red as the car sets off and stays red for a while.
	var clock := 0.0
	for k in 160:
		TrafficSignal.clock = k * 0.25
		if TrafficSignal.lamp_at(nid, phase) == 0 and TrafficSignal.time_to_change(nid, phase) > 15.0:
			clock = k * 0.25
			break
	TrafficSignal.clock = clock
	var car := _car("civique", s[0], s[1])
	_focus = car
	await _wait(0.8)
	_ap(car).drive_to(_v3(g[0]))
	var t0 := _t
	var ran_red := false
	var stopped_at := INF
	var green_t := -1.0
	var through_t := -1.0
	var line := INF
	while _t - t0 < 45.0 and through_t < 0.0:
		await physics_frame
		_trace_car("signal", car)
		line = _line_of(car, nid)
		var lamp := TrafficSignal.lamp_at(nid, phase)
		var front := _front(car)
		if lamp == 0 and front > line + 0.8:
			ran_red = true
		if absf(car.speed) < 0.3 and stopped_at == INF and front < line + 1.0 and front > line - 8.0:
			stopped_at = line - front
		if lamp == 2 and green_t < 0.0:
			green_t = _t
		if green_t >= 0.0 and front > line + 2.0:
			through_t = _t - green_t
	var ok := not ran_red and stopped_at < 6.0 and through_t >= 0.0 and through_t < 8.0
	_result("signal", ok, "junction %s (%s): stopped %.1f m short of the line at the red, ran it: %s; through %.1f s after the green" % [
		nid, inc.edge.name, stopped_at, ran_red, through_t])
	await _clear_cars([car])


## A left turn on a green with three cars coming the other way.
func _left_test() -> void:
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 80.0)
		if x.is_empty():
			continue
		var inc: RoadNetwork.Incident = x[0]
		var opp: RoadNetwork.Incident = x[1]
		var left: RoadNetwork.Incident = x[2]
		if inc.edge.oneway != 0 or opp.edge.oneway != 0 or not _outbound(left) or opp.edge.length < 120.0:
			continue
		pick = {"nid": nid, "x": x}
		break
	if pick.is_empty():
		_result("left", false, "no signalled crossroads with two-way streets to turn left across")
		return
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	var left: RoadNetwork.Incident = pick["x"][2]
	var phase := TrafficSignal.phase_of(inc.dir)
	for k in 160:
		if TrafficSignal.lamp_for(phase, k * 0.25 + float(absi(hash("Signals_%s" % nid)) % 30)) == 2:
			_hold_clock = k * 0.25 + 1.0
			break
	await _settle_at(_net.nodes[nid])
	var me_s: Array = _lane_point(nid, inc, 45.0, true)
	var me_g: Array = _lane_point(nid, left, 40.0, false)
	var cars: Array = []
	var me := _car("civique", me_s[0], me_s[1])
	_focus = me
	cars.append(me)
	var others: Array[Car] = []
	for dist: float in [45.0, 75.0, 105.0]:
		var os: Array = _lane_point(nid, opp, dist, true)
		var og: Array = _lane_point(nid, inc, minf(60.0, inc.edge.length - 10.0), false)
		var o := _car("corollary", os[0], os[1])
		others.append(o)
		cars.append(o)
		_ap(o).drive_to(_v3(og[0]))
	await _wait(0.5)
	_crashes.clear()
	_ap(me).drive_to(_v3(me_g[0]))
	var t0 := _t
	var entered := -1.0
	var gap_at_entry := INF
	var arrived := [false]
	_ap(me).arrived.connect(func() -> void: arrived[0] = true)
	var waited := 0.0
	var np: Vector2 = _net.nodes[nid]
	while _t - t0 < 50.0 and not arrived[0]:
		await physics_frame
		_trace_car("left", me)
		var line := _line_of(me, nid)
		if entered < 0.0 and _front(me) > line + 1.0:
			entered = _t - t0
			# How soon the nearest car still coming would have got there.
			for o: Car in others:
				var rel := Vector2(o.global_position.x, o.global_position.z) - np
				var closing := -o.plane_velocity.dot(rel.normalized())
				if closing > 1.0 and rel.length() > 6.0:
					gap_at_entry = minf(gap_at_entry, rel.length() / closing)
		if entered < 0.0 and absf(me.speed) < 0.5:
			waited += 1.0 / Engine.physics_ticks_per_second
	var hit := false
	for c: Array in _crashes:
		if str(c[0]) == me.name:
			hit = true
	var ok: bool = arrived[0] and not hit and waited > 1.0 and gap_at_entry > 2.5
	_result("left", ok, "junction %s (%s, left onto %s): waited %.1f s at the line, went with the nearest oncoming car %.1f s off, turned without a collision: %s, arrived: %s" % [
		nid, inc.edge.name, left.edge.name, waited, gap_at_entry, not hit, arrived[0]])
	_hold_clock = -1.0
	await _clear_cars(cars)


## A side street onto a main road, with a car coming along it.
func _merge_test() -> void:
	var pick := {}
	var ids := _net.nodes.keys()
	ids.sort()
	for nid: String in ids:
		if _net.degree(nid) != 3 or _net.signal_nodes.has(nid):
			continue
		var minor: RoadNetwork.Incident = null
		for inc: RoadNetwork.Incident in _net.incidents[nid]:
			if _inbound(inc) and _plain(inc.edge) and inc.edge.length > 60.0 and _rules.control(nid, inc.edge) == JunctionRules.Rule.YIELD and JunctionRules.rank(inc.edge) <= 2:
				minor = inc
		if minor == null:
			continue
		# The main road: an inbound way from the left (traffic coming at us
		# in the near lane), long enough to come down, and the way on.
		var from_left: RoadNetwork.Incident = null
		var onto: RoadNetwork.Incident = null
		var din := -minor.dir
		var right := Vector2(-din.y, din.x)
		for o: RoadNetwork.Incident in _net.incidents[nid]:
			if o == minor or JunctionRules.rank(o.edge) < 3 or o.edge.bridge or o.edge.roundabout:
				continue
			if o.dir.dot(right) < -0.6 and _inbound(o) and o.edge.length > 140.0:
				from_left = o
			elif o.dir.dot(right) > 0.6 and _outbound(o) and o.edge.length > 60.0:
				onto = o
		if from_left != null and onto != null:
			pick = {"nid": nid, "minor": minor, "from": from_left, "onto": onto}
			break
	if pick.is_empty():
		_result("merge", false, "no side street joining a main road")
		return
	var nid: String = pick["nid"]
	var minor: RoadNetwork.Incident = pick["minor"]
	var from: RoadNetwork.Incident = pick["from"]
	var onto: RoadNetwork.Incident = pick["onto"]
	await _settle_at(_net.nodes[nid])
	var ms: Array = _lane_point(nid, minor, 40.0, true)
	var mg: Array = _lane_point(nid, onto, 50.0, false)
	var fs: Array = _lane_point(nid, from, 120.0, true)
	var fg: Array = _lane_point(nid, onto, minf(110.0, onto.edge.length - 8.0), false)
	var me := _car("civique", ms[0], ms[1])
	var main_car := _car("halfton", fs[0], fs[1], false)
	_focus = me
	_ap(main_car).cruise_speed_kmh = 50.0
	await _wait(0.5)
	_crashes.clear()
	# Timed so the side-street car gets to the line just ahead of it.
	_ap(main_car).drive_to(_v3(fg[0]))
	await _wait(0.5)
	_ap(me).drive_to(_v3(mg[0]))
	var t0 := _t
	var arrived := [false]
	_ap(me).arrived.connect(func() -> void: arrived[0] = true)
	var closest := INF
	var entered := -1.0
	var main_passed := -1.0
	var np: Vector2 = _net.nodes[nid]
	var yielded := 0.0
	while _t - t0 < 45.0 and not arrived[0]:
		await physics_frame
		_trace_car("merge", me)
		closest = minf(closest, me.global_position.distance_to(main_car.global_position))
		var line := _line_of(me, nid)
		if entered < 0.0 and _front(me) > line + 1.0:
			entered = _t - t0
		var mrel := Vector2(main_car.global_position.x, main_car.global_position.z) - np
		if main_passed < 0.0 and mrel.dot(onto.dir) > 8.0:
			main_passed = _t - t0
		if entered < 0.0 and _ap(me).civil.reason == "yield":
			yielded += 1.0 / Engine.physics_ticks_per_second
	var hit := false
	for c: Array in _crashes:
		hit = hit or str(c[0]) == me.name or str(c[0]) == main_car.name
	var ok: bool = arrived[0] and not hit and closest > 3.0 and (yielded > 0.3 or entered > main_passed)
	_result("merge", ok, "%s onto %s at %s: gave way %.1f s, the car on the main road passed at %.1f s, went at %.1f s, closest %.1f m, collision: %s, joined: %s" % [
		minor.edge.name, onto.edge.name, nid, yielded, main_passed, entered, closest, hit, arrived[0]])
	await _clear_cars([me, main_car])


## Behind a car doing 30 then 60 km/h on a long main road.
func _follow_test() -> void:
	var line := PackedVector2Array()
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or not (e.highway in ["primary", "trunk", "secondary"]) or e.length < 500.0:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.93 and (best == null or e.length > best.length):
			best = e
	if best == null:
		_result("follow", false, "no long straight main road")
		return
	line = StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(40.0))
	var lead := _car("halfton", r.sample(45.0), r.dir_at(45.0), false)
	var me := _car("civique", r.sample(15.0), r.dir_at(15.0))
	_focus = me
	var lap := _ap(lead)
	lap.cruise_speed_kmh = 30.0
	_ap(me).civil.speed_factor = 1.6 # keen to go faster than the car ahead
	await _wait(0.5)
	lap.drive_route(r, 45.0, _v3(r.goal))
	_ap(me).drive_route(StreetRoute.along(line, {"lat_accel": 3.2}), 15.0, _v3(r.goal))
	var t0 := _t
	var samples := {30: [], 60: []}
	var flips := 0
	var last_pedal := 0
	var last_change := -10.0
	while _t - t0 < 50.0 and _ap(me).along < r.length - 60.0:
		await physics_frame
		_trace_car("follow", me)
		if _t - t0 > 22.0:
			lap.cruise_speed_kmh = 60.0
		var ap := _ap(me)
		var pedal := 1 if ap.throttle > 0.05 else (-1 if ap.brake > 0.05 else 0)
		if pedal != 0 and pedal != last_pedal:
			if last_pedal != 0 and _t - last_change < 0.5:
				flips += 1
			last_pedal = pedal
			last_change = _t
		var lv := lead.speed * 3.6
		var gap := ap.civil.leader_gap
		if gap < INF and absf(me.speed - lead.speed) < 1.0:
			for k: int in [30, 60]:
				if absf(lv - k) < 4.0:
					(samples[k] as Array).append(gap)
	var g30 := _mean(samples[30])
	var g60 := _mean(samples[60])
	var c := _ap(me).civil
	var want30 := c.standstill_gap + 30.0 / 3.6 * c.headway
	var want60 := c.standstill_gap + 60.0 / 3.6 * c.headway
	var ok := (samples[30] as Array).size() > 60 and (samples[60] as Array).size() > 60 and g60 > g30 + 4.0 and absf(g30 - want30) < want30 * 0.35 and absf(g60 - want60) < want60 * 0.35 and flips < 3
	_result("follow", ok, "on %s: gap %.1f m at 30 km/h (wanted %.1f), %.1f m at 60 km/h (wanted %.1f); %d/%d samples; throttle-brake flips under 0.5 s: %d" % [
		best.name, g30, want30, g60, want60, (samples[30] as Array).size(), (samples[60] as Array).size(), flips])
	await _clear_cars([lead, me])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x: float in a:
		s += x
	return s / a.size()


## The far side of a junction blocked by a stopped car: wait at the line.
func _box_test() -> void:
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 90.0)
		if x.is_empty() or not _outbound(x[1]):
			continue
		pick = {"nid": nid, "x": x}
		break
	if pick.is_empty():
		_result("box", false, "no crossroads")
		return
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	var phase := TrafficSignal.phase_of(inc.dir)
	for k in 160:
		if TrafficSignal.lamp_for(phase, k * 0.25 + float(absi(hash("Signals_%s" % nid)) % 30)) == 2:
			_hold_clock = k * 0.25 + 1.0
			break
	await _settle_at(_net.nodes[nid])
	var k_opp := _net.incident_index(nid, opp.edge, opp.at_start)
	var mouth := _net.mouth_distance(nid, k_opp)
	var bs: Array = _lane_point(nid, opp, mouth + 3.5, false)
	var blocker := _car("grand_caravel", bs[0], bs[1], false)
	var s: Array = _lane_point(nid, inc, 70.0, true)
	var g: Array = _lane_point(nid, opp, minf(80.0, opp.edge.length - 8.0), false)
	var me := _car("civique", s[0], s[1])
	_focus = me
	await _wait(0.8)
	_ap(me).drive_to(_v3(g[0]))
	var poly := _net.junction_polygon(nid)
	var t0 := _t
	var inside := 0.0
	var stopped_short := INF
	while _t - t0 < 25.0:
		await physics_frame
		_trace_car("box", me)
		var f := me.global_transform * Vector3(0, 0, -float(me.shape["length"]) * 0.5)
		if Geometry2D.is_point_in_polygon(Vector2(f.x, f.z), poly) and absf(me.speed) < 0.5:
			inside += 1.0 / Engine.physics_ticks_per_second
		if absf(me.speed) < 0.3 and _t - t0 > 4.0:
			stopped_short = minf(stopped_short, _line_of(me, nid) - _front(me))
	# Clear the way: it goes on through.
	blocker.queue_free()
	var t1 := _t
	var through := false
	while _t - t1 < 20.0 and not through:
		await physics_frame
		through = _front(me) > _line_of(me, nid) + 20.0
	var ok := inside < 0.1 and stopped_short > -1.0 and stopped_short < 8.0 and through
	_result("box", ok, "junction %s: with the far side blocked it waited %.1f m short of the line, %.1f s stopped inside the junction; went through once it cleared: %s" % [
		nid, stopped_short, inside, through])
	_hold_clock = -1.0
	await _clear_cars([me])


## A police car with its siren on comes up from behind.
func _siren_test() -> void:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or not (e.highway in ["secondary", "tertiary", "primary"]) or e.length < 400.0:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.9 and (best == null or e.length > best.length):
			best = e
	if best == null:
		_result("siren", false, "no long street")
		return
	var line := StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(60.0))
	var me := _car("civique", r.sample(70.0), r.dir_at(70.0))
	var cop := _car("jaunt", r.sample(15.0), r.dir_at(15.0), false, "cps")
	_focus = me
	await _wait(0.8)
	_ap(me).drive_route(r, 70.0, _v3(r.goal))
	await _wait(6.0)
	cop.police.set_mode(PoliceGear.Mode.SIREN)
	_ap(cop).cruise_speed_kmh = 75.0
	_ap(cop).drive_route(StreetRoute.along(line, {}), _ap(cop).along, _v3(r.goal))
	var t0 := _t
	var most_right := 0.0
	var slowest := INF
	var before := me.speed * 3.6
	while _t - t0 < 25.0:
		await physics_frame
		_trace_car("siren", me)
		var p := Vector2(me.global_position.x, me.global_position.z)
		var a := r.project(p)
		var d := r.dir_at(a)
		var lat := (p - r.sample(a)).dot(Vector2(-d.y, d.x)) # + right
		most_right = maxf(most_right, lat)
		var behind := (Vector2(cop.global_position.x, cop.global_position.z) - p).dot(d) < 0.0
		if behind:
			slowest = minf(slowest, me.speed * 3.6)
		elif _t - t0 > 3.0:
			break
	var c := _ap(me).civil
	var ok := most_right > 0.7 and slowest < maxf(before * 0.5, 12.0) and c.pull_overs >= 1
	_result("siren", ok, "on %s at %.0f km/h: pulled %.1f m right, slowed to %.0f km/h while it came by (%d pull-overs)" % [
		best.name, before, most_right, slowest, c.pull_overs])
	await _clear_cars([me, cop])


## A car stopped in the lane of a two-way street: driven round.
func _blocked_test() -> void:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or not (e.highway in ["residential", "tertiary", "unclassified"]) or e.length < 220.0 or e.half_width < 3.5:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.95 and (best == null or e.length > best.length):
			best = e
	if best == null:
		_result("blocked", false, "no long straight two-way street")
		return
	var line := StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(90.0))
	var block := _car("haulux", r.sample(90.0), r.dir_at(90.0), false)
	var me := _car("civique", r.sample(20.0), r.dir_at(20.0))
	_focus = me
	await _wait(1.0)
	_crashes.clear()
	_ap(me).drive_route(r, 20.0, _v3(r.goal))
	var t0 := _t
	var passed := -1.0
	while _t - t0 < 45.0 and passed < 0.0:
		await physics_frame
		_trace_car("blocked", me)
		if _ap(me).along > 90.0 + 12.0:
			passed = _t - t0
	var hit := false
	for c: Array in _crashes:
		hit = hit or str(c[0]) == me.name
	var c := _ap(me).civil
	var ok := passed > 0.0 and passed < 40.0 and not hit
	_result("blocked", ok, "on %s: a car stopped in the lane 70 m ahead; past it %.1f s after setting off (%d passes), collision: %s" % [best.name, passed, c.passes, hit])
	await _clear_cars([me, block])


## Spun round in the road: back on its way.
func _spun_test() -> void:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or not (e.highway in ["residential", "tertiary", "secondary"]) or e.length < 300.0:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.95 and (best == null or e.length > best.length):
			best = e
	if best == null:
		_result("spun", false, "no long street")
		return
	var line := StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, {"lat_accel": 3.2})
	await _settle_at(r.sample(60.0))
	var me := _car("civique", r.sample(20.0), r.dir_at(20.0))
	_focus = me
	await _wait(1.0)
	_ap(me).drive_route(r, 20.0, _v3(r.goal))
	await _wait(6.0)
	# A shove: spun most of the way round, sideways across the road.
	var spot := _ap(me).along
	var d := r.dir_at(spot)
	var p := me.global_position
	me.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.y) + 0.5), p + Vector3.UP * 0.2)
	me.linear_velocity = Vector3.ZERO
	me.angular_velocity = Vector3.ZERO
	var t0 := _t
	var back := -1.0
	var good := 0.0
	while _t - t0 < 30.0 and back < 0.0:
		await physics_frame
		_trace_car("spun", me)
		# Back on its way: moving along its route (whichever way it now
		# goes), in the lane, facing the way the route goes, for 2 s.
		var ap := _ap(me)
		var f := -me.global_basis.z
		var p2 := Vector2(me.global_position.x, me.global_position.z)
		var ok_now := ap.route != null and not ap.route.is_empty() and me.speed > 3.0 and ap.route.off_line(p2, ap.along) < 1.5 and Vector2(f.x, f.z).dot(ap.route.dir_at(ap.along)) > 0.9 and ap.state == "route"
		good = good + 1.0 / Engine.physics_ticks_per_second if ok_now else 0.0
		if good > 2.0:
			back = _t - t0 - 2.0
	var ok := back > 0.0 and back < 20.0
	_result("spun", ok, "on %s: turned %.0f degrees round at %.0f m; on its way again (moving along its route, in lane, facing the way it goes) after %.1f s" % [best.name, 180.0 - rad_to_deg(0.5), spot, back])
	await _clear_cars([me])


## Painting a traffic car, then taking it.
func _react_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var wanted := root.get_node("Wanted")
	wanted.call("clear")
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or not _in_town(e) or e.bridge or not (e.highway in ["residential", "tertiary"]) or e.length < 250.0:
			continue
		if best == null or e.length > best.length:
			best = e
	var line := StreetRoute._offset_line(best.points, StreetRoute._lane_offset(best, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	await _settle_at(r.sample(40.0))
	var p0 := r.sample(20.0)
	var d := tm._new_driver({"street": r.goal, "inside": r.goal, "kind": ""})
	var rf := tm._make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-r.dir_at(20.0).x, -r.dir_at(20.0).y)), _v3(p0)))
	rf.set_route(r)
	rf.along = 20.0
	rf._place()
	tm._to_car(d)
	var car := d.car
	_focus = car
	await _wait(6.0)
	var level0 := int(wanted.get("level"))
	var shots := get_first_node_in_group("paint_shots")
	# Ten paint hits; the first one is what the driver reacts to.
	for i in 10:
		shots.emit_signal("hit", {"target": car, "point": car.global_position, "shooter": null, "kind": "car", "value": 1, "colour": Color.MAGENTA})
	var got_out := false
	var sped_off := false
	var t0 := _t
	while _t - t0 < 12.0 and not got_out:
		await physics_frame
		got_out = d.state == TrafficDriver.State.OUT and d.bystander != null
		sped_off = sped_off or d.civil._speed_mul > 1.0
	var level_after_paint := int(wanted.get("level"))
	if not got_out and sped_off:
		# This driver sped off instead (it's a coin toss): wait for them to
		# stop, and take the car at the next stop.
		pass
	# Wait for it to be stopped, then the player gets in.
	t0 = _t
	while _t - t0 < 20.0 and absf(car.speed) > 0.5:
		await physics_frame
	var player: Node3D = _player
	car.driver = player # as Player.enter_vehicle does
	await _wait(0.5)
	var level_after_take := int(wanted.get("level"))
	var complaining := 0
	for b: TrafficBystander in tm._bystanders:
		if is_instance_valid(b) and b.mode == TrafficBystander.Mode.COMPLAIN:
			complaining += 1
	var ok := (got_out or sped_off) and level_after_paint == level0 and level_after_take >= 1 and tm.thefts == 1 and complaining == 1 and car.ai_controls == null and not tm.drivers.has(d)
	_result("react", ok, "painted: driver %s (wanted level still %d, main.gd counts paint); taken: %d complaining driver, wanted level %d, thefts %d, car handed over: %s" % [
		"got out to stare" if got_out else ("sped off" if sped_off else "did nothing"), level_after_paint, complaining, level_after_take, tm.thefts, car.ai_controls == null])
	car.driver = null
	wanted.call("clear")
	await _clear_cars([car])


## Police and traffic: the cars of each, and knocks between them.
class Knocks:
	var watched := {}
	var last := {} ## pair -> time of its last knock
	## [time, jolt, what hit what: "police-traffic", "player-traffic", ...]
	var events: Array = []


func _kind_of(c: Car, tm: TrafficManager, runner: Car) -> String:
	if c == runner:
		return "player"
	if c.police != null:
		return "police"
	if tm._car_of.has(c):
		return "traffic"
	return "other"


## Connects to the crashed signal of every car about that isn't yet, and
## notes each hard knock with what the nearest other car was.
func _watch_knocks(k: Knocks, tm: TrafficManager, runner: Car) -> void:
	for n: Node in get_nodes_in_group("vehicles"):
		var c := n as Car
		if c == null or k.watched.has(c):
			continue
		k.watched[c] = true
		c.crashed.connect(func(j: float) -> void:
			if j < 5.0 or not is_instance_valid(c):
				return
			var near: Car = null
			var nd := 7.0
			for m: Node in get_nodes_in_group("vehicles"):
				var o := m as Car
				if o != null and o != c and o.global_position.distance_to(c.global_position) < nd:
					nd = o.global_position.distance_to(c.global_position)
					near = o
			if near == null:
				return
			var a := _kind_of(c, tm, runner)
			var b := _kind_of(near, tm, runner)
			# One crash, two cars: both say so. Count it once.
			var key := "%d/%d" % [mini(c.get_instance_id(), near.get_instance_id()), maxi(c.get_instance_id(), near.get_instance_id())]
			if k.last.has(key) and _t - float(k.last[key]) < 1.0:
				return
			k.last[key] = _t
			k.events.append([_t, j, "%s-%s" % [a, b] if a < b else "%s-%s" % [b, a]])
			if j > 9.0 and ((a == "police" and b == "traffic") or (a == "traffic" and b == "police")):
				var pc: Car = c if a == "police" else near
				var tc: Car = near if a == "police" else c
				print("  knock %.1f at t=%.0f at %s: %s" % [j, _t, pc.global_position, _knock_text(pc, tc, tm)]))


## Who hit whom, for a hard knock between a police car and a traffic car.
func _knock_text(pc: Car, tc: Car, tm: TrafficManager) -> String:
	var rel := pc.global_transform.affine_inverse() * tc.global_position # traffic in the police car's frame (-z ahead)
	var where := "ahead" if rel.z < -2.0 else ("behind" if rel.z > 2.0 else "alongside")
	where += " %s %.1f m" % ["left" if rel.x < 0.0 else "right", absf(rel.x)]
	var pa := pc.ai_controls as CarAutopilot
	var d: TrafficDriver = tm._car_of.get(tc)
	var heading := rad_to_deg((-pc.global_basis.z).signed_angle_to(-tc.global_basis.z, Vector3.UP))
	return "police %s %.1f m/s (%s, siren %s, lane %s) - traffic %s %.1f m/s, heading %+.0f deg from the police car, %s; traffic driver: %s, lateral %.2f, reason %s, hazard %s" % [
		pc.name, pc.speed, pa.state if pa != null else "-", pc.police != null and pc.police.mode == PoliceGear.Mode.SIREN,
		("cap %.1f" % pa.siren_lane.cap) if pa != null and pa.siren_lane != null else "-",
		tc.name, tc.speed, heading, where,
		d.civil.debug_text() if d != null else "-", d.civil.lateral if d != null else 0.0, d.civil.reason if d != null else "-", d.civil.hazard if d != null else "-"]


## The nearest traffic car right in front of `c` (within `reach` of its
## nose, roughly in its path), or null.
func _traffic_ahead(c: Car, tm: TrafficManager, reach: float) -> Car:
	var f := -c.global_basis.z
	for d: TrafficDriver in tm.drivers:
		if d.car == null:
			continue
		var rel := d.car.global_position - c.global_position
		var ahead := rel.dot(f)
		if ahead > 0.0 and ahead < reach + float(c.shape["length"]) * 0.5 + 2.5 and absf(rel.dot(c.global_basis.x)) < 2.2:
			return d.car
	return null


## Puts the player in a car at p, driven away by an autopilot (a fleeing
## player), with the camera behind it.
func _runner_car(p: Vector2, dir: Vector2) -> Car:
	var player := _player
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.input_enabled = false
	var car := Car.new()
	car.model_id = "civique"
	car.paint = Color(0.8, 0.2, 0.1)
	car.name = "Runner"
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, _ground_y(p) + 0.3, p.y))
	car.reset_physics_interpolation()
	(_main.get("cars") as Array).append(car)
	player.enter_vehicle(car)
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = _net
	ap.obey_oneway = false
	ap.cruise_speed_kmh = 65.0 # keeping ahead of them, through town traffic
	ap.chase_speed_kmh = 90.0
	car.add_child(ap)
	return car


func _end_runner(car: Car) -> void:
	var player := _player
	if player.vehicle != null:
		player.exit_vehicle(_main)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	(_main.get("cars") as Array).erase(car)
	car.queue_free()


func _drop_police() -> void:
	_police.patrols = false
	for u in _police.units.duplicate():
		_police.drop_unit(u)
	var wanted := root.get_node("Wanted")
	wanted.call("debug_watch", false)
	wanted.call("clear")


func _flee_from(car: Car) -> Vector3:
	var p := Vector2(car.global_position.x, car.global_position.z)
	var ids := _net.nodes.keys()
	ids.sort()
	var best := Vector2.INF
	var best_score := -INF
	var fwd := -car.global_basis.z
	for i in range(0, ids.size(), 7):
		var q: Vector2 = _net.nodes[ids[(i + int(_t)) % ids.size()]]
		var d := q.distance_to(p)
		if d < 400.0 or d > 800.0 or not _world.is_in_play_area(q):
			continue
		var score := (q - p).normalized().dot(Vector2(fwd.x, fwd.z)) - absf(d - 600.0) / 600.0
		if score > best_score:
			best_score = score
			best = q
	return Vector3(best.x, 0.0, best.y)


## A level 2 chase through downtown traffic.
func _chase_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	if tm == null or _police == null:
		_result("chase", false, "no traffic or no police in the main scene")
		return
	var wanted := root.get_node("Wanted")
	var start := _lane_point_near(Vector2(60, -40))
	await _settle_at(start[0])
	var runner := _runner_car(start[0], start[1])
	_focus = runner
	tm.focus = Vector3.INF
	tm.running = true
	# Let the traffic fill in round it first.
	await _wait(20.0)
	var k := Knocks.new()
	_watch_knocks(k, tm, runner)
	var ap := _ap(runner)
	ap.drive_to(_flee_from(runner))
	wanted.call("debug_set_level", 2)
	var behind: Vector2 = start[0] - (start[1] as Vector2) * 60.0
	var lead := _police.new_unit("city")
	var bp := _lane_point_near(behind)
	lead.place_physical(Transform3D(Basis(Vector3.UP, atan2(-(bp[1] as Vector2).x, -(bp[1] as Vector2).y)), _v3(bp[0]) + Vector3.UP * 0.35), _main)
	lead.order(PoliceUnit.Role.CHASE, runner.global_position, _police.clock)
	wanted.call("debug_watch", true)
	var t0 := _t
	var police_held := {} # unit -> seconds held up behind traffic now
	var police_held_worst := 0.0
	var runner_held := 0.0
	var runner_held_worst := 0.0
	var siren_near := 0.0
	var next_dest := _t + 20.0
	var caught := [false]
	var pinned_by_traffic := [false]
	var cb := func(_r: Dictionary) -> void:
		caught[0] = true
		# Was a traffic car holding the player up when they were caught?
		pinned_by_traffic[0] = _traffic_ahead(runner, tm, 2.5) != null
	wanted.connect("arrested", cb)
	var near_miss := {} # [police unit, traffic driver] passes within 1.5 m at speed
	var pulled_seen := {} # traffic drivers seen pulling over
	var meet := {} # traffic driver -> [time a siren came up behind, speed then, answered]
	var driven := 0.0
	var last_p := runner.global_position
	var unfair := 0
	var escaped := false
	while _t - t0 < 240.0 and driven < 2000.0 and not caught[0] and not escaped:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		driven += runner.global_position.distance_to(last_p)
		last_p = runner.global_position
		if _t - t0 > 6.0:
			wanted.call("debug_watch", false)
		if _t - t0 > 10.0 and int(wanted.get("level")) == 0:
			escaped = true # got away: what traffic does after isn't the chase
			break
		if Engine.get_physics_frames() % 30 == 0:
			_watch_knocks(k, tm, runner)
		if _t > next_dest or ap.state == "arrived" or (absf(runner.speed) < 1.0 and runner_held > 3.0):
			ap.drive_to(_flee_from(runner))
			next_dest = _t + 20.0
		# Held up by traffic in front.
		var ta := _traffic_ahead(runner, tm, 6.0)
		var was_held := runner_held
		runner_held = runner_held + dt if ta != null and absf(runner.speed) < 2.0 else 0.0
		# An unfair stop: held up behind traffic 3 s or more.
		var near_unit := INF
		for u in _police.units:
			if is_instance_valid(u) and u.car != null and is_instance_valid(u.car):
				near_unit = minf(near_unit, u.car.global_position.distance_to(runner.global_position))
		# Only with the police near: a red light with nobody after you is
		# just a red light.
		if near_unit < 150.0:
			runner_held_worst = maxf(runner_held_worst, runner_held)
		if was_held < 3.0 and runner_held >= 3.0 and near_unit < 150.0:
			unfair += 1
			var who: TrafficDriver = tm._car_of.get(ta)
			print("  chase: unfair stop at t=%.0f behind %s (%s, %.1f m/s, %.1f m ahead), police %.0f m back%s" % [_t - t0, ta.name, who.civil.debug_text() if who != null else "not traffic", ta.speed, ta.global_position.distance_to(runner.global_position), near_unit, (" (it's holding: %s, tailed %s, close behind %s)" % [who.civil.reason, who.civil._tailed, who.civil.close_behind]) if who != null else ""])
		for u in _police.units:
			if not is_instance_valid(u) or u.car == null or not is_instance_valid(u.car):
				continue
			var held := _traffic_ahead(u.car, tm, 6.0) != null and absf(u.car.speed) < 2.0
			police_held[u] = (float(police_held.get(u, 0.0)) + dt) if held else 0.0
			police_held_worst = maxf(police_held_worst, float(police_held[u]))
			if absf(u.car.speed) > 7.0:
				for d: TrafficDriver in tm.drivers:
					if d.car == null:
						continue
					var rel2 := d.car.global_position - u.car.global_position
					var side := absf(rel2.dot(u.car.global_basis.x)) - float(u.car.shape["width"]) * 0.5 - float(d.car.shape["width"]) * 0.5
					if absf(rel2.dot(u.car.global_basis.z)) < 2.0 and side > 0.0 and side < 1.5:
						near_miss["%d/%d" % [u.get_instance_id(), d.id]] = true
			if u.car.police != null and u.car.police.mode == PoliceGear.Mode.SIREN:
				for d: TrafficDriver in tm.drivers:
					if d.car == null or d.car.global_position.distance_to(u.car.global_position) > 40.0:
						continue
					siren_near += dt
					if d.civil.lateral < -0.5 or (d.civil.reason == "siren"):
						pulled_seen[d] = true
					# A siren coming up behind it, in its lane or the next.
					var f := -d.car.global_basis.z
					var rel := u.car.global_position - d.car.global_position
					if not meet.has(d) and rel.dot(f) < -3.0 and rel.dot(f) > -35.0 and absf(rel.dot(d.car.global_basis.x)) < 4.0 and u.car.speed > d.car.speed + 1.0 and f.dot(-u.car.global_basis.z) > 0.7:
						meet[d] = [_t, d.car.speed, false]
		for d: TrafficDriver in meet:
			var m: Array = meet[d]
			if bool(m[2]) or d.car == null or _t - float(m[0]) > 2.5:
				continue
			if d.civil.lateral < -0.5 or d.civil.reason == "siren" or d.car.speed < float(m[1]) * 0.5:
				m[2] = true
		if _trace and Engine.get_physics_frames() % 120 == 0:
			print("  chase t=%.0f level %d runner %.0f km/h %s, units %d, traffic %d (%d cars), runner held %.1f, police held %.1f, knocks %d" % [
				_t - t0, int(wanted.get("level")), runner.speed * 3.6, ap.state, _police.units.size(), tm.drivers.size(), _count_cars(tm), runner_held, police_held_worst, k.events.size()])
	wanted.disconnect("arrested", cb)
	var pt := 0
	var hard_pt := 0
	var player_t := 0
	for e: Array in k.events:
		if str(e[2]) == "police-traffic":
			pt += 1
			if float(e[1]) > 9.0:
				hard_pt += 1
		elif str(e[2]) == "player-traffic":
			player_t += 1
	tm.running = false
	var answered := 0
	for d: TrafficDriver in meet:
		if bool(meet[d][2]):
			answered += 1
	var ok: bool = not pinned_by_traffic[0] and unfair == 0 and hard_pt <= 1 and answered >= ceili(meet.size() * 0.8) and police_held_worst < 8.0 and runner_held_worst < 8.0 and hard_pt <= 1 and pt <= 4
	_result("chase", ok, "%.0f m of town in %.0f s at level 2 through %d traffic cars: unfair stops of the player (held 3 s or more behind traffic) %d; %sa siren came up behind %d traffic cars, %d pulled right or slowed within 2.5 s (%d seen pulled over in all, %.0f car-seconds near a siren); police held up behind traffic at most %.1f s, the player at most %.1f s; knocks police-traffic %d (%d hard), player-traffic %d; near misses (police by traffic at speed, within 1.5 m) %d; caught: %s%s%s" % [
		driven, _t - t0, tm.drivers.size(), unfair, "(pulling over not exercised this run: queue and siren cover it) " if meet.is_empty() else "", meet.size(), answered, pulled_seen.size(), siren_near, police_held_worst, runner_held_worst, pt, hard_pt, player_t, near_miss.size(), caught[0], " (with a traffic car pinning the player)" if pinned_by_traffic[0] else "", "; got away (level 0)" if escaped else ""])
	_drop_police()
	_end_runner(runner)
	_clear_traffic(tm)
	await _wait(0.5)


## A level 3 chase with sirens: traffic gets out of the way, and people on
## foot scatter from paint.
func _heat_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	if tm == null or _police == null:
		_result("heat", false, "no traffic or no police in the main scene")
		return
	var wanted := root.get_node("Wanted")
	var start := _lane_point_near(Vector2(-150, 60))
	await _settle_at(start[0])
	var runner := _runner_car(start[0], start[1])
	_focus = runner
	tm.focus = Vector3.INF
	tm.running = true
	await _wait(20.0)
	var before := tm.drivers.size()
	var want_before := TrafficDensity.target(_net, Vector2(runner.global_position.x, runner.global_position.z), tm.get_tree(), 0)
	var ap := _ap(runner)
	ap.drive_to(_flee_from(runner))
	wanted.call("debug_set_level", 3)
	wanted.call("debug_watch", true)
	var behind: Vector2 = start[0] - (start[1] as Vector2) * 60.0
	var lead := _police.new_unit("city")
	var bp := _lane_point_near(behind)
	lead.place_physical(Transform3D(Basis(Vector3.UP, atan2(-(bp[1] as Vector2).x, -(bp[1] as Vector2).y)), _v3(bp[0]) + Vector3.UP * 0.35), _main)
	lead.order(PoliceUnit.Role.CHASE, runner.global_position, _police.clock)
	var t0 := _t
	var on_for := 0.0
	var fewest := 1000
	var placed_ahead := 0
	var spawns_seen := tm.spawn_log.size()
	var next_dest := _t + 20.0
	var cleared := {} # driver -> reached its driveway
	var caught := [false]
	var cb := func(_r: Dictionary) -> void: caught[0] = true
	wanted.connect("arrested", cb)
	while _t - t0 < 75.0 and not caught[0]:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		if _t > next_dest or ap.state == "arrived":
			ap.drive_to(_flee_from(runner))
			next_dest = _t + 20.0
		if int(wanted.get("level")) < 3:
			wanted.call("debug_set_level", 3)
		if tm.heat.on:
			on_for += dt
		if _t - t0 > 25.0:
			fewest = mini(fewest, tm.drivers.size())
		# Anything placed while it's on, ahead of the player?
		while spawns_seen < tm.spawn_log.size():
			var sp: Vector3 = tm.spawn_log[spawns_seen][1]
			spawns_seen += 1
			var rp := Vector2(runner.global_position.x, runner.global_position.z)
			if tm.heat.on and tm.heat.heading != Vector2.ZERO:
				var rel := Vector2(sp.x, sp.z) - rp
				if rel.length() < TrafficHeat.NO_SPAWN_AHEAD * 0.9 and rel.dot(tm.heat.heading) > rel.length() * 0.6:
					placed_ahead += 1
					print("  heat: placed ahead at %s, %.0f m, heading %s, %.0f s after the last" % [sp, rel.length(), tm.heat.heading, _t - float(tm.spawn_log[spawns_seen - 1][0])])
		for d: TrafficDriver in tm.drivers:
			if d.cleared_off:
				cleared[d] = bool(cleared.get(d, false)) or d.turned_in or d.state == TrafficDriver.State.ARRIVED
		if _trace and Engine.get_physics_frames() % 120 == 0:
			print("  heat t=%.0f level %d on %s share %.2f traffic %d (%d cars) turned off %d kept on %d (no place %d)" % [
				_t - t0, int(wanted.get("level")), tm.heat.on, tm.heat.share, tm.drivers.size(), _count_cars(tm), tm.heat.turned_off, tm.heat.kept_on, tm.heat.no_place])
	wanted.disconnect("arrested", cb)
	var share := tm.heat.share
	var got_there := 0
	for d: TrafficDriver in cleared:
		if bool(cleared[d]):
			got_there += 1
	var rolled := tm.heat.turned_off + tm.heat.kept_on
	tm.running = false
	_drop_police()
	ap.drive_to(runner.global_position)
	# People on foot: a driver out looking at their car, paint lands near.
	await _wait(3.0)
	var out: TrafficDriver = null
	var out_d := INF
	for d: TrafficDriver in tm.drivers:
		if d.car != null and d.state == TrafficDriver.State.DRIVE and d.bus_route < 0 and not d.truck:
			var dd := d.car.global_position.distance_to(runner.global_position)
			if dd < out_d:
				out_d = dd
				out = d
	if out == null or out_d > 120.0:
		# None near: one of our own, on the street by the player's car.
		var lp := _lane_point_near(Vector2(runner.global_position.x, runner.global_position.z) + Vector2(25, 25))
		var r := StreetRoute.plan(_net, lp[0], (lp[0] as Vector2) + (lp[1] as Vector2) * 300.0, TrafficManager.plan_options(lp[1]))
		if not r.is_empty():
			out = _traffic_on(tm, r, 0.0)
			if not tm._to_car(out):
				out = null
	var ran := 0.0
	var left_car := false
	if out != null:
		out.getting_out = true
		out.civil.hold_for(30.0, "paint", true)
		var w0 := _t
		while out.bystander == null and _t - w0 < 25.0 and out.car != null:
			await physics_frame
		if out.bystander != null:
			var b := out.bystander
			var p0 := b.global_position
			await _wait(1.0)
			tm.heat.shots_at(p0 + (-out.car.global_basis.z) * 6.0)
			await _wait(4.0)
			ran = b.global_position.distance_to(p0) if is_instance_valid(b) else 99.0
			left_car = out.abandoned and out.state == TrafficDriver.State.OUT
	if out == null or out.bystander == null and not left_car:
		print("  heat: nobody got out to scatter (%s)" % ("no traffic car" if out == null else "state %d, car %s, %s" % [out.state, out.car, out.civil.debug_text()]))
	var ok := on_for > 20.0 and tm.heat.turned_off >= 1 and tm.heat.turned_off <= ceili(rolled * 0.8) and got_there >= 1 and fewest >= 3 and share < 0.8 and placed_ahead == 0 and ran > 8.0 and left_car
	_result("heat", ok, "level 3 with sirens %.0f s of %.0f: traffic %d before (want %d), fewest after the first 25 s %d, share of the usual now %.2f; drivers ahead or by a siren %d: %d turned off (%d got into their driveway), %d kept on; placed ahead of the player while on: %d; a driver out of their car scattered from paint: ran %.1f m in 4 s, left the car: %s; caught: %s" % [
		on_for, _t - t0, before, want_before, fewest, share, rolled, tm.heat.turned_off, got_there, tm.heat.kept_on, placed_ahead, ran, left_car, caught[0]])
	_end_runner(runner)
	_clear_traffic(tm)
	await _wait(0.5)


func _count_cars(tm: TrafficManager) -> int:
	var n := 0
	for d: TrafficDriver in tm.drivers:
		if d.car != null:
			n += 1
	return n


func _clear_traffic(tm: TrafficManager) -> void:
	for d: TrafficDriver in tm.drivers.duplicate():
		tm._remove(d, Vector3.ZERO)
	tm.spawn_log.clear()
	tm.removal_log.clear()
	tm.most = 0


## [a point in the right lane of the nearest plain street, its direction].
func _lane_point_near(p: Vector2) -> Array:
	var hit := _net.nearest_on_streets(p, 400.0)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along: float = clampf(hit["along"], 10.0, maxf(10.0, e.length - 10.0))
	var sp: Array = RoadNetwork.sample(e.points, along)
	var dir: Vector2 = sp[1]
	var fwd := e.oneway != -1
	if not fwd:
		dir = -dir
	return [(sp[0] as Vector2) + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, fwd), dir]


## A traffic driver of the manager's, on a route, as a follower at `at`.
func _traffic_on(tm: TrafficManager, r: StreetRoute, at: float) -> TrafficDriver:
	var d := tm._new_driver({"street": r.goal, "inside": r.goal, "kind": ""})
	var dir := r.dir_at(at)
	var rf := tm._make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(r.sample(at))))
	rf.set_route(r)
	rf.along = at
	rf._place()
	return d


## A queue at a red light with a chase coming through it.
func _queue_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 150.0)
		if x.is_empty() or (x[0] as RoadNetwork.Incident).edge.oneway != 0 or (x[0] as RoadNetwork.Incident).edge.half_width < 4.0:
			continue
		pick = {"nid": nid, "x": x}
		break
	if pick.is_empty():
		_result("queue", false, "no signalled crossroads with a long two-way way in")
		return
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	var phase := TrafficSignal.phase_of(inc.dir)
	for k in 160:
		if TrafficSignal.lamp_for(phase, k * 0.25 + float(absi(hash("Signals_%s" % nid)) % 30)) == 0:
			_hold_clock = k * 0.25 + 1.0
			break
	await _settle_at(_net.nodes[nid])
	# The queue: three traffic cars driving up to the red.
	var queue: Array[TrafficDriver] = []
	for dist: float in [45.0, 60.0, 75.0]:
		var a: Array = _lane_point(nid, inc, dist, true)
		var g: Array = _lane_point(nid, opp, minf(80.0, opp.edge.length - 8.0), false)
		var r := StreetRoute.plan(_net, a[0], g[0], TrafficManager.plan_options(a[1]))
		var d := _traffic_on(tm, r, 0.0)
		tm._to_car(d)
		queue.append(d)
	await _wait(14.0)
	var queued := 0
	for d: TrafficDriver in queue:
		if d.car != null and absf(d.car.speed) < 0.5:
			queued += 1
	# The chase: the player's car already through the junction and away, the
	# police after it, through the queue.
	var rs: Array = _lane_point(nid, opp, 25.0, false)
	var runner := _runner_car(rs[0], rs[1])
	_focus = runner
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
	var k := Knocks.new()
	_watch_knocks(k, tm, runner)
	var np: Vector2 = _net.nodes[nid]
	var t0 := _t
	var through := -1.0
	var answered := {}
	var siren_on := false
	while _t - t0 < 40.0 and through < 0.0:
		await physics_frame
		if unit.car == null or not is_instance_valid(unit.car):
			break
		siren_on = siren_on or (unit.car.police != null and unit.car.police.mode == PoliceGear.Mode.SIREN)
		for d: TrafficDriver in queue:
			if d.car != null and (d.civil.reason == "siren" or d.civil.lateral < -0.3 or d.civil._creep):
				answered[d] = true
		var pp := Vector2(unit.car.global_position.x, unit.car.global_position.z)
		if (pp - np).dot(-inc.dir) > 5.0:
			through = _t - t0
		if _trace and Engine.get_physics_frames() % 60 == 0:
			print("  queue t=%.0f police %.0f km/h %s %.0f m from the junction, runner %.0f km/h" % [_t - t0, unit.car.speed * 3.6, unit.pilot.state, (pp - np).dot(inc.dir), runner.speed * 3.6])
	var hard := 0
	var any := 0
	for e: Array in k.events:
		if str(e[2]) == "police-traffic":
			any += 1
			if float(e[1]) > 9.0:
				hard += 1
	var ok := queued >= 2 and siren_on and through > 0.0 and through < 22.0 and answered.size() >= 2 and hard == 0
	_result("queue", ok, "%d traffic cars queued at the red at %s; police (siren: %s) came through the junction after %.1f s, %d of the queue edged right or out for it; knocks police-traffic %d (%d hard)" % [
		queued, inc.edge.name, siren_on, through, answered.size(), any, hard])
	_hold_clock = -1.0
	_drop_police()
	_end_runner(runner)
	_clear_traffic(tm)
	await _wait(0.5)


## Witnesses: who saw the player paint a car, and who calls it in.
##   stays           still in sight when they get through: called in, at the
##                   crime (not the player's live position)
##   drives_off      out of sight at once: no call
##   corner_3s       off round a corner 3 s later: no call
##   lost_late       out of sight 5.5 s later: called in, where they last
##                   saw the player
##   paints_witness  the witness's own car painted: no call
func _witness_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var wanted := root.get_node("Wanted")
	var shots := get_first_node_in_group("paint_shots")
	var e := _straight_edge(["residential", "tertiary", "secondary"], 260.0)
	var line := StreetRoute._offset_line(e.points, StreetRoute._lane_offset(e, true))
	var r := StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO))
	await _settle_at(r.sample(110.0))
	TrafficWitnesses.call_odds = 1.0
	var results: Array[String] = []
	var ok := true
	for case: String in ["stays", "drives_off", "corner_3s", "lost_late", "paints_witness"]:
		wanted.call("clear")
		# The player in a car stopped at 120 m; a parked car to paint just
		# ahead of it; a traffic car coming up the street behind, 45 m off.
		var runner := _runner_car(r.sample(120.0), r.dir_at(120.0))
		var victim := _car("corollary", r.sample(128.0), r.dir_at(128.0), false)
		var d := _traffic_on(tm, StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO)), 75.0)
		tm._to_car(d)
		# Someone following the witness closely: a startled witness mustn't
		# stand on the brakes in front of them.
		# (Only here: painting a witness's car in front of another witness
		# is a fresh crime they'd call in.)
		if case == "stays":
			var tail := _traffic_on(tm, StreetRoute.along(line, TrafficManager.plan_options(Vector2.ZERO)), 64.0)
			tm._to_car(tail)
		_focus = runner
		await _wait(2.0)
		var k := Knocks.new()
		_watch_knocks(k, tm, runner)
		var calls0 := int(wanted.get("witness_calls"))
		var stopped0 := tm.witnesses.stopped
		var seen0 := tm.witnesses.witnessed
		var crime_at := victim.global_position
		var seen_at := runner.global_position
		shots.emit_signal("hit", {"target": victim, "point": crime_at, "shooter": _player, "kind": "car", "value": 1, "colour": Color.MAGENTA})
		var gone_after := {"drives_off": 0.3, "corner_3s": 3.0, "lost_late": 5.5}
		if gone_after.has(case):
			await _wait(float(gone_after[case]))
			seen_at = runner.global_position
			# Gone round the corner: well out of their sight.
			var far := _lane_point_near(r.sample(120.0) + Vector2(260.0, 260.0))
			runner.global_transform = Transform3D(Basis(Vector3.UP, atan2(-(far[1] as Vector2).x, -(far[1] as Vector2).y)), _v3(far[0]) + Vector3.UP * 0.4)
			runner.linear_velocity = Vector3.ZERO
		elif case == "paints_witness":
			# Every witness on the phone gets their car painted.
			await _wait(0.3)
			for pc: Dictionary in tm.witnesses.pending.duplicate():
				var wd: TrafficDriver = pc["driver"]
				if wd.car != null:
					shots.emit_signal("hit", {"target": wd.car, "point": wd.car.global_position, "shooter": _player, "kind": "car", "value": 1, "colour": Color.MAGENTA})
		await _wait(12.0)
		var called := int(wanted.get("witness_calls")) - calls0
		var lk: Vector3 = wanted.get("last_known_position")
		var saw := tm.witnesses.witnessed - seen0
		var stopped := tm.witnesses.stopped - stopped0
		var knocks := 0
		for ev: Array in k.events:
			if str(ev[2]) == "traffic-traffic":
				knocks += 1
		var good := saw >= 1 and knocks == 0
		var where := ""
		match case:
			"stays":
				good = good and called >= 1 and lk.distance_to(crime_at) < 3.0
				where = "%.0f m from the crime" % lk.distance_to(crime_at)
			"lost_late":
				good = good and called >= 1 and lk.distance_to(seen_at) < 3.0 and lk.distance_to(runner.global_position) > 100.0
				where = "%.0f m from where they last saw the player, %.0f m from the player now" % [lk.distance_to(seen_at), lk.distance_to(runner.global_position)]
			_:
				good = good and called == 0 and stopped >= 1
		ok = ok and good
		results.append("%s: %d saw it, %d called%s, %d calls stopped, %d knocks%s" % [case, saw, called, (" (" + where + ")") if where != "" else "", stopped, knocks, "" if good else " WRONG"])
		_end_runner(runner)
		await _clear_cars([victim])
		_clear_traffic(tm)
		await _wait(0.5)
	TrafficWitnesses.call_odds = 0.45
	wanted.call("clear")
	_result("witness", ok, "; ".join(results))


func _straight_edge(classes: Array, min_len: float) -> RoadNetwork.RoadEdge:
	var best: RoadNetwork.RoadEdge = null
	for e in _net.edges:
		if e.oneway != 0 or e.bridge or not _in_town(e) or not (e.highway in classes) or e.length < min_len:
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight > 0.95 and (best == null or e.length > best.length):
			best = e
	return best


## Rollbacks for dead cars.
func _tow_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var e := _straight_edge(["secondary", "tertiary", "residential"], 160.0)
	var sp: Array = RoadNetwork.sample(e.points, e.length * 0.5)
	var mid: Vector2 = sp[0]
	await _settle_at(mid)
	var gs := root.get_node_or_null("GameState")
	var impounded_before: int = (gs.get("impounded") as Array).size() if gs != null else 0
	var keep := [TrafficTows.traffic_after, TrafficTows.player_after]
	TrafficTows.traffic_after = 6.0
	TrafficTows.player_after = 6.0
	tm.focus = _v3(mid)
	tm.running = true
	# Nothing left over from the cases before (a car painted dead, left in
	# the street) waiting its turn for a truck.
	for j: TrafficTows.Job in tm.tows.jobs.duplicate():
		tm.tows._off(j)
	tm.tows._dead.clear()
	for n: Node in get_nodes_in_group("vehicles"):
		var c := n as Car
		if c != null and c.stalled and c.driver == null:
			print("  tow: a dead car left over: %s at %s" % [c.name, c.global_position])
			(_main.get("cars") as Array).erase(c)
			c.queue_free()
	var lines: Array[String] = []
	var ok := true
	for which: String in ["traffic", "player"]:
		var lp := _lane_point_near(mid)
		var car: Car
		var d: TrafficDriver = null
		if which == "traffic":
			var r := StreetRoute.plan(_net, lp[0], (lp[0] as Vector2) + (lp[1] as Vector2) * 70.0, TrafficManager.plan_options(lp[1]))
			d = _traffic_on(tm, r, 0.0)
			tm._to_car(d)
			car = d.car
			await _wait(2.0)
		else:
			car = Car.new()
			car.model_id = "civique"
			car.name = "PlayersCar"
			car.owner_id = "local"
			_main.add_child(car)
			var dir: Vector2 = lp[1]
			car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(lp[0]) + Vector3.UP * 0.3)
			car.reset_physics_interpolation()
			(_main.get("cars") as Array).append(car)
			_player.global_position = _v3((lp[0] as Vector2) + Vector2(-(lp[1] as Vector2).y, (lp[1] as Vector2).x) * 40.0)
		car.stalled = true
		var t0 := _t
		var sent0 := tm.tows.sent
		var towed0 := tm.tows.towed
		var imp0 := tm.tows.impounded
		var steps := {}
		var start := car.global_position
		var carried := 0.0
		var truck_gap := INF
		while _t - t0 < 200.0:
			await physics_frame
			for j: TrafficTows.Job in tm.tows.jobs:
				if j.car == car:
					if not steps.has(j.step):
						steps[j.step] = _t - t0
					var tc := tm.tows._truck_car(j)
					if tc != null and j.step == TrafficTows.Step.SENT:
						truck_gap = minf(truck_gap, tc.global_position.distance_to(car.global_position))
						if _trace and Engine.get_physics_frames() % 180 == 0:
							print("  tow t=%.0f truck %.0f m off, %.1f m/s, %s %s along %.0f/%.0f" % [_t - t0, tc.global_position.distance_to(car.global_position), tc.speed, j.truck.pilot.state, j.truck.civil.debug_text(), j.truck.pilot.along, j.truck.pilot.route.length if j.truck.pilot.route != null else 0.0])
			if is_instance_valid(car):
				carried = maxf(carried, car.global_position.distance_to(start))
			if tm.tows.towed > towed0:
				break
		var done := tm.tows.towed > towed0
		var to_lot := tm.tows.impounded > imp0
		var good := tm.tows.sent > sent0 and steps.has(TrafficTows.Step.AWAY) and carried > 25.0 and done and (to_lot == (which == "player")) and not is_instance_valid(car)
		ok = ok and good
		var names := ["sent", "deck down", "winching", "deck up", "away"]
		var parts: Array[String] = []
		for k in range(5):
			if steps.has(k):
				parts.append("%s %.0f s" % [names[k], float(steps[k])])
		lines.append("%s car: %s; carried %.0f m on the deck; towed off: %s%s" % [which, ", ".join(parts) if not parts.is_empty() else "no truck sent", carried, done, " (to the impound lot)" if to_lot else ""])
		_clear_traffic(tm)
		await _wait(0.5)
	if gs != null:
		var imp: Array = gs.get("impounded")
		while imp.size() > impounded_before:
			imp.pop_back()
		gs.call("save_game")
	TrafficTows.traffic_after = keep[0]
	TrafficTows.player_after = keep[1]
	tm.running = false
	tm.focus = Vector3.INF
	_result("tow", ok, "; ".join(lines))


## The odd truck: traffic trucks drive like the cars do.
func _truck_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var pick := {}
	for nid: String in _nodes_sorted(_net.signal_nodes):
		var x := _crossroads(nid, 120.0)
		if x.is_empty() or not _outbound(x[1]) or (x[1] as RoadNetwork.Incident).edge.length < 100.0:
			continue
		pick = {"nid": nid, "x": x}
		break
	var nid: String = pick["nid"]
	var inc: RoadNetwork.Incident = pick["x"][0]
	var opp: RoadNetwork.Incident = pick["x"][1]
	await _settle_at(_net.nodes[nid])
	var trucks: Array[TrafficDriver] = []
	var dists := [100.0, 70.0]
	var models := ["rollback", "hauler"]
	for i in 2:
		var a: Array = _lane_point(nid, inc, dists[i], true)
		var g: Array = _lane_point(nid, opp, minf(90.0, opp.edge.length - 8.0), false)
		var r := StreetRoute.plan(_net, a[0], g[0], TrafficManager.plan_options(a[1]))
		var d := tm._new_driver({"street": g[0], "inside": g[0], "kind": ""}, models[i])
		var rf := tm._make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-(a[1] as Vector2).x, -(a[1] as Vector2).y)), _v3(a[0])))
		rf.set_route(r)
		tm._to_car(d)
		trucks.append(d)
	_focus = trucks[0].car
	_crashes.clear()
	var t0 := _t
	var arrived := 0
	var worst_off := 0.0
	var ran_red := false
	var phase := TrafficSignal.phase_of(inc.dir)
	while _t - t0 < 70.0:
		await physics_frame
		arrived = 0
		for d: TrafficDriver in trucks:
			if d.car == null:
				continue
			if d.state == TrafficDriver.State.ARRIVED:
				arrived += 1
				continue
			var ap := d.pilot
			if ap.route != null and not ap.route.is_empty():
				worst_off = maxf(worst_off, ap.route.off_line(Vector2(d.car.global_position.x, d.car.global_position.z), ap.along))
			var line := _line_of(d.car, nid)
			if TrafficSignal.lamp_at(nid, phase) == 0 and _front(d.car) > line + 1.0 and _front(d.car) < line + 3.0 and absf(d.car.speed) > 3.0:
				ran_red = true
		if arrived == trucks.size():
			break
	var hit := false
	for c: Array in _crashes:
		hit = hit or str(c[0]).begins_with("Traffic_")
	var ok := arrived == trucks.size() and worst_off < 3.0 and not ran_red and not hit
	_result("truck", ok, "a tow truck and a tractor unit through %s on %s: %d of 2 got there in %.0f s, worst %.1f m off their line, through a red: %s, collisions: %s" % [
		nid, inc.edge.name, arrived, _t - t0, worst_off, ran_red, hit])
	_clear_traffic(tm)
	await _wait(0.5)


## A bus on its route: one appears out of sight on its own; and one put on
## the long leg of route 1 up University Avenue pulls in at a stop, waits
## and pulls out, inside the curb.
func _bus_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	var a: Vector2 = _net.nodes[_net.find_junction("University Avenue", "Euston Street")]
	var b: Vector2 = _net.nodes[_net.find_junction("University Avenue", "Allen Street")]
	var spot := a.lerp(b, 0.25)
	await _settle_at(spot)
	var eye := _v3(spot) + Vector3.UP * 2.0
	_cam.global_position = eye
	tm.focus = eye
	tm.running = true
	# On its own: within a minute a bus is placed on a route near here.
	var t0 := _t
	var natural: TrafficDriver = null
	var natural_t := -1.0
	while _t - t0 < 60.0 and natural == null:
		await physics_frame
		_cam.global_position = eye
		for d: TrafficDriver in tm.drivers:
			if d.bus_route >= 0 and d.car != null:
				natural = d
				natural_t = _t - t0
	var natural_name: String = tm.buses.routes[natural.bus_route]["name"] if natural != null else "none"
	tm.running = false
	_clear_traffic(tm)
	await _wait(0.5)
	# The long leg: from 30 m past University and Euston on to Allen.
	var r0 := StreetRoute.plan(_net, a, b, TrafficManager.plan_options(Vector2.ZERO))
	var p0 := r0.sample(30.0)
	var dir := r0.dir_at(30.0)
	var leg := 4 # University Avenue and Allen Street, in TrafficBuses.ROUTES
	var bus := tm.spawn_bus(_v3(p0) + Vector3.UP * 0.3, dir, 0, leg, b)
	_focus = bus.car if bus != null else null
	var stopped_at := -1.0
	var pulled_out := -1.0
	var lateral_at_stop := 0.0
	var parked_at_stop := false
	var worst_tilt := 0.0
	var curb_gap := INF
	_crashes.clear()
	t0 = _t
	while bus != null and _t - t0 < 90.0 and pulled_out < 0.0:
		await physics_frame
		if bus.car == null or not is_instance_valid(bus.car):
			break
		var tilt := absf(rad_to_deg(asin(clampf(bus.car.global_basis.x.y, -1.0, 1.0))))
		if _trace and int(tilt) > int(worst_tilt) and tilt > 3.0:
			var bh := _net.nearest_on_streets(Vector2(bus.car.global_position.x, bus.car.global_position.z), 30.0)
			print("  bus tilt %.1f at t=%.0f, %.1f m/s, lateral %.2f, %s, %.2f m off the street's middle (half width %.1f)" % [tilt, _t - t0, bus.car.speed, bus.civil.lateral, bus.civil.reason, float(bh.get("dist", -1.0)), (bh["edge"] as RoadNetwork.RoadEdge).half_width if not bh.is_empty() else 0.0])
		worst_tilt = maxf(worst_tilt, tilt)
		if absf(bus.car.speed) < 0.5 and bus.civil.reason == "bus_stop":
			var bp := Vector2(bus.car.global_position.x, bus.car.global_position.z)
			var hit := _net.nearest_on_streets(bp, 30.0)
			if not hit.is_empty():
				var e: RoadNetwork.RoadEdge = hit["edge"]
				curb_gap = e.half_width - float(hit["dist"]) - float(bus.car.shape["width"]) * 0.5 # where it ends up
		if stopped_at < 0.0 and bus.civil.reason == "bus_stop" and absf(bus.car.speed) < 0.5:
			stopped_at = _t - t0
			lateral_at_stop = bus.civil.lateral
			parked_at_stop = bus.civil.curb_keep > 0.0
		elif stopped_at >= 0.0 and pulled_out < 0.0 and bus.car.speed > 3.0:
			pulled_out = _t - t0
	var hit := false
	for c: Array in _crashes:
		hit = hit or str(c[0]).begins_with("Traffic_transit_bus")
	var spawned := tm.spawn_log.filter(func(x: Array) -> bool: return bool(x[2])).size()
	var ok := natural != null and bus != null and stopped_at > 0.0 and pulled_out > stopped_at and not hit and spawned == 0 and curb_gap > 0.0 and curb_gap < (StreetRoute.PARKING_LANE + 0.6 if parked_at_stop else 1.0) and worst_tilt < 5.0
	_result("bus", ok, "on its own: a bus on route %s within %.0f s, placed out of sight (in sight: %d); up University Avenue: stopped at a stop at %.0f s (pulled %.1f m in, %.2f m inside the curb%s), pulled out at %.0f s; rolled at most %.1f degrees; collisions: %s" % [
		natural_name, natural_t, spawned, stopped_at, -lateral_at_stop, curb_gap, ", beside cars parked there" if parked_at_stop else "", pulled_out, worst_tilt, hit])
	_clear_traffic(tm)
	tm.focus = Vector3.INF
	_focus = null
	await _wait(0.5)


## Police patrols among traffic, nobody wanted.
func _patrol_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	if tm == null or _police == null:
		_result("patrol", false, "no traffic or no police in the main scene")
		return
	var spot := _lane_point_near(Vector2(-150, 120))
	await _settle_at(spot[0])
	var eye := _v3(spot[0]) + Vector3.UP * 30.0
	_cam.global_position = eye
	_cam.rotation = Vector3(deg_to_rad(-60.0), 0.0, 0.0)
	_focus = null
	tm.focus = eye
	tm.running = true
	# The patrols go round the player: the player stands here too, on foot.
	var player := _player
	player.place(Transform3D(Basis.IDENTITY, _v3(spot[0] + Vector2(0, 12)) + Vector3.UP * 0.1))
	_police.patrols = true
	# Two city patrols placed on the streets here, driving the beat across
	# downtown (the dispatcher adds its own as well).
	for i in 2:
		var at := _lane_point_near(spot[0] + Vector2(70.0 - i * 140.0, -40.0 + i * 80.0))
		var u := _police.new_unit("city")
		u.place_physical(Transform3D(Basis(Vector3.UP, atan2(-(at[1] as Vector2).x, -(at[1] as Vector2).y)), _v3(at[0]) + Vector3.UP * 0.35), _main)
		var g := _lane_point_near(spot[0] + Vector2(-500.0 + i * 1000.0, 300.0 - i * 600.0))
		u.order(PoliceUnit.Role.PATROL, _v3(g[0]), _police.clock)
	var k := Knocks.new()
	var t0 := _t
	var stuck := {}
	var stuck_worst := 0.0
	var red_runs := 0
	var patrolled := {}
	while _t - t0 < 75.0:
		await physics_frame
		if Engine.get_physics_frames() % 30 == 0:
			_watch_knocks(k, tm, null)
		for u in _police.units:
			if not is_instance_valid(u) or u.car == null or not is_instance_valid(u.car) or u.role != PoliceUnit.Role.PATROL:
				continue
			patrolled[u] = true
			stuck[u] = float(stuck.get(u, 0.0)) + 1.0 / Engine.physics_ticks_per_second if absf(u.car.speed) < 0.5 and not (u.pilot.civil != null and u.pilot.civil.holding) else 0.0
			stuck_worst = maxf(stuck_worst, float(stuck[u]))
			var c := u.pilot.civil
			if c != null and c._stop_reason == "red" and not c._stop_j.is_empty() and _front(u.car) > float(c._stop_j["line"]) + 1.5:
				red_runs += 1
	var pt := 0
	var hard := 0
	var jolts: Array[String] = []
	for e: Array in k.events:
		if str(e[2]) == "police-traffic":
			pt += 1
			jolts.append("%.1f" % float(e[1]))
			if float(e[1]) > 9.0:
				hard += 1
	tm.running = false
	# A light tap now and then is believable; a hard knock, or a habit of
	# them, isn't.
	var ok := patrolled.size() >= 1 and hard == 0 and pt <= 1 and stuck_worst < 20.0 and red_runs == 0
	_result("patrol", ok, "%d patrol cars among %d traffic cars for 75 s: knocks with traffic %d (jolts %s m/s), longest stuck %.1f s (not counting waiting its turn), past a red line %d" % [
		patrolled.size(), tm.drivers.size(), pt, ", ".join(jolts) if not jolts.is_empty() else "-", stuck_worst, red_runs])
	_drop_police()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_clear_traffic(tm)
	await _wait(0.5)


## A minute downtown with TrafficManager running.
func _town_test() -> void:
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	if tm == null:
		_result("town", false, "no TrafficManager in the main scene")
		return
	# A downtown corner: the signalled junction nearest the middle of town.
	var corner := ""
	var best_d := INF
	for nid: String in _net.signal_nodes:
		var d := (_net.nodes[nid] as Vector2).length()
		if d < best_d:
			best_d = d
			corner = nid
	var cp: Vector2 = _net.nodes[corner]
	var look: Vector2 = (_net.incidents[corner][0] as RoadNetwork.Incident).dir
	await _settle_at(cp)
	var eye := Vector3(cp.x, _world.terrain.h2(cp) + 1.7, cp.y) - Vector3(look.x, 0.0, look.y) * 6.0
	_cam.global_position = eye
	_cam.look_at(eye + Vector3(look.x, 0.0, look.y) * 10.0, Vector3.UP)
	tm.focus = eye
	tm.running = true
	_crashes.clear()
	var honks0 := -1
	var car_secs := 0.0
	var t0 := _t
	var worst_stuck := 0.0
	var worst_light := 0.0
	var worst_who := ""
	var inside := 0
	var inside_who := ""
	var cars_max := 0
	var sample_t := 0.0
	var seen_held := {}
	var count_sum := 0.0
	var count_n := 0
	# 20 s for it to fill up, then the minute.
	while _t - t0 < 80.0:
		await physics_frame
		_cam.global_position = eye
		sample_t -= 1.0 / Engine.physics_ticks_per_second
		if sample_t > 0.0:
			continue
		sample_t = 0.5
		var cars := 0
		for d: TrafficDriver in tm.drivers:
			if d.car != null:
				cars += 1
			var p := d.position()
			if p == Vector3.INF:
				continue
			worst_light = maxf(worst_light, d.light_wait)
			if _t - t0 > 20.0 and d.state == TrafficDriver.State.DRIVE:
				if d.stuck_for > worst_stuck:
					worst_stuck = d.stuck_for
					worst_who = "%s %d (%s, %s) at (%.0f, %.0f)%s" % [d.model_id, d.id, "car" if d.car != null else "far", d.civil.debug_text(), p.x, p.z, _follower_text(d)]
			var bld := _in_building(Vector2(p.x, p.z))
			if bld != "":
				inside += 1
				inside_who = "%s %d at (%.1f, %.1f), %s, in building %s" % [d.model_id, d.id, p.x, p.z, "car" if d.car != null else "far", bld]
		cars_max = maxi(cars_max, cars)
		if _t - t0 > 20.0:
			if honks0 < 0:
				honks0 = CivilDriving.all_honks
			car_secs += 0.5 * tm.drivers.size()
		if _t - t0 > 20.0:
			count_sum += tm.drivers.size()
			count_n += 1
		if _trace:
			print("  town t=%.0f drivers %d cars %d worst stuck %.1f" % [_t - t0, tm.drivers.size(), cars, worst_stuck])
	tm.running = false
	var seen_spawns := 0
	for s: Array in tm.spawn_log:
		if bool(s[2]):
			seen_spawns += 1
	var seen_removals := 0
	for s: Array in tm.removal_log:
		if bool(s[2]):
			seen_removals += 1
	var cap := TrafficDensity.CAP
	var pcap := TrafficDensity.PHYSICS_CAP
	var ok := worst_stuck <= STUCK_MAX and inside == 0 and seen_spawns == 0 and seen_removals == 0 and tm.most <= cap and cars_max <= pcap and tm.spawn_log.size() > 5
	_result("town", ok, "at %s for 60 s: %.1f cars on average (most %d, cap %d), up to %d with physics (cap %d); %d placed, %d taken away, seen by the camera: %d and %d; longest stuck %.1f s%s, longest wait at a light %.1f s; inside a building: %d%s; crashes %d; %d honks (%.1f per car-minute)" % [
		_world.street_name_at(cp), count_sum / maxi(count_n, 1), tm.most, cap, cars_max, pcap, tm.spawn_log.size(), tm.removal_log.size(), seen_spawns, seen_removals,
		worst_stuck, (" (" + worst_who + ")") if worst_who != "" else "", worst_light, inside, (" (" + inside_who + ")") if inside_who != "" else "", _crashes.size(), CivilDriving.all_honks - maxi(honks0, 0), (CivilDriving.all_honks - maxi(honks0, 0)) / maxf(car_secs / 60.0, 0.01)])


## How a far car is doing, for debugging a stuck one.
func _follower_text(d: TrafficDriver) -> String:
	var f := d.follower
	if f == null or f.route == null:
		return ""
	return " [%.1f m/s, cap %.1f, %.0f/%.0f m along, route limit %.1f, moving %s, state %d]" % [f.speed, f.max_speed, f.along, f.route.length, f.route.limit_at(f.along + f.speed * 0.3), f.moving, d.state]


## The building a point is inside ("" if none): its id and tags.
func _in_building(p: Vector2) -> String:
	var data := _world.data
	var cs := data.chunk_size
	var cx := floori(p.x / cs)
	var cz := floori(p.y / cs)
	var key := "%d_%d" % [cx, cz]
	if not _buildings.has(key):
		var list: Array = []
		if data.has_chunk(cx, cz):
			var ch := data.load_chunk(cx, cz)
			for b in ch.buildings:
				list.append([b.ring, "%s %s" % [b.id, b.tags.get("building", "")]])
		_buildings[key] = list
	for b: Array in _buildings[key]:
		if Geometry2D.is_point_in_polygon(p, b[0]):
			return str(b[1])
	return ""

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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_trace = args.has("trace")
	var only: Array = str(args.get("only", "signal,left,merge,follow,box,siren,blocked,spun,town")).split(",")
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
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.remove_from_group(RoadUsers.PEOPLE_GROUP)
	root.add_child(_cam)
	_cam.make_current()
	physics_frame.connect(_track)
	await _wait(0.5)
	for test: String in ["signal", "left", "merge", "follow", "box", "siren", "blocked", "spun", "town"]:
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
			(c as Node).queue_free()
	await _wait(0.3)


func _trace_car(tag: String, car: Car) -> void:
	if not _trace or Engine.get_physics_frames() % 30 != 0:
		return
	var ap := _ap(car)
	var c := ap.civil
	print("  %s t=%.1f %.0f km/h along %.0f state %s thr %.2f brk %.2f hold %s %s lead %.1f lat %.2f" % [tag, _t, car.speed * 3.6, ap.along, ap.state, ap.throttle, ap.brake,
		c.holding if c else false, c.reason if c else "", c.leader_gap if c else 0.0, c.lateral if c else 0.0])


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
	_ap(main_car).drive_to(_v3(fg[0]))
	await _wait(2.0)
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
	_result("blocked", ok, "on %s: a car stopped in the lane 70 m ahead; got round it after %.1f s (%d passes), collision: %s" % [best.name, passed, c.passes, hit])
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
	var lvl := TrafficDensity.level()
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
					worst_who = "%s %d (%s, %s) at (%.0f, %.0f)" % [d.model_id, d.id, "car" if d.car != null else "far", d.civil.debug_text(), p.x, p.z]
			if _in_building(Vector2(p.x, p.z)):
				inside += 1
				inside_who = "%s %d at (%.0f, %.0f)" % [d.model_id, d.id, p.x, p.z]
		cars_max = maxi(cars_max, cars)
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
	var cap: int = TrafficDensity.CAP[lvl]
	var pcap: int = TrafficDensity.PHYSICS_CAP[lvl]
	var ok := worst_stuck <= STUCK_MAX and inside == 0 and seen_spawns == 0 and seen_removals == 0 and tm.most <= cap and cars_max <= pcap and tm.spawn_log.size() > 5
	_result("town", ok, "at %s for 60 s: %.1f cars on average (most %d, cap %d), up to %d with physics (cap %d); %d placed, %d taken away, seen by the camera: %d and %d; longest stuck %.1f s%s, longest wait at a light %.1f s; inside a building: %d%s; crashes %d" % [
		_world.street_name_at(cp), count_sum / maxi(count_n, 1), tm.most, cap, cars_max, pcap, tm.spawn_log.size(), tm.removal_log.size(), seen_spawns, seen_removals,
		worst_stuck, (" (" + worst_who + ")") if worst_who != "" else "", worst_light, inside, (" (" + inside_who + ")") if inside_who != "" else "", _crashes.size()])


func _in_building(p: Vector2) -> bool:
	var data := _world.data
	var cs := data.chunk_size
	var cx := floori(p.x / cs)
	var cz := floori(p.y / cs)
	var key := "%d_%d" % [cx, cz]
	if not _buildings.has(key):
		var rings: Array[PackedVector2Array] = []
		if data.has_chunk(cx, cz):
			var ch := data.load_chunk(cx, cz)
			for b in ch.buildings:
				rings.append(b.ring)
		_buildings[key] = rings
	for ring: PackedVector2Array in _buildings[key]:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false

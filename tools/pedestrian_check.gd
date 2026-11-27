extends SceneTree
## Watches the people on foot downtown (PedestrianManager) for glitches, and
## runs one ride (RideFares) from hail to pay:
##
##   godot --headless --path . --script res://tools/pedestrian_check.gd -- [--secs=90] [--no-ride] [--no-bus]
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
## and checks they got in, got out and paid. Then (unless --no-bus) it puts
## two people waiting at a stop on University Avenue and a route 1 bus up
## the street, and checks the bus pulls in, they get on and it goes on.
## It also counts crossings at the lights (on the walk and on red), people
## waiting for buses, twos, and who notices a crash put next to the camera.
## One "PEDS" line per result;
## it fails (exit code 1) on a broken ride or people walking in the road.

var _main: Node
var _world: WorldBuilder
var _cam := Camera3D.new()
var _t := 0.0
var _prev := {} ## Pedestrian -> [position, state]
var _issues := {} ## kind -> [count, first example]
var _states := {} ## state name -> seconds
var _crossings := 0
var _light_crossings := 0
var _red_crossings := 0
var _watches := 0
var _history := {} ## person -> their last state changes (for --debug)
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
	var bus := true
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a == "--no-ride":
			ride = false
		elif a == "--no-bus":
			bus = false
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
	var waiting_most := 0
	var event_posted := false
	while _t < secs:
		await process_frame
		most = maxi(most, pm.people.size())
		var waiting := 0
		for p: Pedestrian in pm.people:
			if is_instance_valid(p) and p.state == Pedestrian.State.WAIT_BUS:
				waiting += 1
		waiting_most = maxi(waiting_most, waiting)
		if not event_posted and _t > secs * 0.3:
			# Something in the street right here: who notices?
			event_posted = true
			StreetEvents.post("crash", eye + Vector3(6.0, -1.7, 4.0), 25.0, 32.0)
		# Look round now and then, so placing and taking away out of sight
		# is tested from every side.
		if shots == "":
			_cam.rotation.y = fmod(_t * 0.15, TAU)
	print("PEDS people: most %d at once (want %d), placed %d, taken away %d" % [most, pm._target(eye), pm.placed, pm.removed])
	var st := []
	for k: String in _states:
		st.append("%s %.0f%%" % [k, 100.0 * _states[k] / maxf(_total_state(), 0.001)])
	print("PEDS time spent: " + ", ".join(st))
	print("PEDS crossings %d (%d at lights: %d on the walk, %d on red), chats %d, thoughts %d, dodges %d" % [_crossings, _light_crossings, _light_crossings - _red_crossings, _red_crossings, _chats, _thoughts, pm.dodges])
	print("PEDS buses: most waiting at once %d, got on %d, got off %d; walking in twos: %d pairs; noticed the crash: %d; watching %d" % [waiting_most, pm.boarded, pm.got_off, pm.pairs, pm.noticed, _watches])
	if OS.get_cmdline_user_args().has("--debug"):
		for p: Pedestrian in pm.people:
			if p.bus_stop >= 0 or p.leader != null:
				print("PEDS DEBUG %s %s stop %d side %d leader %s state %s pos %s path %d/%d goal %s" % [p.name, p.kind, p.bus_stop, p.bus_side, p.leader.name if p.leader != null else "-", Pedestrian.State.keys()[p.state], p.position2(), p._pi, p._path.size(), p.goal.get("inside", "")])
	for k: String in _issues:
		print("PEDS ISSUE %s: %d (first: %s)" % [k, _issues[k][0], _issues[k][1]])
	if _issues.has("in the road") and int(_issues["in the road"][0]) > 3:
		_fail = true
	if shots != "":
		await _shots(pm, shots)
	await _witness(pm, player)
	if ride:
		await _ride(pm, player)
	if bus:
		await _bus(pm, tm, player)
	print("PEDS %s" % ("FAIL" if _fail else "OK"))
	quit(1 if _fail else 0)


## Calling it in: painting someone with no police about gives no stars
## until a witness gets through (PedestrianManager.call_odds, CALL_DELAY);
## painting the caller mid-call stops it.
func _witness(pm: PedestrianManager, player: Node3D) -> void:
	var wanted := root.get_node("Wanted")
	var police := _main.get_node_or_null("Police")
	if police != null:
		police.set("patrols", false)
		for u: Variant in (police.get("units") as Array).duplicate():
			police.call("drop_unit", u)
	var odds: Dictionary = PedestrianManager.call_odds.duplicate()
	var give_up := PedestrianManager.give_up_odds
	for k: String in PedestrianManager.call_odds:
		PedestrianManager.call_odds[k] = 1.0 if k != "teen" else 0.0
	PedestrianManager.give_up_odds = 0.0
	# Only the people on foot call here (a passing driver could too).
	var driver_odds := TrafficWitnesses.call_odds
	TrafficWitnesses.call_odds = 0.0
	var shots := PaintShots.find(_main.get_tree())
	var results: Array[String] = []
	var ok := true
	for case: String in ["calls", "hung_up"]:
		wanted.call("clear")
		pm._calls.clear()
		# No police about (the first case's star brought a cruiser).
		if police != null:
			for u: Variant in (police.get("units") as Array).duplicate():
				police.call("drop_unit", u)
		var victim: Pedestrian = null
		var best := INF
		for p: Pedestrian in pm.people:
			var d := p.global_position.distance_to(player.global_position)
			if p.kind != "teen" and p.state == Pedestrian.State.WALK and d < best:
				best = d
				victim = p
		if victim == null:
			results.append("%s: nobody to paint" % case)
			ok = false
			continue
		# The player a few metres off, in plain view.
		player.call("place", Transform3D(Basis.IDENTITY, victim.global_position + Vector3(5.0, 0.3, 0.0)))
		for i in 10:
			await physics_frame
		var made0 := pm.calls_made
		shots.emit_signal("hit", {"target": victim, "point": victim.global_position + Vector3.UP * 1.2, "shooter": player, "kind": "person", "value": 1, "colour": Color.MAGENTA})
		await physics_frame
		var none_yet := int(wanted.get("level")) == 0 and (wanted.get("unreported") as Array).size() == 1
		var calling := bool(wanted.call("being_called_in"))
		if case == "hung_up" and not pm._calls.is_empty():
			var caller: Pedestrian = pm._calls[0][0]
			await _wait_s(1.0)
			shots.emit_signal("hit", {"target": caller, "point": caller.global_position + Vector3.UP * 1.2, "shooter": player, "kind": "person", "value": 1, "colour": Color.MAGENTA})
		await _wait_s(PedestrianManager.CALL_DELAY.y + 1.5)
		var lvl := int(wanted.get("level"))
		var made := pm.calls_made - made0
		var radio: Variant = police.get("radio") if police != null else null
		var said := ""
		if radio != null:
			for l: Array in radio.get("log"):
				if str(l[1]).contains("reports") or str(l[1]).contains("Call from") or str(l[1]).contains("Another call") or str(l[1]).contains("Report from"):
					said = str(l[1])
		var good := none_yet and calling and (lvl >= 1 and made == 1 if case == "calls" else lvl == 0 and made == 0)
		if case == "calls":
			good = good and said != ""
		ok = ok and good
		results.append("%s: no stars at first %s, calling %s, then level %d, %d calls made%s%s" % [case, none_yet, calling, lvl, made, (" (radio: \"%s\")" % said) if said != "" else "", "" if good else " WRONG"])
	PedestrianManager.call_odds = odds
	PedestrianManager.give_up_odds = give_up
	TrafficWitnesses.call_odds = driver_odds
	wanted.call("clear")
	print("PEDS WITNESS %s: %s" % ["ok" if ok else "FAIL", "; ".join(results)])
	if not ok:
		_fail = true


func _wait_s(secs: float) -> void:
	for i in int(secs * Engine.physics_ticks_per_second):
		await physics_frame


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
	# Sitting on the seat, not left standing at the door.
	for i in 10:
		await physics_frame
	var seat_at := PassengerSeat.of(car).global_position
	var off := Vector2(h.global_position.x - seat_at.x, h.global_position.z - seat_at.z).length()
	print("PEDS RIDE: %.2f m from the seat" % off)
	if off > 0.2:
		_fail = true
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


## Two waiting at University Ave / Gerald St, a route 1 bus coming up
## University Avenue toward Allen Street: it stops, they get on, it goes.
func _bus(pm: PedestrianManager, tm: TrafficManager, player: Node3D) -> void:
	var ts := TransitStops.current
	var si := -1
	for i in ts.stops.size():
		if str(ts.stops[i]["name"]) == "University Ave / Gerald St":
			si = i
	if si < 0:
		print("PEDS BUS: no stop at University Ave / Gerald St")
		_fail = true
		return
	var net := pm.net
	var a: Vector2 = net.nodes[net.find_junction("University Avenue", "Euston Street")]
	var b: Vector2 = net.nodes[net.find_junction("University Avenue", "Allen Street")]
	var r0 := StreetRoute.plan(net, a, b, TrafficManager.plan_options((b - a).normalized()))
	var st: Dictionary = ts.stops[si]
	var sa := r0.project(st["p"])
	var from := maxf(30.0, sa - 140.0)
	var side := ts.right_side(si, r0.dir_at(sa))
	var watch_at := r0.sample(sa - 45.0)
	var eye := Vector3(watch_at.x, _world.terrain.h2(watch_at) + 6.0, watch_at.y)
	_cam.global_position = eye
	# The player here too, on foot across the street (traffic gives physics
	# to the cars near the player; after the ride they're in a car across
	# town).
	if player.get("vehicle") != null:
		player.call("exit_vehicle", _main)
	var across: Vector2 = st["wait"][-side] if (st["wait"] as Dictionary).has(-side) else st["wait"][side]
	player.call("place", Transform3D(Basis.IDENTITY, Vector3(across.x, _world.terrain.h2(across) + 0.4, across.y)))
	tm.focus = eye
	pm.focus = eye
	await _load_streets(watch_at, 220.0)
	var riders: Array[Pedestrian] = []
	for k in 2:
		var p := pm._new_person("commuter")
		p.start_waiting(si, side, pm.slot_point(si, side, k))
		p._bus_wait = 600.0 # here for the test's bus, however long it takes
		riders.append(p)
	var boarded0 := pm.boarded
	var p0 := r0.sample(from)
	var d := tm.spawn_bus(Vector3(p0.x, _world.terrain.h2(p0) + 0.3, p0.y), r0.dir_at(from), 0, 4, b)
	if d == null:
		print("PEDS BUS: couldn't place the bus")
		_fail = true
		return
	var t0 := _t
	var stopped := -1.0
	var gone := -1.0
	while _t - t0 < 120.0 and gone < 0.0:
		await physics_frame
		if d.car == null or not is_instance_valid(d.car):
			break
		if OS.get_cmdline_user_args().has("--debug") and int((_t - t0) * 60.0) % 120 == 0:
			print("PEDS DEBUG bus at %s speed %.1f reason %s stops %s ids %s next %d along %.0f waiting %d" % [Vector2(d.car.global_position.x, d.car.global_position.z), d.car.speed, d.civil.reason, d.bus_stops, d.bus_stop_ids, d.bus_next_stop, d.pilot.along if d.pilot != null else -1.0, pm.waiting_at(si, side)])
		var bp := Vector2(d.car.global_position.x, d.car.global_position.z)
		if stopped < 0.0 and absf(d.car.speed) < 1.0 and bp.distance_to(st["p"]) < 40.0 + TrafficBuses.CURB_SEARCH * 15.0 and pm.boarded + _to_bus(riders) > boarded0:
			stopped = _t - t0
			print("PEDS BUS: stopped %.1f m from the stop" % bp.distance_to(st["p"]))
		elif stopped >= 0.0 and d.car.speed > 3.0:
			gone = _t - t0
	var on := pm.boarded - boarded0
	var still := 0
	var states: Array[String] = []
	for p: Pedestrian in riders:
		if is_instance_valid(p) and not p.on_bus:
			still += 1
			states.append("%s %s at %s" % [p.name, Pedestrian.State.keys()[p.state], p.position2()])
	if not states.is_empty():
		print("PEDS BUS: still there: " + ", ".join(states))
	print("PEDS BUS: route 1 at %s, side %d: pulled in at %.0f s, %d got on, %d left at the stop, pulled out at %.0f s" % [st["name"], side, stopped, on, still, gone])
	if stopped < 0.0 or gone < 0.0 or on < 2:
		_fail = true


func _to_bus(riders: Array[Pedestrian]) -> int:
	var n := 0
	for p: Pedestrian in riders:
		if is_instance_valid(p) and (p.state == Pedestrian.State.TO_BUS or p.on_bus):
			n += 1
	return n


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
				var sig: Array = p._signal_at.get(p._pi, [])
				if not sig.is_empty():
					_light_crossings += 1
					if TrafficSignal.lamp_at(sig[0], 1 - int(sig[1])) != 2:
						_red_crossings += 1
			if p.state == Pedestrian.State.WATCH and was[1] != Pedestrian.State.WATCH:
				_watches += 1
			if p.state == Pedestrian.State.CHAT and was[1] != Pedestrian.State.CHAT:
				_chats += 1
			if p.saying and not was[3] and p._label.modulate.b > p._label.modulate.r + 0.1:
				_thoughts += 1
		if _prev.has(p) and (_prev[p] as Array)[1] != p.state:
			var h: Array = _history.get(p, [])
			h.append("%.1f %s>%s at %.1f,%.1f" % [_t, Pedestrian.State.keys()[(_prev[p] as Array)[1]], sname, pos.x, pos.z])
			if h.size() > 12:
				h.pop_front()
			_history[p] = h
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
				if OS.get_cmdline_user_args().has("--debug"):
					print("PEDS DEBUG stuck %s: %s" % [p.name, "; ".join(_history.get(p, []))])
				_issue("stuck", "%s at %s (%s, path %d/%d, %s, speed %.1f, crossing %s%s)" % [p.name, pos, p.kind, p._pi, p._path.size(),
					("next %s" % p._path[p._pi]) if p._pi < p._path.size() else "at the end", p._speed_now, p._crossing,
					(", beside %s (%s)" % [p.leader.name, Pedestrian.State.keys()[p.leader.state]]) if p.leader != null else ""])
				_still[p] = [pos, _t]
			else:
				_still[p] = s

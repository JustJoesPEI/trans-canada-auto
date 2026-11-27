class_name EmergencyServices
extends Node3D
## The Island Boo-Boo Bus (IBBB, the paramedics) and the Island Wee-Woo
## Brigade (IWWB, the fire department): who gets sent where. One of these,
## a child of Main, beside the traffic and the people on foot. It only runs
## round the local player (like PedestrianManager): nothing on a server.
##
## Calls:
##   * someone down (PedestrianManager.casualty_down: hit by the player's
##     car, or painted out): a few seconds later someone near says so on
##     the phone, and a Boo-Boo Bus comes (more people down nearby join the
##     same call; past PER_BUS a second bus comes). Half the calls, and
##     every big one, the Brigade comes too, because they go to everything.
##   * the player's own car stalled by police paint and left (not wanted):
##     the Brigade hoses it down before the tow truck gets there.
##   * a Jam Jar or a paint bomb in the street: the Brigade hoses the mess.
##   * now and then, nothing near: one of them goes by with the lights and
##     siren on, on its way somewhere else.
##
## The player hitting people (PedestrianManager.struck_by_player) is
## counted here for the wanted level: one in the last HIT_WINDOW seconds is
## "hit_pedestrian" (level 1), three "hit_pedestrians" (2), six or more
## "hit_spree" (3). The police radio and Kinbook say so.
##
## Words: EmergencyLines, RadioLines ("struck", "struck_more", "spree",
## "brigade"), KinbookLines (ABOUT_YOU "struck", "spree"; SCENES).

static var autostart := true

## At once, at most.
const BUSES_MAX := 3
const ENGINES_MAX := 2
const AMBIENT_MAX := 1
## People down per bus before another comes.
const PER_BUS := 4
## People down this near each other are one scene (m).
const SCENE_RADIUS := 30.0
## From someone going down to the call (s).
const CALL_DELAY := Vector2(5.0, 10.0)
## Share of calls the Brigade comes along to (always, three or more down).
const BRIGADE_ODDS := 0.5
## Where a truck starts: this far from the scene (m), out of sight, and
## this far from the player.
const FROM_SCENE := Vector2(60.0, 220.0)
const FROM_PLAYER := Vector2(70.0, 200.0)
## Hits on people counted over this long (s) for the wanted level.
const HIT_WINDOW := 150.0
## The player's stalled car, left this long (s), gets hosed down.
const CAR_AFTER := 10.0
## A paint mess waits this long (s) before the Brigade comes.
const MESS_AFTER := 14.0
## Seconds between trucks going by on other calls.
const AMBIENT_EVERY := Vector2(140.0, 280.0)

var running := true
var main: Node
var world: WorldBuilder
var net: RoadNetwork
var player: Node3D
var hud: Node
var people: PedestrianManager
var traffic: TrafficManager
var units: Array[EmergencyUnit] = []
var rng := RandomNumberGenerator.new()
## For tests and the record.
var calls := 0
var sent := {"ibbb": 0, "iwwb": 0}
var treated := 0
var hosed_cars := 0
var hosed_messes := 0

var _clock := 0.0
var _scan := 0.0
## Calls waiting to be answered: {at: Vector3, patients: Array, due: float}.
var _pending: Array = []
var _hits: Array[float] = []
var _stalled := {} # Car -> seconds left stalled
var _hosed := {} # Car -> true (done once)
var _messes: Array = [] # {at, since}
var _ambient_t := 0.0
var _posted_struck := -INF
var _posted_spree := false
var _scenes_posted := 0


func _ready() -> void:
	name = "EmergencyServices"
	running = autostart and not OS.get_cmdline_args().has("--script")
	main = get_parent()
	world = CarAutopilot.find_world(self)
	net = world.network
	player = main.get_node_or_null("Player") as Node3D
	hud = main.get_node_or_null("HUD")
	rng.seed = 911
	_ambient_t = rng.randf_range(AMBIENT_EVERY.x * 0.5, AMBIENT_EVERY.y)
	var shots := get_tree().get_first_node_in_group("paint_shots")
	if shots != null:
		shots.connect("hit", _on_paint_hit)
	_hook_up.call_deferred()
	_warm_up()


func _hook_up() -> void:
	people = main.get_node_or_null("Pedestrians") as PedestrianManager
	traffic = main.get_node_or_null("Traffic") as TrafficManager
	if people != null:
		people.casualty_down.connect(_on_casualty)
		people.struck_by_player.connect(_on_struck)


## The trucks' meshes and the crews' bodies built behind the loading
## screen, one a frame, so the first call doesn't stop the game.
func _warm_up() -> void:
	for id: String in ["ambulance", "fire_engine"]:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var c := Color.from_string(str(CarModels.get_model(id)["colours"][0]), Color.WHITE)
		if not Car.is_warm(id, c):
			Car.warm_meshes(id, c)
	Responder.warm_looks(self)


func player_point() -> Vector3:
	if player != null and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _physics_process(delta: float) -> void:
	_clock += delta
	for u: EmergencyUnit in units.duplicate():
		if not u.step_unit(delta):
			_remove(u)
	if not running:
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	_answer_calls()
	_watch_cars(0.5)
	_watch_messes()
	_ambient(0.5)


# --- people down -----------------------------------------------------------------------------

func _on_casualty(p: Pedestrian) -> void:
	var at := p.global_position
	# A bus already there or on its way, with room: theirs.
	for u: EmergencyUnit in units:
		if u.kind == "ibbb" and u.job == "casualty" and u.busy_at(at, SCENE_RADIUS) and u.patients.size() < PER_BUS:
			u.add_patient(p)
			return
	for c: Dictionary in _pending:
		if (c["at"] as Vector3).distance_to(at) < SCENE_RADIUS and (c["patients"] as Array).size() < PER_BUS:
			(c["patients"] as Array).append(p)
			return
	_pending.append({"at": at, "patients": [p], "due": _clock + rng.randf_range(CALL_DELAY.x, CALL_DELAY.y), "said": false})


func _answer_calls() -> void:
	for c: Dictionary in _pending.duplicate():
		var ps: Array = (c["patients"] as Array).filter(func(x: Variant) -> bool: return is_instance_valid(x) and (x as Pedestrian).hurt())
		c["patients"] = ps
		if ps.is_empty():
			_pending.erase(c)
			continue
		var at: Vector3 = c["at"]
		if not bool(c["said"]) and float(c["due"]) - _clock < 4.0:
			c["said"] = true
			var caller := _caller_near(at)
			if caller != null:
				caller.on_phone(4.5)
				caller.say(PedestrianLines.pick(caller.rng, EmergencyLines.CALLING), 3.5)
		if _clock < float(c["due"]) or _count("ibbb") >= BUSES_MAX:
			continue
		var u := _send("ibbb", "casualty", at)
		if u == null:
			c["due"] = _clock + 3.0 # nowhere to come from yet: try again
			continue
		_pending.erase(c)
		calls += 1
		for p: Pedestrian in ps:
			u.add_patient(p)
		if (ps.size() >= 3 or rng.randf() < BRIGADE_ODDS) and _count("iwwb") < ENGINES_MAX and not _brigade_near(at):
			_send("iwwb", "standby", at)


## Someone near `at` on their feet, not busy, to make the call.
func _caller_near(at: Vector3) -> Pedestrian:
	if people == null:
		return null
	var best: Pedestrian = null
	var best_d := 35.0
	for p: Pedestrian in people.people:
		if not is_instance_valid(p) or p.state in [Pedestrian.State.DOWN, Pedestrian.State.RIDE, Pedestrian.State.INSIDE] or p.on_bus:
			continue
		var d := p.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	return best


func _count(kind: String, job := "") -> int:
	var n := 0
	for u: EmergencyUnit in units:
		if u.kind == kind and (job == "" or u.job == job):
			n += 1
	return n


func _brigade_near(at: Vector3) -> bool:
	for u: EmergencyUnit in units:
		if u.kind == "iwwb" and u.busy_at(at, 45.0):
			return true
	return false


## A Boo-Boo Bus still working near `at`.
func boo_boo_busy_at(at: Vector3, r: float) -> bool:
	for u: EmergencyUnit in units:
		if u.kind == "ibbb" and u.job == "casualty" and not u.done() and u.busy_at(at, r):
			return true
	for c: Dictionary in _pending:
		if (c["at"] as Vector3).distance_to(at) < r:
			return true
	return false


# --- the player hitting people ---------------------------------------------------------------

func _on_struck(p: Pedestrian, car: Car, kind: String) -> void:
	if kind == "bump":
		return
	_hits.append(_clock)
	while not _hits.is_empty() and _clock - _hits[0] > HIT_WINDOW:
		_hits.pop_front()
	var n := _hits.size()
	var crime := "hit_spree" if n >= 6 else ("hit_pedestrians" if n >= 3 else "hit_pedestrian")
	var w := get_node_or_null("/root/Wanted")
	if w != null and w.has_method("report_crime"):
		w.call("report_crime", crime, p.global_position)
	if traffic != null:
		traffic.crime_seen.emit("hit_pedestrian", p.global_position)
	var extra := _radio_vars(p.global_position, car)
	if n == 1:
		_radio("struck", extra)
	elif n == 3:
		_radio("struck_more", extra)
	elif n == 6:
		_radio("spree", extra)
	var kb := main.get_node_or_null("Kinbook")
	if kb != null:
		if n >= 6 and not _posted_spree:
			_posted_spree = true
			kb.call("post_about_you", "spree")
		elif _clock - _posted_struck > 300.0:
			_posted_struck = _clock
			kb.call("post_about_you", "struck")


func _radio_vars(at: Vector3, car: Car) -> Dictionary:
	var v := {"street": _street(at)}
	if car != null:
		v["car"] = str(CarModels.get_model(car.model_id)["model"])
		v["colour"] = PoliceDispatcher._colour_name(car.paint)
	return v


func _street(at: Vector3) -> String:
	var s := world.street_name_at(Vector2(at.x, at.z), 40.0) if world != null else ""
	return s if s != "" else "downtown"


func _radio(topic: String, extra := {}) -> void:
	var disp := PoliceDispatcher.find(get_tree())
	if disp != null and disp.radio != null:
		disp.radio.say(topic, 0, extra)


# --- the Brigade's other calls ---------------------------------------------------------------

## The player's own car, stalled by police paint and left (not wanted):
## hosed down so it starts again.
func _watch_cars(dt: float) -> void:
	var w := get_node_or_null("/root/Wanted")
	if w != null and int(w.get("level")) > 0:
		_stalled.clear()
		return
	var pp := player_point()
	var pv: Variant = player.get("vehicle") if player != null else null
	for c: Car in Car.all:
		if not is_instance_valid(c) or c.owner_id != "local" or not c.stalled or c.driver != null or c == pv or _hosed.has(c):
			continue
		var d := c.global_position.distance_to(pp)
		if d < 12.0 or d > 160.0:
			continue
		_stalled[c] = float(_stalled.get(c, 0.0)) + dt
		if float(_stalled[c]) >= CAR_AFTER and _count("iwwb") < ENGINES_MAX:
			var u := _send("iwwb", "car", c.global_position)
			if u != null:
				u.target_car = c
				_hosed[c] = true
				_stalled.erase(c)


## A Jam Jar or a paint bomb from the player: a mess for the Brigade.
func _on_paint_hit(info: Dictionary) -> void:
	if player == null or info.get("shooter") != player:
		return
	if not str(info.get("weapon", "")) in ["jam_jars", "tourist_season"]:
		return
	var at: Vector3 = info.get("point", Vector3.INF)
	if at == Vector3.INF:
		return
	for m: Dictionary in _messes:
		if (m["at"] as Vector3).distance_to(at) < 15.0:
			return
	_messes.append({"at": at, "since": _clock})
	if _messes.size() > 6:
		_messes.pop_front()


func _watch_messes() -> void:
	var w := get_node_or_null("/root/Wanted")
	var level := int(w.get("level")) if w != null else 0
	for m: Dictionary in _messes.duplicate():
		if _clock - float(m["since"]) < MESS_AFTER:
			continue
		if level >= 3 or _clock - float(m["since"]) > 240.0:
			_messes.erase(m) # (a big chase: they've other things to do)
			continue
		if _count("iwwb") >= ENGINES_MAX or _brigade_near(m["at"]):
			continue
		if _send("iwwb", "mess", m["at"]) != null:
			_messes.erase(m)


## Every few minutes, one of them goes by on a call somewhere else.
func _ambient(dt: float) -> void:
	_ambient_t -= dt
	if _ambient_t > 0.0:
		return
	_ambient_t = rng.randf_range(AMBIENT_EVERY.x, AMBIENT_EVERY.y)
	if _count("ibbb", "ambient") + _count("iwwb", "ambient") >= AMBIENT_MAX:
		return
	var w := get_node_or_null("/root/Wanted")
	if w != null and int(w.get("level")) >= 3:
		return
	_send("ibbb" if rng.randf() < 0.55 else "iwwb", "ambient", player_point(), true)


# --- sending a truck -------------------------------------------------------------------------

## A truck for `job` at `at`, placed out of sight on a street near it and
## driving there; null if there's nowhere to place it now. An ambient run
## starts near the player and heads for `at`, passing by.
func _send(kind: String, job: String, at: Vector3, passing := false) -> EmergencyUnit:
	var stop := Vector3.INF
	var start := {}
	if passing:
		# From one side of the player, past them, to a street on the other.
		var fp := player_point()
		start = _start_point(Vector2(fp.x, fp.z), true)
		if start.is_empty():
			return null
		var sp: Vector3 = start["pos"]
		var across := Vector3(fp.x - sp.x, 0.0, fp.z - sp.z).normalized()
		stop = _stop_point(fp + across * 260.0)
	else:
		stop = _stop_point(at)
		if stop != Vector3.INF:
			start = _start_point(Vector2(stop.x, stop.z), false)
	if stop == Vector3.INF or start.is_empty():
		return null
	var model := "ambulance" if kind == "ibbb" else "fire_engine"
	var c := Car.new()
	c.model_id = model
	c.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	c.owner_id = "service"
	c.name = "%s_%d" % [kind.to_upper(), sent[kind] + 1]
	main.add_child(c)
	var p3: Vector3 = start["pos"]
	var dir: Vector2 = start["dir"]
	c.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3 + Vector3.UP * 0.4)
	c.reset_physics_interpolation()
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = net
	ap.corner_accel = 3.4
	ap.brake_accel = 3.2
	c.add_child(ap)
	var cars: Variant = main.get("cars")
	if cars is Array:
		(cars as Array).append(c)
	var u := EmergencyUnit.new(self, kind, job, at)
	add_child(u)
	units.append(u)
	sent[kind] = int(sent[kind]) + 1
	u.respond(c, ap, stop)
	return u


## Where a truck pulls up for something at `at`: on the nearest street, in
## the lane on its side.
func _stop_point(at: Vector3) -> Vector3:
	var p := Vector2(at.x, at.z)
	var hit := net.nearest_on_streets(p, 45.0)
	if hit.is_empty():
		return Vector3.INF
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var dir: Vector2 = hit["dir"]
	var q: Vector2 = hit["pos"]
	var side := signf((p - q).dot(RoadNetwork._perp(dir)))
	if side == 0.0:
		side = 1.0
	var s := q + RoadNetwork._perp(dir) * side * maxf(e.half_width - 1.8, 0.8)
	return Vector3(s.x, world.terrain.h2(s), s.y)


## A street out of sight to start from, with a route to `to`: {pos, dir}.
func _start_point(to: Vector2, passing: bool) -> Dictionary:
	var fp := player_point()
	var fp2 := Vector2(fp.x, fp.z)
	var centre := fp2 if passing else to
	var reach := FROM_PLAYER.y if passing else FROM_SCENE.y
	var edges := net.edges_near(Rect2(centre - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	edges.shuffle()
	edges.sort_custom(func(a: RoadNetwork.RoadEdge, b: RoadNetwork.RoadEdge) -> bool: return TrafficDensity.class_weight(a) > TrafficDensity.class_weight(b))
	var tries := 0
	for e in edges:
		if TrafficDensity.class_weight(e) <= 0.0 or e.bridge or e.length < 24.0:
			continue
		var along := rng.randf_range(8.0, e.length - 8.0)
		var sp: Array = RoadNetwork.sample(e.points, along)
		var q: Vector2 = sp[0]
		var dq := q.distance_to(to)
		var dp := q.distance_to(fp2)
		if dp < FROM_PLAYER.x or dp > FROM_PLAYER.y:
			continue
		if not passing and (dq < FROM_SCENE.x or dq > FROM_SCENE.y):
			continue
		tries += 1
		if tries > 12:
			return {}
		for forward: bool in [true, false]:
			if (e.oneway == 1 and not forward) or (e.oneway == -1 and forward):
				continue
			var dv: Vector2 = (sp[1] as Vector2) * (1.0 if forward else -1.0)
			var st: Vector2 = q + Vector2(-dv.y, dv.x) * StreetRoute._lane_offset(e, forward)
			var r := StreetRoute.plan(net, st, to, TrafficManager.plan_options(dv))
			if r.is_empty() or r.partial or r.length > dq * 1.8 + 80.0:
				continue
			var gy := _ground(st)
			if is_nan(gy):
				continue
			var p3 := Vector3(st.x, gy, st.y)
			if TrafficSight.seen(get_tree(), p3, fp):
				continue
			return {"pos": p3, "dir": dv}
	return {}


func _ground(p: Vector2) -> float:
	var h := world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 6.0, p.y), Vector3(p.x, h - 6.0, p.y), Layers.GROUND)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


## Somewhere to drive off to, ahead.
func away_from(p: Vector2, fwd: Vector2) -> Vector3:
	if traffic != null and traffic.dests != null:
		var d := traffic.dests.pick(rng, p, 350.0, 1200.0, fwd.normalized())
		if not d.is_empty():
			var s: Vector2 = d["street"]
			return Vector3(s.x, world.terrain.h2(s), s.y)
	var s2 := p + fwd.normalized() * 500.0
	return Vector3(s2.x, world.terrain.h2(s2), s2.y)


func _remove(u: EmergencyUnit) -> void:
	units.erase(u)
	if u.car != null and is_instance_valid(u.car):
		var cars: Variant = main.get("cars")
		if cars is Array:
			(cars as Array).erase(u.car)
		PoliceUnit._silence(u.car)
		u.car.queue_free()
	u._drop_crew()
	u.queue_free()


# --- what the units report -------------------------------------------------------------------

func arrived(u: EmergencyUnit) -> void:
	StreetEvents.post("boo_boo" if u.kind == "ibbb" else "brigade", u.scene, 60.0, 35.0)


func brigade_on_scene(u: EmergencyUnit) -> void:
	var w := get_node_or_null("/root/Wanted")
	if w != null and int(w.get("level")) > 0:
		_radio("brigade", {"street": _street(u.scene)})
	_scenes_posted += 1
	var kb := main.get_node_or_null("Kinbook")
	if kb != null and _scenes_posted % 2 == 1:
		kb.call("post_scene", "brigade", _street(u.scene))


func patched(p: Pedestrian) -> void:
	treated += 1
	if treated % 4 == 1:
		var kb := main.get_node_or_null("Kinbook")
		if kb != null:
			kb.call("post_scene", "boo_boo", _street(p.global_position))


func car_hosed(c: Car) -> void:
	if c == null or not is_instance_valid(c):
		return
	CarWashes.wash_paint(c)
	hosed_cars += 1
	if hud != null and hud.has_method("show_title") and c.owner_id == "local":
		hud.call("show_title", "The Wee-Woo Brigade hosed down your %s" % c.display_name(), "It'll start now. They'd like that noted.")


func mess_hosed(at: Vector3) -> void:
	var shots := get_tree().get_first_node_in_group("paint_shots")
	if shots != null and shots.get("splats") != null:
		(shots.get("splats") as PaintSplats).clear_near(at, 9.0)
	hosed_messes += 1


## A line from a car's crew, over the car (an officer answering the
## Brigade from the cruiser).
func say_from_car(c: Car, text: String) -> void:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 34
	l.pixel_size = 0.006
	l.outline_size = 8
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 620.0
	l.modulate = Color(0.75, 0.88, 1.0)
	l.text = text
	l.visibility_range_end = 50.0
	l.position = Vector3(0.0, float(c.shape.get("height", 1.5)) + 0.7, 0.0)
	c.add_child(l)
	get_tree().create_timer(3.6, false).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())

class_name EmergencyUnit
extends Node
## One Island Boo-Boo Bus or Island Wee-Woo Brigade truck and its crew
## (EmergencyServices sends them). It drives to the scene with the lights
## and siren on (traffic pulls over for it, as for the police), parks at
## the curb, the crew get out and do the job, get back in, and it drives
## off with the lights off, to be taken away once nobody can see it.
##
## Jobs:
##   "casualty"  (the Boo-Boo Bus) people down: a paramedic to each in
##               turn, they sit up, get asked the questions, get rinsed if
##               there's paint on them, get a brace, a bandage or a
##               blanket, and walk off
##   "standby"   (the Brigade) at someone else's scene, because they go to
##               everything: the captain, Kevin on the hose wanting to spray
##               something, and a third standing by the truck. They tease
##               any police car that comes by. Once the Boo-Boo Bus is done,
##               Kevin gets his squirt, and they go
##   "car"       (the Brigade) the player's car stalled by police paint:
##               hosed down so it starts (and isn't towed to the impound)
##   "mess"      (the Brigade) a mess of paint in the street: hosed away
##   "ambient"   either, lights and siren, on its way to a call somewhere:
##               no crew, it only drives past

enum Step { RESPOND, SCENE, PACK_UP, LEAVE }

## Seconds to get to the scene before giving up.
const RESPOND_LIMIT := 150.0
## How long the Brigade stands by at most (s), and at least.
const STANDBY_MAX := 95.0
const STANDBY_MIN := 22.0
## Once leaving, taken away when out of sight this far from the player
## (m), or past this whether seen or not.
const GONE_UNSEEN := 120.0
const GONE_ANYWAY := 230.0

var services: EmergencyServices
var kind := "ibbb"
var job := "casualty"
var scene := Vector3.ZERO
var stop := Vector3.ZERO
var patients: Array[Pedestrian] = []
var target_car: Car = null
var car: Car = null
var pilot: CarAutopilot = null
var crew: Array[Responder] = []
var step := Step.RESPOND
var t := 0.0
var rng := RandomNumberGenerator.new()
## Patients seen to (for the record and the checks).
var treated := 0

var _phase := ""
var _pt := 0.0
var _current: Pedestrian = null
## Lines still to come: [seconds from now, who (a Responder, a Pedestrian
## or a Label3D), text].
var _talk: Array = []
var _banter_done := {}
var _banter_t := 0.0
var _kevin_t := 0.0
var _kevin_turn := true


func _init(s: EmergencyServices, k: String, j: String, at: Vector3) -> void:
	services = s
	kind = k
	job = j
	scene = at
	name = "%s_%s" % [k, j]
	rng.seed = hash(at) ^ Time.get_ticks_usec()


## Drive to `stop_at` with the lights and siren on.
func respond(the_car: Car, the_pilot: CarAutopilot, stop_at: Vector3) -> void:
	car = the_car
	pilot = the_pilot
	stop = stop_at
	step = Step.RESPOND
	t = 0.0
	pilot.use_civil_driving(false)
	pilot.chase_mode = CarAutopilot.ChaseMode.RESPOND
	pilot.cruise_speed_kmh = 62.0 if kind == "ibbb" else 52.0
	pilot.drive_to(stop)
	pilot.arrived.connect(_on_arrived)
	if car.police != null:
		car.police.set_mode(PoliceGear.Mode.SIREN)


func busy_at(p: Vector3, r: float) -> bool:
	return step != Step.LEAVE and Vector2(scene.x - p.x, scene.z - p.z).length() < r


## Finished with its scene (the Brigade watches for the Boo-Boo Bus's).
func done() -> bool:
	return step == Step.LEAVE or step == Step.PACK_UP


func add_patient(p: Pedestrian) -> void:
	if not patients.has(p):
		patients.append(p)


func step_unit(delta: float) -> bool:
	t += delta
	if car == null or not is_instance_valid(car):
		_drop_crew()
		return false
	if car.driver != null:
		# The player took it: the job's off, the crew go home on foot (out
		# of sight).
		_release_patients()
		if car.police != null:
			car.police.set_mode(PoliceGear.Mode.OFF)
		car = null
		_drop_crew()
		return false
	_say_queued(delta)
	match step:
		Step.RESPOND:
			if job == "ambient" and t > 15.0:
				# Gone by: taken away once it's well past, out of sight.
				var fp := services.player_point()
				var dp := car.global_position.distance_to(fp)
				if dp > GONE_ANYWAY or (dp > GONE_UNSEEN and not TrafficSight.seen(get_tree(), car.global_position, fp)):
					return false
			var flat := Vector2(car.global_position.x - stop.x, car.global_position.z - stop.z).length()
			if flat < 9.0 and absf(car.speed) < 1.5:
				_on_arrived()
			elif t > RESPOND_LIMIT:
				_release_patients()
				_leave()
		Step.SCENE:
			_pt += delta
			match job:
				"casualty":
					_casualty_step(delta)
				"standby":
					_standby_step(delta)
				"car", "mess":
					_hose_step(delta)
		Step.PACK_UP:
			_pt += delta
			var all_in := true
			for i in crew.size():
				var r := crew[i]
				if not is_instance_valid(r):
					continue
				if not r.aboard:
					if r.at_goal() or _pt > 14.0:
						r.board(car, _seat(i, r.model), _door(i))
					all_in = false
				elif not r.settled():
					all_in = false
			if all_in or _pt > 20.0:
				_leave()
		Step.LEAVE:
			var fp := services.player_point()
			var d := car.global_position.distance_to(fp)
			if d > GONE_ANYWAY or (d > GONE_UNSEEN and not TrafficSight.seen(get_tree(), car.global_position, fp)) \
					or (t > 120.0 and not TrafficSight.seen(get_tree(), car.global_position, fp)):
				return false
	return true


func _on_arrived() -> void:
	if step != Step.RESPOND:
		return
	if job == "ambient":
		_leave()
		return
	pilot.stop()
	if car.police != null:
		car.police.set_mode(PoliceGear.Mode.LIGHTS)
	step = Step.SCENE
	t = 0.0
	_pt = 0.0
	match job:
		"casualty":
			_crew_out(["medic", "medic"])
			_phase = "next"
		"standby":
			_crew_out(["captain", "kevin", "firefighter"])
			_phase = "arrive"
		_:
			_crew_out(["captain", "kevin"])
			_phase = "arrive"
	services.arrived(self)


# --- the crew ----------------------------------------------------------------------------------

## The crew climb out of their seats, each by their own door (the front
## two, then the crew cab behind).
func _crew_out(roles: Array) -> void:
	var yaw := car.global_basis.get_euler().y
	for i in roles.size():
		var r := Responder.new()
		r.setup(str(roles[i]), rng.randi() % Responder.LOOKS)
		services.add_child(r)
		var seat := car.global_transform * _seat(i, r.model)
		r.climb_out_at(_door(i) + Vector3.UP * 0.05, yaw, seat)
		crew.append(r)


## Where a crew member gets out and back in: beside their door, on the
## ground.
func _door(i: int) -> Vector3:
	var hw := float(car.shape.get("width", 2.2)) * 0.5 + 0.55
	var side := -1.0 if i % 2 == 0 else 1.0
	var at := car.global_transform * Vector3(side * hw, 0.0, float(car.shape["seat"][2]) + (i / 2) * 1.6)
	var hit := car.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, Layers.GROUND))
	return (hit["position"] as Vector3) if not hit.is_empty() else at


## Crew member `i`'s seat, in the truck's space, for a body `m`: the
## model's origin when sat there (the seat marks the hips), the driver on
## the left, beside them on the right, the crew cab behind.
func _seat(i: int, m: HumanoidModel) -> Transform3D:
	var sp := car.seat.position
	var side := -1.0 if i % 2 == 0 else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(side * absf(sp.x), sp.y - m.height / 1.75 * 0.93, sp.z + (i / 2) * 1.6))


func _pack_up() -> void:
	step = Step.PACK_UP
	_pt = 0.0
	for i in crew.size():
		var r := crew[i]
		if is_instance_valid(r):
			r.drop_hose()
			r.gesture = 0.0
			r.move_to(_door(i))


func _drop_crew() -> void:
	for r: Responder in crew:
		if is_instance_valid(r):
			r.queue_free()
	crew.clear()


func _leave() -> void:
	step = Step.LEAVE
	t = 0.0
	if car == null:
		return
	if car.police != null:
		car.police.set_mode(PoliceGear.Mode.OFF)
	var c := pilot.use_civil_driving(true)
	if c != null:
		c.pulls_over = false
	pilot.cruise_speed_kmh = 50.0
	var p := Vector2(car.global_position.x, car.global_position.z)
	var f := -car.global_basis.z
	var dest := services.away_from(p, Vector2(f.x, f.z))
	pilot.drive_to(dest)


func _release_patients() -> void:
	for p: Pedestrian in patients:
		if is_instance_valid(p) and p.responder != null and not crew.has(p.responder):
			continue
		if is_instance_valid(p):
			p.responder = null
	patients.clear()


# --- talking -----------------------------------------------------------------------------------

## Lines one after another, `gap` s apart, starting after `first`: each
## [who, text].
func _queue(lines: Array, gap := 2.6, first := 0.0) -> float:
	var at := first
	for l: Array in lines:
		_talk.append([at, l[0], str(l[1])])
		at += gap
	return at


func _say_queued(delta: float) -> void:
	for i in range(_talk.size() - 1, -1, -1):
		var e: Array = _talk[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) > 0.0:
			continue
		_talk.remove_at(i)
		var who: Variant = e[1]
		if who == null or not is_instance_valid(who):
			continue
		if who is Responder:
			(who as Responder).say(str(e[2]))
		elif who is Pedestrian:
			(who as Pedestrian).say(str(e[2]), 3.4)
		elif who is Car:
			services.say_from_car(who as Car, str(e[2]))


func _pick(lines: Array) -> Variant:
	return lines[rng.randi() % lines.size()]


# --- the Boo-Boo Bus ---------------------------------------------------------------------------

func _casualty_step(_delta: float) -> void:
	var lead: Responder = crew[0] if crew.size() > 0 else null
	var kit: Responder = crew[1] if crew.size() > 1 else null
	if lead == null:
		_pack_up()
		return
	if _phase != "next" and (_current == null or not is_instance_valid(_current) or _current.state != Pedestrian.State.DOWN):
		_phase = "next"
	match _phase:
		"next":
			_current = _next_patient()
			if _current == null:
				if treated > 0 and rng.randf() < 0.5:
					var chat: Array = _pick(EmergencyLines.MEDIC_CHAT)
					_queue([[lead, chat[0]], [kit, chat[1]]], 2.4)
				_pack_up()
				return
			_current.responder = lead
			var pp := _current.global_position
			var from := (car.global_position - pp)
			from.y = 0.0
			from = from.normalized() if from.length() > 0.1 else Vector3.RIGHT
			lead.move_to(pp + from * 0.8, true)
			lead.face = pp
			if kit != null:
				kit.move_to(pp + Basis(Vector3.UP, PI * 0.5) * from * 0.9, false)
				kit.face = pp
			_phase = "walk"
			_pt = 0.0
		"walk":
			if lead.at_goal() or _pt > 18.0:
				_current.begin_treatment(lead)
				lead.tend = _current.global_position + Vector3.UP * 0.55
				var lines: Array = [[lead, _pick(EmergencyLines.MEDIC_ARRIVE)]]
				var pool: Array = EmergencyLines.ASSESS.duplicate()
				pool.append_array(EmergencyLines.ASSESS_STRUCK if _current.down_kind == "struck" else EmergencyLines.ASSESS_PAINTED)
				var ex: Array = _pick(pool)
				for i in ex.size():
					lines.append([lead if i % 2 == 0 else _current, ex[i]])
				_pt = 0.0
				_phase = "assess"
				_phase_len = _queue(lines, 2.7, 0.3) + 0.6
		"assess":
			if _pt > _phase_len:
				_pt = 0.0
				if _current.body_paint != null and not _current.body_paint.splats.is_empty() and kit != null:
					kit.say(str(_pick(EmergencyLines.RINSE)))
					kit.spray_at(_current.global_position + Vector3.UP * 0.6, 3.0, false)
					_phase = "rinse"
				else:
					_phase = "patch"
		"rinse":
			if _pt > 3.3:
				if _current.body_paint != null:
					_current.body_paint.clear()
				_pt = 0.0
				_phase = "patch"
		"patch":
			if _pt < 0.05:
				lead.say(str(_pick(EmergencyLines.MEDIC_DONE)))
			if _pt > 1.6:
				var what := ["brace", "bandage", "blanket"][rng.randi() % 3] as String
				_current.patch_up(what)
				_current.say(str(_pick(EmergencyLines.PATIENT_LEAVES)), 3.2)
				services.patched(_current)
				treated += 1
				lead.tend = Vector3.INF
				_current = null
				_pt = 0.0
				_phase = "breather"
		"breather":
			if _pt > 2.2:
				_phase = "next"


var _phase_len := 0.0


func _next_patient() -> Pedestrian:
	var best: Pedestrian = null
	var best_d := INF
	var lead := crew[0]
	for p: Pedestrian in patients:
		if not is_instance_valid(p) or not p.casualty():
			continue
		if p.responder != null and p.responder != lead and is_instance_valid(p.responder):
			continue
		var d := p.global_position.distance_to(lead.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# --- the Brigade -------------------------------------------------------------------------------

func _role(r: String) -> Responder:
	for c: Responder in crew:
		if is_instance_valid(c) and c.role == r:
			return c
	return null


## Where the hose comes off the truck: the pump panel, behind the cab on the
## curb side.
func _pump_offset() -> Vector3:
	return Vector3(float(car.shape.get("width", 2.5)) * 0.5, 1.0, -1.9)


func _standby_step(delta: float) -> void:
	var cap := _role("captain")
	var kev := _role("kevin")
	var ff := _role("firefighter")
	if cap == null or kev == null:
		_pack_up()
		return
	match _phase:
		"arrive":
			var pair: Array = _pick(EmergencyLines.FIRE_ARRIVE)
			_queue([[cap, pair[0]], [kev, pair[1]]], 2.6, 0.8)
			var to := scene - car.global_position
			to.y = 0.0
			var spot := scene - to.normalized() * 6.0 if to.length() > 7.0 else car.global_position + to * 0.5
			kev.move_to(spot)
			kev.face = scene
			kev.hold_hose(car, _pump_offset())
			cap.move_to(spot + Basis(Vector3.UP, PI * 0.5) * to.normalized() * 2.2)
			cap.face = scene
			if ff != null:
				ff.move_to(car.global_transform * Vector3(float(car.shape.get("width", 2.5)) * 0.5 + 1.0, 0.0, -0.5))
				ff.face = scene
			_kevin_t = 9.0
			_phase = "wait"
			services.brigade_on_scene(self)
		"wait":
			_kevin_t -= delta
			if _kevin_t <= 0.0:
				_kevin_t = rng.randf_range(8.0, 12.0)
				if _kevin_turn:
					_queue([[kev, _pick(EmergencyLines.KEVIN)], [cap, _pick(EmergencyLines.CAPTAIN)]], 2.6)
				_kevin_turn = not _kevin_turn
			_banter(delta, cap if ff == null or rng.randf() < 0.5 else ff)
			var bus_busy := services.boo_boo_busy_at(scene, 35.0)
			if _pt > STANDBY_MAX or (_pt > STANDBY_MIN and not bus_busy):
				var go: Array = _pick(EmergencyLines.KEVIN_GO)
				_queue([[cap, go[0]], [kev, go[1]]], 2.2)
				_phase = "squirt"
				_pt = 0.0
		"squirt":
			if _pt > 2.4 and not kev.spraying() and _pt < 3.0:
				var ahead := kev.global_position + (scene - kev.global_position).normalized() * 5.0
				kev.spray_at(ahead, 2.6, true)
			if _pt > 6.0:
				cap.say(str(_pick(EmergencyLines.FIRE_LEAVE)))
				_pack_up()


## The car or the mess: hose it down.
func _hose_step(_delta: float) -> void:
	var cap := _role("captain")
	var kev := _role("kevin")
	if cap == null or kev == null:
		_pack_up()
		return
	var target := scene
	if job == "car":
		if target_car == null or not is_instance_valid(target_car) or target_car.driver != null:
			_pack_up()
			return
		target = target_car.global_position
	match _phase:
		"arrive":
			var pair: Array = _pick(EmergencyLines.FIRE_CAR if job == "car" else EmergencyLines.FIRE_MESS)
			_queue([[cap, pair[0]], [kev, pair[1]]], 2.6, 0.6)
			var to := target - car.global_position
			to.y = 0.0
			var spot := target - to.normalized() * (4.0 if job == "car" else 5.5)
			kev.move_to(spot)
			kev.face = target
			kev.hold_hose(car, _pump_offset())
			cap.move_to(spot + Basis(Vector3.UP, -PI * 0.5) * to.normalized() * 2.0)
			cap.face = target
			_phase = "walk"
			_pt = 0.0
		"walk":
			if kev.at_goal() or _pt > 14.0:
				kev.spray_at(target + Vector3.UP * (0.8 if job == "car" else 0.0), 6.0, true)
				_phase = "spray"
				_pt = 0.0
		"spray":
			if _pt > 6.2:
				if job == "car":
					services.car_hosed(target_car)
				else:
					services.mess_hosed(scene)
				cap.say(str(_pick(EmergencyLines.FIRE_LEAVE)))
				_pack_up()


## A police car near the scene: one exchange each, a firefighter and the
## car's crew (a line over the car).
func _banter(delta: float, ours: Responder) -> void:
	_banter_t -= delta
	if _banter_t > 0.0 or ours == null:
		return
	_banter_t = 2.0
	for n: Node in get_tree().get_nodes_in_group("police_vehicles"):
		var pc := n as Car
		if pc == null or _banter_done.has(pc) or pc.global_position.distance_to(car.global_position) > 45.0:
			continue
		_banter_done[pc] = true
		var ex: Array = _pick(EmergencyLines.BANTER)
		var lines: Array = []
		for l: Array in ex:
			lines.append([ours if l[0] == "fire" else pc, l[1]])
		_queue(lines, 2.6)
		_banter_t = 30.0
		return

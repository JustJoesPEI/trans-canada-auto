class_name Officer
extends CharacterBody3D
## One police officer (docs/design.md section 7): in a seat, leaning out of
## the passenger window with a marker, or on foot with one. Two ride in
## every police vehicle (PoliceUnit decides what they do; this does it).
##
## They can be painted like anyone (BodyPaint: 4 hits, OUT_HITS, half a
## player's 8; a head hit counts 2). Out, it has to read instantly across a parking lot: the "I'm out"
## call, a hand straight up with the marker held over the head, barrel to
## the sky, a bright yellow OUT vest pulled on over the uniform, gone from
## the aim assist (is_out) and the minimap, and no longer hit at all (balls
## pass through: no collision). Then one of the exits from the design
## (paperwork, the union rep, "That's going in my report", overtime on the
## curb, "Do you know who I am?"), and gone once nobody's looking.
##
## On foot it goes where it's told (`move_to`), runs or walks, faces and
## shoots at `shoot_at` when it can see it, aiming with the drop and a lead
## and a miss that depends on `aim_error`. It fights so you can read it and
## beat it, the way the cops in the big crime games do: a call when it
## brings the marker up, a moment to draw a bead, the first shot or two
## (`warning_shots`) put into the ground and the wall beside you (it looks
## and sounds dangerous and tells you to move), then bursts with a gap
## between them (`burst`, `burst_pause`): the gap is your window. A hit
## staggers it (STAGGER): the burst stops and it has to settle again, so
## getting the first shot in matters. No pathfinding: straight lines,
## sidestepping what it bumps into. The unit keeps it to open ground (round
## its car, along the street).
##
## Joins "police" (its paint is the police's evidence orange: PaintShots)
## and "aim_targets" (AimAssist: aim_points, is_out, is_police).

## Out (by is the shooter).
signal went_out(by: Node)
## Finished its exit and wants to be removed.
signal done

enum State { SEATED, LEANING, ON_FOOT, OUT }

## The exits (design.md, "Shooting your way out"): what they say and do,
## and what their hands do once the marker's down (HumanoidModel.task):
## the paperwork in the car, the union rep on the phone, the report in the
## notebook, the overtime on the phone on the curb.
const EXITS := [
	{"say": "Right. Paperwork.", "do": "car", "task": "notepad"},
	{"say": "I'm calling my union rep.", "do": "stand", "task": "call"},
	{"say": "That's going in my report.", "do": "stand", "then": "*long sigh*", "task": "notepad"},
	{"say": "Checking my overtime.", "do": "curb", "task": "phone"},
]
const FIP_EXIT := {"say": "Do you know who I am?", "do": "stand", "then": "...Anyone?", "task": "arms_crossed"}
## On foot with nothing to shoot at, now and then a word on the radio (s:
## after standing this long, for this long, this often).
const RADIO_AFTER := 1.2
const RADIO_FOR := 3.2
const RADIO_EVERY := 9.0

## How many different officers each force has (bodies are cached per look).
const LOOKS := 6
const WALK := 1.9
const RUN := 5.4
const EYE := 1.6
## How long after an out before it can leave (s), and the most it stays.
## Hits to put an officer out: half a player's 8 (it's paintball, and a
## rampage should be fun). A head hit counts 2, so two to the head do it,
## and the Islander at 5 a second takes one out in under a second of hits.
const OUT_HITS := 4
## s: how long an officer takes to aim once it has a clear shot again,
## before the first pull (the marker comes up first, so you see it coming
## and can get the first shot off).
const DRAW_MIN := 0.7
const DRAW_MAX := 1.2
## s a hit puts it off its aim (and ends the burst).
const STAGGER := 0.45
## What it calls out bringing the marker up (now and then, not every time),
## and when a hit lands and it isn't out. docs/voice.md.
const CALLOUTS := [
	"Drop the marker!", "Paint! We've got paint!", "Put it down. I'm on a double.",
	"Don't make me do the form.", "Sir. Sir. Sir.", "I'm two years off my pension!",
	"Marker! Corner of... whatever this is.", "Not on my overtime.",
]
const FIP_CALLOUTS := [
	"Federal. Drop it.", "This is a federal matter now.", "We have jurisdiction. Somewhere.",
	"Stand down. That's an order. Probably.",
]
const HIT_LINES := [
	"That's a uniform!", "Ow! That's another form.", "My sergeant's going to see that.",
	"That's coming out of the budget.",
]
const EXIT_MIN := 9.0
const EXIT_MAX := 40.0

static var _shape: CapsuleShape3D

var force := "city"
var number := 0
var state := State.ON_FOOT
var model: HumanoidModel
var body_paint: BodyPaint
var marker: PaintMarker
## Where to go on foot (INF: stay), and whether to run there.
var goal := Vector3.INF
var running := true
## Who to shoot at (the player), or null.
var shoot_at: Node3D = null
## The miss, in radians (the spread of where it aims, on top of the
## marker's own): the FIP at level 3 and up aims well.
var aim_error := 0.03
## Shots a second when it has a clear shot.
var fire_rate := 3.0
## How far it'll shoot (m).
var shoot_range := 38.0
## Shots it puts beside you first, each time it gets a clear shot again.
var warning_shots := 2
## Shots in a burst (from, to), and s between bursts (from, to).
var burst := Vector2i(3, 4)
var burst_pause := Vector2(0.9, 1.4)
## The car it rides in (null on foot with no car).
var car: Car = null
var passenger := false
## True while the marker's up and it's firing.
var firing := false

var _ground := PhysicsRayQueryParameters3D.new()
var _sight := PhysicsRayQueryParameters3D.new()
var _speed := 0.0
var _move := Vector3.ZERO
var _aim_t := 0.0
var _trigger_t := 0.0
var _blocked := 0.0
var _side_step := 0.0
var _side_dir := 1.0
var _exit := {}
var _exit_t := 0.0
var _vest: Node3D
var _held_marker: MeshInstance3D
var _speech: Label3D
var _rng := RandomNumberGenerator.new()
var _sound: AudioStreamPlayer3D
var _seat_node: Node3D
var _los_check := 0.0
var _los_ok := false
var _draw_t := 0.0
var _drawing := false
var _seen_vel := Vector3.ZERO ## the target's motion as it's read, a beat behind
## s for the read of a person's motion to catch up (about two thirds of
## the way in this long): quicker at the higher levels.
var read_time := 0.45
var _warn_left := 0
var _burst_left := 0
var _callout_t := 0.0
var _speech_t := 0.0


func _init() -> void:
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if _shape == null:
		_shape = CapsuleShape3D.new()
		_shape.radius = 0.3
		_shape.height = 1.75
	var col := CollisionShape3D.new()
	col.shape = _shape
	col.position = Vector3.UP * 0.875
	add_child(col)
	_ground.collision_mask = Layers.GROUND
	_sight.collision_mask = Layers.SOLID | Layers.VEHICLES


func _ready() -> void:
	add_to_group("police")
	add_to_group(AimAssist.GROUP)
	add_to_group("officers")
	_rng.seed = hash(name) ^ get_instance_id()
	model = make_model(force, _rng.randi() % LOOKS)
	add_child(model)
	body_paint = BodyPaint.new()
	body_paint.name = "BodyPaint"
	body_paint.model = model
	body_paint.can_go_out = true
	body_paint.out_hits = OUT_HITS
	body_paint.went_out.connect(_on_out)
	add_child(body_paint)
	marker = PaintMarker.new()
	marker.name = "PaintMarker"
	marker.shooter = self
	add_child(marker)
	marker.fired.connect(func(_kick: float) -> void: model.recoil())
	_callout_t = _rng.randf_range(0.0, 4.0)
	_sound = AudioStreamPlayer3D.new()
	_sound.unit_size = 10.0
	add_child(_sound)
	# After the model's own pose each frame: the legs folded away leaning
	# out of a window, the marker held up when out.
	var post := _PostPose.new()
	post.officer = self
	add_child(post)


## An officer's body in one of the force's few looks, each built once and
## shared (by its mesh_cache_key).
static func make_model(which: String, look: int) -> HumanoidModel:
	var m := HumanoidModel.new()
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = hash("%s_%d" % [which, look])
	m.set_appearance(uniform(which, look_rng))
	m.mesh_cache_key = "officer_%s_%d" % [which, look]
	return m


## Builds every officer look's body (both forces), one a frame, under
## `parent` as the game starts, so the first officers out of a cruiser in a
## chase don't stop the game while their bodies are built (13-18 ms each).
static func warm_looks(parent: Node) -> void:
	for which: String in ["city", "fip"]:
		for look in LOOKS:
			await parent.get_tree().process_frame
			if not parent.is_inside_tree():
				return
			var m := make_model(which, look)
			m.visible = false
			parent.add_child(m)
			m.queue_free()


## What a city officer and an FIP officer wear (Outfit.UNIFORM_KINDS): a
## duty shirt under a vest carrier with POLICE across the back, a duty belt,
## the force's patch on both shoulders, a cap and boots. The city in a
## dark navy shirt, a black vest, a navy ball cap with POLICE on it and the
## green crest of its cars on the shoulders (Charlottetown's); the
## FIP after the RCMP: a navy shirt and vest, a forage cap with a gold band and a
## gold stripe down the trousers (the dress uniform for no reason is a
## parked idea).
static func uniform(which: String, rng: RandomNumberGenerator) -> Dictionary:
	var look := HumanoidModel.random_appearance(rng)
	if which == "city":
		look["outfit"] = {
			"hat": {"kind": "cap", "color": Color(0.06, 0.07, 0.13), "print": "police_back"},
			"top": {"kind": "duty", "force": "city", "color": Color(0.08, 0.09, 0.15), "trim": Color(0.04, 0.04, 0.045),
				"back": "police_back", "patch": "cps_patch"},
			"bottom": {"kind": "trousers", "color": Color(0.06, 0.07, 0.12)},
			"shoes": {"kind": "boots", "color": Color(0.04, 0.04, 0.045)},
		}
	else:
		look["outfit"] = {
			"hat": {"kind": "forage_cap", "color": Color(0.07, 0.09, 0.17), "trim": Color(0.92, 0.72, 0.18), "band": "plain"},
			"top": {"kind": "duty", "force": "fip", "color": Color(0.1, 0.12, 0.2), "trim": Color(0.06, 0.07, 0.12),
				"back": "fip_back", "patch": "fip_patch"},
			"bottom": {"kind": "trousers", "color": Color(0.06, 0.07, 0.13), "stripe": Color(0.92, 0.72, 0.18)},
			"shoes": {"kind": "boots", "color": Color(0.04, 0.04, 0.045)},
		}
	return look


# --- what the aim assist and the paint ask --------------------------------------------------

func aim_points() -> Array[Vector3]:
	if state == State.SEATED:
		return []
	return [global_position + Vector3.UP * 1.2, global_position + Vector3.UP * 1.55]


func is_out() -> bool:
	return body_paint != null and body_paint.out


func is_police() -> bool:
	return true


func take_paint_hit(value: int, shooter: Node, point: Vector3) -> void:
	if is_out():
		return
	body_paint.take_hit(value, shooter, point, PaintShots.colour_of(shooter))
	if is_out():
		return
	# Staggered: off its aim for a moment, and the burst is over.
	_draw_t = maxf(_draw_t, STAGGER)
	_trigger_t = maxf(_trigger_t, STAGGER)
	_burst_left = 0
	if _callout_t <= 0.0 and _rng.randf() < 0.35:
		_say(HIT_LINES[_rng.randi() % HIT_LINES.size()], 1.6)
		_callout_t = 6.0


func is_head_point(point: Vector3) -> bool:
	return body_paint.is_head_point(point)


## Where its eyes are.
func eye() -> Vector3:
	return global_position + Vector3.UP * EYE


## Which way it's facing, flat.
func facing() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


# --- seats ---------------------------------------------------------------------------------

## Sit in a car: the driver's seat, or the one beside it.
func sit_in(the_car: Car, as_passenger: bool) -> void:
	car = the_car
	passenger = as_passenger
	state = State.SEATED
	collision_layer = 0
	collision_mask = 0
	set_physics_process(true)
	if as_passenger:
		_seat_node = the_car.seat.get_parent().get_node_or_null("PassengerSeat")
		if _seat_node == null:
			_seat_node = Node3D.new()
			_seat_node.name = "PassengerSeat"
			_seat_node.position = Vector3(-the_car.seat.position.x, the_car.seat.position.y, the_car.seat.position.z)
			the_car.seat.get_parent().add_child(_seat_node)
	else:
		_seat_node = the_car.seat
	if get_parent() != _seat_node:
		if get_parent() != null:
			reparent(_seat_node, false)
		else:
			_seat_node.add_child(self)
	position = Vector3(0.0, -model.height / 1.75 * 0.93, 0.0) if model != null else Vector3(0, -0.87, 0)
	rotation = Vector3.ZERO
	if model != null:
		model.seated = true
		model.aim = 0.0
	reset_physics_interpolation()
	firing = false


## Lean out of the passenger window to paint (level 3: design.md), or back in.
func lean_out(on: bool) -> void:
	if not passenger or car == null or is_out():
		return
	if on and state == State.SEATED:
		state = State.LEANING
		model.seated = false
		# Out of the window from the waist: the chest over the sill.
		var sh := car.shape
		var belt := float(sh["cabin"]["belt"])
		var half_w := float(sh["width"]) * 0.5
		var sp: Array = sh["seat"]
		position = Vector3(half_w - absf(float(sp[0])) - 0.02, belt + 0.28 - float(sp[1]) - 1.2 * model.height / 1.75, 0.0)
		collision_layer = Layers.CHARACTERS
		reset_physics_interpolation()
	elif not on and state == State.LEANING:
		sit_in(car, true)


## Out of the car, onto the street beside its door.
func get_out() -> void:
	if car == null or state == State.ON_FOOT or state == State.OUT and get_parent() != _seat_node:
		return
	var world_parent := car.get_parent()
	var side := 1.0 if passenger else -1.0
	var spot := car.door_stand(side, 0.55)
	var yaw := car.global_basis.get_euler().y
	model.end_climb()
	var sat := model.global_transform
	reparent(world_parent, false)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), spot + Vector3.UP * 0.3)
	reset_physics_interpolation()
	model.seated = false
	model.task = ""
	model.climb_out(sat, car)
	if not is_out():
		state = State.ON_FOOT
		collision_layer = Layers.CHARACTERS
		collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	goal = Vector3.INF


## Back in its seat (it's next to the car).
func get_in() -> void:
	if car == null or is_out():
		return
	_climb_into_seat()


## Into its seat from where it stands, climbing in by the door.
func _climb_into_seat() -> void:
	var from := global_position
	var door := door_point()
	model.task = ""
	sit_in(car, passenger)
	model.climb_in(from, door)


## Where to stand to get in: beside its door.
func door_point() -> Vector3:
	if car == null:
		return global_position
	return car.door_stand(1.0 if passenger else -1.0, 0.5)


func move_to(p: Vector3, run := true) -> void:
	goal = p
	running = run


# --- each step ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_callout_t -= delta
	if _speech_t > 0.0:
		_speech_t -= delta
		if _speech_t <= 0.0 and _speech != null and state != State.OUT:
			_speech.text = ""
	match state:
		State.SEATED:
			marker.trigger = false
			return
		State.LEANING:
			_aim_and_fire(delta, true)
			model.set_motion(0.0)
			return
		State.OUT:
			_out_step(delta)
			return
	if model.climbing():
		# Out of the car first.
		marker.trigger = false
		firing = false
		model.aim = 0.0
		velocity = Vector3.ZERO
		return
	_walk(delta)
	_aim_and_fire(delta, false)
	# Stood about with nothing to shoot at: a word on the radio now and then.
	if not firing and _speed < 0.3 and goal == Vector3.INF:
		_idle_t += delta
	else:
		_idle_t = 0.0
	var on_radio := _idle_t > RADIO_AFTER and fmod(_idle_t - RADIO_AFTER, RADIO_EVERY) < RADIO_FOR
	model.task = "radio" if on_radio else ""


var _idle_t := 0.0


func _walk(delta: float) -> void:
	var want := Vector3.ZERO
	if goal != Vector3.INF:
		var to := goal - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.6:
			var sp := (RUN if running else WALK) * (0.65 if firing else 1.0)
			want = to / d * minf(sp, d * 2.0)
			if _side_step > 0.0:
				_side_step -= delta
				var side := Vector3(-want.z, 0, want.x).normalized() * _side_dir
				want = (want * 0.3 + side * sp).limit_length(sp)
	_move = _move.move_toward(want, 30.0 * delta)
	velocity = _move
	move_and_slide()
	var moved := get_real_velocity()
	moved.y = 0.0
	if want.length() > 0.5 and moved.length() < want.length() * 0.3:
		_blocked += delta
		if _blocked > 0.5 and _side_step <= 0.0:
			_side_step = 1.0
			_side_dir = -_side_dir if _rng.randf() < 0.5 else _side_dir
			_blocked = 0.0
	else:
		_blocked = maxf(0.0, _blocked - delta)
	_speed = moved.length()
	_follow_ground(delta)
	# Face the target when shooting, else the way it's going.
	var face := moved
	if firing and shoot_at != null and is_instance_valid(shoot_at):
		face = shoot_at.global_position - global_position
	face.y = 0.0
	if face.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), minf(1.0, 12.0 * delta))
	var local := global_basis.inverse() * moved
	model.set_motion(_speed, 0.0, 0.0, atan2(-local.x, -local.z) if firing and _speed > 0.1 else 0.0)


func _follow_ground(delta: float) -> void:
	# The ground's height looked up ten times a second (one or two rays), not
	# every step, and followed in between.
	_ground_check -= delta
	if _ground_check <= 0.0:
		_ground_check = 0.1
		_ground.from = global_position + Vector3.UP * 0.7
		_ground.to = global_position + Vector3.DOWN * 4.0
		var hit := get_world_3d().direct_space_state.intersect_ray(_ground)
		if hit.is_empty():
			_ground.from = global_position + Vector3.UP * 40.0
			hit = get_world_3d().direct_space_state.intersect_ray(_ground)
		_ground_h = float(hit["position"].y) if not hit.is_empty() else NAN
	if not is_nan(_ground_h):
		global_position.y = lerpf(global_position.y, _ground_h, 0.5)


var _ground_check := 0.0
var _ground_h := NAN


## The marker: up when there's someone to shoot in range and in sight,
## firing at its rate, aimed for the drop and the target's motion.
func _aim_and_fire(delta: float, from_car: bool) -> void:
	var target := shoot_at if shoot_at != null and is_instance_valid(shoot_at) else null
	var aim_p := Vector3.ZERO
	var can := false
	if target != null:
		if target is CharacterBody3D:
			_seen_vel = _seen_vel.lerp((target as CharacterBody3D).velocity, 1.0 - exp(-delta / maxf(read_time, 0.01)))
		aim_p = _aim_point(target)
		var d := eye().distance_to(aim_p)
		_los_check -= delta
		if _los_check <= 0.0:
			_los_check = 0.15
			_los_ok = d < shoot_range and _clear_to(aim_p, target)
		can = _los_ok and d < shoot_range
	firing = can
	_aim_t = move_toward(_aim_t, 1.0 if can else 0.0, delta / 0.35)
	model.aim = 1.0 if can else 0.0
	if can:
		var chest := global_position + Vector3.UP * model.height * 0.8
		var dd := aim_p - chest
		model.aim_pitch = atan2(dd.y, Vector2(dd.x, dd.z).length())
		if from_car:
			# Leaning out the window: turn the body to the target.
			var to := aim_p - global_position
			var local := car.global_basis.inverse() * to
			rotation.y = atan2(-local.x, -local.z) - 0.0
	# Lost the shot: next time, it takes a moment to draw a bead again, and
	# starts with the warning shots.
	if not can:
		_draw_t = _rng.randf_range(DRAW_MIN, DRAW_MAX)
		_warn_left = warning_shots
		_burst_left = 0
		_drawing = false
	elif _aim_t >= 1.0:
		if not _drawing:
			_drawing = true
			if _callout_t <= 0.0 and not from_car and _rng.randf() < 0.6:
				var lines: Array = FIP_CALLOUTS if force == "fip" else CALLOUTS
				_say(str(lines[_rng.randi() % lines.size()]), 1.8)
				_callout_t = 7.0
		_draw_t -= delta
	# Pull the trigger at its own rate (a pull a shot: crisp, not a hose),
	# in bursts with a breather between.
	_trigger_t -= delta
	var pull := false
	var warn := false
	if can and _aim_t >= 1.0 and _draw_t <= 0.0 and _trigger_t <= 0.0:
		if _burst_left <= 0:
			_burst_left = _rng.randi_range(burst.x, burst.y)
		pull = true
		warn = _warn_left > 0
		if warn:
			_warn_left -= 1
		_burst_left -= 1
		_trigger_t = 1.0 / fire_rate * _rng.randf_range(0.85, 1.15)
		if _burst_left <= 0:
			_trigger_t += _rng.randf_range(burst_pause.x, burst_pause.y)
	marker.trigger = pull
	var muzzle := PaintMarker.muzzle_of(model)
	var at := aim_p
	if warn:
		at = _warning_point(muzzle, aim_p)
	else:
		at += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * aim_error * muzzle.distance_to(aim_p)
	marker.step(delta, not is_out(), can, _aim_t, _speed, RUN, muzzle, at)


## A warning shot's mark: a metre or two to one side of the target and
## down by its feet, so it splats on the ground or the wall beside it.
func _warning_point(muzzle: Vector3, aim_p: Vector3) -> Vector3:
	var line := aim_p - muzzle
	line.y = 0.0
	var side := line.cross(Vector3.UP).normalized() if line.length_squared() > 0.01 else Vector3.RIGHT
	side *= (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(1.3, 2.2)
	return aim_p + side + Vector3.DOWN * _rng.randf_range(0.7, 1.2)


## Where to aim at the target: a person's chest, a car's windscreen; led by
## its motion over the flight time, and up for the drop.
func _aim_point(target: Node3D) -> Vector3:
	var p := target.global_position + Vector3.UP * 1.25
	var vel := Vector3.ZERO
	if target is Car:
		var c := target as Car
		var cab: Dictionary = c.shape.get("cabin", {})
		var zw := lerpf(float(cab.get("za", -0.8)), float(cab.get("zb", -0.2)), 0.5)
		var yw := lerpf(float(cab.get("belt", 1.0)), float(cab.get("roof", 1.4)), 0.4)
		p = c.global_transform * Vector3(0, yw, zw)
		vel = c.linear_velocity
	elif target is CharacterBody3D:
		# A person: led on how they've been moving lately, not this instant
		# (like anyone aiming), so a change of direction beats the lead.
		vel = _seen_vel
	var speed := float(marker.weapon.get("speed", 75.0))
	var t := eye().distance_to(p) / speed
	p += vel * t
	p.y += 0.5 * PaintWeapons.GRAVITY * t * t
	return p


func _clear_to(p: Vector3, target: Node3D) -> bool:
	_sight.from = eye()
	_sight.to = p
	var ex: Array[RID] = [get_rid()]
	if car != null:
		ex.append(car.get_rid())
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	var t_car: Variant = target.get("vehicle") if not (target is Car) else null
	if t_car is CollisionObject3D:
		ex.append((t_car as CollisionObject3D).get_rid())
	_sight.exclude = ex
	return get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()


# --- out ------------------------------------------------------------------------------------

func _on_out(by: Node) -> void:
	firing = false
	marker.trigger = false
	goal = Vector3.INF
	shoot_at = null
	remove_from_group(AimAssist.GROUP)
	# Balls pass through now.
	collision_layer = 0
	_play(PaintSounds.out_confirm())
	_put_on_vest()
	_exit = (FIP_EXIT if force != "city" and _rng.randf() < 0.5 else EXITS[_rng.randi() % EXITS.size()]).duplicate()
	if state == State.LEANING or state == State.SEATED:
		# Painted leaning out: back in the seat, hand up, done for the night.
		state = State.OUT
		sit_in(car, passenger)
		state = State.OUT
		model.seated = true
		_exit["do"] = "seat"
	else:
		state = State.OUT
	_exit_t = 0.0
	_say("I'm out!")
	went_out.emit(by)


func _put_on_vest() -> void:
	if _vest != null or model == null or model.skeleton == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "chest"
	model.skeleton.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = PoliceProps.vest_mesh()
	mi.scale = Vector3.ONE * (model.height / 1.75)
	mi.position.y = 0.0
	att.add_child(mi)
	_vest = att
	var hand := BoneAttachment3D.new()
	hand.bone_name = "hand.R"
	model.skeleton.add_child(hand)
	_held_marker = MeshInstance3D.new()
	_held_marker.mesh = MarkerModel.mesh()
	# The hand points up the arm when it's raised: the barrel to the sky.
	_held_marker.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -0.08, 0.0))
	hand.add_child(_held_marker)


func _out_step(delta: float) -> void:
	_exit_t += delta
	marker.trigger = false
	marker.step(delta, false, false, 0.0, 0.0, RUN, global_position, global_position)
	if get_parent() == _seat_node:
		if str(_exit.get("do", "")) == "car":
			# Back in the car for the paperwork: the notebook on the wheel.
			model.hands_up = 0.0
			if not model.climbing():
				model.task = str(_exit.get("task", ""))
		else:
			# In the seat with a hand up.
			model.hands_up = 1.0
		if _exit_t > EXIT_MIN and not model.climbing():
			done.emit()
		return
	var what := str(_exit.get("do", "stand"))
	if _exit_t > 3.0 and _exit.has("then") and _speech != null and _speech.text != str(_exit["then"]):
		_say(str(_exit["then"]))
	if _exit_t > 1.2 and _exit_t < 1.5:
		_say(str(_exit["say"]))
	match what:
		"car":
			if car != null and is_instance_valid(car) and car.driver == null and _exit_t > 2.0:
				goal = door_point()
				running = false
				var to := goal - global_position
				if Vector2(to.x, to.z).length() < 0.9:
					goal = Vector3.INF
					_climb_into_seat()
					state = State.OUT
					collision_layer = 0
					return
		"curb":
			if _exit_t > 5.0 and not model.seated:
				goal = Vector3.INF
				_speed = 0.0
				model.hands_up = 0.0
				model.seated = true
				model.position.y = -0.45
	# The marker comes down after a while, and the hands find something
	# to do.
	var settled := _exit_t > 6.0 or what == "car"
	if _held_marker != null:
		_held_marker.visible = not settled
	if settled and _speed < 0.3:
		model.task = str(_exit.get("task", ""))
	elif what == "curb" and model.seated:
		model.task = str(_exit.get("task", ""))
	if not model.seated:
		model.hands_up = 0.0 if settled else 1.0
		if goal != Vector3.INF:
			_walk(delta)
		else:
			model.set_motion(0.0)
			_follow_ground(delta)
	if _exit_t > EXIT_MAX:
		done.emit()


## True once it's been out long enough to be taken away (when nobody's
## looking: PoliceUnit checks that).
func exit_finished() -> bool:
	return state == State.OUT and _exit_t > EXIT_MIN


func _say(text: String, secs := 0.0) -> void:
	_speech_t = secs
	if _speech == null:
		_speech = Label3D.new()
		_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_speech.font_size = 48
		_speech.pixel_size = 0.004
		_speech.outline_size = 10
		_speech.modulate = Color(1.0, 0.95, 0.4)
		_speech.no_depth_test = false
		_speech.position = Vector3.UP * 2.15
		WorldLod.limit(_speech, 0.6)
		add_child(_speech)
	_speech.text = text


func _play(stream: AudioStream) -> void:
	if _sound == null or not _sound.is_inside_tree():
		return
	_sound.stream = stream
	_sound.play()


## Runs after the model's own pose each frame (a child added after it).
class _PostPose:
	extends Node
	var officer: Officer

	func _process(_delta: float) -> void:
		var m := officer.model
		if m == null or m.skeleton == null:
			return
		var sk := m.skeleton
		var tuck := officer.state == State.LEANING
		for leg: int in [BodyBuilder.UPPER_LEG_L, BodyBuilder.UPPER_LEG_R]:
			sk.set_bone_pose_scale(leg, Vector3.ONE * (0.001 if tuck else 1.0))

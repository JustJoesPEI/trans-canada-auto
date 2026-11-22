class_name Car
extends CharacterBody3D
## A drivable car with simple but honest physics.
##
## Each axle's tyres grip with a force that builds with how far they're
## slipping sideways and then levels off (no more grip than the road
## allows), so the car has weight, carves corners, and slides if pushed too
## hard or on the handbrake. The engine has a power curve; brakes, rolling
## resistance and air drag do the rest, so it coasts when you lift off and
## finds its own top speed. Steering lock shrinks with speed. Below a few
## km/h it blends to exact low-speed steering so parking is tidy.
##
## The body pitches and rolls with braking, acceleration and cornering and
## follows the ground under each wheel (curbs, kerb ramps), purely as looks:
## the physics stays flat, which keeps it predictable.
##
## Controls come from the driver (see PlayerController.enter_vehicle) through
## the input actions accelerate, brake_reverse, steer_left/right, handbrake.

signal crashed(impact_speed: float)

## Which car this is (an id in CarModels). Its shape and how it drives come
## from there; change the numbers in scripts/vehicles/car_models.gd.
@export var model_id := "civique"
@export var paint := Color(0.2, 0.36, 0.34) ## body colour

@export_group("Engine and brakes")
@export var mass := 1350.0 ## kg
@export var engine_force := 6400.0 ## N pulling force at low speed
@export var engine_power := 92000.0 ## W, limits pull at speed
@export var top_speed_kmh := 135.0
@export var reverse_speed_kmh := 22.0
@export var brake_force := 10500.0 ## N, about 0.8 g
@export var handbrake_force := 2200.0
@export var engine_braking := 650.0 ## N when coasting
@export var rolling_resistance := 15.0 ## N per m/s
@export var air_drag := 0.42 ## N per (m/s)²

@export_group("Grip and handling")
@export var grip := 1.0 ## tyre friction; 1.0 is dry pavement
@export var rear_grip_bias := 1.15 ## a little more grip at the back keeps it stable
@export var cornering_stiffness := 82000.0 ## N per radian of slip, front axle
@export var rear_stiffness_ratio := 1.3 ## rear axle bites harder, so the car settles into turns
@export var handbrake_rear_grip := 0.38 ## rear grip left with the handbrake on
@export var yaw_inertia := 2100.0 ## kg m²
@export var cg_to_front := 1.25 ## m, centre of gravity to front axle
@export var cg_to_rear := 1.45 ## m
@export var cg_height := 0.52 ## m; higher means more weight shifts under braking and power
@export_enum("fwd", "rwd", "awd") var drivetrain := "fwd" ## which wheels the engine drives
@export var spin_grip := 0.4 ## share of sideways grip a spinning or locked tyre keeps

@export_group("Steering")
@export var max_steer_degrees := 34.0 ## wheel angle at a crawl
@export var high_speed_steer_degrees := 5.0 ## wheel angle at 100 km/h
@export var steer_speed := 3.0 ## how fast the wheel turns in (full lock in 1/3 s)
@export var steer_return := 5.5 ## how fast it centres when let go

@export_group("Body motion (looks only)")
@export var pitch_per_g := 0.045 ## radians of nose up/down per g
@export var roll_per_g := 0.06 ## radians of lean per g
@export var body_settle_time := 0.16 ## seconds; larger is softer

## Who is driving (the player while seated), or null when parked.
var driver: Node3D = null
## Speed along the way the car points, m/s (negative when reversing).
var speed := 0.0
## 0..1 share of a fast cruise; the camera widens its view with it.
var run_amount := 0.0
var steer_angle := 0.0 ## radians, + is left
var yaw_rate := 0.0 ## radians per second, + is left
var plane_velocity := Vector2.ZERO ## (x, z) in m/s

var _steer_in := 0.0
var _throttle := 0.0
var _brake := 0.0
var _handbrake := false
var _accel := Vector2.ZERO # (forward, rightward) m/s², smoothed, for body motion
var _body: Node3D
var _body_pitch := 0.0
var _body_pitch_vel := 0.0
var _body_roll := 0.0
var _body_roll_vel := 0.0
var _wheels: Array[Node3D] = [] # steering pivots: FL, FR, RL, RR
var _wheel_meshes: Array[MeshInstance3D] = []
var _wheel_offsets: Array[Vector3] = []
var _wheel_y: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _spin := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ground := 0.0
var _ground_set := false ## height taken from the first physics step, after placement
var _slope := 0.0 ## radians, nose up positive: the road's grade under the car
var seat: Node3D
var shape: Dictionary ## this model's measurements (CarModels)
var wheel_radius := 0.31


## Full name for the HUD, e.g. "Hanaka Civique".
func display_name() -> String:
	return CarModels.full_name(model_id)


## Load this model's driving numbers from CarModels.
func _apply_model() -> void:
	var m := CarModels.get_model(model_id)
	for key: String in (m["drive"] as Dictionary):
		set(key, m["drive"][key])
	shape = m["shape"]
	wheel_radius = float(shape["wheel_radius"])


func _ready() -> void:
	_apply_model()
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Layers.VEHICLES
	collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEHICLES
	_ray.collision_mask = Layers.GROUND
	var box := BoxShape3D.new()
	var height: float = self.shape["height"]
	box.size = Vector3(float(self.shape["width"]) - 0.02, height * 0.72, float(self.shape["length"]) - 0.05)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position.y = height * 0.58
	add_child(cs)

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = CarBuilder.new(shape, paint).make_body()
	_body.add_child(mi)
	seat = Node3D.new()
	seat.name = "DriverSeat"
	var sp: Array = shape["seat"]
	seat.position = Vector3(sp[0], sp[1], sp[2]) # driver sits on the left
	_body.add_child(seat)

	for z: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for s: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(float(shape["track_half"]) * s, wheel_radius, z)
			add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = CarBuilder.wheel_mesh(wheel_radius, float(shape["wheel_width"]))
			w.scale = Vector3(s, 1.0, 1.0) # mirror so the hubcap faces out
			pivot.add_child(w)
			_wheels.append(pivot)
			_wheel_meshes.append(w)
			_wheel_offsets.append(pivot.position)
	_ground_set = false


## Where the driver's door is, for getting in (world space).
func door_point() -> Vector3:
	return global_transform * Vector3(-(float(shape["width"]) * 0.5 + 0.15), 0.0, float(shape["seat"][2]))


## A clear spot beside the car to step out to, driver's side first.
func exit_transform() -> Transform3D:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	q.shape = capsule
	q.collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var sx := float(shape["width"]) * 0.5 + 0.5
	var sz := float(shape["seat"][2])
	var ez := float(shape["length"]) * 0.5 + 0.9
	for local: Vector3 in [Vector3(-sx, 0, sz), Vector3(sx, 0, sz), Vector3(-sx, 0, sz + 1.3), Vector3(sx, 0, sz + 1.3), Vector3(0, 0, -ez), Vector3(0, 0, ez)]:
		var p := global_transform * local
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
		if space.intersect_shape(q, 1).is_empty():
			return Transform3D(Basis(Vector3.UP, rotation.y), p + Vector3.UP * 0.3)
	return Transform3D(Basis(Vector3.UP, rotation.y), global_transform * Vector3(-sx, 0, sz) + Vector3.UP * 2.0)


func _physics_process(delta: float) -> void:
	_read_controls(delta)
	var steps := 2
	var h := delta / float(steps)
	var prev := plane_velocity
	var fwd := Vector2(-sin(rotation.y), -cos(rotation.y))
	for i in steps:
		_step(h)
	# Smoothed acceleration in the car's own frame, for the body motion.
	var acc := (plane_velocity - prev) / delta
	var right := Vector2(-fwd.y, fwd.x)
	_accel = _accel.lerp(Vector2(acc.dot(fwd), acc.dot(right)), 1.0 - exp(-10.0 * delta))

	velocity = Vector3(plane_velocity.x, 0.0, plane_velocity.y)
	var before := plane_velocity
	move_and_slide()
	if get_slide_collision_count() > 0:
		var real := get_real_velocity()
		plane_velocity = Vector2(real.x, real.z) * 0.9
		var impact := (before - plane_velocity).length()
		yaw_rate *= 0.5
		if impact > 2.0:
			crashed.emit(impact)
	speed = plane_velocity.dot(Vector2(-sin(rotation.y), -cos(rotation.y)))
	run_amount = clampf(absf(speed) / 30.0, 0.0, 1.0)
	_follow_ground(delta)
	_animate(delta)


func _read_controls(delta: float) -> void:
	var steer_target := 0.0
	var accel := 0.0
	var brake_in := 0.0
	_handbrake = false
	if driver != null:
		accel = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake_reverse")
		steer_target = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		_handbrake = Input.is_action_pressed("handbrake")
	# Steering wheel: turns in at steer_speed, centres faster.
	var rate := steer_speed if absf(steer_target) > absf(_steer_in) and signf(steer_target) == signf(_steer_in) or _steer_in == 0.0 else steer_return
	_steer_in = move_toward(_steer_in, steer_target, rate * delta)
	var kmh := absf(speed) * 3.6
	var lock := deg_to_rad(lerpf(max_steer_degrees, high_speed_steer_degrees, smoothstep(0.0, 100.0, kmh)))
	steer_angle = _steer_in * lock

	# W/RT drives forward and S/LT brakes; once stopped, S/LT reverses.
	_throttle = 0.0
	_brake = 0.0
	if speed > 0.6:
		_throttle = accel
		_brake = brake_in
	elif speed < -0.6:
		_throttle = -brake_in
		_brake = accel
	elif accel > 0.05:
		_throttle = accel
	elif brake_in > 0.05:
		_throttle = -brake_in
	if driver == null:
		_brake = 1.0 # parked: handbrake on
		_handbrake = true


func _step(h: float) -> void:
	var yaw := rotation.y
	var f := Vector2(-sin(yaw), -cos(yaw)) # forward, in (x, z)
	var r := Vector2(-f.y, f.x) # right
	var vx := plane_velocity.dot(f)
	var wheelbase := cg_to_front + cg_to_rear
	var g := 9.81

	# --- engine, brakes and resistance -------------------------------------------
	var drive := 0.0
	if _throttle != 0.0:
		drive = minf(engine_force, engine_power / maxf(absf(vx), 1.0)) * _throttle
		if _throttle > 0.0:
			drive *= clampf((top_speed_kmh / 3.6 - vx) / 3.0, 0.0, 1.0)
		else:
			drive *= clampf((reverse_speed_kmh / 3.6 + vx) / 2.0, 0.0, 1.0)
	else:
		drive = -signf(vx) * engine_braking * minf(1.0, absf(vx))
	var stop_dir := -signf(vx)
	var stop := _brake * brake_force * minf(1.0, absf(vx) * 2.0)
	var resist := -rolling_resistance * vx - air_drag * vx * absf(vx)
	# The hill: gravity along the slope pulls the car back uphill and on downhill.
	resist -= mass * g * sin(_slope)

	# --- weight on each axle: shifts forward under braking, back under power ---
	var shift := mass * _accel.x * cg_height / wheelbase
	var load_front := maxf(mass * g * 0.15, mass * g * cg_to_rear / wheelbase - shift)
	var load_rear := maxf(mass * g * 0.15, mass * g * cg_to_front / wheelbase + shift)
	var limit_front := grip * load_front
	var limit_rear := grip * rear_grip_bias * load_rear * (handbrake_rear_grip if _handbrake else 1.0)

	# --- each axle's push along the road: its share of engine and brakes ---------
	var front_share := 1.0 if drivetrain == "fwd" else (0.4 if drivetrain == "awd" else 0.0)
	var fx_front := drive * front_share + stop_dir * stop * 0.65
	var fx_rear := drive * (1.0 - front_share) + stop_dir * stop * 0.35
	if _handbrake:
		fx_rear += stop_dir * handbrake_force * minf(1.0, absf(vx) * 2.0)
	# A tyre can't push harder than its grip: beyond that it spins or locks.
	fx_front = clampf(fx_front, -limit_front, limit_front)
	fx_rear = clampf(fx_rear, -limit_rear, limit_rear)
	# ...and what it spends pushing isn't there for cornering. This is what
	# lets a rear-drive car step out under power and hold a drift.
	# A spinning or locked tyre still keeps some sideways grip, which is what
	# makes a slide catchable with opposite lock.
	var side_front := sqrt(maxf(limit_front * limit_front - fx_front * fx_front, pow(spin_grip * limit_front, 2.0)))
	var side_rear := sqrt(maxf(limit_rear * limit_rear - fx_rear * fx_rear, pow(spin_grip * limit_rear, 2.0)))

	# --- across the car: tyre grip at each axle ----------------------------------
	var s := steer_angle
	var fw := f * cos(s) - r * sin(s) # front wheel heading (steered left for s > 0)
	var rw := r * cos(s) + f * sin(s) # front wheel's right
	var v_front := plane_velocity - r * yaw_rate * cg_to_front
	var v_rear := plane_velocity + r * yaw_rate * cg_to_rear
	var slip_front := atan2(v_front.dot(rw), maxf(absf(v_front.dot(fw)), 1.5))
	var slip_rear := atan2(v_rear.dot(r), maxf(absf(v_rear.dot(f)), 1.5))
	# Tyre side forces only make sense rolling; at a crawl the exact steering
	# below takes over, so fade them out rather than let them act as a brake.
	var rolling := smoothstep(0.6, 4.0, plane_velocity.length())
	var fy_front := -side_front * tanh(cornering_stiffness * slip_front / side_front) * rolling
	var fy_rear := -side_rear * tanh(cornering_stiffness * rear_stiffness_ratio * slip_rear / side_rear) * rolling

	# Front tyres push along where they point; the rear along the car.
	var front_force := fw * fx_front + rw * fy_front
	var rear_force := f * fx_rear + r * fy_rear
	var force := front_force + rear_force + f * resist

	# Turning effect about the centre of gravity
	# (y component of p x F; + turns left, same as rotation.y).
	var p_front := f * cg_to_front
	var p_rear := -f * cg_to_rear
	var torque := (p_front.y * front_force.x - p_front.x * front_force.y) + (p_rear.y * rear_force.x - p_rear.x * rear_force.y)

	plane_velocity += force / mass * h
	yaw_rate += torque / yaw_inertia * h

	# --- low speeds: blend to exact steering geometry, no sliding ----------------
	var spd := plane_velocity.length()
	var dynamic := smoothstep(0.6, 4.0, spd)
	var vx2 := plane_velocity.dot(f)
	var vy2 := plane_velocity.dot(r)
	var kinematic_yaw := vx2 * tan(s) / wheelbase
	yaw_rate = lerpf(kinematic_yaw, yaw_rate, dynamic)
	plane_velocity = f * vx2 + r * vy2 * dynamic
	# Stopped with the brake held: stay put.
	if _brake > 0.1 and absf(vx2) < 0.25 and _throttle == 0.0:
		plane_velocity = Vector2.ZERO
		yaw_rate = 0.0
	rotation.y += yaw_rate * h


func _follow_ground(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var heights: Array[float] = []
	for i in 4:
		var p := global_transform * Vector3(_wheel_offsets[i].x, 0.0, _wheel_offsets[i].z)
		_ray.from = p + Vector3.UP * 2.5
		_ray.to = p + Vector3.DOWN * 4.0
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			# Lost the road (placed under a hill?): look from well above.
			_ray.from = p + Vector3.UP * 60.0
			hit = space.intersect_ray(_ray)
		heights.append(float(hit["position"].y) if not hit.is_empty() else _ground)
	var avg := (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25
	if not _ground_set:
		_ground = avg
		_ground_set = true
	# The whole car rides the average height; each wheel finds its own.
	_ground = lerpf(_ground, avg, 1.0 - exp(-14.0 * delta))
	global_position.y = _ground
	for i in 4:
		_wheel_y[i] = lerpf(_wheel_y[i], clampf(heights[i] - avg, -0.12, 0.14), 1.0 - exp(-25.0 * delta))
	# Ground slope under the car feeds the body's pitch and roll.
	var front := (heights[0] + heights[1]) * 0.5
	var rear := (heights[2] + heights[3]) * 0.5
	var left := (heights[0] + heights[2]) * 0.5
	var right := (heights[1] + heights[3]) * 0.5
	var ground_pitch := atan2(front - rear, float(shape["rear_axle"]) - float(shape["front_axle"]))
	_slope = lerpf(_slope, ground_pitch, 1.0 - exp(-10.0 * delta))
	var ground_roll := atan2(right - left, float(shape["track_half"]) * 2.0)
	var g := 9.81
	var pitch_goal := ground_pitch + clampf(_accel.x / g, -1.2, 1.2) * pitch_per_g
	var roll_goal := ground_roll + clampf(_accel.y / g, -1.2, 1.2) * roll_per_g
	var sp := CameraRig._spring(_body_pitch, _body_pitch_vel, pitch_goal, body_settle_time, delta)
	_body_pitch = sp[0]
	_body_pitch_vel = sp[1]
	var sr := CameraRig._spring(_body_roll, _body_roll_vel, roll_goal, body_settle_time, delta)
	_body_roll = sr[0]
	_body_roll_vel = sr[1]


func _animate(delta: float) -> void:
	_body.rotation = Vector3(_body_pitch, 0.0, _body_roll)
	_body.position.y = (_wheel_y[0] + _wheel_y[1] + _wheel_y[2] + _wheel_y[3]) * 0.25
	_spin -= speed * delta / wheel_radius
	for i in 4:
		var w := _wheels[i]
		w.position = _wheel_offsets[i] + Vector3(0.0, _wheel_y[i], 0.0)
		w.rotation.y = steer_angle if i < 2 else 0.0
		_wheel_meshes[i].rotation.x = _spin

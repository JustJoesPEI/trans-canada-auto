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

@export var paint := Color(0.2, 0.36, 0.34) ## body colour

@export_group("Engine and brakes")
@export var mass := 1350.0 ## kg
@export var engine_force := 6400.0 ## N pulling force at low speed
@export var engine_power := 92000.0 ## W, limits pull at speed
@export var top_speed_kmh := 135.0
@export var reverse_speed_kmh := 22.0
@export var brake_force := 10500.0 ## N, about 0.8 g
@export var handbrake_force := 4000.0
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
var seat: Node3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Layers.VEHICLES
	collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEHICLES
	_ray.collision_mask = Layers.GROUND
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.78, 1.0, CarBuilder.LENGTH - 0.05)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.78
	add_child(cs)

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = CarBuilder.new(paint).make_body()
	_body.add_child(mi)
	seat = Node3D.new()
	seat.name = "DriverSeat"
	seat.position = Vector3(-0.38, 0.55, 0.18) # driver sits on the left
	_body.add_child(seat)

	for z: float in [CarBuilder.FRONT_AXLE_Z, CarBuilder.REAR_AXLE_Z]:
		for s: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(CarBuilder.TRACK_HALF * s, CarBuilder.WHEEL_RADIUS, z)
			add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = CarBuilder.wheel_mesh()
			w.scale = Vector3(s, 1.0, 1.0) # mirror so the hubcap faces out
			pivot.add_child(w)
			_wheels.append(pivot)
			_wheel_meshes.append(w)
			_wheel_offsets.append(pivot.position)
	_ground = global_position.y


## Where the driver's door is, for getting in (world space).
func door_point() -> Vector3:
	return global_transform * Vector3(-1.05, 0.0, -0.1)


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
	for local: Vector3 in [Vector3(-1.4, 0, -0.1), Vector3(1.4, 0, -0.1), Vector3(-1.4, 0, 1.2), Vector3(1.4, 0, 1.2), Vector3(0, 0, -3.3), Vector3(0, 0, 3.3)]:
		var p := global_transform * local
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
		if space.intersect_shape(q, 1).is_empty():
			return Transform3D(Basis(Vector3.UP, rotation.y), p + Vector3.UP * 0.3)
	return Transform3D(Basis(Vector3.UP, rotation.y), global_transform * Vector3(-1.4, 0, -0.1) + Vector3.UP * 1.6)


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

	# --- along the car: engine, brakes, resistance -------------------------------
	var fx := 0.0
	if _throttle != 0.0:
		var pull := minf(engine_force, engine_power / maxf(absf(vx), 1.0)) * _throttle
		if _throttle > 0.0:
			pull *= clampf((top_speed_kmh / 3.6 - vx) / 3.0, 0.0, 1.0)
		else:
			pull *= clampf((reverse_speed_kmh / 3.6 + vx) / 2.0, 0.0, 1.0)
		fx += pull
	else:
		fx -= signf(vx) * engine_braking * minf(1.0, absf(vx))
	var stopping := _brake * brake_force + (handbrake_force if _handbrake else 0.0)
	fx -= signf(vx) * stopping * minf(1.0, absf(vx) * 2.0)
	fx -= rolling_resistance * vx + air_drag * vx * absf(vx)

	# --- across the car: tyre grip at each axle ----------------------------------
	var s := steer_angle
	var fw := f * cos(s) - r * sin(s) # front wheel heading (steered left for s > 0)
	var rw := r * cos(s) + f * sin(s) # front wheel's right
	var v_front := plane_velocity - r * yaw_rate * cg_to_front
	var v_rear := plane_velocity + r * yaw_rate * cg_to_rear
	var load_front := mass * g * cg_to_rear / wheelbase
	var load_rear := mass * g * cg_to_front / wheelbase
	var limit_front := grip * load_front
	var limit_rear := grip * rear_grip_bias * load_rear * (handbrake_rear_grip if _handbrake else 1.0)
	var slip_front := atan2(v_front.dot(rw), maxf(absf(v_front.dot(fw)), 1.5))
	var slip_rear := atan2(v_rear.dot(r), maxf(absf(v_rear.dot(f)), 1.5))
	# Tyre side forces only make sense rolling; at a crawl the exact steering
	# below takes over, so fade them out rather than let them act as a brake.
	var rolling := smoothstep(0.6, 4.0, plane_velocity.length())
	var fy_front := -limit_front * tanh(cornering_stiffness * slip_front / limit_front) * rolling
	var fy_rear := -limit_rear * tanh(cornering_stiffness * rear_stiffness_ratio * slip_rear / limit_rear) * rolling
	var force := f * fx + rw * fy_front + r * fy_rear

	# Turning effect of the side forces about the centre of gravity
	# (y component of p x F; + turns left, same as rotation.y).
	var p_front := f * cg_to_front
	var p_rear := -f * cg_to_rear
	var front_force := rw * fy_front
	var rear_force := r * fy_rear
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
		_ray.from = p + Vector3.UP * 1.2
		_ray.to = p + Vector3.DOWN * 3.0
		var hit := space.intersect_ray(_ray)
		heights.append(float(hit["position"].y) if not hit.is_empty() else _ground)
	var avg := (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25
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
	var ground_pitch := atan2(front - rear, CarBuilder.REAR_AXLE_Z - CarBuilder.FRONT_AXLE_Z)
	var ground_roll := atan2(right - left, CarBuilder.TRACK_HALF * 2.0)
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
	_spin -= speed * delta / CarBuilder.WHEEL_RADIUS
	for i in 4:
		var w := _wheels[i]
		w.position = _wheel_offsets[i] + Vector3(0.0, _wheel_y[i], 0.0)
		w.rotation.y = steer_angle if i < 2 else 0.0
		_wheel_meshes[i].rotation.x = _spin

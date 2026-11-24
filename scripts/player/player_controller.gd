class_name PlayerController
extends CharacterBody3D
## The player on foot: walk, run, turn, bump into things.
##
## Movement is relative to the camera, so "forward" is always into the
## screen. Controls are tight, for chases and paintball fights: you move
## the way you push straight away (no turning circle, no slowing to turn
## round), starts and stops take a few hundredths of a second, and the body
## snaps round to face the way you're going. Speed still eases in over a
## few frames, so the stride never pops. Physics interpolation (Project
## Settings) keeps it smooth on screens faster than the 60 Hz physics.
##
## Height comes from a downward ray against the GROUND layer instead of floor
## physics, so curbs are stepped up smoothly and never catch the capsule.
## Walls, poles and cars are on SOLID and block normally.

@export_group("Speeds (m/s)")
@export var stroll_speed := 1.0 ## stick barely tilted
@export var walk_speed := 1.9 ## a brisk walk, keyboard or full stick
@export var run_speed := 5.8 ## hold Run
@export_group("Feel")
@export var accel := 55.0 ## m/s² speeding up or changing direction
@export var decel := 70.0 ## m/s² stopping when you let go
@export var turn_time := 0.045 ## seconds for the body to swing round to the way you're moving
@export var gravity := 20.0
@export var step_height := 0.4 ## tallest step the player walks straight up

## Set by main.gd. Movement uses its yaw.
var camera_rig: CameraRig
## When false the player ignores input (menus, sitting in a car).
var input_enabled := true
## Current ground speed (m/s).
var speed := 0.0
## 0..1, how much of a run this is (the camera widens its view with it).
var run_amount := 0.0

## The car being driven, or null on foot.
var vehicle: Car = null

@onready var model: HumanoidModel = $Model

var _fall_speed := 0.0
var _ground_query: PhysicsRayQueryParameters3D
var _move := Vector3.ZERO ## planar velocity we're trying to make
var _yaw_vel := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_ground_query = PhysicsRayQueryParameters3D.new()
	_ground_query.collision_mask = Layers.GROUND


func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	var running := false
	if input_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var yaw := camera_rig.yaw if camera_rig != null else rotation.y
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		wish = right * input.x - forward * input.y # input.y is negative for forward
		running = Input.is_action_pressed("run")

	var amount := minf(1.0, wish.length())
	var target_speed := 0.0
	if amount > 0.05:
		# A light touch on the stick strolls; full tilt walks; Run runs.
		target_speed = lerpf(stroll_speed, walk_speed, smoothstep(0.2, 0.85, amount))
		if running:
			target_speed = lerpf(target_speed, run_speed, amount)
	var goal: Vector3 = wish.normalized() * target_speed if amount > 0.05 else Vector3.ZERO

	# Head straight for the wanted velocity at a fixed rate: changes of
	# direction cut across instead of curving round, and a reversal at a run
	# goes through a stop in about a tenth of a second.
	var rate := accel if goal.length_squared() > 0.0001 else decel
	_move = _move.move_toward(goal, rate * delta)

	# Face the way we're pushing (or still sliding, when stopping).
	var old_yaw := rotation.y
	var face := goal if goal.length_squared() > 0.0001 else _move
	if face.length_squared() > 0.0001:
		var yr := Smooth.spring_angle(rotation.y, _yaw_vel, atan2(-face.x, -face.z), turn_time, delta)
		rotation.y = yr[0]
		_yaw_vel = yr[1]
	else:
		_yaw_vel = 0.0

	velocity = _move
	move_and_slide()
	_follow_ground(delta)

	# Against a wall, keep only what we actually managed, so the legs don't
	# pump on the spot and a reversal off a wall starts from rest.
	var moved := get_real_velocity()
	moved.y = 0.0
	if get_slide_collision_count() > 0 and moved.length() < _move.length():
		_move = moved

	var old_speed := speed
	speed = moved.length()
	run_amount = clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0)
	var turn := angle_difference(old_yaw, rotation.y) / maxf(delta, 0.0001)
	model.set_motion(speed, (speed - old_speed) / maxf(delta, 0.0001), turn)


func _follow_ground(delta: float) -> void:
	_ground_query.from = global_position + Vector3.UP * (step_height + 0.3)
	_ground_query.to = global_position + Vector3.DOWN * 5.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty():
		# Nothing below within reach: maybe we were put under the ground (a
		# teleport onto a hill). Look from well above and stand on it.
		_ground_query.from = global_position + Vector3.UP * 60.0
		var far := get_world_3d().direct_space_state.intersect_ray(_ground_query)
		if not far.is_empty() and float(far["position"].y) > global_position.y:
			global_position.y = float(far["position"].y)
			_fall_speed = 0.0
			return
		_fall(delta, -INF)
		return
	var ground_y: float = hit["position"].y
	if global_position.y <= ground_y + 0.01:
		# On the ground or at a step up (a curb): rise quickly but not instantly.
		global_position.y = lerpf(global_position.y, ground_y, minf(1.0, 25.0 * delta))
		_fall_speed = 0.0
	else:
		_fall(delta, ground_y)


func _fall(delta: float, floor_y: float) -> void:
	_fall_speed += gravity * delta
	global_position.y = maxf(floor_y, global_position.y - _fall_speed * delta)
	if global_position.y == floor_y:
		_fall_speed = 0.0


## Put the player somewhere (spawn, getting out of a car) and settle the camera.
func place(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	speed = 0.0
	_move = Vector3.ZERO
	_yaw_vel = 0.0
	_fall_speed = 0.0
	reset_physics_interpolation()


# --- cars -------------------------------------------------------------------------------------

## Sit in the driver's seat and take the wheel.
func enter_vehicle(car: Car) -> void:
	vehicle = car
	input_enabled = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	speed = 0.0
	run_amount = 0.0
	reparent(car.seat, false)
	# The seat node marks the hip joint; the model's origin is at the feet.
	position = Vector3(0.0, -model.height / 1.75 * 0.93, 0.0)
	rotation = Vector3.ZERO
	reset_physics_interpolation()
	model.seated = true
	car.driver = self


## Step out on the driver's side (or wherever there's room).
func exit_vehicle(world_parent: Node) -> void:
	if vehicle == null:
		return
	var car := vehicle
	var spot := car.exit_transform()
	car.driver = null
	vehicle = null
	reparent(world_parent, false)
	model.seated = false
	model.seated_steer = 0.0
	model.seated_grips = []
	model.seated_feet = []
	model.hide_head = false
	place(spot)
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	set_physics_process(true)
	input_enabled = true


func _process(_delta: float) -> void:
	if vehicle != null:
		model.seated_steer = vehicle.steer_angle / deg_to_rad(vehicle.max_steer_degrees)
		# Hands on the steering wheel and feet on the pedals, wherever this
		# car has them.
		var to_model := model.global_transform.affine_inverse() * vehicle.global_transform
		var grips: Array = []
		for p: Vector3 in vehicle.steering_grips():
			grips.append(to_model * p)
		model.seated_grips = grips
		var feet: Array = []
		for p: Vector3 in vehicle.pedal_points():
			feet.append(to_model * p)
		model.seated_feet = feet

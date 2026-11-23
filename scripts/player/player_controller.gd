class_name PlayerController
extends CharacterBody3D
## The player on foot: stroll, walk, run, turn, bump into things.
##
## Movement is relative to the camera, so "forward" is always into the
## screen. The person turns toward where you push and moves the way they
## face, so walking curves naturally and a run carves a wider turn; a sharp
## reversal at speed slows down first instead of snapping round.
##
## Speed and heading glide on critically damped springs, so starts, stops
## and turns ease in and out with no hard edges, and keyboard direction
## changes are softened very slightly. Physics interpolation (Project
## Settings) keeps it smooth on screens faster than the 60 Hz physics.
##
## Height comes from a downward ray against the GROUND layer instead of floor
## physics, so curbs are stepped up smoothly and never catch the capsule.
## Walls, poles and cars are on SOLID and block normally.

@export_group("Speeds (m/s)")
@export var stroll_speed := 0.9 ## stick barely tilted
@export var walk_speed := 1.7 ## a brisk walk, keyboard or full stick
@export var run_speed := 5.4 ## hold Run
@export_group("Feel")
@export var start_time := 0.12 ## seconds to ease up to speed
@export var stop_time := 0.14 ## seconds to ease to a stop
@export var turn_time_walk := 0.09 ## seconds to swing round to a new heading at a walk
@export var turn_time_run := 0.2 ## same at a full run: wider, steadier turns
@export var input_smoothing := 0.05 ## seconds; softens keyboard direction snaps
@export var reverse_brake_angle := 2.3 ## radians; sharper turns than this at a run brake first
@export var gravity := 20.0
@export var step_height := 0.4 ## tallest step the player walks straight up

## Set by main.gd. Movement uses its yaw.
var camera_rig: CameraRig
## When false the player ignores input (menus, sitting in a car).
var input_enabled := true
## Current ground speed along the facing direction (m/s).
var speed := 0.0
## 0..1, how much of a run this is (the camera widens its view with it).
var run_amount := 0.0

## The car being driven, or null on foot.
var vehicle: Car = null

@onready var model: HumanoidModel = $Model

var _fall_speed := 0.0
var _ground_query: PhysicsRayQueryParameters3D
var _wish := Vector3.ZERO
var _wish_vel := Vector3.ZERO
var _speed_vel := 0.0
var _yaw_vel := 0.0
var _wall_limit := 100.0 ## m/s we can actually manage against a wall


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

	# Soften digital (keyboard) direction changes a touch; sticks are already smooth.
	var ws := Smooth.spring3(_wish, _wish_vel, wish, input_smoothing, delta)
	_wish = ws[0]
	_wish_vel = ws[1]

	var amount := minf(1.0, _wish.length())
	var target_speed := 0.0
	if amount > 0.05:
		# A light touch on the stick strolls; full tilt walks; Run runs.
		target_speed = lerpf(stroll_speed, walk_speed, smoothstep(0.2, 0.85, amount))
		if running:
			target_speed = lerpf(target_speed, run_speed, amount)

	var old_yaw := rotation.y
	var run_t := clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0)
	if amount > 0.05:
		var target_yaw := atan2(-_wish.x, -_wish.z)
		var diff := absf(angle_difference(rotation.y, target_yaw))
		var planting := diff > reverse_brake_angle and speed > walk_speed * 0.8
		if planting:
			# Reversing at speed: plant and slow down first, then come round,
			# instead of whipping round while still moving fast.
			target_speed = 0.0
			target_yaw = rotation.y
		# Don't stride off sideways while still turning to face the way.
		if diff > 1.2 and speed < walk_speed:
			target_speed *= 0.35
		# Big turns take a little longer than small corrections, like a pivot.
		var turn_time := lerpf(turn_time_walk, turn_time_run, run_t) * (1.0 + 1.2 * angle_diff_frac(rotation.y, target_yaw))
		var yr := Smooth.spring_angle(rotation.y, _yaw_vel, target_yaw, turn_time, delta)
		rotation.y = yr[0]
		_yaw_vel = yr[1]
	else:
		_yaw_vel = lerpf(_yaw_vel, 0.0, 1.0 - exp(-12.0 * delta))
		rotation.y += _yaw_vel * delta

	target_speed = minf(target_speed, _wall_limit)
	var old_speed := speed
	var sp := Smooth.spring(speed, _speed_vel, target_speed, start_time if target_speed > speed else stop_time, delta)
	speed = maxf(0.0, sp[0])
	_speed_vel = sp[1]

	var facing := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	velocity = facing * speed
	move_and_slide()
	_follow_ground(delta)

	# Walking into a wall: the stride eases down to what we actually manage,
	# so the legs don't pump on the spot and grazing a wall doesn't stutter.
	var moved := get_real_velocity()
	moved.y = 0.0
	# The speed spring then settles on that limit next step instead of
	# fighting the wall every frame.
	if get_slide_collision_count() > 0:
		_wall_limit = lerpf(minf(_wall_limit, run_speed), moved.length() + 0.25, 1.0 - exp(-12.0 * delta))
	else:
		_wall_limit = minf(run_speed * 2.0, _wall_limit + 6.0 * delta)


	run_amount = clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0)
	var turn := angle_difference(old_yaw, rotation.y) / maxf(delta, 0.0001)
	model.set_motion(moved.length(), (speed - old_speed) / maxf(delta, 0.0001), turn)


## How big a turn is, 0 (none) to 1 (right about).
static func angle_diff_frac(from: float, to: float) -> float:
	return absf(angle_difference(from, to)) / PI


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
	_speed_vel = 0.0
	_yaw_vel = 0.0
	_wish = Vector3.ZERO
	_wish_vel = Vector3.ZERO
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
	place(spot)
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	set_physics_process(true)
	input_enabled = true


func _process(_delta: float) -> void:
	if vehicle != null:
		model.seated_steer = vehicle.steer_angle / deg_to_rad(vehicle.max_steer_degrees)

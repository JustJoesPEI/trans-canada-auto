class_name PlayerController
extends CharacterBody3D
## The player on foot: stroll, walk, run, turn, bump into things.
##
## Movement is relative to the camera, so "forward" is always into the
## screen. The person turns toward where you push and moves the way they
## face, so walking curves naturally and a run carves a wider turn; a sharp
## reversal at speed slows down first instead of snapping round.
##
## Height comes from a downward ray against the GROUND layer instead of floor
## physics, so curbs are stepped up smoothly and never catch the capsule.
## Walls, poles and cars are on SOLID and block normally.

@export_group("Speeds (m/s)")
@export var stroll_speed := 0.9 ## stick barely tilted
@export var walk_speed := 1.7 ## a brisk walk, keyboard or full stick
@export var run_speed := 5.4 ## hold Run
@export_group("Feel")
@export var acceleration := 9.0 ## speeding up, m/s per second
@export var deceleration := 13.0 ## slowing down, m/s per second
@export var turn_speed_walk := 11.0 ## radians per second at a walk
@export var turn_speed_run := 6.5 ## radians per second at a full run
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

@onready var model: HumanoidModel = $Model

var _fall_speed := 0.0
var _ground_query: PhysicsRayQueryParameters3D


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

	var old_yaw := rotation.y
	if amount > 0.05:
		var target_yaw := atan2(-wish.x, -wish.z)
		var diff := absf(angle_difference(rotation.y, target_yaw))
		if diff > reverse_brake_angle and speed > walk_speed + 0.5:
			# Reversing at a run: plant and slow down before coming round.
			target_speed = 0.0
		var run_t := clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0)
		var turn_rate := lerpf(turn_speed_walk, turn_speed_run, run_t)
		rotation.y = rotate_toward(rotation.y, target_yaw, turn_rate * delta)
		# Don't stride off sideways while still turning to face the way.
		if diff > 1.2 and speed < walk_speed:
			target_speed *= 0.3

	var old_speed := speed
	var rate := acceleration if target_speed > speed else deceleration
	speed = move_toward(speed, target_speed, rate * delta)

	var facing := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	velocity = facing * speed
	move_and_slide()
	_follow_ground(delta)

	# Walking into a wall: let the stride slow to what we actually manage,
	# so the legs don't keep pumping on the spot.
	var moved := get_real_velocity()
	moved.y = 0.0
	if get_slide_collision_count() > 0:
		speed = minf(speed, moved.length() + 0.3)

	run_amount = clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0)
	var turn := angle_difference(old_yaw, rotation.y) / maxf(delta, 0.0001)
	model.set_motion(moved.length(), (speed - old_speed) / maxf(delta, 0.0001), turn)


func _follow_ground(delta: float) -> void:
	_ground_query.from = global_position + Vector3.UP * (step_height + 0.3)
	_ground_query.to = global_position + Vector3.DOWN * 5.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty():
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
	_fall_speed = 0.0

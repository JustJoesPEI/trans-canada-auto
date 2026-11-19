class_name PlayerController
extends CharacterBody3D
## The player on foot: walk, run, turn, bump into things.
##
## Movement is relative to the camera, so "forward" is always into the
## screen. Height comes from a downward ray against the GROUND layer instead
## of floor physics, so curbs and kerb ramps are stepped up smoothly and never
## catch the capsule. Walls, poles and cars are on SOLID and block normally.

@export var walk_speed := 1.8 ## m/s, a brisk walk
@export var run_speed := 5.6 ## m/s, a steady run (hold Run)
@export var acceleration := 14.0 ## m/s per second
@export var turn_speed := 11.0 ## radians per second
@export var gravity := 20.0
@export var step_height := 0.4 ## tallest step the player walks straight up

## Set by main.gd. Movement uses its yaw.
var camera_rig: CameraRig
## When false the player ignores input (cutscenes, menus, sitting in a car).
var input_enabled := true

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

	var target_speed := (run_speed if running else walk_speed) * minf(1.0, wish.length())
	var target_vel := wish.normalized() * target_speed if wish.length() > 0.05 else Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_vel, acceleration * delta)
	velocity = horizontal
	move_and_slide()
	_follow_ground(delta)

	var moved := get_real_velocity()
	moved.y = 0.0
	if target_vel.length() > 0.1:
		var target_yaw := atan2(-target_vel.x, -target_vel.z)
		rotation.y = rotate_toward(rotation.y, target_yaw, turn_speed * delta)
	model.set_motion(moved.length())


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
	_fall_speed = 0.0

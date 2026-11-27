class_name AimDummy
extends CharacterBody3D
## A test target for trying the controller aim and the aim assist: a person
## who walks back and forth across your view, every other length at a run.
## Debug only: nothing makes one in the normal game. Press F6 (on foot) to
## put one 15 m in front of you, Shift+F6 for an officer (who gets the
## aim-in snap), Ctrl+F6 to clear them all. It's an "aim_targets" member
## like any other (see AimAssist), so it shows how to join in.

const DEBUG_KEY := KEY_F6
const GROUP := "aim_dummies"

## An officer: the aim-in snap goes to it.
@export var police := false
## Out of play: no assist onto it.
@export var out := false
## False to stand still (and be moved by hand, as the checks do).
@export var walking := true
@export var leg_length := 8.0 ## metres each way
@export var walk_speed := 1.9
@export var run_speed := 5.0

static var _shape: CapsuleShape3D

var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _to_b := true
var _leg := 0
var _model: HumanoidModel
var _ground := PhysicsRayQueryParameters3D.new()
var _speed := 0.0


func _init() -> void:
	add_to_group(AimAssist.GROUP)
	add_to_group(GROUP)
	collision_layer = Layers.CHARACTERS
	collision_mask = 0
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


func _ready() -> void:
	_model = HumanoidModel.new()
	if police:
		_model.set_appearance({"top": Color(0.07, 0.09, 0.17), "under": Color(0.75, 0.78, 0.85),
			"bottom": Color(0.06, 0.07, 0.12), "hat": Color(0.06, 0.07, 0.13), "shoes": Color(0.05, 0.05, 0.05)})
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = get_instance_id()
		_model.set_appearance(HumanoidModel.random_appearance(rng))
	add_child(_model)


## Walk between two points (on the ground near them).
func set_path(a: Vector3, b: Vector3) -> void:
	_a = a
	_b = b
	_to_b = true
	global_position = a
	look_at(b if not b.is_equal_approx(a) else a + Vector3.FORWARD, Vector3.UP)


func aim_points() -> Array[Vector3]:
	return [global_position + Vector3.UP * 1.2, global_position + Vector3.UP * 1.6]


func is_out() -> bool:
	return out


func is_police() -> bool:
	return police


func _physics_process(delta: float) -> void:
	if not walking:
		if _model != null:
			_model.set_motion(0.0)
		return
	var goal := _b if _to_b else _a
	var flat := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	var want := run_speed if _leg % 2 == 1 else walk_speed
	_speed = move_toward(_speed, want, 12.0 * delta)
	if flat.length() < 0.2:
		_to_b = not _to_b
		_leg += 1
		_speed = 0.0
	else:
		var step := flat.normalized() * minf(flat.length(), _speed * delta)
		global_position += step
		rotation.y = atan2(-flat.x, -flat.z)
	_follow_ground()
	if _model != null:
		_model.set_motion(_speed)


func _follow_ground() -> void:
	_ground.from = global_position + Vector3.UP * 1.5
	_ground.to = global_position + Vector3.DOWN * 4.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground)
	if not hit.is_empty():
		global_position.y = float(hit["position"].y)


## F6 and friends (see the class notes). Returns true when it handled the key.
static func debug_key(event: InputEvent, rig: CameraRig) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != DEBUG_KEY or not DevMode.on():
		return false
	var tree := rig.get_tree()
	if k.ctrl_pressed:
		for d in tree.get_nodes_in_group(GROUP):
			d.queue_free()
		return true
	if rig.target == null or rig.cockpit or rig.auto_follow_yaw:
		return true # on foot only
	var at := rig.target.global_position
	var fwd := Vector3(-sin(rig.yaw), 0.0, -cos(rig.yaw))
	var side := Vector3(cos(rig.yaw), 0.0, -sin(rig.yaw))
	var mid := at + fwd * 15.0
	var d := AimDummy.new()
	d.police = k.shift_pressed
	rig.target.get_parent().add_child(d)
	d.set_path(mid - side * d.leg_length * 0.5, mid + side * d.leg_length * 0.5)
	return true

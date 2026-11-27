class_name MissionPerson
extends Node3D
## Someone a mission puts in the town (Tenner, the parking officer): a
## person (HumanoidModel, one cached mesh per look) who stands, turns to
## face something, walks in straight lines over the ground, and says things
## over their head. Responder's walking and talking without the hose. No
## collision: cars and paint pass through, like the paramedics.

const WALK := 1.4
const SAY_RANGE := 40.0

var model: HumanoidModel
var goal := Vector3.INF
## What they turn to face while standing (INF: the way they were going).
var face := Vector3.INF
## 0..1: an arm up (a wave, writing a ticket, pointing).
var gesture := 0.0

var _label: Label3D
var _label_t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_t := 0.0
var _ground := NAN
var _heading := Vector2(0.0, -1.0)
var _speed := 0.0


## `look`: a HumanoidModel appearance; `key` names its cached mesh (the
## same key must always be the same look). `tint`: the colour of their lines.
func setup(look: Dictionary, key: String, tint := Color(1, 0.95, 0.75)) -> void:
	model = make_model(look, key)
	add_child(model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.0055
	_label.outline_size = 10
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 640.0
	_label.position = Vector3(0.0, model.height + 0.45, 0.0)
	_label.modulate = tint
	_label.visible = false
	_label.visibility_range_end = SAY_RANGE
	add_child(_label)
	_ray.collision_mask = Layers.GROUND


static func make_model(look: Dictionary, key: String) -> HumanoidModel:
	var m := HumanoidModel.new()
	m.set_appearance(look)
	m.mesh_cache_key = key
	m.draw_distance = 120.0
	return m


func move_to(p: Vector3) -> void:
	goal = p


func at_goal() -> bool:
	return goal == Vector3.INF


func say(text: String, secs := 3.6) -> void:
	if text == "":
		return
	_label.text = text
	_label.visible = true
	_label_t = secs


func hush() -> void:
	_label.visible = false
	_label_t = 0.0


## Standing at `p`, facing `toward`, at once.
func place(p: Vector3, toward: Vector3) -> void:
	goal = Vector3.INF
	var f := Vector2(toward.x - p.x, toward.z - p.z)
	if f.length() > 0.01:
		_heading = f.normalized()
	_ground = p.y
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-_heading.x, -_heading.y)), p)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0:
			_label.visible = false
	var p := Vector2(global_position.x, global_position.z)
	var want := Vector2.ZERO
	if goal != Vector3.INF:
		var to := Vector2(goal.x, goal.z) - p
		var d := to.length()
		if d > 0.3:
			want = to / d * minf(WALK, d * 3.0)
		else:
			goal = Vector3.INF
	_speed = move_toward(_speed, want.length(), 6.0 * delta)
	if want.length() > 0.01:
		p += want.normalized() * _speed * delta
		_heading = _heading.slerp(want.normalized(), clampf(delta * 8.0, 0.0, 1.0)).normalized()
	elif face != Vector3.INF:
		var f := Vector2(face.x, face.z) - p
		if f.length() > 0.1:
			_heading = _heading.slerp(f.normalized(), clampf(delta * 4.0, 0.0, 1.0)).normalized()
	_ray_t -= delta
	if _ray_t <= 0.0 or is_nan(_ground):
		_ray_t = 0.25
		_ray.from = Vector3(p.x, global_position.y + 1.2, p.y)
		_ray.to = Vector3(p.x, global_position.y - 2.5, p.y)
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			_ground = (hit["position"] as Vector3).y
	var y := global_position.y if is_nan(_ground) else move_toward(global_position.y, _ground, 4.0 * delta)
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-_heading.x, -_heading.y)), Vector3(p.x, y, p.y))
	model.set_motion(_speed)
	model.hands_up = gesture

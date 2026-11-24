class_name TrafficBystander
extends Node3D
## A traffic car's driver out on the street: staring at the paint on their
## car, or complaining that someone's just taken it. A person (HumanoidModel,
## one draw call) with a line over their head, no collision; they never
## fight or chase. Staring, they get back in after a while (`done`);
## complaining, they walk off along the sidewalk and are taken away once
## nobody can see them.

signal done

enum Mode { STARE, COMPLAIN }

const STARE_LINES := ["Oh, come ON.", "That's not coming off.", "My insurance won't cover paint.",
	"Who does that?", "I just had it washed.", "Unbelievable."]
const COMPLAIN_LINES := ["Hey! That's my car!", "I'm calling the police!", "Bring that back!",
	"Seriously? In broad daylight?", "My groceries are in there!"]

var mode := Mode.STARE
var car: Car
var time_left := 8.0
var _model: HumanoidModel
var _label: Label3D
var _walk_dir := Vector3.ZERO
var _t := 0.0


func setup(the_car: Car, how: Mode, rng: RandomNumberGenerator, at: Transform3D) -> void:
	car = the_car
	mode = how
	time_left = rng.randf_range(6.0, 11.0) if how == Mode.STARE else rng.randf_range(4.0, 6.0)
	_model = HumanoidModel.new()
	_model.set_appearance(HumanoidModel.random_appearance(rng))
	add_child(_model)
	_label = Label3D.new()
	var lines: Array = STARE_LINES if how == Mode.STARE else COMPLAIN_LINES
	_label.text = str(lines[rng.randi() % lines.size()])
	_label.font_size = 36
	_label.pixel_size = 0.006
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 2.15, 0.0)
	WorldLod.limit(_label, 0.6)
	add_child(_label)
	global_transform = Transform3D(Basis.IDENTITY, at.origin)
	_face(car.global_position if how == Mode.STARE else at.origin + at.basis.z)
	var away := at.origin - car.global_position
	away.y = 0.0
	_walk_dir = (car.global_basis.z if away.length() < 0.1 else away.normalized().slerp(-car.global_basis.z, 0.5)).normalized()


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.1:
		global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z))


func _physics_process(delta: float) -> void:
	_t += delta
	time_left -= delta
	if mode == Mode.STARE:
		if is_instance_valid(car):
			_face(car.global_position)
		_model.set_motion(0.0)
		_model.hands_up = 0.4 if fmod(_t, 3.0) < 1.2 else 0.0 # arms out at it
		if time_left <= 0.0:
			done.emit()
	else:
		if _t < 2.5:
			_model.set_motion(0.0)
			_model.hands_up = 0.8 # waving their arms
		else:
			_model.hands_up = 0.0
			global_basis = Basis(Vector3.UP, atan2(-_walk_dir.x, -_walk_dir.z))
			global_position += _walk_dir * 1.3 * delta
			_model.set_motion(1.3)
		if _t > 3.5:
			_label.visible = false
		if time_left <= 0.0:
			done.emit()

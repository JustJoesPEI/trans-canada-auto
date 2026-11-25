class_name TrafficBystander
extends Node3D
## A traffic car's driver out on the street: staring at the paint on their
## car, or complaining that someone's just taken it. A person (HumanoidModel,
## one draw call) with a line over their head, no collision; they never
## fight or chase. Staring, they get back in after a while (`done`);
## complaining, they walk off along the sidewalk and are taken away once
## nobody can see them. Paintballs landing near them (`scatter`), they run
## off along the sidewalk, away from it, and don't come back (a starer
## leaves the car where it is).

signal done
## Scattered: they won't be back.
signal ran_off

enum Mode { STARE, COMPLAIN, SCATTER }

const STARE_LINES := ["Oh, come ON.", "That's not coming off.", "My insurance won't cover paint.",
	"Who does that?", "I just had it washed.", "Unbelievable."]
const COMPLAIN_LINES := ["Hey! That's my car!", "I'm calling the police!", "Bring that back!",
	"Seriously? In broad daylight?", "My groceries are in there!"]
const SCATTER_LINES := ["Whoa!", "Run!", "Not again!", "Get down!", "Are you nuts?!"]
## How fast they run off (m/s), and for how long before they're taken away
## (once nobody can see them).
const RUN_SPEED := 4.2
const RUN_FOR := 7.0

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


## Paint landing at p: run off along the sidewalk, away from it. False if
## they're already running.
func scatter(from: Vector3) -> bool:
	if mode == Mode.SCATTER:
		return false
	mode = Mode.SCATTER
	_t = 0.0
	time_left = RUN_FOR
	# Along the street (the way the car points), whichever way is away.
	var along := car.global_basis.z if is_instance_valid(car) else _walk_dir
	along.y = 0.0
	along = along.normalized()
	var away := global_position - from
	away.y = 0.0
	if away.dot(along) < 0.0:
		along = -along
	_walk_dir = along
	ran_off.emit()
	_label.text = str(SCATTER_LINES[randi() % SCATTER_LINES.size()])
	_label.visible = true
	return true


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
	elif mode == Mode.SCATTER:
		# A beat to flinch, then run.
		var sp := 0.0 if _t < 0.35 else RUN_SPEED
		_model.hands_up = 0.9 if _t < 1.2 else 0.0
		global_basis = Basis(Vector3.UP, atan2(-_walk_dir.x, -_walk_dir.z))
		global_position += _walk_dir * sp * delta
		_model.set_motion(sp)
		if _t > 2.0:
			_label.visible = false
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

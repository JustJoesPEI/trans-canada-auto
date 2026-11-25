class_name WorkAudio
extends Node3D
## A working vehicle's sounds on top of its engine (CarAudio): the
## reversing alarm, the hydraulic pump while the forks or deck move, the
## winch reeling in, the clunk of a part reaching its stop, the fifth
## wheel's jaws locking on a kingpin, air brakes sighing as a truck stops,
## and the ratchet straps going on, coming off and snapping.
##
## Which of these a model has is in its shape: "backup_alarm" and
## "air_brakes" (true/false); hydraulics and the winch come with its tool.
## Sounds are in res://sounds/cars/shared/ (tools/make_car_sounds.py --work).

const DIR := "res://sounds/cars/shared/"
const SoundSettings := preload("res://scripts/autoload/sound.gd")

const ALARM_DB := -11.0
const HYDRAULIC_DB := -13.0
const WINCH_DB := -10.0
const AIR_DB := -8.0
const CLUNK_DB := -6.0
const HITCH_DB := -1.0
const STRAP_DB := -7.0

var car: Car

var _alarm: AudioStreamPlayer3D
var _hydraulic: AudioStreamPlayer3D
var _winch: AudioStreamPlayer3D
var _oneshots: Array[AudioStreamPlayer3D] = []
var _has_alarm := false
var _has_air := false
var _flow := 0.0 # smoothed hydraulic flow, 0..1
var _reel := 0.0
var _stops := 0
var _moving_time := 0.0
var _had_driver := false


func _ready() -> void:
	car = get_parent() as Car
	position = Vector3(0.0, 1.0, 0.0)
	_has_alarm = bool(car.shape.get("backup_alarm", false))
	_has_air = bool(car.shape.get("air_brakes", false))
	if _has_alarm:
		_alarm = _player(CarAudio._load_stream(DIR + "backup_alarm.ogg", true))
		# At the back, where the alarm is.
		_alarm.position = Vector3(0.0, 0.0, float(car.shape["length"]) * 0.45)
	if car.tool != null:
		_hydraulic = _player(CarAudio._load_stream(DIR + "hydraulic.ogg", true))
	if car.tool is RollbackTool or car.tool is CraneTool or car.has_winch():
		_winch = _player(CarAudio._load_stream(DIR + "winch.ogg", true))
	for i in 3:
		_oneshots.append(_player(null))
	car.hitched.connect(_on_hitched)
	car.tie_downs.strapped.connect(func(_n: int) -> void: _oneshot("ratchet", STRAP_DB, randf_range(0.95, 1.05)))
	car.tie_downs.released.connect(func(_n: int) -> void: _oneshot("strap_release", STRAP_DB, randf_range(0.95, 1.05)))
	car.tie_downs.strap_broke.connect(func(_b: RigidBody3D) -> void: _oneshot("strap_snap", STRAP_DB + 4.0, randf_range(0.95, 1.05)))


func _exit_tree() -> void:
	for p in get_children():
		if p is AudioStreamPlayer3D:
			p.stop()
			p.stream = null


func _process(delta: float) -> void:
	var bus: StringName = SoundSettings.CAR_BUS if car.driver != null else &"Master"
	for p in get_children():
		if p is AudioStreamPlayer3D and (p as AudioStreamPlayer3D).bus != bus:
			(p as AudioStreamPlayer3D).bus = bus

	# Reversing: the alarm beeps while it's in reverse and rolling back.
	if _has_alarm:
		var backing := car.driver != null and car.gear < 0 and (car.speed < -0.05 or car.throttle_input() < -0.05)
		_loop(_alarm, 1.0 if backing else 0.0, 1.0, ALARM_DB)

	# The hydraulics: the pump whines while the part moves, a little higher
	# the harder it's pushed, and clunks as it reaches the end of its travel.
	if car.tool != null:
		var flow := car.tool.motion()
		_flow = lerpf(_flow, flow, 1.0 - exp(-delta / (0.05 if flow > _flow else 0.12)))
		_loop(_hydraulic, _flow, 0.88 + 0.22 * _flow, HYDRAULIC_DB)
		if car.tool.stops != _stops:
			_stops = car.tool.stops
			_oneshot("clunk", CLUNK_DB, randf_range(0.9, 1.1))

	# The winch (the tow truck's, or one on the front bumper).
	if _winch != null:
		var wl := car.winch_line()
		var reel := 0.0
		var strain := 0.0
		if wl != null:
			reel = clampf(absf(wl.reel_rate) / maxf(wl.reel_speed, 0.01), 0.0, 1.0)
			# Labouring: slower and lower as the cable takes the strain.
			strain = clampf(wl.tension / wl.max_force, 0.0, 1.0)
		_reel = lerpf(_reel, reel, 1.0 - exp(-delta / 0.08))
		_loop(_winch, _reel, 0.8 + 0.25 * _reel - 0.2 * strain, WINCH_DB + 3.0 * strain)

	# Air brakes: a sigh as the truck comes to a stop, and the big one when
	# the parking brake goes on as the driver gets out.
	if _has_air:
		if absf(car.speed) > 2.0:
			_moving_time += delta
		elif absf(car.speed) < 0.2 and _moving_time > 1.5 and car.brake_applied > 0.1:
			_moving_time = 0.0
			_oneshot("air_short", AIR_DB, randf_range(0.92, 1.08))
		if _had_driver and car.driver == null:
			_oneshot("air_brake", AIR_DB + 2.0, randf_range(0.95, 1.05))
	_had_driver = car.driver != null


func _on_hitched(on: bool) -> void:
	if on:
		_oneshot("fifth_wheel", HITCH_DB, randf_range(0.95, 1.05))
	else:
		_oneshot("clunk", CLUNK_DB, 0.85)
		if _has_air:
			_oneshot("air_short", AIR_DB - 2.0, 1.15) # the air lines let go


func _player(stream: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 10.0
	p.max_distance = 160.0
	p.panning_strength = 0.6
	p.attenuation_filter_db = 0.0
	add_child(p)
	return p


func _loop(p: AudioStreamPlayer3D, gain: float, pitch: float, db: float) -> void:
	if p == null or p.stream == null:
		return
	if gain < 0.01:
		if p.playing:
			p.stop()
		return
	p.pitch_scale = pitch
	p.volume_db = db + linear_to_db(gain)
	if not p.playing:
		p.play(randf() * p.stream.get_length() if p != _alarm else 0.0)


func _oneshot(sound: String, db: float, pitch: float) -> void:
	var s := CarAudio._load_stream(DIR + sound + ".ogg", false)
	if s == null:
		return
	var best := _oneshots[0]
	for p in _oneshots:
		if not p.playing:
			best = p
			break
	best.stream = s
	best.volume_db = db
	best.pitch_scale = pitch
	best.play()

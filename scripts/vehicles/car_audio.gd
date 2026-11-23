class_name CarAudio
extends Node3D
## A car's sounds: the engine, the tyres, the road, the wind, and knocks.
##
## The engine is played from looping clips recorded (synthesized, by
## tools/make_car_sounds.py) at a ladder of steady revs, on the throttle
## and coasting. At any moment the two clips either side of the engine's
## revs play, each pitched to match the revs exactly, and are crossfaded;
## the on and off throttle sets are crossfaded by how hard the throttle is
## pressed. That's how racing games play real engine recordings, and it
## means the engine sounds right at every rev, not just one sample pitched
## up and down.
##
## The engine runs while someone's driving: it starts when a driver gets in
## (the starter, then it catches) and is switched off when they get out.
## Tyres, road and wind follow the car's own motion, so a parked car that
## gets shoved still scrapes and knocks.
##
## Sounds live in res://sounds/cars/<model id>/ (engine) and
## res://sounds/cars/shared/ (everything else). A model with no folder
## of its own simply has no engine sound.

const DIR := "res://sounds/cars/"

## Overall levels, dB.
const ENGINE_DB := 0.0
const ROAD_DB := -9.0
const WIND_DB := -13.0
const SQUEAL_DB := -7.0
const KNOCK_DB := -1.0
const BUMP_DB := -5.0
const POP_DB := -2.0

## How keen each engine is to pop and crackle on the overrun (0 never).
const POPS := {"pony_gt": 1.0, "halfton": 0.25}

var car: Car

var _rungs: Array[float] = [] # the revs of each clip on the ladder
var _on: Array[AudioStreamPlayer3D] = []
var _off: Array[AudioStreamPlayer3D] = []
var _start: AudioStreamPlayer3D
var _oneshots: Array[AudioStreamPlayer3D] = [] # pops, knocks and bumps share these
var _road: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _squeal: AudioStreamPlayer3D

var _running := false
var _engine_gain := 0.0
var _engine_wait := 0.0 # seconds before the loops come in after key-on
var _rpm := 0.0
var _load := 0.0
var _prev_throttle := 0.0
var _skid := 0.0
var _knock_cool := 0.0
var _pop_cool := 0.0
var _was_shifting := false


func _ready() -> void:
	_add_limiter()
	car = get_parent() as Car
	var shape: Dictionary = car.shape
	# The exhaust is what you hear most from behind: put the engine there.
	position = Vector3(0.0, 0.4, float(shape["rear_axle"]) * 0.9)
	_road = _player(_load_stream(DIR + "shared/road.ogg", true))
	_wind = _player(_load_stream(DIR + "shared/wind.ogg", true))
	_squeal = _player(_load_stream(DIR + "shared/tyre_squeal.ogg", true))
	for i in 3:
		_oneshots.append(_player(null))
	car.crashed.connect(_on_crashed)
	car.bumped.connect(_on_bumped)
	_rpm = float(car.spec["engine"]["idle_rpm"])


func _exit_tree() -> void:
	# Let go of everything playing, so nothing's left in the mixer.
	for p in get_children():
		if p is AudioStreamPlayer3D:
			p.stop()
			p.stream = null


func _process(delta: float) -> void:
	if car.driver != null and not _running:
		_key_on()
	elif car.driver == null and _running:
		_key_off()
	_update_engine(delta)
	_update_motion(delta)
	_knock_cool = maxf(0.0, _knock_cool - delta)
	_pop_cool = maxf(0.0, _pop_cool - delta)


# --- engine --------------------------------------------------------------------------

func _build_engine() -> bool:
	if not _rungs.is_empty():
		return true
	var dir := DIR + car.model_id + "/"
	for f in ResourceLoader.list_directory(dir):
		if f.begins_with("on_") and f.ends_with(".ogg"):
			_rungs.append(float(f.trim_prefix("on_").trim_suffix(".ogg")))
	if _rungs.is_empty():
		return false
	_rungs.sort()
	for r in _rungs:
		_on.append(_player(_load_stream(dir + "on_%d.ogg" % int(r), true)))
		_off.append(_player(_load_stream(dir + "off_%d.ogg" % int(r), true)))
	_start = _player(null)
	return true


func _key_on() -> void:
	_running = true
	if not _build_engine():
		return
	_engine_gain = 0.0
	_rpm = float(car.spec["engine"]["idle_rpm"])
	var s := _load_stream(DIR + car.model_id + "/start.ogg", false)
	_engine_wait = 0.0
	if s != null:
		_start.stream = s
		_start.volume_db = ENGINE_DB
		_start.play()
		# The clip ends idling; the loops take over for its last moments.
		_engine_wait = maxf(0.0, s.get_length() - 0.55)


func _key_off() -> void:
	_running = false
	if _rungs.is_empty():
		return
	_start.stop()
	var s := _load_stream(DIR + car.model_id + "/stop.ogg", false)
	if s != null and _engine_gain > 0.3:
		_start.stream = s
		_start.volume_db = ENGINE_DB
		_start.play()


func _update_engine(delta: float) -> void:
	if _rungs.is_empty():
		return
	var eng: Dictionary = car.spec["engine"]
	var idle := float(eng["idle_rpm"])
	var redline := float(eng["redline_rpm"])
	var throttle := absf(car.throttle_input())
	var shifting := car.is_shifting()

	# Engine gain: in once the key-on clip has caught, out at key-off.
	if _running:
		_engine_wait -= delta
		if throttle > 0.1 and _engine_wait > 0.0 and _start.get_playback_position() > 1.0:
			# Foot down before it's settled: hand over now.
			_engine_wait = 0.0
		if _engine_wait <= 0.0:
			_engine_gain = move_toward(_engine_gain, 1.0, delta / 0.35)
			if _start.playing and _engine_gain > 0.5 and _start.stream.resource_path.ends_with("start.ogg"):
				_start.volume_db = ENGINE_DB + linear_to_db(maxf(1.0 - _engine_gain, 0.001) * 2.0)
	else:
		_engine_gain = move_toward(_engine_gain, 0.0, delta / 0.08)

	# Revs and load, with a touch of the engine's own inertia.
	var target := clampf(car.rpm, idle * 0.9, redline * 1.05)
	_rpm = lerpf(_rpm, target, 1.0 - exp(-delta / (0.04 if target > _rpm else 0.07)))
	var want_load := 0.15 if shifting else throttle
	_load = lerpf(_load, want_load, 1.0 - exp(-delta / 0.06))

	# Overrun pops: lifting off at high revs, the odd one on an upshift, and
	# now and then while coasting down from high revs.
	var pops := float(POPS.get(car.model_id, 0.0))
	if pops > 0.0 and _running and _engine_gain > 0.9:
		var high := _rpm > redline * 0.5
		if high and _prev_throttle > 0.6 and throttle < 0.1 and randf() < 0.75 * pops:
			_pop_burst(randi_range(1, 3))
		elif shifting and not _was_shifting and randf() < 0.35 * pops:
			_pop_burst(1)
		elif high and throttle < 0.05 and randf() < delta * 0.7 * pops:
			_pop_burst(1)
	_prev_throttle = throttle
	_was_shifting = shifting

	# Where the revs sit on the ladder, and the two clips either side.
	var n := _rungs.size()
	var x := 0.0
	if _rpm <= _rungs[0]:
		x = 0.0
	elif _rpm >= _rungs[n - 1]:
		x = n - 1.0
	else:
		for i in range(1, n):
			if _rpm <= _rungs[i]:
				x = i - 1 + log(_rpm / _rungs[i - 1]) / log(_rungs[i] / _rungs[i - 1])
				break
	var lo := mini(int(x), n - 2)
	var f := x - lo
	var g_on := sin(_load * PI * 0.5) * _engine_gain
	var g_off := cos(_load * PI * 0.5) * _engine_gain
	for i in n:
		var w := 0.0
		if i == lo:
			w = cos(f * PI * 0.5)
		elif i == lo + 1:
			w = sin(f * PI * 0.5)
		var pitch := clampf(_rpm / _rungs[i], 0.5, 2.0)
		_drive_loop(_on[i], w * g_on, pitch, ENGINE_DB)
		_drive_loop(_off[i], w * g_off, pitch, ENGINE_DB)


func _pop_burst(count: int) -> void:
	if _pop_cool > 0.0:
		return
	_pop_cool = 0.35
	var s := _load_stream(DIR + car.model_id + "/pop_%d.ogg" % randi_range(0, 3), false)
	_oneshot(s, POP_DB - 3.0 + count, randf_range(0.92, 1.08))


# --- tyres, road, wind ---------------------------------------------------------------

func _update_motion(delta: float) -> void:
	var v := car.linear_velocity.length()
	var on_road := car.wheels_down > 0
	_skid = lerpf(_skid, car.skid if on_road else 0.0, 1.0 - exp(-delta / 0.07))
	var sp := clampf(v / 30.0, 0.0, 1.0) if on_road else 0.0
	_drive_loop(_road, pow(sp, 1.2), 0.7 + 0.6 * sp, ROAD_DB)
	var ws := clampf(v / 45.0, 0.0, 1.4)
	_drive_loop(_wind, ws * ws, 0.8 + 0.4 * ws, WIND_DB)
	var sk := clampf((_skid - 0.03) * 1.2, 0.0, 1.0)
	_drive_loop(_squeal, sk, 0.92 + 0.15 * sk + 0.05 * clampf(v / 30.0, 0.0, 1.0), SQUEAL_DB)


func _on_crashed(jolt: float) -> void:
	if _knock_cool > 0.0:
		return
	_knock_cool = 0.2
	var heavy := jolt > 10.0
	var s := _load_stream(DIR + "shared/knock_%s_%d.ogg" % ["heavy" if heavy else "light", randi_range(0, 2)], false)
	_oneshot(s, KNOCK_DB + linear_to_db(clampf(jolt / (16.0 if heavy else 9.0), 0.3, 1.0)), randf_range(0.9, 1.1))


func _on_bumped(strength: float) -> void:
	if _knock_cool > 0.0:
		return
	_knock_cool = 0.12
	var s := _load_stream(DIR + "shared/bump_%d.ogg" % randi_range(0, 2), false)
	_oneshot(s, BUMP_DB + linear_to_db(clampf(strength / 3.5, 0.25, 1.0)), randf_range(0.9, 1.1))


# --- players -------------------------------------------------------------------------

func _player(stream: AudioStream) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 8.0
	p.max_distance = 220.0
	p.panning_strength = 0.6
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -12.0
	add_child(p)
	return p


## Keeps a looping player going while it's wanted, silent and stopped when not.
func _drive_loop(p: AudioStreamPlayer3D, gain: float, pitch: float, db: float) -> void:
	if p.stream == null:
		return
	if gain < 0.002:
		if p.playing:
			p.stop()
		return
	p.pitch_scale = pitch
	p.volume_db = db + linear_to_db(gain)
	if not p.playing:
		# Start each loop somewhere new, so two cars never sound in step.
		p.play(randf() * p.stream.get_length())


func _oneshot(s: AudioStream, db: float, pitch: float) -> void:
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


## A limiter on the master bus, so a crash on top of a screaming engine on
## top of squealing tyres doesn't clip.
static func _add_limiter() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)


static func _load_stream(path: String, looped: bool) -> AudioStream:
	# (load() keeps one copy of each file, shared by every car.)
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if looped and s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s

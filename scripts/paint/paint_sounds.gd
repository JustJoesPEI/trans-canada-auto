class_name PaintSounds
extends RefCounted
## The marker's sounds, made in code once (no files to ship): the pop of a
## shot, the "thwack" only the shooter hears when they hit someone, the
## heavier thwack and ref's whistle of an out (docs/design.md section 2,
## "Feel"), and an armour plate breaking. Placeholders with the right
## timing and weight: worth replacing with recorded ones in the sound pass.

const RATE := 22050

static var _cache := {}


## A shot leaving the barrel.
static func pop() -> AudioStreamWAV:
	return _make("pop", _pop_at, 0.08)


## A hit on someone (or a car), heard by the shooter.
static func thwack() -> AudioStreamWAV:
	return _make("thwack", _thwack_at, 0.12)


## Someone's out: a heavy thwack, then two blasts of a pea whistle.
static func out_confirm() -> AudioStreamWAV:
	return _make("out", _out_at, 0.82)


## An armour plate breaking (Armour): a hard crack and a ceramic rattle.
static func plate_break() -> AudioStreamWAV:
	return _make("plate", _plate_at, 0.3)


static func _plate_at(t: float, rng: RandomNumberGenerator) -> float:
	var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
	var ring := sin(TAU * 1850.0 * t) * exp(-t * 30.0) * 0.35 + sin(TAU * 2630.0 * t) * exp(-t * 42.0) * 0.25
	# Bits falling: a few short clicks after the crack.
	var bits := 0.0
	for start: float in [0.07, 0.12, 0.19]:
		var u := t - start
		if u > 0.0:
			bits += rng.randf_range(-1.0, 1.0) * exp(-u * 260.0) * 0.4
	return crack * 0.9 + ring + bits


static func _pop_at(t: float, rng: RandomNumberGenerator) -> float:
	return (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 160.0 * t) * 0.6) * exp(-t * 90.0)


static func _thwack_at(t: float, rng: RandomNumberGenerator) -> float:
	var click := exp(-t * 400.0) * rng.randf_range(-1.0, 1.0)
	var body := sin(TAU * (320.0 - 900.0 * t) * t) * exp(-t * 45.0)
	return click * 0.8 + body * 0.7


static func _out_at(t: float, rng: RandomNumberGenerator) -> float:
	var thud := (rng.randf_range(-1.0, 1.0) * exp(-t * 200.0) + sin(TAU * (180.0 - 300.0 * t) * t) * exp(-t * 18.0)) * 0.8
	var w := 0.0
	for start: float in [0.18, 0.52]:
		var u := t - start
		if u > 0.0 and u < 0.26:
			var shape := smoothstep(0.0, 0.02, u) * (1.0 - smoothstep(0.2, 0.26, u))
			# The pea: the pitch warbles about 30 times a second.
			w += sin(TAU * 2900.0 * u + sin(TAU * 32.0 * u) * 6.0) * shape * 0.45
	return thud + w


static func _make(id: String, f: Callable, length: float) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(float(f.call(float(i) / RATE, rng)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	_cache[id] = s
	return s

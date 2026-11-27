class_name MissionSounds
extends RefCounted
## The missions' little sounds, made in code like PaintSounds (no files):
## the pen scratching a line out, the result stamp, the meter's tick, a
## coin in the meter, and the title cards' stings (a 70s cop-show funk
## hit for The Garage). 16-bit mono, made once and cached.
##
##   MissionSounds.play(node, stream, db)   a one-shot on the screen (not
##                                          in the world), freed after

const RATE := 22050

static var _cache := {}


## A one-shot, not positional, added under `node` and freed when done.
static func play(node: Node, stream: AudioStream, db := -6.0, pitch := 1.0) -> void:
	if node == null or not node.is_inside_tree() or stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	node.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## A sound by name (a title style's "sting"), null for none.
static func named(id: String) -> AudioStream:
	match id:
		"garage_sting":
			return garage_sting()
	return null


## A pen line scribbled across a word: scratchy noise in a few strokes.
static func scribble() -> AudioStreamWAV:
	return _make("scribble", 0.42, func(t: float, rng: RandomNumberGenerator) -> float:
		var strokes := 3.0
		var u := fmod(t * strokes / 0.42, 1.0)
		var env := sin(PI * u) * (1.0 - t / 0.42 * 0.4)
		var n := rng.randf_range(-1.0, 1.0)
		return n * env * 0.35 * (0.6 + 0.4 * sin(TAU * 90.0 * t)))


## The rubber stamp coming down: a thump and a slap.
static func stamp() -> AudioStreamWAV:
	return _make("stamp", 0.35, func(t: float, rng: RandomNumberGenerator) -> float:
		var thump := sin(TAU * (95.0 - 50.0 * t) * t) * exp(-t * 18.0)
		var slap := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.6
		return (thump + slap) * 0.9)


## The meter's tick, the last seconds.
static func tick() -> AudioStreamWAV:
	return _make("tick", 0.05, func(t: float, _rng: RandomNumberGenerator) -> float:
		return sin(TAU * 1900.0 * t) * exp(-t * 120.0) * 0.6)


## A coin going in: two bright pings and a rattle down the slot.
static func coin() -> AudioStreamWAV:
	return _make("coin", 0.5, func(t: float, rng: RandomNumberGenerator) -> float:
		var v := 0.0
		for hit: float in [0.0, 0.09]:
			var u := t - hit
			if u >= 0.0:
				v += (sin(TAU * 3100.0 * u) + 0.6 * sin(TAU * 4650.0 * u)) * exp(-u * 30.0) * 0.35
		var r := t - 0.16
		if r > 0.0:
			v += rng.randf_range(-1.0, 1.0) * exp(-r * 14.0) * 0.12 * (0.5 + 0.5 * signf(sin(TAU * 38.0 * r)))
		return v)


## A short pass/fail sting for the result: up for hired, down for failed.
static func result(passed: bool) -> AudioStreamWAV:
	return _make("result_%s" % passed, 0.9, func(t: float, _rng: RandomNumberGenerator) -> float:
		var notes := [392.0, 523.3, 659.3] if passed else [329.6, 293.7, 220.0]
		var i := mini(int(t / 0.14), 2)
		var u := t - i * 0.14
		var f: float = notes[i]
		var env := exp(-u * (3.0 if i == 2 else 9.0))
		return (_saw(f * t) * 0.4 + _saw(f * 1.006 * t) * 0.3) * env * 0.5)


## The Garage's title sting: a bar of 70s cop-show funk. A popping bass,
## a wah guitar on the off-beats, hi-hats, and a brass hit to finish.
static func garage_sting() -> AudioStreamWAV:
	if _cache.has("garage_sting"):
		return _cache["garage_sting"]
	var length := 3.0
	var n := int(length * RATE)
	var beat := 60.0 / 112.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var data := PackedByteArray()
	data.resize(n * 2)
	# The wah: a sawtooth chord through a resonant low-pass whose cutoff
	# sweeps with each stab (a state-variable filter, kept as we go).
	var lp := 0.0
	var bp := 0.0
	# E9 (E G# D F#), in the guitar's middle register.
	var chord := [164.8, 207.7, 293.7, 370.0]
	# The bass: E, E an octave up, G, A, B (sixteenths, some rests).
	var bass := [41.2, 0.0, 82.4, 41.2, 0.0, 49.0, 55.0, 61.7, 41.2, 0.0, 82.4, 0.0, 73.4, 0.0, 82.4, 82.4]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		var sixteenth := beat / 4.0
		var step := int(t / sixteenth)
		var in_step := t - step * sixteenth
		var bar_done := t > beat * 4.0
		if not bar_done:
			# Bass, a pluck per sixteenth.
			var bf: float = bass[step % bass.size()]
			if bf > 0.0:
				var benv := exp(-in_step * 9.0)
				v += (sin(TAU * bf * t) * 0.8 + _saw(bf * 2.0 * t) * 0.15) * benv * 0.55
			# Hi-hat on every eighth, open on the off-beat.
			var eighth := beat / 2.0
			var in_e := fmod(t, eighth)
			var open := int(t / eighth) % 2 == 1
			v += rng.randf_range(-1.0, 1.0) * exp(-in_e * (25.0 if open else 70.0)) * 0.12
			# Kick on 1 and 3, snare on 2 and 4.
			var in_b := fmod(t, beat)
			var b := int(t / beat)
			if b % 2 == 0:
				v += sin(TAU * (110.0 - 60.0 * minf(in_b * 8.0, 1.0)) * in_b) * exp(-in_b * 14.0) * 0.6
			else:
				v += (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 190.0 * in_b) * 0.3) * exp(-in_b * 16.0) * 0.45
		# The wah guitar: a chord stab on each off-beat sixteenth, the
		# filter opening and closing over each stab ("wacka").
		var g := 0.0
		for f: float in chord:
			g += _saw(f * t) * 0.25
		var stab := step % 2 == 1 and not bar_done
		var genv := exp(-in_step * 10.0) if stab else 0.0
		var sweep := sin(PI * clampf(in_step / sixteenth, 0.0, 1.0))
		var cutoff := 400.0 + 2600.0 * sweep
		var fq := 2.0 * sin(PI * minf(cutoff, RATE * 0.2) / RATE)
		var q := 0.18
		lp += fq * bp
		var hp := g * genv - lp - q * bp
		bp += fq * hp
		v += bp * 0.7
		# The brass hit on the downbeat after the bar, held and fading.
		if bar_done:
			var u := t - beat * 4.0
			var benv2 := minf(u * 40.0, 1.0) * exp(-u * 1.6)
			var brass := 0.0
			for f: float in [164.8, 246.9, 329.6, 415.3]:
				brass += _saw(f * t) * 0.22 + _saw(f * 1.004 * t) * 0.18
			# A fall-off at the end, the way a horn section drops a note.
			var fall := 1.0 - 0.06 * smoothstep(0.6, 1.4, u)
			brass *= fall
			v += brass * benv2 * 0.55
			v += sin(TAU * (90.0 - 40.0 * minf(u * 8.0, 1.0)) * u) * exp(-u * 10.0) * 0.6
		var out := tanh(v * 1.2) * 0.85
		data.encode_s16(i * 2, int(clampf(out, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	_cache["garage_sting"] = s
	return s


## A sawtooth, -1..1, at phase `x` (cycles).
static func _saw(x: float) -> float:
	return 2.0 * (x - floorf(x + 0.5))


static func _make(id: String, length: float, f: Callable) -> AudioStreamWAV:
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

class_name TickProfile
extends Node
## Where a server tick's time goes (tools/traffic_server.gd `--profile`):
## the code being timed adds the microseconds of its parts with `add`
## (only while `on`), and a TickProfile node marks where the physics
## step's scripts and the frame's own processing start and end (`mark`:
## one runs first, one last).

static var on := false
static var _us := {} ## section -> microseconds, summed
static var _ticks := 0

## Which end this node marks: 0 the physics scripts' start, 1 their end,
## 2 the idle processing's start, 3 its end.
var which := 0
static var _at := [0, 0, 0, 0]


static func add(section: StringName, us: int) -> void:
	_us[section] = int(_us.get(section, 0)) + us
	_cur[section] = int(_cur.get(section, 0)) + us


## This tick's sections so far, the slowest tick's, and for the ticks
## over SLOW_MS, which of their sections was the biggest (and how often).
static var _cur := {}
static var _worst := {}
static var _worst_us := 0
static var _slow := {}
const SLOW_MS := 25.0
const WHOLE := [&"physics scripts (all)", &"idle process (all)"]


## Starts counting again (after the fill).
static func reset() -> void:
	_us.clear()
	_cur.clear()
	_worst.clear()
	_worst_us = 0
	_slow.clear()
	_ticks = 0


## A tick's end, and what it took (us).
static func tick(frame_us := 0) -> void:
	_ticks += 1
	if frame_us > _worst_us:
		_worst_us = frame_us
		_worst = _cur.duplicate()
	if frame_us > SLOW_MS * 1000.0:
		var big: StringName = &""
		for k: StringName in _cur:
			if not WHOLE.has(k) and (big == &"" or int(_cur[k]) > int(_cur[big])):
				big = k
		# What no script timed: the physics engine's step, the engine, the
		# machine.
		var rest := frame_us - int(_cur.get(WHOLE[0], 0)) - int(_cur.get(WHOLE[1], 0))
		if big == &"" or rest > int(_cur[big]):
			big = &"(untimed: the physics engine, the machine)"
		_slow[big] = int(_slow.get(big, 0)) + 1
	_cur.clear()


## The slowest tick's sections and the slow ticks' biggest parts.
static func report_slow() -> String:
	var w := PackedStringArray()
	for k: StringName in _worst:
		w.append("%s %.1f" % [k, int(_worst[k]) / 1000.0])
	var sl := PackedStringArray()
	for k: StringName in _slow:
		sl.append("%s %d" % [k, _slow[k]])
	return "the slowest (%.1f ms): %s; ticks over %.0f ms, by their biggest part: %s" % [_worst_us / 1000.0, ", ".join(w), SLOW_MS, ", ".join(sl)]


## The sections, slowest first, in ms a tick.
static func report() -> String:
	var keys := _us.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(_us[a]) > int(_us[b]))
	var out := PackedStringArray()
	for k: StringName in keys:
		out.append("%s %.2f" % [k, int(_us[k]) / 1000.0 / maxi(_ticks, 1)])
	return ", ".join(out)


## Two nodes for the physics scripts (first and last) and two for the
## frame's processing, added under `parent`.
static func add_marks(parent: Node) -> void:
	for i in 4:
		var m := TickProfile.new()
		m.which = i
		m.name = "TickProfile%d" % i
		if i < 2:
			m.process_physics_priority = -100000 if i == 0 else 100000
			m.set_process(false)
		else:
			m.process_priority = -100000 if i == 2 else 100000
			m.set_physics_process(false)
		parent.add_child(m)


func _physics_process(_delta: float) -> void:
	_mark()


func _process(_delta: float) -> void:
	_mark()


func _mark() -> void:
	var now := Time.get_ticks_usec()
	_at[which] = now
	if not on:
		return
	if which == 1:
		add(&"physics scripts (all)", now - int(_at[0]))
	elif which == 3:
		add(&"idle process (all)", now - int(_at[2]))

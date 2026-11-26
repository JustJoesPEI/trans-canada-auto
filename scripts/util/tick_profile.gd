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


## Starts counting again (after the fill).
static func reset() -> void:
	_us.clear()
	_ticks = 0


static func tick() -> void:
	_ticks += 1


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

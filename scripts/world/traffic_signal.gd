class_name TrafficSignal
extends Node
## Cycles the signal heads at one junction: one direction gets green, then
## amber, then both red, then the other direction gets its turn.
## Every junction runs off one shared clock (`clock`, advanced once per
## physics step by whichever signal or driver gets there first), offset per
## junction, so a junction shows the same lights whenever its chunk is
## built, and computer drivers read them with `lamp_at(nid, phase)` without
## the signal's chunk being loaded. A way in's phase is `phase_of(dir)`.

const GREEN_TIME := 14.0
const AMBER_TIME := 3.5
const ALL_RED_TIME := 1.5

static var _on: Array[Material] = []
static var _off: Array[Material] = []

## Seconds on the town's signal clock (see advance()).
static var clock := 0.0
static var _clock_frame := -1

## Every signal in the tree. One of them (`_ticker`) does the per-frame
## work for all of them (each its own _process and _physics_process was a
## callback per junction, thousands a frame over a big town).
static var _all: Array[TrafficSignal] = []
static var _ticker: TrafficSignal = null

var _heads: Array = [] # [lamps: Array[MeshInstance3D], phase: int]
var _time := 0.0
var _offset := 0.0
var _state := -1


static func _ensure_materials() -> void:
	if not _on.is_empty():
		return
	var mats := Materials.get_shared()
	var colours := [Color(0.95, 0.15, 0.1), Color(1.0, 0.65, 0.1), Color(0.2, 0.95, 0.4)]
	for c: Color in colours:
		_on.append(mats.glow(c, 3.0))
		_off.append(mats.plain(c.darkened(0.8), 0.4))


func _ready() -> void:
	_ensure_materials()
	# Offset each junction so the whole town doesn't change in step.
	_offset = float(absi(hash(name)) % 30)
	_time = clock + _offset
	_pick_ticker()


func _enter_tree() -> void:
	_all.append(self)
	if is_node_ready():
		_pick_ticker()


func _exit_tree() -> void:
	_all.erase(self)
	if _ticker == self:
		_ticker = null
		set_process(false)
		set_physics_process(false)
		for s: TrafficSignal in _all:
			if s.is_node_ready():
				s._pick_ticker()
				break


## Only the ticker processes (it ticks them all); the rest are ticked.
func _pick_ticker() -> void:
	if _ticker == null or not is_instance_valid(_ticker) or not _ticker.is_inside_tree():
		_ticker = self
	var me := _ticker == self
	set_process(me)
	set_physics_process(me)


## Moves the shared clock on by one physics step (only once per step,
## however many call it).
static func advance(delta: float) -> void:
	var f := Engine.get_physics_frames()
	if f == _clock_frame:
		return
	_clock_frame = f
	clock += delta


## The lamp (0 red, 1 amber, 2 green) showing now for a phase at junction
## `nid`, whether or not its chunk is built.
static func lamp_at(nid: String, phase: int) -> int:
	return lamp_for(phase, clock + offset_of(nid))


## How far (s) junction `nid`'s lights run ahead of the shared clock.
static func offset_of(nid: String) -> float:
	return float(absi(hash("Signals_%s" % nid)) % 30)


## Seconds until the lamp for a phase at `nid` next changes.
static func time_to_change(nid: String, phase: int) -> float:
	var t := clock + float(absi(hash("Signals_%s" % nid)) % 30)
	var now := lamp_for(phase, t)
	var dt := 0.0
	while dt < 40.0 and lamp_for(phase, t + dt) == now:
		dt += 0.25
	return dt


## The phase of a way into a junction, from its direction (an incident's
## `dir`, pointing out of the junction): as the heads are hung.
static func phase_of(dir: Vector2) -> int:
	return 0 if absf(dir.x) >= absf(dir.y) else 1


func add_head(lamps: Array[MeshInstance3D], phase: int) -> void:
	_heads.append([lamps, phase])


## Which lamp (0 red, 1 amber, 2 green) shows for a phase at cycle time t.
static func lamp_for(phase: int, t: float) -> int:
	var half := GREEN_TIME + AMBER_TIME + ALL_RED_TIME
	var local := fmod(t, half * 2.0) - half * phase
	if local < 0.0 or local >= half:
		return 0
	if local < GREEN_TIME:
		return 2
	if local < GREEN_TIME + AMBER_TIME:
		return 1
	return 0


func is_green(phase: int) -> bool:
	return lamp_for(phase, _time) == 2


func _physics_process(delta: float) -> void:
	advance(delta)


func _process(_delta: float) -> void:
	for s: TrafficSignal in _all:
		if s.is_node_ready():
			s._show()


## This junction's lamps for the clock now.
func _show() -> void:
	_time = clock + _offset
	var state := lamp_for(0, _time) * 3 + lamp_for(1, _time)
	if state == _state:
		return
	_state = state
	if ChunkBuilder.server_build():
		return # (a server draws nothing: its chunks have no lamps)
	for h: Array in _heads:
		var lamps: Array[MeshInstance3D] = h[0]
		var lit := lamp_for(h[1], _time)
		# Lamps are stacked red (top), amber, green, matching lamp_for()'s numbers.
		for i in lamps.size():
			lamps[i].material_override = _on[i] if i == lit else _off[i]

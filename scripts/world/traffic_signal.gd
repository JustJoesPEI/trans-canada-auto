class_name TrafficSignal
extends Node
## Cycles the signal heads at one junction: one direction gets green, then
## amber, then both red, then the other direction gets its turn.
##
## Every junction runs on one game clock (physics steps since the start),
## offset by its node id, so the lights are the same whether or not the
## chunk with the heads in it is built: a computer driver anywhere can ask
## `lamp_at(node_id, phase)` (the police do). The phase of a way in is
## `phase_of(dir)`: 0 for ways in running mostly east-west, 1 north-south,
## the rule StreetProps hangs the heads by.

const GREEN_TIME := 14.0
const AMBER_TIME := 3.5
const ALL_RED_TIME := 1.5

static var _on: Array[Material] = []
static var _off: Array[Material] = []

## The junction's node id in the RoadNetwork (StreetProps sets it).
var node_id := ""

var _heads: Array = [] # [lamps: Array[MeshInstance3D], phase: int]
var _time := 0.0
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


## Seconds on the game clock that every signal runs on.
static func clock() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Each junction's own offset into the cycle, so the whole town doesn't
## change in step.
static func offset_of(node_id: String) -> float:
	return float(absi(hash("Signals_%s" % node_id)) % 30)


## The lamp (0 red, 1 amber, 2 green) a way in of `phase` sees at a
## junction now.
static func lamp_at(node_id: String, phase: int) -> int:
	return lamp_for(phase, clock() + offset_of(node_id))


## The phase of a way into a junction from its direction out along the way
## (RoadNetwork.Incident.dir), as StreetProps groups the heads.
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


func _process(_delta: float) -> void:
	_time = clock() + offset_of(node_id if node_id != "" else str(name).trim_prefix("Signals_"))
	var state := lamp_for(0, _time) * 3 + lamp_for(1, _time)
	if state == _state:
		return
	_state = state
	for h: Array in _heads:
		var lamps: Array[MeshInstance3D] = h[0]
		var lit := lamp_for(h[1], _time)
		# Lamps are stacked red (top), amber, green, matching lamp_for()'s numbers.
		for i in lamps.size():
			lamps[i].material_override = _on[i] if i == lit else _off[i]

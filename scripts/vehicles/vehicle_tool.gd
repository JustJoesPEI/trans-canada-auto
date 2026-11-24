class_name VehicleTool
extends Node
## A vehicle's working part: the tilting deck and winch of a tow truck, the
## mast and forks of a forklift. The part's collision shapes move with it
## (Car.set_part_transform), so whatever sits on a deck or a pair of forks
## is carried by the physics, not stuck on.
##
## The driver works it with the actions work_up / work_down (R / G, the
## bumpers) and aux_in / aux_out (Y / H, the d-pad), and "hitch" (T) for
## anything that hooks on.

var car: Car
## Counts each time a moving part runs up against the end of its travel
## (forks at the top, deck stowed), for the clunk (WorkAudio).
var stops := 0

## How long the hydraulics take to come up to speed and to stop (s): a
## valve opening, not a switch, so loads aren't jolted.
const EASE_TIME := 0.18


static func make(kind: String) -> VehicleTool:
	match kind:
		"rollback":
			return RollbackTool.new()
		"forklift":
			return ForkliftTool.new()
	return VehicleTool.new()


func setup(owner_car: Car) -> void:
	car = owner_car


## Called by the vehicle every physics step, before its wheels.
func physics(_delta: float) -> void:
	pass


## True while the part is out and the vehicle shouldn't drive off.
func holds_still() -> bool:
	return false


## The hitch key while driving: hook or unhook something. Returns a line
## for the HUD, or "" if this tool has nothing to hook.
func hitch_action() -> String:
	return ""


## One line about what the part is doing now ("Deck down", "Forks 1.2 m").
func status() -> String:
	return ""


## How hard the hydraulics are working, 0 (still) to 1 (full flow): the
## pump's whine follows it and the engine revs up to drive it.
func motion() -> float:
	return 0.0


## The controls for the HUD's card while driving: rows of [actions, what
## they do], e.g. [["work_up", "work_down"], "forks up / down"] (see
## Hud.set_controls).
func controls() -> Array:
	return []


## Moves a rate toward what the lever asks for at the hydraulics' pace.
static func ease_rate(rate: float, want: float, full: float, delta: float) -> float:
	return move_toward(rate, want, full / EASE_TIME * delta)


## -1..1 from a pair of actions, only while someone is driving.
func _axis(neg: String, pos: String) -> float:
	if car.driver == null:
		return 0.0
	return Input.get_action_strength(pos) - Input.get_action_strength(neg)

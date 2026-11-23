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


## The controls, for the HUD when getting in.
func hint() -> String:
	return ""


## One line about what the part is doing now ("Deck down", "Forks 1.2 m").
func status() -> String:
	return ""


## -1..1 from a pair of actions, only while someone is driving.
func _axis(neg: String, pos: String) -> float:
	if car.driver == null:
		return 0.0
	return Input.get_action_strength(pos) - Input.get_action_strength(neg)

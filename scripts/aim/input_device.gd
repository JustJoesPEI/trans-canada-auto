class_name InputDevice
extends RefCounted
## Which the player is using right now, a controller or the mouse and
## keyboard: the last one touched wins. The camera passes every input event
## to `note()`; controller-only help (aim assist) asks `controller`.
##
## A stick has to move clearly (past a third of its travel) to count, so a
## resting stick that drifts doesn't take over from the mouse; the mouse
## has to move a couple of pixels, so a knocked desk doesn't either.

## True when a controller was the last thing used.
static var controller := false

const STICK_THRESHOLD := 0.35
const MOUSE_THRESHOLD := 2.0 ## pixels in one event


static func note(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_THRESHOLD:
			controller = true
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			controller = true
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_THRESHOLD:
			controller = false
	elif event is InputEventMouseButton or event is InputEventKey:
		if event.is_pressed():
			controller = false

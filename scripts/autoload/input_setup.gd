extends Node
## Builds the input map in code so every binding lives in one readable place.
##
## Keyboard + mouse and an Xbox-style controller are bound to the same actions.
## Gameplay code only ever asks for action names (e.g. "move_forward"), so a
## rebinding menu can be added later without touching any other script.
## Actions that already exist (for example ones added in the editor's Input Map)
## are left alone.

const DEADZONE := 0.2

# action name -> list of bindings. A binding is one of:
#   {"key": KEY_*}  {"mouse": MOUSE_BUTTON_*}  {"joy_button": JOY_BUTTON_*}
#   {"joy_axis": JOY_AXIS_*, "dir": -1.0 or 1.0}
var _bindings := {
	# On foot
	"move_forward": [{"key": KEY_W}, {"key": KEY_UP}, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": -1.0}],
	"move_back": [{"key": KEY_S}, {"key": KEY_DOWN}, {"joy_axis": JOY_AXIS_LEFT_Y, "dir": 1.0}],
	"move_left": [{"key": KEY_A}, {"key": KEY_LEFT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1.0}],
	"move_right": [{"key": KEY_D}, {"key": KEY_RIGHT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1.0}],
	"run": [{"key": KEY_SHIFT}, {"joy_button": JOY_BUTTON_A}],
	"interact": [{"key": KEY_E}, {"key": KEY_F}, {"joy_button": JOY_BUTTON_Y}],
	"aim": [{"mouse": MOUSE_BUTTON_RIGHT}, {"joy_axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0}], # LT is the brake in a car; aiming is on foot only
	# The paintball marker (on foot, while aiming). RT is the throttle in a
	# car, R works the deck in a truck, X couples: none of those on foot.
	"fire": [{"mouse": MOUSE_BUTTON_LEFT}, {"joy_axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0}],
	"reload": [{"key": KEY_R}, {"joy_button": JOY_BUTTON_X}],
	# Hold for the weapon wheel (on foot or a passenger), on LB as in most
	# open-world games. LB works a truck's deck, but nobody uses the wheel
	# from a truck's driver's seat.
	"weapon_wheel": [{"key": KEY_TAB}, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	# Driver's seat to passenger seat and back, stopped. RB is a working
	# vehicle's deck; those have one seat, so it doesn't switch in them.
	"switch_seat": [{"key": KEY_X}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	# Wipers, in a car: two sweeps clear paint off the windscreen. (On a
	# working vehicle's controller D-pad right also works the tool.)
	"wipers": [{"key": KEY_Q}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	# Driving (used from Milestone 2)
	"accelerate": [{"key": KEY_W}, {"key": KEY_UP}, {"joy_axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0}],
	"brake_reverse": [{"key": KEY_S}, {"key": KEY_DOWN}, {"joy_axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0}],
	"steer_left": [{"key": KEY_A}, {"key": KEY_LEFT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1.0}],
	"steer_right": [{"key": KEY_D}, {"key": KEY_RIGHT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1.0}],
	"handbrake": [{"key": KEY_SPACE}, {"joy_button": JOY_BUTTON_B}],
	# The horn on a click of the left stick, as in most open-world games.
	# (H also works a forklift's tilt or a tow truck's winch: in those it's
	# the controller's left stick only.)
	"horn": [{"key": KEY_H}, {"joy_button": JOY_BUTTON_LEFT_STICK}],
	# Working vehicles: couple a trailer or hook the winch, strap the load
	# down, and work the deck, forks or winch.
	"hitch": [{"key": KEY_T}, {"joy_button": JOY_BUTTON_X}],
	# A strap: A is free in a vehicle, and on foot by a deck a tap of A
	# (run) with the stick still goes nowhere.
	"strap": [{"key": KEY_B}, {"joy_button": JOY_BUTTON_A}],
	"work_up": [{"key": KEY_R}, {"key": KEY_PAGEUP}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	"work_down": [{"key": KEY_G}, {"key": KEY_PAGEDOWN}, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	"aux_in": [{"key": KEY_Y}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	"aux_out": [{"key": KEY_H}, {"joy_button": JOY_BUTTON_DPAD_LEFT}],
	"emergency_lights": [{"key": KEY_L}, {"joy_button": JOY_BUTTON_DPAD_LEFT}], # a police car's lights, then siren, then off
	# Camera
	"camera_left": [{"joy_axis": JOY_AXIS_RIGHT_X, "dir": -1.0}],
	"camera_right": [{"joy_axis": JOY_AXIS_RIGHT_X, "dir": 1.0}],
	"camera_up": [{"joy_axis": JOY_AXIS_RIGHT_Y, "dir": -1.0}],
	"camera_down": [{"joy_axis": JOY_AXIS_RIGHT_Y, "dir": 1.0}],
	# (On a controller, View steps the camera near, far and back instead.)
	"camera_zoom_in": [{"mouse": MOUSE_BUTTON_WHEEL_UP}, {"key": KEY_EQUAL}],
	"camera_zoom_out": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}, {"key": KEY_MINUS}],
	"camera_reset": [{"key": KEY_C}, {"joy_button": JOY_BUTTON_RIGHT_STICK}],
	# V: chase view or driver's seat. View on a controller: on foot, the
	# camera near, far, middle; in a car, near, far, then the driver's seat.
	"camera_view": [{"key": KEY_V}, {"joy_button": JOY_BUTTON_BACK}],
	# Menus
	"pause": [{"key": KEY_ESCAPE}, {"joy_button": JOY_BUTTON_START}],
	# The phone on D-pad up and the map on D-pad down, as in most open-world
	# games (Share also opens the map, and both are in the pause menu).
	"map": [{"key": KEY_M}, {"joy_button": JOY_BUTTON_DPAD_DOWN}, {"joy_button": JOY_BUTTON_MISC1}],
	"phone": [{"key": KEY_P}, {"joy_button": JOY_BUTTON_DPAD_UP}], # your phone: jobs, SpudDash, the garage
	"map_editor": [{"key": KEY_F8}], # opens the map editor in the browser (running from Godot only)
}


func _enter_tree() -> void:
	for action: String in _bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for b: Dictionary in _bindings[action]:
			var ev := _make_event(b)
			if ev != null:
				InputMap.action_add_event(action, ev)


func _make_event(b: Dictionary) -> InputEvent:
	if b.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = b["key"]
		return k
	if b.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = b["mouse"]
		return m
	if b.has("joy_button"):
		var j := InputEventJoypadButton.new()
		j.device = -1
		j.button_index = b["joy_button"]
		return j
	if b.has("joy_axis"):
		var a := InputEventJoypadMotion.new()
		a.device = -1
		a.axis = b["joy_axis"]
		a.axis_value = b["dir"]
		return a
	return null

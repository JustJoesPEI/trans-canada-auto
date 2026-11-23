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
	# Driving (used from Milestone 2)
	"accelerate": [{"key": KEY_W}, {"key": KEY_UP}, {"joy_axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0}],
	"brake_reverse": [{"key": KEY_S}, {"key": KEY_DOWN}, {"joy_axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0}],
	"steer_left": [{"key": KEY_A}, {"key": KEY_LEFT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1.0}],
	"steer_right": [{"key": KEY_D}, {"key": KEY_RIGHT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1.0}],
	"handbrake": [{"key": KEY_SPACE}, {"joy_button": JOY_BUTTON_B}],
	# Camera
	"camera_left": [{"joy_axis": JOY_AXIS_RIGHT_X, "dir": -1.0}],
	"camera_right": [{"joy_axis": JOY_AXIS_RIGHT_X, "dir": 1.0}],
	"camera_up": [{"joy_axis": JOY_AXIS_RIGHT_Y, "dir": -1.0}],
	"camera_down": [{"joy_axis": JOY_AXIS_RIGHT_Y, "dir": 1.0}],
	"camera_zoom_in": [{"mouse": MOUSE_BUTTON_WHEEL_UP}, {"key": KEY_EQUAL}, {"joy_button": JOY_BUTTON_DPAD_UP}],
	"camera_zoom_out": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}, {"key": KEY_MINUS}, {"joy_button": JOY_BUTTON_DPAD_DOWN}],
	"camera_reset": [{"key": KEY_C}, {"joy_button": JOY_BUTTON_RIGHT_STICK}],
	"camera_view": [{"key": KEY_V}, {"joy_button": JOY_BUTTON_BACK}], # chase view or driver's seat
	# Menus
	"pause": [{"key": KEY_ESCAPE}, {"joy_button": JOY_BUTTON_START}],
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

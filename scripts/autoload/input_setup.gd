extends Node
## Builds the input map in code so every binding lives in one readable place.
##
## Keyboard + mouse and an Xbox-style controller are bound to the same actions.
## Gameplay code only ever asks for action names (e.g. "move_forward"), so
## the rebinding page in the Controls menu (KeyBindsPanel) only changes
## things here: each REBIND row's first keyboard or mouse binding can be
## changed, and the change is saved in user://controls.cfg ("keys") and put
## back each time the game starts. The arrow keys and the controller stay
## as they are.
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
	# open-world games; in the driver's seat the same key holds up the
	# vehicle wheel (wipers, lights, hitch, straps, seats, phone, map).
	"weapon_wheel": [{"key": KEY_TAB}, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	# Driver's seat to passenger seat and back, stopped. On a controller the
	# driver does it from the vehicle wheel (RB is the handbrake there); a
	# passenger's RB switches back.
	"switch_seat": [{"key": KEY_X}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	# Wipers, in a car: two sweeps clear paint off the windscreen. (On a
	# controller, from the vehicle wheel: hold LB.)
	"wipers": [{"key": KEY_Q}],
	# Driving (used from Milestone 2)
	"accelerate": [{"key": KEY_W}, {"key": KEY_UP}, {"joy_axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0}],
	"brake_reverse": [{"key": KEY_S}, {"key": KEY_DOWN}, {"joy_axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0}],
	"steer_left": [{"key": KEY_A}, {"key": KEY_LEFT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": -1.0}],
	"steer_right": [{"key": KEY_D}, {"key": KEY_RIGHT}, {"joy_axis": JOY_AXIS_LEFT_X, "dir": 1.0}],
	# RB as in most open-world games, and B as well.
	"handbrake": [{"key": KEY_SPACE}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}, {"joy_button": JOY_BUTTON_B}],
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
	# A working vehicle's tool on the D-pad: up and down the deck, forks or
	# hook, left and right the winch, tilt or reach. (In one, the phone and
	# the map are on the vehicle wheel.)
	"work_up": [{"key": KEY_R}, {"key": KEY_PAGEUP}, {"joy_button": JOY_BUTTON_DPAD_UP}],
	"work_down": [{"key": KEY_G}, {"key": KEY_PAGEDOWN}, {"joy_button": JOY_BUTTON_DPAD_DOWN}],
	"aux_in": [{"key": KEY_Y}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	"aux_out": [{"key": KEY_H}, {"joy_button": JOY_BUTTON_DPAD_LEFT}],
	"emergency_lights": [{"key": KEY_L}], # a police car's lights, then siren, then off (controller: the vehicle wheel)
	# Held in a car on its roof or side, come to rest: puts it back on its
	# wheels (CarRighting). R and A do nothing else in a car that's over.
	"flip_car": [{"key": KEY_R}, {"joy_button": JOY_BUTTON_A}],
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


## What the rebinding page lists: [id (saved under), what it's called, the
## actions it moves together]. Actions that share a key by default share a
## row (W walks forward and accelerates), so they stay together.
const REBIND := [
	["forward", "Walk forward, accelerate", ["move_forward", "accelerate"]],
	["back", "Walk back, brake and reverse", ["move_back", "brake_reverse"]],
	["left", "Walk left, steer left", ["move_left", "steer_left"]],
	["right", "Walk right, steer right", ["move_right", "steer_right"]],
	["run", "Run", ["run"]],
	["interact", "Get in or out, use", ["interact"]],
	["aim", "Aim", ["aim"]],
	["fire", "Fire", ["fire"]],
	["reload", "Reload", ["reload"]],
	["wheel", "Weapon wheel, vehicle wheel", ["weapon_wheel"]],
	["handbrake", "Handbrake", ["handbrake"]],
	["horn", "Horn", ["horn"]],
	["flip", "Flip the car back over (hold)", ["flip_car"]],
	["wipers", "Wipers", ["wipers"]],
	["seat", "Switch seat", ["switch_seat"]],
	["lights", "Police lights and siren", ["emergency_lights"]],
	["hitch", "Hitch, winch hook, tow strap", ["hitch"]],
	["strap", "Strap the load", ["strap"]],
	["work_up", "Deck or forks up", ["work_up"]],
	["work_down", "Deck or forks down", ["work_down"]],
	["aux_in", "Winch in, mast back", ["aux_in"]],
	["aux_out", "Winch out, mast forward", ["aux_out"]],
	["camera_reset", "Reset the camera", ["camera_reset"]],
	["camera_view", "Driver's seat or chase view", ["camera_view"]],
	["map", "Town map", ["map"]],
	["phone", "Phone", ["phone"]],
]
const SAVE_PATH := "user://controls.cfg"
const KEYS_SECTION := "keys"


func _enter_tree() -> void:
	for action: String in _bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for b: Dictionary in _bindings[action]:
			var ev := _make_event(b)
			if ev != null:
				InputMap.action_add_event(action, ev)
	# Godot's own ui_accept and ui_cancel are keyboard only (Enter, Space,
	# Esc): give them A and B, so A presses the focused button in every menu.
	for pair: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		if not InputMap.has_action(pair[0]):
			continue
		var j := _make_event({"joy_button": pair[1]})
		if not InputMap.action_has_event(pair[0], j):
			InputMap.action_add_event(pair[0], j)
	_load_keys()


## The row's binding as it is now: {"key": physical keycode} or
## {"mouse": button}, or {} if it has none.
func binding(id: String) -> Dictionary:
	var row := _row(id)
	if row.is_empty():
		return {}
	var a: String = (row[2] as Array)[0]
	for ev in InputMap.action_get_events(a):
		var b := _describe(ev)
		if not b.is_empty():
			return b
	return {}


## The row's binding as text ("W", "Right mouse button").
func binding_text(id: String) -> String:
	return text_for(binding(id))


static func text_for(b: Dictionary) -> String:
	if b.has("key"):
		# The key's name on this keyboard's layout (an AZERTY Z for W's spot).
		var shown := KEY_NONE
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(int(b["key"]) as Key)
		return OS.get_keycode_string(shown if shown != KEY_NONE else int(b["key"]) as Key)
	if b.has("mouse"):
		match int(b["mouse"]):
			MOUSE_BUTTON_LEFT:
				return "Left mouse button"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse button"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse button"
		return "Mouse button %d" % int(b["mouse"])
	return "(none)"


## Gives row `id` the new binding (from an event: a key or a mouse button),
## in place of its first keyboard or mouse one, and saves it. Returns the
## names of the other rows that use the same key (shared, not taken away:
## many keys do one thing on foot and another in a car).
func rebind(id: String, ev: InputEvent) -> Array[String]:
	var b := _describe(ev)
	var row := _row(id)
	if b.is_empty() or row.is_empty():
		return []
	_apply(row, b)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(KEYS_SECTION, id, b)
	cfg.save(SAVE_PATH)
	return _sharing(id, b)


## Every row back to the keys it started with.
func reset_keys() -> void:
	for row: Array in REBIND:
		var first := {}
		for d: Dictionary in _bindings.get((row[2] as Array)[0], []):
			if d.has("key") or d.has("mouse"):
				first = d
				break
		if not first.is_empty():
			_apply(row, first)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	if cfg.has_section(KEYS_SECTION):
		cfg.erase_section(KEYS_SECTION)
	cfg.save(SAVE_PATH)


func _load_keys() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section(KEYS_SECTION):
		return
	for id: String in cfg.get_section_keys(KEYS_SECTION):
		var b: Variant = cfg.get_value(KEYS_SECTION, id)
		var row := _row(id)
		if b is Dictionary and not row.is_empty() and (b.has("key") or b.has("mouse")):
			_apply(row, b)


## Swaps the first keyboard or mouse binding of each of the row's actions
## for `b` (adds it if the action had none).
func _apply(row: Array, b: Dictionary) -> void:
	for a: String in row[2]:
		if not InputMap.has_action(a):
			continue
		for ev in InputMap.action_get_events(a):
			if not _describe(ev).is_empty():
				InputMap.action_erase_event(a, ev)
				break
		var nev := _make_event(b)
		var rest := InputMap.action_get_events(a)
		InputMap.action_erase_events(a)
		InputMap.action_add_event(a, nev) # first, so it's the one shown
		for ev in rest:
			InputMap.action_add_event(a, ev)


func _sharing(id: String, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row: Array in REBIND:
		if row[0] == id:
			continue
		for a: String in row[2]:
			var hit := false
			for ev in InputMap.action_get_events(a):
				if _describe(ev) == b:
					hit = true
			if hit:
				out.append(str(row[1]))
				break
	return out


static func _row(id: String) -> Array:
	for row: Array in REBIND:
		if row[0] == id:
			return row
	return []


## A key (by its physical place) or a mouse button as a binding; {} for
## anything else (the wheel, the controller).
static func _describe(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return {"key": int(code)} if code != KEY_NONE else {}
	if ev is InputEventMouseButton:
		var m := (ev as InputEventMouseButton).button_index
		if m in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return {}
		return {"mouse": int(m)}
	return {}


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

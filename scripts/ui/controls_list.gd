class_name ControlsList
extends VBoxContainer
## The list of controls at the top of the menu's Controls page: what each
## does, its key and its controller button, read from the input map
## (InputSetup), so a key changed on the keyboard page shows here as it is.
## The developer keys are listed only in developer mode (DevMode).

const GOLD := Color(1.0, 0.84, 0.0)
const TEXT := Color(0.95, 0.92, 0.85)
const DIM := Color(0.95, 0.92, 0.85, 0.7)
## [heading] or [what it does, keyboard, controller]: a keyboard or
## controller entry starting with "@" is an action (or several, joined by
## "+"), named from its first binding; anything else is said as it is.
const ROWS := [
	["On foot"],
	["Walk", "@move_forward+move_left+move_back+move_right", "Left stick"],
	["Run", "@run", "@run"],
	["Look", "Mouse", "Right stick"],
	["Aim, fire", "@aim+fire", "@aim+fire"],
	["Reload", "@reload", "@reload"],
	["Dodge roll", "@dodge", "@dodge"],
	["Weapons (hold)", "@weapon_wheel", "@weapon_wheel"],
	["Get in a car, get out", "@interact", "@interact"],
	["Driving"],
	["Go, brake and reverse", "@accelerate+brake_reverse", "@accelerate+brake_reverse"],
	["Steer", "@steer_left+steer_right", "Left stick"],
	["Handbrake", "@handbrake", "@handbrake"],
	["Horn", "@horn", "@horn"],
	["Lights, wipers, seats (hold)", "@weapon_wheel", "@weapon_wheel"],
	["Driver's seat or chase view", "@camera_view", "@camera_view"],
	["Put the car back on its wheels (hold)", "@flip_car", "@flip_car"],
	["Anywhere"],
	["Phone: jobs, SpudDash, the garage", "@phone", "@phone"],
	["Town map", "@map", "@map"],
	["Zoom the camera", "Mouse wheel", "@camera_view"],
	["Reset the camera", "@camera_reset", "@camera_reset"],
	["This menu", "@pause", "@pause"],
]
## Shown in developer mode only (DevMode has what each does).
const DEV_ROWS := [
	["Developer keys"],
	["Frame rate and draw calls", "F3", ""],
	["Every weapon, hoppers full", "F11", ""],
	["Wanted level up, down (Shift)", "F5", ""],
	["A cop watching, getting caught", "F7, F4", ""],
	["Aim practice dummy (Ctrl clears)", "F6", ""],
	["Note about this spot, notes folder", "N, F9", ""],
	["Graphics, step through", "F10", ""],
	["Map editor (from Godot)", "F8", ""],
]

var _grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	refresh()


## Rebuilds the list from the bindings as they are now: one grid, so the
## columns line up from section to section.
func refresh() -> void:
	for c in get_children():
		c.queue_free()
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 3)
	add_child(_grid)
	_cells("", "Keyboard", "Controller", 16, DIM)
	for r: Array in ROWS + (DEV_ROWS if DevMode.on() else []):
		if r.size() == 1:
			_cells(str(r[0]), "", "", 22, GOLD)
			continue
		_cells(str(r[0]), _say(str(r[1]), false), _say(str(r[2]), true), 19, TEXT)


func _cells(a: String, b: String, c: String, size: int, colour: Color) -> void:
	var widths := [300.0, 200.0, 150.0]
	var texts := [a, b, c]
	for i in 3:
		var l := _label(texts[i], size, colour if i == 0 or colour != GOLD else TEXT)
		l.custom_minimum_size = Vector2(widths[i], 0)
		if colour == GOLD:
			l.size_flags_vertical = Control.SIZE_SHRINK_END
			l.custom_minimum_size.y = 40
		_grid.add_child(l)


## An entry as words: actions by their first key or button, else as it is.
static func _say(entry: String, pad: bool) -> String:
	if not entry.begins_with("@"):
		return entry
	var names: Array[String] = []
	for action in entry.substr(1).split("+"):
		var n := _name(action, pad)
		if n != "" and not names.has(n):
			names.append(n)
	return (" " if names.size() == 4 and not pad else ", ").join(names)


## The first keyboard or mouse binding of `action` (or controller one, for
## `pad`), in words.
static func _name(action: String, pad: bool) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if pad:
			if ev is InputEventJoypadButton:
				return Hud.PAD_BUTTONS.get((ev as InputEventJoypadButton).button_index, "")
			if ev is InputEventJoypadMotion:
				var axis := (ev as InputEventJoypadMotion).axis
				if Hud.PAD_AXES.has(axis):
					return Hud.PAD_AXES[axis]
		elif ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		elif ev is InputEventMouseButton:
			return Hud.MOUSE_BUTTONS.get((ev as InputEventMouseButton).button_index, "Mouse wheel")
	return ""


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l

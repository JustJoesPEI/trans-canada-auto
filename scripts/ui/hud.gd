class_name Hud
extends CanvasLayer
## Minimal on-screen information:
##   * the street you are on (top left),
##   * a short controls reminder that fades after a while,
##   * a prompt when there's something to use, like "E  Get in" (bottom centre),
##   * your speed in km/h while driving (bottom right),
##   * a crosshair while aiming (centre),
##   * the wanted level (top centre) and the search circle (WantedHud),
##   * the OpenStreetMap credit the map data requires (bottom right).
## Money, minimap and mission text join this in a later milestone.

const HELP_TEXT := "WASD / left stick: walk    Shift / A: run    Right mouse / LT: aim    Mouse / right stick: look    E / Y: get in or out of the car\nDriving: W / RT go, S / LT brake and reverse, Space / B handbrake, H / A horn, V / Back driver's seat view    Wheel / D-pad: zoom    C: reset camera    N: leave a note    Esc: menu"

var _world: WorldBuilder
var _player: Node3D
var _street: Label
var _help: Label
var _timer := 0.0
var _help_time := 14.0
var _prompt_panel: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _speed_panel: PanelContainer
var _speed: Label
var _title: Label
var _subtitle: Label
var _title_time := 0.0
var _gear: Label
var _card: PanelContainer
var _card_rows: VBoxContainer
var _card_status: Label
var _crosshair: Control
var _card_key := "" # what the card shows now, so it's only rebuilt on a change
## The player last used a controller (true) or the keyboard and mouse.
var pad := false
## The wanted level, the search circle and the car wash's suds bar.
var wanted_hud: WantedHud


func _ready() -> void:
	_street = _label(22, Control.PRESET_TOP_LEFT, Vector2(24, 18))
	_help = _label(15, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24))
	_help.text = HELP_TEXT
	var credit := _label(12, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -28))
	credit.text = "Map data © OpenStreetMap contributors. Elevation: NRCan HRDEM, Open Government Licence – Canada"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.modulate.a = 0.8
	_build_prompt()
	_build_speed()
	_build_card()
	_build_crosshair()
	_title = _label(34, Control.PRESET_CENTER_TOP, Vector2(0, 70))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle = _label(17, Control.PRESET_CENTER_TOP, Vector2(0, 116))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wanted_hud = WantedHud.new()
	add_child(wanted_hud)


## A title across the top of the screen for a few seconds, e.g. the car's
## name when you get in.
func show_title(title: String, subtitle := "") -> void:
	_title.text = title
	_subtitle.text = subtitle
	_title_time = 3.5


## Moves the titles down to start at `y` (px from the top), out from under
## the wanted level; negative puts them back.
func set_title_top(y: float) -> void:
	var top := 70.0 if y < 0.0 else y
	_title.position.y = top
	_subtitle.position.y = top + 46.0


## Show a prompt like "E  Get in", or hide it with an empty text.
func set_prompt(key: String, text: String) -> void:
	_prompt_panel.visible = text != ""
	_prompt_key.text = key
	_prompt_text.text = text


## Fade the crosshair in (1) or out (0), with the aim.
func set_crosshair(amount: float) -> void:
	_crosshair.visible = amount > 0.01
	_crosshair.modulate.a = amount


## Show the speedometer (km/h) and the gear ("4", "R"), or hide it with
## a negative speed.
func set_speed(kmh: float, gear := "") -> void:
	_speed_panel.visible = kmh >= 0.0
	if kmh >= 0.0:
		_speed.text = "%d  km/h" % roundi(kmh)
		_gear.text = gear
		_gear.visible = gear != ""


## The key (or controller button) for an action, as the player would
## press it now: "T", "Page Up", "RB", "X".
func key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return action
	for ev in InputMap.action_get_events(action):
		if pad:
			if ev is InputEventJoypadButton:
				return PAD_BUTTONS.get((ev as InputEventJoypadButton).button_index, "?")
			if ev is InputEventJoypadMotion:
				var m := ev as InputEventJoypadMotion
				return PAD_AXES.get(m.axis, "Stick")
		elif ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			return "Wheel"
	return "?"


## Xbox-style names for the buttons.
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu",
}
const PAD_AXES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}


## The controls card for a working vehicle: rows of [actions, what they do]
## (two actions read "R / G"), or [actions, what, "pad"] for a row shown
## only to controller players, and a status line under them. An empty list
## hides it.
func set_controls(rows: Array, status := "") -> void:
	_card.visible = not rows.is_empty()
	if rows.is_empty():
		_card_key = ""
		return
	var key := "%s|%s" % [str(rows), str(pad)]
	if key != _card_key:
		_card_key = key
		for c in _card_rows.get_children():
			c.queue_free()
		for r: Array in rows:
			if r.size() > 2 and str(r[2]) == "pad" and not pad:
				continue # on the keyboard that key does something else here
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			var keys: Array = r[0]
			var names: Array[String] = []
			for a: String in keys:
				names.append(key_for(a))
			var k := Label.new()
			k.text = " / ".join(names)
			if names.size() == 2 and names[0].begins_with("D-pad ") and names[1].begins_with("D-pad "):
				k.text = "%s / %s" % [names[0], names[1].trim_prefix("D-pad ")]
			k.custom_minimum_size.x = 150 if pad else 92
			k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			k.add_theme_font_size_override("font_size", 16)
			k.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
			line.add_child(k)
			var t := Label.new()
			t.text = str(r[1])
			t.add_theme_font_size_override("font_size", 16)
			line.add_child(t)
			_card_rows.add_child(line)
	_card_status.text = status
	_card_status.visible = status != ""


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.68)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override("panel", _panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_prompt_panel.add_child(row)
	_prompt_key = Label.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(0.95, 0.94, 0.9)
	key_style.set_corner_radius_all(5)
	key_style.content_margin_left = 9
	key_style.content_margin_right = 9
	_prompt_key.add_theme_stylebox_override("normal", key_style)
	_prompt_key.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_prompt_key.add_theme_font_size_override("font_size", 20)
	row.add_child(_prompt_key)
	_prompt_text = Label.new()
	_prompt_text.add_theme_font_size_override("font_size", 20)
	row.add_child(_prompt_text)
	add_child(_prompt_panel)
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.position.y -= 90
	_prompt_panel.visible = false


func _build_speed() -> void:
	_speed_panel = PanelContainer.new()
	_speed_panel.add_theme_stylebox_override("panel", _panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_speed_panel.add_child(row)
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 30)
	row.add_child(_speed)
	_gear = Label.new()
	_gear.add_theme_font_size_override("font_size", 22)
	_gear.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gear)
	add_child(_speed_panel)
	_speed_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_speed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed_panel.position += Vector2(-24, -56)
	_speed_panel.visible = false


## A small ring and dot in the middle of the screen, outlined so it shows
## on sky and on snow.
func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.visible = false
	_crosshair.draw.connect(func() -> void:
		var dark := Color(0, 0, 0, 0.55)
		var light := Color(1, 1, 1, 0.9)
		_crosshair.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 32, dark, 3.5, true)
		_crosshair.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 32, light, 1.5, true)
		_crosshair.draw_circle(Vector2.ZERO, 2.6, dark)
		_crosshair.draw_circle(Vector2.ZERO, 1.6, light))
	add_child(_crosshair)


## The controls card, down the left side above the help line.
func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _panel_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_card.add_child(col)
	_card_rows = VBoxContainer.new()
	_card_rows.add_theme_constant_override("separation", 2)
	col.add_child(_card_rows)
	_card_status = Label.new()
	_card_status.add_theme_font_size_override("font_size", 16)
	_card_status.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0))
	col.add_child(_card_status)
	add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.position += Vector2(24, 60)
	_card.visible = false


func setup(world: WorldBuilder, player: Node3D) -> void:
	_world = world
	_player = player


func _process(delta: float) -> void:
	_title_time -= delta
	var ta := clampf(_title_time / 0.6, 0.0, 1.0)
	_title.modulate.a = ta
	_subtitle.modulate.a = ta * 0.85
	_help_time -= delta
	if _help_time < 2.0:
		_help.modulate.a = clampf(_help_time / 2.0, 0.0, 1.0)
	_timer -= delta
	if _timer > 0.0 or _world == null or _player == null or not _world.is_built:
		return
	_timer = 0.25
	var p := _player.global_position
	_street.text = _world.street_name_at(Vector2(p.x, p.z))


func _label(size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	# Grow away from the screen edge the label is pinned to.
	if preset == Control.PRESET_BOTTOM_RIGHT:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_BOTTOM_RIGHT or preset == Control.PRESET_BOTTOM_LEFT:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	l.position += offset
	return l

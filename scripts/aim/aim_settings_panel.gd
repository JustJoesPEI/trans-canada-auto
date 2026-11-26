class_name AimSettingsPanel
extends VBoxContainer
## The settings in the Controls menu: the mouse (sensitivity, inverted
## looking), the way to the keyboard page (KeyBindsPanel), and the
## controller: aim assist, response curve, look and aim sensitivity, and the
## deadzones (AimSettings). Every change is saved straight away. Works with
## a controller: up and down move between rows, left and right move a slider.

## The "Change keys" button: the menu swaps this page for the keyboard one.
signal keys_requested

const ROW_WIDTH := 560.0

var _invert: Button
var _keys: Button
var _assist: Button
var _curve: Button
var _sliders := {} ## setting name -> HSlider
var _values := {} ## setting name -> Label


func _ready() -> void:
	AimSettings.ensure_loaded()
	add_theme_constant_override("separation", 8)
	var mouse := _label("Mouse and keyboard", 22)
	mouse.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	add_child(mouse)
	_slider("mouse_sensitivity", "Mouse sensitivity", AimSettings.MOUSE_MIN, AimSettings.MOUSE_MAX, 0.05)
	_invert = _button(_toggle_invert)
	_keys = _button(func() -> void: keys_requested.emit())
	_keys.text = "Change keys..."
	var title := _label("Controller", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	add_child(title)
	_assist = _button(_next_assist)
	_curve = _button(_next_curve)
	_slider("look_sensitivity", "Look sensitivity", AimSettings.SENSITIVITY_MIN, AimSettings.SENSITIVITY_MAX, 0.05)
	_slider("aim_sensitivity", "Aim sensitivity", AimSettings.SENSITIVITY_MIN, AimSettings.SENSITIVITY_MAX, 0.05)
	_slider("inner_deadzone", "Inner deadzone", 0.0, AimSettings.INNER_MAX, 0.01)
	_slider("outer_deadzone", "Outer deadzone", 0.0, AimSettings.OUTER_MAX, 0.01)
	_button(_reset).text = "Reset mouse and controller settings"
	refresh()


## Show the current values.
func refresh() -> void:
	_invert.text = "Look up and down: %s" % ("inverted" if AimSettings.invert_y else "normal")
	_assist.text = "Aim assist: %s" % AimSettings.assist_label()
	_curve.text = "Response curve: %s" % AimSettings.curve_label()
	for key: String in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(AimSettings.get_number(key))
		_show_value(key)


## The first control, for focusing from the menu.
func first() -> Control:
	return _invert


func _toggle_invert() -> void:
	AimSettings.invert_y = not AimSettings.invert_y
	AimSettings.save()
	refresh()


func _next_assist() -> void:
	AimSettings.assist = ((AimSettings.assist + 1) % 3) as AimSettings.Assist
	AimSettings.save()
	refresh()


func _next_curve() -> void:
	AimSettings.curve = AimSettings.Response.LINEAR if AimSettings.curve == AimSettings.Response.EXPONENTIAL else AimSettings.Response.EXPONENTIAL
	AimSettings.save()
	refresh()


func _reset() -> void:
	AimSettings.reset_defaults()
	AimSettings.save()
	refresh()


func _changed(v: float, key: String) -> void:
	AimSettings.set_number(key, v)
	AimSettings.save()
	_show_value(key)


func _show_value(key: String) -> void:
	var v := AimSettings.get_number(key)
	(_values[key] as Label).text = ("%d%%" % roundi(v * 100.0)) if key.ends_with("deadzone") else ("%.2f" % v)


func _slider(key: String, text: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, 36)
	row.add_theme_constant_override("separation", 12)
	var name_label := _label(text, 20)
	name_label.custom_minimum_size = Vector2(200, 0)
	row.add_child(name_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(240, 24)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(_changed.bind(key))
	row.add_child(s)
	var value := _label("", 20)
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	add_child(row)
	_sliders[key] = s
	_values[key] = value


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


## A button in the menu's style (black box, red when picked), a size down.
func _button(action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(ROW_WIDTH, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.03, 0.03, 0.92)
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.84, 0.17, 0.12, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	add_child(b)
	return b

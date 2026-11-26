class_name KeyBindsPanel
extends VBoxContainer
## The keyboard and mouse page of the Controls menu: every row of
## InputSetup.REBIND with its key, and a click (or A) on a row to change it:
## the next key or mouse button pressed takes its place, Esc keeps the old
## one. Saved straight away (InputSetup.rebind). A key can do more than one
## thing (H is the horn, and the winch in a tow truck), so a key already in
## use isn't taken from the other row; the page just says which rows share it.

signal closed

const ROW_WIDTH := 560.0

var _buttons := {} ## row id -> Button
var _note: Label
var _waiting := "" ## the row waiting for a key, or ""
var _back: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var title := _label("Keyboard and mouse", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	add_child(title)
	_note = _label("Pick a row, then press the new key or mouse button. Esc keeps the old one.", 16)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	add_child(_note)
	_back = _button("Back to the other settings", func() -> void:
		_waiting = ""
		closed.emit())
	for row: Array in InputSetup.REBIND:
		var id: String = row[0]
		var b := _button("", _start.bind(id))
		_buttons[id] = b
	_button("Put every key back the way it was", func() -> void:
		_waiting = ""
		InputSetup.reset_keys()
		_note.text = "Every key is back the way it started."
		refresh())
	refresh()


func refresh() -> void:
	for row: Array in InputSetup.REBIND:
		var id: String = row[0]
		var shown := "press a key..." if id == _waiting else InputSetup.binding_text(id)
		(_buttons[id] as Button).text = "%s:  %s" % [str(row[1]), shown]


## The first control, for focusing from the menu.
func first() -> Control:
	return _back


func _start(id: String) -> void:
	_waiting = id
	_note.text = "Press the new key or mouse button for \"%s\". Esc keeps the old one." % _name(id)
	refresh()


func _input(event: InputEvent) -> void:
	if _waiting == "" or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if key != null and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			_note.text = "Kept as it was."
			_finish()
			return
		_take(event)
	elif mouse != null and mouse.pressed and not mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		get_viewport().set_input_as_handled()
		_take(event)


func _take(event: InputEvent) -> void:
	var id := _waiting
	var shared := InputSetup.rebind(id, event)
	_note.text = "%s: %s." % [_name(id), InputSetup.binding_text(id)]
	if not shared.is_empty():
		_note.text += " The same key also does: %s." % ", ".join(shared)
	_finish()


func _finish() -> void:
	var id := _waiting
	_waiting = ""
	refresh()
	# Keep the focus on the row (the click that picked it mustn't press it again).
	if _buttons.has(id):
		(_buttons[id] as Button).call_deferred("grab_focus")


func _name(id: String) -> String:
	for row: Array in InputSetup.REBIND:
		if row[0] == id:
			return str(row[1])
	return id


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


## A button in the menu's style (black box, red when picked), as in
## AimSettingsPanel, a touch smaller so the list fits.
func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(ROW_WIDTH, 34)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
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

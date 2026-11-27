class_name ConfirmBox
extends Control
## An "are you sure?" box over the menu: a title, a line, and two buttons
## (the one that does it, and the one that doesn't). The one that doesn't
## has the focus to start with, and Esc (or B) is the same as it, so a
## stray press never quits the game or throws away a setting. Same look as
## the menu: black boxes, red when picked.
##
##   ConfirmBox.ask(parent, "Quit the game?", "A line under it.", "Quit", "Stay", func(): ...)

const GOLD := Color(1.0, 0.84, 0.0)
const TEXT := Color(0.95, 0.92, 0.85)

var _yes_action: Callable
var _no_action: Callable
var _no: Button


## Puts a box over `parent` (a full-screen Control or a CanvasLayer) and
## calls `on_yes` if the first button is pressed (`on_no`, if given, for
## the second). `focus_yes` starts on the first button instead, for a box
## that's news rather than a question (the welcome). Returns the box.
static func ask(parent: Node, title: String, line: String, yes_text: String, no_text: String, on_yes: Callable,
		on_no := Callable(), focus_yes := false) -> ConfirmBox:
	var box := ConfirmBox.new()
	box._yes_action = on_yes
	box._no_action = on_no
	parent.add_child(box)
	box._build(title, line, yes_text, no_text, focus_yes)
	return box


## Where a box over `n` goes: its CanvasLayer (so it's over the menu `n`
## is in), or the window.
static func host(n: Node) -> Node:
	var p := n
	while p != null and not p is CanvasLayer:
		p = p.get_parent()
	return p if p != null else n.get_tree().root


func _build(title: String, line: String, yes_text: String, no_text: String, focus_yes: bool) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.03, 0.96)
	style.border_color = Color(0.98, 0.98, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(_label(title, 28, GOLD))
	if line != "":
		var l := _label(line, 20, TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560 if line.length() > 160 else 460, 0)
		column.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	var yes := _button(yes_text, func() -> void:
		queue_free()
		_yes_action.call())
	row.add_child(yes)
	_no = _button(no_text, func() -> void:
		queue_free()
		if _no_action.is_valid():
			_no_action.call())
	row.add_child(_no)
	(yes if focus_yes else _no).grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	# Over everything else while it's up: Esc closes the box, not the menu.
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 46)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.03, 0.03, 0.92)
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.84, 0.17, 0.12, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	return b

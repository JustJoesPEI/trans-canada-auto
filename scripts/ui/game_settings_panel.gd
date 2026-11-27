class_name GameSettingsPanel
extends VBoxContainer
## The Settings page of the menu (TitleMenu): the graphics setting (Low,
## Medium or High, picked from three, with what each is for), the volume,
## the frame rate counter, and, once developer mode is on (DevMode), the
## switch to turn it off. Every change is saved straight away. Works with a
## controller: up and down between rows, left and right on the slider and
## the graphics row. Same look as AimSettingsPanel beside it.

const ROW_WIDTH := 560.0
const GOLD := Color(1.0, 0.84, 0.0)
const TEXT := Color(0.95, 0.92, 0.85)
## What each setting is for, under the three buttons (Graphics.Level order).
const LEVEL_NOTES := [
	"For laptops and older computers. Plainer buildings, a shorter view. Still the Island.",
	"For a modest graphics card. Most of the look, a little less far.",
	"Everything, as far as it goes. Your fan will let you know.",
]

var _levels: Array[Button] = []
var _level_note: Label
var _restart_note: Label
var _volume: HSlider
var _volume_value: Label
var _fps: Button
var _dev_title: Label
var _dev: Button
## The graphics level when the game started: Low's plainer buildings are
## chosen then (Graphics), so a switch to or from Low says so.
var _started_low := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var g := _graphics()
	_started_low = g != null and int(g.get("level")) == 0
	add_child(_heading("Graphics"))
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, 44)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for l in 3:
		var b := _button(_set_level.bind(l), (ROW_WIDTH - 20.0) / 3.0)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.text = ["Low", "Medium", "High"][l]
		b.toggle_mode = true
		# The one chosen is red; the one the mouse or controller is on gets
		# a gold edge, so the two never look alike.
		var on := b.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		on.border_color = GOLD
		b.add_theme_stylebox_override("hover", on)
		b.add_theme_stylebox_override("focus", on)
		row.add_child(b)
		_levels.append(b)
	_level_note = _label("", 18)
	_level_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_note.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	add_child(_level_note)
	_restart_note = _label("The plainer buildings come and go the next time you start the game.", 18)
	_restart_note.add_theme_color_override("font_color", GOLD)
	_restart_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_restart_note.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	add_child(_restart_note)
	_fps = _button(_toggle_fps)
	add_child(_fps)
	add_child(_heading("Sound"))
	var vrow := HBoxContainer.new()
	vrow.custom_minimum_size = Vector2(ROW_WIDTH, 36)
	vrow.add_theme_constant_override("separation", 12)
	add_child(vrow)
	var vname := _label("Volume", 20)
	vname.custom_minimum_size = Vector2(200, 0)
	vrow.add_child(vname)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.custom_minimum_size = Vector2(240, 24)
	_volume.focus_mode = Control.FOCUS_ALL
	_volume.value_changed.connect(_set_volume)
	vrow.add_child(_volume)
	_volume_value = _label("", 20)
	_volume_value.custom_minimum_size = Vector2(64, 0)
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vrow.add_child(_volume_value)
	_dev_title = _heading("Developer")
	add_child(_dev_title)
	_dev = _button(func() -> void:
		ConfirmBox.ask(ConfirmBox.host(self), "Turn developer mode off?",
			"The developer keys stop working. Seven clicks on the version number turn it back on.",
			"Turn off", "Leave on", func() -> void:
				DevMode.set_on(false)
				refresh()))
	add_child(_dev)
	refresh()


## Show the current values.
func refresh() -> void:
	var g := _graphics()
	var level := int(g.get("level")) if g != null else 2
	for l in _levels.size():
		_levels[l].set_pressed_no_signal(l == level)
	_level_note.text = LEVEL_NOTES[level]
	_restart_note.visible = (level == 0) != _started_low
	_fps.text = "Frame rate counter: %s" % ("on" if g != null and bool(g.call("stats_shown")) else "off")
	var s := get_tree().root.get_node_or_null("Sound") if is_inside_tree() else null
	var v := float(s.get("volume")) if s != null else 1.0
	_volume.set_value_no_signal(v)
	_volume_value.text = "%d%%" % roundi(v * 100.0)
	_dev_title.visible = DevMode.on()
	_dev.visible = DevMode.on()
	_dev.text = "Developer mode: on (turn off)"


## The first control, for focusing from the menu.
func first() -> Control:
	return _levels[0]


func _graphics() -> Node:
	return get_tree().root.get_node_or_null("Graphics") if is_inside_tree() else null


func _set_level(l: int) -> void:
	var g := _graphics()
	if g == null or int(g.get("level")) == l:
		refresh()
		return
	if (l == 0) == (int(g.get("level")) == 0):
		_apply_level(l) # Medium and High: all at once, nothing to warn about
		return
	refresh() # the old one stays lit until it's agreed
	var to: String = ["Low", "Medium", "High"][l]
	ConfirmBox.ask(ConfirmBox.host(self), "Switch to %s?" % to,
		"Most of it changes now. The %s buildings come in the next time you start the game." % ("plainer" if l == 0 else "detailed"),
		"Switch", "Cancel", _apply_level.bind(l))


func _apply_level(l: int) -> void:
	var g := _graphics()
	if g != null:
		g.call("set_level", l)
	refresh()


func _toggle_fps() -> void:
	var g := _graphics()
	if g != null:
		g.call("set_stats", not bool(g.call("stats_shown")))
	refresh()


func _set_volume(v: float) -> void:
	var s := get_tree().root.get_node_or_null("Sound")
	if s != null:
		s.call("set_volume", v)
	_volume_value.text = "%d%%" % roundi(v * 100.0)


func _heading(text: String) -> Label:
	var l := _label(text, 22)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


## A button in the menu's style (black box, red when picked or chosen).
func _button(action: Callable, width := ROW_WIDTH) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.03, 0.03, 0.92)
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.84, 0.17, 0.12, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.pressed.connect(action)
	return b

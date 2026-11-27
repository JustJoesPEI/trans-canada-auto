class_name CaptionBar
extends Control
## Who's talking and what they said, bottom centre over the prompt: the
## speaker's name in gold Bebas, the line in big outlined white typing on
## quickly, on the HUD's dark panel. Two ways to say something:
##
##   say(name, text)            a line you read and move on from (any key
##                              shows it all, the next press moves on);
##                              `finished` once it's dismissed
##   mumble(name, text, secs)   a line said in passing: no key, it goes by
##                              itself, smaller (Tenner while you drive)
##
## A mumble never covers a line you have to dismiss.

signal finished

const TYPE_RATE := 70.0 ## characters a second
const WIDTH := 820.0 ## at 1080 px tall

var _panel: PanelContainer
var _name: Label
var _text: Label
var _hint: Label
var _full := ""
var _shown := 0.0
var _waiting := false ## a line to dismiss
var _left := 0.0 ## s left of a mumble
var _fade := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var sb := HudStyle.panel(HudStyle.ACCENT)
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.86)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_name = HudStyle.label(24, true, HudStyle.ACCENT, false)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	_hint = HudStyle.label(15, false, HudStyle.DIM, false)
	head.add_child(_hint)
	_text = HudStyle.label(28, false, Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	visible = false
	get_viewport().size_changed.connect(_place)


func say(who: String, text: String) -> void:
	_start(who, text)
	_waiting = true
	_hint.text = "%s  next" % _key()
	_text.add_theme_font_size_override("font_size", int(28 * _k()))


func mumble(who: String, text: String, secs := 4.5) -> void:
	if _waiting:
		return
	_start(who, text)
	_left = secs
	_hint.text = ""
	_text.add_theme_font_size_override("font_size", int(24 * _k()))


func is_waiting() -> bool:
	return _waiting


func hide_now() -> void:
	_waiting = false
	_left = 0.0
	visible = false


func _start(who: String, text: String) -> void:
	_name.text = who
	_full = text
	_shown = 0.0
	_text.text = ""
	_fade = 1.0
	visible = true
	modulate.a = 1.0
	_place()


func _key() -> String:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("key_for"):
		return "[%s]" % str(hud.call("key_for", "interact"))
	return "[E]"


func _k() -> float:
	return maxf(0.6, get_viewport_rect().size.y / 1080.0)


func _place() -> void:
	if _panel == null:
		return
	var vs := get_viewport_rect().size
	var k := _k()
	_name.add_theme_font_size_override("font_size", int(24 * k))
	_hint.add_theme_font_size_override("font_size", int(15 * k))
	var w := minf(WIDTH * k, vs.x - 32.0)
	_panel.custom_minimum_size = Vector2(w, 0)
	_panel.size = Vector2(w, 0)
	_panel.reset_size()
	_panel.position = Vector2((vs.x - w) * 0.5, vs.y * 0.86 - _panel.size.y)


func _process(delta: float) -> void:
	if not visible:
		return
	if _shown < _full.length():
		_shown = minf(_full.length(), _shown + TYPE_RATE * delta)
		_text.text = _full.substr(0, int(_shown))
		_place()
	if not _waiting:
		_left -= delta
		if _left < 0.4:
			modulate.a = maxf(0.0, _left / 0.4)
		if _left <= 0.0:
			visible = false


## The interact key (or Enter, Space, A): show it all, then move on.
func _input(event: InputEvent) -> void:
	if not _waiting or not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _shown < _full.length():
			_shown = _full.length()
			_text.text = _full
			_place()
			return
		_waiting = false
		visible = false
		finished.emit()

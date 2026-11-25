class_name CounterMenu
extends CanvasLayer
## The card a counter shows (Counters): its name, a list of things with
## prices, your money, and a line for what just happened. Up and down (W S,
## arrows, D-pad, stick) pick, the interact key, Enter, Space or A buys,
## Esc, Tab or B closes; the mouse works too. While it's up the player
## can't walk, and a car's controls are held (a drive-thru).

signal chosen(counter_id: String, item: Dictionary)
signal closed

const LAYER := 65
const WIDTH := 460.0

var counter_id := ""
var items: Array = []
var selected := 0
var _player: Node3D
var _held_car: Object
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _list: VBoxContainer
var _money: Label
var _message: Label
var _hint: Label
var _rows: Array[PanelContainer] = []
var _opened_frame := 0


func _ready() -> void:
	layer = LAYER
	visible = false
	_panel = PanelContainer.new()
	var sb := HudStyle.panel(HudStyle.ACCENT)
	sb.bg_color = Color(0.07, 0.08, 0.09, 0.94)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size.x = WIDTH
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = HudStyle.label(34, true, Color.WHITE, false)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_money = HudStyle.label(24, true, Color(0.93, 0.97, 0.9), false)
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_money)
	_subtitle = HudStyle.label(15, false, HudStyle.DIM, false)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	col.add_child(_list)
	_message = HudStyle.label(16, false, HudStyle.ACCENT, false)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_message)
	_hint = HudStyle.label(13, false, HudStyle.DIM, false)
	col.add_child(_hint)
	get_viewport().size_changed.connect(_place)


func open(id: String, title: String, subtitle: String, list: Array, who: Node3D) -> void:
	counter_id = id
	_player = who
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	_message.text = ""
	selected = 0
	set_items(list)
	visible = true
	_opened_frame = Engine.get_process_frames()
	_hold(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_place.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	counter_id = ""
	_hold(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## Shows a line under the list ("Bought a tow strap.").
func say(text: String) -> void:
	_message.text = text


func set_items(list: Array) -> void:
	items = list
	selected = clampi(selected, 0, maxi(0, items.size() - 1))
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in items.size():
		var it: Dictionary = items[i]
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", -2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(texts)
		var on := bool(it.get("enabled", true))
		var name := HudStyle.label(19, false, Color.WHITE if on else Color(1, 1, 1, 0.45), false)
		name.text = str(it.get("name", "?"))
		texts.add_child(name)
		if str(it.get("note", "")) != "":
			var note := HudStyle.label(14, false, HudStyle.DIM if on else Color(1, 1, 1, 0.35), false)
			note.text = str(it["note"])
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = WIDTH - 150.0
			texts.add_child(note)
		var price := HudStyle.label(20, true, HudStyle.ACCENT if on else Color(1, 1, 1, 0.4), false)
		var p := int(it.get("price", 0))
		price.text = (CarModels.dollars(p) if p > 0 else ("Free" if p == 0 else "")) if on else str(it.get("why_short", "—"))
		if on and it.has("price_text"):
			price.text = str(it["price_text"]) # what a job pays, say

		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(price)
		var idx := i
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				selected = idx
				_restyle()
				_choose()
			elif e is InputEventMouseMotion:
				if selected != idx:
					selected = idx
					_restyle())
		_list.add_child(row)
		_rows.append(row)
	if items.is_empty():
		var none := HudStyle.label(16, false, HudStyle.DIM, false)
		none.text = "Nothing here right now."
		var row := PanelContainer.new()
		row.add_child(none)
		_list.add_child(row)
		_rows.append(row)
	_restyle()
	_place.call_deferred()


func _restyle() -> void:
	for i in _rows.size():
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.bg_color = Color(HudStyle.ACCENT, 0.18) if i == selected and not items.is_empty() else Color(1, 1, 1, 0.04)
		_rows[i].add_theme_stylebox_override("panel", sb)
	var gs := get_tree().root.get_node_or_null("GameState")
	_money.text = CarModels.dollars(int(gs.get("money"))) if gs != null else ""
	_hint.text = "%s choose  ·  %s close" % [_key("interact"), "Esc"]


func _key(action: String) -> String:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("key_for"):
		return str(hud.call("key_for", action))
	return "E"


func _place() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	_panel.size = Vector2.ZERO
	var s := _panel.get_combined_minimum_size()
	_panel.position = Vector2(vp.x - s.x - 60.0, (vp.y - s.y) * 0.5)


func _choose() -> void:
	if items.is_empty() or selected >= items.size():
		return
	chosen.emit(counter_id, items[selected])
	_restyle()


func _hold(on: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var car: Variant = _player.get("vehicle")
	if on:
		if car is Object and (car as Object).get("controls_held") != null:
			_held_car = car
			(car as Object).set("controls_held", true)
		else:
			_player.set("input_enabled", false)
	else:
		if _held_car != null and is_instance_valid(_held_car):
			_held_car.set("controls_held", false)
		_held_car = null
		if _player.get("vehicle") == null:
			_player.set("input_enabled", true)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# The press that opened it shouldn't also buy.
	if Engine.get_process_frames() == _opened_frame:
		return
	var handled := true
	if event.is_action_pressed("pause") or event.is_action_pressed("weapon_wheel") or (event is InputEventJoypadButton and event.is_pressed() and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B):
		close()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		selected = posmod(selected - 1, maxi(1, items.size()))
		_restyle()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		selected = posmod(selected + 1, maxi(1, items.size()))
		_restyle()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_choose()
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		handled = false
	elif event is InputEventKey or event is InputEventJoypadButton:
		pass # swallow the rest: no walking off, firing or honking at the till
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

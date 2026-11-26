class_name Phone
extends CanvasLayer
## Your phone: P or the controller's D-pad up (or Phone in the pause menu,
## or the vehicle wheel; in a working vehicle the D-pad works the tool)
## brings it up in the bottom right of the screen, and P, Esc or the
## controller's B puts it away (B in an app goes back to the home screen
## first; with it out, the D-pad moves between its buttons). The home screen is a grid of
## apps: the Map (opens the town map), and whatever the money side adds
## with add_app (Jobs, SpudDash, Garage...). An app is a builder: `build`
## is called with an empty VBoxContainer each time the app is shown, and
## again on refresh(), to fill it. Use make_button for buttons in it, so
## they work with the mouse and, on a controller, with the D-pad and A.
##
## The game is paused while it's out, like the map.

const LAYER := 71 ## over the map (70), under the pause menu (80)
const SIZE := Vector2(380, 720) ## px at 1600 x 900
const MARGIN := 28.0
const BODY := Color(0.05, 0.05, 0.06, 1.0)
const SCREEN := Color(0.09, 0.1, 0.12, 1.0)

var is_open := false
var pad := false ## last input from a controller

var _apps := {} ## id -> {title, colour, build: Callable(VBoxContainer)}
var _order: Array[String] = []
var _app := "" ## the app shown, "" for the home screen
var _was_paused := false
var _was_captured := false

var _root: Control
var _body: PanelContainer
var _clock: Label
var _money: Label
var _title: Label
var _back: Button
var _home: GridContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _hint: Label


static func find(tree: SceneTree) -> Phone:
	return tree.get_first_node_in_group("phone") as Phone if tree != null else null


func _ready() -> void:
	add_to_group("phone")
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	add_app("map", "Map", Color(0.36, 0.62, 0.95), Callable())
	visible = false


# --- apps --------------------------------------------------------------------------------------

## An app on the home screen. `colour` is its icon's; `build` fills the app
## (see the top). An app with an id already there is replaced.
func add_app(id: String, title: String, colour: Color, build: Callable) -> void:
	_apps[id] = {"title": title, "colour": colour, "build": build}
	if not id in _order:
		_order.append(id)
	_fill_home()


func remove_app(id: String) -> void:
	_apps.erase(id)
	_order.erase(id)
	if _app == id:
		show_app("")
	_fill_home()


## The app shown now ("" for the home screen).
func current_app() -> String:
	return _app


## Shows an app ("" for the home screen). The Map app opens the town map.
func show_app(id: String) -> void:
	if id == "map":
		var map := WorldMap.find(get_tree())
		if map != null:
			close()
			map.open()
		return
	if id != "" and not _apps.has(id):
		id = ""
	_app = id
	_home.visible = id == ""
	_scroll.visible = id != ""
	_back.visible = id != ""
	_title.text = "" if id == "" else str(_apps[id]["title"])
	refresh()


## Builds the shown app again (after something in it changed).
func refresh() -> void:
	_update_status()
	_update_hint()
	if _app == "":
		if pad and is_open:
			_focus_first(_home)
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var build: Variant = _apps.get(_app, {}).get("build")
	if build is Callable and (build as Callable).is_valid():
		(build as Callable).call(_box)
	_scroll.scroll_vertical = 0
	if pad and is_open:
		_focus_first(_box)


func _focus_first(in_node: Node) -> void:
	for c in in_node.find_children("*", "Button", true, false):
		if (c as Button).visible:
			(c as Button).grab_focus.call_deferred()
			return


## A button for an app, in the phone's style.
func make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", HudStyle.heading_font())
	b.add_theme_font_size_override("font_size", 17)
	var normal := _round(Color(1, 1, 1, 0.08), 8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 4
	normal.content_margin_bottom = 3
	var hot := normal.duplicate() as StyleBoxFlat
	hot.bg_color = Color(1, 1, 1, 0.18)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(HudStyle.ACCENT, 0.35)
	var down := normal.duplicate() as StyleBoxFlat
	down.bg_color = HudStyle.ACCENT
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))
	b.pressed.connect(action)
	return b


# --- opening and closing -----------------------------------------------------------------------

## Something else has the screen (the pause menu, the note box, the
## character creator, the loading screen, the map): the phone stays away.
func _blocked() -> bool:
	var tree := get_tree()
	var menu := tree.root.get_node_or_null("TitleMenu")
	if menu != null and (bool(menu.get("_open")) or (menu.get("_loading") is Control and (menu.get("_loading") as Control).visible)):
		return true
	var notes := tree.root.get_node_or_null("FieldNotes")
	if notes != null and notes.get("_panel") is Control and (notes.get("_panel") as Control).visible:
		return true
	for card in tree.get_nodes_in_group("counter_menu"):
		if (card as CanvasLayer).visible:
			return true
	var map := WorldMap.find(tree)
	if map != null and map.is_open:
		return true
	return tree.paused and not is_open


## Brings the phone out, on the home screen or straight into an app.
func open(app := "") -> void:
	if is_open or _blocked():
		return
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout()
	show_app(app)


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not pad:
			pad = true
			_update_hint()
	elif event is InputEventKey or event is InputEventMouseButton:
		if pad:
			pad = false
			_update_hint()
	if not is_open:
		if event.is_action_pressed("phone") and not _blocked() and not (event is InputEventJoypadButton and dpad_works_tool(get_tree())):
			open()
			get_viewport().set_input_as_handled()
		return
	var back := event is InputEventJoypadButton and event.is_pressed() and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	if back and _app != "":
		show_app("")
		get_viewport().set_input_as_handled()
	elif back or (event.is_action_pressed("phone") and not event is InputEventJoypadButton) or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open:
		_update_status()


## In the driver's seat of a working vehicle (a forklift, a tow truck, the
## crane), the D-pad works its tool: the phone and the map are on the
## vehicle wheel instead.
static func dpad_works_tool(tree: SceneTree) -> bool:
	var scene := tree.current_scene if tree != null else null
	var who: Variant = scene.get("player") if scene != null else null
	if not who is Node or not is_instance_valid(who):
		return false
	var car: Variant = (who as Node).get("vehicle")
	return car is Car and (car as Car).tool != null and not bool((who as Node).get("passenger"))


# --- the look ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	_root.add_child(shade)

	# The body (the bezel) and the screen inside it.
	_body = PanelContainer.new()
	_body.name = "Body"
	var bezel := _round(BODY, 38)
	bezel.set_content_margin_all(12)
	bezel.border_color = Color(0.25, 0.26, 0.28)
	bezel.set_border_width_all(2)
	bezel.shadow_color = Color(0, 0, 0, 0.5)
	bezel.shadow_size = 18
	_body.add_theme_stylebox_override("panel", bezel)
	_root.add_child(_body)
	var screen := PanelContainer.new()
	var glass := _round(SCREEN, 28)
	glass.content_margin_left = 18
	glass.content_margin_right = 18
	glass.content_margin_top = 10
	glass.content_margin_bottom = 12
	screen.add_theme_stylebox_override("panel", glass)
	_body.add_child(screen)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	screen.add_child(col)

	# The status bar: the time, the notch, your money.
	var status := HBoxContainer.new()
	col.add_child(status)
	_clock = HudStyle.label(15, true, Color.WHITE, false)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_clock)
	var notch := Panel.new()
	notch.custom_minimum_size = Vector2(70, 16)
	notch.add_theme_stylebox_override("panel", _round(BODY, 8))
	status.add_child(notch)
	_money = HudStyle.label(15, true, HudStyle.GOOD, false)
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(_money)

	# The app's header: back, and its name.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_back = make_button("‹ Home", func() -> void: show_app(""))
	head.add_child(_back)
	_title = HudStyle.label(22, true, Color.WHITE, false)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)

	# The home screen.
	_home = GridContainer.new()
	_home.columns = 3
	_home.add_theme_constant_override("h_separation", 14)
	_home.add_theme_constant_override("v_separation", 16)
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_home)

	# An app.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	col.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)

	_hint = HudStyle.label(13, false, HudStyle.DIM, false)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)
	_back.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


## The home screen's icons: a rounded square in the app's colour with its
## first letter, the name under it.
func _fill_home() -> void:
	if _home == null:
		return
	for c in _home.get_children():
		_home.remove_child(c)
		c.queue_free()
	for id: String in _order:
		var app: Dictionary = _apps[id]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_home.add_child(cell)
		var icon := Button.new()
		icon.custom_minimum_size = Vector2(76, 76)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.focus_mode = Control.FOCUS_ALL
		icon.text = str(app["title"]).left(1)
		icon.add_theme_font_override("font", HudStyle.heading_font())
		icon.add_theme_font_size_override("font_size", 40)
		var c: Color = app["colour"]
		icon.add_theme_stylebox_override("normal", _round(c, 18))
		icon.add_theme_stylebox_override("hover", _round(c.lightened(0.15), 18))
		icon.add_theme_stylebox_override("pressed", _round(c.darkened(0.2), 18))
		var focus := _round(c.lightened(0.15), 18)
		focus.border_color = HudStyle.ACCENT
		focus.set_border_width_all(3)
		icon.add_theme_stylebox_override("focus", focus)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			icon.add_theme_color_override(s, Color.WHITE)
		var app_id := id
		icon.pressed.connect(func() -> void: show_app(app_id))
		cell.add_child(icon)
		var caption := HudStyle.label(14, false, Color.WHITE, false)
		caption.text = str(app["title"])
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)


func _layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var k := minf(vp.y / 900.0, vp.x / 1600.0 * 1.6)
	var s := SIZE * clampf(k, 0.6, 2.0)
	s.y = minf(s.y, vp.y - MARGIN * 2.0)
	_body.size = s
	_body.position = vp - s - Vector2(MARGIN, MARGIN) * clampf(k, 0.6, 2.0)


func _update_status() -> void:
	var t := Time.get_time_dict_from_system()
	_clock.text = "%d:%02d" % [int(t["hour"]), int(t["minute"])]
	var gs := get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	_money.text = CarModels.dollars(int(gs.get("money"))) if gs != null else ""


func _update_hint() -> void:
	if _hint == null:
		return
	if pad:
		_hint.text = "D-pad and A to pick  ·  B back" if _app != "" else "D-pad and A to pick  ·  B put away"
	else:
		_hint.text = "P or Esc to put away"


static func _round(colour: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb

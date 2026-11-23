extends Node
## The title menu: the Trans-Canada Auto name over the live town when the
## game starts, with Play, Graphics, Controls, Credits and Quit. Esc during
## play brings it back as a pause menu (Resume). While it's up the player
## can't move, and the mouse is free for clicking.
##
## In a browser, clicking Play is also what lets the game take the mouse
## (browsers only allow that after a click). There's no Quit there.

const TITLE_ART := "res://branding/title.png"
const SPLASH := "res://branding/splash.png"

var _layer: CanvasLayer
var _shade: ColorRect
var _panel: VBoxContainer
var _play: Button
var _graphics: Button
var _info: Label
var _started := false
var _open := false
## The loading screen, up until the town round the spawn is built.
var _loading: Control
var _loading_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_loading()
	_show(true)
	_layer.visible = false


func _process(_delta: float) -> void:
	if _loading.visible:
		var scene := get_tree().current_scene
		var world := scene.get_node_or_null("World") if scene != null else null
		if world != null and bool(world.get("is_built")):
			_loading.visible = false
			_layer.visible = _open
		elif world != null:
			_loading_label.text = "%s\u2026" % str(world.get("loading_step"))
	# Keep the player still while the menu is up (the scene may have only
	# just loaded, or the player may have got into a car).
	if _open:
		var p := _player()
		if p != null and p.get("vehicle") == null:
			p.set("input_enabled", false)


func _unhandled_input(event: InputEvent) -> void:
	var notes := get_tree().root.get_node_or_null("FieldNotes")
	if notes != null and notes.get("_panel") != null and (notes.get("_panel") as Control).visible:
		return # Esc closes the note box first
	if event.is_action_pressed("pause") and _started:
		if _open:
			_resume()
		else:
			_show(false)
		get_viewport().set_input_as_handled()


func _show(first: bool) -> void:
	_open = true
	_layer.visible = true
	_play.text = "Play" if first else "Resume"
	_info.text = ""
	_update_graphics()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play.grab_focus.call_deferred()


func _resume() -> void:
	_open = false
	_started = true
	_layer.visible = false
	var p := _player()
	if p != null and p.get("vehicle") == null:
		p.set("input_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _player() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Player") if scene != null else null


func _graphics_node() -> Node:
	return get_tree().root.get_node_or_null("Graphics")


func _update_graphics() -> void:
	var g := _graphics_node()
	if g == null:
		_graphics.visible = false
		return
	_graphics.text = "Graphics: %s" % ("High" if int(g.get("level")) == 1 else "Low")


func _toggle_graphics() -> void:
	var g := _graphics_node()
	if g == null:
		return
	g.call("set_level", 0 if int(g.get("level")) == 1 else 1)
	_update_graphics()


func _show_controls() -> void:
	_info.text = "\n".join([
		"Walk: W A S D or arrow keys, left stick.  Run: Shift, A button.",
		"Look: mouse, right stick.  Zoom: mouse wheel, D-pad.  Reset camera: C.",
		"Get in or out of a car: E or F at the driver's door, Y button.",
		"Drive: W go, S brake and reverse, A D steer, Space handbrake.",
		"Leave a note about a spot: N.  Open your notes folder: F9.",
		"Graphics High or Low: F10.  This menu: Esc.",
	])


func _show_credits() -> void:
	_info.text = "\n".join([
		"Trans-Canada Auto. Made on Prince Edward Island.",
		"Map data © OpenStreetMap contributors, under the Open Database License.",
		"Elevation, building heights and trees: Natural Resources Canada, HRDEM;",
		"contains information licensed under the Open Government Licence – Canada.",
		"Brick, stone and clapboard textures: Poly Haven (polyhaven.com), CC0.",
		"Made with the Godot Engine (godotengine.org).",
		"Businesses in the game are made up; any likeness to real ones is a joke.",
	])


func _build_loading() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 81
	add_child(layer)
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.0706, 0.2118, 0.1412)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var art := TextureRect.new()
	art.texture = load(SPLASH) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(art)
	_loading_label = Label.new()
	_loading_label.text = "Starting\u2026"
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_loading_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_loading_label.add_theme_constant_override("outline_size", 6)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_loading_label.offset_left = -400
	_loading_label.offset_right = 400
	_loading_label.offset_top = -120
	_loading_label.offset_bottom = -80
	_loading.add_child(_loading_label)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 80
	add_child(_layer)
	_shade = ColorRect.new()
	_shade.color = Color(0.04, 0.12, 0.08, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	_layer.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var art := TextureRect.new()
	art.texture = load(TITLE_ART) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.custom_minimum_size = Vector2(620, 182)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(art)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	_panel.custom_minimum_size = Vector2(320, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_panel)
	_play = _button("Play", _resume)
	_graphics = _button("Graphics", _toggle_graphics)
	_button("Controls", _show_controls)
	_button("Credits", _show_credits)
	if not OS.has_feature("web"):
		_button("Quit", func() -> void: get_tree().quit())
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_info.add_theme_constant_override("outline_size", 4)
	column.add_child(_info)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	b.add_theme_font_size_override("font_size", 24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.36, 0.24, 0.92)
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.71, 0.28, 0.17, 0.95) # red clay
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	_panel.add_child(b)
	return b

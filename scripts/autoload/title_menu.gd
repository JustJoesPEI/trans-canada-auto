extends Node
## The title menu: the Trans-Canada Auto name over the live town when the
## game starts, with Play, Character (the character creator), Settings
## (graphics, volume, the frame rate counter: GameSettingsPanel), Controls
## (every key and button, ControlsList; then the mouse, driving help and
## controller settings, AimSettingsPanel, and the keyboard page,
## KeyBindsPanel), Credits and Quit. Each page opens beside the buttons.
## Esc during play brings it back as a pause menu (Resume, and Map and
## Phone). While it's up the player can't move, the game's HUD is hidden,
## and the mouse is free for clicking.
##
## Clicking the version number in the corner seven times turns developer
## mode on (DevMode); Settings can turn it off again.
##
## In a browser, clicking Play is also what lets the game take the mouse
## (browsers only allow that after a click). There's no Quit there.

const TITLE_ART := "res://branding/title.png"
## The loading screens, drawn by tools/make_branding.py, shown in turn while
## the town is built. The first is the same picture as the boot splash, so
## the hand-over from the engine's splash doesn't jump. Imported compressed
## (BC7; their .import files are kept in git): 2 MB of graphics memory each
## instead of 8, with two or three up at once while the town loads, when
## the memory is at its fullest.
const LOADING_ART := [
	"res://branding/loading/01.jpg",
	"res://branding/loading/02.jpg",
	"res://branding/loading/03.jpg",
	"res://branding/loading/04.jpg",
	"res://branding/loading/05.jpg",
	"res://branding/loading/06.jpg",
]
## Seconds the first picture (the boot splash's) stays up, then each of the
## others, picked in a fresh shuffled order each launch; and the cross-fade.
const LOADING_FIRST := 2.5
const LOADING_HOLD := 5.0
const LOADING_FADE := 0.8
## Tips along the bottom of the loading screen, one per picture.
const LOADING_TIPS := [
	"Nobody on the Island locks their car. Walk up to a driver's door and press E to find out.",
	"Space is the handbrake. The roundabouts were built for it, probably.",
	"Your phone (P) has jobs, SpudDash and the garage. Rent's due either way.",
	"Everyone in Charlatown knows your mother. Drive accordingly.",
	"The red on the roads isn't paint. It's the dirt. It gets on everything.",
	"Graphics are in Settings: Low, Medium or High. Low still looks fine, eh.",
	"Tim Hardly's is open. Tim Hardly's is always open. Nobody knows who Tim is.",
	"Wanted level: your aunt saw you. Everybody will know by supper.",
]

var _layer: CanvasLayer
var _shade: ColorRect
var _panel: VBoxContainer
var _play: Button
var _map: Button
var _phone: Button
var _info: Label
var _game_settings: GameSettingsPanel
var _controls_page: VBoxContainer
var _controls_list: ControlsList
var _controls: AimSettingsPanel
var _keys: KeyBindsPanel
var _credits: VBoxContainer
## Clicks on the version number so far (DevMode.TAPS turns it on).
var _version_taps := 0
## Holds the settings pages beside the buttons, scrolling when they're taller
## than the room left under the title art.
var _settings: ScrollContainer
var _menu: Control
var _character: Button
var _creator: CharacterCreator
var _started := false
var _open := false
## The loading screen, up until the town round the spawn is built.
var _loading: Control
var _loading_label: Label
var _loading_tip: Label
var _loading_spinner: Control
## Two pictures, bottom and top, for cross-fading between loading screens.
var _loading_art: Array[TextureRect] = []
var _loading_index := 0
var _loading_time := 0.0
var _loading_start_ms := 0
var _loading_tip_start := 0
var _loading_order: Array = []
## When the town was built (ms), for the most the loading screen waits on
## the shader warm-up after it.
var _built_ms := -1
const WARMUP_WAIT_MS := 10000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_loading()
	_show(true)
	_layer.visible = false


func _process(_delta: float) -> void:
	if _loading.visible:
		_animate_loading()
		var scene := get_tree().current_scene
		var world := scene.get_node_or_null("World") if scene != null else null
		# Up until the town's built and its shaders are warmed up
		# (ShaderWarmup: a few frames; never more than WARMUP_WAIT).
		var built := world != null and bool(world.get("is_built"))
		if built and _built_ms < 0:
			_built_ms = Time.get_ticks_msec()
		var warm := ShaderWarmup.done or (_built_ms >= 0 and Time.get_ticks_msec() - _built_ms > WARMUP_WAIT_MS)
		if built and warm:
			_loading.visible = false
			_layer.visible = _open
			# The loading screen is only shown once: let go of its pictures
			# (full-screen, 2 MB of graphics memory each even compressed,
			# which counts on chips with a small slice of it).
			for art in _loading_art:
				art.texture = null
		elif world != null:
			_loading_label.text = "%s\u2026" % str(world.get("loading_step")).to_upper()
	# Keep the player still while the menu is up (the scene may have only
	# just loaded, or the player may have got into a car).
	if _open:
		# The scene may have only just loaded under the menu.
		_set_hud(false)
		var p := _player()
		if p != null and p.get("vehicle") == null:
			p.set("input_enabled", false)


func _unhandled_input(event: InputEvent) -> void:
	var notes := get_tree().root.get_node_or_null("FieldNotes")
	if notes != null and notes.get("_panel") != null and (notes.get("_panel") as Control).visible:
		return # Esc closes the note box first
	if _creator != null and _creator.visible:
		return # the creator handles its own Esc
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
	_map.visible = not first
	_phone.visible = not first
	_info.text = ""
	_settings_page("")
	_set_hud(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play.grab_focus.call_deferred()


func _resume() -> void:
	_open = false
	_started = true
	_layer.visible = false
	_set_hud(true)
	var p := _player()
	if p != null and p.get("vehicle") == null:
		p.set("input_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The game's HUD (street, hints, minimap, money) is hidden under the menu.
func _set_hud(show: bool) -> void:
	var scene := get_tree().current_scene
	var hud := scene.get_node_or_null("HUD") as CanvasLayer if scene != null else null
	if hud != null:
		hud.visible = show


## The town map (WorldMap), from the pause menu: back to the game, with
## the map open over it.
func _open_map() -> void:
	_resume()
	var map := WorldMap.find(get_tree())
	if map != null:
		map.open()


## Your phone (Phone), from the pause menu: back to the game, with the
## phone out over it.
func _open_phone() -> void:
	_resume()
	var phone := Phone.find(get_tree())
	if phone != null:
		phone.open()


## The character creator, over the town in place of the menu.
func _open_creator() -> void:
	var p := _player()
	var model: HumanoidModel = p.get("model") if p != null else null
	if _creator == null:
		_creator = CharacterCreator.new()
		_creator.closed.connect(_creator_closed)
		_layer.add_child(_creator)
	_menu.visible = false
	_shade.visible = false
	_info.text = ""
	var look := PlayerLook.load_look() if model == null else _look_of(model)
	if p != null and p.get("paint_colour") is Color:
		look["paint"] = p.get("paint_colour")
	_creator.open(look)


func _creator_closed(saved: bool) -> void:
	_menu.visible = true
	_shade.visible = true
	if saved:
		var p := _player()
		if p != null:
			(p.get("model") as HumanoidModel).set_look(PlayerLook.copy(_creator.look))
			p.set("paint_colour", _creator.look.get("paint", p.get("paint_colour")))
	_character.grab_focus.call_deferred()


## The look a person is wearing now, as PlayerLook keeps it.
static func _look_of(model: HumanoidModel) -> Dictionary:
	return {"skin": model.skin, "hair": model.hair, "hair_style": model.hair_style, "height": model.height,
		"build": model.build, "outfit": Outfit.complete(model.outfit)}


func _player() -> Node:
	return get_tree().get_first_node_in_group(PlayerController.GROUP)


## Which page is up beside the buttons: "settings", "controls", "keys",
## "credits" or "" (none).
func _settings_page(page: String) -> void:
	_settings.visible = page != ""
	_game_settings.visible = page == "settings"
	_controls_page.visible = page == "controls"
	_keys.visible = page == "keys"
	_credits.visible = page == "credits"
	if page == "settings":
		_game_settings.refresh()
		_game_settings.first().grab_focus.call_deferred()
	elif page == "controls":
		_controls_list.refresh()
		_controls.refresh()
		_controls.first().grab_focus.call_deferred()
	elif page == "keys":
		_keys.refresh()
		_keys.first().grab_focus.call_deferred()
	_settings.scroll_vertical = 0


## A page's button: opens it, or closes it if it's the one up.
func _toggle_page(page: String, shown: Control) -> void:
	_info.text = ""
	_settings_page("" if _settings.visible and shown.visible else page)


func _build_credits() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var lines := [
		["Trans-Canada Auto", 22, true],
		["%s. Made on Prince Edward Island." % ("Version " + BuildInfo.label() if BuildInfo.label()[0].is_valid_int() else BuildInfo.label().capitalize()), 19, false],
		["Map", 22, true],
		["Map data © OpenStreetMap contributors, under the Open Database License.", 19, false],
		["Elevation, building heights and trees: Natural Resources Canada, HRDEM. Contains information licensed under the Open Government Licence – Canada.", 19, false],
		["Sound and pictures", 22, true],
		["Engine recordings: Bryan Gold and Dramatic Cat, from the Sonniss #GameAudioGDC bundle.", 19, false],
		["Bark texture: Poly Haven (polyhaven.com), CC0.", 19, false],
		["Made with the Godot Engine (godotengine.org).", 19, false],
		["The fine print", 22, true],
		["Every business in the game is made up. Any likeness to a real one is a joke, and they know what they did.", 19, false],
	]
	for l: Array in lines:
		var label := Label.new()
		label.text = str(l[0])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(560, 0)
		label.add_theme_font_size_override("font_size", int(l[1]))
		label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0) if bool(l[2]) else Color(0.95, 0.92, 0.85))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		label.add_theme_constant_override("outline_size", 4)
		page.add_child(label)
	return page


## The version number: seven clicks turn developer mode on (DevMode).
func _version_clicked(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or DevMode.on():
		return
	_version_taps += 1
	if _version_taps >= DevMode.TAPS:
		_version_taps = 0
		DevMode.set_on(true)
		_info.text = "Developer mode on. The keys are under Controls; Settings turns it off."
		if _game_settings.visible:
			_game_settings.refresh()


func _build_loading() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 81
	add_child(layer)
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.055)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	for i in 2:
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading.add_child(art)
		_loading_art.append(art)
	_loading_art[0].texture = load(LOADING_ART[0]) as Texture2D
	_loading_start_ms = Time.get_ticks_msec()
	_loading_order = range(1, LOADING_ART.size())
	_loading_order.shuffle()
	_loading_art[1].modulate.a = 0.0
	# A dark band along the bottom for the tip and the spinner to sit on.
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -150
	_loading.add_child(band)
	# The tip, bottom left.
	_loading_tip_start = randi() % LOADING_TIPS.size()
	_loading_tip = _loading_text(20, Color(0.98, 0.96, 0.9))
	_loading_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_loading_tip.offset_left = 48
	_loading_tip.offset_right = -420
	_loading_tip.offset_top = -74
	_loading_tip.offset_bottom = -26
	_loading_tip.text = "TIP: " + str(LOADING_TIPS[_loading_tip_start])
	_loading.add_child(_loading_tip)
	# What's being built, and a spinner, bottom right.
	_loading_label = _loading_text(20, Color(1.0, 0.84, 0.0))
	_loading_label.text = "STARTING\u2026"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loading_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_loading_label.offset_left = -440
	_loading_label.offset_right = -96
	_loading_label.offset_top = -66
	_loading_label.offset_bottom = -36
	_loading.add_child(_loading_label)
	_loading_spinner = Control.new()
	_loading_spinner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_loading_spinner.offset_left = -78
	_loading_spinner.offset_right = -46
	_loading_spinner.offset_top = -67
	_loading_spinner.offset_bottom = -35
	_loading_spinner.draw.connect(_draw_spinner)
	_loading.add_child(_loading_spinner)


func _loading_text(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


## A ring with a gap in it, turning, like every loading screen ever.
func _draw_spinner() -> void:
	var c := _loading_spinner.size / 2.0
	var r := minf(c.x, c.y) - 3.0
	var a := _loading_time * TAU * 0.9
	_loading_spinner.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 5.0, true)
	_loading_spinner.draw_arc(c, r, a, a + TAU * 0.7, 40, Color(1, 1, 1, 0.95), 5.0, true)


## Turn the spinner, and every few seconds fade to the next loading picture
## and tip.
func _animate_loading() -> void:
	# Wall-clock time, not frame delta: building the town makes for long
	# frames, and the engine clamps delta on those.
	_loading_time = (Time.get_ticks_msec() - _loading_start_ms) / 1000.0
	_loading_spinner.queue_redraw()
	var slot := 0
	var into := _loading_time
	if _loading_time >= LOADING_FIRST:
		slot = 1 + int((_loading_time - LOADING_FIRST) / LOADING_HOLD)
		into = fmod(_loading_time - LOADING_FIRST, LOADING_HOLD)
	var bottom := _loading_art[0]
	var top := _loading_art[1]
	if slot != _loading_index:
		_loading_index = slot
		# The picture that was showing goes underneath; the next fades in over it.
		bottom.texture = top.texture if top.modulate.a > 0.5 else bottom.texture
		top.texture = load(LOADING_ART[_loading_order[(slot - 1) % _loading_order.size()]]) as Texture2D
		top.modulate.a = 0.0
		_loading_tip.text = "TIP: " + str(LOADING_TIPS[(_loading_tip_start + slot) % LOADING_TIPS.size()])
	if slot > 0:
		top.modulate.a = clampf(into / LOADING_FADE, 0.0, 1.0)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 80
	add_child(_layer)
	_shade = ColorRect.new()
	_shade.color = Color(0.04, 0.03, 0.055, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	_layer.add_child(margin)
	_menu = margin
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var art := TextureRect.new()
	art.texture = load(TITLE_ART) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.custom_minimum_size = Vector2(480, 260)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(art)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	_panel.custom_minimum_size = Vector2(320, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# The buttons, with the controller settings beside them when Controls is open.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	column.add_child(row)
	row.add_child(_panel)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_settings = ScrollContainer.new()
	_settings.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings.follow_focus = true
	_settings.visible = false
	row.add_child(_settings)
	var pages := VBoxContainer.new()
	_settings.add_child(pages)
	_game_settings = GameSettingsPanel.new()
	_game_settings.visible = false
	pages.add_child(_game_settings)
	_controls_page = VBoxContainer.new()
	_controls_page.add_theme_constant_override("separation", 18)
	_controls_page.visible = false
	pages.add_child(_controls_page)
	_controls_list = ControlsList.new()
	_controls_page.add_child(_controls_list)
	_controls = AimSettingsPanel.new()
	_controls.keys_requested.connect(func() -> void: _settings_page("keys"))
	_controls_page.add_child(_controls)
	_credits = _build_credits()
	_credits.visible = false
	pages.add_child(_credits)
	_keys = KeyBindsPanel.new()
	_keys.visible = false
	_keys.closed.connect(func() -> void:
		_settings_page("controls")
		_controls.first().grab_focus.call_deferred())
	pages.add_child(_keys)
	_play = _button("Play", _resume)
	_map = _button("Map", _open_map)
	_phone = _button("Phone", _open_phone)
	_character = _button("Character", _open_creator)
	_button("Settings", func() -> void: _toggle_page("settings", _game_settings))
	_button("Controls", func() -> void: _toggle_page("controls", _controls_page))
	_button("Credits", func() -> void: _toggle_page("credits", _credits))
	if not OS.has_feature("web"):
		_button("Quit", func() -> void: get_tree().quit())
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_info.add_theme_constant_override("outline_size", 4)
	column.add_child(_info)
	# Which build this is, small in the bottom-right corner.
	var version := Label.new()
	version.text = BuildInfo.label()
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.75))
	version.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	version.add_theme_constant_override("outline_size", 4)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_version_clicked)
	_layer.add_child(version)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	b.add_theme_font_size_override("font_size", 24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.03, 0.03, 0.92) # the wordmark's black box
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.84, 0.17, 0.12, 0.95) # maple leaf red
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	_panel.add_child(b)
	return b

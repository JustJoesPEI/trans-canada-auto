class_name CharacterCreator
extends Control
## The character creator: choose the player's skin, hair, height, build,
## clothes (every kind, colour and print in Outfit) and paint colour (the
## twelve in PaintWeapons), with a turning preview of the result. Opened from the title menu; Done saves the look
## (PlayerLook) and puts it on the player, Cancel or Esc leaves it as it was.
##
## The choices are rows down the left (arrows for a kind, swatches for a
## colour, sliders for height and build), built in code like the rest of
## the menus so it works with a mouse, keyboard or controller. The preview
## is a small world of its own on the right: drag it to turn the person,
## Walk to see the clothes move.

signal closed(saved: bool)

const GREEN := Color(0.12, 0.36, 0.24, 0.92)
const CLAY := Color(0.71, 0.28, 0.17, 0.95)
const CREAM := Color(0.95, 0.92, 0.85)
const PANEL := Color(0.05, 0.14, 0.09, 0.9)

## What a top's second colour is, by kind (tops not listed don't use one).
const TRIM_NAMES := {"tshirt": "Collar", "hoodie": "Cuffs", "flannel": "Check", "bomber": "Knit bands",
	"varsity": "Sleeves", "denim": "Buttons"}

var look: Dictionary

var _list: VBoxContainer
var _scroll: ScrollContainer
var _preview: HumanoidModel
var _viewport: SubViewport
var _camera: Camera3D
var _walk := false
var _walk_button: Button
var _turn := 0.5
var _dragging := false
var _focus_key := ""
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


## Open with the player's current look.
func open(current: Dictionary) -> void:
	look = PlayerLook.copy(current)
	if _list == null:
		_build()
	visible = true
	# Its picture full size again (shrunk to nothing while it's shut).
	var holder := _viewport.get_parent() as SubViewportContainer
	if holder != null:
		holder.stretch = true
	var gfx := get_node_or_null("/root/Graphics")
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if gfx != null and int(gfx.get("level")) == 0 else Viewport.MSAA_4X
	_preview.set_look(PlayerLook.copy(look))
	_frame_camera()
	_refresh()


func _process(delta: float) -> void:
	if not visible or _preview == null:
		return
	if not _dragging:
		_turn += delta * 0.35
	_preview.rotation.y = _turn
	_preview.set_motion(1.5 if _walk else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close(false)
		get_viewport().set_input_as_handled()


# --- layout ---------------------------------------------------------------------------

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.08, 0.05, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	# Left: the choices, and the buttons along the bottom.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(540, 0)
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(_label("Your Character", 34))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = PANEL
	pstyle.set_corner_radius_all(8)
	pstyle.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", pstyle)
	left.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	left.add_child(bar)
	bar.add_child(_button("Randomize", _randomize, Vector2(128, 48)))
	bar.add_child(_button("Reset", _reset, Vector2(100, 48)))
	bar.add_child(_button("Cancel", func() -> void: _close(false), Vector2(110, 48)))
	bar.add_child(_button("Done", func() -> void: _close(true), Vector2(150, 48)))

	# Right: the preview, a little world of its own.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.gui_input.connect(_on_preview_input)
	right.add_child(holder)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(_viewport)
	_build_stage()
	var under := HBoxContainer.new()
	under.alignment = BoxContainer.ALIGNMENT_CENTER
	under.add_theme_constant_override("separation", 16)
	right.add_child(under)
	_walk_button = _button("Walk", _toggle_walk, Vector2(140, 44))
	under.add_child(_walk_button)
	under.add_child(_label("Drag to turn", 18))


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.56, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.65, 0.7)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.55, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.8, 0.0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)
	# A pedestal of red clay to stand on.
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.6
	cyl.height = 0.12
	base.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.55, 0.24, 0.15)
	bm.roughness = 0.9
	base.material_override = bm
	base.position.y = -0.06
	_viewport.add_child(base)
	_preview = HumanoidModel.new()
	_viewport.add_child(_preview)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_viewport.add_child(_camera)


func _frame_camera() -> void:
	var h: float = look.get("height", 1.75)
	var target := Vector3(0.0, h * 0.5, 0.0)
	_camera.position = target + Vector3(0.0, 0.2, -h * 2.05)
	_camera.look_at(target)


# --- the rows -------------------------------------------------------------------------

## Rebuilds the rows (some depend on others: a cap has a print, a T-shirt a
## collar colour), keeping focus on the same choice.
func _refresh() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus.has_meta("key"):
		_focus_key = str(focus.get_meta("key"))
	var scroll := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var outfit: Dictionary = look["outfit"]

	_section("Body")
	_swatches("Skin", "skin", PlayerLook.SKINS, look["skin"], func(c: Color) -> void: look["skin"] = c)
	var cm := func(v: float) -> String: return "%d cm" % roundi(v * 100.0)
	var set_height := func(v: float) -> void:
		look["height"] = v
		_frame_camera()
	_slider("Height", "height", PlayerLook.HEIGHT_RANGE, look["height"], cm, set_height)
	var build_name := func(v: float) -> String: return "Slim" if v < 0.96 else ("Broad" if v > 1.08 else "Average")
	_slider("Build", "build", PlayerLook.BUILD_RANGE, look["build"], build_name, func(v: float) -> void: look["build"] = v)

	_section("Hair")
	_choice("Style", "hair_style", PlayerLook.HAIR_STYLES, int(look["hair_style"]), func(i: int) -> void: look["hair_style"] = i)
	_swatches("Colour", "hair", PlayerLook.HAIRS, look["hair"], func(c: Color) -> void: look["hair"] = c)

	var hat: Dictionary = outfit["hat"]
	_section("Hat")
	_kind("hat")
	if hat["kind"] != "none":
		_swatches("Colour", "hat_color", PlayerLook.CLOTHS, hat["color"], func(c: Color) -> void: hat["color"] = c)
		_print_choice("Logo", "hat_print", hat, "print")

	var top: Dictionary = outfit["top"]
	_section("Top")
	_kind("top")
	_swatches("Colour", "top_color", PlayerLook.CLOTHS, top["color"], func(c: Color) -> void: top["color"] = c)
	if TRIM_NAMES.has(top["kind"]):
		_swatches(TRIM_NAMES[top["kind"]], "top_trim", PlayerLook.CLOTHS, top["trim"], func(c: Color) -> void: top["trim"] = c)
	_print_choice("Chest" if top["kind"] in Outfit.FRONT_BIG else "Chest logo", "top_print", top, "print")
	_print_choice("Back", "top_back", top, "back")
	if top["kind"] in Outfit.HAS_PATCH:
		_print_choice("Sleeve patch", "top_patch", top, "patch")

	var bottom: Dictionary = outfit["bottom"]
	_section("Bottoms")
	_kind("bottom")
	_swatches("Colour", "bottom_color", PlayerLook.CLOTHS, bottom["color"], func(c: Color) -> void: bottom["color"] = c)

	var shoes: Dictionary = outfit["shoes"]
	_section("Shoes")
	_kind("shoes")
	_swatches("Colour", "shoes_color", PlayerLook.CLOTHS, shoes["color"], func(c: Color) -> void: shoes["color"] = c)
	_swatches("Sole", "shoes_trim", PlayerLook.CLOTHS, shoes["trim"], func(c: Color) -> void: shoes["trim"] = c)

	# Your paintballs (design section 3, "Colours"): your splats on walls,
	# cars and people are this colour.
	var paint: Color = look.get("paint", PaintWeapons.COLOURS[PaintWeapons.DEFAULT_COLOUR])
	_section("Paint  ·  %s" % PaintWeapons.colour_name(paint))
	_swatches("Paintballs", "paint", PaintWeapons.COLOURS, paint, func(c: Color) -> void: look["paint"] = c)

	_restore_focus.call_deferred(scroll)


func _restore_focus(scroll: int) -> void:
	_scroll.scroll_vertical = scroll
	for c in _all_controls(_list):
		if c.has_meta("key") and str(c.get_meta("key")) == _focus_key:
			c.grab_focus()
			return
	var first := _first_focusable(_list)
	if first != null:
		first.grab_focus()


func _changed(rebuild := false) -> void:
	_preview.set_look(PlayerLook.copy(look))
	if rebuild:
		_refresh()


func _section(title: String) -> void:
	var l := _label(title, 22)
	l.add_theme_color_override("font_color", Color(0.98, 0.78, 0.45))
	_list.add_child(l)


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(title, 18)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	_list.add_child(row)
	return row


## Arrows through a list of names; `set_index` gets the new index.
func _choice(title: String, key: String, names: Array, index: int, set_index: Callable, rebuild := false) -> void:
	var row := _row(title)
	var value := _label(str(names[index]), 20)
	value.custom_minimum_size = Vector2(220, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var step := func(d: int) -> void:
		var i := posmod(index + d, names.size())
		set_index.call(i)
		_focus_key = key + ("<" if d < 0 else ">")
		_changed(rebuild)
		if not rebuild:
			index = i
			value.text = str(names[i])
	var prev := _button("<", func() -> void: step.call(-1), Vector2(44, 40))
	prev.set_meta("key", key + "<")
	var next := _button(">", func() -> void: step.call(1), Vector2(44, 40))
	next.set_meta("key", key + ">")
	row.add_child(prev)
	row.add_child(value)
	row.add_child(next)


## The kind of garment in a slot (changing it can change the rows below).
func _kind(slot: String) -> void:
	var g: Dictionary = (look["outfit"] as Dictionary)[slot]
	var kinds: Dictionary = Outfit.KINDS[slot]
	var keys: Array = kinds.keys()
	var pick := func(i: int) -> void:
		g["kind"] = keys[i]
		g["trim"] = Outfit.default_trim(slot, g["kind"], g["color"])
		if g["kind"] == "varsity" and str(g.get("print", "")) == "":
			g["print"] = "varsity_s"
	_choice("Kind", slot + "_kind", kinds.values(), keys.find(g["kind"]), pick, true)


## A print from Outfit.PRINTS (or none) for one place on a garment.
func _print_choice(title: String, key: String, g: Dictionary, field: String) -> void:
	var names: Array = ["None"]
	var ids: Array = [""]
	for id: String in Outfit.PRINTS:
		ids.append(id)
		names.append(Outfit.PRINTS[id])
	_choice(title, key, names, maxi(0, ids.find(str(g.get(field, "")))), func(i: int) -> void: g[field] = ids[i])


func _swatches(title: String, key: String, colours: Array, current: Color, set_colour: Callable) -> void:
	var row := _row(title)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	row.add_child(flow)
	var best := 0
	for i in colours.size():
		if _colour_distance(colours[i], current) < _colour_distance(colours[best], current):
			best = i
	for i in colours.size():
		var c: Color = colours[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_ALL
		b.set_meta("key", "%s%d" % [key, i])
		b.tooltip_text = ""
		var chosen := i == best
		for state in ["normal", "hover", "focus", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(4)
			var lit: bool = chosen or state != "normal"
			sb.set_border_width_all(3 if chosen else (2 if lit else 1))
			sb.border_color = Color(1, 1, 1) if chosen else (Color(0.98, 0.78, 0.45) if lit else Color(0, 0, 0, 0.5))
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func() -> void:
			set_colour.call(c)
			_focus_key = "%s%d" % [key, i]
			_changed(true))
		flow.add_child(b)


func _slider(title: String, key: String, range_: Vector2, current: float, text: Callable, set_value: Callable) -> void:
	var row := _row(title)
	var s := HSlider.new()
	s.min_value = range_.x
	s.max_value = range_.y
	s.step = 0.01
	s.value = current
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(200, 30)
	s.set_meta("key", key)
	var value := _label(str(text.call(current)), 18)
	value.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v: float) -> void:
		set_value.call(v)
		value.text = str(text.call(v))
		_changed())
	row.add_child(s)
	row.add_child(value)


static func _colour_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


# --- buttons --------------------------------------------------------------------------

func _randomize() -> void:
	_rng.randomize()
	look = PlayerLook.random_look(_rng)
	_frame_camera()
	_changed(true)


func _reset() -> void:
	look = PlayerLook.default_look()
	_frame_camera()
	_changed(true)


func _toggle_walk() -> void:
	_walk = not _walk
	_walk_button.text = "Stand" if _walk else "Walk"


func _close(saved: bool) -> void:
	visible = false
	# The preview's screen-sized buffers (4x MSAA) let go while it's shut:
	# it's kept for next time, but graphics memory is short on some chips.
	var holder := _viewport.get_parent() as SubViewportContainer
	if holder != null:
		holder.stretch = false
	_viewport.size = Vector2i(2, 2)
	if saved:
		PlayerLook.save_look(look)
	closed.emit(saved)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn += (event as InputEventMouseMotion).relative.x * 0.012


# --- widgets ---------------------------------------------------------------------------

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CREAM)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _button(text: String, action: Callable, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = GREEN
	normal.border_color = Color(0.98, 0.98, 0.96)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = CLAY
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	return b


static func _all_controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in n.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_all_controls(c))
	return out


static func _first_focusable(n: Node) -> Control:
	for c in _all_controls(n):
		if c.focus_mode != Control.FOCUS_NONE and c is BaseButton:
			return c
	return null

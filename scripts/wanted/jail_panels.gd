class_name JailPanels
extends CanvasLayer
## Two Years Less a Day: the comic-book page played when the police catch
## you (design.md section 7). The panels land one at a time on the loading
## screens' black dotted ground, tilted, white-bordered and keylined, each
## with its caption slapped on in a yellow Anton card, the way
## tools/make_branding.py draws the loading screens. The art is in
## branding/jail/ (tools/make_jail_panels.py); the captions come from
## JailLines, so the fine and the excuse can change every time.
##
## About 15 s in all, skippable once the first panel has had its moment.
## As it starts, the player is moved (out of sight behind the page) to the
## front of the police station, so the streets there load while it plays.

signal finished

## The whole page (s), and how long the first panel holds before any key
## skips the rest.
const TOTAL := 15.0
const SKIP_AFTER := 1.6
## The last panel stays up this long on its own.
const LAST_HOLD := 4.0
const FONT := "res://branding/fonts/Anton-Regular.ttf"
const BACKDROP := "res://branding/jail/backdrop.jpg"
## The panels' art is 1200 x 760.
const ASPECT := 760.0 / 1200.0
const YELLOW := Color(1.0, 0.84, 0.0)
const KEYLINE := Color(0.0, 0.0, 0.0)
const BORDER := Color(1.0, 1.0, 1.0)

var result: Dictionary = {}
var _panels: Array = []
var _times: Array[float] = []
var _shown := 0
var _time := 0.0
var _root: Control
var _hint: Label
var _font: Font
var _done := false


## Plays the page for an arrest (Wanted.caught's result) over everything,
## and lets the player out at the station.
static func play(tree: SceneTree, arrest: Dictionary) -> JailPanels:
	var p := JailPanels.new()
	p.result = arrest
	tree.root.add_child(p)
	return p


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT) as Font
	_panels = result.get("panels", [])
	# Evenly through the page, the last one held on its own at the end.
	var step := (TOTAL - LAST_HOLD) / maxf(1.0, float(_panels.size() - 1))
	for i in _panels.size():
		_times.append(i * step)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.055)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var dots := TextureRect.new()
	dots.texture = load(BACKDROP) as Texture2D
	dots.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dots.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dots)
	_hint = Label.new()
	_hint.text = "ANY KEY: SKIP"
	_hint.add_theme_font_override("font", _font)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -220
	_hint.offset_top = -44
	_hint.offset_right = -24
	_hint.offset_bottom = -14
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.visible = false
	_root.add_child(_hint)
	_let_out()
	_hold_player(true)


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta
	while _shown < _panels.size() and _time >= _times[_shown]:
		_add_panel(_shown)
		_shown += 1
	_hint.visible = _time >= SKIP_AFTER
	if _time >= TOTAL:
		_finish()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	# Every key is ours while the page is up (Esc doesn't open the menu).
	get_viewport().set_input_as_handled()
	if _time >= SKIP_AFTER:
		_finish()


## Where panel i of n sits: [centre as a share of the screen, tilt degrees,
## the caption's corner ("tl", "br"...)].
func _slot(i: int, n: int) -> Array:
	if n <= 3:
		return [[Vector2(0.27, 0.28), -1.4, "tl"], [Vector2(0.73, 0.3), 1.2, "br"], [Vector2(0.5, 0.73), -0.8, "bl"]][mini(i, 2)]
	return [[Vector2(0.27, 0.27), -1.4, "tl"], [Vector2(0.73, 0.28), 1.2, "br"],
		[Vector2(0.27, 0.73), 1.0, "bl"], [Vector2(0.73, 0.72), -1.2, "tr"]][mini(i, 3)]


func _add_panel(i: int) -> void:
	var info: Dictionary = _panels[i]
	var view := _root.get_viewport_rect().size
	var w := minf(view.x * 0.44, view.y * 0.42 / ASPECT)
	var size := Vector2(w, w * ASPECT)
	var slot := _slot(i, _panels.size())
	var centre: Vector2 = (slot[0] as Vector2) * view
	var tilt := float(slot[1])
	var panel := Control.new()
	panel.size = size + Vector2(24, 24)
	panel.position = centre - panel.size * 0.5
	panel.pivot_offset = panel.size * 0.5
	panel.rotation_degrees = tilt
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A soft drop shadow, the black keyline, the white border, the art.
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.55)
	shadow.position = Vector2(10, 14)
	shadow.size = panel.size
	panel.add_child(shadow)
	var keyline := ColorRect.new()
	keyline.color = KEYLINE
	keyline.size = panel.size
	panel.add_child(keyline)
	var border := ColorRect.new()
	border.color = BORDER
	border.position = Vector2(3, 3)
	border.size = panel.size - Vector2(6, 6)
	panel.add_child(border)
	var art := TextureRect.new()
	art.texture = load(str(JailLines.ART.get(str(info.get("art", "judge")), JailLines.ART["judge"]))) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(12, 12)
	art.size = size
	panel.add_child(art)
	_root.add_child(panel)
	# It lands: a little big and see-through, then down onto the page.
	panel.scale = Vector2(1.12, 1.12)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	# The caption a beat later, across its corner.
	var cap := _caption(str(info.get("caption", "")), str(info.get("sub", "")), w)
	_root.add_child(cap)
	cap.reset_size()
	var corner := str(slot[2])
	var half := size * 0.5
	var at := centre + Vector2(-half.x + 10.0 if corner[1] == "l" else half.x - cap.size.x - 10.0,
		-half.y - 6.0 if corner[0] == "t" else half.y - cap.size.y + 14.0)
	at.x = clampf(at.x, 8.0, view.x - cap.size.x - 8.0)
	at.y = clampf(at.y, 8.0, view.y - cap.size.y - 8.0)
	cap.position = at
	cap.pivot_offset = cap.size * 0.5
	cap.rotation_degrees = -tilt * 1.5
	cap.scale = Vector2(1.4, 1.4)
	cap.modulate.a = 0.0
	var ct := cap.create_tween().set_parallel(true)
	ct.tween_property(cap, "scale", Vector2.ONE, 0.18).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(cap, "modulate:a", 1.0, 0.1).set_delay(0.35)


## A comic caption: Anton capitals on a yellow card with a black edge, and
## a smaller line under it.
func _caption(text: String, sub: String, panel_w: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = YELLOW
	sb.border_color = Color.BLACK
	sb.set_border_width_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(6, 8)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	var big := _text(text.to_upper(), roundi(panel_w * 0.06), panel_w * 0.9)
	col.add_child(big)
	if sub != "":
		var small := _text(sub.to_upper(), roundi(panel_w * 0.032), panel_w * 0.9)
		col.add_child(small)
	return card


func _text(text: String, size: int, max_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.BLACK)
	l.add_theme_constant_override("line_spacing", -4)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = max_w
	return l


## Out of sight behind the page: the player goes to the front of the
## station (main.gd send_player_to), on foot, so the streets there load
## while the page plays.
func _let_out() -> void:
	var scene := get_tree().current_scene
	var wanted := get_tree().root.get_node_or_null("Wanted")
	if scene == null or wanted == null or not scene.has_method("send_player_to"):
		return
	var world := scene.get_node_or_null("World")
	if world == null or not bool(world.get("is_built")):
		return
	scene.call("send_player_to", wanted.call("station_xform", world))


## Keeps the player still while the page is up.
func _hold_player(on: bool) -> void:
	var p := get_tree().get_first_node_in_group(PlayerController.GROUP)
	if p == null:
		return
	if on:
		p.set("input_enabled", false)
	elif p.get("vehicle") == null:
		p.set("input_enabled", true)


func _finish() -> void:
	if _done:
		return
	_done = true
	_hold_player(false)
	var wanted := get_tree().root.get_node_or_null("Wanted")
	if wanted != null:
		if bool(result.get("dismissed", false)):
			wanted.emit_signal("announced", "Case dismissed", JailLines.radio(wanted.get("rng")))
		elif int(result.get("fine", 0)) > 0:
			wanted.emit_signal("announced", "Out on the street", "Fine paid: %s. Your car's where you left it." % JailLines.dollars(int(result["fine"])))
		else:
			wanted.emit_signal("announced", "Out on the street", "No fine. Your car's where you left it.")
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())

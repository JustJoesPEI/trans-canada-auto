class_name TitleCard
extends Control
## A mission's opening title, a few seconds over the game before it starts.
## Each mission can borrow the look of the game it's a homage to: a style in
## STYLES says the font, slant, colours, film tint and grain, letterbox
## bars, the stripe under the title, how the title comes in and the sting.
## The next mission inspired by another game gets its own entry here and
## the card does the rest.
##
##   var card := TitleCard.new(); parent.add_child(card)
##   card.show_card("garage", title, subtitle, credit)
##   await card.done
##
## Drawn with Labels and rects only: no textures, no shaders.

signal done

## How long the card holds once it's all in, and how long it takes to go.
const HOLD := 2.2
const OUT := 0.45

## A style:
##   font       res:// path of the title's font
##   size       the title's size at 1080 px tall
##   slant      how far it leans (0 upright; 0.25 is a good italic)
##   colour     the title's face; shadow its drop shadow (offset px);
##              outline its edge colour and outline_px its width
##   sub_colour the subtitle's colour (Bebas); credit_colour the credit's
##   tint       the screen washed over (alpha is how strong)
##   grain      0..1, film grain over everything
##   bars       0..1 of the screen's height each letterbox bar takes
##   stripe     colours of the stripes under the title, top down ([] none)
##   enter      "slide" (in from the left, with a streak) or "zoom"
##   sting      a MissionSounds function name ("" for none)
const STYLES := {
	# The Garage: a 70s car-chase movie opener, the look of the 1999 game it
	# sends up. Heavy slanted letters, gold over a brown shadow, a racing
	# stripe in orange and brown, warm film and letterbox bars.
	"garage": {
		"font": "res://branding/fonts/Anton-Regular.ttf", "size": 150, "slant": 0.28,
		"colour": Color(1.0, 0.82, 0.36), "shadow": Color(0.62, 0.22, 0.05), "shadow_px": 7,
		"outline": Color(0.12, 0.05, 0.02), "outline_px": 10,
		"sub_colour": Color(1.0, 0.93, 0.8), "credit_colour": Color(0.95, 0.62, 0.3),
		"tint": Color(0.55, 0.3, 0.08, 0.38), "grain": 0.6, "bars": 0.13,
		"stripe": [Color(0.98, 0.55, 0.12), Color(0.82, 0.32, 0.08), Color(0.45, 0.22, 0.08)],
		"enter": "slide", "sting": "garage_sting",
	},
}

var _style: Dictionary
var _t := -1.0
var _total := 0.0
var _tint: ColorRect
var _bars: Array[ColorRect] = []
var _title: Label
var _ghosts: Array[Label] = [] ## the streak behind the title as it slides in
var _sub: Label
var _credit: Label
var _stripes: Array[ColorRect] = []
var _grain_seed := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


static func style(id: String) -> Dictionary:
	return STYLES.get(id, STYLES["garage"])


func show_card(style_id: String, title: String, subtitle := "", credit := "") -> void:
	for c in get_children():
		c.queue_free()
	_bars.clear()
	_ghosts.clear()
	_stripes.clear()
	_style = style(style_id)
	_tint = ColorRect.new()
	_tint.color = Color(_style["tint"], 0.0)
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	for i in 2:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(b)
		_bars.append(b)
	for c: Color in _style["stripe"]:
		var s := ColorRect.new()
		s.color = c
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		_stripes.append(s)
	var font := FontVariation.new()
	font.base_font = load(str(_style["font"])) as Font
	font.variation_transform = Transform2D(Vector2(1, 0), Vector2(float(_style["slant"]), 1), Vector2.ZERO)
	font.spacing_glyph = 2
	for i in 3:
		var g := _title_label(font, title)
		g.modulate.a = 0.0
		_ghosts.append(g)
	_title = _title_label(font, title)
	_sub = HudStyle.label(30, true, _style["sub_colour"])
	_sub.text = subtitle
	_sub.add_theme_constant_override("outline_size", 6)
	add_child(_sub)
	_credit = HudStyle.label(18, true, _style["credit_colour"])
	_credit.text = credit
	add_child(_credit)
	_t = 0.0
	_total = 1.2 + HOLD + OUT
	visible = true
	_layout()
	var sting := str(_style.get("sting", ""))
	if sting != "":
		MissionSounds.play(self, MissionSounds.named(sting), -3.0)


func _title_label(font: Font, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", _style["colour"])
	l.add_theme_color_override("font_outline_color", _style["outline"])
	l.add_theme_constant_override("outline_size", int(_style["outline_px"]))
	l.add_theme_color_override("font_shadow_color", _style["shadow"])
	l.add_theme_constant_override("shadow_offset_x", int(_style["shadow_px"]))
	l.add_theme_constant_override("shadow_offset_y", int(_style["shadow_px"]))
	l.add_theme_constant_override("shadow_outline_size", int(_style["outline_px"]))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


## Skips to the end (a key pressed).
func skip() -> void:
	if _t >= 0.0 and _t < 1.2 + HOLD:
		_t = 1.2 + HOLD


func is_showing() -> bool:
	return _t >= 0.0


func _scale() -> float:
	return maxf(0.5, get_viewport_rect().size.y / 1080.0)


func _layout() -> void:
	var vs := get_viewport_rect().size
	var k := _scale()
	_title.add_theme_font_size_override("font_size", int(float(_style["size"]) * k))
	for g in _ghosts:
		g.add_theme_font_size_override("font_size", int(float(_style["size"]) * k))
	_sub.add_theme_font_size_override("font_size", int(30 * k))
	_credit.add_theme_font_size_override("font_size", int(18 * k))
	_title.size = Vector2(vs.x, 0)
	_title.reset_size()
	_title.size.x = vs.x


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var vs := get_viewport_rect().size
	var k := _scale()
	# Going: everything fades together.
	var out := clampf((_t - 1.2 - HOLD) / OUT, 0.0, 1.0)
	var fade := 1.0 - out
	# The tint and the bars, in over the first 0.35 s.
	var come := _ease(clampf(_t / 0.35, 0.0, 1.0))
	var tint: Color = _style["tint"]
	_tint.color = Color(tint, tint.a * come * fade)
	_tint.position = Vector2.ZERO
	_tint.size = vs
	var bar_h := vs.y * float(_style["bars"]) * come * (1.0 - _ease(out))
	_bars[0].position = Vector2(0, 0)
	_bars[0].size = Vector2(vs.x, bar_h)
	_bars[1].position = Vector2(0, vs.y - bar_h)
	_bars[1].size = Vector2(vs.x, bar_h)
	# The title: from 0.3 s, in from the left with a little overshoot.
	var th := _title.get_combined_minimum_size().y
	var ty := vs.y * 0.5 - th * 0.62
	var a := clampf((_t - 0.3) / 0.45, 0.0, 1.0)
	var x := 0.0
	if str(_style["enter"]) == "slide":
		x = lerpf(-vs.x * 1.1, 0.0, _back(a))
		_title.scale = Vector2.ONE
	else:
		_title.pivot_offset = Vector2(vs.x * 0.5, th * 0.5)
		_title.scale = Vector2.ONE * lerpf(3.0, 1.0, _ease(a))
	_title.position = Vector2(x, ty)
	_title.size.x = vs.x
	_title.modulate.a = (1.0 if a > 0.0 else 0.0) * fade
	# The streak: copies behind it, further back the faster it's moving.
	var speed := absf(x) / vs.x
	for i in _ghosts.size():
		var g := _ghosts[i]
		g.position = Vector2(x - (i + 1) * 90.0 * k * speed * 4.0, ty)
		g.size.x = vs.x
		g.modulate.a = 0.3 / (i + 1) * minf(speed * 6.0, 1.0) * (1.0 if a > 0.0 else 0.0) * fade
	# The stripes grow out from the middle once it's landed.
	var sa := _ease(clampf((_t - 0.7) / 0.35, 0.0, 1.0))
	var sy := ty + th * 0.92
	var sw := vs.x * 0.56 * sa
	var sh := 7.0 * k
	for i in _stripes.size():
		var s := _stripes[i]
		s.size = Vector2(sw, sh)
		s.position = Vector2(vs.x * 0.5 - sw * 0.5 + i * 10.0 * k, sy + i * (sh + 3.0 * k))
		s.modulate.a = fade
	# The subtitle and the credit fade up.
	var below := sy + _stripes.size() * (sh + 3.0 * k) + 16.0 * k
	var ua := clampf((_t - 0.95) / 0.3, 0.0, 1.0) * fade
	_sub.position = Vector2(vs.x * 0.5 - _sub.get_combined_minimum_size().x * 0.5, below)
	_sub.modulate.a = ua
	_credit.position = Vector2(vs.x * 0.5 - _credit.get_combined_minimum_size().x * 0.5, ty - 30.0 * k)
	_credit.modulate.a = clampf((_t - 1.1) / 0.3, 0.0, 1.0) * fade
	_grain_seed += 1
	queue_redraw()
	if _t >= _total:
		_t = -1.0
		visible = false
		done.emit()


## Film grain, drawn over the tint (under the labels, which are children).
func _draw() -> void:
	if _t < 0.0:
		return
	var g := float(_style.get("grain", 0.0))
	if g <= 0.0:
		return
	var vs := get_viewport_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = _grain_seed
	var fade := 1.0 - clampf((_t - 1.2 - HOLD) / OUT, 0.0, 1.0)
	var n := int(500 * g)
	for i in n:
		var p := Vector2(rng.randf() * vs.x, rng.randf() * vs.y)
		var bright := rng.randf() < 0.5
		var c := Color(1, 0.95, 0.85, 0.12 * fade) if bright else Color(0.1, 0.05, 0.0, 0.16 * fade)
		var s := rng.randf_range(1.0, 2.6)
		draw_rect(Rect2(p, Vector2(s, s)), c)
	# A scratch or two down the film now and then.
	if rng.randf() < 0.25:
		var sx := rng.randf() * vs.x
		draw_line(Vector2(sx, 0), Vector2(sx + rng.randf_range(-8, 8), vs.y), Color(1, 0.95, 0.85, 0.12 * fade), 1.0)


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


## Ease out with a little overshoot past the end.
static func _back(x: float) -> float:
	var c := 1.6
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

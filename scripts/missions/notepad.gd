class_name Notepad
extends Control
## The list of moves on a page torn out of a pocket notepad, in blue pen:
## crumpled (creases, a coffee ring), tilted, slapped onto the right of the
## screen when the test starts. Each move done gets a wobbly pen line
## scratched through it as you watch. All drawn in _draw (no textures).
##
##   set_list(items)          [[id, text, note], ...]
##   cross_out(id)            scratches one out
##   write_extra(text)        red marker at the bottom ("ROOF??")
##   slap_in() / slide_out()

const W := 410.0 ## the page at 1080 px tall
const H := 480.0
const TILT := -3.5 ## degrees
const ROW := 37.0
const TOP := 92.0 ## the first row's baseline
const MARGIN := 44.0
const PAPER := Color(0.97, 0.95, 0.86)
const RULE := Color(0.45, 0.62, 0.86, 0.55)
const MARGIN_LINE := Color(0.88, 0.32, 0.32, 0.6)
const INK := Color(0.1, 0.16, 0.52)
const RED := Color(0.82, 0.1, 0.1)
const PEN_FONT := "res://branding/fonts/Caveat-Variable.ttf"
const MARKER_FONT := "res://branding/fonts/PermanentMarker-Regular.ttf"

var head := ""
var sub := ""
var _items: Array = []
var _crossed := {} ## id -> 0..1, how far the line's gone
var _extra := ""
var _extra_t := 0.0
var _in := 0.0 ## 0 off to the right, 1 in place
var _going := false
var _pen: Font
var _pen_bold: Font
var _marker: Font
var _torn := PackedVector2Array() ## the torn top edge, page space
var _creases: Array = [] ## [from, to] in page space


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var base := load(PEN_FONT) as Font
	_pen = _weight(base, 500)
	_pen_bold = _weight(base, 700)
	_marker = load(MARKER_FONT) as Font
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	# Torn along the top where it came off the pad: little teeth.
	var x := 0.0
	while x < W:
		_torn.append(Vector2(x, rng.randf_range(0.0, 7.0)))
		x += rng.randf_range(5.0, 11.0)
	_torn.append(Vector2(W, rng.randf_range(0.0, 6.0)))
	# Creases from being stuffed in a jacket: two across, one corner.
	_creases = [[Vector2(0, H * 0.38), Vector2(W, H * 0.44)], [Vector2(0, H * 0.71), Vector2(W, H * 0.66)],
		[Vector2(W * 0.62, H), Vector2(W, H * 0.8)]]
	visible = false


static func _weight(base: Font, w: int) -> Font:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return f


func set_list(items: Array) -> void:
	_items = items
	_crossed.clear()
	_extra = ""
	queue_redraw()


func cross_out(id: String) -> void:
	if not _crossed.has(id):
		_crossed[id] = 0.0
		MissionSounds.play(self, MissionSounds.scribble(), -4.0, randf_range(0.95, 1.08))


func is_crossed(id: String) -> bool:
	return _crossed.has(id)


func write_extra(text: String) -> void:
	_extra = text
	_extra_t = 0.0


func slap_in() -> void:
	visible = true
	_going = false
	_in = 0.0


func slide_out() -> void:
	_going = true


func _scale() -> float:
	return maxf(0.5, get_viewport_rect().size.y / 1080.0)


func _process(delta: float) -> void:
	if not visible:
		return
	if _going:
		_in = maxf(0.0, _in - delta * 3.0)
		if _in <= 0.0:
			visible = false
	else:
		_in = minf(1.0, _in + delta * 2.6)
	for id: String in _crossed:
		_crossed[id] = minf(1.0, float(_crossed[id]) + delta / 0.35)
	if _extra != "":
		_extra_t = minf(1.0, _extra_t + delta / 0.5)
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var k := _scale()
	# In place: right side, a little above the middle. Slapped in: from off
	# the right, turning, with an overshoot.
	var e := _back(_in) if not _going else _in
	var home := Vector2(vs.x - (W + 34.0) * k, vs.y * 0.17)
	var pos := home.lerp(Vector2(vs.x + 40.0 * k, vs.y * 0.1), 1.0 - e)
	var ang := deg_to_rad(TILT + (1.0 - e) * 18.0)
	draw_set_transform(pos, ang, Vector2(k, k))
	var page := PackedVector2Array()
	for p in _torn:
		page.append(p)
	page.append(Vector2(W, H))
	page.append(Vector2(0, H))
	# Its shadow, then the page.
	var shadow := PackedVector2Array()
	for p in page:
		shadow.append(p + Vector2(6, 8))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(page, PAPER)
	# Ruled lines and the margin.
	var y := TOP - ROW + 6.0
	while y < H - 8.0:
		draw_line(Vector2(4, y), Vector2(W - 4, y), RULE, 1.4)
		y += ROW
	draw_line(Vector2(MARGIN, 14), Vector2(MARGIN, H - 4), MARGIN_LINE, 1.6)
	# Creases: a light line with a shadow beside it.
	for c: Array in _creases:
		draw_line(c[0], c[1], Color(0, 0, 0, 0.08), 3.0)
		draw_line((c[0] as Vector2) + Vector2(0, 2), (c[1] as Vector2) + Vector2(0, 2), Color(1, 1, 1, 0.5), 1.5)
	# A coffee ring in the corner, not quite closed.
	var ring := Vector2(W - 70, H - 78)
	draw_arc(ring, 46.0, 0.3, 5.6, 40, Color(0.55, 0.36, 0.16, 0.22), 5.0, true)
	draw_arc(ring + Vector2(2, 1), 43.0, 0.5, 4.9, 40, Color(0.55, 0.36, 0.16, 0.12), 2.0, true)
	# The heading, underlined.
	draw_string(_pen_bold, Vector2(MARGIN + 10, 46), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, INK)
	var hw := _pen_bold.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	_wobbly(Vector2(MARGIN + 8, 54), Vector2(MARGIN + 14 + hw, 51), INK, 2.2, 1.0, 7)
	draw_string(_pen, Vector2(MARGIN + 18 + hw, 46), sub, HORIZONTAL_ALIGNMENT_LEFT, W - MARGIN - 30 - hw, 20, INK)
	# The moves.
	for i in _items.size():
		var it: Array = _items[i]
		var by := TOP + i * ROW
		var text := str(it[1])
		var note := str(it[2])
		draw_string(_pen_bold, Vector2(MARGIN + 10, by), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 29, INK)
		var tw := _pen_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 29).x
		if note != "":
			draw_string(_pen, Vector2(MARGIN + 18 + tw, by), note, HORIZONTAL_ALIGNMENT_LEFT, W - MARGIN - 26 - tw, 19, INK.lightened(0.15))
		var id := str(it[0])
		if _crossed.has(id):
			var t := float(_crossed[id])
			var full := tw + (8.0 + _pen.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x if note != "" else 0.0)
			full = minf(full, W - MARGIN - 30)
			_wobbly(Vector2(MARGIN + 4, by - 9), Vector2(MARGIN + 14 + full, by - 11), INK, 3.0, t, hash(id))
			# A tick in the margin once the line's through.
			if t >= 1.0:
				var c := Vector2(MARGIN - 24, by - 10)
				draw_polyline(PackedVector2Array([c + Vector2(-7, -1), c + Vector2(-1, 7), c + Vector2(11, -10)]), INK, 3.0, true)
	# Red marker at the bottom.
	if _extra != "":
		var p := Vector2(MARGIN + 30, H - 30)
		draw_string(_marker, p, _extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(RED, minf(1.0, _extra_t * 2.0)))
		var ew := _marker.get_string_size(_extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_wobbly(p + Vector2(-4, 8), p + Vector2(ew + 6, 6), RED, 3.0, clampf(_extra_t * 2.0 - 0.6, 0.0, 1.0), 5)
		_wobbly(p + Vector2(0, 15), p + Vector2(ew + 2, 14), RED, 2.5, clampf(_extra_t * 2.0 - 1.0, 0.0, 1.0), 9)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A hand-drawn line from a to b, `t` of the way along, wobbling.
func _wobbly(a: Vector2, b: Vector2, c: Color, width: float, t: float, seed_value: int) -> void:
	if t <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := 14
	var pts := PackedVector2Array()
	var normal := (b - a).orthogonal().normalized()
	for i in n + 1:
		var f := float(i) / n
		if f > t:
			pts.append(a.lerp(b, t) + normal * rng.randf_range(-1.6, 1.6))
			break
		pts.append(a.lerp(b, f) + normal * rng.randf_range(-1.8, 1.8))
	if pts.size() >= 2:
		draw_polyline(pts, c, width, true)


static func _back(x: float) -> float:
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

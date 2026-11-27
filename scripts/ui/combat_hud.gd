class_name CombatHud
extends Control
## The paintball fight on screen, round the crosshair and low in the
## middle (docs/design.md section 2, "Feel"): you always know when you've
## been hit, where from, and how many more you can take.
##
##   * The paint meter: OUT_HITS segments low in the middle, filling orange
##     as hits land (a fresh one flashes white), and visibly draining once
##     you're out of the fire (BodyPaint's regen). Shown while there's paint
##     on the meter, and while aiming.
##   * Where a hit came from: an arc round the crosshair pointing at the
##     shooter, in their paint colour, fading over HIT_ARROW_TIME. It turns
##     with the view, so you can swing round onto it.
##   * Nearly out (one or two hits left): the screen's edges go the
##     colour of the last paint that hit you, pulsing, so you know to get
##     out of there without looking down.
##
## Drawn with a handful of lines and polygons, redrawn only while something
## is moving.

const HIT_ARROW_TIME := 1.1 ## s an arrow stays
const ARROW_RADIUS := 92.0 ## px from the middle
const ARROW_SPAN := 0.42 ## radians of arc
const MAX_ARROWS := 6
const SEG_W := 20.0
const SEG_H := 9.0
const SEG_GAP := 4.0
const FLASH_TIME := 0.25 ## s a fresh segment flashes
const LOW_LEFT := 2 ## hits left at which the edges warn
const METER_COLOUR := Color(1.0, 0.5, 0.1)

var _player: Node3D
var _paint: BodyPaint
## [{from: Vector3 (world), colour: Color, t: s left}]
var _arrows: Array[Dictionary] = []
var _flash := 0.0
var _last_colour := Color(1.0, 0.36, 0.0)
var _hits := 0
var _aiming := false
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(player: Node3D) -> void:
	_player = player
	_paint = player.get("body_paint") as BodyPaint
	if _paint != null:
		_paint.took_hit.connect(_on_hit)


func _on_hit(shooter: Node, value: int) -> void:
	var from := Vector3.INF
	if shooter != null and is_instance_valid(shooter) and shooter is Node3D:
		from = (shooter as Node3D).global_position
		_last_colour = PaintShots.colour_of(shooter)
	if from != Vector3.INF:
		_arrows.append({"from": from, "colour": _last_colour, "t": HIT_ARROW_TIME})
		while _arrows.size() > MAX_ARROWS:
			_arrows.pop_front()
	if value > 0:
		_flash = FLASH_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if _paint == null:
		return
	var busy := false
	for a in _arrows:
		a["t"] = float(a["t"]) - delta
	_arrows = _arrows.filter(func(a: Dictionary) -> bool: return float(a["t"]) > 0.0)
	busy = not _arrows.is_empty()
	if _flash > 0.0:
		_flash -= delta
		busy = true
	var aiming := bool(_player.get("aiming"))
	if _paint.hits != _hits or aiming != _aiming:
		_hits = _paint.hits
		_aiming = aiming
		busy = true
	if _paint.is_regenerating() or _low():
		busy = true
	_pulse += delta
	if busy:
		queue_redraw()


func _low() -> bool:
	return _paint.can_go_out and not _paint.out and _paint.hits > 0 and _paint.out_hits - _paint.hits <= LOW_LEFT


func _draw() -> void:
	if _paint == null:
		return
	var mid := size * 0.5
	_draw_edges()
	_draw_arrows(mid)
	if _paint.hits > 0 or _paint.out or (_aiming and _paint.can_go_out):
		_draw_meter(Vector2(mid.x, size.y - 150.0))


## The meter: a segment a hit, filled from the left.
func _draw_meter(at: Vector2) -> void:
	var n := _paint.out_hits
	var w := n * SEG_W + (n - 1) * SEG_GAP
	var x0 := at.x - w * 0.5
	var regen := _paint.is_regenerating()
	var f := clampf(_flash / FLASH_TIME, 0.0, 1.0)
	for i in n:
		var r := Rect2(x0 + i * (SEG_W + SEG_GAP), at.y - SEG_H * 0.5, SEG_W, SEG_H)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
		if i < _paint.hits:
			var c := METER_COLOUR
			if regen:
				# Draining: the meter breathes lighter.
				c = c.lerp(Color(1, 0.85, 0.6), 0.25 + 0.25 * sin(_pulse * 12.0))
			if i == _paint.hits - 1 and f > 0.0:
				c = c.lerp(Color.WHITE, f)
				draw_rect(r.grow(2.0 * f), c)
			else:
				draw_rect(r, c)
		else:
			draw_rect(r, Color(1, 1, 1, 0.2))


## Arcs round the crosshair towards whoever hit you.
func _draw_arrows(mid: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _arrows.is_empty():
		return
	var view := cam.global_basis
	var fwd := -view.z
	fwd.y = 0.0
	var right := view.x
	right.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	right = right.normalized()
	var me := _player.global_position
	for a in _arrows:
		var to: Vector3 = (a["from"] as Vector3) - me
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		# 0 is straight ahead (up the screen), turning clockwise to the right.
		var ang := atan2(to.dot(right), to.dot(fwd))
		var screen := ang - PI * 0.5
		var alpha := clampf(float(a["t"]) / HIT_ARROW_TIME, 0.0, 1.0)
		var c: Color = a["colour"]
		draw_arc(mid, ARROW_RADIUS, screen - ARROW_SPAN * 0.5, screen + ARROW_SPAN * 0.5, 16, Color(0, 0, 0, 0.55 * alpha), 9.0, true)
		draw_arc(mid, ARROW_RADIUS, screen - ARROW_SPAN * 0.5, screen + ARROW_SPAN * 0.5, 16, Color(c.r, c.g, c.b, 0.95 * alpha), 5.0, true)
		# A point on the outside, so it reads as "from there".
		var d := Vector2.from_angle(screen)
		var tip := mid + d * (ARROW_RADIUS + 14.0)
		var side := d.orthogonal() * 7.0
		var base := mid + d * (ARROW_RADIUS + 3.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(c.r, c.g, c.b, 0.95 * alpha))


## Nearly out: the edges of the screen in the paint's colour, pulsing.
func _draw_edges() -> void:
	if not _low():
		return
	var left := _paint.out_hits - _paint.hits
	var strength := (0.32 if left <= 1 else 0.2) * (0.75 + 0.25 * sin(_pulse * 6.0))
	var c := _last_colour
	var solid := Color(c.r, c.g, c.b, strength)
	var clear := Color(c.r, c.g, c.b, 0.0)
	var band := minf(size.x, size.y) * 0.16
	var w := size.x
	var h := size.y
	# Four bands, solid at the edge and clear inside.
	_band([Vector2(0, 0), Vector2(w, 0), Vector2(w - band, band), Vector2(band, band)], solid, clear)
	_band([Vector2(0, h), Vector2(band, h - band), Vector2(w - band, h - band), Vector2(w, h)], solid, clear)
	_band([Vector2(0, 0), Vector2(band, band), Vector2(band, h - band), Vector2(0, h)], solid, clear)
	_band([Vector2(w, 0), Vector2(w, h), Vector2(w - band, h - band), Vector2(w - band, band)], solid, clear)


func _band(p: Array, edge: Color, inner: Color) -> void:
	# The first two points are on the screen's edge, the other two inside
	# (in each band above, the inside pair are the ones a band in).
	var pts := PackedVector2Array(p)
	var cols := PackedColorArray()
	for i in pts.size():
		var on_edge := pts[i].x <= 0.5 or pts[i].y <= 0.5 or pts[i].x >= size.x - 0.5 or pts[i].y >= size.y - 0.5
		cols.append(edge if on_edge else inner)
	draw_polygon(pts, cols)

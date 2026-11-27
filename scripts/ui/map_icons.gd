class_name MapIcons
extends RefCounted
## The little pictures for places on the map (WorldMap): a coloured disc
## with a white glyph, drawn from a few shapes (no textures), plus the
## waypoint pin and your arrow, which the minimap and the HUD's screen marker
## share. `k` scales everything (1 at 1600 x 900).

const DARK := Color(0, 0, 0, 0.75)


static func draw(ci: CanvasItem, kind: String, at: Vector2, k: float, font: Font) -> void:
	var c := WorldMap.kind_colour(kind)
	var r := 8.0 * k
	ci.draw_circle(at, r + 1.6 * k, DARK)
	ci.draw_circle(at, r, c)
	var w := Color(1, 1, 1, 0.95)
	var s := k
	match kind:
		"park":
			# A tree.
			ci.draw_colored_polygon(_pts(at, s, [Vector2(0, -5.5), Vector2(4.5, 2.5), Vector2(-4.5, 2.5)]), w)
			ci.draw_rect(Rect2(at + Vector2(-0.9, 2.0) * s, Vector2(1.8, 3.0) * s), w)
		"golf":
			# A flag on a pin.
			ci.draw_line(at + Vector2(-1.5, -5) * s, at + Vector2(-1.5, 5) * s, w, 1.4 * s)
			ci.draw_colored_polygon(_pts(at, s, [Vector2(-1, -5), Vector2(4.5, -3), Vector2(-1, -1)]), w)
		"cemetery", "church":
			# A cross.
			ci.draw_rect(Rect2(at + Vector2(-0.9, -5) * s, Vector2(1.8, 10) * s), w)
			ci.draw_rect(Rect2(at + Vector2(-3.5, -2.6) * s, Vector2(7, 1.8) * s), w)
		"water", "car_wash":
			# A drop.
			var drop := PackedVector2Array([at + Vector2(0, -5.5) * s])
			for i in 11:
				var a := -PI * 0.5 + 0.7 + (TAU - 1.4) * i / 10.0
				drop.append(at + (Vector2(cos(a), sin(a)) * 3.6 + Vector2(0, 1.3)) * s)
			ci.draw_colored_polygon(drop, w)
		"marina":
			# A sail.
			ci.draw_colored_polygon(_pts(at, s, [Vector2(0, -5.5), Vector2(4, 2), Vector2(0, 2)]), w)
			ci.draw_colored_polygon(_pts(at, s, [Vector2(-4.5, 3), Vector2(4.5, 3), Vector2(3, 5), Vector2(-3, 5)]), w)
		"sport":
			# A track.
			ci.draw_arc(at, 4.0 * s, 0.0, TAU, 16, w, 1.6 * s, true)
			ci.draw_circle(at, 1.2 * s, w)
		"school":
			# A mortarboard.
			ci.draw_colored_polygon(_pts(at, s, [Vector2(0, -4.5), Vector2(6, -1.5), Vector2(0, 1.5), Vector2(-6, -1.5)]), w)
			ci.draw_rect(Rect2(at + Vector2(-3, 0) * s, Vector2(6, 3) * s), w)
		"landmark":
			_star(ci, at, 5.5 * s, w)
		"coffee":
			# A cup.
			ci.draw_rect(Rect2(at + Vector2(-3.5, -3) * s, Vector2(6, 6.5) * s), w)
			ci.draw_arc(at + Vector2(3, 0) * s, 2.0 * s, -PI * 0.5, PI * 0.5, 8, w, 1.4 * s)
		"food":
			# A fork and knife.
			ci.draw_line(at + Vector2(-2, -5) * s, at + Vector2(-2, 5) * s, w, 1.5 * s)
			ci.draw_line(at + Vector2(-3.6, -5) * s, at + Vector2(-3.6, -1.5) * s, w, 1.0 * s)
			ci.draw_line(at + Vector2(-0.4, -5) * s, at + Vector2(-0.4, -1.5) * s, w, 1.0 * s)
			ci.draw_colored_polygon(_pts(at, s, [Vector2(2, -5), Vector2(4, -2), Vector2(3, 0), Vector2(3, 5), Vector2(2, 5)]), w)
		"gas":
			# A pump.
			ci.draw_rect(Rect2(at + Vector2(-3.5, -4.5) * s, Vector2(5, 9) * s), w)
			ci.draw_rect(Rect2(at + Vector2(-2.5, -3.5) * s, Vector2(3, 2.5) * s), WorldMap.kind_colour(kind))
			ci.draw_line(at + Vector2(1.5, -2) * s, at + Vector2(3.8, 0) * s, w, 1.2 * s)
			ci.draw_line(at + Vector2(3.8, 0) * s, at + Vector2(3.8, 3.5) * s, w, 1.2 * s)
		"grocery", "shop", "cinema":
			# A bag.
			ci.draw_rect(Rect2(at + Vector2(-4, -1.5) * s, Vector2(8, 6) * s), w)
			ci.draw_arc(at + Vector2(0, -1.5) * s, 2.4 * s, PI, TAU, 8, w, 1.3 * s)
		"dealer":
			# A car.
			ci.draw_colored_polygon(_pts(at, s, [Vector2(-5, 2), Vector2(-5, -0.5), Vector2(-3, -1), Vector2(-1.5, -3.5), Vector2(2, -3.5), Vector2(3.5, -1), Vector2(5, -0.5), Vector2(5, 2)]), w)
			ci.draw_circle(at + Vector2(-2.8, 2.4) * s, 1.4 * s, DARK)
			ci.draw_circle(at + Vector2(2.8, 2.4) * s, 1.4 * s, DARK)
		"police_station":
			ci.draw_colored_polygon(_pts(at, s, [Vector2(0, -5.5), Vector2(4.5, -3.8), Vector2(4.5, 0), Vector2(0, 5.5), Vector2(-4.5, 0), Vector2(-4.5, -3.8)]), w)
			ci.draw_circle(at + Vector2(0, -0.8) * s, 1.6 * s, WorldMap.kind_colour(kind))
		"job_board":
			# A briefcase.
			ci.draw_rect(Rect2(at + Vector2(-5, -2.5) * s, Vector2(10, 7) * s), w)
			ci.draw_rect(Rect2(at + Vector2(-2, -4.5) * s, Vector2(4, 2.2) * s), w, false, 1.2 * s)
		"property":
			# A house.
			ci.draw_colored_polygon(_pts(at, s, [Vector2(0, -5.5), Vector2(5, -0.5), Vector2(3.5, -0.5), Vector2(3.5, 4.5), Vector2(-3.5, 4.5), Vector2(-3.5, -0.5), Vector2(-5, -0.5)]), w)
		"mission":
			# A steering wheel.
			ci.draw_arc(at, 4.4 * s, 0.0, TAU, 18, w, 1.6 * s, true)
			ci.draw_circle(at, 1.4 * s, w)
			for a: float in [PI * 0.5, PI * 1.17, PI * 1.83]:
				ci.draw_line(at, at + Vector2(cos(a), sin(a)) * 4.2 * s, w, 1.3 * s)
		"custom_shop":
			# A wrench.
			ci.draw_line(at + Vector2(-4, 4) * s, at + Vector2(2, -2) * s, w, 2.0 * s)
			ci.draw_arc(at + Vector2(2.8, -2.8) * s, 2.4 * s, PI * 0.9, PI * 2.6, 10, w, 1.6 * s)
		_:
			# A letter: $ for a bank, H for a hotel, P for parking.
			var letter := "$" if kind == "bank" else ("H" if kind == "hotel" else ("P" if kind == "parkade" else "?"))
			var fs := int(14 * s)
			var size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			ci.draw_string(font, at + Vector2(-size.x * 0.5, size.y * 0.32), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, w)


## The waypoint: a pin whose point is at `at`.
static func pin(ci: CanvasItem, at: Vector2, k: float) -> void:
	var head := at + Vector2(0, -15) * k
	var body := PackedVector2Array([at])
	for i in 13:
		var a := PI * 0.5 + 0.55 + (TAU - 1.1) * i / 12.0
		body.append(head + Vector2(cos(a), sin(a)) * 8.0 * k)
	var outline := body.duplicate()
	outline.append(body[0])
	ci.draw_polyline(outline, Color(0, 0, 0, 0.85), 3.5 * k, true)
	ci.draw_colored_polygon(body, HudStyle.WAYPOINT)
	ci.draw_circle(head, 3.0 * k, Color.WHITE)


## You: an arrow at `at`, pointing `angle` (0 up).
static func arrow(ci: CanvasItem, at: Vector2, angle: float, k: float) -> void:
	var shape := [Vector2(0, -9), Vector2(7, 7), Vector2(0, 3), Vector2(-7, 7)]
	var pts := PackedVector2Array()
	for q: Vector2 in shape:
		pts.append(at + q.rotated(angle) * k)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(0, 0, 0, 0.85), 3.5 * k, true)
	ci.draw_colored_polygon(pts, HudStyle.ACCENT)


static func _pts(at: Vector2, s: float, list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in list:
		out.append(at + p * s)
	return out


static func _star(ci: CanvasItem, at: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		pts.append(at + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, c)

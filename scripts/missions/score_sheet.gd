class_name ScoreSheet
extends Control
## The result as a road test sheet: a printed form filled in by hand, each
## move PASS or a dash, the time left on the meter, the examiner's remarks,
## and then the stamp comes down at an angle: HIRED in green, FAILED or
## TICKETED in red. The interact key goes again, Esc (or B) closes.
##
##   show_sheet({rows: [[label, passed]], lines: [String], remarks:
##               [String], stamp: String, passed: bool, money: String})

signal again
signal closed

const W := 560.0 ## at 1080 px tall
const PAPER := Color(0.96, 0.95, 0.9)
const PRINT := Color(0.18, 0.2, 0.24)
const FORM_BLUE := Color(0.2, 0.35, 0.6)
const INK := Notepad.INK
const GREEN := Color(0.12, 0.55, 0.22)
const RED := Color(0.8, 0.1, 0.08)

var _d := {}
var _t := -1.0
var _stamped := false
var _print: Font
var _pen: Font
var _stamp_font: Font
var _h := 600.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_print = load("res://branding/fonts/LiberationSans-Bold.ttf") as Font
	_pen = Notepad._weight(load(Notepad.PEN_FONT) as Font, 600)
	_stamp_font = load("res://branding/fonts/Anton-Regular.ttf") as Font
	visible = false


func show_sheet(d: Dictionary) -> void:
	_d = d
	_t = 0.0
	_stamped = false
	visible = true
	var rows: Array = d.get("rows", [])
	var remarks: Array = d.get("remarks", [])
	_h = 210.0 + rows.size() * 30.0 + 40.0 + remarks.size() * 44.0 + 70.0


func is_showing() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if not _stamped and _t > 0.9:
		_stamped = true
		MissionSounds.play(self, MissionSounds.stamp(), -1.0)
		MissionSounds.play(self, MissionSounds.result(bool(_d.get("passed", false))), -8.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or _t < 0.6:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		visible = false
		again.emit()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B and event.is_pressed()):
		get_viewport().set_input_as_handled()
		visible = false
		closed.emit()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var k := maxf(0.5, vs.y / 1080.0)
	# Dim the game behind it.
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45 * minf(1.0, _t * 4.0)))
	# Slides up from below.
	var e := 1.0 - pow(1.0 - clampf(_t / 0.4, 0.0, 1.0), 3.0)
	var pos := Vector2((vs.x - W * k) * 0.5, lerpf(vs.y + 20.0, (vs.y - _h * k) * 0.5, e))
	draw_set_transform(pos, deg_to_rad(1.2), Vector2(k, k))
	draw_rect(Rect2(8, 10, W, _h), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, 0, W, _h), PAPER)
	# The printed form.
	draw_rect(Rect2(0, 0, W, 58), FORM_BLUE)
	draw_string(_print, Vector2(24, 40), str(_d.get("head", GarageLines.SHEET_HEAD)), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_string(_print, Vector2(W - 150, 38), "FORM 99-G", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.75))
	var y := 92.0
	for line: String in _d.get("lines", []):
		var parts := line.split(":", true, 1)
		draw_string(_print, Vector2(24, y), parts[0] + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PRINT)
		if parts.size() > 1:
			var lw := _print.get_string_size(parts[0] + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(_pen, Vector2(34 + lw, y + 1), parts[1].strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, W - 60 - lw, 26, INK)
		draw_line(Vector2(24, y + 7), Vector2(W - 24, y + 7), Color(PRINT, 0.25), 1.0)
		y += 34.0
	y += 8.0
	draw_string(_print, Vector2(24, y), "MANOEUVRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FORM_BLUE)
	draw_string(_print, Vector2(W - 150, y), "RESULT", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FORM_BLUE)
	y += 10.0
	for row: Array in _d.get("rows", []):
		y += 30.0
		draw_string(_print, Vector2(24, y), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PRINT)
		draw_string(_pen, Vector2(W - 150, y + 2), "PASS" if bool(row[1]) else "—", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK if bool(row[1]) else RED)
		draw_line(Vector2(24, y + 8), Vector2(W - 24, y + 8), Color(PRINT, 0.15), 1.0)
	y += 44.0
	draw_string(_print, Vector2(24, y), "EXAMINER'S REMARKS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FORM_BLUE)
	for r: String in _d.get("remarks", []):
		y += 40.0
		draw_multiline_string(_pen, Vector2(24, y), r, HORIZONTAL_ALIGNMENT_LEFT, W - 48, 26, 2, INK)
		if _pen.get_string_size(r, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x > W - 48:
			y += 28.0
	# Money in or out, and the keys.
	var money := str(_d.get("money", ""))
	if money != "":
		draw_string(_print, Vector2(24, _h - 22), money, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GREEN if bool(_d.get("passed", false)) else RED)
	draw_string(_print, Vector2(0, _h - 22), "%s  Again     Esc  Done  " % _key(), HORIZONTAL_ALIGNMENT_RIGHT, W - 20, 16, PRINT)
	# The stamp: big and turned, coming down hard.
	if _t > 0.6:
		var s := clampf((_t - 0.6) / 0.3, 0.0, 1.0)
		var sc := lerpf(2.4, 1.0, s * s)
		var col := GREEN if bool(_d.get("passed", false)) else RED
		col.a = 0.85 * s
		var text := str(_d.get("stamp", ""))
		var size := 76
		var tw := _stamp_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var centre := Vector2(W * 0.66, _h * 0.34)
		var xf := Transform2D(deg_to_rad(-14.0), Vector2(sc, sc), 0.0, pos + centre * k)
		draw_set_transform_matrix(xf.scaled_local(Vector2(k, k)))
		var box := Rect2(-tw * 0.5 - 20, -size * 0.5 - 14, tw + 40, size + 22)
		draw_rect(box, col, false, 7.0)
		draw_rect(box.grow(-11), Color(col, col.a * 0.6), false, 2.5)
		draw_string(_stamp_font, Vector2(-tw * 0.5, size * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _key() -> String:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("key_for"):
		return str(hud.call("key_for", "interact"))
	return "E"

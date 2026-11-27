class_name MeterDisplay
extends Control
## The parking meter's window under the notepad: "METER" over the time left
## in big Bebas, in a grey meter head with a red EXPIRED flag that comes up
## at zero. Gold while there's time, orange under 20 s, red and pulsing
## under 10, ticking the last five.

const W := 210.0 ## at 1080 px tall
const H := 132.0

var seconds := 60.0
var _last_tick := -1
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var whole := ceili(seconds)
	if seconds > 0.0 and whole <= 5 and whole != _last_tick:
		_last_tick = whole
		MissionSounds.play(self, MissionSounds.tick(), -2.0)
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var k := maxf(0.5, vs.y / 1080.0)
	var font := HudStyle.heading_font()
	# Under the notepad (Notepad.W wide, from its left edge).
	var pos := Vector2(vs.x - (Notepad.W + 34.0) * k + (Notepad.W - W) * 0.5 * k, vs.y * 0.17 + (Notepad.H + 34.0) * k)
	draw_set_transform(pos, 0.0, Vector2(k, k))
	# The meter head: a rounded grey box with a dark window.
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.5, 0.52, 0.53)
	body.set_corner_radius_all(18)
	body.corner_radius_bottom_left = 6
	body.corner_radius_bottom_right = 6
	body.border_color = Color(0.25, 0.26, 0.27)
	body.set_border_width_all(3)
	body.shadow_color = Color(0, 0, 0, 0.35)
	body.shadow_size = 6
	body.shadow_offset = Vector2(4, 5)
	draw_style_box(body, Rect2(0, 0, W, H))
	var win := StyleBoxFlat.new()
	win.bg_color = Color(0.06, 0.07, 0.07)
	win.set_corner_radius_all(8)
	draw_style_box(win, Rect2(14, 30, W - 28, H - 44))
	draw_string(font, Vector2(0, 24), "METER", HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(0.1, 0.1, 0.1))
	var colour := HudStyle.ACCENT
	if seconds < 20.0:
		colour = Color(1.0, 0.6, 0.2)
	if seconds < 10.0:
		colour = Color(1.0, 0.25, 0.2).lerp(Color(1, 0.75, 0.7), 0.5 + 0.5 * sin(_t * 12.0))
	var s := maxi(0, ceili(seconds))
	var text := "%d:%02d" % [s / 60, s % 60]
	draw_string(font, Vector2(0, H - 24), text, HORIZONTAL_ALIGNMENT_CENTER, W, 70, colour)
	if seconds <= 0.0:
		# The red flag.
		var flag := Rect2(24, 40, W - 48, 44)
		draw_rect(flag, Color(0.85, 0.1, 0.08))
		draw_string(font, Vector2(flag.position.x, flag.position.y + 36), "EXPIRED", HORIZONTAL_ALIGNMENT_CENTER, flag.size.x, 40, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

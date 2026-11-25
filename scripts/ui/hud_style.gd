class_name HudStyle
extends RefCounted
## The HUD's look in one place, so every panel matches: dark translucent
## panels with a faint light edge, white text with a dark outline (it shows
## on sky and snow), the gold accent for keys and numbers that matter, and
## Bebas Neue for headings and big numbers.
##
## Used by Hud, Minimap, WantedHud and WorldMap.

const TEXT := Color(1, 1, 1)
const DIM := Color(0.78, 0.8, 0.82)
const ACCENT := Color(1.0, 0.86, 0.45) ## gold: keys, the gear, your arrow
const WARN := Color(1.0, 0.55, 0.4) ## low ammo
const GOOD := Color(0.55, 0.92, 0.55) ## money in
const PANEL := Color(0.08, 0.09, 0.1, 0.72)
const EDGE := Color(1, 1, 1, 0.09)
const OUTLINE := Color(0, 0, 0, 0.85)
## The waypoint and the route to it (on the minimap, the map and the screen).
const WAYPOINT := Color(0.78, 0.49, 1.0)
const HEADING_FONT := "res://branding/fonts/BebasNeue-Regular.ttf"

static var _bebas: Font


## Bebas Neue with a little letter spacing (shared, made once).
static func heading_font() -> Font:
	if _bebas == null:
		var f := FontVariation.new()
		f.base_font = load(HEADING_FONT) as Font
		f.spacing_glyph = 1
		_bebas = f
	return _bebas


## A panel: rounded, translucent, a hairline edge. `accent` adds a coloured
## bar down the left side.
static func panel(accent := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(8)
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	if accent.a > 0.0:
		sb.border_color = accent
		sb.border_width_left = 4
		sb.border_width_top = 0
		sb.border_width_right = 0
		sb.border_width_bottom = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.anti_aliasing = true
	return sb


## A key cap: light, dark letters ("E", "RB").
static func keycap() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.94, 0.9)
	sb.set_corner_radius_all(5)
	sb.border_color = Color(0.62, 0.6, 0.56)
	sb.border_width_bottom = 2
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	return sb


## A label in the HUD's style: `heading` uses Bebas Neue.
static func label(size: int, heading := false, colour := TEXT, outline := true) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if heading:
		l.add_theme_font_override("font", heading_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if outline:
		l.add_theme_color_override("font_outline_color", OUTLINE)
		l.add_theme_constant_override("outline_size", 5)
	return l


## A key cap label ("E").
static func key_label(text: String, size := 17) -> Label:
	var k := Label.new()
	k.text = text
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_theme_stylebox_override("normal", keycap())
	k.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	k.add_theme_font_size_override("font_size", size)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return k


## "450 m", "1.2 km".
static func distance_text(m: float) -> String:
	if m < 950.0:
		return "%d m" % (roundi(m / 10.0) * 10)
	return "%.1f km" % (m / 1000.0)


## The compass point for a heading in the world's x,z plane (-z north).
static func compass(dir: Vector2) -> String:
	if dir.length_squared() < 1e-6:
		return ""
	# Bearing: 0 north, 90 east.
	var bearing := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
	const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return POINTS[int(round(bearing / 45.0)) % 8]

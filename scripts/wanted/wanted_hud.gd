class_name WantedHud
extends Control
## The wanted level on the HUD (design.md section 7), top centre: four
## police shields, the earned ones filled yellow, the level's name under
## them in Bebas Neue, and under that a red pill: "IN SIGHT" while police
## can see you, or how long you still have to lie low once they've lost you.
## While they've lost you the search circle round where they last saw you
## is on the minimap (Hud.minimap: set_search_circle), with how far outside
## it you are over the map. Under the pill, whether a car wash would clear
## it yet (Wanted.wash_wait: at level 3 and 4 they've to have been without
## you a while first). Also the suds bar while you're in a car wash.
## While wanted, the HUD's titles move down out of its way.
##
## Only listens to the Wanted autoload; Hud makes one of these.

const YELLOW := Color("#FFD23F")
const PILL := Color("#c8102e")
const GOLD := Color(1.0, 0.86, 0.45) # the HUD's accent (key names, the gear)
const RED := Color(0.95, 0.2, 0.18)
## The shields at 1600 x 900, and the gap between them (px).
const SHIELD := Vector2(34, 38)
const SHIELD_GAP := 6.0
const NAME_FONT := "res://branding/fonts/BebasNeue-Regular.ttf"
## Where the HUD's titles go while the wanted level is up (under it).
const TITLE_TOP_WANTED := 150.0
## What comes at each level, under its name when it goes up (design.md's
## "What comes" column, in the HUD's voice).
const RISING := [
	"",
	"One cruiser's on its way. Lose it, or stop.",
	"Three or four cruisers, two officers each. They cut you off at junctions.",
	"The city's called in the FIP. \"Do you even know who we are?\"",
	"The tactical unit's rolling. Funded through the Island Safety Initiative.",
]

var _wanted: Node
var _badge: VBoxContainer
var _pips: Control
var _name: Label
var _pill: PanelContainer
var _status: Label
var _wash_note: Label

var _wash: PanelContainer
var _wash_bar: Control
var _wash_amount := -1.0
var _t := 0.0
var _seen := false
var _on_map := false ## the search circle is on the minimap (ours to clear)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wanted = get_tree().root.get_node_or_null("Wanted")
	_build_badge()
	_build_wash()
	if _wanted != null:
		_wanted.connect("level_changed", _on_level)
		_wanted.connect("seen_changed", func(on: bool) -> void: _seen = on)
		_wanted.connect("announced", _announce)
	_on_level(int(_wanted.get("level")) if _wanted != null else 0, false)


## The suds bar: 0 to 1 through the wash, negative to hide it.
func set_wash(amount: float) -> void:
	_wash_amount = amount
	_wash.visible = amount >= 0.0
	_wash_bar.queue_redraw()


func _on_level(level: int, say := true) -> void:
	var was := int(_badge.get_meta("level", 0))
	_badge.set_meta("level", level)
	_badge.visible = level > 0
	_name.text = str(_wanted.call("level_name", level)) if _wanted != null and level > 0 else ""
	_pips.queue_redraw()
	var hud := get_parent()
	if hud != null and hud.has_method("set_title_top"):
		hud.call("set_title_top", TITLE_TOP_WANTED if level > 0 else -1.0)
	if say and level > was:
		_announce(_name.text, RISING[level])


func _announce(title: String, sub: String) -> void:
	var hud := get_parent()
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", title, sub)


func _process(delta: float) -> void:
	_t += delta
	var level := int(_wanted.get("level")) if _wanted != null else 0
	var map: Variant = get_parent().get("minimap") if get_parent() != null else null
	if level == 0:
		_search_off(map)
		return
	_pips.queue_redraw()
	var seen := bool(_wanted.call("seen_recently"))
	if seen:
		_status.text = "IN SIGHT"
	else:
		var inside := bool(_wanted.call("inside_search_circle"))
		var left := float(_wanted.call("escape_left"))
		_status.text = "%s  ·  %d:%02d" % ["IN THE SEARCH AREA" if inside else "LOST SIGHT", int(left) / 60, int(left) % 60]
	# The car wash: works once they've lost you (and, at 3 and up, after a
	# while). Not while they can see you: going in under their noses is the
	# one sure way it doesn't.
	var wait := float(_wanted.call("wash_wait"))
	if seen:
		_wash_note.text = "Car wash: lose them first"
	elif wait == 0.0:
		_wash_note.text = "Car wash: works now, if nobody sees you go in"
	elif wait < 0.0:
		_wash_note.text = "Car wash: not this time. Lose them the long way"
	else:
		_wash_note.text = "Car wash: works in %d:%02d" % [ceili(wait) / 60, ceili(wait) % 60]
	if bool(_wanted.get("debug_watching")):
		_status.text += "  ·  DEBUG WATCH"
	if seen:
		_search_off(map)
	elif map is Minimap:
		var mm := map as Minimap
		_on_map = true
		var p: Vector3 = _wanted.call("player_position")
		var c: Vector3 = _wanted.get("last_known_position")
		var r := float(_wanted.get("search_radius"))
		var d := Vector2(p.x - c.x, p.z - c.z).length() - r
		mm.set_search_circle(c, r)
		mm.set_caption("Search area  ·  %s" % ("you're inside it" if d <= 0.0 else "%d m outside it" % roundi(d)))


## Take the search circle and its line off the minimap (once).
func _search_off(map: Variant) -> void:
	if not _on_map or not (map is Minimap):
		return
	_on_map = false
	(map as Minimap).clear_search_circle()
	(map as Minimap).set_caption("")


## Top centre: the shields, the name, the pill, one under the other.
func _build_badge() -> void:
	_badge = VBoxContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_constant_override("separation", 2)
	_badge.alignment = BoxContainer.ALIGNMENT_BEGIN
	_pips = Control.new()
	_pips.custom_minimum_size = Vector2(SHIELD.x * 4 + SHIELD_GAP * 3 + 4, SHIELD.y + 4)
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pips.draw.connect(_draw_pips)
	_badge.add_child(_pips)
	_name = Label.new()
	var bebas := FontVariation.new()
	bebas.base_font = load(NAME_FONT) as Font
	bebas.spacing_glyph = 2
	_name.add_theme_font_override("font", bebas)
	_name.add_theme_font_size_override("font_size", 46)
	_name.add_theme_color_override("font_color", Color.WHITE)
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_name.add_theme_constant_override("shadow_offset_x", 2)
	_name.add_theme_constant_override("shadow_offset_y", 3)
	_name.add_theme_constant_override("shadow_outline_size", 4)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_badge.add_child(_name)
	_pill = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PILL
	sb.set_corner_radius_all(11)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status = Label.new()
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.8
	bold.spacing_glyph = 1
	_status.add_theme_font_override("font", bold)
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color.WHITE)
	_pill.add_child(_status)
	_badge.add_child(_pill)
	_wash_note = Label.new()
	_wash_note.add_theme_font_size_override("font_size", 13)
	_wash_note.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_wash_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_wash_note.add_theme_constant_override("outline_size", 4)
	_wash_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wash_note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_badge.add_child(_wash_note)
	add_child(_badge)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_badge.position.y += 14
	_badge.visible = false


## Four police shields: the earned ones yellow with a white edge, the rest
## a faint white outline.
func _draw_pips() -> void:
	var level := int(_wanted.get("level")) if _wanted != null else 0
	var w := SHIELD.x
	var h := SHIELD.y
	for i in 4:
		var o := Vector2(2 + i * (w + SHIELD_GAP), 2)
		var shield := PackedVector2Array([
			o + Vector2(w * 0.5, 0), o + Vector2(w * 0.78, h * 0.08), o + Vector2(w, h * 0.06),
			o + Vector2(w, h * 0.45), o + Vector2(w * 0.86, h * 0.72), o + Vector2(w * 0.5, h),
			o + Vector2(w * 0.14, h * 0.72), o + Vector2(0, h * 0.45), o + Vector2(0, h * 0.06),
			o + Vector2(w * 0.22, h * 0.08)])
		var outline := shield.duplicate()
		outline.append(shield[0])
		if i < level:
			_pips.draw_colored_polygon(shield, YELLOW)
			_pips.draw_polyline(outline, Color.WHITE, 1.5, true)
		else:
			_pips.draw_polyline(outline, Color(1, 1, 1, 0.55), 1.5, true)

func _build_wash() -> void:
	_wash = PanelContainer.new()
	_wash.add_theme_stylebox_override("panel", Hud._panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_wash.add_child(row)
	var l := Label.new()
	l.text = "Suds"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", GOLD)
	row.add_child(l)
	_wash_bar = Control.new()
	_wash_bar.custom_minimum_size = Vector2(220, 24)
	_wash_bar.draw.connect(func() -> void:
		var s := _wash_bar.size
		_wash_bar.draw_rect(Rect2(Vector2(0, 6), Vector2(s.x, s.y - 12)), Color(1, 1, 1, 0.15))
		_wash_bar.draw_rect(Rect2(Vector2(0, 6), Vector2(s.x * clampf(_wash_amount, 0.0, 1.0), s.y - 12)), Color(0.55, 0.8, 1.0)))
	row.add_child(_wash_bar)
	add_child(_wash)
	_wash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_wash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wash.position.y += 240
	_wash.visible = false

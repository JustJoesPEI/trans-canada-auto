class_name Hud
extends CanvasLayer
## Minimal on-screen information:
##   * the street you are on (top left),
##   * a short controls reminder that fades after a while,
##   * a prompt when there's something to use, like "E  Get in" (bottom centre),
##   * your speed in km/h while driving (bottom right),
##   * the OpenStreetMap credit the map data requires (bottom right).
## Money, minimap and mission text join this in a later milestone.

const HELP_TEXT := "WASD / left stick: walk    Shift / A: run    Mouse / right stick: look    E / Y: get in or out of the car\nDriving: W / RT go, S / LT brake and reverse, Space / B handbrake    Wheel / D-pad: zoom    C: reset camera    N: leave a note    Esc: free the mouse"

var _world: WorldBuilder
var _player: Node3D
var _street: Label
var _help: Label
var _timer := 0.0
var _help_time := 14.0
var _prompt_panel: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _speed_panel: PanelContainer
var _speed: Label
var _title: Label
var _subtitle: Label
var _title_time := 0.0


func _ready() -> void:
	_street = _label(22, Control.PRESET_TOP_LEFT, Vector2(24, 18))
	_help = _label(15, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24))
	_help.text = HELP_TEXT
	var credit := _label(12, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -28))
	credit.text = "Map data © OpenStreetMap contributors. Elevation: NRCan HRDEM, Open Government Licence – Canada"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.modulate.a = 0.8
	_build_prompt()
	_build_speed()
	_title = _label(34, Control.PRESET_CENTER_TOP, Vector2(0, 70))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle = _label(17, Control.PRESET_CENTER_TOP, Vector2(0, 116))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH


## A title across the top of the screen for a few seconds, e.g. the car's
## name when you get in.
func show_title(title: String, subtitle := "") -> void:
	_title.text = title
	_subtitle.text = subtitle
	_title_time = 3.5


## Show a prompt like "E  Get in", or hide it with an empty text.
func set_prompt(key: String, text: String) -> void:
	_prompt_panel.visible = text != ""
	_prompt_key.text = key
	_prompt_text.text = text


## Show the speedometer (km/h), or hide it with a negative value.
func set_speed(kmh: float) -> void:
	_speed_panel.visible = kmh >= 0.0
	if kmh >= 0.0:
		_speed.text = "%d  km/h" % roundi(kmh)


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.68)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override("panel", _panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_prompt_panel.add_child(row)
	_prompt_key = Label.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(0.95, 0.94, 0.9)
	key_style.set_corner_radius_all(5)
	key_style.content_margin_left = 9
	key_style.content_margin_right = 9
	_prompt_key.add_theme_stylebox_override("normal", key_style)
	_prompt_key.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_prompt_key.add_theme_font_size_override("font_size", 20)
	row.add_child(_prompt_key)
	_prompt_text = Label.new()
	_prompt_text.add_theme_font_size_override("font_size", 20)
	row.add_child(_prompt_text)
	add_child(_prompt_panel)
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.position.y -= 90
	_prompt_panel.visible = false


func _build_speed() -> void:
	_speed_panel = PanelContainer.new()
	_speed_panel.add_theme_stylebox_override("panel", _panel_style())
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 30)
	_speed_panel.add_child(_speed)
	add_child(_speed_panel)
	_speed_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_speed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed_panel.position += Vector2(-24, -56)
	_speed_panel.visible = false


func setup(world: WorldBuilder, player: Node3D) -> void:
	_world = world
	_player = player


func _process(delta: float) -> void:
	_title_time -= delta
	var ta := clampf(_title_time / 0.6, 0.0, 1.0)
	_title.modulate.a = ta
	_subtitle.modulate.a = ta * 0.85
	_help_time -= delta
	if _help_time < 2.0:
		_help.modulate.a = clampf(_help_time / 2.0, 0.0, 1.0)
	_timer -= delta
	if _timer > 0.0 or _world == null or _player == null or not _world.is_built:
		return
	_timer = 0.25
	var p := _player.global_position
	_street.text = _world.street_name_at(Vector2(p.x, p.z))


func _label(size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	# Grow away from the screen edge the label is pinned to.
	if preset == Control.PRESET_BOTTOM_RIGHT:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_BOTTOM_RIGHT or preset == Control.PRESET_BOTTOM_LEFT:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	l.position += offset
	return l

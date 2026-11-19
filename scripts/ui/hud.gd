class_name Hud
extends CanvasLayer
## Minimal on-screen information for Milestone 1:
##   * the street you are on (top left),
##   * a short controls reminder that fades after a while,
##   * the OpenStreetMap credit the map data requires (bottom right).
## Money, speed, minimap and mission text join this in later milestones.

const HELP_TEXT := "WASD / left stick: walk    Shift / A: run    Mouse / right stick: look\nWheel / D-pad: zoom    C: reset camera    Esc: free the mouse"

var _world: WorldBuilder
var _player: Node3D
var _street: Label
var _help: Label
var _timer := 0.0
var _help_time := 12.0


func _ready() -> void:
	_street = _label(22, Control.PRESET_TOP_LEFT, Vector2(24, 18))
	_help = _label(15, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24))
	_help.text = HELP_TEXT
	var credit := _label(12, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -28))
	credit.text = "Map data © OpenStreetMap contributors"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.modulate.a = 0.8


func setup(world: WorldBuilder, player: Node3D) -> void:
	_world = world
	_player = player


func _process(delta: float) -> void:
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

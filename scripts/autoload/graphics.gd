extends Node
## The graphics setting: High (the default) or Low, for older or basic
## graphics chips. F10 switches between them in the game; the choice is saved
## in user://graphics.cfg. Starting the game with `-- --graphics=low` forces Low.
##
## Low turns off the screen-space effects (ambient occlusion, bounced light,
## glow), uses sharper cheaper shadows over a shorter distance, and tells the
## shaders (through the `gfx_detail` global) to skip the fine detail: brick
## and slab relief, the depth in window openings and the reflections in glass.
## The town looks the same at a glance either way.
##
## Nothing here touches gameplay; it only finds the scene's WorldEnvironment
## and sun and adjusts how they draw.

enum Level { LOW, HIGH }

const SAVE_PATH := "user://graphics.cfg"

var level := Level.HIGH

var _label: Label
var _label_time := 0.0


func _ready() -> void:
	level = _load_level()
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--graphics=low":
			level = Level.LOW
		elif a == "--graphics=high":
			level = Level.HIGH
	# The Compatibility (OpenGL) renderer has no SSAO or SSIL anyway; give it
	# the Low shader detail too, since it is the fallback for weaker chips.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" and not _has_saved_level():
		level = Level.LOW
	get_tree().node_added.connect(_on_node_added)
	_apply_shader_detail()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	_label.visible = false
	layer.add_child(_label)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node is DirectionalLight3D:
		# Wait until it is fully set up in the tree.
		_apply_to.call_deferred(node)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F10:
		set_level(Level.LOW if level == Level.HIGH else Level.HIGH)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _label.visible:
		_label_time -= delta
		if _label_time <= 0.0:
			_label.visible = false


func set_level(new_level: Level) -> void:
	level = new_level
	_apply_shader_detail()
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_to(node)
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_apply_to(node)
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "level", "high" if level == Level.HIGH else "low")
	cfg.save(SAVE_PATH)
	_label.text = "Graphics: %s  (F10 to switch)" % ("High" if level == Level.HIGH else "Low")
	_label.visible = true
	_label_time = 2.5


func _apply_shader_detail() -> void:
	RenderingServer.global_shader_parameter_set("gfx_detail", 1.0 if level == Level.HIGH else 0.0)


func _apply_to(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var high := level == Level.HIGH
	if node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		if env == null:
			return
		env.ssao_enabled = high
		# SSIL is Forward+ only; leaving it off in the scene file keeps the
		# Compatibility renderer from warning about it.
		env.ssil_enabled = high and RenderingServer.get_current_rendering_method() == "forward_plus"
		env.glow_enabled = high
	elif node is DirectionalLight3D:
		var sun := node as DirectionalLight3D
		# Soft contact-hardening shadows are the costly part on High.
		sun.light_angular_distance = 0.5 if high else 0.0
		sun.directional_shadow_max_distance = 160.0 if high else 90.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)


func _has_saved_level() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and cfg.has_section_key("graphics", "level")


func _load_level() -> Level:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return Level.LOW if str(cfg.get_value("graphics", "level", "high")) == "low" else Level.HIGH
	return Level.HIGH

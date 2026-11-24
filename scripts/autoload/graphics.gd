extends Node
## The graphics setting: High (the default) or Low, for older or basic
## graphics chips. F10 switches between them in the game; the choice is saved
## in user://graphics.cfg. Starting the game with `-- --graphics=low` forces Low.
##
## Low turns off the screen-space effects (ambient occlusion, bounced light,
## glow), uses sharper cheaper shadows over a shorter distance, and tells the
## shaders (through the `gfx_detail` global) to skip the fine detail: brick
## and slab relief, the depth in window openings and the reflections in glass.
## The town looks the same at a glance either way. Low also keeps the fully
## detailed part of town (the chunks with curbs, lamps, signs and collision)
## to a smaller circle round the player, and the simpler distant town to a
## shorter range.
##
## Automatic resolution (both levels): the graphics card's own time for
## each frame is measured, and while it takes longer than the screen allows
## (or 60 fps, on a faster screen) the town is drawn at a lower resolution,
## down to 60%, and scaled up with AMD FSR, which sharpens as it goes; the
## menus and text stay sharp. When there's room again it steps back up. So a
## modest graphics card keeps the High look without the stutter, and a fast
## one never notices. Start with `-- --no-auto-res` to keep full resolution.
##
## Nothing here touches gameplay; it only finds the scene's WorldEnvironment
## and sun and adjusts how they draw.

enum Level { LOW, HIGH }

const SAVE_PATH := "user://graphics.cfg"

var level := Level.HIGH

var _label: Label
var _label_time := 0.0
## F3: frame rate and frame times in the corner, to tell whether stutter is
## the graphics card falling behind (frames slower than the screen's refresh)
## or something else (a smooth frame rate, but jerky motion).
var _stats: Label
var _stats_frames := 0
var _stats_time := 0.0
var _stats_worst := 0.0
var _stats_slow := 0
var _stats_last_us := 0

const SCALE_MIN := 0.6
const SCALE_MAX := 1.0
var auto_res := not OS.get_cmdline_user_args().has("--no-auto-res")
## Current 3D render scale (1 = full resolution).
var render_scale := 1.0
## The graphics card's time per frame (ms), smoothed; 0 where it can't be measured.
var gpu_ms := 0.0
var _over := 0.0 ## seconds the card has been over budget
var _under := 0.0 ## seconds it has had plenty of room
var _settle := 0.0 ## seconds to wait after a change before judging again


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
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_stats.add_theme_constant_override("outline_size", 5)
	_stats.anchor_left = 1.0
	_stats.anchor_right = 1.0
	_stats.offset_left = -420.0
	_stats.offset_right = -16.0
	_stats.offset_top = 16.0
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.visible = false
	layer.add_child(_stats)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var vp := get_viewport()
	# FSR 1 needs Forward+ or Mobile; the Compatibility renderer scales plainly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Viewport.SCALING_3D_MODE_FSR
	vp.fsr_sharpness = 0.3
	vp.scaling_3d_scale = render_scale


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node is DirectionalLight3D:
		# Wait until it is fully set up in the tree.
		_apply_to.call_deferred(node)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F10:
		set_level(Level.LOW if level == Level.HIGH else Level.HIGH)
		get_viewport().set_input_as_handled()
	elif k != null and k.pressed and not k.echo and k.keycode == KEY_F3:
		_stats.visible = not _stats.visible
		_stats.text = "measuring\u2026"
		_stats_frames = 0
		_stats_time = 0.0
		_stats_worst = 0.0
		_stats_slow = 0
		_stats_last_us = 0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _label.visible:
		_label_time -= delta
		if _label_time <= 0.0:
			_label.visible = false
	_auto_resolution(delta)
	if _stats.visible:
		_update_stats()


## See the note at the top. The card's time follows the number of pixels,
## so a step down by 0.1 saves roughly a fifth of it.
func _auto_resolution(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if ms <= 0.0 or delta > 0.5:
		return # not measurable here (or a load hitch, which says nothing about drawing)
	gpu_ms = ms if gpu_ms <= 0.0 else lerpf(gpu_ms, ms, 1.0 - exp(-delta / 0.4))
	if not auto_res:
		return
	if _settle > 0.0:
		_settle -= delta
		return
	var hz := DisplayServer.screen_get_refresh_rate()
	var budget := 1000.0 / clampf(hz if hz > 0.0 else 60.0, 30.0, 60.0)
	if gpu_ms > budget * 0.9 and render_scale > SCALE_MIN:
		_over += delta
		_under = 0.0
		if _over > 0.6:
			_set_scale(render_scale - 0.1)
	else:
		_over = 0.0
		# Room to go up a step: what the next step up would cost still fits.
		var up := minf(SCALE_MAX, render_scale + 0.05)
		if up > render_scale and gpu_ms * pow(up / render_scale, 2.0) < budget * 0.75:
			_under += delta
			if _under > 3.0:
				_set_scale(up)
		else:
			_under = 0.0


func _set_scale(s: float) -> void:
	var old := render_scale
	render_scale = clampf(snappedf(s, 0.05), SCALE_MIN, SCALE_MAX)
	get_viewport().scaling_3d_scale = render_scale
	gpu_ms *= pow(render_scale / old, 2.0) # a guess until it's measured at the new size
	_over = 0.0
	_under = 0.0
	_settle = 1.0


## Real time between frames (not the smoothed delta), summed over a second.
## "Late" counts frames that took over 1.5 times the screen's refresh: each
## one is a frame the screen showed twice, which is what reads as a judder.
func _update_stats() -> void:
	var now := Time.get_ticks_usec()
	if _stats_last_us == 0:
		_stats_last_us = now
		return
	var ms := (now - _stats_last_us) / 1000.0
	_stats_last_us = now
	_stats_frames += 1
	_stats_time += ms
	_stats_worst = maxf(_stats_worst, ms)
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		hz = 60.0
	if ms > 1500.0 / hz:
		_stats_slow += 1
	if _stats_time < 1000.0:
		return
	_stats.text = "%d fps  ·  avg %.1f ms  ·  worst %.0f ms\nlate frames %d  ·  screen %d Hz  ·  %s\n%s\n%d draw calls  ·  %.1fM triangles" % [
		roundi(_stats_frames * 1000.0 / _stats_time), _stats_time / _stats_frames, _stats_worst,
		_stats_slow, roundi(hz), "High" if level == Level.HIGH else "Low",
		("GPU %.1f ms  ·  drawn at %d%%%s" % [gpu_ms, roundi(render_scale * 100.0), "" if auto_res else " (auto off)"]) if gpu_ms > 0.0 else "GPU time not measurable here",
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6]
	_stats_frames = 0
	_stats_time = 0.0
	_stats_worst = 0.0
	_stats_slow = 0


## How far round the player the town is built in full detail (metres).
func detail_radius() -> float:
	return 330.0 if level == Level.HIGH else 230.0


## How far round the player buildings get their close-up facades: real
## window openings, trim, porches and chimneys (metres).
func facade_radius() -> float:
	return 150.0 if level == Level.HIGH else 90.0


## How far the simpler distant town reaches (metres).
func distant_radius() -> float:
	return 1000.0 if level == Level.HIGH else 750.0


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

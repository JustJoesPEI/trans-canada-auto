extends Node
## The graphics setting: High (the default), Medium or Low, for older or
## basic graphics chips. F10 steps through them in the game (High, Medium,
## Low, High...); the choice is saved in user://graphics.cfg. Starting the
## game with `-- --graphics=low` (or medium, high) forces one.
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
## Low is also sized for laptop graphics that share the computer's memory
## (integrated AMD and Intel chips, which often get a fixed 512 MB of it).
## Going over that slice doesn't just slow the game down: the driver runs
## out of memory blocks and the game freezes and crashes (VkResult -10,
## "Can't create buffer"). So on Low there's no MSAA (at 1080p its buffers
## alone are about 125 MB), and the buildings have flat facades: no
## modelled window openings, trim or porches, the photo walls or the
## branchy trees (BuildingGenerator.facade_relief, as with --flat-facades).
## The close-up facades are most of the town's geometry, so this cuts its
## mesh data by about 60%. The facade part is chosen at start-up (it's
## built into shared materials and props), so switching to or from Low
## with F10 changes it at the next start. The simpler distant town reaches
## 450 m on Low (the haze hides most of it beyond that anyway).
##
## The -10 is VK_ERROR_TOO_MANY_OBJECTS: once the slice is full the
## allocator falls back to one small block per mesh until it hits the
## driver's limit of 4096 blocks. Measured on Low at 1080p (software
## renderer): about 290 MB at the spawn, of which ~60 MB are screen-sized
## buffers, ~80 MB town meshes and ~70 MB allocator slack. Windows' own
## desktop takes from the same slice, so a 512 MB chip can still run out.
## The Direct3D 12 driver (`--rendering-driver d3d12`) should let Windows spill
## over into ordinary memory instead of failing.
##
## Medium sits between: High's shader detail and glow, but no ambient
## occlusion or bounced light, hard-edged shadows to 120 m, and the detailed
## town, the close-up facades and the distant town each a little closer in
## (280, 120 and 880 m). Other things scale with it too: the paint splats on
## walls and the ground are capped at 4000 on High, 2000 on Medium and 800
## on Low (PaintSplats, design section 3).
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

enum Level { LOW, MEDIUM, HIGH }

## What each level is called on screen.
const NAMES := {Level.LOW: "Low", Level.MEDIUM: "Medium", Level.HIGH: "High"}

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
		elif a == "--graphics=medium":
			level = Level.MEDIUM
		elif a == "--graphics=high":
			level = Level.HIGH
	# The Compatibility (OpenGL) renderer has no SSAO or SSIL anyway; give it
	# the Low shader detail too, since it is the fallback for weaker chips.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" and not _has_saved_level():
		level = Level.LOW
	# Before any chunk, material or prop is built (autoloads are ready before
	# the main scene): flat facades on Low (see the note at the top).
	if level == Level.LOW:
		BuildingGenerator.facade_relief = false
	_msaa_default = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	_apply_msaa()
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
		cycle()
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


## See the note at the top. The card's time follows the number of pixels
## (the square of the scale), so the scale that fits is worked out from the
## time measured and set in one go.
##
## Each change of scale has the renderer make a new set of screen-sized
## buffers before it lets go of the old ones: for a frame the graphics
## memory jumps by 40-50 MB at 1080p (tools/memory_budget.gd). On a chip
## with a small slice of memory that's enough to crash it, so the scale
## changes as seldom as it can: not while the town is loading (the frame
## times then are the building, not the drawing, and the memory is at its
## fullest), straight to the scale that fits rather than a step at a time,
## and on Low only back up after a long spell with room to spare.
func _auto_resolution(delta: float) -> void:
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if ms <= 0.0 or delta > 0.5:
		return # not measurable here (or a load hitch, which says nothing about drawing)
	gpu_ms = ms if gpu_ms <= 0.0 else lerpf(gpu_ms, ms, 1.0 - exp(-delta / 0.4))
	if not auto_res or not _world_ready():
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
			# Straight to the scale that brings it to 80% of the time there is.
			_set_scale(minf(render_scale - 0.05, render_scale * sqrt(budget * 0.8 / gpu_ms)))
	else:
		_over = 0.0
		# Room to go up a step: what the next step up would cost still fits.
		var up := minf(SCALE_MAX, render_scale + (0.1 if level == Level.LOW else 0.05))
		if up > render_scale and gpu_ms * pow(up / render_scale, 2.0) < budget * 0.75:
			_under += delta
			if _under > (10.0 if level == Level.LOW else 3.0):
				_set_scale(up)
		else:
			_under = 0.0


## Whether the town is built (the loading screen is gone).
func _world_ready() -> bool:
	if _ready_seen:
		return true
	var scene := get_tree().current_scene
	var world := scene.get_node_or_null("World") if scene != null else null
	_ready_seen = world != null and bool(world.get("is_built"))
	return _ready_seen


var _ready_seen := false


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
		_stats_slow, roundi(hz), level_name(),
		("GPU %.1f ms  ·  drawn at %d%%%s" % [gpu_ms, roundi(render_scale * 100.0), "" if auto_res else " (auto off)"]) if gpu_ms > 0.0 else "GPU time not measurable here",
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6]
	_stats_frames = 0
	_stats_time = 0.0
	_stats_worst = 0.0
	_stats_slow = 0


## How far round the player the town is built in full detail (metres).
func detail_radius() -> float:
	return [200.0, 280.0, 330.0][level]


## How far round the player buildings get their close-up facades: real
## window openings, trim, porches and chimneys (metres).
func facade_radius() -> float:
	return [90.0, 120.0, 150.0][level]


## How far the simpler distant town reaches (metres).
func distant_radius() -> float:
	return [450.0, 880.0, 1000.0][level]


## The level's name ("High"), or another level's.
func level_name(l := -1) -> String:
	return str(NAMES.get(level if l < 0 else l, "High"))


## The next level down, wrapping from Low back to High (F10, the menu).
func cycle() -> void:
	set_level(Level.HIGH if level == Level.LOW else ((level - 1) as Level))


func set_level(new_level: Level) -> void:
	level = new_level
	_apply_shader_detail()
	_apply_msaa()
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_to(node)
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_apply_to(node)
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "level", level_name().to_lower())
	cfg.save(SAVE_PATH)
	_label.text = "Graphics: %s  (F10 to switch)" % level_name()
	_label.visible = true
	_label_time = 2.5


## The project's MSAA (High and Medium), read at start-up.
var _msaa_default := 0


## No MSAA on Low: its colour and depth buffers are the biggest single use
## of graphics memory after the town's meshes.
func _apply_msaa() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if level == Level.LOW else (_msaa_default as Viewport.MSAA)


func _apply_shader_detail() -> void:
	RenderingServer.global_shader_parameter_set("gfx_detail", 0.0 if level == Level.LOW else 1.0)


func _apply_to(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var high := level == Level.HIGH
	var low := level == Level.LOW
	if node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		if env == null:
			return
		env.ssao_enabled = high
		# SSIL is Forward+ only; leaving it off in the scene file keeps the
		# Compatibility renderer from warning about it.
		env.ssil_enabled = high and RenderingServer.get_current_rendering_method() == "forward_plus"
		env.glow_enabled = not low
	elif node is DirectionalLight3D:
		var sun := node as DirectionalLight3D
		# Soft contact-hardening shadows are the costly part on High.
		sun.light_angular_distance = 0.5 if high else 0.0
		sun.directional_shadow_max_distance = [90.0, 120.0, 160.0][level]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)


func _has_saved_level() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and cfg.has_section_key("graphics", "level")


func _load_level() -> Level:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		match str(cfg.get_value("graphics", "level", "high")):
			"low":
				return Level.LOW
			"medium":
				return Level.MEDIUM
	return Level.HIGH

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
## So on Windows the game draws with Direct3D 12 (project.godot,
## rendering_device/driver.windows; Godot falls back to Vulkan where it
## can't): Windows then spills over into ordinary memory instead of
## failing. On the Ryzen laptop that crashed with Vulkan it ran smoothly,
## without the broken triangles, and even High was playable.
## `--rendering-driver vulkan` still picks Vulkan.
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
## down to 60%, and scaled up with AMD FSR, which sharpens as it goes (on
## Low plainly, which takes less memory); the menus and text stay sharp. When there's room again it steps back up. So a
## modest graphics card keeps the High look without the stutter, and a fast
## one never notices. Start with `-- --no-auto-res` to keep full resolution.
##
## A chip that can't make 60 fps even at 60% (a laptop on Low: GPU 17 ms at
## 60%, so every frame just missed the refresh and it ran at 30 anyway, at
## the blurriest scale) gets a steady 30 fps instead: the frame rate is
## capped at 30 and the resolution goes back up to what fits 33 ms. Same
## frame rate, a much sharper picture, and no see-saw between 60 and 30.
## It goes back to 60 when the drawing fits again with room to spare.
## FXAA (Low) is only on at full resolution: a stretched-up picture is
## already soft at the edges, and FXAA on top of it blurred everything.
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
## The screen's refresh rate, asked every few seconds (on Windows asking is a
## system call, too slow to make every frame).
var _hz := 0.0
var _hz_check := 0.0
## Seconds since the town last streamed a chunk in or a shader was compiled:
## the scale doesn't go up while it's busy (those frames say nothing about
## the drawing, and bigger buffers would land on top of the work). It may
## come down any time: that gives memory back.
var _busy_quiet := 0.0
## How long the drawing must be over (or comfortably under) the budget
## before the scale changes, and how long it holds after a change: a change
## rebuilds every screen-sized buffer (tens of ms, and memory), so going
## back up is seldom, not a see-saw between busy and quiet streets.
const DROP_AFTER := 1.5
const DROP_AFTER_LOW := 0.6
const RAISE_AFTER := 15.0
const RAISE_AFTER_LOW := 25.0
const HOLD_AFTER := 8.0
## Seconds pinned at the lowest scale and still over the 60 fps budget
## before dropping to a steady 30, and the 30 fps state itself.
const HALF_RATE_AFTER := 3.0
var half_rate := false
var _pinned := 0.0
var _fits_60 := 0.0


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
	vp.fsr_sharpness = 0.3
	_apply_scaling_mode()
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
	_watch_hitches()
	if _stats.visible:
		_update_stats()


# --- hitch log -----------------------------------------------------------------------------
# A frame much slower than the ones round it gets a line in the log
# (godot.log, in the game's user folder) saying what happened in it: chunks
# of town added, close-up facades swapped in, shaders compiled for the
# first time (the pipeline counts), the resolution changed, how many physics
# steps it had to catch up. One drive on a slow machine then says what its
# hitches are, instead of guessing.

## A frame this much slower than the usual (and over HITCH_MIN_MS) is a hitch.
const HITCH_FACTOR := 2.5
const HITCH_MIN_MS := 50.0
var _hitch_last_us := 0
var _hitch_avg_ms := 0.0
var _hitch_quiet := 0.0 ## seconds before the next line may be written
var _hitch_skipped := 0
var _hitch_count := 0
var _hitch_prev := {}
var _scale_changes := 0


func _hitch_counts() -> Dictionary:
	return {
		"near": ChunkStreamer.added_near, "far": ChunkStreamer.added_far, "facades": ChunkStreamer.facades_swapped,
		"dropped": ChunkStreamer.dropped,
		"shaders": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
			+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)),
		"physics": Engine.get_physics_frames(), "scale": _scale_changes,
	}


func _watch_hitches() -> void:
	var now := Time.get_ticks_usec()
	var counts := _hitch_counts()
	if _hitch_last_us == 0 or not _world_ready():
		_hitch_last_us = now
		_hitch_prev = counts
		return
	var ms := (now - _hitch_last_us) / 1000.0
	_hitch_last_us = now
	for k: String in ["near", "far", "facades", "shaders"]:
		if int(counts[k]) != int(_hitch_prev.get(k, counts[k])):
			_busy_quiet = 0.0
	_hitch_quiet = maxf(0.0, _hitch_quiet - ms / 1000.0)
	if _hitch_avg_ms <= 0.0:
		_hitch_avg_ms = ms
	if ms > HITCH_MIN_MS and ms > _hitch_avg_ms * HITCH_FACTOR:
		_hitch_count += 1
		if _hitch_quiet > 0.0:
			_hitch_skipped += 1
		else:
			var what: PackedStringArray = []
			for k: String in ["near", "far", "facades", "dropped", "shaders", "scale"]:
				var n := int(counts[k]) - int(_hitch_prev.get(k, counts[k]))
				if n > 0:
					what.append({"near": "%d chunk(s) added", "far": "%d distant chunk(s) added",
						"facades": "%d close-up facade(s) swapped in", "dropped": "%d chunk(s) freed", "shaders": "%d shader(s) compiled",
						"scale": "resolution changed"}[k] % n if k != "scale" else "resolution changed")
			var steps := int(counts["physics"]) - int(_hitch_prev.get("physics", counts["physics"]))
			var secs := Time.get_ticks_msec() / 1000
			print("HITCH %.0f ms (usual %.0f) at %d:%02d, %s: %s; %d physics steps%s" % [
				ms, _hitch_avg_ms, secs / 60, secs % 60, level_name(),
				", ".join(what) if not what.is_empty() else "nothing streamed or compiled", steps,
				"" if _hitch_skipped == 0 else " (%d more since the last line)" % _hitch_skipped])
			_hitch_skipped = 0
			_hitch_quiet = 0.5
	else:
		# The usual frame time, not counting hitches.
		_hitch_avg_ms = lerpf(_hitch_avg_ms, ms, 0.05)
	_hitch_prev = counts


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
	_busy_quiet += delta
	_hz_check -= delta
	if _hz_check <= 0.0:
		_hz_check = 5.0
		_hz = DisplayServer.screen_get_refresh_rate()
	var budget := 1000.0 / clampf(_hz if _hz > 0.0 else 60.0, 30.0, 60.0)
	if _half_rate_check(delta, budget):
		return
	if half_rate:
		budget = 1000.0 / 30.0
	if gpu_ms > budget * 0.9 and render_scale > SCALE_MIN:
		_over += delta
		_under = 0.0
		if _over > (DROP_AFTER_LOW if level == Level.LOW else DROP_AFTER):
			# Straight to the scale that brings it to 80% of the time there is.
			_set_scale(minf(render_scale - 0.05, render_scale * sqrt(budget * 0.8 / gpu_ms)))
	else:
		_over = 0.0
		# Room to go up a step: what the next step up would cost still fits.
		var up := minf(SCALE_MAX, render_scale + (0.1 if level == Level.LOW else 0.05))
		if up > render_scale and gpu_ms * pow(up / render_scale, 2.0) < budget * 0.75 and _busy_quiet > 3.0:
			_under += delta
			if _under > (RAISE_AFTER_LOW if level == Level.LOW else RAISE_AFTER):
				_set_scale(up)
		else:
			_under = 0.0


## Steady 30 fps when the card can't make the screen's rate even at the
## lowest scale (see the note at the top), and back when it can. True if it
## changed something this frame.
func _half_rate_check(delta: float, budget: float) -> bool:
	if budget > 1000.0 / 45.0:
		return false # a 30-50 Hz screen: the budget is already that long
	if not half_rate:
		if render_scale <= SCALE_MIN + 0.001 and gpu_ms > budget * 0.9 and _busy_quiet > 3.0:
			_pinned += delta
		else:
			_pinned = 0.0
		if _pinned > HALF_RATE_AFTER:
			_set_half_rate(true)
			# Straight up to the scale that fits 80% of 33 ms.
			_set_scale(render_scale * sqrt((1000.0 / 30.0) * 0.8 / gpu_ms))
			return true
		return false
	# Back to the full rate once the card would make it at the scale it's
	# drawing now, with room (well clear of where it dropped, so no see-saw).
	if gpu_ms < budget * 0.7 and _busy_quiet > 3.0:
		_fits_60 += delta
	else:
		_fits_60 = 0.0
	if _fits_60 > RAISE_AFTER_LOW:
		_set_half_rate(false)
		_settle = HOLD_AFTER
		return true
	return false


func _set_half_rate(on: bool) -> void:
	half_rate = on
	_pinned = 0.0
	_fits_60 = 0.0
	Engine.max_fps = 30 if on else 0
	print("Graphics: %s" % ("steady 30 fps (the card can't make the screen's rate)" if on else "back to the screen's rate"))


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
	_scale_changes += 1
	get_viewport().scaling_3d_scale = render_scale
	_apply_fxaa()
	gpu_ms *= pow(render_scale / old, 2.0) # a guess until it's measured at the new size
	_over = 0.0
	_under = 0.0
	_settle = HOLD_AFTER


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
	if ms > 1500.0 / (30.0 if half_rate else hz):
		_stats_slow += 1
	if _stats_time < 1000.0:
		return
	_stats.text = "%d fps  ·  avg %.1f ms  ·  worst %.0f ms\nlate frames %d  ·  screen %d Hz  ·  %s\n%s\n%d draw calls  ·  %.1fM triangles" % [
		roundi(_stats_frames * 1000.0 / _stats_time), _stats_time / _stats_frames, _stats_worst,
		_stats_slow, roundi(hz), level_name() + ("  ·  30 fps cap" if half_rate else ""),
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
	_apply_scaling_mode()
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


## How the town is scaled up when it's drawn below full resolution: AMD FSR,
## which sharpens, on High and Medium; plainly on Low, since FSR keeps its
## own full-size buffers (about 20 MB of graphics memory at 1080p), and on
## the Compatibility renderer, which has no FSR.
func _apply_scaling_mode() -> void:
	var plain := level == Level.LOW or RenderingServer.get_current_rendering_method() == "gl_compatibility"
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if plain else Viewport.SCALING_3D_MODE_FSR


## The project's MSAA (High and Medium), read at start-up.
var _msaa_default := 0


## No MSAA on Low: its colour and depth buffers are the biggest single use
## of graphics memory after the town's meshes.
func _apply_msaa() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if level == Level.LOW else (_msaa_default as Viewport.MSAA)
	_apply_fxaa()
	# Soft shadow filtering, per pixel over the whole screen: the least on Low,
	# lighter on Medium (the project's setting, soft medium, on High).
	var q: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][level]
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)


## Low has no MSAA, so brick, window grids and road paint shimmered: FXAA
## instead, one cheap pass and next to no memory. Only at full resolution:
## stretched up, the picture is soft at the edges already, and FXAA on top
## made the whole town look out of focus.
func _apply_fxaa() -> void:
	var on := level == Level.LOW and render_scale >= SCALE_MAX - 0.001
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED


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
		# The first split as a share of the distance: 8% (7 m) suits four
		# splits; with two, the second would stretch one half of the map
		# over the rest, blurry and crawling, so a quarter there.
		if not sun.has_meta("split_1"):
			sun.set_meta("split_1", sun.directional_shadow_split_1)
		sun.directional_shadow_split_1 = 0.25 if low else float(sun.get_meta("split_1"))
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

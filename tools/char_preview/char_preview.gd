extends SceneTree
## Renders the person model to PNGs for checking its look and its walk.
## godot --path . -s tools/char_preview/char_preview.gd -- <out_dir> [speed]
## Writes poses.png (front, 3/4, side, back standing), seated.png and walk.png (8 frames
## of one walk cycle from the side, then 8 from behind, as the game camera sees it).

var out := "user://"
var speed := 1.7

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: speed = float(args[1])
	_run.call_deferred()

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 600)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	vp.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.45, 0.45, 0.43)
	floor.material_override = fm
	vp.add_child(floor)
	var model: HumanoidModel = load("res://scripts/characters/humanoid_model.gd").new()
	vp.add_child(model)
	var cam := Camera3D.new()
	cam.fov = 28.0
	vp.add_child(cam)

	var poses := Image.create(360 * 4, 600, false, Image.FORMAT_RGBA8)
	var views := [0.0, -0.7, -PI * 0.5, PI]
	for i in views.size():
		model.set_motion(0.0)
		_aim(cam, views[i])
		for f in 30: await process_frame
		var pi := vp.get_texture().get_image()
		pi.convert(Image.FORMAT_RGBA8)
		poses.blit_rect(pi, Rect2i(0, 0, 360, 600), Vector2i(360 * i, 0))
	poses.save_png(out.path_join("poses.png"))

	# Seated (driving), from the side and from the front-left.
	model.seated = true
	var seat := Image.create(360 * 2, 600, false, Image.FORMAT_RGBA8)
	for i in 2:
		_aim(cam, [-PI * 0.5, -0.7][i])
		for f in 20: await process_frame
		var si := vp.get_texture().get_image()
		si.convert(Image.FORMAT_RGBA8)
		seat.blit_rect(si, Rect2i(0, 0, 360, 600), Vector2i(360 * i, 0))
	seat.save_png(out.path_join("seated.png"))
	model.seated = false
	model.rotation.z = 0.0

	# Walk: settle into the cycle, then sample 8 frames through one cycle.
	var walk := Image.create(180 * 8, 300 * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		_aim(cam, -PI * 0.5 if row == 0 else PI)
		model._phase = 0.0
		Engine.time_scale = 1.0
		for f in 120:
			model.set_motion(speed)
			await process_frame
		var start: float = model._phase
		var cyc := 0.0
		var frame := 0
		var shots := []
		# step the model manually for exact phases
		model.set_process(false)
		for n in 8:
			model._phase = fmod(start + TAU * n / 8.0, TAU)
			model.set_motion(speed)
			model._process(0.0)
			await process_frame
			await process_frame
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(180, 300)
			walk.blit_rect(img, Rect2i(0, 0, 180, 300), Vector2i(180 * n, 300 * row))
		model.set_process(true)
	walk.save_png(out.path_join("walk.png"))
	quit()

func _aim(cam: Camera3D, yaw: float) -> void:
	var target := Vector3(0, 0.9, 0)
	var dir := Vector3(sin(yaw), 0.0, -cos(yaw)) # yaw 0: in front of the model (model faces -Z)
	cam.position = target + dir * 4.6 + Vector3(0, 0.2, 0)
	cam.look_at(target)

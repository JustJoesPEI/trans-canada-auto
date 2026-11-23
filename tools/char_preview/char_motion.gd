extends SceneTree
## Renders the person through starts and stops, for judging how the motion
## feels: stand, walk, stop, run, stop. Speed follows the same springs as
## the player controller. Writes numbered PNG frames (30 fps) to <out_dir>;
## join them with e.g. ffmpeg -i f%04d.png clip.mp4.
## godot --path . -s tools/char_preview/char_motion.gd -- <out_dir> [side|behind]

const FPS := 30.0
# [seconds, target speed m/s]
const TIMELINE := [[0.8, 0.0], [2.4, 1.7], [1.4, 0.0], [2.6, 5.4], [1.6, 0.0], [1.6, 1.7], [1.2, 0.0]]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var view: String = args[1] if args.size() > 1 else "side"
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 400)
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
	# A ground with stripes every metre, so foot slide shows.
	for i in 80:
		var tile := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(6.0, 1.0)
		tile.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.47, 0.47, 0.45) if i % 2 == 0 else Color(0.41, 0.41, 0.4)
		tile.material_override = fm
		tile.position = Vector3(0.0, 0.0, 2.0 - i)
		vp.add_child(tile)
	var model: HumanoidModel = load("res://scripts/characters/humanoid_model.gd").new()
	vp.add_child(model)
	model.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)

	var dt := 1.0 / FPS
	var speed := 0.0
	var speed_vel := 0.0
	var frame := 0
	for seg: Array in TIMELINE:
		var n := int(float(seg[0]) * FPS)
		for i in n:
			var goal: float = seg[1]
			var old := speed
			var sp := Smooth.spring(speed, speed_vel, goal, 0.1 if goal > speed else 0.12, dt)
			speed = maxf(0.0, sp[0])
			speed_vel = sp[1]
			model.position.z -= speed * dt
			model.set_motion(speed, (speed - old) / dt, 0.0)
			model._process(dt)
			var target := model.position + Vector3(0, 0.9, 0)
			cam.position = target + (Vector3(-4.2, 0.4, 0.0) if view == "side" else Vector3(0.6, 0.9, 3.4))
			cam.look_at(target)
			await process_frame
			var img := vp.get_texture().get_image()
			img.save_png(out.path_join("f%04d.png" % frame))
			frame += 1
	quit()

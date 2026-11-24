extends SceneTree
## Renders the person aiming and stepping every way, for judging strafing
## and backing up: aim, walk ahead, strafe left, back up, strafe right, the
## diagonals, then look up and down. They always face -Z; the camera stays
## at a fixed angle to them. Writes numbered PNG frames (30 fps) to <out_dir>.
## godot --path . -s tools/char_preview/char_aim.gd -- <out_dir> [front|side|back]

const FPS := 30.0
# [seconds, step angle (degrees, 0 ahead, + left), speed m/s, aim 0/1, aim pitch degrees]
const TIMELINE := [
	[0.6, 0.0, 0.0, 0.0, 0.0],
	[0.8, 0.0, 0.0, 1.0, 0.0],
	[1.6, 0.0, 2.6, 1.0, 0.0],
	[1.6, 90.0, 2.6, 1.0, 0.0],
	[1.6, 180.0, 2.1, 1.0, 0.0],
	[1.6, -90.0, 2.6, 1.0, 0.0],
	[1.4, 45.0, 2.6, 1.0, 0.0],
	[1.4, 135.0, 2.1, 1.0, 0.0],
	[1.4, -135.0, 2.1, 1.0, 0.0],
	[1.2, 0.0, 0.0, 1.0, 35.0],
	[1.2, 0.0, 0.0, 1.0, -30.0],
	[0.8, 0.0, 0.0, 0.0, 0.0],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var view: String = args[1] if args.size() > 1 else "front"
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
	# A checked ground, a metre a square, so foot slide shows every way.
	for i in 40:
		for j in 40:
			var tile := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(1.0, 1.0)
			tile.mesh = pm
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.47, 0.47, 0.45) if (i + j) % 2 == 0 else Color(0.41, 0.41, 0.4)
			tile.material_override = fm
			tile.position = Vector3(i - 20.0 + 0.5, 0.0, j - 20.0 + 0.5)
			vp.add_child(tile)
	var model: HumanoidModel = load("res://scripts/characters/humanoid_model.gd").new()
	vp.add_child(model)
	model.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	var offsets := {"front": Vector3(-1.6, 0.5, -3.6), "side": Vector3(-4.0, 0.4, 0.0), "back": Vector3(0.9, 0.7, 3.6)}

	var dt := 1.0 / FPS
	var vel := Vector3.ZERO
	var frame := 0
	for seg: Array in TIMELINE:
		var n := int(float(seg[0]) * FPS)
		var a := deg_to_rad(float(seg[1]))
		var goal := Vector3(-sin(a), 0.0, -cos(a)) * float(seg[2])
		for i in n:
			var old := vel
			vel = vel.move_toward(goal, 55.0 * dt)
			model.position += vel * dt
			var accel := (vel - old).dot(Vector3.FORWARD) / dt
			var angle := atan2(-vel.x, -vel.z) if vel.length() > 0.05 else 0.0
			model.aim = float(seg[3])
			model.aim_pitch = deg_to_rad(float(seg[4]))
			model.set_motion(vel.length(), accel, 0.0, angle)
			model._process(dt)
			var target: Vector3 = model.position + Vector3(0, 0.95, 0)
			cam.position = target + offsets.get(view, offsets["front"])
			cam.look_at(target)
			await process_frame
			var img := vp.get_texture().get_image()
			img.save_png(out.path_join("f%04d.png" % frame))
			frame += 1
	quit()

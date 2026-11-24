extends SceneTree
## A photo studio for the paint: a wall, the ground, a car and a person,
## painted by real shots, photographed as the paint ages, for checking how
## it looks without loading the town. Run it with a real renderer:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/paint_studio.gd -- --out=/tmp/paint \
##       [--scene=drips|lean] [--times=0.3,5,25]
##
## drips: the splats as they land, while they run and once they're dry
##   (design section 3, "Drips"): OUT/drips_T.png for each time T (s).
## lean: a person in a car's passenger seat leaning out to aim
##   (PassengerSeat), from the side and from behind: OUT/lean_VIEW.png.
##
## Prints one "STUDIO" line per picture saved.

var _args := {}
var _stage: Node3D
var _cam: Camera3D
var _out := "/tmp/paint"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	_run.call_deferred()


func _run() -> void:
	_out = str(_args.get("out", "/tmp/paint"))
	DirAccess.make_dir_recursive_absolute(_out)
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	_stage = Node3D.new()
	root.add_child(_stage)
	_lighting()
	_ground()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.03
	_stage.add_child(_cam)
	_cam.current = true
	match str(_args.get("scene", "drips")):
		"lean":
			await _lean()
		_:
			await _drips()
	quit()


func _drips() -> void:
	var shots := PaintShots.new()
	_stage.add_child(shots)
	# A wall facing the camera, a car side-on in front of it, a person.
	var wall := _box(Vector3(8, 4, 0.4), Vector3(0, 2, -3), Color(0.72, 0.7, 0.66))
	wall.name = "Wall"
	var car := Car.new()
	car.model_id = "civique"
	car.paint = Color(0.15, 0.2, 0.3)
	_stage.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1.6, 0.0, 0.5))
	car.freeze = true
	var person := PlayerController.new()
	var model := HumanoidModel.new()
	model.name = "Model"
	person.add_child(model)
	person.name = "Target"
	_stage.add_child(person)
	person.global_position = Vector3(-2.2, 0.0, 0.5)
	person.set_physics_process(false)
	var shooter := Node3D.new()
	shooter.name = "Studio"
	shooter.set("paint_colour", PaintWeapons.COLOURS[0])
	_stage.add_child(shooter)
	for i in 4:
		await process_frame
	var w := PaintWeapons.ISLANDER.duplicate()
	var colours := [PaintWeapons.COLOURS[0], PaintWeapons.COLOURS[2], PaintWeapons.COLOURS[3], PaintWeapons.COLOURS[1]]
	for i in 9:
		w["colour"] = colours[i % colours.size()]
		shots.fire(Vector3(-3.5 + i * 0.9, 2.6 + (i % 3) * 0.4, 6.0), Vector3(0, 0, -1), shooter, w, 0.0)
	for i in 5:
		w["colour"] = colours[(i + 1) % colours.size()]
		shots.fire(Vector3(0.6 + i * 0.45, 0.75 + (i % 2) * 0.2, 6.0), Vector3(0, 0, -1), shooter, w, 0.0)
	for i in 3:
		w["colour"] = colours[(i + 2) % colours.size()]
		shots.fire(Vector3(-2.2 + (i - 1) * 0.12, 1.0 + i * 0.25, 6.0), Vector3(0, 0, -1), shooter, w, 0.0)
	for i in 30:
		await physics_frame
	_cam.global_position = Vector3(-0.4, 1.8, 6.2)
	_cam.look_at(Vector3(-0.2, 1.5, -1.0))
	var start := PaintSplats.clock
	for t: float in (str(_args.get("times", "0.3,5,25"))).split_floats(","):
		# Age the paint without waiting: move the clock the shaders read.
		PaintSplats.clock = start + t
		RenderingServer.global_shader_parameter_set("paint_now", PaintSplats.clock)
		await _shoot("drips_%s" % str(t))


func _lean() -> void:
	var car := Car.new()
	car.model_id = str(_args.get("car", "civique"))
	car.paint = Color(0.15, 0.2, 0.3)
	_stage.add_child(car)
	car.freeze = true
	# Someone in the passenger seat, as PlayerController puts them there.
	var person := Node3D.new()
	person.name = "Passenger"
	_stage.add_child(person)
	var model := HumanoidModel.new()
	model.name = "Model"
	person.add_child(model)
	var seat := PassengerSeat.of(car)
	for i in 4:
		await process_frame
	seat.sit(person, model, null)
	# Aiming out of the window at a point ahead and to the side.
	var aim := (str(_args.get("aim", "6,1.2,-4"))).split_floats(",")
	seat.aim_at = car.global_transform * Vector3(aim[0], aim[1], aim[2])
	seat.wants_lean = not _args.has("sitting")
	for i in 40:
		await physics_frame
	for v: Array in [["side", Vector3(5.5, 1.6, 1.5), Vector3(0.6, 1.1, 0.0)], ["behind", Vector3(3.2, 2.2, 6.0), Vector3(0.9, 1.1, -1.0)], ["front", Vector3(4.0, 1.7, -4.5), Vector3(0.7, 1.1, 0.0)]]:
		_cam.global_position = car.global_transform * (v[1] as Vector3)
		_cam.look_at(car.global_transform * (v[2] as Vector3))
		await _shoot("lean_%s" % v[0])


func _shoot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("STUDIO saved %s" % name)


func _box(size: Vector3, at: Vector3, colour: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	mi.material_override = m
	body.add_child(mi)
	_stage.add_child(body)
	body.global_position = at
	return body


func _ground() -> void:
	var body := _box(Vector3(60, 1, 60), Vector3(0, -0.5, 0), Color(0.36, 0.35, 0.33))
	body.collision_layer = Layers.GROUND


func _lighting() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_stage.add_child(sun)

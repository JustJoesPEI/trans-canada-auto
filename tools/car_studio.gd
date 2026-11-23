extends SceneTree
## A photo studio for the cars: each model on a plain pad under a sun and
## sky, with a driver sitting in it, shot from set angles (front and rear
## three-quarters, side, a wheel close up, through the driver's window and
## from the driver's seat). For checking how the cars look without loading
## the town. Run it with a real renderer:
##
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/car_studio.gd -- --out=/tmp/cars [--cars=pony_gt,civique] \
##       [--views=front,rear,side,wheel,window,seat,top] [--steer=0.6] \
##       [--livery=cps] [--lights]  (a fleet's livery; --lights shows the
##       light bar lit, both colours at once)
##
## Saves OUT/CAR_VIEW.png.

const VIEWS := {
	# name: [camera position, look-at point], in the car's own space
	# (front toward -z, driver on the left, -x).
	"front": [Vector3(-3.6, 1.45, -4.6), Vector3(0, 0.6, 0)],
	"rear": [Vector3(3.8, 1.6, 4.4), Vector3(0, 0.6, 0)],
	"side": [Vector3(-6.2, 0.85, 0.0), Vector3(0, 0.65, 0)],
	"wheel": [Vector3(-1.75, 0.45, -2.25), Vector3(-0.8, 0.33, -1.35)],
	"window": [Vector3(-1.75, 1.25, -0.55), Vector3(-0.3, 0.95, -0.2)],
	"seat": [Vector3(-0.38, 1.18, 0.12), Vector3(-0.38, 0.95, -2.0)],
	"top": [Vector3(-1.4, 3.2, 1.1), Vector3(-0.2, 0.7, -0.3)],
	"cabin": [Vector3.ZERO, Vector3.FORWARD],
	"dash": [Vector3.ZERO, Vector3.FORWARD],
	"seats": [Vector3.ZERO, Vector3.FORWARD],
	"nose": [Vector3(-1.3, 0.95, -4.4), Vector3(0, 0.6, -2.2)],
	"tail": [Vector3(1.4, 1.1, 4.6), Vector3(0, 0.75, 2.3)],
}

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	_run.call_deferred()


func _run() -> void:
	var out: String = _args.get("out", "/tmp/cars")
	DirAccess.make_dir_recursive_absolute(out)
	var cars: Array = CarModels.MODELS.keys()
	if _args.has("cars"):
		cars = (_args["cars"] as String).split(",")
	var views: Array = VIEWS.keys()
	if _args.has("views"):
		views = (_args["views"] as String).split(",")
	var steer := float(_args.get("steer", "0.0"))
	# The autoloads draw a loading screen and title menu over everything.
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false

	var stage := Node3D.new()
	root.add_child(stage)
	_lighting(stage)
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.36, 0.35, 0.33)
	pmat.roughness = 0.9
	pad.material_override = pmat
	stage.add_child(pad)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.GROUND
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	fs.shape = box
	fs.position.y = -0.5
	floor_body.add_child(fs)
	stage.add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.03
	stage.add_child(cam)
	cam.current = true

	if _args.has("parked"):
		# The curb-parked versions, through a MultiMesh as the streets use them.
		var x := -3.0
		for id: String in cars:
			var pm2 := CarBuilder.new(CarModels.get_model(id)["shape"], Color.WHITE).make_parked()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = pm2
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.5), Vector3(x, 0, 0)))
			mm.set_instance_custom_data(0, Color.html(CarModels.get_model(id)["colours"][1]))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			stage.add_child(mmi)
			x += 3.0
		cam.global_position = Vector3(-6.5, 3.2, -7.5)
		cam.look_at(Vector3(0, 0.6, 0))
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/parked.png")
		print("STUDIO saved parked")
		quit()
		return
	for id: String in cars:
		var m := CarModels.get_model(id)
		var car := Car.new()
		car.model_id = id
		car.paint = Color.html(m["colours"][0])
		if _args.has("livery"):
			car.livery = str(_args["livery"])
			car.unit = 12
			car.paint = Color.html(str(CarModels.LIVERIES[car.livery]["colour"]))
		stage.add_child(car)
		var gear := car.find_child("PoliceGear", true, false) as PoliceGear
		if gear != null and _args.has("lights"):
			gear.set_process(false)
			gear._apply(1.0, 1.0)
		car.freeze = true
		var driver := HumanoidModel.new()
		car.seat.add_child(driver)
		driver.position = Vector3(0.0, -driver.height / 1.75 * 0.93, 0.0)
		driver.seated = true
		driver.seated_steer = steer
		car.steer_angle = steer * deg_to_rad(car.max_steer_degrees)
		var tris := 0
		for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				tris += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var pk := CarBuilder.new(m["shape"], Color.WHITE).make_parked()
		var ptris := 0
		for si in pk.get_surface_count():
			ptris += (pk.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("STUDIO %s: %d triangles driven, %d parked" % [id, tris, ptris])
		car.set_physics_process(false)
		car._animate(0.0)
		await process_frame
		# Hands on the wheel and feet on the pedals, as PlayerController does.
		var to_model := driver.global_transform.affine_inverse() * car.global_transform
		var grips: Array = []
		for p: Vector3 in car.steering_grips():
			grips.append(to_model * p)
		driver.seated_grips = grips
		var feet: Array = []
		for p: Vector3 in car.pedal_points():
			feet.append(to_model * p)
		driver.seated_feet = feet
		if _args.has("nodriver"):
			driver.visible = false
		for i in 4:
			await process_frame
		for v: String in views:
			if not VIEWS.has(v):
				continue
			var spec: Array = VIEWS[v]
			var shape: Dictionary = car.shape
			var eye: Vector3 = spec[0]
			var at: Vector3 = spec[1]
			if v == "seat":
				var sp: Array = shape["seat"]
				# Where the game's driver's-seat camera puts the eyes.
				eye = Vector3(sp[0], float(sp[1]) + 0.76, float(sp[2]))
				at = Vector3(sp[0], float(sp[1]) + 0.6, float(sp[2]) - 2.0)
				cam.fov = 70.0
				driver.hide_head = true
			elif v == "cabin":
				# From over the passenger's shoulder, looking at the driver's hands.
				var sp3: Array = shape["seat"]
				eye = Vector3(-float(sp3[0]) * 0.6, float(sp3[1]) + 0.55, float(sp3[2]) + 0.05)
				at = Vector3(float(sp3[0]), float(sp3[1]) + 0.3, float(sp3[2]) - 0.42)
				cam.fov = 60.0
				car.get_node("Body").get_child(0).visible = not _args.has("noshell")
			elif v == "dash" or v == "seats":
				# Inside: from the passenger's seat looking at the dash, or
				# from over the dash looking back at the seats.
				var sp4: Array = shape["seat"]
				var hx := -float(sp4[0])
				var hy := float(sp4[1])
				var hz := float(sp4[2])
				if v == "dash":
					eye = Vector3(hx, hy + 0.62, hz + 0.1)
					at = Vector3(float(sp4[0]) * 0.6, hy + 0.3, hz - 0.7)
				else:
					var cab4: Dictionary = shape["cabin"]
					eye = Vector3(0.05, float(cab4["roof"]) - 0.12, float(cab4["za"]) + 0.15)
					at = Vector3(0, hy + 0.1, hz + 0.4)
					driver.visible = false
				cam.fov = 75.0
			elif v == "window":
				var sp2: Array = shape["seat"]
				eye = Vector3(-float(shape["width"]) * 0.5 - 0.9, float(sp2[1]) + 0.75, float(sp2[2]) - 0.25)
				at = Vector3(float(sp2[0]) + 0.1, float(sp2[1]) + 0.42, float(sp2[2]) - 0.5)
				cam.fov = 50.0
			elif v == "wheel":
				var fz := float(shape["front_axle"])
				var th := float(shape["track_half"])
				var r := float(shape["wheel_radius"])
				eye = Vector3(-th - 1.1, r + 0.12, fz - 0.9)
				at = Vector3(-th, r, fz)
				cam.fov = 50.0
			else:
				cam.fov = 50.0
			if v != "seat":
				driver.hide_head = false
			if v != "seats":
				driver.visible = not _args.has("nodriver")
			cam.global_transform = Transform3D(Basis.IDENTITY, car.global_transform * eye)
			cam.look_at(car.global_transform * at)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var path := "%s/%s_%s.png" % [out, id, v]
			img.save_png(path)
			print("STUDIO saved ", path)
		car.queue_free()
		await process_frame
	quit()


func _lighting(stage: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sm.ground_horizon_color = Color(0.5, 0.5, 0.5)
	sm.ground_bottom_color = Color(0.25, 0.24, 0.22)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	stage.add_child(sun)

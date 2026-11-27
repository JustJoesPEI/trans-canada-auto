extends SceneTree
## Films the people's work animations without the town: getting in and out
## of cars, the officers' radio, notebook, phone and curb, the paramedics
## kneeling and rinsing, Kevin walking the hose out and spraying, a crew
## climbing out of the fire engine. Each clip is numbered PNG frames
## (30 fps) in OUT/CLIP/; join them with ffmpeg. Run it with a real
## renderer, with a fixed frame rate so the clips play at speed:
##
##   godot --path . --rendering-driver vulkan --resolution 640x400 --fixed-fps 30 \
##       --script res://tools/action_studio.gd -- --out=/tmp/actions [--clip=car_in_out,hose]
##
## Clips: car_in_out, cruiser, cop_radio, cop_notepad, cop_call,
## cop_arms, cop_curb, medic, hose, crew_out.

const FPS := 30.0

var _args := {}
var _stage: Node3D
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	_run.call_deferred()


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	var out: String = _args.get("out", "/tmp/actions")
	var all := "car_in_out,cruiser,cop_radio,cop_notepad,cop_call,cop_arms,cop_curb,medic,hose,crew_out"
	for clip: String in str(_args.get("clip", all)).split(","):
		_make_stage()
		var dir := "%s/%s" % [out, clip]
		DirAccess.make_dir_recursive_absolute(dir)
		await call("_clip_" + clip, dir)
		_stage.free()
		await process_frame
		print("STUDIO done ", clip)
	quit()


func _make_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
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
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_stage.add_child(sun)
	# The street: asphalt with a curb line, and ground to stand on.
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.GROUND | Layers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	_stage.add_child(ground)
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	pad.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.31)
	pad.material_override = mat
	_stage.add_child(pad)
	for i in 12:
		var line := MeshInstance3D.new()
		var lm := PlaneMesh.new()
		lm.size = Vector2(0.12, 1.6)
		line.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.85, 0.75, 0.2)
		line.material_override = lmat
		line.position = Vector3(-3.2, 0.005, -18.0 + i * 3.2)
		_stage.add_child(line)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.05
	_stage.add_child(_cam)
	_cam.current = true


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at)


## Saves `secs` of frames, calling `each` (if given) with the time first.
func _film(dir: String, secs: float, each := Callable()) -> void:
	var n := int(secs * FPS)
	for i in n:
		if each.is_valid():
			each.call(float(i) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/f%04d.png" % [dir, i])


func _wait(secs: float) -> void:
	for i in int(secs * FPS):
		await process_frame


func _car(model: String, livery := "", pos := Vector3.ZERO, yaw := 0.0) -> Car:
	var c := Car.new()
	c.model_id = model
	if livery != "":
		c.livery = livery
		c.paint = Color.from_string(str(CarModels.LIVERIES[livery]["colour"]), Color.WHITE)
	else:
		c.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	_stage.add_child(c)
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 0.4)
	return c


## Someone in the driver's (or the passenger's) seat of `c`, the way the
## game seats them: a holder at the hips, the model's origin below.
func _seat_holder(c: Car, m: HumanoidModel, passenger := false) -> Node3D:
	var holder := Node3D.new()
	var seat := c.seat
	if passenger:
		var p := Node3D.new()
		p.position = Vector3(-seat.position.x, seat.position.y, seat.position.z)
		seat.get_parent().add_child(p)
		seat = p
	seat.add_child(holder)
	holder.position = Vector3(0.0, -m.height / 1.75 * 0.93, 0.0)
	holder.add_child(m)
	return holder


func _person(look_seed: String) -> HumanoidModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(look_seed)
	var m := HumanoidModel.new()
	m.set_appearance(HumanoidModel.random_appearance(rng))
	return m


## Climbing in and out of a car: walk up to the driver's door, in, a
## moment at the wheel, out again.
func _clip_car_in_out(dir: String) -> void:
	var c := _car("civique")
	await _wait(1.5)
	c.freeze = true
	var m := _person("driver")
	var holder := _seat_holder(c, m)
	var start := c.global_transform * Vector3(-1.9, 0.0, 1.6)
	m.seated = true
	var door := c.door_point()
	var phase := [0]
	_look(c.global_transform * Vector3(-3.6, 1.6, -1.9), c.global_transform * Vector3(-0.7, 0.75, 0.4))
	await process_frame
	m.climb_in(start, door)
	await _film(dir, 7.0, func(t: float) -> void:
		if t > 3.4 and phase[0] == 0:
			phase[0] = 1
			# Out: the holder goes to the spot by the door, the model climbs.
			var sat := m.global_transform
			holder.reparent(_stage, false)
			holder.global_transform = Transform3D(c.global_basis, c.global_transform * Vector3(-(float(c.shape["width"]) * 0.5 + 0.5), 0.0, float(c.shape["seat"][2])))
			m.seated = false
			m.climb_out(sat))


## An officer out of the cruiser's passenger side and back in.
func _clip_cruiser(dir: String) -> void:
	var c := _car("jaunt", "cps")
	await _wait(1.5)
	c.freeze = true
	var rng := RandomNumberGenerator.new()
	var m := Officer.make_model("city", 1)
	var holder := _seat_holder(c, m, true)
	m.seated = true
	_look(c.global_transform * Vector3(3.6, 1.6, -2.4), c.global_transform * Vector3(0.7, 0.8, 0.4))
	var phase := [0]
	var spot := c.global_transform * Vector3(float(c.shape["width"]) * 0.5 + 0.55, 0.0, float(c.shape["seat"][2]))
	await _film(dir, 6.6, func(t: float) -> void:
		if t > 0.4 and phase[0] == 0:
			phase[0] = 1
			var sat := m.global_transform
			holder.reparent(_stage, false)
			holder.global_transform = Transform3D(c.global_basis, spot)
			m.seated = false
			m.climb_out(sat)
		elif t > 2.4 and phase[0] == 1:
			phase[0] = 2
			m.task = "radio"
		elif t > 4.6 and phase[0] == 2:
			phase[0] = 3
			m.task = ""
			var seat := c.seat.get_parent().get_child(c.seat.get_parent().get_child_count() - 1) as Node3D
			holder.reparent(seat, false)
			holder.position = Vector3(0.0, -m.height / 1.75 * 0.93, 0.0)
			holder.rotation = Vector3.ZERO
			m.seated = true
			m.climb_in(spot, spot))


## One officer standing, with `task` coming on after a moment.
func _cop_task(dir: String, task: String, which := "city", secs := 4.0) -> HumanoidModel:
	var m := Officer.make_model(which, 2)
	_stage.add_child(m)
	m.rotation.y = 0.5
	_look(Vector3(-0.75, 1.5, -1.7), Vector3(0.0, 1.2, 0.0))
	await _film(dir, secs, func(t: float) -> void:
		m.task = task if t > 0.5 else "")
	return m


func _clip_cop_radio(dir: String) -> void:
	await _cop_task(dir, "radio")


func _clip_cop_notepad(dir: String) -> void:
	await _cop_task(dir, "notepad")


func _clip_cop_call(dir: String) -> void:
	await _cop_task(dir, "call")


func _clip_cop_arms(dir: String) -> void:
	await _cop_task(dir, "arms_crossed", "fip")


## Overtime on the curb: sat on the curb, phone in both hands.
func _clip_cop_curb(dir: String) -> void:
	var m := Officer.make_model("city", 3)
	_stage.add_child(m)
	m.rotation.y = 0.6
	m.seated = true
	m.position.y = -0.45
	var curb := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(4.0, 0.15, 0.5)
	curb.mesh = cb
	curb.position = Vector3(0.0, 0.075, 0.25)
	curb.rotation.y = 0.6
	_stage.add_child(curb)
	_look(Vector3(-1.0, 1.2, -2.2), Vector3(0.0, 0.7, 0.0))
	await _film(dir, 3.5, func(t: float) -> void:
		m.task = "phone" if t > 0.4 else "")


## The Boo-Boo Bus at work: one paramedic kneels by someone sat on the
## ground, a hand on them; the other kneels and rinses the paint off.
func _clip_medic(dir: String) -> void:
	var patient := _person("patient")
	_stage.add_child(patient)
	patient.seated = true
	patient.ground_sit = true
	await process_frame
	patient.position = Vector3(0.0, patient.ground_sit_drop(), 0.0)
	patient.rotation.y = PI * 0.5
	var lead := Responder.new()
	lead.setup("medic", 0)
	_stage.add_child(lead)
	lead.global_position = Vector3(-0.8, 0.0, 0.0)
	lead.face = Vector3.ZERO
	var kit := Responder.new()
	kit.setup("medic", 1)
	_stage.add_child(kit)
	kit.global_position = Vector3(0.0, 0.0, -0.9)
	kit.face = Vector3.ZERO
	_look(Vector3(1.0, 1.3, 1.9), Vector3(-0.35, 0.5, -0.35))
	await _film(dir, 7.0, func(t: float) -> void:
		if t > 0.3 and lead.tend == Vector3.INF:
			lead.tend = Vector3(0.0, 0.55, 0.0)
		if t > 1.6 and t < 1.7 and not kit.spraying():
			kit.spray_at(Vector3(0.0, 0.6, 0.0), 4.0, false))


## The Wee-Woo Brigade: Kevin walks the hose out from the pump panel, over
## his shoulder, stops, holds it at the ready, then gets his squirt.
func _clip_hose(dir: String) -> void:
	var c := _car("fire_engine", "", Vector3(2.5, 0.0, 4.0))
	await _wait(1.5)
	c.freeze = true
	var kev := Responder.new()
	kev.setup("kevin", 0)
	_stage.add_child(kev)
	var pump := Vector3(float(c.shape.get("width", 2.5)) * 0.5, 1.0, -1.9)
	# He starts by the pump panel (the curb side, behind the cab).
	kev.global_position = c.global_transform * Vector3(-float(c.shape.get("width", 2.5)) * 0.5 - 0.7, 0.0, -1.9)
	pump = Vector3(-pump.x, pump.y, pump.z)
	await _wait(0.3)
	kev.hold_hose(c, pump)
	var spot := Vector3(-6.5, 0.0, -5.0)
	kev.move_to(spot)
	kev.face = Vector3(-10.0, 0.0, -9.0)
	var shot := [false]
	await _film(dir, 10.0, func(t: float) -> void:
		var p := kev.global_position
		_look(p + Vector3(-3.4, 1.7, 2.6), p + Vector3(-0.6, 0.9, -0.9))
		if t > 6.0 and not shot[0]:
			shot[0] = true
			kev.spray_at(Vector3(-11.0, 0.3, -10.0), 3.6, true))


## A crew climbing out of the fire engine by their doors, the crew cab too.
func _clip_crew_out(dir: String) -> void:
	var c := _car("fire_engine")
	await _wait(1.5)
	c.freeze = true
	var crew: Array[Responder] = []
	var roles := ["captain", "kevin", "firefighter"]
	var sp := c.seat.position
	for i in roles.size():
		var r := Responder.new()
		r.setup(roles[i], i)
		_stage.add_child(r)
		var side := -1.0 if i % 2 == 0 else 1.0
		var seat := c.global_transform * Transform3D(Basis.IDENTITY, Vector3(side * absf(sp.x), sp.y - r.model.height / 1.75 * 0.93, sp.z + (i / 2) * 1.6))
		var door := c.global_transform * Vector3(side * (float(c.shape.get("width", 2.5)) * 0.5 + 0.55), 0.0, float(c.shape["seat"][2]) + (i / 2) * 1.6)
		r.climb_out_at(Vector3(door.x, 0.0, door.z), c.global_basis.get_euler().y, seat)
		r.model.process_mode = Node.PROCESS_MODE_DISABLED
		crew.append(r)
	var sz := float(c.shape["seat"][2])
	_look(c.global_transform * Vector3(-6.5, 2.2, sz - 3.5), c.global_transform * Vector3(-1.0, 1.1, sz + 0.9))
	await _film(dir, 3.2, func(t: float) -> void:
		for i in crew.size():
			# One after another.
			if t > 0.3 + i * 0.5:
				crew[i].model.process_mode = Node.PROCESS_MODE_INHERIT
		if t > 2.4:
			for r in crew:
				if not r.model.climbing() and r.goal == Vector3.INF:
					r.move_to(r.global_position + Vector3(-2.5, 0.0, -1.0)))

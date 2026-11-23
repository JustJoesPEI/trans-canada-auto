extends SceneTree
## Loads the game, goes to the truck yard (map_config.json "work_yard"),
## waits for the streets there to build and the yard's vehicles and loads to
## wake and settle, then reports where everything came to rest and saves
## screenshots. Run it with a real renderer:
##
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/yard_check.gd -- --out=/tmp/yard
##
## One "YARD ..." line per vehicle and load: how far it moved settling, and
## whether it's upright and resting on something.

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var world: WorldBuilder = main.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	var yard: Dictionary = world.data.config["work_yard"]
	var base: Transform3D = world.edit_xform(yard, 1.0)
	print("YARD middle at %s, in the play area: %s" % [base.origin, world.is_in_play_area(Vector2(base.origin.x, base.origin.z))])
	var player: Node3D = main.get_node("Player")
	player.global_position = base.origin + Vector3.UP
	var rig: Node3D = main.get_node("CameraRig")
	rig.call("snap_to_target")
	await world.wait_until_settled()
	var start := {}
	for n in main.get_children():
		if n is Car or n is Cargo:
			start[n] = (n as Node3D).global_position
	# Let them wake and settle.
	for i in 300:
		await physics_frame
	for n in start:
		var b := n as RigidBody3D
		var moved := b.global_position.distance_to(start[n])
		if moved < 0.0001 and b.global_position.distance_to(base.origin) > 200.0:
			continue
		var what := (b as Car).model_id if b is Car else (b as Cargo).kind
		print("YARD %s %s: settled %.2f m from where it was put, %s, %s, height above ground %.2f" % [
			b.name, what, moved, "frozen" if b.freeze else "awake", "upright" if b.global_basis.y.y > 0.95 else "TILTED %.0f deg" % rad_to_deg(acos(clampf(b.global_basis.y.y, -1, 1))),
			b.global_position.y - world.terrain.height_at(b.global_position.x, b.global_position.z)])
	var out := str(_args.get("out", "user://yard"))
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	root.add_child(cam)
	var shots := {
		"overview": [Vector3(35.0, 30.0, 40.0), Vector3(-8.0, 0.0, 2.0)],
		"rig": [Vector3(8.0, 4.0, 6.0), Vector3(1.7, 1.5, 22.0)],
		"rollback": [Vector3(-10.0, 2.6, -24.0), Vector3(-10.0, 1.2, -6.0)],
		"forklift": [Vector3(-20.0, 16.0, -6.0), Vector3(-20.0, 0.0, -20.0)],
	}
	for nm: String in shots:
		var pts: Array = shots[nm]
		var eye: Vector3 = base * (pts[0] as Vector3)
		var at: Vector3 = base * (pts[1] as Vector3)
		eye.y = world.terrain.height_at(eye.x, eye.z) + (pts[0] as Vector3).y
		at.y = world.terrain.height_at(at.x, at.z) + (pts[1] as Vector3).y
		cam.global_position = eye
		cam.look_at(at)
		cam.make_current()
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])
		print("YARD shot %s" % nm)
	if _args.has("drive"):
		await _drive(main, base)
	quit()


## Get in the tractor, back it under the trailer, and pull away, on the
## town's own ground.
func _drive(main: Node, base: Transform3D) -> void:
	var tractor: Car = null
	for n in main.get_children():
		if n is Car and (n as Car).model_id == "hauler":
			tractor = n
	var player: PlayerController = main.get_node("Player")
	player.enter_vehicle(tractor)
	var rig: CameraRig = main.get_node("CameraRig")
	rig.target = tractor
	rig.set_vehicle_mode(true)
	main.call("_vehicle_camera", tractor)
	var t := 0.0
	while tractor.towing == null and t < 25.0:
		Input.action_press("brake_reverse", 0.35 if tractor.speed > -1.0 else 0.0)
		if tractor.speed <= -1.0:
			Input.action_release("brake_reverse")
		await physics_frame
		t += 1.0 / 60.0
	Input.action_release("brake_reverse")
	print("YARD drive: %s after %.1f s backing up" % ["coupled" if tractor.towing != null else "NOT COUPLED", t])
	if tractor.towing == null:
		return
	main.call("_vehicle_camera", tractor)
	var straps := tractor.towing.tie_downs.strap_all()
	Input.action_press("accelerate", 0.6)
	for i in 420:
		await physics_frame
	Input.action_release("accelerate")
	print("YARD drive: strapped %d, pulled away to %.0f km/h, %.1f m from the start, trailer %s, tractor %s" % [
		straps, tractor.speed * 3.6, tractor.global_position.distance_to(base * Vector3(1.7, 0, 15.5)),
		"upright" if tractor.towing.global_basis.y.y > 0.95 else "TILTED", "upright" if tractor.global_basis.y.y > 0.95 else "TILTED"])
	(rig.camera as Camera3D).make_current()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/driving.png" % str(_args.get("out", "user://yard")))
	Input.action_press("brake_reverse")
	for i in 240:
		await physics_frame
	Input.action_release("brake_reverse")

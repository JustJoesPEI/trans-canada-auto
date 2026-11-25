extends SceneTree
## Records a scripted drive through the game's own sound code, so the car
## sounds can be checked exactly as the game plays them:
##
##   godot --headless --path . --write-movie /tmp/drive.avi --fixed-fps 60 \
##       --script res://tools/sound_drive.gd -- [--car=pony_gt]
##   ffmpeg -i /tmp/drive.avi -vn drive.mp3
##
## (Movie mode mixes the audio in step with the frames, so it works with no
## sound card.) A flat pad, a chase camera, and a driver who gets in, idles,
## blips the throttle, launches, lifts, brakes, throws it into a handbrake
## turn, clips a wall, and gets out.
##
## --cockpit uses the game's own camera rig and moves to the driver's seat
## for the launch and the coast after it (the muffled cabin sound), then back
## out to the chase view for the rest. --chase uses the game's own camera rig
## in the chase view all the way (with --fixed-fps under 60 that's the game
## at a lower frame rate: the camera and the car's sounds move out of step
## with the physics just as they do when playing).

var _driver := Node3D.new()
var _cam := Camera3D.new()
var _car: Car
var _rig: CameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var id := "pony_gt"
	var cockpit := false
	var chase := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			id = a.trim_prefix("--car=")
		elif a == "--cockpit":
			cockpit = true
		elif a == "--chase":
			chase = true
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 3000)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -1, -1400)
	pad.add_child(cs)
	# a wall to clip at the end, and a curb on the way
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.SOLID
	var wb := BoxShape3D.new()
	wb.size = Vector3(40, 3, 1)
	var ws := CollisionShape3D.new()
	ws.shape = wb
	wall.add_child(ws)
	root.add_child(pad)
	root.add_child(_driver)
	if cockpit or chase:
		_rig = (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
		root.add_child(_rig)
	else:
		root.add_child(_cam)
		_cam.current = true

	_car = Car.new()
	_car.model_id = id
	root.add_child(_car)
	_car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))
	if _rig != null:
		_rig.target = _car
		_rig.set_vehicle_mode(true)
		_rig.camera.current = true
		_rig.snap_to_target()
	await _wait(1.2)
	_car.driver = _driver # key on
	await _wait(3.5)
	for i in 2: # blip, blip
		Input.action_press("accelerate", 0.7)
		await _wait(0.12)
		Input.action_release("accelerate")
		await _wait(0.9)
	await _wait(0.6)
	if _rig != null:
		_rig.set_cockpit(true)
	Input.action_press("accelerate")
	await _until(func() -> bool: return _car.speed * 3.6 > 140.0, 14.0)
	Input.action_release("accelerate")
	await _wait(2.2)
	if _rig != null:
		_rig.set_cockpit(false)
	Input.action_press("brake_reverse")
	await _until(func() -> bool: return _car.speed * 3.6 < 70.0, 5.0)
	Input.action_release("brake_reverse")
	Input.action_press("accelerate", 0.6)
	Input.action_press("steer_left")
	await _wait(1.0)
	Input.action_press("handbrake")
	await _wait(0.8)
	Input.action_release("handbrake")
	Input.action_release("steer_left")
	Input.action_press("accelerate")
	await _wait(1.6)
	Input.action_release("accelerate")
	# put the wall just ahead
	var ahead := _car.global_position + (-_car.global_basis.z).normalized() * 25.0
	wall.global_transform = Transform3D(Basis.looking_at(-_car.global_basis.z, Vector3.UP), Vector3(ahead.x, 1.5, ahead.z))
	root.add_child(wall)
	wall.global_position = Vector3(ahead.x, 1.5, ahead.z)
	Input.action_press("accelerate", 0.5)
	await _until(func() -> bool: return _car.speed < 3.0, 6.0)
	Input.action_release("accelerate")
	await _wait(2.0)
	_car.driver = null # key off
	await _wait(2.0)
	quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		_follow()
		t += root.get_process_delta_time()


func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while t < limit and not cond.call():
		await process_frame
		_follow()
		t += root.get_process_delta_time()


func _follow() -> void:
	if _car == null or _rig != null:
		return
	var back := _car.global_basis.z
	back.y = 0.0
	var want := _car.global_position + back.normalized() * 6.0 + Vector3.UP * 2.0
	_cam.global_position = _cam.global_position.lerp(want, 0.15) if _cam.global_position != Vector3.ZERO else want
	_cam.look_at(_car.global_position + Vector3.UP * 0.8)

extends SceneTree
## Screenshots for the itch.io page (docs/itch-page.md), taken in the real
## game: the player's car driven by the game's own autopilot through the
## town's traffic and people, a real police chase after it, the phone and
## the town map open over it, and a few framed views. Run with a real
## renderer, at a fixed frame rate (the town's clocks run on game time):
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##       godot --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 15 --path . \
##       --script res://tools/itch_shots.gd -- [--out=/tmp/itch-shots] [--only=drive,phone,foot,chase]
##
## Saves OUT/NAME.png for each picture and prints "ITCH_SHOT path". Nothing
## is drawn while the town runs between pictures (in software a frame takes
## seconds), so a scene's minute of traffic takes a minute or two.

var _out := "/tmp/itch-shots"
var _only: PackedStringArray = []
var _main: Node
var _world: WorldBuilder
var _player: PlayerController
var _rig: CameraRig
var _hud: Hud
var _cam: Camera3D
var _car: Car


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	# Between pictures nothing is drawn: in software even an undrawn frame
	# waits on the 3D view otherwise.
	RenderingServer.render_loop_enabled = false
	root.disable_3d = true
	var notes := root.get_node_or_null("FieldNotes")
	if notes != null:
		notes.process_mode = Node.PROCESS_MODE_DISABLED
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	while _main.get_node_or_null("Police") == null or _main.get_node_or_null("Traffic") == null:
		await process_frame
	_player = _main.get_node("Player")
	_rig = _main.get("camera_rig")
	_hud = _main.get("hud")
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 900.0
	_main.add_child(_cam)
	(_main.get_node("Police") as PoliceDispatcher).patrols = false
	print("ITCH ready")

	if _want("drive"):
		await _drive()
	if _want("phone"):
		await _phone()
	if _want("foot"):
		await _foot()
	if _only.has("ems"): # (not yet: nobody walking when it looks)
		await _ems()
	if _want("chase"):
		await _chase()
	print("ITCH_SHOT done")
	quit(0)


func _want(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


## The player's car on `street` near `near`, in the right-hand lane, facing
## along it (`flip` for the other way), driven by the autopilot to `to`.
func _start_car(model: String, colour: Color, street: String, near: Vector2, to: Vector2, flip := false, civil := true) -> void:
	await _drop_car()
	var e := _edge(street, near)
	var at := _nearest_along(e, near)
	var s: Array = RoadNetwork.sample(e.points, at)
	var p: Vector2 = s[0]
	var dir: Vector2 = s[1]
	if flip or e.oneway == -1:
		dir = -dir
	var right := Vector2(-dir.y, dir.x)
	var lane := StreetRoute._lane_offset(e, true) if e.oneway == 0 else 0.0
	p += right * lane
	print("ITCH loading round %s on %s" % [p, street])
	await _load_at(p)
	print("ITCH loaded")
	_car = Car.new()
	_car.model_id = model
	_car.paint = colour
	_car.owner_id = "local"
	_car.name = "ItchCar"
	_main.add_child(_car)
	_car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(p) + Vector3.UP * 0.6)
	_car.reset_physics_interpolation()
	(_main.get("cars") as Array).append(_car)
	await physics_frame
	_main.call("seat_player", _car)
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = _world.network
	_car.add_child(ap)
	if civil:
		ap.use_civil_driving()
	ap.drive_to(_v3(to))
	_rig.snap_to_target()


func _drop_car() -> void:
	if _car == null:
		return
	_main.call("unseat_player")
	(_main.get("cars") as Array).erase(_car)
	_car.queue_free()
	_car = null
	await physics_frame


## 1. Driving downtown in traffic: the game's own camera and HUD, then a
## couple of framed views of the car among the town's cars and people.
func _drive() -> void:
	await _start_car("pony_gt", Color(0.75, 0.08, 0.06), "Grafton Street", Vector2(-150, -60), Vector2(400, -60))
	await _sim(14.0)
	await _snap("drive_grafton_hud")
	await _sim(4.0)
	await _snap("drive_grafton_hud2")
	_hud.visible = false
	await _framed("drive_grafton_front", 9.0, 2.2, 25.0)
	await _sim(5.0)
	await _framed("drive_grafton_side", 8.0, 1.4, 80.0)
	_hud.visible = true
	# Down Great George toward St. Dunstan's.
	await _start_car("civique", Color(0.1, 0.25, 0.55), "Great George Street", Vector2(5, -180), Vector2(20, 90))
	await _sim(10.0)
	await _snap("drive_great_george_hud")
	_hud.visible = false
	await _framed("great_george_behind", 11.0, 3.5, 180.0, 40.0)
	_hud.visible = true


## The car's position, with the camera `dist` m off at `angle` degrees from
## its nose (0 in front, 180 behind), `lift` m up, looking `ahead` m along.
func _framed(name: String, dist: float, lift: float, angle: float, ahead := 0.0) -> void:
	var xf := _car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var off := fwd.rotated(Vector3.UP, deg_to_rad(angle)) * dist
	var eye := xf.origin + off + Vector3.UP * lift
	var at := xf.origin + Vector3.UP * 0.9 + fwd * ahead
	_cam.look_at_from_position(eye, at)
	_cam.make_current()
	await _snap(name)
	_rig_camera_current()


func _rig_camera_current() -> void:
	for c in _rig.find_children("*", "Camera3D", true, false):
		(c as Camera3D).make_current()
		return


## 2. The phone (SpudDash, Kinbook, Jobs) and the town map, over a drive.
func _phone() -> void:
	if _car == null:
		await _start_car("pony_gt", Color(0.75, 0.08, 0.06), "Grafton Street", Vector2(-150, -60), Vector2(400, -60))
		await _sim(12.0)
	else:
		await _sim(3.0)
	var phone: Phone = _hud.phone
	for app: String in ["spuddash", "kinbook", ""]:
		phone.open(app)
		await _snap("phone_" + (app if app != "" else "home"))
		phone.close()
	var wm: WorldMap = _hud.world_map
	# A waypoint to Victoria Park, so the route shows.
	wm.gps.set_waypoint(_v3(Vector2(-1000, 420)), "Victoria Park")
	await _sim(1.0)
	await _snap("drive_waypoint_hud")
	wm.open()
	await _snap("town_map")
	wm.close()


## 3. On foot downtown among the people, the game's camera.
func _foot() -> void:
	await _drop_car()
	var spots := [["Richmond Street", Vector2(-40, 60)], ["Queen Street", Vector2(-80, 20)]]
	for s: Array in spots:
		var e := _edge(s[0], s[1])
		var at := _nearest_along(e, s[1])
		var smp: Array = RoadNetwork.sample(e.points, at)
		var dir: Vector2 = smp[1]
		var right := Vector2(-dir.y, dir.x)
		var p: Vector2 = (smp[0] as Vector2) + right * (e.half_width + 1.5)
		await _load_at(p)
		_player.place(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(p) + Vector3.UP * 0.1))
		_rig.snap_to_target()
		await _sim(20.0)
		await _snap("foot_" + str(s[0]).to_snake_case())


## 5. Someone on the sidewalk clipped by the player's car, and the Island
## Boo-Boo Bus coming to see to them (as tools/emergency_check.gd).
func _ems() -> void:
	await _drop_car()
	var e := _edge("Queen Street", Vector2(-80, 20))
	var p: Vector2 = RoadNetwork.sample(e.points, _nearest_along(e, Vector2(-80, 20)))[0]
	await _load_at(p)
	_player.place(Transform3D(Basis.IDENTITY, _v3(p) + Vector3.UP * 0.1))
	_rig.snap_to_target()
	var pm: PedestrianManager = _main.get_node("Pedestrians")
	await _sim(25.0)
	var victim: Pedestrian = null
	var best := 120.0
	for q: Pedestrian in pm.people:
		if is_instance_valid(q) and q.state == Pedestrian.State.WALK and q.leader == null and q.companion == null:
			var d := q.global_position.distance_to(_player.global_position)
			if d < best:
				best = d
				victim = q
	if victim == null:
		print("ITCH nobody walking for the Boo-Boo Bus")
		return
	_car = Car.new()
	_car.model_id = "halfton"
	_car.paint = Color(0.2, 0.3, 0.25)
	_car.owner_id = "local"
	_main.add_child(_car)
	var h: Vector2 = victim._heading
	var at := victim.global_position - Vector3(h.x, 0.0, h.y) * 6.0
	_car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-h.x, -h.y)), at + Vector3.UP * 0.6)
	_car.reset_physics_interpolation()
	(_main.get("cars") as Array).append(_car)
	await physics_frame
	_player.enter_vehicle(_car)
	await physics_frame
	victim.reaction = 5.0
	for i in 40:
		_car.linear_velocity = -_car.global_basis.z * 11.0
		await physics_frame
		if victim.state == Pedestrian.State.DOWN:
			break
	_car.linear_velocity = Vector3.ZERO
	_player.exit_vehicle(_main)
	_player.model.visible = true
	_rig.target = _player
	_rig.set_vehicle_mode(false)
	_hud.visible = false
	for i in 14:
		await _sim(10.0)
		if not is_instance_valid(victim):
			break
		var v := victim.global_position
		var side := Vector3(1, 0, 0).rotated(Vector3.UP, deg_to_rad(40.0 * i))
		_cam.look_at_from_position(v + side * 11.0 + Vector3.UP * 3.5, v + Vector3.UP * 0.8)
		_cam.make_current()
		await _snap("ems_%02d" % i)
	_rig_camera_current()
	_hud.visible = true


## 4. A real chase: wanted level 2, then 3, the car driven away across
## town by the autopilot and the police after it. Pictures every few
## seconds; pick the best.
func _chase() -> void:
	await _start_car("pony_gt", Color(0.75, 0.08, 0.06), "Grafton Street", Vector2(-250, -60), Vector2(700, -500), false, false)
	var police: PoliceDispatcher = _main.get_node("Police")
	police.enabled = true
	await _sim(4.0)
	root.get_node("Wanted").call("debug_set_level", 2)
	for i in 10:
		await _sim(5.0)
		if i == 3:
			root.get_node("Wanted").call("debug_set_level", 3)
		await _snap("chase_%02d" % i)
		_hud.visible = false
		await _framed("chase_%02d_behind" % i, 16.0, 4.0, 160.0)
		_hud.visible = true


## Runs the town for `secs` of game time with nothing drawn.
func _sim(secs: float) -> void:
	RenderingServer.render_loop_enabled = false
	var w0 := Time.get_ticks_msec()
	var t := 0.0
	var n := 0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		n += 1
		if n % 30 == 0:
			_world.streamer.refresh()
	print("ITCH ran %.0f s of town in %d s" % [secs, (Time.get_ticks_msec() - w0) / 1000])
	# The town round wherever the car got to.
	await _world.wait_until_settled(2.0)


func _snap(name: String) -> void:
	root.disable_3d = false
	RenderingServer.render_loop_enabled = true
	# A few frames for the sky, shadows and screen-space effects to settle
	# (the HUD's fades run on game time and barely move in this).
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("ITCH_SHOT %s" % path)
	RenderingServer.render_loop_enabled = false
	root.disable_3d = true


func _load_at(p: Vector2) -> void:
	var s := _world.streamer
	_cam.global_position = Vector3(p.x, _world.terrain.h2(p) + 3.0, p.y)
	_cam.make_current()
	_player.global_position = _v3(p) + Vector3.UP * 0.2
	RenderingServer.render_loop_enabled = false
	s.refresh()
	var t0 := Time.get_ticks_msec()
	var last_check := t0
	var last_note := t0
	var f0 := Engine.get_process_frames()
	while not s.is_settled() and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
		var now := Time.get_ticks_msec()
		if now - last_check > 100:
			last_check = now
			s.refresh()
		if now - last_note > 15000:
			last_note = now
			print("ITCH waiting %d s, %d frames, near=%d far=%d jobs=%d done=%d" % [(now - t0) / 1000, Engine.get_process_frames() - f0, s._near.size(), s._far.size(), s._jobs.size(), s._done.size()])
	await _world.wait_until_settled(2.0)
	_rig_camera_current()


func _edge(street: String, near: Vector2) -> RoadNetwork.RoadEdge:
	var best: RoadNetwork.RoadEdge = null
	var best_d := INF
	for e in _world.network.edges_near(Rect2(near - Vector2(600, 600), Vector2(1200, 1200))):
		if e.name != street or e.length < 40.0:
			continue
		var d := (RoadNetwork.sample(e.points, _nearest_along(e, near))[0] as Vector2).distance_to(near)
		if d < best_d:
			best_d = d
			best = e
	assert(best != null, "no %s near %s" % [street, near])
	return best


## How far along `e` the point nearest `p` is.
func _nearest_along(e: RoadNetwork.RoadEdge, p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	var run := 0.0
	for i in e.points.size() - 1:
		var a := e.points[i]
		var b := e.points[i + 1]
		var seg := a.distance_to(b)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = run + a.distance_to(q)
		run += seg
	return clampf(best, 10.0, maxf(10.0, e.length - 10.0))


func _v3(p: Vector2) -> Vector3:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var h := _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 8.0, p.y), Vector3(p.x, h - 4.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return Vector3(p.x, h if hit.is_empty() else (hit["position"] as Vector3).y, p.y)

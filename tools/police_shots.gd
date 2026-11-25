extends SceneTree
## Pictures of the police in the real town, for checking how they look:
## a city cruiser and an FIP SUV with the passenger leaning out, officers on
## foot (one painted out: the OUT vest and the marker held up), a paint
## strip, a two-car roadblock, a harvester roadblock and the Paint Tank.
## Run with a real renderer:
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##       --resolution 1280x720 --script res://tools/police_shots.gd -- [--out=/tmp/police-shots] [--at=x,z]
##
## Saves OUT/NAME.png for each view and prints the paths.

var _main: Node
var _world: WorldBuilder
var _police: PoliceDispatcher
var _cam: Camera3D
var _out := "/tmp/police-shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(args.get("out", _out))
	DirAccess.make_dir_recursive_absolute(_out)
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	root.get_node("Wanted").set("play_panels", false)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	_police = _main.get_node("Police")
	_police.patrols = false
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var spot := Vector2(-120, 60)
	if args.has("at"):
		var xz: PackedStringArray = str(args["at"]).split(",")
		spot = Vector2(float(xz[0]), float(xz[1]))
	# A straight two-way street near the spot, with a junction at one end.
	var e := _street_near(spot)
	var a: Vector2 = RoadNetwork.sample(e.points, e.length * 0.35)[0]
	var dir: Vector2 = RoadNetwork.sample(e.points, e.length * 0.35)[1]
	var right := Vector2(-dir.y, dir.x)
	var player: Node3D = _main.get_node("Player")
	player.set_physics_process(false)
	player.global_position = _v3(a - right * 30.0) + Vector3.UP * 0.1
	_main.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_main.add_child(_cam)
	_cam.make_current()
	_cam.global_position = _v3(a) + Vector3.UP * 3.0
	await _world.wait_until_settled()
	await _settle_at(a)
	var lane := StreetRoute._lane_offset(e, true)
	# Staged, not driven: the dispatcher leaves them as they're put.
	_police.enabled = false

	# 1. An FIP SUV and a city cruiser, lights on, the passenger leaning out.
	var fip := _unit("fip", a + right * lane, dir)
	var city := _unit("city", a + right * lane - dir * 12.0, dir)
	var target := Node3D.new()
	_main.add_child(target)
	target.global_position = _v3(a + dir * 25.0) + Vector3.UP * 1.0
	for u: PoliceUnit in [fip, city]:
		u.car.police.set_mode(PoliceGear.Mode.LIGHTS)
		u.car.freeze = true
		var pas: Officer = u.officers[1]
		pas.lean_out(true)
		pas.shoot_at = target
		pas.shoot_range = 60.0
	await _wait(1.5)
	var p0 := fip.car.global_position
	await _shot("suv_lean_front", p0 + _v3d(dir * 8.0 + right * 5.0) + Vector3.UP * 1.6, p0 + Vector3.UP * 1.3)
	await _shot("suv_side", p0 + _v3d(right * 7.5) + Vector3.UP * 1.4, p0 + Vector3.UP * 1.0)
	await _shot("cruiser_rear", city.car.global_position + _v3d(-dir * 8.0 - right * 3.0) + Vector3.UP * 1.8, city.car.global_position + Vector3.UP * 1.0)

	# 2. Officers on foot: one shooting, one painted out.
	var foot_at := a - right * (e.half_width + 2.5) + dir * 6.0
	var o1 := Officer.new()
	o1.force = "city"
	_main.add_child(o1)
	o1.global_position = _v3(foot_at) + Vector3.UP * 0.1
	o1.look_at(o1.global_position + _v3d(dir), Vector3.UP)
	o1.shoot_at = target
	var o2 := Officer.new()
	o2.force = "fip"
	_main.add_child(o2)
	o2.global_position = _v3(foot_at + dir * 2.5) + Vector3.UP * 0.1
	o2.look_at(o2.global_position - _v3d(right), Vector3.UP)
	await _wait(0.3)
	for i in 3:
		o2.take_paint_hit(1, player, o2.global_position + Vector3.UP * 1.2)
	await _wait(1.5)
	var mid := (o1.global_position + o2.global_position) * 0.5
	await _shot("officers_out", mid + _v3d(-right * 5.0 + dir * 1.0) + Vector3.UP * 1.7, mid + Vector3.UP * 1.2)
	await _shot("out_vest_back", o2.global_position + _v3d(right * 3.0) + Vector3.UP * 1.6, o2.global_position + Vector3.UP * 1.3)

	# 3. A paint strip across the road ahead.
	var strip_at := a + dir * 40.0
	PaintStrip.lay(_main, _v3(strip_at), dir)
	await _wait(0.3)
	await _shot("paint_strip", _v3(strip_at - dir * 14.0 + right * 3.0) + Vector3.UP * 2.2, _v3(strip_at))

	# 4. A two-car roadblock and a harvester one, further along.
	var rb_at := a + dir * 80.0
	PoliceRoadblock.build(_police, _main, _v3(rb_at), -dir, e.half_width, "cars", "fip")
	await _wait(1.5)
	await _shot("roadblock", _v3(rb_at - dir * 22.0) + Vector3.UP * 2.0, _v3(rb_at) + Vector3.UP * 0.8)
	var hv_at := a - dir * 60.0
	PoliceRoadblock.build(_police, _main, _v3(hv_at), dir, e.half_width, "harvester", "fip")
	await _wait(1.5)
	await _shot("harvester_roadblock", _v3(hv_at + dir * 24.0 + right * 4.0) + Vector3.UP * 3.0, _v3(hv_at) + Vector3.UP * 1.5)

	# 5. The Paint Tank.
	var tank := _unit("tactical", a - right * lane - dir * 30.0, -dir)
	tank.car.freeze = true
	tank.car.police.set_mode(PoliceGear.Mode.LIGHTS)
	await _wait(1.0)
	var tp := tank.car.global_position
	await _shot("paint_tank", tp + _v3d(-dir * 10.0 + right * 6.0) + Vector3.UP * 3.0, tp + Vector3.UP * 1.6)
	await _shot("paint_tank_side", tp + _v3d(right * 11.0) + Vector3.UP * 2.0, tp + Vector3.UP * 1.5)
	quit(0)


func _unit(force: String, p: Vector2, dir: Vector2) -> PoliceUnit:
	var u := _police.new_unit(force)
	u.order(PoliceUnit.Role.CHASE, _v3(p), _police.clock)
	u.place_physical(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _v3(p) + Vector3.UP * 0.4), _main)
	return u


func _street_near(p: Vector2) -> RoadNetwork.RoadEdge:
	var best: RoadNetwork.RoadEdge = null
	for e in _world.network.edges_near(Rect2(p - Vector2(900, 900), Vector2(1800, 1800))):
		if e.oneway != 0 or e.length < 170.0 or e.bridge or e.highway.begins_with("motorway"):
			continue
		var straight := e.points[0].distance_to(e.points[e.points.size() - 1]) / e.length
		if straight < 0.92:
			continue
		if best == null or (RoadNetwork.sample(e.points, e.length * 0.5)[0] as Vector2).distance_to(p) < (RoadNetwork.sample(best.points, best.length * 0.5)[0] as Vector2).distance_to(p):
			best = e
	return best


func _v3(p: Vector2) -> Vector3:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var h := _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 8.0, p.y), Vector3(p.x, h - 4.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return Vector3(p.x, h if hit.is_empty() else (hit["position"] as Vector3).y, p.y)


static func _v3d(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, d.y)


func _settle_at(p: Vector2) -> void:
	_cam.global_position = _v3(p) + Vector3.UP * 3.0
	var s := _world.streamer
	s._focus = p
	s._has_focus = true
	s.refresh()
	await _world.wait_until_settled()
	await _wait(1.0)


## Game time (physics steps): drawn in software a frame can take seconds,
## and a wait in frames would let the officers' clocks run on.
func _wait(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _shot(name: String, eye: Vector3, at: Vector3) -> void:
	_cam.look_at_from_position(eye, at)
	for i in 3:
		await process_frame
	var path := "%s/%s.png" % [_out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("POLICE_SHOT %s" % path)

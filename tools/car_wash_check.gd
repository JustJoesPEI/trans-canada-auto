extends SceneTree
## Checks every car wash bay can be driven into: a car starts on the street
## nearest the bay's way in, a computer driver takes it to the middle of the
## bay (lining up outside its way in, then straight in along the bay, as a
## player would) and it must end up
## inside the bay (CarWashes.bay_at) and stay there long enough to come out
## clean. A bay you can't drive into is no way out of a chase.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/car_wash_check.gd
##
## Exits non-zero on failure.

const MODEL := "civique"
const LIMIT := 60.0 ## seconds to get in

var _main: Node
var _world: Node
var _cam := Camera3D.new()
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	_main.get_node("Player").process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_cam)
	_cam.make_current()
	var net: RoadNetwork = _world.network
	var spots := CarWashes.find_spots(_world)
	_check(spots.size() >= 3, "the car washes are on the map (%d)" % spots.size())
	var washes := CarWashes.new()
	for s in spots:
		var xf: Transform3D = s["xform"]
		var name: String = s["name"]
		washes.spots = [s]
		# The way in is the bay's +Z end; start on the street nearest it.
		var mouth := CarWashes.way_in(s, 8.0)
		var near: Dictionary = net.nearest_on_streets(Vector2(mouth.x, mouth.z), 120.0)
		if near.is_empty():
			_check(false, "%s: a street near its way in" % name)
			continue
		var start: Vector2 = near["pos"]
		_cam.global_position = Vector3(start.x, xf.origin.y + 4.0, start.y)
		await _world.wait_until_settled()
		for i in 30:
			await physics_frame
		var car := Car.new()
		car.model_id = MODEL
		_main.add_child(car)
		var to_bay := Vector2(xf.origin.x, xf.origin.z) - start
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-to_bay.x, -to_bay.y)), Vector3(start.x, _ground_y(start) + 0.3, start.y))
		car.reset_physics_interpolation()
		var ap := CarAutopilot.new()
		ap.network = net
		car.add_child(ap)
		await physics_frame
		# Line up outside the way in, then straight in along the bay to its
		# middle, and wait there to be washed.
		var flat := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
		var line := PackedVector2Array([start, flat.call(mouth), flat.call(CarWashes.way_in(s, 1.0)), flat.call(xf.origin)])
		var r := StreetRoute.along(line, {"top_speed": 4.0})
		ap.drive_route(r, 0.0, xf.origin)
		var t := 0.0
		var inside := 0.0
		while t < LIMIT and inside < CarWashes.WASH_SECONDS:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			_cam.global_position = car.global_position + Vector3(0, 4, 0)
			if washes.bay_at(car.global_position) >= 0:
				inside += 1.0 / Engine.physics_ticks_per_second
			else:
				inside = 0.0
		var d := Vector2(car.global_position.x - xf.origin.x, car.global_position.z - xf.origin.z).length()
		var loc := xf.affine_inverse() * car.global_position
		print("  %s: ended at local (%.1f, %.1f, %.1f), autopilot %s, speed %.1f" % [name, loc.x, loc.y, loc.z, ap.state, car.speed])
		_check(inside >= CarWashes.WASH_SECONDS, "%s: driven in from the street at (%.0f, %.0f) and held %.0f s in the bay (took %.0f s, %.1f m from its middle)" % [name, start.x, start.y, CarWashes.WASH_SECONDS, t, d])
		car.queue_free()
		await physics_frame
	washes.free()
	print("CARWASH %s" % ("all checks passed" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _ground_y(p: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	var h: float = _world.terrain.h2(p)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 6.0, p.y), Vector3(p.x, h - 3.0, p.y), Layers.GROUND)
	var hit := space.intersect_ray(q)
	return h if hit.is_empty() else (hit["position"] as Vector3).y


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print(("ok    " if ok else "FAIL  ") + what)

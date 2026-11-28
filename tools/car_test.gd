extends SceneTree
## Drives each car on a flat test pad with scripted inputs and prints how it
## performs, so changes to the physics or the car settings can be checked:
##
##   godot --headless --path . --script res://tools/car_test.gd -- [--car=civique] [--parts=a,b]
##
## Measures: how it settles at rest, 0-100 km/h, top speed, braking from
## 100, cornering grip at 60 km/h, a handbrake turn, and a jump (time in the
## air off a ramp at 90 km/h). One "CARTEST" line per result.

var _pad: StaticBody3D
var _driver := Node3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cars: Array = [str(args["car"])] if args.has("car") else ["civique", "pony_gt", "halfton"]
	var parts: Array[String] = []
	if args.has("parts"):
		for p in str(args["parts"]).split(","):
			parts.append(p)
	_build_pad()
	root.add_child(_driver)
	for id: String in cars:
		await _test(id, parts)
	quit()


func _build_pad() -> void:
	_pad = StaticBody3D.new()
	_pad.collision_layer = Layers.GROUND
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(400, 2, 6000)
	var cs := CollisionShape3D.new()
	cs.shape = floor_shape
	cs.position = Vector3(0, -1, -2900)
	_pad.add_child(cs)
	# A ramp for the jump test, off to the side of the straight: 4 m long,
	# up 0.6 m, then a sheer drop.
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = PackedVector3Array([
		Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(-4, 0, -6), Vector3(4, 0, -6),
		Vector3(-4, 0.7, -6), Vector3(4, 0.7, -6)])
	var rs := CollisionShape3D.new()
	rs.shape = ramp
	rs.position = Vector3(100, 0, -300)
	_pad.add_child(rs)
	root.add_child(_pad)


func _spawn(id: String, parts: Array[String], at: Vector3) -> Car:
	var car := Car.new()
	car.model_id = id
	car.parts = parts
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, at)
	car.driver = _driver
	return car


func _hold(action: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for a in ["accelerate", "brake_reverse", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)


func _test(id: String, parts: Array[String]) -> void:
	var name := id + ("+" + ",".join(parts) if not parts.is_empty() else "")
	# --- settling: drop it on the pad and watch it come to rest -----------------
	var car := _spawn(id, parts, Vector3(0, 0.3, 0))
	var max_bob := 0.0
	for i in 180:
		await physics_frame
		if i > 90:
			max_bob = maxf(max_bob, absf(car.linear_velocity.y))
	var rest_y := car.global_position.y
	print("CARTEST %s settle: body at %.3f m, still moving %.3f m/s after 1.5 s, wheels down %d" % [name, rest_y, max_bob, car.wheels_down])

	# --- 0-100 and top speed ---------------------------------------------------------
	_hold("accelerate", true)
	var t := 0.0
	var t100 := -1.0
	var top := 0.0
	var max_pitch := 0.0
	while t < 45.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var kmh := car.speed * 3.6
		top = maxf(top, kmh)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		max_pitch = maxf(max_pitch, absf(car.global_basis.get_euler().x))
	print("CARTEST %s 0-100 km/h: %.1f s, top speed %.0f km/h (gear %d, %.0f rpm), most squat %.1f deg" % [name, t100, top, car.gear, car.rpm, rad_to_deg(max_pitch)])

	# --- braking from 100 ------------------------------------------------------------
	_release_all()
	_hold("brake_reverse", true)
	while car.speed * 3.6 > 101.0:
		await physics_frame
	var start := car.global_position
	var dive := 0.0
	while car.speed > 0.3:
		await physics_frame
		dive = maxf(dive, absf(car.global_basis.get_euler().x))
	print("CARTEST %s braking 100-0: %.1f m, most dive %.1f deg" % [name, start.distance_to(car.global_position), rad_to_deg(dive)])
	_release_all()
	car.queue_free()
	await physics_frame

	# --- cornering: hold 60 km/h and steer full left, see what it can take ------
	car = _spawn(id, parts, Vector3(0, 0.3, 0))
	for i in 60:
		await physics_frame
	_hold("accelerate", true)
	while car.speed * 3.6 < 60.0:
		await physics_frame
	var peak_lat := 0.0
	var roll := 0.0
	_hold("steer_left", true)
	for i in 180:
		await physics_frame
		# Keep the speed about 60 with the throttle.
		_hold("accelerate", car.speed * 3.6 < 60.0, 0.6)
		var lat := absf(car.speed * car.angular_velocity.y) / 9.81
		peak_lat = maxf(peak_lat, lat)
		roll = maxf(roll, absf(car.global_basis.get_euler().z))
	print("CARTEST %s cornering at 60 km/h: %.2f g, most lean %.1f deg" % [name, peak_lat, rad_to_deg(roll)])

	# --- handbrake turn from 50 ---------------------------------------------------------
	_release_all()
	for i in 120:
		await physics_frame
		_hold("accelerate", car.speed * 3.6 < 50.0)
	var yaw0 := car.global_basis.get_euler().y
	var turned := 0.0
	var last := yaw0
	_release_all()
	_hold("handbrake", true)
	_hold("steer_left", true)
	for i in 90:
		await physics_frame
		var y := car.global_basis.get_euler().y
		turned += absf(angle_difference(last, y))
		last = y
	_release_all()
	_hold("brake_reverse", true)
	for i in 120:
		await physics_frame
		var y2 := car.global_basis.get_euler().y
		turned += absf(angle_difference(last, y2))
		last = y2
	print("CARTEST %s handbrake turn from 50: swung round %.0f deg" % [name, rad_to_deg(turned)])
	_release_all()
	car.queue_free()
	await physics_frame

	# --- the jump: 90 km/h up a 0.7 m ramp ---------------------------------------------------
	car = _spawn(id, parts, Vector3(100, 0.3, -120))
	for i in 60:
		await physics_frame
	_hold("accelerate", true)
	var air := 0.0
	var longest := 0.0
	var peak_y := 0.0
	var landed_upright := true
	for i in 900:
		await physics_frame
		_hold("accelerate", car.speed * 3.6 < 90.0)
		if car.global_position.z < -260.0:
			if car.wheels_down == 0:
				air += 1.0 / Engine.physics_ticks_per_second
				longest = maxf(longest, air)
			else:
				air = 0.0
			peak_y = maxf(peak_y, car.global_position.y)
		if car.global_position.z < -420.0:
			break
	landed_upright = car.global_basis.y.y > 0.9
	print("CARTEST %s jump at 90 km/h: %.2f s in the air, %.1f m high, landed %s" % [name, longest, peak_y, "upright" if landed_upright else "badly"])
	_release_all()
	car.queue_free()
	await physics_frame

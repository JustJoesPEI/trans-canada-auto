extends SceneTree
## Drives vehicles on test pads of each kind of ground (GroundMap) and
## prints how they cope, for tuning the ground and checking nothing gets
## stuck for good:
##
##   godot --headless --path . --script res://tools/mud_test.gd -- [--car=civique,rammer] [--ground=field]
##
## For each vehicle and ground:
##   floored   full throttle for 25 s from a standstill: how far, the
##             speed at the end, how deep the tyres dug in
##   eased     a light throttle (just short of spinning the wheels)
##   rocking   floored until bogged, then back and forth: does it get out
## and on pavement and lawn the time to 60 km/h, for comparison.
##
##   --only=tow  instead: a pickup on the road straps a car out of a field,
##               and a four-by-four winches itself out of a bog on a post.
## One "MUDTEST" line per result. A line with "STUCK" means a vehicle
## made less than 10 m in 25 s.

var _driver := Node3D.new()
var _pads := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cars: Array = str(args.get("car", "civique,pony_gt,interlude,halfton,rammer,hinterland,yukoner,rollback")).split(",")
	var grounds: Array = str(args.get("ground", "lawn,rough,field,wet,sand")).split(",")
	root.add_child(_driver)
	# A camera, or every parked car is "far away" and freezes.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var kinds := {"paved": GroundMap.PAVED, "gravel": GroundMap.GRAVEL, "lawn": GroundMap.LAWN, "rough": GroundMap.ROUGH,
		"field": GroundMap.FIELD, "wet": GroundMap.WET, "sand": GroundMap.SAND}
	var x := 0.0
	for g: String in kinds:
		_pads[g] = _pad(kinds[g], x)
		x += 300.0
	if str(args.get("only", "")) == "tow":
		await _strap_test()
		await _winch_test()
		quit()
		return
	for id: String in cars:
		await _sprint(id, "paved")
		await _sprint(id, "lawn")
		for g: String in grounds:
			await _crawl(id, g, 1.0, "floored")
			await _crawl(id, g, 0.0, "eased")
			if g in ["field", "wet", "sand"]:
				await _rock(id, g)
	quit()


func _pad(kind: int, x: float, z0 := 100.0, length := 3000.0) -> Vector3:
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, length)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(x, -1, z0 - length * 0.5)
	pad.add_child(cs)
	GroundMap.uniform(kind).attach(pad)
	root.add_child(pad)
	return Vector3(x, 0.3, 0)


func _spawn(id: String, ground: String) -> Car:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, _pads[ground])
	car.driver = _driver
	for i in 90:
		await physics_frame
	return car


func _release_all() -> void:
	for a in ["accelerate", "brake_reverse", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)


func _deepest(car: Car) -> float:
	var d := 0.0
	for s: float in car._sink:
		d = maxf(d, s)
	return d


## 0-60 km/h, to compare pavement and lawn.
func _sprint(id: String, ground: String) -> void:
	var car: Car = await _spawn(id, ground)
	Input.action_press("accelerate", 1.0)
	var t := 0.0
	while car.speed * 3.6 < 60.0 and t < 40.0:
		await physics_frame
		t += 1.0 / 60.0
	var top := 0.0
	for i in 600:
		await physics_frame
		top = maxf(top, car.speed * 3.6)
	print("MUDTEST %s %s: 0-60 km/h %.1f s, %.0f km/h after 10 s more" % [id, ground, t, top])
	_release_all()
	car.queue_free()
	await physics_frame


## Full throttle, or (strength 0) as much as the tyres take without spinning.
func _crawl(id: String, ground: String, strength: float, label: String) -> void:
	var car: Car = await _spawn(id, ground)
	var start := car.global_position
	var throttle := 0.3
	var top := 0.0
	var spinning_time := 0.0
	for i in 25 * 60:
		await physics_frame
		if strength > 0.0:
			Input.action_press("accelerate", strength)
		else:
			# Feather it: back off while the wheels spin, ease on while they grip.
			var spin := 0.0
			for w: float in car._wheel_spin:
				spin = maxf(spin, w)
			throttle = clampf(throttle + (-0.6 if spin > 0.3 else 0.15) / 60.0, 0.05, 1.0)
			Input.action_press("accelerate", throttle)
		top = maxf(top, car.speed * 3.6)
		for w: float in car._wheel_spin:
			if w > 0.3:
				spinning_time += 1.0 / 60.0
				break
	var d := start.distance_to(car.global_position)
	print("MUDTEST %s %s %s: %.0f m in 25 s, %.1f km/h at the end (best %.1f), tyres %.0f cm deep, belly at %.0f cm, spinning %.0f s, bogged %.2f%s" % [
		id, ground, label, d, car.speed * 3.6, top, _deepest(car) * 100.0, car._belly * 100.0, spinning_time, car.bogged,
		"  STUCK" if d < 10.0 else ""])
	_release_all()
	car.queue_free()
	await physics_frame


## Dig in, then rock back and forth with a light foot.
func _rock(id: String, ground: String) -> void:
	var car: Car = await _spawn(id, ground)
	Input.action_press("accelerate", 1.0)
	for i in 8 * 60:
		await physics_frame
	_release_all()
	var dug := _deepest(car)
	var start := car.global_position
	for cycle in 4:
		Input.action_press("brake_reverse", 0.5)
		for i in 90:
			await physics_frame
		_release_all()
		Input.action_press("accelerate", 0.5)
		for i in 120:
			await physics_frame
		_release_all()
	Input.action_press("accelerate", 0.45)
	for i in 6 * 60:
		await physics_frame
	print("MUDTEST %s %s rocking: dug in %.0f cm, after rocking %.0f cm, then %.1f km/h, %.0f m on" % [
		id, ground, dug * 100.0, _deepest(car) * 100.0, car.speed * 3.6, start.distance_to(car.global_position)])
	_release_all()
	car.queue_free()
	await physics_frame


func _spawn_at(id: String, at: Vector3, driven: bool) -> Car:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, at)
	if driven:
		car.driver = _driver
	return car


## A Civique dug into a field; a Rammer on the road ahead straps it and
## pulls away gently.
func _strap_test() -> void:
	var cam := get_root().get_viewport().get_camera_3d()
	# Mud from z = 100 back to -20, road beyond it.
	_pad(GroundMap.FIELD, 3000.0, 100.0, 120.0)
	_pad(GroundMap.PAVED, 3000.0, -20.0, 2000.0)
	var stuck := _spawn_at("civique", Vector3(3000, 0.3, 0), true)
	cam.global_position = Vector3(3008, 4, 0)
	for i in 90:
		await physics_frame
	Input.action_press("accelerate", 1.0)
	for i in 6 * 60:
		await physics_frame
	_release_all()
	var dug := _deepest(stuck)
	stuck.driver = null # its driver's out, waiting for the tow
	var puller := _spawn_at("rammer", stuck.global_position + Vector3(0, 0, -30), true)
	for i in 90:
		await physics_frame
	# Back up to it.
	puller.global_transform = Transform3D(Basis.IDENTITY, stuck.global_position + Vector3(0, 0.3, -float(stuck.shape["length"]) * 0.5 - float(puller.shape["length"]) * 0.5 - 4.0))
	for i in 60:
		await physics_frame
	var msg := puller.line_action()
	var start := stuck.global_position
	var peak := 0.0
	Input.action_press("accelerate", 0.4)
	var t := 0.0
	while t < 30.0 and stuck.global_position.z > -25.0:
		await physics_frame
		t += 1.0 / 60.0
		if puller.tow_line != null:
			peak = maxf(peak, puller.tow_line.tension)
		Input.action_press("accelerate", 0.4 if puller.speed < 3.0 else 0.0)
	_release_all()
	print("MUDTEST strap: \"%s\"; car dug %.0f cm deep, pulled %.0f m in %.1f s%s, most tension %.0f kN" % [
		msg, dug * 100.0, start.distance_to(stuck.global_position), t, " onto the road" if stuck.global_position.z <= -25.0 else " (still in the field)", peak / 1000.0])
	puller.line_action()
	print("MUDTEST strap off: line %s, car free_rolling %s" % ["gone" if puller.tow_line == null else "still on", stuck.free_rolling])
	stuck.queue_free()
	puller.queue_free()
	await physics_frame


## A Yukoner deep in a bog winches itself out on a post 18 m ahead.
func _winch_test() -> void:
	var at := Vector3(_pads["wet"].x, 0.3, -200.0)
	var car := _spawn_at("yukoner", at, true)
	for i in 90:
		await physics_frame
	Input.action_press("accelerate", 1.0)
	for i in 8 * 60:
		await physics_frame
	_release_all()
	var post := StaticBody3D.new()
	post.name = "PostCollision"
	post.collision_layer = Layers.SOLID
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.15
	cyl.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	post.add_child(cs)
	root.add_child(post)
	post.global_position = car.global_position + Vector3(0, 1.0, -18.0)
	for i in 10:
		await physics_frame
	var dug := _deepest(car)
	var msg := car.line_action()
	var start := car.global_position
	Input.action_press("aux_in", 1.0)
	var peak := 0.0
	for i in 30 * 60:
		await physics_frame
		if car.tow_line != null:
			peak = maxf(peak, car.tow_line.tension)
	_release_all()
	print("MUDTEST winch: \"%s\"; dug %.0f cm, wound itself %.1f m toward the post in 30 s, most tension %.0f kN, line %.1f m" % [
		msg, dug * 100.0, start.distance_to(car.global_position), peak / 1000.0, car.tow_line.length if car.tow_line != null else -1.0])
	car.queue_free()
	post.queue_free()
	await physics_frame

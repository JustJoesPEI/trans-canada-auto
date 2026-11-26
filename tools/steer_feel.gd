extends SceneTree
## How each car takes keyboard steering at speed, on a flat pad: holding the
## throttle at 50 and 80 km/h, a quick lane change (a tap one way, then the
## other) and a weave (taps back and forth for a few seconds), with the
## player's steering help (Car.steer_assist) on and off. Prints the most it
## yawed, how far its tail stepped out (the slide angle), whether it spun,
## and how far sideways a lane change moved it.
##
##   godot --headless --path . --script res://tools/steer_feel.gd -- [--car=pony_gt,civique,halfton]
##
## One "STEER" line per run.

var _driver := Node3D.new()
var _pilot := Pilot.new()


class Pilot:
	extends RefCounted
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 3000)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -1, -1400)
	pad.add_child(cs)
	root.add_child(pad)
	root.add_child(_driver)
	for id: String in str(args.get("car", "pony_gt,civique,halfton")).split(","):
		for kmh: float in ([] if args.has("exits") else [50.0, 80.0]):
			for assist: int in [0, 1]:
				await _try(id, kmh, assist, "lane change", [[0.25, 1.0], [0.35, -1.0], [0.2, 0.0]])
				await _try(id, kmh, assist, "weave", [[0.2, 1.0], [0.3, -1.0], [0.3, 1.0], [0.3, -1.0], [0.3, 1.0], [0.3, -1.0], [0.2, 0.0]])
		for assist: int in [0, 1]:
			# Out of a corner: 30 km/h, full lock and flat out for 1.5 s.
			await _try(id, 30.0, assist, "corner exit", [[1.5, 1.0], [0.4, 0.0]])
	quit()


func _try(id: String, kmh: float, assist: int, what: String, taps: Array) -> void:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0))
	car.driver = _driver
	car.ai_controls = _pilot
	car.steer_assist = assist
	car.traction_assist = assist
	for i in 30:
		await physics_frame
	# Up to speed with the throttle, steering straight.
	car.linear_velocity = Vector3(0, 0, -kmh / 3.6 * 0.9)
	_pilot.steer = 0.0
	var n := 0
	while car.speed * 3.6 < kmh and n < 600:
		_pilot.throttle = 1.0
		await physics_frame
		n += 1
	var x0 := car.global_position.x
	var yaw0 := car.global_basis.get_euler().y
	var most_yaw := 0.0
	var most_slide := 0.0
	var spun := false
	_pilot.throttle = 1.0 # flat out, the way it's driven
	var steps: Array = taps.duplicate()
	steps.append([1.5, 0.0]) # then straight, to see it settle
	for s: Array in steps:
		_pilot.steer = float(s[1])
		for i in roundi(float(s[0]) * 60.0):
			await physics_frame
			most_yaw = maxf(most_yaw, absf(car.angular_velocity.y))
			var f := -car.global_basis.z
			var v := car.linear_velocity
			if Vector2(v.x, v.z).length() > 3.0:
				most_slide = maxf(most_slide, absf(Vector2(f.x, f.z).angle_to(Vector2(v.x, v.z))))
			if most_slide > deg_to_rad(60.0):
				spun = true # swapped ends (turning a long way isn't spinning)
	var moved := car.global_position.x - x0
	print("STEER %-8s %3.0f km/h %-11s %s: yaw up to %3.0f deg/s, tail out up to %2.0f deg, %s, sideways %.1f m, ends at %.0f km/h" % [
		id, kmh, what, "help on " if assist == 1 else "help off", rad_to_deg(most_yaw), rad_to_deg(most_slide),
		"SPUN" if spun else "held it", moved, car.speed * 3.6])
	_pilot.throttle = 0.0
	_pilot.steer = 0.0
	car.queue_free()
	await physics_frame

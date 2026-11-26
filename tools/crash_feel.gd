extends SceneTree
## How hitting things feels, on a flat pad: a car at speed into the town's
## kinds of solid thing, straight on and clipping it with a corner, and
## along a wall at a shallow angle, the way you do in a chase. For each:
## how much speed it keeps a second later, how far it was swung round, and
## whether it ended up stuck, spun or on its roof.
##
##   godot --headless --path . --script res://tools/crash_feel.gd -- [--car=civique] [--friction=1.0]
##
## --friction is the solid things' friction (the town's have none set:
## Godot's default, 1.0). One "CRASH" line per hit.

var _driver := Node3D.new()
var _pilot := Pilot.new()
var _friction := -1.0
var _car_friction := -1.0
var _knocked := 0


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
	if args.has("friction"):
		_friction = float(args["friction"])
	if args.has("car-friction"):
		_car_friction = float(args["car-friction"])
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 1200)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -1, -500)
	pad.add_child(cs)
	root.add_child(pad)
	root.add_child(_driver)
	var cars: Array = str(args.get("car", "civique")).split(",")
	var keep_all := 0.0
	var n := 0
	for id: String in cars:
		for kmh: float in [40.0, 80.0]:
			# [what, radius, how far across, breakaway kind ("" solid)]
			for what: Array in [["lamp post", 0.12, 0.0, "lamp"], ["lamp post", 0.12, 0.55, "lamp"],
					["street light", 0.15, 0.8, "street_light"], ["hydrant", 0.18, 0.75, "hydrant"],
					["sign post", 0.08, 0.3, "post"], ["signal pole", 0.12, 0.8, ""], ["tree", 0.25, 0.6, ""]]:
				var r: Dictionary = await _post_hit(id, kmh, str(what[0]), float(what[1]), float(what[2]), str(what[3]))
				keep_all += float(r["kept"])
				n += 1
			for deg: float in [6.0, 12.0, 25.0]:
				var r: Dictionary = await _wall_hit(id, kmh, deg)
				keep_all += float(r["kept"])
				n += 1
	print("CRASH average speed kept: %.0f%% over %d hits" % [keep_all / n * 100.0, n])
	quit()


func _solid(shape: Shape3D, xf: Transform3D, breakaway := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	if _friction >= 0.0:
		var m := PhysicsMaterial.new()
		m.friction = _friction
		body.physics_material_override = m
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	if breakaway == "post":
		Breakaway.mark_whole(body, breakaway)
	elif breakaway != "":
		Breakaway.mark_shapes(body, breakaway)
	root.add_child(body)
	body.global_transform = xf
	return body


func _spawn(id: String) -> Car:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0))
	car.driver = _driver
	car.ai_controls = _pilot
	car.contact_monitor = true
	car.max_contacts_reported = 8
	if _car_friction >= 0.0:
		car.physics_material_override.friction = _car_friction
	return car


## Runs the car up to `kmh` and on into whatever's ahead; returns what the
## hit did: {kept (share of the speed a second on), swing (deg), spun, over}.
func _drive_in(car: Car, kmh: float, label: String) -> Dictionary:
	for i in 30:
		await physics_frame
	car.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	var hit := false
	var v0 := 0.0
	var yaw0 := 0.0
	var t := 0.0
	var max_spin := 0.0
	var worst_tilt := 0.0
	var frames := 0
	var knocked_before := Breakaway.knocked
	var last_v := 0.0
	var last_yaw := 0.0
	while frames < 60 * 20:
		await physics_frame
		frames += 1
		if not hit:
			for b in car.get_colliding_bodies():
				if b is StaticBody3D and (b as StaticBody3D).collision_layer & Layers.SOLID:
					hit = true
			if Breakaway.knocked > _knocked:
				_knocked = Breakaway.knocked
				hit = true
			if hit:
				v0 = last_v # the speed just before the hit
				yaw0 = last_yaw
			last_v = car.linear_velocity.length()
			last_yaw = car.global_basis.get_euler().y
		if not hit:
			_pilot.throttle = clampf((kmh - car.speed * 3.6) * 0.3, 0.0, 1.0)
			_pilot.steer = clampf(car.global_position.x * -0.5 + car.angular_velocity.y * -0.3, -0.3, 0.3) if car.global_position.z > -40.0 else 0.0
			continue
		_pilot.throttle = 0.0
		_pilot.steer = 0.0
		t += 1.0 / 60.0
		max_spin = maxf(max_spin, absf(car.angular_velocity.y))
		worst_tilt = maxf(worst_tilt, 1.0 - car.global_basis.y.dot(Vector3.UP))
		if t >= 1.0:
			break
	if not hit:
		print("CRASH %s %s at %.0f: missed it (at %s, %.1f km/h)" % [car.model_id, label, kmh, car.global_position, car.speed * 3.6])
		return {"kept": 1.0}
	var v1 := car.linear_velocity
	var fwd := -car.global_basis.z
	var kept := v1.length() / maxf(v0, 0.1)
	var swing := rad_to_deg(absf(angle_difference(yaw0, car.global_basis.get_euler().y)))
	var over := car.global_basis.y.dot(Vector3.UP) < 0.35
	var note := "on its roof" if over else ("spun" if swing > 60.0 else ("stopped dead" if kept < 0.15 else ""))
	if Breakaway.knocked > knocked_before:
		note += " (knocked it over)"
	print("CRASH %s %-30s at %3.0f km/h: kept %3.0f%% of its speed, swung %3.0f deg, spin up to %3.0f deg/s, tilt %2.0f deg %s" % [
		car.model_id, label, kmh, kept * 100.0, swing, rad_to_deg(max_spin), rad_to_deg(acos(clampf(1.0 - worst_tilt, -1.0, 1.0))), note])
	return {"kept": kept, "swing": swing, "over": over, "along": v1.dot(fwd)}


func _post_hit(id: String, kmh: float, what: String, radius: float, offset: float, breakaway: String) -> Dictionary:
	var car := _spawn(id)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0
	var half := float(car.shape.get("width", 1.8)) * 0.5
	# offset: 0 dead centre, 1 at the car's side (the corner just clips it).
	var post := _solid(shape, Transform3D(Basis.IDENTITY, Vector3(offset * half, 2.0, -kmh / 3.6 * 3.0 - 10.0)), breakaway)
	var r: Dictionary = await _drive_in(car, kmh, "%s, %s" % [what, "dead centre" if offset == 0.0 else "%.0f%% across" % (offset * 100.0)])
	car.queue_free()
	post.queue_free()
	await physics_frame
	return r


func _wall_hit(id: String, kmh: float, deg: float) -> Dictionary:
	var car := _spawn(id)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 3.0, 60.0)
	var d := -kmh / 3.6 * 3.0 - 10.0
	# A wall on the right, angled `deg` in across the car's path, its near
	# end meeting the path at d.
	var a := deg_to_rad(deg)
	var dir := Vector3(-sin(a), 0, -cos(a)) # along the wall, away from the car
	# Its near end starts well out to the side, so the car meets its face,
	# not its end.
	var start := Vector3(2.2, 1.5, d)
	var xf := Transform3D(Basis(Vector3.UP, a), start + dir * 30.0)
	var wall := _solid(shape, xf)
	var r: Dictionary = await _drive_in(car, kmh, "wall at %.0f deg" % deg)
	car.queue_free()
	wall.queue_free()
	await physics_frame
	return r

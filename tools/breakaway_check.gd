extends SceneTree
## Checks knocking things over (Breakaway) on a flat pad:
##   - a car at speed knocks a lamp post over and carries on
##   - a second car right behind it (bumper to bumper, racing) goes straight
##     through where the post stood, without a knock
##   - once it's down, what the police driver looks with (CarAutopilot's
##     rays and its car-wide sweep: SOLID) sees nothing there, so a chase
##     follows you through the gap
##   - the fallen post doesn't stop a car either
##   - below Breakaway.MIN_KMH a post is solid (nosing up to one parking)
##
##   godot --headless --path . --script res://tools/breakaway_check.gd
##
## Exits non-zero on failure.

var _fails := 0
var _checks := 0
var _driver := Node3D.new()


class Pilot:
	extends RefCounted
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok    " if ok else "FAIL  ") + what)


func _run() -> void:
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
	await _bumper_to_bumper()
	await _too_slow()
	print("%d of %d checks passed" % [_checks - _fails, _checks])
	quit(1 if _fails > 0 else 0)


func _post(at: Vector3) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = 4.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at + Vector3(0, 2.0, 0)
	body.add_child(cs)
	Breakaway.mark_shapes(body, "lamp")
	root.add_child(body)
	return cs


func _car(at: Vector3, pilot: Pilot) -> Car:
	var car := Car.new()
	car.model_id = "civique"
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, at)
	car.driver = _driver
	car.ai_controls = pilot
	return car


func _bumper_to_bumper() -> void:
	var post := _post(Vector3(0, 0, -120))
	var lead_p := Pilot.new()
	var tail_p := Pilot.new()
	var lead := _car(Vector3(0, 0.4, 0), lead_p)
	# Right behind: the follower's nose 8 m off the leader's back (under
	# half a second at 80 km/h). Any closer and it runs into the leader,
	# who loses a slice of speed taking the post down: that's a real
	# shunt, not the post.
	var gap := float(lead.shape["length"]) + 8.0
	var tail := _car(Vector3(0, 0.4, gap), tail_p)
	for i in 30:
		await physics_frame
	var kmh := 80.0
	lead.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	tail.linear_velocity = Vector3(0, 0, -kmh / 3.6)
	var knocked0 := Breakaway.knocked
	var tail_before := 0.0
	var tail_after := 0.0
	var tail_jolt := 0.0
	var last_v := tail.linear_velocity
	var passed := false
	for i in 60 * 12:
		await physics_frame
		# Both held at 80 km/h, nose to tail, straight down the line.
		for c: Array in [[lead, lead_p], [tail, tail_p]]:
			var car: Car = c[0]
			var p: Pilot = c[1]
			p.throttle = clampf((kmh - car.speed * 3.6) * 0.3, 0.0, 1.0)
			p.steer = clampf(-car.global_position.x * 0.4 - car.angular_velocity.y * 0.3, -0.3, 0.3)
		var dv := (tail.linear_velocity - last_v).length()
		last_v = tail.linear_velocity
		var tz := tail.global_position.z
		if tz > -112.0:
			tail_before = tail.speed * 3.6
		elif tz < -112.0 and tz > -130.0:
			tail_jolt = maxf(tail_jolt, dv)
		elif tz <= -130.0 and not passed:
			passed = true
			tail_after = tail.speed * 3.6
		if passed:
			break
	_check(Breakaway.knocked > knocked0, "the leader knocks the lamp post over")
	_check(post.disabled, "the post's collision is off once it's down")
	_check(passed, "the car right behind gets past where it stood")
	_check(tail_after > tail_before * 0.9, "the car right behind keeps its speed through the gap (%.0f -> %.0f km/h)" % [tail_before, tail_after])
	_check(tail_jolt < 2.0, "the car right behind isn't knocked by the post or the fallen post (biggest jolt %.2f m/s in a step)" % tail_jolt)
	_check(Breakaway.knocked == knocked0 + 1, "the post goes down once, not again for the second car")
	# What the police driver sees: a ray and a car-wide sweep at the spot.
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-5, 1.0, -120), Vector3(5, 1.0, -120), Layers.SOLID)
	_check(space.intersect_ray(q).is_empty(), "a police driver's ray across the spot finds nothing")
	var sweep := PhysicsShapeQueryParameters3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(1.9, 1.2, 4.5)
	sweep.shape = sb
	sweep.collision_mask = Layers.SOLID
	sweep.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -120))
	_check(space.intersect_shape(sweep, 4).is_empty(), "a police driver's car-wide sweep through the spot finds it clear")
	lead.queue_free()
	tail.queue_free()
	await physics_frame


func _too_slow() -> void:
	var post := _post(Vector3(10, 0, -40))
	var p := Pilot.new()
	var car := _car(Vector3(10, 0.4, 0), p)
	for i in 30:
		await physics_frame
	var knocked0 := Breakaway.knocked
	var stopped_at := INF
	for i in 60 * 12:
		await physics_frame
		p.throttle = clampf((10.0 - car.speed * 3.6) * 0.3, 0.0, 1.0)
		p.steer = clampf(-(car.global_position.x - 10.0) * 0.4, -0.3, 0.3)
		if car.global_position.z < -36.0 and car.speed < 0.3:
			stopped_at = car.global_position.z
			break
	_check(Breakaway.knocked == knocked0 and not post.disabled, "at 10 km/h a car just bumps the post: it stays up")
	_check(stopped_at > -40.0, "and the car stops against it")
	car.queue_free()
	await physics_frame

extends SceneTree
## Drives the working vehicles on a flat test pad with scripted inputs and
## prints how they behave, so changes to the truck physics can be checked:
##
##   godot --headless --path . --script res://tools/truck_test.gd -- [--only=drive,couple,load,rollback,forklift]
##
##   drive     each truck alone: settling, 0-60, top speed, braking, cornering
##   couple    a tractor backs under a trailer and the fifth wheel locks
##   load      a loaded rig: pulling, braking, a lane change, how far loose
##             and strapped pallets slide when it brakes hard
##   rollback  the tow truck's deck goes down, the winch pulls a car up,
##             it's strapped, the deck comes up, and the truck drives and brakes
##   forklift  forks into a pallet, lift, back out, set it down on a trailer
## One "TRUCKTEST" line per result.

var _pad: StaticBody3D
var _driver := Node3D.new()
var _cam := Camera3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var only: Array = str(args.get("only", "drive,couple,load,rollback,forklift")).split(",")
	_build_pad()
	root.add_child(_driver)
	root.add_child(_cam)
	_cam.current = true
	if "drive" in only:
		for id: String in ["hauler", "rollback", "forklift"]:
			await _drive_test(id)
		await _trailer_settle()
	if "couple" in only:
		await _couple_test()
	if "load" in only:
		await _load_test(false)
		await _load_test(true)
		await _jackknife_test()
	if "rollback" in only:
		await _rollback_test()
	if "forklift" in only:
		await _forklift_test()
	quit()


func _build_pad() -> void:
	_pad = StaticBody3D.new()
	_pad.collision_layer = Layers.GROUND
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(600, 2, 6000)
	var cs := CollisionShape3D.new()
	cs.shape = floor_shape
	cs.position = Vector3(0, -1, -2900)
	_pad.add_child(cs)
	root.add_child(_pad)


func _spawn(id: String, at: Vector3, yaw := 0.0) -> Car:
	var car := Car.new()
	car.model_id = id
	car.paint = Color.from_string(str(CarModels.get_model(id)["colours"][0]), Color.WHITE)
	root.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	return car


func _cargo(kind: String, at: Vector3, yaw := 0.0) -> Cargo:
	var c := Cargo.new()
	c.kind = kind
	root.add_child(c)
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	return c


func _hold(action: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for a in ["accelerate", "brake_reverse", "steer_left", "steer_right", "handbrake", "work_up", "work_down", "aux_in", "aux_out"]:
		Input.action_release(a)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clear() -> void:
	_release_all()
	for n in root.get_children():
		if n is Car or n is Cargo:
			n.queue_free()
	await physics_frame
	await physics_frame


## Keep the camera near a vehicle so nothing freezes as "far away".
func _follow(car: Car) -> void:
	_cam.global_position = car.global_position + Vector3(0, 20, 25)


func _bad(car: Car) -> bool:
	var p := car.global_position
	return not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)) or p.y < -5.0 or p.y > 50.0


# --- each truck alone ------------------------------------------------------------------------

func _drive_test(id: String) -> void:
	var car := _spawn(id, Vector3(0, 0.3, 0))
	car.driver = _driver
	var max_bob := 0.0
	for i in 180:
		_follow(car)
		await physics_frame
		if i > 90:
			max_bob = maxf(max_bob, absf(car.linear_velocity.y))
	print("TRUCKTEST %s settle: body at %.3f m, still moving %.3f m/s after 1.5 s, wheels down %d of %d, pitch %.1f deg" % [
		id, car.global_position.y, max_bob, car.wheels_down, car._n - _legs(car), rad_to_deg(car.global_basis.get_euler().x)])
	_hold("accelerate", true)
	var t := 0.0
	var t60 := -1.0
	var top := 0.0
	var limit := 70.0 if id != "forklift" else 15.0
	while t < limit:
		_follow(car)
		await physics_frame
		t += 1.0 / 60.0
		var kmh := car.speed * 3.6
		top = maxf(top, kmh)
		if t60 < 0.0 and kmh >= 60.0:
			t60 = t
	print("TRUCKTEST %s 0-60 km/h: %s, top speed %.0f km/h (gear %d, %.0f rpm)" % [id, ("%.1f s" % t60) if t60 > 0.0 else "never", top, car.gear, car.rpm])
	_release_all()
	_hold("brake_reverse", true)
	var from := minf(60.0, top - 2.0)
	while car.speed * 3.6 > from + 1.0:
		_follow(car)
		await physics_frame
	var start := car.global_position
	var dive := 0.0
	while car.speed > 0.3:
		_follow(car)
		await physics_frame
		dive = maxf(dive, absf(car.global_basis.get_euler().x))
	print("TRUCKTEST %s braking %.0f-0: %.1f m, most dive %.1f deg" % [id, from, start.distance_to(car.global_position), rad_to_deg(dive)])
	_release_all()
	# Cornering at a steady speed with full lock.
	var corner := 40.0 if id != "forklift" else 10.0
	_hold("accelerate", true)
	while car.speed * 3.6 < corner:
		_follow(car)
		await physics_frame
	_hold("steer_left", true)
	var peak := 0.0
	var roll := 0.0
	var min_wheels := car.wheels_down
	for i in 240:
		_follow(car)
		await physics_frame
		_hold("accelerate", car.speed * 3.6 < corner, 0.6)
		peak = maxf(peak, absf(car.speed * car.angular_velocity.y) / 9.81)
		roll = maxf(roll, absf(car.global_basis.get_euler().z))
		min_wheels = mini(min_wheels, car.wheels_down)
	var radius := absf(car.speed / maxf(0.01, car.angular_velocity.y))
	print("TRUCKTEST %s full lock at %.0f km/h: %.2f g, turning circle %.1f m across, most lean %.1f deg, fewest wheels down %d%s" % [
		id, corner, peak, radius * 2.0, rad_to_deg(roll), min_wheels, "  ROLLED" if car.global_basis.y.y < 0.5 else ""])
	_release_all()
	car.queue_free()
	await physics_frame
	await physics_frame


func _legs(car: Car) -> int:
	var n := 0
	for b in car._is_leg:
		if b:
			n += 1
	return n


func _trailer_settle() -> void:
	var t := _spawn("flatbed_trailer", Vector3(0, 0.3, 0))
	for i in 180:
		_follow(t)
		await physics_frame
	var kp: Vector3 = t.model_point("kingpin")
	print("TRUCKTEST flatbed_trailer on its legs: kingpin %.3f m up, deck top %.3f m at the front, %.3f m at the back, moving %.3f m/s, wheels down %d" % [
		kp.y, (t.global_transform * Vector3(0, 1.5, -7.0)).y, (t.global_transform * Vector3(0, 1.5, 7.0)).y, t.linear_velocity.length(), t.wheels_down])
	await _clear()


# --- coupling ----------------------------------------------------------------------------------

## A trailer facing -z with a tractor in front of it, ready to back under
## (off to one side by `side` metres, as a driver would be).
func _rig(gap := 2.5, side := 0.0) -> Array:
	var trailer := _spawn("flatbed_trailer", Vector3(side, 0.3, 0))
	# The tractor's fifth wheel (2.2 m behind its middle) `gap` in front of the kingpin (6.4 m ahead of the trailer's).
	var tractor := _spawn("hauler", Vector3(0, 0.3, -6.4 - 2.2 - gap))
	for i in 90:
		_follow(tractor)
		await physics_frame
	return [tractor, trailer]


func _couple_test() -> void:
	var r := await _rig(2.5, 0.25)
	var tractor: Car = r[0]
	var trailer: Car = r[1]
	tractor.driver = _driver
	var t := 0.0
	var off_x := 0.0
	_hold("brake_reverse", true, 0.35)
	while tractor.towing == null and t < 20.0:
		off_x = (tractor.global_transform.basis.inverse() * ((trailer.model_point("kingpin") as Vector3) - (tractor.model_point("hitch") as Vector3))).x
		_follow(tractor)
		await physics_frame
		t += 1.0 / 60.0
		_hold("brake_reverse", tractor.speed > -1.0, 0.35)
	_release_all()
	_hold("brake_reverse", true)
	await _frames(60)
	_release_all()
	var hp: Vector3 = tractor.model_point("hitch")
	var kp: Vector3 = trailer.model_point("kingpin")
	print("TRUCKTEST couple: backing in 0.25 m off to the side, %s after %.1f s reversing (the throat had it %.3f m off as the jaws closed), kingpin %.3f m from the fifth wheel, legs %s" % [
		"locked on" if tractor.towing == trailer else "DID NOT COUPLE", t, off_x, hp.distance_to(kp), "up" if trailer._legs_up > 0.3 else "down"])
	# Pull away empty and uncouple again.
	_hold("accelerate", true)
	for i in 300:
		_follow(tractor)
		await physics_frame
	_release_all()
	print("TRUCKTEST couple: pulled away to %.0f km/h, trailer %.1f m behind (should stay 8.6), hitch error %.3f m" % [
		tractor.speed * 3.6, trailer.global_position.distance_to(tractor.global_position), (tractor.model_point("hitch") as Vector3).distance_to(trailer.model_point("kingpin"))])
	_hold("brake_reverse", true)
	while tractor.speed > 0.2:
		_follow(tractor)
		await physics_frame
	_release_all()
	var msg := tractor.hitch_action()
	var left := trailer.global_position
	_hold("accelerate", true)
	for i in 200:
		_follow(tractor)
		await physics_frame
	_release_all()
	print("TRUCKTEST couple: \"%s\", drove off %.1f m, the trailer stayed (moved %.2f m, legs down: %s, nose %.2f m up)" % [
		msg, tractor.global_position.distance_to(trailer.global_position) - 8.6, trailer.global_position.distance_to(left), str(trailer._legs_up < 0.01), (trailer.model_point("kingpin") as Vector3).y])
	await _clear()


# --- a loaded rig ----------------------------------------------------------------------------

func _load_test(strapped: bool) -> void:
	var r := await _rig(0.0)
	var tractor: Car = r[0]
	var trailer: Car = r[1]
	Coupling.couple(tractor, trailer)
	# Ten pallets of bricks down the deck, two abreast at the front.
	var pallets: Array[Cargo] = []
	for i in 5:
		for s: float in [-0.62, 0.62]:
			pallets.append(_cargo("pallet_bricks", trailer.global_transform * Vector3(s, 1.52, -5.6 + i * 1.6)))
	for i in 120:
		_follow(tractor)
		await physics_frame
	if strapped:
		print("TRUCKTEST load: strapped %d loads" % trailer.tie_downs.strap_all())
	var label := "strapped" if strapped else "loose"
	var rel0: Array[Transform3D] = []
	for p in pallets:
		rel0.append(trailer.global_transform.affine_inverse() * p.global_transform)
	tractor.driver = _driver
	_hold("accelerate", true)
	var t := 0.0
	var t50 := -1.0
	while t < 60.0 and tractor.speed * 3.6 < 70.0:
		_follow(tractor)
		await physics_frame
		t += 1.0 / 60.0
		if t50 < 0.0 and tractor.speed * 3.6 >= 50.0:
			t50 = t
	print("TRUCKTEST load (%s, %.1f t on the deck): 0-50 km/h %.1f s, 0-70 %.1f s" % [label, pallets.size() * 1.45 + 0.0, t50, t])
	# A lane change at 70.
	var max_art := 0.0
	var max_gap := 0.0
	for phase: String in ["steer_left", "steer_right", ""]:
		_release_all()
		if phase != "":
			_hold(phase, true, 0.35)
		for i in 60:
			_follow(tractor)
			await physics_frame
			_hold("accelerate", tractor.speed * 3.6 < 70.0, 0.5)
			max_art = maxf(max_art, _articulation(tractor, trailer))
			max_gap = maxf(max_gap, (tractor.model_point("hitch") as Vector3).distance_to(trailer.model_point("kingpin")))
	print("TRUCKTEST load (%s) lane change at 70: trailer swung %.1f deg, hitch error up to %.3f m, %s" % [
		label, max_art, max_gap, "upright" if tractor.global_basis.y.y > 0.9 and trailer.global_basis.y.y > 0.9 else "ROLLED"])
	# Hard stop.
	_release_all()
	_hold("brake_reverse", true)
	var start := tractor.global_position
	var peak_g := 0.0
	var last := tractor.speed
	while tractor.speed > 0.3:
		_follow(tractor)
		await physics_frame
		peak_g = maxf(peak_g, (last - tractor.speed) * 60.0 / 9.81)
		last = tractor.speed
		max_art = maxf(max_art, _articulation(tractor, trailer))
	for i in 60:
		_follow(tractor)
		await physics_frame
	var slid := 0.0
	var fell := 0
	for i in pallets.size():
		var rel := trailer.global_transform.affine_inverse() * pallets[i].global_transform
		slid = maxf(slid, rel.origin.distance_to(rel0[i].origin))
		if rel.origin.y < 1.0 or absf(rel.origin.x) > 1.4 or absf(rel.origin.z) > 7.4:
			fell += 1
	print("TRUCKTEST load (%s) braking from 70: %.1f m, peak %.2f g, trailer swung %.1f deg; pallets slid up to %.2f m, %d off the deck" % [
		label, start.distance_to(tractor.global_position), peak_g, max_art, slid, fell])
	await _clear()


func _articulation(a: Car, b: Car) -> float:
	var fa := Vector2(-a.global_basis.z.x, -a.global_basis.z.z).normalized()
	var fb := Vector2(-b.global_basis.z.x, -b.global_basis.z.z).normalized()
	return rad_to_deg(absf(fa.angle_to(fb)))


func _jackknife_test() -> void:
	var r := await _rig(0.0)
	var tractor: Car = r[0]
	var trailer: Car = r[1]
	Coupling.couple(tractor, trailer)
	tractor.driver = _driver
	_hold("accelerate", true)
	while tractor.speed * 3.6 < 60.0:
		_follow(tractor)
		await physics_frame
	_release_all()
	# Brake hard mid-corner with the trailer empty.
	_hold("steer_left", true, 0.5)
	for i in 30:
		_follow(tractor)
		await physics_frame
	_hold("brake_reverse", true)
	var max_art := 0.0
	var bad := false
	for i in 400:
		_follow(tractor)
		await physics_frame
		max_art = maxf(max_art, _articulation(tractor, trailer))
		bad = bad or _bad(tractor) or _bad(trailer)
	print("TRUCKTEST jackknife (empty, braking hard in a 60 km/h turn): trailer swung up to %.1f deg, %s" % [max_art, "BLEW UP" if bad else "stable"])
	await _clear()


# --- tow truck --------------------------------------------------------------------------------

func _rollback_test() -> void:
	var truck := _spawn("rollback", Vector3(0, 0.3, 0))
	var tool := truck.tool as RollbackTool
	truck.driver = _driver
	for i in 60:
		_follow(truck)
		await physics_frame
	# Deck all the way down.
	_hold("work_down", true)
	var t := 0.0
	while tool.deck < 1.0 and t < 20.0:
		_follow(truck)
		await physics_frame
		t += 1.0 / 60.0
	_release_all()
	var tail := truck.global_transform * (tool.deck_xform(1.0) * Vector3(0, 1.1, 5.6))
	print("TRUCKTEST rollback deck down in %.1f s: tail %.2f m off the road, %.1f m behind the truck's middle, truck rear lifted %.3f m" % [
		t, tail.y, tail.z - truck.global_position.z, truck.global_position.y])
	# A car behind, facing the truck, nose 2 m off the tail.
	var car := _spawn("civique", Vector3(0, 0.3, tail.z + 2.0 + 2.36), 0.0)
	for i in 90:
		_follow(truck)
		await physics_frame
	var msg := truck.hitch_action()
	_hold("aux_in", true)
	t = 0.0
	var peak := 0.0
	while t < 60.0:
		_follow(truck)
		await physics_frame
		t += 1.0 / 60.0
		peak = maxf(peak, tool.tension)
		# Stop reeling once the car's nose is near the headboard.
		var nose := car.global_transform * Vector3(0, 0.4, -2.3)
		if nose.distance_to(tool.winch_point()) < 1.1:
			break
	_release_all()
	var on_deck := car.wheels_down
	print("TRUCKTEST rollback winch: \"%s\"; pulled the car up in %.1f s, most tension %.0f kN, car %.2f m up, wheels down %d, car pitched %.1f deg" % [
		msg, t, peak / 1000.0, car.global_position.y, on_deck, rad_to_deg(car.global_basis.get_euler().x)])
	# Strap it, deck up, unhook.
	for i in 30:
		await physics_frame
	var strapped := truck.tie_downs.strap_all()
	_hold("work_up", true)
	t = 0.0
	while tool.deck > 0.0 and t < 20.0:
		_follow(truck)
		await physics_frame
		t += 1.0 / 60.0
	_release_all()
	for i in 60:
		_follow(truck)
		await physics_frame
	var unhook := truck.hitch_action()
	var rel0 := truck.global_transform.affine_inverse() * car.global_transform
	print("TRUCKTEST rollback deck up in %.1f s with %d strapped; \"%s\"; car sits %.2f m up on the deck (%.2f m above the truck's frame), truck sags %.3f m at the back" % [
		t, strapped, unhook, car.global_position.y, rel0.origin.y, -(truck.global_transform * Vector3(0, 0, 3.0)).y])
	# Drive off and brake hard.
	_hold("accelerate", true)
	while truck.speed * 3.6 < 60.0:
		_follow(truck)
		await physics_frame
	_release_all()
	_hold("brake_reverse", true)
	var start := truck.global_position
	while truck.speed > 0.3:
		_follow(truck)
		await physics_frame
	for i in 30:
		await physics_frame
	var rel := truck.global_transform.affine_inverse() * car.global_transform
	print("TRUCKTEST rollback loaded braking 60-0: %.1f m; the car moved %.2f m on the deck, straps %s" % [
		start.distance_to(truck.global_position), rel.origin.distance_to(rel0.origin), "held" if not truck.tie_downs.is_empty() else "SNAPPED"])
	await _clear()


# --- forklift ------------------------------------------------------------------------------------

func _forklift_test() -> void:
	var fl := _spawn("forklift", Vector3(0, 0.3, 0))
	var tool := fl.tool as ForkliftTool
	# A pallet of boxes 2 m ahead of the fork tips, its openings facing the forklift.
	var pallet := _cargo("pallet_boxes", Vector3(0, 0.02, -2.12 - 2.0 - 0.6))
	for i in 90:
		_follow(fl)
		await physics_frame
	fl.driver = _driver
	# Creep forward until the backrest meets the pallet.
	_hold("accelerate", true, 0.25)
	var t := 0.0
	while t < 12.0:
		_follow(fl)
		await physics_frame
		t += 1.0 / 60.0
		_hold("accelerate", fl.speed < 1.0, 0.25)
		var back := fl.global_transform * Vector3(0, 0.3, -1.06)
		if pallet.global_position.z > back.z - 0.65:
			break
	_release_all()
	_hold("brake_reverse", true)
	for i in 30:
		await physics_frame
	_release_all()
	var depth := (fl.global_transform * Vector3(0, 0, -1.06)).z - pallet.global_position.z
	# Lift 0.3 m and tilt back.
	_hold("work_up", true)
	_hold("aux_in", true)
	t = 0.0
	while tool.lift < 0.3:
		_follow(fl)
		await physics_frame
		t += 1.0 / 60.0
	_release_all()
	for i in 60:
		_follow(fl)
		await physics_frame
	print("TRUCKTEST forklift: forks in %.2f m (pallet middle in front of the backrest), lifted 0.3 m in %.1f s; pallet now %.2f m up, rear wheels %s" % [
		depth, t, pallet.global_position.y, "down" if fl._hits[2] != null else "LIGHT"])
	# Back up 5 m with it.
	var p0 := pallet.global_position
	_hold("brake_reverse", true, 0.4)
	var start := fl.global_position
	while fl.global_position.distance_to(start) < 5.0:
		_follow(fl)
		await physics_frame
	_release_all()
	_hold("accelerate", true)
	for i in 40:
		await physics_frame
	_release_all()
	for i in 60:
		await physics_frame
	var carried := pallet.global_position.distance_to(p0)
	var on_forks := (fl.global_transform.affine_inverse() * pallet.global_position)
	print("TRUCKTEST forklift carried the pallet %.2f m backing up 5 m; it sits %.2f m up, %.2f m ahead of the forklift's middle (still on the forks: %s)" % [
		carried, pallet.global_position.y, -on_forks.z, str(on_forks.y > 0.2 and on_forks.z < -1.0)])
	# Heavy: a pallet of bricks 3 m up.
	_hold("work_up", true)
	while tool.lift < 2.8:
		_follow(fl)
		await physics_frame
	_release_all()
	for i in 90:
		_follow(fl)
		await physics_frame
	print("TRUCKTEST forklift with 520 kg at 2.8 m: pallet %.2f m up, front tipped %.1f deg, %s" % [
		pallet.global_position.y, rad_to_deg(fl.global_basis.get_euler().x), "steady" if fl.global_basis.y.y > 0.95 else "TIPPING"])
	# Down low again, and now the load is far over what it's rated for.
	_hold("work_down", true)
	while tool.lift > 0.3:
		_follow(fl)
		await physics_frame
	_release_all()
	for i in 60:
		await physics_frame
	for kg: float in [2300.0, 4500.0]:
		# Load it up over a second, the way a real load comes onto the forks.
		var from := pallet.mass
		for i in 60:
			pallet.mass = lerpf(from, kg, (i + 1) / 60.0)
			_follow(fl)
			await physics_frame
		var light := 0
		var worst := 0.0
		for i in 120:
			_follow(fl)
			await physics_frame
			if fl._hits[2] == null and fl._hits[3] == null:
				light += 1
			worst = minf(worst, fl.global_basis.get_euler().x)
		print("TRUCKTEST forklift with %.0f kg (rated 2300) at 0.3 m: nosed down up to %.1f deg, rear wheels off the ground %.1f s of 2, %s" % [
			kg, rad_to_deg(-worst), light / 60.0, "steady" if rad_to_deg(-worst) < 3.0 else "TIPPED FORWARD onto its forks"])
	await _clear()

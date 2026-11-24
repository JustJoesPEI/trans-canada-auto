extends SceneTree
## Checks the paint piece (scripts/paint) on a bare test pad, headless:
##
##   godot --headless --path . --script res://tools/paint_check.gd
##
## Fires at a car, a person and the ground through PaintShots and checks:
## hits land and are reported; a car's coverage rises; police paint gums it
## up (2/3 power from 80%, stalled at 100%, and a stalled car won't drive)
## and the car wash clears it; windscreen hits show and the wipers clear
## them; 3 hits put a person out (a head hit counts 2) and hits wear off;
## the other weapons work through fire() with their own numbers and
## splash; the world splat pool keeps to its cap; fresh paint is stamped
## for the drips, which run on walls and not on the flat or off an edge.
## One "PAINT" line per
## check; exits non-zero with "PAINT FAIL" lines if any fail.

var _failures := 0
var _hits: Array[Dictionary] = []
var _shots: PaintShots
var _shooter: Node3D
var _police: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PAINT ok   %s" % what)
	else:
		_failures += 1
		print("PAINT FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Wait until nothing's in flight (or a few seconds pass).
func _land() -> void:
	for i in 300:
		await physics_frame
		if _shots.in_flight() == 0:
			return


func _run() -> void:
	# The pad: ground, and a wall to shoot at.
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(200, 2, 200)
	floor_shape.position = Vector3(0, -1, 0)
	pad.add_child(floor_shape)
	root.add_child(pad)
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.SOLID
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	(wall_shape.shape as BoxShape3D).size = Vector3(20, 6, 1)
	wall.add_child(wall_shape)
	root.add_child(wall)
	wall.global_position = Vector3(0, 3, 40)

	_shots = PaintShots.new()
	root.add_child(_shots)
	_shots.hit.connect(func(info: Dictionary) -> void: _hits.append(info))
	_shooter = Node3D.new()
	_shooter.name = "Shooter"
	root.add_child(_shooter)
	_police = Node3D.new()
	_police.name = "Officer"
	_police.add_to_group("police")
	root.add_child(_police)

	var car := Car.new()
	car.model_id = "civique"
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -10))
	var person: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	person.input_enabled = false
	root.add_child(person)
	person.place(Transform3D(Basis.IDENTITY, Vector3(14, 0, 0)))
	await _frames(90)

	await _check_car(car)
	await _check_windscreen(car)
	await _check_person(person)
	await _check_weapons(car, person)
	await _check_world()
	await _check_drips(car)
	await _check_hip_and_reload()

	if _failures > 0:
		print("PAINT %d check(s) failed" % _failures)
		quit(1)
	else:
		print("PAINT all checks passed")
		quit(0)


func _check_car(car: Car) -> void:
	var at := car.global_position + Vector3(0, 0.5, 0)
	_hits.clear()
	_shots.fire(Vector3(0, 1.0, 0), at - Vector3(0, 1.0, 0), _shooter, PaintWeapons.ISLANDER, 0.0)
	await _land()
	var on_car := _hits.filter(func(h: Dictionary) -> bool: return h["kind"] == "car" and h["target"] == car)
	_check(on_car.size() == 1, "a ball fired at a car hits it (%d car hits of %d)" % [on_car.size(), _hits.size()])
	var pc := car.get_node_or_null("PaintCoverage") as PaintCoverage
	_check(pc != null and pc.coverage > 0.0, "the car's coverage rises (%.3f)" % (pc.coverage if pc != null else -1.0))
	_check(pc != null and pc.hits.size() == 1 and car.body_mesh.material_overlay != null, "the hit is kept and drawn over the body")
	_check(car.power_factor == 1.0 and not car.stalled, "player paint only paints")

	# Police paint, from all round, until it stalls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var gummed_power := -1.0
	var spotted := 1.0
	var fired := 0
	while not car.stalled and fired < 800:
		for k in 8:
			var a := rng.randf() * TAU
			var from := car.global_position + Vector3(cos(a) * 8.0, rng.randf_range(0.6, 3.0), sin(a) * 8.0)
			var to := car.global_position + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.3, 1.0), rng.randf_range(-1.8, 1.8))
			_shots.fire(from, to - from, _police, PaintWeapons.ISLANDER, 0.0)
			fired += 1
		await _land()
		if pc.police_coverage >= 0.8 and pc.police_coverage < 0.999:
			gummed_power = maxf(gummed_power, car.power_factor)
		if pc.police_coverage >= 0.5:
			spotted = pc.spotting_factor
	print("PAINT      %d police balls: coverage %.2f, police %.2f" % [fired, pc.coverage, pc.police_coverage])
	_check(is_equal_approx(spotted, 2.0), "50%+ police paint doubles the spotting distance")
	_check(absf(gummed_power - 2.0 / 3.0) < 0.01, "80%%+ police paint cuts the power to 2/3 (%.3f)" % gummed_power)
	_check(car.stalled and car.power_factor == 0.0 and pc.police_coverage >= 0.999, "100% police paint stalls the car")
	_check(pc.hits.size() == PaintCoverage.MAX_HITS, "the car keeps the last 32 hits (%d)" % pc.hits.size())

	# A stalled car doesn't drive.
	var driver := Node3D.new()
	root.add_child(driver)
	car.driver = driver
	Input.action_press("accelerate")
	await _frames(90)
	_check(absf(car.speed) < 0.3, "a stalled car won't drive (%.2f m/s)" % car.speed)
	Input.action_release("accelerate")
	car.driver = null
	driver.queue_free()

	# The car wash.
	pc.clear()
	_check(pc.coverage == 0.0 and not car.stalled and car.power_factor == 1.0 and car.body_mesh.material_overlay == null, "clear() (the car wash) takes it all off")
	await _frames(30)


func _check_windscreen(car: Car) -> void:
	var cab: Dictionary = car.shape["cabin"]
	var mid := Vector3(0.2, lerpf(float(cab["belt"]), float(cab["roof"]), 0.5), lerpf(float(cab["za"]), float(cab["zb"]), 0.5))
	var at := car.global_transform * mid
	var from := at + car.global_basis * Vector3(0, 1.0, -6.0)
	_shots.fire(from, at - from, _shooter, PaintWeapons.ISLANDER, 0.0)
	await _land()
	var pc := PaintCoverage.of(car)
	_check(pc.screen.size() == 1, "a hit on the windscreen smears it (%d)" % pc.screen.size())
	pc.wipe()
	await _frames(int(PaintCoverage.SWEEP_TIME * 2.0 * 60.0) + 10)
	_check(pc.screen.is_empty() and pc.wiper < 0.0, "the wipers clear it in two sweeps")
	pc.clear()


func _check_person(person: PlayerController) -> void:
	var outs: Array[Node] = []
	person.went_out.connect(func(by: Node) -> void: outs.append(by))
	var chest := person.global_position + Vector3(0, 1.1, 0)
	_hits.clear()
	for i in 3:
		_shots.fire(chest + Vector3(0, 0, 8), Vector3(0, 0, -1), _shooter, PaintWeapons.ISLANDER, 0.0)
		await _land()
		if i < 2:
			_check(person.body_paint.hits == i + 1 and not person.is_out(), "hit %d on a person counts (%d)" % [i + 1, person.body_paint.hits])
	_check(person.is_out() and outs.size() == 1 and outs[0] == _shooter, "3 hits and they're out, by the shooter")
	var last: Dictionary = _hits.back() if not _hits.is_empty() else {}
	_check(last.get("kind") == "person" and bool(last.get("out", false)), "the hit that puts them out says so")
	_check(person.body_paint.splats.size() == 3 and person.model.mesh_instance.material_overlay != null, "the splats show on the body")
	_check(person.model.hands_up == 1.0, "their hands go up")
	person.marker.trigger = true
	var before := person.marker.ammo
	person.marker.step(0.1, not person.is_out(), true, 1.0, 0.0, 3.8, chest, chest + Vector3(0, 0, -5))
	person.marker.trigger = false
	_check(person.marker.ammo == before, "out, the marker won't fire")

	person.body_paint.revive()
	_check(not person.is_out() and person.body_paint.hits == 0, "revive() puts them back in")
	var head := person.global_position + Vector3(0, 1.66, 0)
	_shots.fire(head + Vector3(0, 0, 8), Vector3(0, 0, -1), _shooter, PaintWeapons.ISLANDER, 0.0)
	await _land()
	_check(person.body_paint.hits == 2, "a head hit counts 2 (%d)" % person.body_paint.hits)
	await _frames(int(BodyPaint.WEAR_TIME * 60.0) + 20)
	_check(person.body_paint.hits == 1, "one hit wears off after 6 s (%d)" % person.body_paint.hits)
	await _frames(int(BodyPaint.WEAR_TIME * 60.0) + 20)
	_check(person.body_paint.hits == 0, "then the next (%d)" % person.body_paint.hits)
	person.clean_paint()
	_check(person.body_paint.splats.is_empty() and person.model.mesh_instance.material_overlay == null, "clean_paint() takes the paint off")

	# The player's own marker: fires while aiming, the hopper counts down,
	# the rate is capped, and it reloads.
	var m := person.marker
	m.set_weapon(PaintWeapons.ISLANDER)
	var muzzle := person.global_position + Vector3(0, 1.4, -0.5)
	var aim_at := muzzle + Vector3(0, 0, -30)
	var count := [0] # (a lambda can't add to a local, but it can to an array's item)
	m.fired.connect(func() -> void: count[0] += 1)
	m.trigger = true
	for i in 60: # one second held
		m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, aim_at)
	m.trigger = false
	var held: int = count[0]
	_check(held >= 5 and held <= 6, "holding fires 5 a second (%d)" % held)
	count[0] = 0
	for i in 60: # pulling every frame: capped at 8 a second
		m.trigger = i % 2 == 0
		m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, aim_at)
	m.trigger = false
	var shots: int = count[0]
	_check(shots >= 7 and shots <= 9, "fast pulls fire up to 8 a second (%d)" % shots)
	_check(m.ammo == 40 - held - shots, "the hopper counts down (%d left)" % m.ammo)
	m.reload()
	for i in 60:
		m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, aim_at)
	_check(m.ammo < 40 and m.is_reloading(), "a reload takes 1.6 s")
	for i in 40:
		m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, aim_at)
	_check(m.ammo == 40, "and fills the hopper")
	await _land()


func _check_weapons(car: Car, person: PlayerController) -> void:
	person.body_paint.revive()
	# The Farmhand: hits count 2.
	var chest := person.global_position + Vector3(0, 1.1, 0)
	_shots.fire(chest + Vector3(0, 0, 8), Vector3(0, 0, -1), _shooter, PaintWeapons.FARMHAND, 0.0)
	await _land()
	_check(person.body_paint.hits == 2, "a Farmhand hit counts 2 (%d)" % person.body_paint.hits)
	person.body_paint.revive()
	_shots.fire(chest + Vector3(0, 0, 8), Vector3(0, 0, -1), _shooter, PaintWeapons.LOBBYIST, 0.0)
	await _land()
	_check(person.body_paint.hits == 1, "a Lobbyist hit counts 1 (%d)" % person.body_paint.hits)
	person.body_paint.revive()

	# A Jam Jar dropped at their feet: 2 hits when it bursts after 1.5 s.
	_hits.clear()
	var feet := person.global_position + Vector3(1.0, 0.5, 0)
	_shots.fire(feet, Vector3.DOWN, _shooter, PaintWeapons.JAM_JARS, 0.0)
	await _frames(60)
	_check(person.body_paint.hits == 0, "a Jam Jar waits for its fuse")
	await _frames(40)
	_check(person.body_paint.hits == 2, "then it's 2 hits on everyone within 3 m (%d)" % person.body_paint.hits)
	var splashed := _hits.filter(func(h: Dictionary) -> bool: return bool(h["splash"]) and h["kind"] == "person")
	_check(splashed.size() == 1, "and the splash is reported")
	person.body_paint.revive()

	# A Jam Jar by the car: +15% coverage.
	var pc := PaintCoverage.of(car)
	pc.clear()
	_shots.fire(car.global_position + Vector3(2.2, 0.5, 0), Vector3.DOWN, _shooter, PaintWeapons.JAM_JARS, 0.0)
	await _frames(110)
	_check(absf(pc.coverage - 0.15) < 0.01, "a Jam Jar puts 15%% on a car (%.3f)" % pc.coverage)
	pc.clear()
	# Tourist Season, a direct hit: +30%.
	var top := car.global_position + Vector3(0, 1.4, 0)
	_shots.fire(top + Vector3(0, 6, 0), Vector3.DOWN, _shooter, PaintWeapons.TOURIST_SEASON, 0.0)
	await _land()
	_check(absf(pc.coverage - 0.3) < 0.01, "a paint bomb's direct hit puts 30%% on a car (%.3f)" % pc.coverage)
	pc.clear()


func _check_world() -> void:
	var splats := _shots.splats
	var start := splats.count
	_hits.clear()
	for i in 10:
		_shots.fire(Vector3(i - 5.0, 2.0, 30.0), Vector3(0, 0, 1), _shooter, PaintWeapons.ISLANDER, 0.0)
	await _land()
	var world := _hits.filter(func(h: Dictionary) -> bool: return h["kind"] == "world")
	_check(world.size() == 10 and splats.count == start + 10, "balls at a wall leave splats (%d hits, %d splats)" % [world.size(), splats.count - start])
	# On the ground: the splat lies flat, just off it.
	_shots.fire(Vector3(3, 2, 10), Vector3(0, -1, 0.2), _shooter, PaintWeapons.ISLANDER, 0.0)
	await _land()
	var xf := splats.transform_of(splats.newest_slot())
	_check(absf(xf.origin.y - PaintSplats.SURFACE_OFFSET) < 0.002 and xf.basis.z.normalized().dot(Vector3.UP) > 0.999, "a splat on the ground lies flat on it (y %.4f)" % xf.origin.y)
	# Half on, half off the edge of the wall's top: shrunk to fit or skipped.
	var edge_ok := true
	var before := splats.count
	if splats.add(Vector3(9.95, 6.0, 40.0), Vector3.UP, Color.WHITE, 0.3):
		var e := splats.transform_of(splats.newest_slot())
		edge_ok = e.basis.x.length() < 0.3
	_check(edge_ok and splats.count <= before + 1, "a splat over an edge is shrunk or dropped")

	# The cap follows the graphics setting.
	var gfx: Node = root.get_node_or_null("Graphics")
	_check(gfx != null, "the Graphics autoload is there")
	if gfx == null:
		return
	_check(PaintSplats.cap_for_level() == 4000 and splats.cap == 4000, "High holds 4000 (%d)" % splats.cap)
	var old_level: int = gfx.get("level")
	gfx.set("level", 0) # Low
	await _frames(80)
	_check(splats.cap == 800, "Low holds 800 (%d)" % splats.cap)
	for i in 1000:
		splats.add(Vector3(randf_range(-50, 50), 0.0, randf_range(-50, 0)), Vector3.UP, PaintWeapons.COLOURS[i % 12], 0.1)
	_check(splats.count == 800 and splats.multimesh.visible_instance_count <= 800, "the pool keeps to its cap, oldest out first (%d)" % splats.count)
	gfx.set("level", old_level)
	await _frames(80)
	_check(splats.cap == 4000 and splats.count == 800, "back on High, it keeps what it had (%d of %d)" % [splats.count, splats.cap])
	# Twenty minutes on, they're gone (faded out over the last two, in the shader).
	PaintSplats.clock += PaintSplats.LIFE + 1.0
	splats._expire()
	_check(splats.count == 0, "splats go after 20 minutes (%d left)" % splats.count)


## Firing without aiming (hip fire), and the pod swap a reload shows.
func _check_hip_and_reload() -> void:
	var p: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var rig: CameraRig = (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate()
	root.add_child(p)
	root.add_child(rig)
	p.place(Transform3D(Basis.IDENTITY, Vector3(-30, 0, 0)))
	p.camera_rig = rig
	rig.target = p
	rig.snap_to_target()
	p.input_enabled = true
	await _frames(30)
	var count := [0]
	p.marker.fired.connect(func() -> void: count[0] += 1)
	p.marker.set_weapon(PaintWeapons.ISLANDER)
	# Turn the camera away from where the body faces: hip fire turns to it.
	rig.yaw = p.rotation.y + PI * 0.5
	Input.action_press("fire")
	await _frames(20)
	_check(p.hip_firing and not p.aiming, "Fire without Aim fires from the hip")
	_check(count[0] >= 1, "a hip shot goes on the first pull (%d)" % count[0])
	await _frames(40)
	_check(absf(angle_difference(p.rotation.y, rig.yaw)) < deg_to_rad(15.0), "from the hip the body turns to the crosshair (%.0f deg off)" % rad_to_deg(absf(angle_difference(p.rotation.y, rig.yaw))))
	_check(p.aim_amount < 0.05, "the camera stays back: no shoulder aim from the hip")
	Input.action_release("fire")
	await _frames(int(p.hip_hold * 60.0) + 10)
	_check(not p.hip_firing, "hip fire lets go %.1f s after the last pull" % p.hip_hold)
	# The pod swap: Reload with the marker down shows it, the pod rides in
	# the left hand partway through, and it's gone once the hopper's full.
	p.marker.ammo = 10
	Input.action_press("reload")
	await _frames(2)
	Input.action_release("reload")
	_check(p.marker.is_visible_reload() and p.model.reload >= 0.0, "Reload shows the pod swap")
	var saw_pod := false
	var pod_near_hopper := false
	for i in 110:
		await physics_frame
		await process_frame
		var pod := p.model.skeleton.get_node_or_null("PaintPod") as Node3D
		var mk := p.model.skeleton.get_node_or_null("Marker") as Node3D
		if pod != null and pod.visible:
			saw_pod = true
			if mk != null and p.model.reload > 0.6 and p.model.reload < 0.8:
				var mouth := mk.global_transform * MarkerModel.HOPPER_TOP
				pod_near_hopper = pod_near_hopper or pod.global_position.distance_to(mouth) < 0.25
	_check(saw_pod, "the pod is in the hand during the reload")
	_check(pod_near_hopper, "and tipped in over the hopper")
	await _frames(20)
	var pod := p.model.skeleton.get_node_or_null("PaintPod") as Node3D
	_check(p.marker.ammo == 40 and p.model.reload < 0.0 and (pod == null or not pod.visible), "full again, the pod's put away")
	# The quiet top-up (not aiming, not a Reload) shows nothing.
	p.marker.ammo = 20
	await _frames(int((PaintMarker.TOPUP_DELAY + 0.3) * 60.0))
	_check(p.marker.is_reloading() and not p.marker.is_visible_reload() and p.model.reload < 0.0, "the top-up while the marker's away isn't shown")
	p.input_enabled = false
	p.queue_free()
	rig.queue_free()


## Drips (design section 3): every splat and hit is stamped on the paint
## clock the shaders read; wall splats get room to run, the flat and a
## splat with nothing under it get none.
func _check_drips(car: Car) -> void:
	_check(ProjectSettings.has_setting("shader_globals/paint_now"), "the shaders' paint clock is a global uniform")
	var t0 := PaintSplats.clock
	await process_frame
	await process_frame
	_check(PaintSplats.clock > t0, "the paint clock runs (%.3f to %.3f)" % [t0, PaintSplats.clock])
	var splats := _shots.splats
	# The wall at z 40 faces -z; its face is at z 39.5, from y 0 to 6.
	splats.add(Vector3(2.0, 3.0, 39.5), Vector3(0, 0, -1), Color.WHITE, 0.16)
	var slot := splats.newest_slot()
	var xf := splats.transform_of(slot)
	_check(splats.drip_room_of(slot) > 0.99 and xf.basis.y.normalized().dot(Vector3.DOWN) > 0.99,
		"a wall splat is laid to run downhill, with room to (%.2f)" % splats.drip_room_of(slot))
	splats.add(Vector3(2.0, 0.0, 20.0), Vector3.UP, Color.WHITE, 0.16)
	_check(splats.drip_room_of(splats.newest_slot()) == 0.0, "a splat on the flat doesn't run")
	splats.add(Vector3(4.0, 0.12, 39.5), Vector3(0, 0, -1), Color.WHITE, 0.16)
	_check(splats.drip_room_of(splats.newest_slot()) == 0.0, "a splat with no wall under it doesn't run into the air")
	var born := splats.born_of(slot)
	_check(absf(born - PaintSplats.clock) < 1.0, "a splat carries when it landed (%.2f)" % born)
	var pc := PaintCoverage.of(car)
	pc.add_hit(Vector3(-0.9, 0.7, 0.0), Color.WHITE, 0.16, false, Vector3.LEFT)
	var h: Dictionary = pc.hits[-1]
	_check(absf(float(h.get("born", -1.0)) - PaintSplats.clock) < 0.01, "a hit on a car carries when it landed")
	var mat := car.body_mesh.material_overlay as ShaderMaterial
	var borns: Variant = mat.get_shader_parameter("hit_born") if mat != null else null
	_check(borns is PackedFloat32Array and absf((borns as PackedFloat32Array)[pc.hits.size() - 1] - PaintSplats.clock) < 0.01,
		"the car's paint shader gets the landing times")
	pc.clear()

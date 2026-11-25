extends SceneTree
## Checks the crane truck and the building-supply jobs (CraneTool,
## SupplyJobs; docs/design.md section 6½), headless and without the town:
##
##   godot --headless --path . --script res://tools/supplies_check.gd
##
## The crane truck is within its drawing budget (tools/model_budget.gd);
## its crane won't move until the legs are down, and the legs hold the
## truck still; the driving controls swing the crane and raise the boom;
## it hooks a pallet off the ground, lifts it, swings it across and sets it
## down upright in a zone, lets go, and folds itself away. A supply job is
## made and runs stop by stop: the order is set out at each store, the stop
## waits until it's on the deck, a drop waits until the right load sits in
## its ring on the ground, a knock costs condition, and the job pays and
## counts as done. One "SUPPLIES" line per check; exits non-zero with
## "SUPPLIES FAIL" lines if any fail. The save file is put back exactly as
## it was.

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false
var _world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("SUPPLIES ok   %s" % what)
	else:
		_failures += 1
		print("SUPPLIES FAIL %s" % what)


func _steps(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _steps(roundi(s * Engine.physics_ticks_per_second))


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var gs := root.get_node("GameState")
	_had_save = FileAccess.file_exists("user://savegame.json")
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes("user://savegame.json")
	gs.call("reset_save")
	_world = Node3D.new()
	_world.name = "CheckWorld"
	root.add_child(_world)
	var cam := Camera3D.new()
	_world.add_child(cam)

	_budget_checks()
	await _crane_checks(cam)
	await _job_checks(gs, cam)

	if _had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("SUPPLIES %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Flat ground (80 m square) round a point.
func _pad(at: Vector3) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	ground.add_child(shape)
	ground.collision_layer = Layers.GROUND
	_world.add_child(ground)
	ground.global_position = Vector3(at.x, -0.5, at.z)


func _truck(at: Vector3, yaw := 0.0) -> Car:
	var car := Car.new()
	car.model_id = "crane_truck"
	car.paint = Color.html("#e9e7e1")
	_world.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.4)
	car.reset_physics_interpolation()
	return car


func _load(kind: String, at: Vector3) -> Cargo:
	var c := Cargo.new()
	c.kind = kind
	_world.add_child(c)
	c.global_position = at
	return c


func _place(b: RigidBody3D, at: Vector3, yaw := 0.0) -> void:
	b.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.reset_physics_interpolation()


# --- the model -----------------------------------------------------------------------------

func _budget_checks() -> void:
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/model_budget.gd"], out, true)
	var lines := "\n".join(PackedStringArray(out)).split("\n")
	var mine: Array[String] = []
	var failed := false
	for l: String in lines:
		if l.contains("crane_truck"):
			mine.append(l.strip_edges())
			failed = failed or l.contains("FAIL")
	_check(mine.size() >= 2 and not failed, "the crane truck is within its drawing budget (model_budget exit %d): %s" % [code, mine[0] if not mine.is_empty() else "not measured"])


# --- the crane -----------------------------------------------------------------------------

## Moves the crane to a pose over `secs` seconds, a step at a time (as the
## controls would), so a hanging load is carried, not yanked.
func _swing_to(tool: CraneTool, slew_deg: float, boom_deg: float, reach: float, secs: float) -> void:
	var s0 := rad_to_deg(tool.slew)
	var b0 := rad_to_deg(tool.boom)
	var r0 := tool.reach
	var n := roundi(secs * Engine.physics_ticks_per_second)
	for i in n:
		var t := smoothstep(0.0, 1.0, float(i + 1) / n)
		tool.set_pose(1.0, lerpf(s0, slew_deg, t), lerpf(b0, boom_deg, t), lerpf(r0, reach, t), tool.hook_len)
		await physics_frame


## The reach (0..1) that puts the tip `dist` m out from the column at this
## boom angle, with the knuckle straight.
func _reach_for(tool: CraneTool, boom_deg: float, dist: float) -> float:
	var keep := [tool.slew, tool.boom, tool.reach]
	var best := 0.0
	var best_err := INF
	for i in 56:
		tool.boom = deg_to_rad(boom_deg)
		tool.reach = 0.45 + i / 100.0
		var err := absf(tool.reach_m() - dist)
		if err < best_err:
			best_err = err
			best = tool.reach
	tool.slew = keep[0]
	tool.boom = keep[1]
	tool.reach = keep[2]
	return best


func _crane_checks(cam: Camera3D) -> void:
	_pad(Vector3.ZERO)
	var car := _truck(Vector3.ZERO)
	cam.global_position = Vector3(0, 8, 20)
	await _seconds(1.5)
	var tool := car.tool as CraneTool
	_check(tool != null and tool.stowed() and tool.legs == 0.0, "a crane truck has its crane, stowed")
	var driver := Node3D.new()
	_world.add_child(driver)
	car.driver = driver
	Input.action_press("steer_left")
	await _seconds(0.5)
	Input.action_release("steer_left")
	_check(tool.slew == 0.0, "with the legs up the steering doesn't swing the crane")
	var y0 := car.global_position.y
	Input.action_press("work_down")
	await _seconds(0.3)
	Input.action_release("work_down")
	await _seconds(4.0)
	_check(tool.mode == CraneTool.Mode.WORKING and tool.legs >= 1.0 and car.tool.holds_still(), "stopped, work_down puts the legs down (%s)" % tool.status())
	_check(car.global_position.y > y0 + 0.01 and car.global_basis.y.y > 0.995, "the legs take the weight: the truck rises %.2f m, level" % (car.global_position.y - y0))
	Input.action_press("accelerate")
	await _seconds(1.0)
	Input.action_release("accelerate")
	_check(absf(car.speed) < 0.05 and tool.boom > deg_to_rad(68.0) + 0.1, "the throttle raises the boom and doesn't drive (boom %.0f°)" % rad_to_deg(tool.boom))
	Input.action_press("steer_left")
	await _seconds(1.0)
	Input.action_release("steer_left")
	_check(tool.slew > 0.15 and absf(car.steer_angle) < 0.01, "steering swings the crane (%.0f°), not the wheels" % rad_to_deg(tool.slew))
	Input.action_press("aux_in")
	await _seconds(1.5)
	Input.action_release("aux_in")
	var r := tool.reach_m()
	_check(tool.reach > 0.2, "aux_in unfolds the boom (reach %.1f m)" % r)

	# A pallet of bricks on the ground off the right side, level with the
	# column.
	var column := car.global_transform * Vector3(0.0, 0.0, -0.72)
	var right := car.global_basis.x
	var bricks := _load("pallet_bricks", column + right * 4.2 + Vector3.UP * 0.05)
	await _seconds(1.0)
	var boom := 35.0
	await _swing_to(tool, 90.0, boom, _reach_for(tool, boom, 4.2), 2.5)
	var lift := bricks.global_transform * CraneTool.lift_point(bricks)
	tool.hook_len = tool.tip_point().y - lift.y - 0.55 - 0.1
	await _seconds(0.5)
	var msg := tool.hitch_action()
	_check(tool.line != null and tool.hooked == bricks, "the hook catches the pallet under it: \"%s\"" % msg)
	var ground_y := bricks.global_position.y
	Input.action_press("work_up")
	await _seconds(3.0)
	Input.action_release("work_up")
	await _seconds(1.0)
	_check(bricks.global_position.y > ground_y + 1.0 and car.global_basis.y.y > 0.99, "the hoist lifts it %.1f m, the truck stays level on its legs" % (bricks.global_position.y - ground_y))
	# Swing it round toward the back and set it down in a zone there.
	var zone := column + right * 3.2 + car.global_basis.z * 3.0
	var rel := car.global_transform.affine_inverse() * zone
	var slew_deg := rad_to_deg(atan2(rel.x, rel.z + 0.72))
	var dist := Vector2(rel.x, rel.z + 0.72).length()
	await _swing_to(tool, slew_deg, boom, _reach_for(tool, boom, dist), 4.0)
	await _seconds(2.0)
	_check(bricks.global_position.y > ground_y + 0.5, "carried round in the air (swinging %.2f m/s)" % bricks.linear_velocity.length())
	Input.action_press("work_down")
	for i in 300:
		await physics_frame
		if tool.line.tension < 2000.0 and bricks.global_position.y < ground_y + 0.1:
			break
	Input.action_release("work_down")
	await _seconds(1.5)
	var off := Vector2(bricks.global_position.x - zone.x, bricks.global_position.z - zone.z).length()
	_check(off < 1.0 and bricks.global_basis.y.y > 0.95 and absf(bricks.global_position.y - ground_y) < 0.1, "set down %.2f m from the middle of the zone, upright" % off)
	msg = tool.hitch_action()
	_check(tool.line == null and msg.begins_with("Let go"), "and let go: \"%s\"" % msg)
	# Too heavy at full reach.
	tool.set_pose(1.0, 90.0, 0.0, 1.0, 1.0)
	_check(tool.capacity() < bricks.mass, "at full reach (%.1f m) it's rated for %d kg, less than the bricks" % [tool.reach_m(), roundi(tool.capacity())])
	await _swing_to(tool, 0.0, 30.0, 0.3, 1.0)
	Input.action_press("handbrake")
	await physics_frame
	await physics_frame
	Input.action_release("handbrake")
	for i in 30 * 60:
		await physics_frame
		if tool.stowed():
			break
	_check(tool.stowed() and tool.legs == 0.0 and not car.tool.holds_still() and not car.controls_held, "the handbrake folds it away and brings the legs up")
	car.driver = null
	driver.queue_free()
	bricks.queue_free()
	car.queue_free()
	await _seconds(0.2)


# --- a supply job ---------------------------------------------------------------------------

func _job_checks(gs: Node, cam: Camera3D) -> void:
	var main := Node3D.new()
	main.name = "FakeMain"
	_world.add_child(main)
	var who := Node3D.new()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar vehicle = null\nvar velocity := Vector3.ZERO\n"
	s.reload()
	who.set_script(s)
	main.add_child(who)
	var eco := Economy.new()
	_world.add_child(eco)
	eco.setup(null, main, who, null)
	await _steps(2)
	var sup := eco.get_node_or_null("Supplies") as SupplyJobs
	_check(sup != null, "Supplies is one of Economy's modules")
	if sup == null:
		return
	_check(not eco.jobs.offers(["supplies"], Vector3.ZERO, 3).is_empty(), "the jobs board offers supply jobs")
	seed(7)
	var job := {}
	for i in 40:
		job = sup.make_job(Vector3.ZERO, 2, 2)
		var k: Array = job["data"]["drops"].map(func(d: Dictionary) -> String: return str(d["kind"]))
		if (job["stops"] as Array).size() == 4 and k[0] != k[1]:
			break
	var stops: Array = job["stops"]
	_check(stops.size() == 4 and str(stops[0]["name"]) == "Load up" and str(stops[1]["name"]) == "Load up" and (str(stops[2]["name"]).begins_with("Drop") or str(stops[2]["name"]).begins_with("Set")), "a job: two stores then two houses (%s)" % str(stops.map(func(x: Dictionary) -> String: return "%s %s" % [x["name"], x["address"]])))
	_check(int(job["pay"]) >= 500 and int(job["pay"]) <= 1500, "it pays %s: %s" % [CarModels.dollars(int(job["pay"])), str(job["title"])])
	_check(eco.jobs.start(job) != "", "on foot with no crane truck about, it can't be taken: \"%s\"" % eco.jobs.start(job))

	var data: Dictionary = job["data"]
	var loads: Array = data["loads"]
	for st: Dictionary in stops:
		_pad(st["at"])
	for d: Dictionary in data["drops"]:
		_pad(Vector3(d["zone"].x, 0.0, d["zone"].y))
	var truck := _truck(stops[0]["at"] + Vector3(4, 0, 0))
	who.set("vehicle", truck)
	who.global_position = truck.global_position
	cam.global_position = truck.global_position + Vector3(0, 10, 15)
	await _seconds(1.5)
	_check(eco.jobs.start(job) == "" and eco.jobs.active == job, "in the crane truck it starts")

	var slot := 0
	for store in 2:
		await _drive_to(truck, who, cam, stops[store]["at"] + Vector3(4, 0, 0))
		await _seconds(1.0)
		var mine: Array = loads.filter(func(l: Dictionary) -> bool: return int(l["store"]) == store)
		var set_out := mine.all(func(l: Dictionary) -> bool: return l["body"] != null and is_instance_valid(l["body"]))
		_check(set_out, "at %s the order is set out (%d load%s)" % [stops[store]["address"], mine.size(), "" if mine.size() == 1 else "s"])
		await _seconds(3.0)
		_check(eco.jobs.index == store, "the stop waits while it's on the ground: \"%s\"" % stops[store]["hint"])
		# On the deck (the crane's own checks above lift for real).
		for i in mine.size():
			var b: RigidBody3D = mine[i]["body"]
			var spot := truck.global_transform * Vector3(-0.6 + 1.2 * (slot % 2), 1.35, 1.2 + 1.8 * (slot / 2))
			slot += 1
			_place(b, spot, truck.global_rotation.y)
			mine[i]["v"] = Vector3.ZERO
		await _seconds(3.5)
		_check(eco.jobs.index == store + 1, "once it's on the deck, on to the next stop (%s)" % str(eco.jobs.stop().get("name", "done")))

	for n in 2:
		var stop: Dictionary = stops[2 + n]
		var drop: Dictionary = data["drops"][int(stop["drop"])]
		await _drive_to(truck, who, cam, stop["at"])
		await _seconds(3.0)
		_check(eco.jobs.index == 2 + n, "at %s nothing happens while the load's on the deck" % stop["address"])
		var right: RigidBody3D = null
		var wrong: RigidBody3D = null
		for l: Dictionary in loads:
			if bool(l["delivered"]):
				continue
			if str(l["kind"]) == str(drop["kind"]) and right == null:
				right = l["body"]
			elif str(l["kind"]) != str(drop["kind"]):
				wrong = l["body"]
		var zone := Vector3(drop["zone"].x, 0.0, drop["zone"].y)
		if wrong != null:
			_place(wrong, zone + Vector3.UP * 0.05)
			await _seconds(3.0)
			_check(eco.jobs.index == 2 + n, "the wrong load in the ring doesn't count")
			_place(wrong, truck.global_transform * Vector3(0.0, 1.35, 3.0), truck.global_rotation.y)
		if n == 0:
			# Dropped from two metres: a knock.
			_place(right, zone + Vector3.UP * 2.0)
			await _seconds(1.5)
			_check(sup.condition(job) < 1.0, "dropped, it takes a knock: condition %.2f" % sup.condition(job))
		else:
			_place(right, zone + Vector3(0.6, 0.05, -0.4))
		await _seconds(3.5)
		_check(eco.jobs.index == 3 + n or eco.jobs.active.is_empty(), "the right load in the ring: done (%s)" % stop["address"])

	_check(eco.jobs.active.is_empty() and int(gs.call("jobs_done_count", "supplies")) == 1 and int(gs.get("money")) > 300, "the job's finished: paid %s and counted" % CarModels.dollars(int(gs.get("money"))))
	eco.queue_free()
	truck.queue_free()
	await _seconds(0.2)
	gs.call("reset_save")


## Puts the truck at a spot (as if driven there) and lets it settle.
func _drive_to(truck: Car, who: Node3D, cam: Camera3D, at: Vector3) -> void:
	var keep := []
	for l in truck.tie_downs.loads_on_deck():
		var b: RigidBody3D = l["body"]
		keep.append([b, truck.global_transform.affine_inverse() * b.global_transform])
	truck.global_transform = Transform3D(truck.global_basis, at + Vector3.UP * 0.25)
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	truck.reset_physics_interpolation()
	for k: Array in keep:
		_place(k[0], truck.global_transform * (k[1] as Transform3D).origin, truck.global_rotation.y)
	who.global_position = truck.global_position
	cam.global_position = truck.global_position + Vector3(0, 10, 15)
	await _seconds(1.0)
	for k: Array in keep:
		(k[0] as RigidBody3D).linear_velocity = Vector3.ZERO

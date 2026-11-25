extends SceneTree
## Checks the money foundation (scripts/economy/, docs/design.md section
## 6½), headless and without the town:
##
##   godot --headless --path . --script res://tools/economy_check.gd
##
## The save keeps vehicles, properties, jobs done, items and home, and reads
## an old (version 1) save; storage spaces limit how many vehicles you can
## keep; owned cars are made from the save where they were left and their
## spot is saved; addresses load; a counter shows its prompt, charges for
## what you pick and refuses when you're short; a job runs stop by stop,
## points the GPS at each, pays by the formula and counts as done; a
## cancelled one pays nothing. One "ECONOMY" line per check; exits non-zero
## with "ECONOMY FAIL" lines if any fail. The save file is put back exactly
## as it was.

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ECONOMY ok   %s" % what)
	else:
		_failures += 1
		print("ECONOMY FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


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

	await _save_checks(gs)
	await _owned_car_checks(gs)
	_address_checks()
	await _counter_checks(gs)
	await _job_checks(gs)

	# Put the save back as it was.
	if _had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("ECONOMY %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _save_checks(gs: Node) -> void:
	var id: String = gs.call("add_vehicle", "civique", Color(0.8, 0.1, 0.1), {"parts": ["sport_exhaust"]})
	gs.call("set_vehicle", id, {"parked": {"x": 10.0, "y": 2.0, "z": -5.0, "yaw": 1.0}})
	gs.call("add_property", "queen_parkade")
	gs.call("add_job_done", "spuddash")
	gs.call("add_job_done", "spuddash")
	gs.call("add_item", "armour", 3)
	gs.call("set_home", "queen_parkade")
	gs.call("load_game")
	var v: Dictionary = gs.call("vehicle", id)
	_check(not v.is_empty() and str(v["model"]) == "civique" and str(v["paint"]).begins_with("cc1a1a") and (v["mods"]["parts"] as Array).has("sport_exhaust") and is_equal_approx(float(v["parked"]["x"]), 10.0),
		"a vehicle survives a save and load, with its paint, mods and spot")
	_check((gs.get("properties") as Array).has("queen_parkade") and int(gs.call("jobs_done_count", "spuddash")) == 2 and int(gs.call("item_count", "armour")) == 3 and str(gs.get("home")) == "queen_parkade",
		"so do properties, jobs done, items and home")
	_check(not bool(gs.call("add_item", "armour", -5)) and int(gs.call("item_count", "armour")) == 3 and bool(gs.call("add_item", "armour", -3)) and int(gs.call("item_count", "armour")) == 0,
		"items can't be used past zero")
	# Spaces: one free, more with a property.
	(gs.get_script() as GDScript).set("property_spaces", {"queen_parkade": 2})
	_check(int(gs.call("storage_spaces")) == 3 and bool(gs.call("has_space")), "storage: one free space plus a property's (%d)" % int(gs.call("storage_spaces")))
	gs.call("remove_property", "queen_parkade")
	_check(int(gs.call("storage_spaces")) == 1 and not bool(gs.call("has_space")) and str(gs.get("home")) == "", "without it, one space, already taken; and it's not home any more")
	# An old save (version 1) still reads.
	var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "money": 1234, "weapons": ["islander"], "impounded": [], "session": 3}))
	f.close()
	gs.call("load_game")
	_check(int(gs.get("money")) == 1234 and (gs.get("vehicles") as Array).is_empty() and (gs.get("properties") as Array).is_empty(), "a version 1 save still loads, with nothing owned")
	gs.call("reset_save")


func _owned_car_checks(gs: Node) -> void:
	var main := Node3D.new()
	main.name = "FakeMain"
	main.set_meta("note", "stands in for Main")
	root.add_child(main)
	var who := Node3D.new()
	main.add_child(who)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	ground.collision_layer = Layers.GROUND
	main.add_child(ground)
	var owned := OwnedCars.new()
	main.add_child(owned)
	owned.setup(main, who)
	var car := Car.new()
	car.model_id = "civique"
	car.paint = Color(0.1, 0.3, 0.8)
	main.add_child(car)
	car.global_position = Vector3(5, 0.6, 7)
	await _frames(2)
	var id := owned.adopt(car)
	var v: Dictionary = gs.call("vehicle", id)
	_check(car.garage_id == id and not v.is_empty() and str(v["model"]) == "civique" and not (v["parked"] as Dictionary).is_empty(), "a bought car is adopted: in the save with where it is")
	# Moved and left: its spot is saved.
	car.global_position = Vector3(20, 0.6, -12)
	car.set_meta("_driven", true)
	await _frames(3)
	v = gs.call("vehicle", id)
	_check(absf(float(v["parked"]["x"]) - 20.0) < 0.6 and absf(float(v["parked"]["z"]) + 12.0) < 0.6, "getting out saves where it was left (%.1f, %.1f)" % [float(v["parked"]["x"]), float(v["parked"]["z"])])
	# A new session: made again from the save.
	car.queue_free()
	owned.queue_free()
	await _frames(2)
	var again := OwnedCars.new()
	main.add_child(again)
	again.setup(main, who)
	var back := again.car_for(id)
	_check(back != null and back.model_id == "civique" and back.paint.is_equal_approx(Color.html(str(v["paint"]))) and back.global_position.distance_to(Vector3(20, 0.9, -12)) < 1.0 and back.garage_id == id,
		"next session it's waiting where it was left")
	again.put_away(id, "queen_parkade")
	await _frames(2)
	v = gs.call("vehicle", id)
	_check(again.car_for(id) == null and str(v["stored"]) == "queen_parkade" and (v["parked"] as Dictionary).is_empty(), "put away: off the street, in storage")
	var out := again.spawn(id, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	_check(out != null and str((gs.call("vehicle", id) as Dictionary)["stored"]) == "", "brought out again")
	main.queue_free()
	await _frames(2)
	gs.call("reset_save")


func _address_checks() -> void:
	var a := Addresses.load_for(null)
	_check(a.all.size() > 1000, "addresses load (%d)" % a.all.size())
	var homes := 0
	for e in a.all:
		if e["kind"] == "home":
			homes += 1
	var pick := a.pick(Vector2.ZERO, 300.0, 900.0, ["home"])
	var d := Vector2(pick.get("x", 0.0), pick.get("z", 0.0)).length()
	_check(not pick.is_empty() and d >= 300.0 and d <= 900.0 and pick["kind"] == "home", "pick: a home %d m out: %s" % [roundi(d), Addresses.text(pick)])
	var mid := Addresses.lawn(pick, 0.5)
	_check(mid.distance_to(pick["door"]) < (pick["door"] as Vector2).distance_to(pick["road"]), "the lawn lies between the street and the door")
	_check(homes > 1000, "most are homes (%d)" % homes)


func _counter_checks(gs: Node) -> void:
	var hud := Hud.new()
	root.add_child(hud)
	var who := Node3D.new()
	root.add_child(who)
	await _frames(2)
	var counters := Counters.new()
	root.add_child(counters)
	counters.setup(who, hud)
	var bought := []
	counters.add({"id": "test_till", "title": "Ervin's", "at": Vector3(0, 0, 0), "kind": "gas", "items": func() -> Array:
		return [{"id": "balls", "name": "Paintballs", "price": 40, "action": func(_i: Dictionary) -> String:
			bought.append("balls")
			return "Hopper's full."},
			{"id": "vest", "name": "Armour", "price": 500, "enabled": false, "why": "Sold out."}]})
	who.global_position = Vector3(1, 0, 1)
	await _frames(2)
	_check(counters.near() == "test_till" and hud._prompt_panel.visible and hud._prompt_text.text == "Ervin's", "at a counter the prompt shows (%s)" % hud._prompt_text.text)
	_check(counters.map_places().size() == 1 and counters.map_places()[0]["kind"] == "gas", "and it's on the map")
	gs.call("add_money", 100)
	counters.open_card("test_till")
	_check(counters.menu.visible and counters.menu.items.size() == 2, "the card opens with its list")
	counters._on_chosen("test_till", counters.menu.items[0])
	_check(int(gs.get("money")) == 60 and bought == ["balls"] and counters.menu._message.text == "Hopper's full.", "buying pays and does it ($%d left)" % int(gs.get("money")))
	counters._on_chosen("test_till", counters.menu.items[1])
	_check(int(gs.get("money")) == 60 and counters.menu._message.text == "Sold out.", "a disabled item says why and charges nothing")
	counters._on_chosen("test_till", counters.menu.items[0])
	counters._on_chosen("test_till", counters.menu.items[0])
	_check(int(gs.get("money")) == 20 and bought.size() == 2 and counters.menu._message.text.begins_with("Not enough money"), "short of money: refused (%s)" % counters.menu._message.text)
	counters.menu.close()
	who.global_position = Vector3(10, 0, 10)
	await _frames(2)
	_check(counters.near() == "", "walk away: no counter")
	counters.queue_free()
	hud.queue_free()
	who.queue_free()
	await _frames(2)
	gs.call("reset_save")


func _job_checks(gs: Node) -> void:
	var gps := Gps.new()
	root.add_child(gps)
	var who := Node3D.new()
	root.add_child(who)
	gps.setup(null, who)
	var jobs := Jobs.new()
	root.add_child(jobs)
	jobs.setup(who, null)
	var reached := []
	var job := {"kind": "spuddash", "company": "SpudDash", "title": "Fries to 45 Kent Street", "pay": 200, "estimate": 60.0, "gps": "directions",
		"stops": [
			{"name": "Pick up", "address": "Tim Hardly's", "at": Vector3(50, 0, 0), "radius": 5.0, "wait": 0.4, "in_vehicle": false, "on_reach": func(_s: Dictionary, _j: Dictionary) -> void: reached.append("pickup")},
			{"name": "Drop off", "address": "45 Kent Street", "at": Vector3(-80, 0, 40), "radius": 5.0, "wait": 0.4, "in_vehicle": false},
		]}
	jobs.add_source("spuddash", func(_near: Vector3, _n: int) -> Array: return [job])
	_check(jobs.offers(["spuddash"], Vector3.ZERO).size() == 1, "job sources offer jobs")
	_check(jobs.start(job) == "" and not jobs.active.is_empty(), "a job starts")
	_check(jobs.start(job) != "", "only one at a time")
	_check(gps.active and gps.place == "Tim Hardly's" and gps.mode == "directions" and gps.has_meta("job"), "the GPS points at the first stop, with the job's help mode")
	who.global_position = Vector3(51, 0, 1)
	await create_timer(0.9).timeout
	_check(jobs.index == 1 and reached == ["pickup"] and gps.place == "45 Kent Street", "stopping in the first stop's zone moves on to the next")
	# Close to the drop: the GPS doesn't call it arrived; the job decides.
	who.global_position = Vector3(-80, 0, 30)
	await create_timer(0.5).timeout
	_check(gps.active and not jobs.active.is_empty(), "near isn't there: the job's still on")
	var expect: int = jobs.pay_now()["pay"]
	who.global_position = Vector3(-79, 0, 41)
	await create_timer(0.9).timeout
	_check(jobs.active.is_empty() and int(gs.get("money")) >= expect - 5 and int(gs.get("money")) > 200 and int(gs.call("jobs_done_count", "spuddash")) == 1,
		"the last stop finishes it: paid %s (quick, and more for less GPS help) and counted" % CarModels.dollars(int(gs.get("money"))))
	_check(not gps.active, "and the GPS is cleared")
	# Cancelled: no pay.
	var money := int(gs.get("money"))
	jobs.start(job.duplicate(true))
	jobs.cancel()
	_check(jobs.active.is_empty() and int(gs.get("money")) == money and not gps.active, "a cancelled job pays nothing")
	# Needs: refused with the reason.
	var truck_job := job.duplicate(true)
	truck_job["needs"] = func(_p: Node3D) -> String: return "You need a tow truck."
	_check(jobs.start(truck_job) == "You need a tow truck.", "a job you can't do says why")
	# The pay formula's time factor.
	jobs.active = {"pay": 100, "estimate": 100.0, "gps": "route", "stops": [{}]}
	jobs._t0 = Time.get_ticks_msec() / 1000.0 - 200.0
	_check(int(jobs.pay_now()["pay"]) == 60, "twice the estimate pays 0.6 (%d)" % int(jobs.pay_now()["pay"]))
	jobs._t0 = Time.get_ticks_msec() / 1000.0 - 10.0
	_check(int(jobs.pay_now()["pay"]) == 120, "half the estimate or quicker pays 1.2 (%d)" % int(jobs.pay_now()["pay"]))
	jobs.active = {}
	jobs.queue_free()
	gps.queue_free()
	who.queue_free()
	await _frames(2)
	gs.call("reset_save")

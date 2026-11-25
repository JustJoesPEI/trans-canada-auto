extends SceneTree
## Checks SpudDash (scripts/economy/spuddash.gd, docs/design.md section 6),
## headless and without the town:
##
##   godot --headless --path . --script res://tools/spuddash_check.gd
##
## The food places load with a drive-thru spot each; the phone offers 3 to
## 5 orders from them to real addresses (homes and apartments, 250-1300 m
## out), each paying more with less GPS help; a run picks up at the window,
## points the GPS with the chosen mode, loses food to hard hits, bumps and
## a roll, drops at the door on foot, pays by the condition and tips by the
## customer's mood with a rating line; a painted car tips less ("My order
## arrived orange"); runs count toward the licence ladder. One "SPUDDASH"
## line per check; exits non-zero with "SPUDDASH FAIL" lines if any fail.
## The save file is put back exactly as it was.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("SPUDDASH ok   %s" % what)
	else:
		_failures += 1
		print("SPUDDASH FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var gs := root.get_node("GameState")
	var had_save := FileAccess.file_exists("user://savegame.json")
	var saved := FileAccess.get_file_as_bytes("user://savegame.json") if had_save else PackedByteArray()
	gs.call("reset_save")

	await _checks(gs)

	if had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("SPUDDASH %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _checks(gs: Node) -> void:
	# The world in miniature: flat ground, the GPS, someone who can drive.
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9000, 1, 9000)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	ground.collision_layer = Layers.GROUND
	root.add_child(ground)
	var who_script := GDScript.new()
	who_script.source_code = "extends Node3D\nvar vehicle: Node3D = null\nvar velocity := Vector3.ZERO\n"
	who_script.reload()
	var who: Node3D = who_script.new()
	root.add_child(who)
	var gps := Gps.new()
	root.add_child(gps)
	gps.setup(null, who)
	var jobs := Jobs.new()
	root.add_child(jobs)
	jobs.setup(who, null)
	var sd := SpudDash.new()
	root.add_child(sd)
	var addresses := Addresses.load_for(null)
	sd.start(jobs, addresses, null, who, null)

	# Places and offers.
	_check(sd.places.size() >= 8 and sd.places.any(func(p: Dictionary) -> bool: return p["name"] == "Tim Hardly's"), "food places load (%d)" % sd.places.size())
	var windys: Dictionary = sd.places.filter(func(p: Dictionary) -> bool: return p["name"] == "Windy's")[0]
	var here: Vector2 = windys["at"] + Vector2(100, 50)
	var offers := sd.current_offers(here)
	_check(offers.size() >= 3 and offers.size() <= 5, "the phone offers %d orders" % offers.size())
	var real := true
	var far_ok := true
	for o in offers:
		var a: Dictionary = o["address"]
		real = real and addresses.all.has(a) and str(a["kind"]) in ["home", "apartments"] and Addresses.text(a) != ""
		var d := (o["place"]["at"] as Vector2).distance_to(Vector2(a["x"], a["z"]))
		far_ok = far_ok and d >= SpudDash.DROP_MIN - 0.1 and d <= SpudDash.DROP_MAX + 0.1
		print("  %s -> %s: %s, \"%s\" (%s), %s / %s / %s" % [o["place"]["name"], Addresses.text(a), o["order"], o["line"], o["client"],
			CarModels.dollars(SpudDash.pay_for(o, "route")), CarModels.dollars(SpudDash.pay_for(o, "directions")), CarModels.dollars(SpudDash.pay_for(o, "address"))])
	_check(real, "each goes to a real house number (a home or apartments)")
	_check(far_ok, "250-1300 m from the place")
	var o0: Dictionary = offers[0]
	_check(SpudDash.pay_for(o0, "route") < SpudDash.pay_for(o0, "directions") and SpudDash.pay_for(o0, "directions") < SpudDash.pay_for(o0, "address")
		and SpudDash.pay_for(o0, "address") == roundi(float(o0["base"]) * 1.35), "less GPS help pays more (route ×1.0, directions ×1.15, address ×1.35)")
	_check(offers.all(func(o: Dictionary) -> bool: return SpudDash.pay_for(o, "route") >= 60 and SpudDash.pay_for(o, "address") <= 250), "pay in the starter range")
	_check(sd.current_offers(here) == offers, "the same orders until the next set")
	_check(jobs.offers(["spuddash"], Vector3(here.x, 0, here.y), 2).size() == 2, "and they're a job source (for a job board)")

	# A car to deliver in.
	var car := Car.new()
	car.model_id = "civique"
	car.paint = Color(0.9, 0.9, 0.85)
	root.add_child(car)
	await _frames(2)
	car.freeze = true

	# Run 1: clean and careful.
	var r1 := await _run_one(sd, jobs, gps, who, car, gs, offers[0], "directions", func() -> void: pass)
	_check(r1["food"] >= 0.99 and r1["tip"] == roundi(r1["pay"] * SpudDash.MAX_TIP) and r1["stars"] == 5, "a clean, careful run: food %d%%, tip 25%% (%s on %s), 5/5 \"%s\"" % [roundi(r1["food"] * 100.0), CarModels.dollars(r1["tip"]), CarModels.dollars(r1["pay"]), r1["line"]])
	_check(int(gs.call("jobs_done_count", "spuddash")) == 1, "and it counts toward the licence ladder")

	# Run 2: hit something, a curb, then roll it.
	var r2 := await _run_one(sd, jobs, gps, who, car, gs, sd.current_offers(here)[0], "route", func() -> void:
		var before := float(jobs.active["data"]["food"])
		car.crashed.emit(12.0)
		car.crashed.emit(10.0) # the same knock, next frame
		var after_hit := float(jobs.active["data"]["food"])
		var expect := SpudDash.crash_loss(12.0) * float(jobs.active["data"]["fragile"])
		_check(absf((before - after_hit) - minf(expect, before)) < 0.001, "a hard hit spills the food (%d%% → %d%%), once per knock" % [roundi(before * 100.0), roundi(after_hit * 100.0)])
		_check(jobs._panel != null and str(jobs.active["cargo"]) == "Food" and is_equal_approx(float((jobs.active["cargo_state"] as Callable).call(jobs.active)), after_hit), "the job panel shows it")
		car.bumped.emit(4.0)
		_check(float(jobs.active["data"]["food"]) < after_hit or after_hit == 0.0, "so does a big jolt")
		var before_roll := float(jobs.active["data"]["food"])
		car.rotation = Vector3(0, 0, PI)
		await _frames(3)
		car.rotation = Vector3.ZERO
		await _frames(2)
		_check(float(jobs.active["data"]["food"]) < before_roll or before_roll == 0.0, "and rolling over (%d%% left)" % roundi(float(jobs.active["data"]["food"]) * 100.0)))
	_check(r2["food"] < 0.8 and r2["condition"] < 1.0 and r2["tip"] < roundi(r2["pay"] * SpudDash.MAX_TIP) and r2["stars"] < 5, "a rough run pays less for the condition (×%.2f) and tips less: %s, %d/5 \"%s\"" % [r2["condition"], CarModels.dollars(r2["tip"]), r2["stars"], r2["line"]])

	# Run 3: food fine, car painted orange.
	var pc := PaintCoverage.of(car)
	for i in 14:
		pc.add_hit(Vector3(randf_range(-0.8, 0.8), randf_range(0.3, 1.3), randf_range(-2.0, 2.0)), Color(1.0, 0.5, 0.05), PaintCoverage.BALL_SIZE, false)
	var r3 := await _run_one(sd, jobs, gps, who, car, gs, sd.current_offers(here)[0], "address", func() -> void: pass)
	_check(r3["food"] >= 0.99 and float(r3["tip"]) / r3["pay"] < float(r1["tip"]) / r1["pay"] - 0.03, "a painted car (%d%% covered) tips less: %s on %s" % [roundi(pc.coverage * 100.0), CarModels.dollars(r3["tip"]), CarModels.dollars(r3["pay"])])
	_check(str(r3["line"]).contains("orange"), "and the customer says why: \"%s\"" % r3["line"])
	_check(SpudDash.mood(1.0, 0.5) == 0.0 and SpudDash.mood(0.2, 0.0) == 0.0, "a soaked car or wrecked food: no tip at all")

	# Cancelled: nothing, and the food stops being watched.
	var money := int(gs.get("money"))
	_check(sd.take(sd.current_offers(here)[0], "route") == "", "another order taken")
	jobs.cancel()
	_check(int(gs.get("money")) == money and jobs.active.is_empty() and int(gs.call("jobs_done_count", "spuddash")) == 3, "cancelled: no pay, not counted")
	# A new set after a couple of minutes.
	var first_ids := sd.current_offers(here).map(func(o: Dictionary) -> int: return int(o["id"]))
	sd._offers_time -= SpudDash.REFRESH + 1.0
	var next_ids := sd.current_offers(here).map(func(o: Dictionary) -> int: return int(o["id"]))
	_check(not next_ids.any(func(i: int) -> bool: return first_ids.has(i)), "a new set of orders comes every couple of minutes")

	for n: Node in [sd, jobs, gps, who, car, ground]:
		n.queue_free()
	await _frames(2)
	gs.call("reset_save")


## Takes `offer` with `mode`, drives to the window, does `en_route` with the
## food on board, walks it to the door. {pay, tip, food, stars, line, condition}.
func _run_one(sd: SpudDash, jobs: Jobs, gps: Gps, who: Node3D, car: Car, gs: Node, offer: Dictionary, mode: String, en_route: Callable) -> Dictionary:
	var money := int(gs.get("money"))
	var why := sd.take(offer, mode)
	_check(why == "" and str(jobs.active.get("kind", "")) == "spuddash" and gps.active and gps.mode == mode and gps.place == str(offer["place"]["name"]),
		"%s: taken, GPS to the pickup in %s mode" % [offer["place"]["name"], mode])
	_check(not sd.offers.has(offer), "and it's off the list")
	# At the drive-thru, in the car, held still.
	var pickup: Vector3 = jobs.stop()["at"]
	car.global_position = pickup + Vector3(2, 0.6, 0)
	who.global_position = car.global_position
	who.vehicle = car
	await create_timer(3.6).timeout
	_check(jobs.index == 1 and bool(jobs.active["data"]["picked"]) and gps.place == Addresses.text(offer["address"]), "picked up at the window; the GPS moves on to the address")
	await _frames(2)
	await en_route.call()
	var p := jobs.pay_now()
	# At the address: out of the car, to the door.
	car.global_position = jobs.stop()["at"] + Vector3(8, 0.6, 0)
	await _frames(2)
	who.vehicle = null
	who.global_position = jobs.stop()["at"] + Vector3(1, 0, 0)
	await create_timer(1.5).timeout
	var r: Dictionary = sd.last_rating
	var got := int(gs.get("money")) - money
	_check(jobs.active.is_empty() and not r.is_empty() and got == int(p["pay"]) + int(r["tip"]), "delivered at the door: paid %s + tip %s" % [CarModels.dollars(got - int(r["tip"])), CarModels.dollars(int(r["tip"]))])
	return {"pay": got - int(r["tip"]), "tip": int(r["tip"]), "food": float(r["food"]), "stars": int(r["stars"]), "line": str(r["line"]), "condition": float(p["condition"])}

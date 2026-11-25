extends SceneTree
## Checks Delayed & Lost Trucking (scripts/economy/delayed_lost.gd,
## docs/design.md section 6½), headless, on a flat stand-in for the yard:
##
##   godot --headless --path . --script res://tools/delayed_lost_check.gd
##
## The licence ladder locks tows until three SpudDash runs, and so on up,
## and the window says why; the window and the Surplus counter are on the
## map; offers list their pay, time, truck and the client's line, and the
## pay is in the design's range; taking a tow on foot lends a rollback in a
## free bay (with the logo on its doors) and adds "get in" and "bring it
## back" stops; the tow car is waiting, locked, and the pickup only counts
## once it's strapped on the deck; the drop at the yard pays, counts, takes
## the car and, once you walk off, the lent truck. In your own rollback
## nothing's lent. Freight lends the hauler and a loaded trailer, needs it
## coupled and strapped, pays by the loads still on it at the drop, and
## brings the trailer back. Giving up a job with the truck out of the yard
## costs the tow-back fee. Supply drops from another source are listed and
## lent their truck. The Surplus sells a truck into a bay as yours, and
## refuses once you're out of room. One "DELAYED" line per check; exits
## non-zero with "DELAYED FAIL" lines if any fail. The save file is put back
## as it was.
##
## With `-- --town` it loads the real town instead (a few minutes) and
## checks the module there: the yard's trucks wear the logo, the window
## and the Surplus are in the yard, every freight site and tow address is
## on a street in the play area, and a lent rollback settles upright in its
## bay.

const MAIN_SRC := "extends Node3D\nconst LOCAL_PLAYER_ID := \"local\"\nvar cars: Array[Car] = []\nvar loads: Array = []\n"
const PLAYER_SRC := "extends Node3D\nvar vehicle: Car = null\nvar velocity := Vector3.ZERO\n"

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false
var gs: Node
var main: Node3D
var player: Node3D
var cam: Camera3D
var economy: Economy
var dl: DelayedLost


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("DELAYED ok   %s" % what)
	else:
		_failures += 1
		print("DELAYED FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _script(src: String) -> GDScript:
	var g := GDScript.new()
	g.source_code = src
	g.reload()
	return g


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	gs = root.get_node("GameState")
	_had_save = FileAccess.file_exists("user://savegame.json")
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes("user://savegame.json")
	gs.call("reset_save")
	if OS.get_cmdline_user_args().has("--town"):
		await _town_checks()
		_finish()
		return
	_build()
	await _frames(3)

	_ladder_checks()
	await _tow_checks()
	await _own_truck_checks()
	await _freight_checks()
	await _cancel_checks()
	await _supplies_checks()
	await _surplus_checks()
	_finish()


func _finish() -> void:
	if _had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("DELAYED %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## A flat yard: Main (with its cars), the player, a camera with them, the
## economy's shared pieces and the module.
func _build() -> void:
	main = Node3D.new()
	main.set_script(_script(MAIN_SRC))
	main.name = "FakeMain"
	root.add_child(main)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	ground.collision_layer = Layers.GROUND
	main.add_child(ground)
	player = Node3D.new()
	player.set_script(_script(PLAYER_SRC))
	main.add_child(player)
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var gps := Gps.new()
	root.add_child(gps)
	gps.setup(null, player)
	var hud := Hud.new()
	root.add_child(hud)
	economy = Economy.new()
	root.add_child(economy)
	economy.main = main
	economy.player = player
	economy.hud = hud
	economy.addresses = Addresses.load_for(null)
	economy.owned_cars = OwnedCars.new()
	economy.add_child(economy.owned_cars)
	economy.owned_cars.setup(main, player)
	economy.counters = Counters.new()
	economy.add_child(economy.counters)
	economy.counters.setup(player, hud)
	economy.jobs = Jobs.new()
	economy.add_child(economy.jobs)
	economy.jobs.setup(player, hud)
	dl = DelayedLost.new()
	economy.add_child(dl)
	dl.setup(economy)


## Puts the player (and the camera) at `p`, on foot or in `car`.
func _at(p: Vector3, car: Car = null) -> void:
	player.set("vehicle", car)
	player.global_position = p
	cam.global_position = p + Vector3(0, 6, 12)


## Moves a vehicle and everything riding or coupled on it by the same step.
func _move(bodies: Array, to: Vector3) -> void:
	var d := to - (bodies[0] as Node3D).global_position
	for b: Variant in bodies:
		var n := b as RigidBody3D
		n.global_position += d
		n.linear_velocity = Vector3.ZERO
		n.angular_velocity = Vector3.ZERO
		n.reset_physics_interpolation()


func _item(id_prefix: String) -> Dictionary:
	for it: Dictionary in dl._dispatch_items():
		if str(it["id"]).begins_with(id_prefix):
			return it
	return {}


func _ladder_checks() -> void:
	_check(DelayedLost.licence_why("tow") != "" and DelayedLost.licence_why("freight") != "", "a new player: tows and freight are locked (%s)" % DelayedLost.licence_why("tow"))
	var items := dl._dispatch_items()
	var tows := items.filter(func(i: Dictionary) -> bool: return i.has("job") and str(i["job"]["kind"]) == "tow")
	var locked := _item("locked_tow")
	_check(tows.is_empty() and not locked.is_empty() and not bool(locked.get("enabled", true)) and str(locked["why"]).contains("3 SpudDash runs"), "the window shows the tow licence locked and why: %s" % locked.get("why", ""))
	for i in 3:
		gs.call("add_job_done", "spuddash")
	_check(DelayedLost.licence_why("tow") == "" and DelayedLost.licence_why("supplies").contains("3 tows"), "three SpudDash runs open tows; supplies still need 3 tows (%s)" % DelayedLost.licence_why("supplies"))
	dl._board = []
	var job_item := _item("job_")
	var j: Dictionary = job_item.get("job", {})
	_check(not j.is_empty() and str(j["kind"]) == "tow" and int(j["pay"]) >= 450 and int(j["pay"]) <= 1300, "tows are on offer, paying %s" % CarModels.dollars(int(j.get("pay", 0))))
	_check(str(job_item.get("note", "")).contains("Rollback") and str(job_item.get("note", "")).contains("\"") and str(job_item.get("price_text", "")).begins_with("+$"), "with the truck, the time and the client's line: %s" % str(job_item.get("note", "")).replace("\n", " / "))
	var kinds := dl.counters.map_places().map(func(p: Dictionary) -> String: return str(p["kind"]))
	_check(kinds.has("job_board") and kinds.has("dealer"), "the dispatch window and the Surplus counter are on the map")


func _tow_checks() -> void:
	var a := {"n": "45", "street": "Kent Street", "kind": "home", "x": 70.0, "z": 40.0, "road": Vector2(60, 40), "door": Vector2(70, 40)}
	var job := dl.tow_job(a, true, false)
	_at(dl.point(DelayedLost.WINDOW_AT))
	var why := dl.take(job)
	var active := dl.jobs.active
	_check(why == "" and not active.is_empty(), "taking a tow on foot starts it (%s)" % why)
	if active.is_empty():
		return
	var loans: Array = active["data"]["loans"]
	var truck := loans[0] as Car if loans.size() > 0 else null
	_check(truck != null and truck.model_id == "rollback" and truck.global_position.distance_to(dl.bay_xform(0).origin) < 1.0 and truck.get_node_or_null("DoorLogo") != null,
		"a rollback is lent, in the first bay, with the logo on its doors")
	var stops: Array = active["stops"]
	_check(stops.size() == 3 and str(stops[0]["name"]) == "Get in the truck" and str(stops[2]["name"]).contains("yard"), "stops: get in, pick up, drop at the yard (which is bringing the truck back)")
	var car := active["data"]["car"] as Car
	_check(car != null and car.stalled and not car.can_enter("local") and car.global_position.distance_to(Vector3(60, 0, 40)) < 8.0, "the broken-down car waits at the curb, and won't start")
	await _frames(2)
	_at(truck.global_position, truck)
	await _wait(0.8)
	_check(dl.jobs.index == 1, "getting in the truck: on to the pickup")
	# Drive over (by moving the truck), and the car's not on yet: no pickup.
	_move([truck], car.global_position + Vector3(0, 0.3, -9.0))
	_at(truck.global_position, truck)
	await _wait(2.0)
	_check(dl.jobs.index == 1, "parked by it isn't enough: the car has to be on the deck")
	# Up on the deck and strapped.
	car.global_transform = Transform3D(truck.global_basis, truck.global_transform * Vector3(0, 1.4, 2.4))
	car.linear_velocity = Vector3.ZERO
	await _wait(1.0)
	var n := truck.tie_downs.strap_all()
	_check(n >= 1 and truck.tie_downs.has(car), "strapped on the deck")
	_at(truck.global_position, truck)
	await _wait(2.0)
	_check(dl.jobs.index == 2, "strapped on, deck up: the pickup's done")
	var money := int(gs.get("money"))
	var expect := int(dl.jobs.pay_now().get("pay", 0))
	_move([truck, car], dl.point(DelayedLost.RETURN_AT) + Vector3(0, 0.4, 0))
	_at(truck.global_position, truck)
	await _wait(2.2)
	_check(dl.jobs.active.is_empty() and int(gs.get("money")) - money >= expect - 10 and int(gs.call("jobs_done_count", "tow")) == 1,
		"dropped at the yard: paid %s and counted" % CarModels.dollars(int(gs.get("money")) - money))
	await _frames(2)
	_check(not is_instance_valid(car), "the crew takes the car")
	_check(is_instance_valid(truck), "the truck stays while you're in it")
	_at(truck.global_position + Vector3(90, 0, 0))
	await _wait(1.3)
	_check(not is_instance_valid(truck) and (main.get("cars") as Array).all(func(c: Variant) -> bool: return is_instance_valid(c)), "walk off and the lent truck goes back to the fleet")


func _own_truck_checks() -> void:
	var mine := dl.spawn_truck("rollback", 2)
	mine.garage_id = "test_own"
	await _frames(2)
	_at(mine.global_position, mine)
	var a := {"n": "7", "street": "Queen Street", "kind": "home", "x": -60.0, "z": 50.0, "road": Vector2(-60, 40), "door": Vector2(-60, 50)}
	var why := dl.take(dl.tow_job(a, false, false))
	var active := dl.jobs.active
	_check(why == "" and (active["data"]["loans"] as Array).is_empty() and (active["stops"] as Array).size() == 2, "in your own rollback nothing's lent: pick up, drop")
	var car := active["data"]["car"] as Car
	_check(car != null and not car.stalled and car.global_position.distance_to(Vector3(-60, 0, 40)) > 3.0, "a badly parked car sits up off the street, at an angle")
	dl.jobs.cancel()
	await _frames(2)
	_at(Vector3(200, 0, 200))
	await _wait(1.3)
	_check(not is_instance_valid(car) and is_instance_valid(mine), "given up: the car's taken away, your own truck isn't")
	dl.remove_body(mine)
	await _frames(2)


func _freight_checks() -> void:
	_check(DelayedLost.licence_why("freight").contains("3 supply drops"), "freight waits for supply drops (%s)" % DelayedLost.licence_why("freight"))
	for i in 3:
		gs.call("add_job_done", "supplies")
	_check(DelayedLost.licence_why("freight") == "", "three supply drops open freight")
	var site := {"name": "Test Megastore", "client": "Receiving", "lines": ["Pallets."]}
	var job := dl.freight_job(site, Vector3(120, 0, -80), false)
	_check(int(job["pay"]) >= 500 and int(job["pay"]) <= 1500, "freight pays %s" % CarModels.dollars(int(job["pay"])))
	_at(dl.point(DelayedLost.WINDOW_AT))
	var why := dl.take(job)
	var active := dl.jobs.active
	_check(why == "" and not active.is_empty(), "taking freight on foot starts it (%s)" % why)
	if active.is_empty():
		return
	var loans: Array = active["data"]["loans"]
	var hauler := loans[0] as Car
	var trailer := active["data"]["trailer"] as Car
	var loads: Array = active["data"]["loads"]
	var count := int(active["data"]["count"])
	_check(hauler.model_id == "hauler" and trailer != null and trailer.model_id == "flatbed_trailer" and loads.size() == count and (active["stops"] as Array).size() == 4,
		"a hauler and a trailer with %d loads on it are lent; stops: get in, hook up, deliver, bring it back" % count)
	await _wait(1.5)
	_check(dl.loads_on(active) == count, "the loads are on the trailer's deck (%d)" % dl.loads_on(active))
	_at(hauler.global_position, hauler)
	await _wait(0.8)
	_check(dl.jobs.index == 1, "in the hauler: on to hooking up")
	# Back under the trailer: the fifth wheel under its kingpin.
	hauler.global_transform = Transform3D(trailer.global_basis, hauler.global_position)
	hauler.global_position += (trailer.model_point("kingpin") as Vector3) - (hauler.model_point("hitch") as Vector3)
	hauler.reset_physics_interpolation()
	Coupling.couple(hauler, trailer)
	_at(hauler.global_position, hauler)
	await _wait(1.5)
	_check(dl.jobs.index == 1, "coupled but not strapped: not yet")
	var n := trailer.tie_downs.strap_all()
	await _wait(1.5)
	_check(n == count and dl.jobs.index == 2, "strapped down (%d): on the road" % n)
	# Lose one on the way.
	var lost := loads[0] as Cargo
	trailer.tie_downs.release(lost)
	lost.global_position = trailer.global_position + trailer.global_basis.x * 6.0
	lost.reset_physics_interpolation()
	var bodies: Array = [hauler, trailer]
	for l: Variant in loads:
		if l != lost:
			bodies.append(l)
	_move(bodies, Vector3(120, 1.0, -80))
	_at(hauler.global_position, hauler)
	await _wait(2.5)
	_check(dl.jobs.index == 3 and int(active["data"].get("delivered", -1)) == count - 1, "delivered with one lost: %d of %d count" % [int(active["data"].get("delivered", -1)), count])
	await _frames(2)
	var left := 0
	for l: Variant in loads:
		if is_instance_valid(l):
			left += 1
	_check(left == 1, "the delivered loads are taken off; the lost one's still lying back there")
	var money := int(gs.get("money"))
	var expect := int(dl.jobs.pay_now().get("pay", 0))
	_check(absf(float(dl.jobs.pay_now()["condition"]) - float(count - 1) / count) < 0.01, "pay goes by what arrived (condition %.2f)" % float(dl.jobs.pay_now()["condition"]))
	_move([hauler, trailer], dl.point(DelayedLost.RETURN_AT) + Vector3(0, 1.0, 0))
	_at(hauler.global_position, hauler)
	await _wait(2.0)
	_check(dl.jobs.active.is_empty() and int(gs.get("money")) - money >= expect - 10 and int(gs.call("jobs_done_count", "freight")) == 1, "trailer back at the yard: paid %s" % CarModels.dollars(int(gs.get("money")) - money))
	_at(Vector3(-200, 0, 200))
	await _wait(1.3)
	_check(not is_instance_valid(hauler) and not is_instance_valid(trailer) and not is_instance_valid(lost), "walk off: the hauler, the trailer and the lost load are cleared away")


func _cancel_checks() -> void:
	var a := {"n": "9", "street": "Kent Street", "kind": "home", "x": 150.0, "z": 150.0, "road": Vector2(150, 140), "door": Vector2(150, 150)}
	_at(dl.point(DelayedLost.WINDOW_AT))
	gs.call("add_money", 1000)
	dl.take(dl.tow_job(a, true, false))
	var truck := (dl.jobs.active["data"]["loans"] as Array)[0] as Car
	_move([truck], Vector3(150, 0.4, 120))
	_at(truck.global_position, truck)
	await _frames(2)
	var money := int(gs.get("money"))
	dl.jobs.cancel()
	_check(money - int(gs.get("money")) == DelayedLost.RETURN_FEE, "given up with the truck out of the yard: towed back for %s" % CarModels.dollars(DelayedLost.RETURN_FEE))
	_at(Vector3(-200, 0, -200))
	await _wait(1.3)
	_check(not is_instance_valid(truck), "and it's gone once you're out of it")


func _supplies_checks() -> void:
	gs.call("add_job_done", "tow")
	gs.call("add_job_done", "tow")
	_check(DelayedLost.licence_why("supplies") == "", "three tows open supply drops")
	dl.jobs.add_source("supplies", func(_near: Vector3, _n: int) -> Array:
		return [{"kind": "supplies", "company": DelayedLost.COMPANY, "title": "Lumber to 12 Elm Avenue", "truck": "rollback", "pay": 700, "estimate": 400.0,
			"needs": func(p: Node3D) -> String: return "" if p.get("vehicle") != null else "You need the crane truck.",
			"stops": [{"name": "Drop", "at": Vector3(-150, 0, 100)}]}])
	dl._board = []
	var it := {}
	for i: Dictionary in dl._dispatch_items():
		if i.has("job") and str(i["job"]["kind"]) == "supplies":
			it = i
	_check(not it.is_empty(), "supply drops from their own source are on the window")
	if it.is_empty():
		return
	_at(dl.point(DelayedLost.WINDOW_AT))
	var why := dl.take(it["job"])
	var stops: Array = dl.jobs.active.get("stops", [])
	_check(why == "" and (dl.jobs.active["data"]["loans"] as Array).size() == 1 and stops.size() == 3 and str(stops[2]["name"]) == "Bring the truck back",
		"taking one lends its truck, even though its own check wants you in it (%s)" % why)
	var truck := (dl.jobs.active["data"]["loans"] as Array)[0] as Car
	dl.jobs.cancel()
	await _frames(2)
	_at(Vector3(-200, 0, -200))
	await _wait(1.3)
	_check(not is_instance_valid(truck), "given up in the yard: no fee, the truck goes back")


func _surplus_checks() -> void:
	gs.call("reset_save")
	gs.call("add_money", 30000)
	_at(dl.point(DelayedLost.SURPLUS_AT))
	await _frames(3)
	_check(dl.counters.near() == "delayed_lost_surplus", "at the Surplus counter")
	dl.counters.open_card("delayed_lost_surplus")
	var items: Array = dl.counters.menu.items
	var rb := {}
	for i: Dictionary in items:
		if str(i["id"]) == "rollback":
			rb = i
	_check(not rb.is_empty() and bool(rb.get("enabled", true)) and int(rb["price"]) == 24000, "a retired rollback for %s" % CarModels.dollars(int(rb.get("price", 0))))
	dl.counters._on_chosen("delayed_lost_surplus", rb)
	var vs: Array = gs.get("vehicles")
	var car := economy.owned_cars.car_for(str(vs[0]["id"])) if vs.size() == 1 else null
	_check(vs.size() == 1 and str(vs[0]["model"]) == "rollback" and int(gs.get("money")) == 6000 and car != null and car.can_enter("local"), "bought: yours, in a bay, $6,000 left")
	var again := {}
	for i: Dictionary in dl.counters.menu.items:
		if str(i["id"]) == "forklift":
			again = i
	_check(not bool(again.get("enabled", true)) and str(again.get("why", "")).contains("No room"), "out of room: the rest say so (%s)" % again.get("why", ""))
	dl.counters.menu.close()
	gs.call("reset_save")


func _town_checks() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await process_frame
	var world: WorldBuilder = m.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	dl = DelayedLost.find(self)
	_check(dl != null, "the module is set up under Economy")
	if dl == null:
		return
	var p: Node3D = m.get_node("Player")
	p.global_position = dl.point(DelayedLost.WINDOW_AT, 1.0)
	m.get_node("CameraRig").call("snap_to_target")
	await world.streamer.prime(Vector2(dl.yard.origin.x, dl.yard.origin.z), 150.0)
	await _frames(240)
	var logos := 0
	for c: Car in m.get("cars"):
		if str(c.name).begins_with("Yard_") and c.get_node_or_null("DoorLogo") != null:
			logos += 1
	_check(logos == 2, "the yard's hauler and rollback wear the logo (%d)" % logos)
	_check(dl.point(DelayedLost.WINDOW_AT).distance_to(dl.yard.origin) < 30.0 and world.is_in_play_area(Vector2(dl.yard.origin.x, dl.yard.origin.z)), "the window is in the yard, in the play area")
	for s: Dictionary in DelayedLost.SITES:
		var at := dl.site_point(s)
		var on := world.network.nearest_on_streets(Vector2(at.x, at.z), 5.0) if at != Vector3.INF else {}
		_check(at != Vector3.INF and not on.is_empty() and world.is_in_play_area(Vector2(at.x, at.z)),
			"%s: a drop on %s, %d m from the yard" % [s["name"], str((on.get("edge") as RoadNetwork.RoadEdge).name) if not on.is_empty() else "nothing", roundi(at.distance_to(dl.yard.origin))])
	var offers := dl._tow_offers(dl.yard.origin, 6)
	var ok := offers.size() == 6
	for j: Dictionary in offers:
		var a: Dictionary = j["data"]["address"]
		ok = ok and not world.network.nearest_on_streets(a["road"], 30.0).is_empty()
	_check(ok, "tow offers come from real addresses on streets (%s)" % (Addresses.text(offers[0]["data"]["address"]) if not offers.is_empty() else ""))
	var bay := dl.free_bay()
	var t := dl.spawn_truck("rollback", bay) if bay >= 0 else null
	await _frames(240)
	_check(t != null and t.global_basis.y.dot(Vector3.UP) > 0.97 and t.global_position.distance_to(dl.bay_xform(bay).origin) < 1.5 and t.wheels_down >= 4,
		"a lent rollback settles upright in bay %d" % (bay + 1))
	m.queue_free()
	await _frames(2)

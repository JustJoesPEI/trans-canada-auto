extends SceneTree
## Checks the custom shop and the used lot (scripts/economy/custom_shop.gd,
## used_lot.gd; docs/design.md section 6½), headless and without the town:
##
##   godot --headless --path . --script res://tools/custom_shop_check.gd
##
## An upgrade bought at the card is paid for, saved in the vehicle's mods,
## changes how it drives and comes back on the next spawn; engine stages go
## in order; Maple Tire kits are fitted for the labour; the winch, the horn
## and paint stick; tyres matter in the mud; a car you don't own gets
## nothing; work trucks take the truck upgrades only; used cars are cheap;
## selling pays and lets the car go. One "SHOP" line per check; exits
## non-zero with "SHOP FAIL" lines if any fail. The save file is put back
## exactly as it was.

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false
var gs: Node
var economy: Economy
var shop: CustomShop
var who: Node3D
var main: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("SHOP ok   %s" % what)
	else:
		_failures += 1
		print("SHOP FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## A stand-in for Main (seat_player, unseat_player) and the player (vehicle).
func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


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
	(gs.get_script() as GDScript).set("property_spaces", {"test_garage": 6})
	gs.call("add_property", "test_garage")

	await _make_town()
	await _upgrade_checks()
	await _not_owned_checks()
	await _truck_checks()
	_used_lot_checks()
	await _sell_checks()

	# Put the save back as it was.
	main.queue_free()
	economy.queue_free()
	await _frames(2)
	if _had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("SHOP %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _make_town() -> void:
	main = _script("extends Node3D\nvar player\nfunc seat_player(car):\n\tplayer.vehicle = car\nfunc unseat_player():\n\tplayer.vehicle = null\n").new()
	main.name = "FakeMain"
	root.add_child(main)
	who = _script("extends Node3D\nvar vehicle = null\n").new()
	main.add_child(who)
	main.set("player", who)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	ground.collision_layer = Layers.GROUND
	main.add_child(ground)
	var hud := Hud.new()
	root.add_child(hud)
	economy = Economy.new()
	root.add_child(economy)
	economy.main = main
	economy.player = who
	economy.hud = hud
	economy.owned_cars = OwnedCars.new()
	economy.add_child(economy.owned_cars)
	economy.owned_cars.setup(main, who)
	economy.counters = Counters.new()
	economy.add_child(economy.counters)
	economy.counters.setup(who, hud)
	shop = CustomShop.new()
	economy.add_child(shop)
	shop.setup(economy)
	await _frames(2)


## A new car of `model` bought and adopted at x.
func _buy(model: String, x: float) -> Car:
	var car := Car.new()
	car.model_id = model
	car.paint = Color(0.3, 0.3, 0.3)
	main.add_child(car)
	car.global_position = Vector3(x, 0.8, 0)
	await _frames(2)
	economy.owned_cars.adopt(car)
	return car


func _find(id: String) -> Dictionary:
	for it: Dictionary in economy.counters.menu.items:
		if str(it.get("id", "")) == id:
			return it
	return {}


## Picks item `id` on the open card, as the player would.
func _pick(id: String) -> void:
	var it := _find(id)
	if it.is_empty():
		print("  (no item %s on the card: %s)" % [id, ", ".join(economy.counters.menu.items.map(func(i: Dictionary) -> String: return str(i.get("id", ""))))])
		return
	economy.counters._on_chosen(CustomShop.COUNTER_ID, it)
	await _frames(1)


func _torque(car: Car) -> float:
	var best := 0.0
	for pt: Array in car.spec["engine"]["torque"]:
		best = maxf(best, float(pt[1]))
	return best


func _mods(id: String) -> Dictionary:
	return (gs.call("vehicle", id) as Dictionary).get("mods", {})


func _upgrade_checks() -> void:
	var car := await _buy("civique", 0.0)
	var id := car.garage_id
	var stock_torque := _torque(car)
	who.set("vehicle", car)
	gs.call("add_money", 100000)
	economy.counters.open_card(CustomShop.COUNTER_ID)
	_check(economy.counters.menu.visible and not _find("page_engine").is_empty() and not _find("page_paint").is_empty() and not _find("winch").is_empty(),
		"in your own car the card opens on the upgrades (%d items)" % economy.counters.menu.items.size())
	await _pick("page_engine")
	var s3 := _find("stage3")
	_check(not s3.is_empty() and not bool(s3.get("enabled", true)), "stage 3 waits for stage 2 (%s)" % str(s3.get("why", "")))
	var s1 := _find("stage1")
	_check(str(s1.get("note", "")).contains("hp") and str(s1.get("note", "")).contains("→"), "the card shows the change: %s" % str(s1.get("note", "")))
	var money0 := int(gs.get("money"))
	await _pick("stage1")
	car = economy.owned_cars.car_for(id)
	var mods := _mods(id)
	_check(int(gs.get("money")) == money0 - 3000 and str(mods.get("engine", "")) == "stage1" and (mods.get("parts", []) as Array).has("intake_exhaust") and int(mods.get("spent", 0)) == 3000,
		"stage 1: paid $3,000 and saved in the mods (%s)" % str(mods.get("parts", [])))
	_check(car != null and car.parts.has("intake_exhaust") and _torque(car) > stock_torque * 1.05, "the car's rebuilt with it: torque %.0f → %.0f N·m" % [stock_torque, _torque(car)])
	_check(who.get("vehicle") == car and economy.counters.menu.visible and economy.counters.menu._message.text.contains("fitted"),
		"you're back in the seat with the card up: %s" % economy.counters.menu._message.text)
	await _pick("stage2")
	car = economy.owned_cars.car_for(id)
	_check(car.parts.has("engine_tune") and car.parts.has("intake_exhaust"), "stage 2 on top of stage 1 (%s)" % str(car.parts))
	await _pick("back")
	# Tyres, with a Maple Tire kit.
	gs.call("add_item", "all_terrain_tyres", 1)
	await _pick("page_tyres")
	var at := _find("all_terrain")
	_check(int(at.get("price", 0)) == 250 and str(at.get("note", "")).contains("kit"), "a kit from Maple Tire is fitted for the labour ($%d)" % int(at.get("price", 0)))
	var mud0 := CustomShop.stats(car.model_id, car.parts)
	await _pick("all_terrain")
	car = economy.owned_cars.car_for(id)
	var mud1 := CustomShop.stats(car.model_id, car.parts)
	_check(int(gs.call("item_count", "all_terrain_tyres")) == 0 and float(car.spec["tyres"]["offroad"]) > 0.4 and int(mud1["mud"]) > int(mud0["mud"]) + 10,
		"all-terrain tyres: the kit's used up, grip in mud %d%% → %d%%" % [int(mud0["mud"]), int(mud1["mud"])])
	car._kind[0] = GroundMap.FIELD
	var field_grip := car._ground_grip(0)
	_check(field_grip > float(GroundMap.KINDS[GroundMap.FIELD]["grip"]) + 0.2, "and the car grips a field better (%.2f against %.2f)" % [field_grip, float(GroundMap.KINDS[GroundMap.FIELD]["grip"])])
	car._kind[0] = GroundMap.PAVED
	await _pick("back")
	# The winch, the horn, paint.
	_check(not car.has_winch(), "a Civique has no winch")
	await _pick("winch")
	car = economy.owned_cars.car_for(id)
	_check(car.has_winch() and bool(_mods(id).get("winch", false)) and not CarModels.shape_for("civique").get("winch", false),
		"a winch fitted: this car has one, other Civiques don't")
	await _pick("page_horn")
	await _pick("horn_air")
	car = economy.owned_cars.car_for(id)
	var audio: CarAudio = null
	for c in car.get_children():
		if c is CarAudio:
			audio = c
	_check(audio != null and audio._horn_kind == "air", "an air horn fitted (%s)" % (audio._horn_kind if audio != null else "no audio"))
	await _pick("back")
	await _pick("page_paint")
	await _pick("paint_lupin_purple")
	car = economy.owned_cars.car_for(id)
	var purple := Color.html("#6b4a9a")
	_check(car.paint.is_equal_approx(purple) and Color.html(str((gs.call("vehicle", id) as Dictionary)["paint"])).is_equal_approx(purple), "painted Lupin Purple, saved")
	economy.counters.menu.close()
	_check(shop.page == "main", "closing the card goes back to its first page")
	# Next session: all of it comes back from the save.
	var spent := int(_mods(id).get("spent", 0))
	who.set("vehicle", null)
	economy.owned_cars.queue_free()
	car.queue_free()
	await _frames(2)
	var again := OwnedCars.new()
	economy.add_child(again)
	economy.owned_cars = again
	shop.economy.owned_cars.spawned.connect(shop.apply_mods)
	again.setup(main, who)
	var back := again.car_for(id)
	audio = null
	if back != null:
		for c in back.get_children():
			if c is CarAudio:
				audio = c
	_check(back != null and back.parts.has("engine_tune") and back.parts.has("all_terrain_tyres") and _torque(back) > stock_torque * 1.1 and back.has_winch()
		and back.paint.is_equal_approx(purple) and audio != null and audio._horn_kind == "air",
		"next session: engine, tyres, winch, horn and paint all come back (spent $%d)" % spent)
	_check(spent == 3000 + 7500 + 250 + CustomShop.WINCH_PRICE + 650 + CustomShop.PAINT_PRICE, "what was spent is kept, for the resale ($%d)" % spent)


func _not_owned_checks() -> void:
	var stranger := Car.new()
	stranger.model_id = "corollary"
	main.add_child(stranger)
	stranger.global_position = Vector3(-20, 0.8, 0)
	await _frames(2)
	who.set("vehicle", stranger)
	var money0 := int(gs.get("money"))
	economy.counters.open_card(CustomShop.COUNTER_ID)
	var items := economy.counters.menu.items
	_check(items.size() == 1 and not bool((items[0] as Dictionary).get("enabled", true)), "a car you don't own: nothing on the card but why")
	economy.counters._on_chosen(CustomShop.COUNTER_ID, items[0])
	_check(int(gs.get("money")) == money0 and economy.counters.menu._message.text.contains("own"), "and nothing's charged: %s" % economy.counters.menu._message.text)
	economy.counters.menu.close()
	_check((gs.get("vehicles") as Array).size() == 1, "nor is it adopted")
	who.set("vehicle", null)
	stranger.queue_free()


func _truck_checks() -> void:
	var truck := await _buy("rollback", 30.0)
	var id := truck.garage_id
	var t0 := _torque(truck)
	who.set("vehicle", truck)
	economy.counters.open_card(CustomShop.COUNTER_ID)
	_check(not _find("page_engine").is_empty() and not _find("page_tyres").is_empty() and _find("page_suspension").is_empty() and not _find("page_paint").is_empty(),
		"a work truck: engine, tyres and paint, no car suspension")
	await _pick("page_tyres")
	_check(_find("performance").is_empty() and not _find("mud").is_empty(), "truck tyres: mud tyres, not street ones")
	await _pick("back")
	await _pick("page_engine")
	await _pick("stage1")
	truck = economy.owned_cars.car_for(id)
	_check(truck != null and _torque(truck) > t0 * 1.05, "a truck's engine stage 1: torque %.0f → %.0f N·m" % [t0, _torque(truck)])
	await _pick("back")
	await _pick("page_paint")
	var p := _find("paint_highway_yellow")
	_check(int(p.get("price", 0)) == CustomShop.PAINT_PRICE_TRUCK, "a truck respray costs more ($%d)" % int(p.get("price", 0)))
	await _pick("paint_highway_yellow")
	truck = economy.owned_cars.car_for(id)
	_check(truck.paint.is_equal_approx(Color.html("#e0b81c")), "and it's yellow")
	economy.counters.menu.close()
	who.set("vehicle", null)


func _used_lot_checks() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_config.json"))
	var used: Dictionary = cfg["landmarks"]["695948071"].get("used_lot", {})
	var stock: Array = used.get("stock", [])
	_check(not stock.is_empty(), "Reliable Motors has a used lot (%d models)" % stock.size())
	var lo := 1 << 30
	var hi := 0
	var dearer := 0
	for m: Variant in stock:
		_check(StreetProps.PARKED_MODELS.has(str(m)), "%s can stand on a lot" % str(m))
		for i in 40:
			var price := UsedLot.used_price(str(m), Vector3(i * 2.9, 0.0, i * 6.4))
			lo = mini(lo, price)
			hi = maxi(hi, price)
			if price >= CarModels.price(str(m)):
				dearer += 1
	_check(lo >= 3000 and hi <= 8000 and dearer == 0, "used cars are %s to %s, all less than new" % [CarModels.dollars(lo), CarModels.dollars(hi)])
	var hit := {"model_id": "filly", "used": true, "at": Vector3(12.3, 0, 45.6)}
	_check(UsedLot.sale_price(hit) == UsedLot.sale_price(hit.duplicate()) and UsedLot.sale_prompt(hit).contains("km"), "the same car, the same price: %s" % UsedLot.sale_prompt(hit))
	_check(UsedLot.sale_price({"model_id": "rammer", "used": false}) == CarModels.price("rammer"), "a new car is still the dealer's price")


func _sell_checks() -> void:
	var car := await _buy("cavalcade", -40.0)
	var id := car.garage_id
	gs.call("set_vehicle", id, {"mods": {"paid": 4495}})
	var value := UsedLot.sale_value(id)
	_check(value == 2250, "a $4,495 beater sells for half (%s)" % CarModels.dollars(value))
	who.set("vehicle", car)
	economy.counters.open_card(CustomShop.COUNTER_ID)
	await _pick("page_sell")
	var money0 := int(gs.get("money"))
	var n0 := (gs.get("vehicles") as Array).size()
	await _pick("sell")
	_check(int(gs.get("money")) == money0 + value and (gs.get("vehicles") as Array).size() == n0 - 1 and (gs.call("vehicle", id) as Dictionary).is_empty(),
		"sold: paid %s and it's gone from the save" % CarModels.dollars(value))
	_check(car.garage_id == "" and car.owner_id == "dealer" and who.get("vehicle") == null and not economy.counters.menu.visible, "you're out, and it's the shop's now")

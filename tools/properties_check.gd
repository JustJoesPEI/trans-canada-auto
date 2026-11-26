extends SceneTree
## Checks property (scripts/economy/properties.gd, docs/design.md section
## 6½): loads the town, then
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/properties_check.gd
##
## a parkade pass and the Gamma Prince Edward suite are sold at their
## counters, charged for, refused when you're short, and add their spaces;
## the suite is made home and the start moves to the garage under the
## hotel; a car is stored in your stall and shown there, each keeps its
## stall; the valet brings a car round to the curb near you for the fee;
## the Garage app lists it all; the save keeps it; and a car can be driven
## in off Queen Street, down the ramp and into the garage. One "PROPERTY"
## line per check; exits non-zero with "PROPERTY FAIL" lines if any fail.
## The save file is put back exactly as it was.

const SAVE := "user://savegame.json"

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false
var _main: Node
var _world: WorldBuilder
var _player: Node3D
var _props: Properties
var _eco: Economy
var _gs: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PROPERTY ok   %s" % what)
	else:
		_failures += 1
		print("PROPERTY FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_gs = root.get_node("GameState")
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SAVE)
	_gs.call("reset_save")

	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	for i in 5:
		await process_frame
	_player = _main.get_node("Player")
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_eco = Economy.find(self)
	_props = Properties.find(self)
	_check(_eco != null and _props != null, "the Properties module is set up under Economy")
	if _props == null:
		_finish()
		return

	await _buying()
	await _home()
	await _storing()
	await _valet()
	_tab()
	_save()
	await _drive_in()
	_finish()


func _finish() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_gs.call("load_game")
	print("PROPERTY %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Chooses item `item_id` on counter `counter` as the player would.
func _choose(counter: String, item_id: String) -> void:
	var c := _eco.counters
	c.open_card(counter)
	for it: Dictionary in c.menu.items:
		if str(it.get("id", "")) == item_id:
			c.call("_on_chosen", counter, it)
			break
	c.menu.close()


func _buying() -> void:
	_check(int(_gs.call("storage_spaces")) == 1, "one space to start with (the street)")
	for id: String in Properties.PLACES:
		_check(_eco.counters.has("property_" + id) and Properties.desk_point(_world, id) != Vector3.INF,
			"%s has its counter (%s)" % [Properties.PLACES[id]["name"], Properties.desk_point(_world, id)])
	_gs.set("money", 6000)
	_choose("property_queen_parkade", "buy")
	_check(bool(_gs.call("owns_property", "queen_parkade")) and int(_gs.get("money")) == 1000,
		"a Queen Parkade pass is bought for %s" % CarModels.dollars(int(Properties.PLACES["queen_parkade"]["price"])))
	_check(int(_gs.call("storage_spaces")) == 1 + int(Properties.PLACES["queen_parkade"]["spaces"]), "the pass adds its spaces (%d now)" % int(_gs.call("storage_spaces")))
	_choose("property_gamma_suite", "buy")
	_check(not bool(_gs.call("owns_property", "gamma_suite")) and int(_gs.get("money")) == 1000, "the suite is refused when you're short")
	_gs.set("money", 50000)
	_choose("property_gamma_suite", "buy")
	_check(bool(_gs.call("owns_property", "gamma_suite")) and int(_gs.get("money")) == 10000, "the suite is bought for %s" % CarModels.dollars(40000))
	_check(int(_gs.call("storage_spaces")) == 8, "the suite adds 4 spaces (8 now)")
	await _frames(2)
	_check(_props.get("_marks").has("gamma_suite") and _props.get("_marks").has("queen_parkade"), "your stalls are marked")


func _home() -> void:
	_check(str(_gs.get("home")) == "gamma_suite", "the first suite becomes home")
	var lay := Properties.layout_of(_world, "gamma_suite")
	_check(not lay.is_empty(), "the garage under the Gamma Prince Edward is found")
	var spawn := _world.get_spawn()
	_check(UndergroundGarage.contains(lay, spawn.origin, 0.5), "you start in the garage under the hotel (%s)" % spawn.origin)
	_gs.call("set_home", "queen_parkade")
	var s2 := _world.get_spawn()
	_check(_props.is_at("queen_parkade", s2.origin), "made home, a parkade pass moves the start there (%s)" % s2.origin)
	_choose("property_gamma_suite", "home")
	_check(str(_gs.get("home")) == "gamma_suite", "the front desk makes the suite home again")


func _storing() -> void:
	var owned := _eco.owned_cars
	var vid: String = _gs.call("add_vehicle", "civique", Color(0.2, 0.4, 0.8))
	var desk := Properties.desk_point(_world, "gamma_suite")
	var car := owned.spawn(vid, _props.curb_spot(desk))
	_check(car != null, "a car of yours is out on the street")
	_check(_props.store(vid, "gamma_suite"), "it's stored at the suite")
	var v: Dictionary = _gs.call("vehicle", vid)
	_check(str(v.get("stored", "")) == "gamma_suite" and Properties.stored_at("gamma_suite").has(vid), "the save says it's in the garage")
	# Near the garage it's shown in its stall.
	_player.global_position = Properties.aisle_xform(_world, "gamma_suite", 0).origin
	_props.call("_process", 0.016)
	await _frames(2)
	var shown := owned.car_for(vid)
	var stall := Properties.stall_xform(_world, "gamma_suite", 0).origin
	_check(shown != null and shown.global_position.distance_to(stall) < 1.5, "near the garage it's parked in your first stall")
	_check(str((_gs.call("vehicle", vid) as Dictionary).get("stored", "")) == "gamma_suite", "shown, it's still stored")
	# Far away it's put away again.
	_player.global_position = stall + Vector3(400, 0, 0)
	_props.call("_process", 0.016)
	await _frames(2)
	_check(owned.car_for(vid) == null and str((_gs.call("vehicle", vid) as Dictionary).get("stored", "")) == "gamma_suite", "far away it's off the street, still stored")
	# Full: a fifth car won't fit in four stalls.
	var extra: Array[String] = []
	for i in 3:
		var x: String = _gs.call("add_vehicle", "civique", Color.WHITE)
		extra.append(x)
		_props.store(x, "gamma_suite")
	var fifth: String = _gs.call("add_vehicle", "pony_gt", Color.RED)
	_check(not _props.store(fifth, "gamma_suite") and Properties.stored_at("gamma_suite").size() == 4, "a fifth won't fit in the suite's four stalls")
	# One taken away: the next stored takes its stall, and nobody moves.
	_eco.owned_cars.release(extra[0])
	_check(_props.store(fifth, "gamma_suite") and Properties.stall_of(fifth, "gamma_suite") == 1 and Properties.stall_of(vid, "gamma_suite") == 0 \
		and Properties.stall_of(extra[1], "gamma_suite") == 2 and Properties.stall_of(extra[2], "gamma_suite") == 3,
		"each stored car keeps its stall; a freed one is used again")
	for x in [extra[1], extra[2], fifth]:
		_eco.owned_cars.release(x)
	# In a car at your stalls, the counter offers to store it.
	_player.global_position = Properties.aisle_xform(_world, "gamma_suite", 1).origin
	var items: Array = _props.call("_stall_items", "gamma_suite")
	_check(not items.is_empty() and not bool(items[0].get("enabled", true)), "on foot, the stalls' card won't store a car (%s)" % str(items[0].get("why", "")))


func _valet() -> void:
	var owned := _eco.owned_cars
	var vid: String = Properties.stored_at("gamma_suite")[0]
	var here := _world.get_spawn().origin
	# Out on Queen Street, by the Queen Parkade.
	var q := Properties.desk_point(_world, "queen_parkade")
	_player.global_position = q
	_gs.set("money", 1000)
	var car := _props.bring_round(vid)
	_check(car != null and car.global_position.distance_to(q) < 80.0, "the valet brings it to the curb near you (%.0f m away)" % (car.global_position.distance_to(q) if car != null else -1.0))
	_check(int(_gs.get("money")) == 1000 - Properties.VALET_FEE, "for the fee (%s)" % CarModels.dollars(Properties.VALET_FEE))
	_check(str((_gs.call("vehicle", vid) as Dictionary).get("stored", "x")) == "", "brought round, it's no longer stored")
	_gs.set("money", 10)
	_check(_props.bring_round(vid) == null or owned.car_for(vid) != null, "short of the fee, nothing happens")
	_check(int(_gs.get("money")) == 10, "and nothing's charged")
	# Store it again at the parkade, from there.
	_check(_props.store(vid, "queen_parkade") and Properties.stored_at("queen_parkade").has(vid), "stored at the Queen Parkade pass")
	_check(_props.where_text(vid).contains("Queen Parkade"), "the Garage app says where (%s)" % _props.where_text(vid))
	_player.global_position = here


func _tab() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	_props.call("_build_tab", box)
	var text := ""
	for n in box.get_children():
		if n is Label:
			text += (n as Label).text + "\n"
		elif n is HBoxContainer or n is HFlowContainer:
			for b in n.get_children():
				if b is Button:
					text += "[%s] " % (b as Button).text
			text += "\n"
	_check(text.contains("Garage: 1 of 8 spaces") and text.contains("Stored at Queen Parkade") and text.contains("Bring it round"), "the Garage app lists your car, where it is and the valet")
	_check(text.contains("Suite at the Gamma Prince Edward (home)"), "and your places, with home")
	box.queue_free()


func _save() -> void:
	var vid: String = (_gs.get("vehicles") as Array)[0]["id"]
	_gs.call("save_game")
	_gs.call("load_game")
	_check((_gs.get("properties") as Array).has("queen_parkade") and (_gs.get("properties") as Array).has("gamma_suite"), "the save keeps your places")
	_check(str(_gs.get("home")) == "gamma_suite", "and home")
	_check(str((_gs.call("vehicle", vid) as Dictionary).get("stored", "")) == "queen_parkade", "and where your car is stored")
	Properties.register_spaces()
	_check(int(_gs.call("storage_spaces")) == 8, "and the spaces")


## A car driven off Queen Street, over the driveway, through the opening,
## down the ramp and into the aisle in front of the suite's stalls.
func _drive_in() -> void:
	var lay := Properties.layout_of(_world, "gamma_suite")
	var c: Vector2 = lay["c"]
	var u: Vector2 = lay["u"]
	var hall: Array = lay["hall"]
	var street := c - u * 14.0
	var flat := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
	var goal := Properties.aisle_xform(_world, "gamma_suite", 1).origin
	_player.global_position = Vector3(street.x, _world.terrain.h2(street) + 2.0, street.y)
	await _world.streamer.prime(street, 120.0)
	await _frames(30)
	var car := Car.new()
	car.model_id = "civique"
	_main.add_child(car)
	var y := _world.terrain.h2(street)
	var hit := car.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(street.x, y + 5, street.y), Vector3(street.x, y - 5, street.y), Layers.GROUND))
	if not hit.is_empty():
		y = (hit["position"] as Vector3).y
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-u.x, -u.y)), Vector3(street.x, y + 0.4, street.y))
	car.reset_physics_interpolation()
	var ap := CarAutopilot.new()
	ap.network = _world.network
	car.add_child(ap)
	await physics_frame
	var line := PackedVector2Array([street, c - u * 4.0, c + u * 3.0, c + u * float(hall[1]), c + u * (float(hall[1]) + 2.5), flat.call(goal)])
	ap.drive_route(StreetRoute.along(line, {"top_speed": 4.0}), 0.0, goal)
	var t := 0.0
	var inside := false
	while t < 60.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		_player.global_position = car.global_position + Vector3.UP * 2.0
		if UndergroundGarage.contains(lay, car.global_position) and car.global_position.distance_to(goal) < 4.0 and absf(car.speed) < 0.5:
			inside = true
			break
	var up := car.global_basis.y.dot(Vector3.UP)
	_check(inside and up > 0.9, "a car drives in off Queen Street and down the ramp to the suite's stalls (%.0f s, %.1f m from the aisle spot, %s)" % [t, car.global_position.distance_to(goal), car.global_position])
	# Parked there, the stalls' card stores it.
	var vid: String = _eco.owned_cars.adopt(car)
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.call("enter_vehicle", car)
	await process_frame
	_player.global_position = car.global_position
	await process_frame
	_check(_eco.counters.near() == "stalls_gamma_suite", "in the garage in your car, the stalls' card is the one to hand (%s)" % _eco.counters.near())
	_choose("stalls_gamma_suite", "store")
	await _frames(2)
	_check(_player.get("vehicle") == null and Properties.stored_at("gamma_suite").has(vid), "choosing \"Store this car\" gets you out and stores it")
	var shown := _eco.owned_cars.car_for(vid)
	_check(shown != null and shown.global_position.distance_to(Properties.stall_xform(_world, "gamma_suite", 0).origin) < 1.5, "and it's parked in your stall")

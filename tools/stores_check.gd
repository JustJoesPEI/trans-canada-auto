extends SceneTree
## Checks the stores (scripts/economy/stores.gd, armour.gd; docs/design.md
## section 6½), headless:
##
##   godot --headless --path . --script res://tools/stores_check.gd
##
## Ervin's: paint fills the hoppers, Mustard Pickles and markers are sold and
## owned, armour plates go on (three at most) and are kept in the save.
## Armour takes paint hits before the pips (a head hit breaks two), not
## outside events, and the HUD's bar flashes when one breaks. Maple Tire:
## gear goes into the items for the custom shop, the recovery strap works
## at once and only one is sold, Maple Money comes back on the cash paid,
## is spent before cash and shows on the card, and the save keeps it. Every
## Ervin's and the Maple Tire are found in the real map data, with the
## counter outside the building. One "STORES" line per check; exits
## non-zero with "STORES FAIL" lines if any fail. The save file is put back
## exactly as it was.

## Stands in for the player: what the stores read.
class FakePlayer extends Node3D:
	var marker: PaintMarker
	var body_paint: BodyPaint
	var vehicle: Car = null

## Stands in for WorldBuilder: what finding the stores reads.
class FakeWorld extends Node:
	var data: StreetData
	var network: RoadNetwork
	var terrain: Terrain

	func is_in_play_area(_p: Vector2) -> bool:
		return true

var _failures := 0
var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("STORES ok   %s" % what)
	else:
		_failures += 1
		print("STORES FAIL %s" % what)


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

	var hud := Hud.new()
	root.add_child(hud)
	var player := FakePlayer.new()
	player.marker = PaintMarker.new()
	player.marker.shooter = player
	player.add_child(player.marker)
	player.body_paint = BodyPaint.new()
	player.add_child(player.body_paint)
	root.add_child(player)
	await _frames(2)
	var economy := Economy.new()
	economy.name = "Economy"
	economy.player = player
	economy.hud = hud
	root.add_child(economy)
	economy.counters = Counters.new()
	economy.add_child(economy.counters)
	economy.counters.setup(player, hud)
	var stores := Stores.new()
	stores.name = "Stores"
	economy.add_child(stores)
	stores.setup(economy)
	stores.add_counters({"brand": Stores.ERVINS, "door": Vector3.ZERO, "pumps": Vector3(20, 0, 0), "pumps_reach": 8.0}, 0)
	stores.add_counters({"brand": Stores.MAPLE_TIRE, "door": Vector3(100, 0, 0)}, 1)
	_check(Stores.find(self) == stores and stores.armour != null, "the stores are a module of Economy, with the player's armour")
	gs.call("add_money", 20000)

	await _ervins_checks(gs, economy.counters, player)
	_armour_checks(gs, hud, player)
	await _maple_checks(gs, economy.counters)
	_site_checks()

	# Put the save back as it was.
	if _had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(_saved_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("STORES %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## The item with `id` on a counter's card now ({} if it isn't there).
func _item(counters: Counters, counter: String, id: String) -> Dictionary:
	for it: Dictionary in counters._items(counter):
		if str(it["id"]) == id:
			return it
	return {}


## Picks an item on a counter's card, as the player would.
func _buy(counters: Counters, counter: String, id: String) -> bool:
	var it := _item(counters, counter, id)
	if it.is_empty():
		return false
	counters._on_chosen(counter, it)
	return true


func _ervins_checks(gs: Node, counters: Counters, player: FakePlayer) -> void:
	var m := player.marker
	var spec := counters.spec("ervins_0_pumps")
	_check(counters.has("ervins_0") and bool(spec.get("in_car", false)) and not bool(spec.get("on_foot", true)), "Ervin's has a counter at the door, and one at the pumps you use from the car")
	var money := int(gs.get("money"))
	m.ammo = 3
	_buy(counters, "ervins_0", "paint")
	_check(m.ammo == int(PaintWeapons.ISLANDER["hopper"]) and int(gs.get("money")) == money - Stores.PAINT_PRICE, "paintballs fill the hopper (%d) for %s" % [m.ammo, CarModels.dollars(Stores.PAINT_PRICE)])
	_check(_item(counters, "ervins_0", "jars").is_empty() and not _item(counters, "ervins_0", "jam_jars").is_empty(), "Mustard Pickles are sold; their refills once you own them")
	_buy(counters, "ervins_0", "jam_jars")
	_check(bool(gs.call("owns_weapon", "jam_jars")) and m.ammo_for("jam_jars") == 4 and not bool(_item(counters, "ervins_0", "jam_jars").get("enabled", true)),
		"buying Mustard Pickles owns them, full, and they're off the card after")
	m.switch_to(PaintWeapons.JAM_JARS)
	m.ammo = 1
	m.switch_to(PaintWeapons.ISLANDER)
	money = int(gs.get("money"))
	_buy(counters, "ervins_0", "jars")
	_check(m.ammo_for("jam_jars") == 4 and int(gs.get("money")) == money - Stores.JARS_PRICE, "a refill tops the jars back up to 4")
	_buy(counters, "ervins_0", "farmhand")
	_check(bool(gs.call("owns_weapon", "farmhand")), "the markers are sold too (the Farmhand)")
	_buy(counters, "ervins_0", "plate")
	_check(player.body_paint.armour == 1 and int(gs.call("item_count", "armour")) == 1, "a plate goes on and into the save's items")
	_buy(counters, "ervins_0", "plates")
	var plate := _item(counters, "ervins_0", "plate")
	_check(player.body_paint.armour == BodyPaint.ARMOUR_MAX and int(gs.call("item_count", "armour")) == BodyPaint.ARMOUR_MAX and not bool(plate.get("enabled", true)),
		"filling up puts on all %d, and then plates aren't sold" % BodyPaint.ARMOUR_MAX)
	money = int(gs.get("money"))
	_buy(counters, "ervins_0", "plate")
	_check(int(gs.get("money")) == money and player.body_paint.armour == BodyPaint.ARMOUR_MAX, "a fourth plate is refused and costs nothing")
	gs.call("load_game")
	_check(int(gs.call("item_count", "armour")) == BodyPaint.ARMOUR_MAX and player.body_paint.armour == BodyPaint.ARMOUR_MAX, "the plates are kept in the save")
	await _frames(1)


func _armour_checks(gs: Node, hud: Hud, player: FakePlayer) -> void:
	var b := player.body_paint
	b.can_go_out = false
	b.take_hit(1, null, Vector3.ZERO, Color.WHITE)
	_check(b.armour == 3 and b.hits == 0, "outside events a hit uses no plate")
	b.can_go_out = true
	b.take_hit(1, null, Vector3.ZERO, Color.WHITE)
	_check(b.armour == 3 and b.plate_wear == 1 and b.hits == 0, "a hit wears a plate and counts nothing (%d plates, %d hits)" % [b.armour, b.hits])
	b.take_hit(1, null, Vector3.ZERO, Color.WHITE)
	_check(b.armour == 2 and b.hits == 0 and int(gs.call("item_count", "armour")) == 2, "the plate's %dnd hit breaks it (%d plates, %d hits)" % [BodyPaint.PLATE_HITS, b.armour, b.hits])
	_check(hud._plates == 2 and hud._plate_flash > 0.0 and hud._plates_broke == 1, "the HUD's armour bar shows it, the broken plate flashing")
	b.take_hit(2, null, Vector3.ZERO, Color.WHITE)
	b.take_hit(1, null, Vector3.ZERO, Color.WHITE)
	b.take_hit(2, null, Vector3.ZERO, Color.WHITE)
	_check(b.armour == 0 and b.hits == 1 and int(gs.call("item_count", "armour")) == 0, "a head hit on a worn last plate breaks it and counts the rest (%d hits)" % b.hits)
	for i in BodyPaint.OUT_HITS - 1:
		b.take_hit(1, null, Vector3.ZERO, Color.WHITE)
	_check(b.out and b.hits == BodyPaint.OUT_HITS, "with no plates left, hits count toward an out as before")
	b.revive()
	# A new session: plates from the save go on.
	gs.call("add_item", "armour", 2)
	var b2 := BodyPaint.new()
	player.add_child(b2)
	var a2 := Armour.new()
	player.add_child(a2)
	a2.setup(b2, null)
	_check(b2.armour == 2, "the plates in the save are worn when the game starts")
	a2.queue_free()
	b2.queue_free()


func _maple_checks(gs: Node, counters: Counters) -> void:
	_check(int(gs.call("item_count", Stores.MAPLE_ITEM)) == 0, "no Maple Money to start")
	var money := int(gs.get("money"))
	_buy(counters, "maple_tire_1", "lift_kit")
	var back := roundi(2400 * 100 * Stores.MAPLE_BACK)
	_check(int(gs.get("money")) == money - 2400 and int(gs.call("item_count", "lift_kit")) == 1 and int(gs.call("item_count", Stores.MAPLE_ITEM)) == back,
		"a lift kit goes into the items for the custom shop, with %s Maple Money back" % Stores.money_text(back))
	var tires := _item(counters, "maple_tire_1", "all_terrain_tires")
	_check(int(tires["price"]) == 1100 - back / 100, "Maple Money comes off the next price on the card (%s)" % CarModels.dollars(int(tires["price"])))
	money = int(gs.get("money"))
	_buy(counters, "maple_tire_1", "all_terrain_tires")
	var back2 := roundi((1100 - back / 100) * 100 * Stores.MAPLE_BACK)
	_check(int(gs.get("money")) == money - (1100 - back / 100) and int(gs.call("item_count", Stores.MAPLE_ITEM)) == back % 100 + back2,
		"and is spent like cash, with more back on the cash part (%s left)" % Stores.money_text(int(gs.call("item_count", Stores.MAPLE_ITEM))))
	_check(is_equal_approx(Car.strap_length(), Car.STRAP_LENGTH), "every car's strap is %d m" % int(Car.STRAP_LENGTH))
	_buy(counters, "maple_tire_1", "recovery_strap")
	_check(is_equal_approx(Car.strap_length(), Car.LONG_STRAP_LENGTH) and not bool(_item(counters, "maple_tire_1", "recovery_strap").get("enabled", true)),
		"the recovery strap reaches %d m at once, and one is all you need" % int(Car.LONG_STRAP_LENGTH))
	var cents := int(gs.call("item_count", Stores.MAPLE_ITEM))
	counters.open_card("maple_tire_1")
	await _frames(1)
	var line := counters.menu._subtitle.text
	_check(line.contains(Stores.money_text(cents)), "the card shows the Maple Money (\"%s\")" % line)
	counters.menu.close()
	gs.call("load_game")
	_check(int(gs.call("item_count", Stores.MAPLE_ITEM)) == cents and int(gs.call("item_count", "all_terrain_tires")) == 1, "the save keeps the Maple Money and the gear")
	money = int(gs.get("money"))
	gs.set("money", 0)
	_buy(counters, "maple_tire_1", "winch_kit")
	_check(int(gs.call("item_count", "winch_kit")) == 0 and int(gs.call("item_count", Stores.MAPLE_ITEM)) == cents, "short of cash, nothing's bought and no Maple Money is used")
	gs.set("money", money)


func _site_checks() -> void:
	var data := StreetData.load_from("res://data/map_config.json")
	var world := FakeWorld.new()
	world.data = data
	world.network = RoadNetwork.new(data)
	world.terrain = Terrain.load_from(str(data.config.get("elevation")))
	root.add_child(world)
	var ervins := Stores.find_sites(world, Stores.ERVINS)
	var pumps := 0
	for s in ervins:
		if s.has("pumps"):
			pumps += 1
	_check(ervins.size() >= 3 and pumps >= 3, "every Ervin's is found (%d, %d with pumps)" % [ervins.size(), pumps])
	var maple := Stores.find_sites(world, Stores.MAPLE_TIRE)
	_check(maple.size() == 1, "and the Maple Tire (%d)" % maple.size())
	var bad: Array[String] = []
	for s in ervins + maple:
		var at: Vector3 = s["door"]
		var p := Vector2(at.x, at.z)
		var cx := floori(p.x / data.chunk_size)
		var cz := floori(p.y / data.chunk_size)
		var near_wall := INF
		var inside := false
		var around: Array[StreetData.Building] = []
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				around.append_array(data.load_chunk(cx + dx, cz + dz).buildings)
		for b in around:
			if BuildingGenerator.CANOPY_TYPES.has(str(b.tags.get("building", ""))) or bool((data.config.get("landmarks", {}) as Dictionary).get(b.id, {}).get("canopy", false)):
				continue # under a canopy is fine
			if Geometry2D.is_point_in_polygon(p, b.ring):
				inside = true
			for i in b.ring.size():
				near_wall = minf(near_wall, p.distance_to(Geometry2D.get_closest_point_to_segment(p, b.ring[i], b.ring[(i + 1) % b.ring.size()])))
		if inside or (not s.has("pumps") and near_wall > 8.0) or absf(at.y - world.terrain.height_at(p.x, p.y)) > 0.01:
			bad.append("%s at (%.0f, %.0f)" % [s["brand"], p.x, p.y])
	_check(bad.is_empty(), "each counter stands on the ground outside the store, by its wall %s" % str(bad))
	for s in ervins + maple:
		print("STORES      %s door (%.0f, %.0f)%s" % [s["brand"], (s["door"] as Vector3).x, (s["door"] as Vector3).z,
			("  pumps (%.0f, %.0f)" % [(s["pumps"] as Vector3).x, (s["pumps"] as Vector3).z]) if s.has("pumps") else ""])
	world.queue_free()

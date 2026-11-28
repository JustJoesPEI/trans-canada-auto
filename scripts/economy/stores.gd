class_name Stores
extends Node
## The stores that sell things (docs/design.md section 6½, "Spending"): a
## module of Economy. Most real buildings stay scenery; these do something.
##
## Ervin's (every gas station of the brand): a counter at the store's door
## on foot, and one under the canopy you can use from the car. Paint (every
## hopper full), Mustard Pickles, the markers themselves and armour plates. No
## fuel (decided). Masks wait for clothes that can show one.
##
## Maple Tire: car gear, bought into GameState.items for the custom shop to
## fit ("winch_kit": 1...), and the long recovery strap, which works as
## soon as you have it (Car.strap_length). Maple Money: MAPLE_BACK of the
## cash paid comes back, kept in GameState.items["maple_money"] in cents,
## and is spent before cash on the next purchase there.
##
## Armour (Armour): plates worn on the player's BodyPaint that take paint
## hits first; bought here.
##
## Where the stores are: the world brands' entries in locations.json
## (tools/make_locations.py) say roughly where; the buildings of the brand
## there (map_config.json "brands": the real chains each replaces) give the
## store and its canopy. The counter goes outside the store's front: the
## wall facing the pumps for a gas station, the entrance on its parking lot
## for a big box.

const ERVINS := "Ervin's"
const MAPLE_TIRE := "Maple Tire"

## Prices (to tune by playing, as section 6½'s pacing says).
const PAINT_PRICE := 10 ## every hopper full ("ammo is cheap", section 2)
const JARS_PRICE := 40 ## a full carry of Mustard Pickles
const PLATE_PRICE := 150
## Markers and throwables (section 2's table), in the order sold.
const MARKERS := [
	["farmhand", 1500, "Scoped pump marker: slow, very accurate, out to 80 m. Each hit counts 2."],
	["lobbyist", 2500, "Full-auto: 15 a second, a wide spread, a 100-ball hopper."],
	["jam_jars", 600, "Paint grenades in a mustard pickle jar, carry 4. Everyone within 3.5 m. Return the jar."],
	["tourist_season", 4000, "Paint launcher: lobs bombs, 2 hits on everyone within 5 m."],
]

## Maple Tire's gear: id (the GameState item), name, price, note, and
## "max" to own (0: any number, one per vehicle to fit).
const GEAR := [
	{"id": "recovery_strap", "name": "Recovery strap, 15 m", "price": 120, "max": 1,
		"note": "Every car carries a 9 m strap; this one reaches 15 m and stretches more. Yours as soon as you buy it."},
	{"id": "all_terrain_tires", "name": "All-terrain tires", "price": 1100,
		"note": "A set of four that bite in the mud and sand. Fitted at the custom shop."},
	{"id": "lift_kit", "name": "Lift kit", "price": 2400,
		"note": "Two inches up, for ground clearance. Fitted at the custom shop."},
	{"id": "winch_kit", "name": "Front winch kit", "price": 1800,
		"note": "A twelve-thousand-pound winch on the front bumper. Fitted at the custom shop."},
	{"id": "roof_lights", "name": "Roof light bar", "price": 450,
		"note": "LEDs across the roof. Fitted at the custom shop."},
	{"id": "roof_rack", "name": "Roof rack", "price": 350,
		"note": "Crossbars and a basket. Fitted at the custom shop."},
]
## Maple Money back on the cash paid at Maple Tire (design: "a little").
const MAPLE_BACK := 0.05
const MAPLE_ITEM := "maple_money"

## How far from a brand's location entry its buildings can be (m), how far
## a plain canopy can be from the brand's store and still be its pumps
## (BuildingGenerator.GAS_CANOPY_REACH), and how far out from the wall the
## counter is.
const SITE_REACH := 70.0
const CANOPY_REACH := 45.0
const DOOR_OUT := 2.0
## m a big store's glass vestibule stands out from its front
## (BuildingGenerator._storefront).
const VESTIBULE := 3.0
## m round a store to look for its parking lot.
const LOT_REACH := 130.0
const DOOR_REACH := 3.5

var economy: Economy
var armour: Armour
## Every store: {brand, door: Vector3, pumps: Vector3 (gas stations with a
## canopy), pumps_reach (m)}.
var sites: Array[Dictionary] = []


static func find(tree: SceneTree) -> Stores:
	var e := Economy.find(tree)
	return e.get_node_or_null("Stores") as Stores if e != null else null


func setup(e: Economy) -> void:
	economy = e
	var body: Variant = e.player.get("body_paint") if e.player != null else null
	if body is BodyPaint:
		armour = Armour.new()
		armour.name = "Armour"
		add_child(armour)
		armour.setup(body, e.hud)
	if e.world != null and e.world.data != null and e.counters != null:
		sites = find_sites(e.world, ERVINS) + find_sites(e.world, MAPLE_TIRE)
	for i in sites.size():
		add_counters(sites[i], i)


## The counters for one store (`n` numbers them).
func add_counters(site: Dictionary, n: int) -> void:
	var c := economy.counters
	if str(site["brand"]) == ERVINS:
		c.add({"id": "ervins_%d" % n, "title": ERVINS, "subtitle": "Paint, throwables, markers, armour. The pumps are for show.",
			"at": site["door"], "reach": DOOR_REACH, "kind": "gas", "items": ervins_items})
		if site.has("pumps"):
			c.add({"id": "ervins_%d_pumps" % n, "title": ERVINS, "subtitle": "Pull up, pay at the pump. No gas, just paint.",
				"prompt": "Ervin's: paint and armour", "at": site["pumps"], "reach": float(site.get("pumps_reach", 7.0)),
				"on_foot": false, "in_car": true, "kind": "", "items": ervins_items})
	else:
		c.add({"id": "maple_tire_%d" % n, "title": MAPLE_TIRE, "subtitle": maple_line,
			"at": site["door"], "reach": DOOR_REACH, "kind": "shop", "items": maple_items})


# --- Ervin's ------------------------------------------------------------------------------------

func ervins_items() -> Array:
	var gs := _gs()
	var marker := _marker()
	var list: Array = []
	list.append({"id": "paint", "name": "Paintballs", "note": "Every hopper full.", "price": PAINT_PRICE,
		"enabled": marker != null, "why": "Nothing to fill.",
		"action": func(_i: Dictionary) -> String:
			for id: String in gs.get("owned_weapons"):
				if float(PaintWeapons.get_weapon(id).get("reload_time", 0.0)) > 0.0:
					marker.fill(id)
			return "Every hopper's full."})
	if bool(gs.call("owns_weapon", "jam_jars")):
		var carry := int(PaintWeapons.JAM_JARS["hopper"])
		var have := marker.ammo_for("jam_jars") if marker != null else carry
		list.append({"id": "jars", "name": "Paint grenade refill", "note": "Mustard Pickles, a full carry of %d (you have %d)." % [carry, have], "price": JARS_PRICE,
			"enabled": have < carry, "why": "You're carrying all %d." % carry, "why_short": "Full",
			"action": func(_i: Dictionary) -> String:
				marker.fill("jam_jars")
				return "%d paint grenades." % carry})
	var worn := armour.plates() if armour != null else 0
	var room := armour.room() if armour != null else 0
	list.append({"id": "plate", "name": "Armour plate", "note": "Takes a paint hit for you. Wearing %d of %d." % [worn, BodyPaint.ARMOUR_MAX],
		"price": PLATE_PRICE, "enabled": room > 0, "why": "You're wearing all %d." % BodyPaint.ARMOUR_MAX, "why_short": "Full",
		"action": func(_i: Dictionary) -> String:
			armour.add_plates(1)
			return "Plate on: wearing %d." % armour.plates()})
	if room >= 2:
		list.append({"id": "plates", "name": "Armour, %d plates" % room, "note": "Fill up: all %d on." % BodyPaint.ARMOUR_MAX,
			"price": PLATE_PRICE * room,
			"action": func(_i: Dictionary) -> String:
				armour.add_plates(room)
				return "Wearing %d plates." % armour.plates()})
	for m: Array in MARKERS:
		var id := str(m[0])
		var w := PaintWeapons.get_weapon(id)
		var owned := bool(gs.call("owns_weapon", id))
		list.append({"id": id, "name": PaintWeapons.full_label(w), "note": str(m[2]), "price": int(m[1]),
			"enabled": not owned, "why": "You've got one.", "why_short": "Owned",
			"action": func(_i: Dictionary) -> String:
				gs.call("unlock_weapon", id)
				if marker != null:
					marker.fill(id)
				return "Bought the %s: hold %s for the weapon wheel." % [str(w["type"]).to_lower(), _key("weapon_wheel")]})
	return list


# --- Maple Tire ---------------------------------------------------------------------------------

func maple_items() -> Array:
	var gs := _gs()
	var cents := int(gs.call("item_count", MAPLE_ITEM))
	var list: Array = []
	for g: Dictionary in GEAR:
		var id := str(g["id"])
		var have := int(gs.call("item_count", id))
		var most := int(g.get("max", 0))
		var full := int(g["price"])
		var use := mini(full, cents / 100) # whole dollars of Maple Money
		var note := str(g["note"])
		if have > 0 and most == 0:
			note += " %d waiting to be fitted." % have
		if use > 0:
			note += " Maple Money pays %s." % CarModels.dollars(use)
		list.append({"id": id, "name": str(g["name"]), "note": note, "price": full - use,
			"enabled": most == 0 or have < most, "why": "You've got one.", "why_short": "Owned",
			"action": func(_i: Dictionary) -> String:
				return buy_gear(id, full, use)})
	return list


## Pays for gear (the cash part was taken already; `use` dollars of Maple
## Money now), gives it, and puts Maple Money back on the cash.
func buy_gear(id: String, full: int, use: int) -> String:
	var gs := _gs()
	if use > 0:
		gs.call("add_item", MAPLE_ITEM, -use * 100)
	gs.call("add_item", id, 1)
	var back := roundi(float(full - use) * 100.0 * MAPLE_BACK)
	if back > 0:
		gs.call("add_item", MAPLE_ITEM, back)
	var label := id
	for g: Dictionary in GEAR:
		if str(g["id"]) == id:
			label = str(g["name"])
	return "Bought: %s. %s Maple Money back." % [label, money_text(back)]


## The Maple Tire card's line: what Maple Money you have.
func maple_line() -> String:
	return "Maple Money: %s. %d%% back on everything, spent like cash here." % [money_text(int(_gs().call("item_count", MAPLE_ITEM))), roundi(MAPLE_BACK * 100.0)]


## Cents as "$12.40".
static func money_text(cents: int) -> String:
	return "$%d.%02d" % [cents / 100, cents % 100]


# --- where the stores are -----------------------------------------------------------------------

## Every store of a world brand in the play area: see `sites`.
static func find_sites(world: Node, brand: String) -> Array[Dictionary]:
	var data: StreetData = world.get("data")
	var cfg: Dictionary = (data.config.get("brands", {}) as Dictionary).get(brand, {})
	var real: Array = cfg.get("replaces", [])
	var landmarks: Dictionary = data.config.get("landmarks", {})
	var gas := str(cfg.get("kind", "")) == "gas"
	var cells := {}
	var out: Array[Dictionary] = []
	var taken := {}
	for spot in _seeds(world, brand):
		var buildings := {}
		var lots: Array[PackedVector2Array] = []
		var cs := data.chunk_size
		for cx in range(floori((spot.x - LOT_REACH) / cs), floori((spot.x + LOT_REACH) / cs) + 1):
			for cz in range(floori((spot.y - LOT_REACH) / cs), floori((spot.y + LOT_REACH) / cs) + 1):
				var key := StreetData.chunk_key(cx, cz)
				if not cells.has(key):
					cells[key] = data.load_chunk(cx, cz)
				var chunk: StreetData.Chunk = cells[key]
				for b in chunk.buildings:
					buildings[b.id] = b
				for a in chunk.areas:
					if a.type == "amenity=parking":
						lots.append(a.ring)
		var stores: Array[StreetData.Building] = []
		var canopies: Array[StreetData.Building] = []
		var loose: Array[StreetData.Building] = []
		for b: StreetData.Building in buildings.values():
			if _centre(b.ring).distance_to(spot) > SITE_REACH:
				continue
			var lm: Dictionary = landmarks.get(b.id, {})
			var branded := real.has(str(b.tags.get("brand", ""))) or real.has(str(b.tags.get("name", ""))) or str(lm.get("brand", "")) == brand
			var canopy := BuildingGenerator.CANOPY_TYPES.has(str(b.tags.get("building", ""))) or bool(lm.get("canopy", false))
			if branded:
				(canopies if canopy else stores).append(b)
			elif canopy and gas:
				loose.append(b)
		stores.sort_custom(func(a: StreetData.Building, b: StreetData.Building) -> bool: return _area(a.ring) > _area(b.ring))
		if gas and canopies.is_empty() and not stores.is_empty():
			# A plain roof over the pumps beside the brand's store is its
			# canopy (as the building generator decides).
			for b in loose:
				if _centre(b.ring).distance_to(_centre(stores[0].ring)) < CANOPY_REACH:
					canopies.append(b)
					break
		if stores.is_empty() and canopies.is_empty():
			continue
		var main_b := stores[0] if not stores.is_empty() else canopies[0]
		if taken.has(main_b.id):
			continue
		taken[main_b.id] = true
		var site := {"brand": brand}
		var door: Vector2
		if not stores.is_empty():
			if not canopies.is_empty():
				door = _door(stores[0].ring, _centre(canopies[0].ring)) # facing the pumps
			else:
				door = _front_door(world, stores[0].ring, lots)
		else:
			door = _centre(canopies[0].ring) # no store of ours: under the canopy
		site["door"] = _on_ground(world, door)
		if gas and not canopies.is_empty():
			var c := _centre(canopies[0].ring)
			site["pumps"] = _on_ground(world, c)
			var r := 0.0
			for q in canopies[0].ring:
				r = maxf(r, q.distance_to(c))
			site["pumps_reach"] = clampf(r + 2.0, 6.0, 14.0)
		out.append(site)
	return out


## Roughly where each of a brand's stores is: its entries in locations.json
## inside the play area.
static func _seeds(world: Node, brand: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var data: StreetData = world.get("data")
	var dir := data.city_dir if data.city_dir != "" else "res://data/city"
	var f := FileAccess.open(dir.path_join("locations.json"), FileAccess.READ)
	if f == null:
		return out
	var j: Variant = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary):
		return out
	for e: Dictionary in (j as Dictionary).get("locations", []):
		if str(e.get("name", "")) != brand:
			continue
		var at := Vector2(float(e["x"]), float(e["z"]))
		if not world.has_method("is_in_play_area") or bool(world.call("is_in_play_area", at)):
			out.append(at)
	return out


## A store without pumps: its entrance, where BuildingGenerator puts it
## (_front_line, _storefront): the middle of the side looking onto the most
## parking lot (or else the side nearest a street), out past the vestibule.
static func _front_door(world: Node, ring: PackedVector2Array, lots: Array[PackedVector2Array]) -> Vector2:
	var obb := BuildingGenerator._obb(ring)
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var hu := float(obb["half_u"])
	var hv := float(obb["half_v"])
	var net: RoadNetwork = world.get("network")
	var best_n := Vector2.ZERO
	var best_score := -INF
	for n: Vector2 in [u, -u, v, -v]:
		var reach := absf(n.dot(u)) * hu + absf(n.dot(v)) * hv
		var side := Vector2(-n.y, n.x)
		var span := absf(side.dot(u)) * hu + absf(side.dot(v)) * hv
		var score := 0.0
		for k in 5:
			for d: float in [8.0, 20.0, 35.0]:
				var q := c + n * (reach + d) + side * span * (float(k) / 2.0 - 1.0) * 0.8
				for lot in lots:
					if Geometry2D.is_point_in_polygon(q, lot):
						score += 1.0
						break
		if score == 0.0 and net != null:
			var hit := net.nearest_on_streets(c + n * (reach + 4.0), 60.0)
			score = -float(hit.get("dist", 99.0)) * 0.001
		if score > best_score:
			best_score = score
			best_n = n
	# The front line: the footprint's frontmost points on that side.
	var max_d := -INF
	for p in ring:
		max_d = maxf(max_d, (p - c).dot(best_n))
	var t := Vector2(-best_n.y, best_n.x)
	var lo := INF
	var hi := -INF
	for p in ring:
		if (p - c).dot(best_n) > max_d - 2.0:
			lo = minf(lo, (p - c).dot(t))
			hi = maxf(hi, (p - c).dot(t))
	return c + best_n * (max_d + VESTIBULE + DOOR_OUT) + t * (lo + hi) * 0.5


## The point DOOR_OUT outside the wall of `ring` nearest `toward`.
static func _door(ring: PackedVector2Array, toward: Vector2) -> Vector2:
	var c := _centre(ring)
	var best := c
	var best_n := Vector2.DOWN
	var best_d := INF
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 0.5:
			continue
		var q := Geometry2D.get_closest_point_to_segment(toward, a, b)
		var d := q.distance_to(toward)
		if d < best_d:
			best_d = d
			best = q
			var t := (b - a).normalized()
			var n := Vector2(t.y, -t.x)
			best_n = n if n.dot(q - c) >= 0.0 else -n
	return best + best_n * DOOR_OUT


static func _on_ground(world: Node, p: Vector2) -> Vector3:
	var t: Terrain = world.get("terrain")
	return Vector3(p.x, t.height_at(p.x, p.y) if t != null and t.nx > 0 else 0.0, p.y)


static func _centre(ring: PackedVector2Array) -> Vector2:
	var m := Vector2.ZERO
	for q in ring:
		m += q
	return m / float(maxi(1, ring.size()))


static func _area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		a += ring[i].cross(ring[(i + 1) % ring.size()])
	return absf(a) * 0.5


# --- helpers -----------------------------------------------------------------------------------

func _gs() -> Node:
	return get_tree().root.get_node("GameState")


func _marker() -> PaintMarker:
	var m: Variant = economy.player.get("marker") if economy != null and economy.player != null else null
	return m as PaintMarker if m is PaintMarker else null


func _key(action: String) -> String:
	var hud := economy.hud if economy != null else null
	return str(hud.call("key_for", action)) if hud != null and hud.has_method("key_for") else action

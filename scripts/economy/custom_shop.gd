class_name CustomShop
extends Node
## The custom shop (docs/design.md section 6½): Red Dirt Kustoms, in the old
## Mufflercentre at Belvedere Avenue and Brackley Point Road. Drive into the
## bay round the side in a car or truck you own and the card upgrades it:
## engine stages, tyres (all-terrain and mud tyres matter off the
## pavement), suspension or a lift kit, brakes, gearing and weight, a front
## winch, horns and paint. Kits bought at Maple Tire (GameState.items) are
## fitted for the labour. It buys cars too (UsedLot.sell_item).
##
## What's fitted is kept in the vehicle's mods in GameState.vehicles:
##   engine, tyres, suspension, brakes, gearing, weight   the upgrade's id
##   parts    the CarParts ids those add up to (OwnedCars fits these)
##   winch    true for a front winch
##   horn     {kind, pitch}
##   spent    dollars spent here (UsedLot.sale_value counts some of it)
## and the paint in the vehicle's own "paint". OwnedCars builds a vehicle
## from those whenever it's spawned; this applies the rest (the winch and
## the horn) on its `spawned` signal. A fit rebuilds the vehicle where it
## stands (OwnedCars.refit), since a Car reads its parts and paint when it's
## made, and puts you back in the seat.
##
## Work trucks (TruckModels) take everything but the car-only upgrades
## ("cars_only": sport suspension, the lift kit, weight reduction, street
## tyres).

const COUNTER_ID := "custom_shop"
const TITLE := "Red Dirt Kustoms"
## The bay: off the service lane on the shop's south side.
const BAY_POS := [-63.1202130, 46.2590740]
const BAY_REACH := 7.0

## Every upgrade: a slot (one fitted per slot), the CarParts it adds, what
## it costs. "after": the one that has to be fitted first (the engine
## stages). "kit": a Maple Tire item that, if you have one, is fitted for
## "labour" instead of the price.
const UPGRADES: Array[Dictionary] = [
	{"slot": "engine", "id": "stage1", "name": "Stage 1: intake and exhaust", "price": 3000, "parts": ["intake_exhaust"]},
	{"slot": "engine", "id": "stage2", "name": "Stage 2: engine tune", "price": 7500, "parts": ["intake_exhaust", "engine_tune"], "after": "stage1"},
	{"slot": "engine", "id": "stage3", "name": "Stage 3: forced induction", "price": 18000, "parts": ["intake_exhaust", "engine_tune", "forced_induction"], "after": "stage2"},
	{"slot": "tyres", "id": "performance", "name": "Performance tyres", "price": 1800, "parts": ["performance_tyres"], "cars_only": true},
	{"slot": "tyres", "id": "all_terrain", "name": "All-terrain tyres", "price": 2400, "parts": ["all_terrain_tyres"], "kit": "all_terrain_tyres", "labour": 250},
	{"slot": "tyres", "id": "mud", "name": "Mud-terrain tyres", "price": 4200, "parts": ["mud_tyres"]},
	{"slot": "suspension", "id": "sport", "name": "Sport suspension", "price": 3500, "parts": ["sport_springs", "anti_roll_bars"], "cars_only": true},
	{"slot": "suspension", "id": "lift", "name": "Lift kit", "price": 4800, "parts": ["lift_kit"], "kit": "lift_kit", "labour": 600, "cars_only": true},
	{"slot": "brakes", "id": "big", "name": "Big brakes", "price": 2800, "parts": ["big_brakes"]},
	{"slot": "gearing", "id": "short", "name": "Short final drive", "price": 1500, "parts": ["short_gearing"]},
	{"slot": "weight", "id": "light", "name": "Weight reduction", "price": 5000, "parts": ["weight_reduction"], "cars_only": true},
]
const SLOTS := ["engine", "tyres", "suspension", "brakes", "gearing", "weight"]
## The card's pages of upgrades: slots on each.
const PAGES := {
	"engine": {"name": "Engine", "slots": ["engine"]},
	"tyres": {"name": "Tyres", "slots": ["tyres"]},
	"suspension": {"name": "Suspension", "slots": ["suspension"]},
	"chassis": {"name": "Brakes, gearing, weight", "slots": ["brakes", "gearing", "weight"]},
}
const WINCH_PRICE := 3500
const WINCH_KIT := "winch_kit"
const WINCH_LABOUR := 400
const HORNS: Array[Dictionary] = [
	{"id": "stock", "name": "The horn it came with", "price": 50, "kind": "car", "pitch": 0.0, "note": "Back to stock."},
	{"id": "air", "name": "Air horn", "price": 650, "kind": "air", "pitch": 0.0, "note": "A transport truck's, for the Trans-Canada. Clears a lane."},
	{"id": "meep", "name": "Meep meep", "price": 150, "kind": "car", "pitch": 1.8, "note": "Small horn, big feelings."},
	{"id": "buzz", "name": "Forklift buzzer", "price": 90, "kind": "buzz", "pitch": 0.0, "note": "For people who mean business in a parking lot."},
]
## Paint, in local colours.
const COLOURS: Array[Dictionary] = [
	{"name": "Red Dirt", "hex": "#8e3b22"},
	{"name": "Lobster Boil", "hex": "#c8321e"},
	{"name": "Carrot-Top Orange", "hex": "#d0641e"},
	{"name": "Highway Yellow", "hex": "#e0b81c"},
	{"name": "Fiddlehead Green", "hex": "#4f6b2a"},
	{"name": "Gulf Blue", "hex": "#1f4e7a"},
	{"name": "Lupin Purple", "hex": "#6b4a9a"},
	{"name": "Potato Skin", "hex": "#9a7a52"},
	{"name": "Island Sand", "hex": "#d9c49a"},
	{"name": "Confederation Bridge Grey", "hex": "#8b9096"},
	{"name": "Snowbank White", "hex": "#eeeeea"},
	{"name": "Mussel Black", "hex": "#1b1d22"},
]
const PAINT_PRICE := 1200
const PAINT_PRICE_TRUCK := 2500

var economy: Economy
var at := Vector3.ZERO
## The card's page: "main", a PAGES key, "horn", "paint" or "sell".
var page := "main"


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


func setup(e: Economy) -> void:
	economy = e
	if e.world != null:
		at = e.world.edit_xform({"pos": BAY_POS}, 0.0).origin
	e.counters.add({"id": COUNTER_ID, "title": TITLE, "subtitle": "If it's worth doing, it's worth overdoing. Your own vehicles only: we don't do the company's trucks.",
		"at": at, "reach": BAY_REACH, "on_foot": false, "in_car": true, "kind": "custom_shop", "prompt": "Drive into " + TITLE,
		"items": items})
	e.counters.menu.closed.connect(func() -> void: page = "main")
	e.owned_cars.spawned.connect(apply_mods)
	# The ones already out (OwnedCars set them up before this module).
	for v: Dictionary in _gs().get("vehicles"):
		var car := e.owned_cars.car_for(str(v["id"]))
		if car != null:
			apply_mods(car, str(v["id"]))


# --- what's fitted -------------------------------------------------------------------------

static func upgrade(id: String) -> Dictionary:
	for u: Dictionary in UPGRADES:
		if str(u["id"]) == id:
			return u
	return {}


static func is_truck(model_id: String) -> bool:
	return str(CarModels.shape_for(model_id).get("builder", "car")) == "truck"


## Whether upgrade `u` can go on `model_id`.
static func fits(u: Dictionary, model_id: String) -> bool:
	return not (bool(u.get("cars_only", false)) and is_truck(model_id))


## The CarParts ids a vehicle's mods add up to, in the order of UPGRADES,
## after any parts it had that aren't the shop's.
static func parts_for(mods: Dictionary) -> Array:
	var ours := {}
	for u: Dictionary in UPGRADES:
		for p: String in u["parts"]:
			ours[p] = true
	var out: Array = []
	for p: Variant in mods.get("parts", []):
		if not ours.has(str(p)):
			out.append(str(p))
	for slot: String in SLOTS:
		var u := upgrade(str(mods.get(slot, "")))
		for p: String in u.get("parts", []):
			if not out.has(p):
				out.append(p)
	return out


## The things on the card worth showing before and after a change.
static func stats(model_id: String, parts: Array) -> Dictionary:
	var spec := CarParts.build_spec(model_id, parts)
	var hp := 0.0
	var eng: Variant = spec.get("engine")
	if eng is Dictionary:
		for pt: Array in (eng as Dictionary).get("torque", []):
			hp = maxf(hp, float(pt[0]) * float(pt[1]) / 7127.0)
	var ty: Dictionary = spec.get("tyres", {})
	var grip := float(ty.get("grip", 1.0))
	var field: Dictionary = GroundMap.KINDS[GroundMap.FIELD]
	var fg := float(field["grip"])
	var sus: Dictionary = spec.get("suspension", {})
	return {
		"hp": roundi(hp),
		"grip": roundi(grip * 100.0),
		"mud": roundi(grip * (fg + (1.0 - fg) * float(ty.get("offroad", 0.0)) * float(field["soft"])) * 100.0),
		"ride": roundi(float(sus.get("travel", 0.0)) * 100.0),
		"roll": roundi(float(sus.get("anti_roll", 0.0)) * 100.0),
		"brakes": snappedf(float(spec.get("brakes", {}).get("force", 0.0)) / 1000.0, 0.1),
		"final": snappedf(float(spec.get("gearbox", {}).get("final", 0.0)), 0.01),
		"mass": roundi(float(spec.get("body", {}).get("mass", 0.0))),
	}


const STAT_TEXT := {
	"hp": "Power %s → %s hp", "grip": "Grip %s → %s%%", "mud": "In mud %s → %s%%", "ride": "Suspension travel %s → %s cm",
	"roll": "Roll stiffness %s → %s", "brakes": "Brakes %s → %s kN", "final": "Final drive %s → %s", "mass": "Weight %s → %s kg",
}


## "Power 140 → 151 hp, ..." for what changes from `before` to `after`.
static func change_text(before: Dictionary, after: Dictionary) -> String:
	var out: Array[String] = []
	for k: String in STAT_TEXT:
		if before.get(k) != after.get(k):
			out.append(STAT_TEXT[k] % [str(before[k]), str(after[k])])
	return ", ".join(out) if not out.is_empty() else "No change you'd feel."


## The winch and horn (OwnedCars fits the parts and paint): on every owned
## vehicle as it's spawned.
func apply_mods(car: Car, id: String) -> void:
	var mods: Dictionary = (_gs().call("vehicle", id) as Dictionary).get("mods", {})
	if bool(mods.get("winch", false)) and not car.has_winch():
		# The model's shape is shared by every car of it: this one gets its own.
		var own := car.shape.duplicate(true)
		own["winch"] = true
		car.shape = own
	var horn: Variant = mods.get("horn")
	if horn is Dictionary:
		for c: Node in car.get_children():
			if c is CarAudio:
				(c as CarAudio).set_horn(str(horn.get("kind", "car")), float(horn.get("pitch", 0.0)))


# --- fitting -------------------------------------------------------------------------------

## Fits upgrade `up_id` to owned vehicle `car` (the price is the card's to
## charge), using up a kit if `kit`. The rebuilt car.
func fit(car: Car, up_id: String, spent: int, kit := "") -> Car:
	var id := car.garage_id
	var u := upgrade(up_id)
	var mods: Dictionary = ((_gs().call("vehicle", id) as Dictionary).get("mods", {}) as Dictionary).duplicate(true)
	mods[str(u["slot"])] = up_id
	mods["parts"] = parts_for(mods)
	mods["spent"] = int(mods.get("spent", 0)) + spent
	if kit != "":
		_gs().call("add_item", kit, -1)
	_gs().call("set_vehicle", id, {"mods": mods})
	return rebuild(car)


## Changes mods fields (the winch, the horn) on owned vehicle `car`.
func set_mods(car: Car, fields: Dictionary, spent: int, kit := "") -> Car:
	var id := car.garage_id
	var mods: Dictionary = ((_gs().call("vehicle", id) as Dictionary).get("mods", {}) as Dictionary).duplicate(true)
	mods.merge(fields, true)
	mods["spent"] = int(mods.get("spent", 0)) + spent
	if kit != "":
		_gs().call("add_item", kit, -1)
	_gs().call("set_vehicle", id, {"mods": mods})
	return rebuild(car)


func repaint(car: Car, colour: Color, spent: int) -> Car:
	var id := car.garage_id
	var mods: Dictionary = ((_gs().call("vehicle", id) as Dictionary).get("mods", {}) as Dictionary).duplicate(true)
	mods["spent"] = int(mods.get("spent", 0)) + spent
	_gs().call("set_vehicle", id, {"paint": colour.to_html(false), "mods": mods})
	return rebuild(car)


## Builds `car` again from the save where it stands, with whoever was
## driving back in the seat and the card (if it was up) open again on it.
func rebuild(car: Car) -> Car:
	var driving := _driving() == car
	var menu := economy.counters.menu if economy.counters != null else null
	var card_up := menu != null and menu.visible and menu.counter_id == COUNTER_ID
	if card_up:
		var keep := page
		menu.close()
		page = keep
	if driving and economy.main != null and economy.main.has_method("unseat_player"):
		economy.main.call("unseat_player")
	var fresh := economy.owned_cars.refit(car.garage_id)
	if fresh == null:
		return car
	if driving and economy.main != null and economy.main.has_method("seat_player"):
		economy.main.call("seat_player", fresh)
	if card_up:
		economy.counters.open_card(COUNTER_ID)
	return fresh


func _driving() -> Car:
	if economy == null or economy.player == null:
		return null
	var v: Variant = economy.player.get("vehicle")
	return v as Car if v is Car else null


# --- the card ------------------------------------------------------------------------------

func items() -> Array:
	var car := _driving()
	if car == null or car.garage_id == "":
		page = "main"
		return [{"id": "nope", "name": "Bring a vehicle you own", "enabled": false,
			"why": "We only work on vehicles you own. Buy one, or bring yours round.", "why_short": ""}]
	match page:
		"horn":
			return _horn_items(car)
		"paint":
			return _paint_items(car)
		"sell":
			return [_back(), UsedLot.sell_item(economy, TITLE)]
	if PAGES.has(page):
		return _upgrade_items(car, PAGES[page]["slots"])
	return _main_items(car)


func _back() -> Dictionary:
	return {"id": "back", "name": "‹ Back", "price": -1, "action": func(_i: Dictionary) -> String:
		page = "main"
		return ""}


func _go(to: String, name: String, note: String) -> Dictionary:
	return {"id": "page_" + to, "name": name + "  ›", "note": note, "price": -1, "action": func(_i: Dictionary) -> String:
		page = to
		return ""}


func _mods(car: Car) -> Dictionary:
	return (_gs().call("vehicle", car.garage_id) as Dictionary).get("mods", {})


func _main_items(car: Car) -> Array:
	var mods := _mods(car)
	var now := stats(car.model_id, car.parts)
	var out: Array = []
	for key: String in PAGES:
		var fitted: Array[String] = []
		var any := false
		for slot: String in PAGES[key]["slots"]:
			for u: Dictionary in UPGRADES:
				if str(u["slot"]) == slot and fits(u, car.model_id):
					any = true
			var u := upgrade(str(mods.get(slot, "")))
			if not u.is_empty():
				fitted.append(str(u["name"]))
		if not any:
			continue
		var note := "Stock" if fitted.is_empty() else ", ".join(fitted)
		match key:
			"engine":
				note += ". %d hp" % int(now["hp"])
			"tyres":
				note += ". Grip %d%%, in mud %d%%" % [int(now["grip"]), int(now["mud"])]
		out.append(_go(key, str(PAGES[key]["name"]), note))
	if car.has_winch():
		out.append({"id": "winch", "name": "Front winch", "enabled": false, "why": "It has one: the hitch key, nose to a tree or post.", "why_short": "Fitted"})
	elif str(car.shape.get("tool", "")) == "":
		var kit := int(_gs().call("item_count", WINCH_KIT)) > 0
		out.append({"id": "winch", "name": "Front winch", "price": WINCH_LABOUR if kit else WINCH_PRICE,
			"note": ("Your winch kit, fitted. " if kit else "") + "Pulls you (or anyone) out of the mud from a tree or post: the hitch key.",
			"action": func(_i: Dictionary) -> String:
				set_mods(car, {"winch": true}, WINCH_LABOUR if kit else WINCH_PRICE, WINCH_KIT if kit else "")
				return "Winch fitted. Nose up to a tree and press the hitch key."})
	var horn: Dictionary = mods.get("horn", {}) if mods.get("horn") is Dictionary else {}
	out.append(_go("horn", "Horn", "Now: %s" % _horn_name(horn)))
	out.append(_go("paint", "Paint", "Now: %s" % _colour_name(car.paint)))
	out.append(_go("sell", "Sell it", "We'll give you %s for it." % CarModels.dollars(UsedLot.sale_value(car.garage_id))))
	return out


func _upgrade_items(car: Car, slots: Array) -> Array:
	var mods := _mods(car)
	var before := stats(car.model_id, car.parts)
	var out: Array = [_back()]
	for u: Dictionary in UPGRADES:
		if not slots.has(u["slot"]) or not fits(u, car.model_id):
			continue
		var uid := str(u["id"])
		var slot := str(u["slot"])
		var item := {"id": uid, "name": str(u["name"])}
		var trial := mods.duplicate(true)
		trial[slot] = uid
		var after := stats(car.model_id, parts_for(trial))
		var about := str(CarParts.PARTS.get((u["parts"] as Array).back(), {}).get("about", ""))
		item["note"] = change_text(before, after) + (". " + about if about != "" else "")
		var have := str(mods.get(slot, ""))
		var needs := str(u.get("after", ""))
		var kit := str(u.get("kit", ""))
		if have == uid:
			item["enabled"] = false
			item["why"] = "That's on it now."
			item["why_short"] = "Fitted"
		elif needs != "" and not _stage_done(have, needs):
			item["enabled"] = false
			item["why"] = "%s first." % str(upgrade(needs)["name"])
			item["why_short"] = "Next"
		else:
			var use_kit := kit != "" and int(_gs().call("item_count", kit)) > 0
			var price := int(u["labour"]) if use_kit else int(u["price"])
			item["price"] = price
			if use_kit:
				item["note"] = "Your kit from Maple Tire, fitted. " + str(item["note"])
			item["action"] = func(_i: Dictionary) -> String:
				var b := stats(car.model_id, car.parts)
				var fresh := fit(car, uid, price, kit if use_kit else "")
				return "%s fitted. %s." % [str(u["name"]), change_text(b, stats(fresh.model_id, fresh.parts))]
		out.append(item)
	return out


## True if engine stage `have` is `needs` or past it.
static func _stage_done(have: String, needs: String) -> bool:
	var order := ["", "stage1", "stage2", "stage3"]
	return order.find(have) >= order.find(needs)


func _horn_name(horn: Dictionary) -> String:
	for h: Dictionary in HORNS:
		if str(h["kind"]) == str(horn.get("kind", "car")) and is_equal_approx(float(h["pitch"]), float(horn.get("pitch", 0.0))):
			return str(h["name"]).to_lower() if str(h["id"]) == "stock" else str(h["name"])
	return "the horn it came with"


func _horn_items(car: Car) -> Array:
	var horn: Dictionary = _mods(car).get("horn", {}) if _mods(car).get("horn") is Dictionary else {}
	var out: Array = [_back()]
	for h: Dictionary in HORNS:
		var item := {"id": "horn_" + str(h["id"]), "name": str(h["name"]), "note": str(h["note"]), "price": int(h["price"])}
		var on := str(h["kind"]) == str(horn.get("kind", "car")) and is_equal_approx(float(h["pitch"]), float(horn.get("pitch", 0.0)))
		if on:
			item["enabled"] = false
			item["why"] = "That's the one on it."
			item["why_short"] = "Fitted"
		else:
			item["action"] = func(_i: Dictionary) -> String:
				set_mods(car, {"horn": {"kind": str(h["kind"]), "pitch": float(h["pitch"])}}, int(h["price"]))
				return "%s fitted. Try it (H)." % str(h["name"])
		out.append(item)
	return out


func _colour_name(c: Color) -> String:
	for col: Dictionary in COLOURS:
		if Color.html(str(col["hex"])).is_equal_approx(c):
			return str(col["name"])
	return "factory paint"


func _paint_items(car: Car) -> Array:
	var price := PAINT_PRICE_TRUCK if is_truck(car.model_id) else PAINT_PRICE
	var out: Array = [_back()]
	for col: Dictionary in COLOURS:
		var c := Color.html(str(col["hex"]))
		var item := {"id": "paint_" + str(col["name"]).to_snake_case(), "name": str(col["name"]), "price": price}
		if c.is_equal_approx(car.paint):
			item["enabled"] = false
			item["why"] = "It's that colour now."
			item["why_short"] = "Now"
		else:
			item["action"] = func(_i: Dictionary) -> String:
				repaint(car, c, price)
				return "Painted %s. Washed, too, no charge." % str(col["name"])
		out.append(item)
	return out

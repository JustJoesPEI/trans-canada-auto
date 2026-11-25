class_name UsedLot
extends Node
## The used lot at Reliable Motors on John Yeo Drive (docs/design.md
## section 6½): Mostly Reliable Used Cars, beaters at $3,000-8,000 so a new
## player has something to save up for in the first hour. And where you
## sell a car you own (the custom shop buys them too).
##
## The cars are a dealer lot's like any other (StreetProps._dealer_lots):
## the landmark's "used_lot" in map_config.json says which older models and
## how many new cars still go nearest the showroom; the rest are marked
## "used". Buying one goes through main.gd's _buy_parked_car like a new
## car, at sale_price here: fixed for each spot on the lot, so the same car
## costs the same every time you look.
##
##   UsedLot.sale_price(hit)    what a car for sale costs (new or used)
##   UsedLot.sale_prompt(hit)   the prompt beside it
##   UsedLot.sale_value(id)     what an owned vehicle sells for
##   UsedLot.sell_item(eco, by) the "Sell this car" item for a counter's card
##
## As a module (Economy.MODULES) it puts a counter on the lot: drive in and
## sell the car you're in.

const COUNTER_ID := "used_lot"
const TITLE := "Mostly Reliable Used Cars"
## Reliable Motors (OSM way 695948071), until the lot's cars are built and
## the counter moves to the middle of them.
const LOT_POS := [-63.15372, 46.27605]
## How close to the lot's middle counts as on it, in a car (m).
const REACH := 22.0
## What a used car can cost.
const MIN_PRICE := 3000
const MAX_PRICE := 8000
## Selling: this share of what you paid, and of what you spent on it at
## the custom shop.
const RESALE := 0.5
const RESALE_MODS := 0.25

const NOTES := [
	"one owner (a rally school)", "runs, mostly", "new-ish tires", "smells like fries",
	"winter beater, every winter", "rust is load-bearing", "check engine light is decorative",
	"AM radio, both stations", "driven to church on Sundays (and everywhere else)",
	"heater stuck on high", "passed inspection (in 2019)", "comes with a hockey bag",
]

var economy: Economy
var at := Vector3.ZERO
var _located := false
var _look := 0.0


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


## Where a used car stands rounded to a key, so its price and story don't
## change between looks.
static func _spot_hash(p: Vector3) -> int:
	return absi(hash(Vector3i(roundi(p.x * 2.0), 0, roundi(p.z * 2.0))))


## A used model's price at a spot: a fifth or so of new, between MIN_PRICE
## and MAX_PRICE, ending in 495 the way the lots price them.
static func used_price(model_id: String, p: Vector3) -> int:
	var h := _spot_hash(p)
	var share := 0.14 + 0.14 * float(h % 101) / 100.0
	var k := clampi(roundi(CarModels.price(model_id) * share / 500.0) * 500, MIN_PRICE, MAX_PRICE - 500)
	return k + 495


## How far it's been, by the odometer (km).
static func mileage(p: Vector3) -> int:
	return 160000 + (_spot_hash(p) >> 3) % 300 * 1000


static func note(p: Vector3) -> String:
	return NOTES[(_spot_hash(p) >> 5) % NOTES.size()]


## What a car for sale (a StreetProps.nearest_parked hit) costs.
static func sale_price(hit: Dictionary) -> int:
	var id := str(hit.get("model_id", "civique"))
	if bool(hit.get("used", false)):
		return used_price(id, hit.get("at", Vector3.ZERO))
	return CarModels.price(id)


## The prompt beside a car for sale.
static func sale_prompt(hit: Dictionary) -> String:
	var id := str(hit.get("model_id", "civique"))
	if not bool(hit.get("used", false)):
		return "Buy %s  %s" % [CarModels.full_name(id), CarModels.price_text(id)]
	var p: Vector3 = hit.get("at", Vector3.ZERO)
	return "Buy used %s, %s km, %s  %s" % [CarModels.full_name(id), _thousands(mileage(p)), note(p), CarModels.dollars(used_price(id, p))]


static func _thousands(n: int) -> String:
	return CarModels.dollars(n).trim_prefix("$")


## What owned vehicle `id` sells for: RESALE of what was paid (the dealer's
## price if the save doesn't say) and RESALE_MODS of the custom shop work.
static func sale_value(id: String) -> int:
	var v: Dictionary = _gs().call("vehicle", id)
	if v.is_empty():
		return 0
	var mods: Dictionary = v.get("mods", {})
	var paid := int(mods.get("paid", CarModels.price(str(v["model"]))))
	return roundi((paid * RESALE + int(mods.get("spent", 0)) * RESALE_MODS) / 50.0) * 50


## The "Sell this car" item for a counter's card (`by`: who's buying).
## Paid to you, not by you: no price on the card (-1), the action pays.
static func sell_item(eco: Economy, by: String) -> Dictionary:
	var car: Car = eco.player.get("vehicle") if eco != null and eco.player != null else null
	if car == null or car.garage_id == "":
		return {"id": "sell", "name": "Sell this car", "enabled": false, "why": "Drive in in a vehicle you own to sell it.", "why_short": ""}
	var value := sale_value(car.garage_id)
	return {"id": "sell", "name": "Sell the %s for %s" % [car.display_name(), CarModels.dollars(value)],
		"note": "%s will take it as it stands. You get out here." % by, "price": -1,
		"action": func(_i: Dictionary) -> String: return sell(eco, car)}


## Sells `car` (one of yours, the player in it or not): the money's paid,
## it's gone from the save, and it stays where it is, locked, the dealer's.
static func sell(eco: Economy, car: Car) -> String:
	if car == null or car.garage_id == "":
		return "That's not yours to sell."
	var value := sale_value(car.garage_id)
	var name := car.display_name()
	if eco != null and eco.player != null and eco.player.get("vehicle") == car:
		var cm := eco.counters.menu if eco.counters != null else null
		if cm != null:
			cm.close()
		if eco.main != null and eco.main.has_method("unseat_player"):
			eco.main.call("unseat_player")
	eco.owned_cars.release(car.garage_id)
	car.owner_id = "dealer"
	_gs().call("add_money", value)
	_gs().call("save_game")
	var msg := "Sold the %s for %s." % [name, CarModels.dollars(value)]
	if eco != null and eco.hud != null and eco.hud.has_method("show_title"):
		eco.hud.call("show_title", "Sold", msg)
	return msg


func setup(e: Economy) -> void:
	economy = e
	if e.world != null:
		at = e.world.edit_xform({"pos": LOT_POS}, 0.0).origin
	_add_counter()


func _add_counter() -> void:
	economy.counters.add({"id": COUNTER_ID, "title": TITLE, "subtitle": "Every car certified (by Gerald). Drive in to sell yours; the ones for sale are on the lot.",
		"at": at, "reach": REACH, "on_foot": false, "in_car": true, "kind": "dealer", "prompt": "Sell your car at " + TITLE,
		"items": func() -> Array: return [sell_item(economy, "Gerald")]})


## Once the lot's cars are built, the counter goes to the middle of them.
func _process(delta: float) -> void:
	if _located:
		return
	_look -= delta
	if _look > 0.0:
		return
	_look = 2.0
	var sum := Vector3.ZERO
	var n := 0
	for node: Node in get_tree().get_nodes_in_group("parked_cars"):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or not bool(mmi.get_meta("used", false)):
			continue
		for xf: Variant in mmi.get_meta("xforms", []):
			if xf is Transform3D:
				sum += (mmi.global_transform * (xf as Transform3D)).origin
				n += 1
	if n > 0:
		at = sum / float(n)
		_located = true
		_add_counter()

class_name SpudDash
extends Node
## SpudDash (docs/design.md sections 6 and 6½): food runs in your own car,
## the starter job. The phone's SpudDash app (Phone) lists 3 to 5 orders
## from food places near you (the world brands' drive-thrus, and the town's
## own restaurants under made-up names, data/city/kitchens.json from
## tools/make_kitchens.py), a new set every couple of minutes: the place,
## the order, who wants it and their line, the real address it goes to, an
## estimate and the pay for each GPS mode (less help pays more: Jobs.GPS_PAY).
## Taking one starts a two-stop job (kind "spuddash", counted toward the
## Delayed & Lost licence ladder):
##
##   1. Pick up: stop at the place's drive-thru (between the building and
##      its street) and wait a moment at the window, or for a restaurant,
##      out front while they run it out. The order goes in the car.
##   2. Drop off: park near the address and walk it to the door.
##
## Food condition starts at 100% at the window and drops with hard hits,
## big jolts (curbs, landings) and rolling over, faster for fragile orders
## (a tray of floats, an ice cream cake); it's on the job panel. Pay is
## Jobs' formula with condition 0.3 at 0% to 1.0 at 100%. At the door the
## customer tips pay × mood, mood 0-25% from the food and from paint on the
## car it came in (PaintCoverage: "My order arrived orange"), and rates the
## run with a line of text.

const KIND := "spuddash"
const REFRESH := 120.0 ## s between new sets of orders
const OFFER_RANGE := 1200.0 ## m: food places this near you make orders
const OFFER_FEWEST := 5 ## else the nearest this many do
const DROP_MIN := 250.0 ## m from the place to the address
const DROP_MAX := 1300.0
const MAX_TIP := 0.25
## Food lost per hit, before the order's fragility.
const CRASH_FROM := 4.0 ## m/s of jolt (Car.crashed starts there)
const CRASH_LOSS := 0.025 ## per m/s over it
const BUMP_FROM := 1.6 ## m/s of suspension punch (Car.bumped)
const BUMP_LOSS := 0.04
const ROLL_LOSS := 0.45
const HIT_GAP := 0.4 ## s: one knock, however many frames it shows in
## Paint coverage that leaves no tip at all.
const PAINT_NO_TIP := 0.35

var jobs: Jobs
var addresses: Addresses
var world: Node
var player: Node3D
var hud: Node
## Food places: {name, kind ("food", "coffee": a brand's drive-thru;
## "kitchen": a restaurant), food (kitchens: pizza, pub...), at: Vector2,
## pickup: Vector3, radius}.
var places: Array[Dictionary] = []
## Orders on offer now (see make_offer).
var offers: Array[Dictionary] = []
## The last run's rating: {stars, tip, line, client} ({} before the first).
var last_rating := {}

var _rng := RandomNumberGenerator.new()
var _offers_time := -INF
var _offers_near := Vector2.INF
var _next_id := 0
var _car: Node3D ## the car the order's riding in
var _rolled := false
var _crash_peak := 0.0
var _crash_until := 0.0
var _bump_until := 0.0
var _say := "" ## a line for the tab (why a job didn't start)


func setup(economy: Economy) -> void:
	start(economy.jobs, economy.addresses, economy.world, economy.player, economy.hud)
	var phone := Phone.find(get_tree())
	if phone != null:
		phone.add_app("spuddash", "SpudDash", Color(0.85, 0.3, 0.3), _build_tab)


## The parts it needs, without the town (tools/spuddash_check.gd).
func start(j: Jobs, a: Addresses, w: Node, p: Node3D, h: Node) -> void:
	jobs = j
	addresses = a
	world = w
	player = p
	hud = h
	_rng.randomize()
	_load_places()
	jobs.add_source(KIND, func(near: Vector3, n: int) -> Array:
		var out: Array = []
		for o in current_offers(Vector2(near.x, near.z)).slice(0, n):
			out.append(make_job(o, "route"))
		return out)


func _load_places() -> void:
	places.clear()
	var dir := "res://data/city"
	var data: Variant = world.get("data") if world != null else null
	if data is StreetData and (data as StreetData).city_dir != "":
		dir = (data as StreetData).city_dir
	for e: Dictionary in _read(dir.path_join("locations.json"), "locations"):
		if str(e["kind"]) in ["food", "coffee"]:
			_add_place(str(e["name"]), str(e["kind"]), "", e)
	for e: Dictionary in _read(dir.path_join("kitchens.json"), "kitchens"):
		_add_place(str(e["name"]), "kitchen", str(e["food"]), e)


static func _read(path: String, key: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	return (j as Dictionary).get(key, []) if j is Dictionary else []


func _add_place(name: String, kind: String, food: String, e: Dictionary) -> void:
	var at := Vector2(float(e["x"]), float(e["z"]))
	if world != null and world.has_method("is_in_play_area") and not bool(world.call("is_in_play_area", at)):
		return
	var spot := _pickup_spot(at, kind == "kitchen")
	places.append({"name": name, "kind": kind, "food": food, "at": at, "pickup": spot["at"], "radius": spot["radius"]})


## Where to stop: for a drive-thru, between the building and its street, a
## zone wide enough to take the lane, the lot's front and the curb; for a
## restaurant, the street out front.
func _pickup_spot(at: Vector2, curb: bool) -> Dictionary:
	var spot := at
	var radius := 14.0
	var net: Variant = world.get("network") if world != null else null
	if net is RoadNetwork:
		var near: Dictionary = (net as RoadNetwork).nearest_on_streets(at, 120.0)
		if not near.is_empty():
			var road: Vector2 = near["pos"]
			var d := at.distance_to(road)
			spot = at.lerp(road, 0.8 if curb else 0.55)
			radius = clampf(d * 0.5, 12.0, 20.0) if curb else clampf(d * 0.55, 12.0, 30.0)
	return {"at": _ground(spot), "radius": radius}


func _ground(p: Vector2) -> Vector3:
	var t: Variant = world.get("terrain") if world != null else null
	var y := (t as Terrain).height_at(p.x, p.y) if t is Terrain else 0.0
	return Vector3(p.x, y, p.y)


# --- orders ------------------------------------------------------------------------------------

## The orders on offer near `near` (x, z): kept for REFRESH seconds, or
## until you've gone far from where they were made (half OFFER_RANGE).
func current_offers(near: Vector2) -> Array[Dictionary]:
	var now := Time.get_ticks_msec() / 1000.0
	if offers.is_empty() or now - _offers_time > REFRESH or near.distance_to(_offers_near) > OFFER_RANGE * 0.5:
		new_offers(near)
	return offers


func new_offers(near: Vector2) -> void:
	offers.clear()
	_offers_time = Time.get_ticks_msec() / 1000.0
	_offers_near = near
	var close := places.filter(func(p: Dictionary) -> bool: return near.distance_to(p["at"]) <= OFFER_RANGE)
	if close.size() < OFFER_FEWEST:
		close = places.duplicate()
		close.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return near.distance_to(a["at"]) < near.distance_to(b["at"]))
		close = close.slice(0, OFFER_FEWEST)
	if close.is_empty():
		return
	var want := _rng.randi_range(3, 5)
	# Each place once before any twice.
	var order: Array = []
	for i in want * 4:
		if i % close.size() == 0:
			var batch := close.duplicate()
			batch.shuffle()
			order.append_array(batch)
	var tries := 0
	while offers.size() < want and tries < order.size():
		var o := make_offer(order[tries], near)
		tries += 1
		if o.is_empty() or offers.any(func(x: Dictionary) -> bool: return Addresses.text(x["address"]) == Addresses.text(o["address"])):
			continue
		offers.append(o)


## An order from `place` for someone 250-1300 m away: {id, place, address,
## order, fragile, client, line, distance (m, you to the place to the
## door), base ($, before the GPS factor), estimate (s)}. {} if there's
## nowhere to take it.
func make_offer(place: Dictionary, near: Vector2) -> Dictionary:
	var a := addresses.pick(place["at"], DROP_MIN, DROP_MAX, ["home", "apartments"]) if addresses != null else {}
	if a.is_empty():
		return {}
	var order := SpudDashLines.order_for(place, _rng)
	var door := Vector2(a["x"], a["z"])
	var dist := near.distance_to(place["at"]) + (place["at"] as Vector2).distance_to(door)
	_next_id += 1
	return {
		"id": _next_id,
		"place": place,
		"address": a,
		"order": str(order[0]),
		"fragile": float(order[1]),
		"client": SpudDashLines.CLIENTS[_rng.randi() % SpudDashLines.CLIENTS.size()],
		"line": _fresh_line(),
		"distance": dist,
		# About $110-310 a run with the time and GPS factors: about $3,000
		# an hour on the route GPS with a quick run and a fair tip, more
		# for those who know the town well enough to go by the address
		# (design.md 6½, "Pacing").
		"base": int(snappedf(clampf(70.0 + dist * 0.12, 100.0, 230.0), 5.0)),
		# Streets wind about a third further than the crow flies; ~9 m/s in town,
		# and a minute for the window and the walk to the door.
		"estimate": roundf(60.0 + dist * 1.35 / 9.0),
	}


## A client line not already on the list.
func _fresh_line() -> String:
	var lines := SpudDashLines.LINES.filter(func(l: String) -> bool: return not offers.any(func(o: Dictionary) -> bool: return o["line"] == l))
	return lines[_rng.randi() % lines.size()] if not lines.is_empty() else SpudDashLines.LINES[0]


## What an offer pays with a GPS mode, at the estimate with the food intact.
static func pay_for(offer: Dictionary, mode: String) -> int:
	return roundi(float(offer["base"]) * float(Jobs.GPS_PAY.get(mode, 1.0)))


## The job for an offer, with the GPS help chosen.
func make_job(offer: Dictionary, mode: String) -> Dictionary:
	var place: Dictionary = offer["place"]
	var a: Dictionary = offer["address"]
	var addr := Addresses.text(a)
	var door := Addresses.lawn(a, 0.85)
	var kitchen := str(place["kind"]) == "kitchen"
	var data := {"offer": offer, "food": 1.0, "fragile": float(offer["fragile"]), "picked": false, "car": null, "coverage": 0.0, "colour": Color.WHITE}
	return {
		"kind": KIND,
		"company": "SpudDash",
		"title": "%s to %s" % [offer["order"], addr],
		"client": offer["client"],
		"line": "\"%s\" (%s)" % [offer["line"], offer["client"]],
		"pay": int(offer["base"]),
		"estimate": float(offer["estimate"]),
		"gps": mode,
		"cargo": "Food",
		"cargo_state": func(job: Dictionary) -> float: return float(job["data"]["food"]),
		"condition": func(job: Dictionary) -> float: return 0.3 + 0.7 * float(job["data"]["food"]),
		"stops": [
			{"name": "Pick up", "address": str(place["name"]), "at": place["pickup"], "radius": float(place["radius"]), "wait": 3.0,
				"in_vehicle": null if kitchen else true,
				"wrong_way": "" if kitchen else "The window serves cars. Feet are a liability",
				"hint": "Pull up or walk up out front; they'll run it out" if kitchen else "Stop at the drive-thru window", "on_reach": _picked_up},
			{"name": "Drop off", "address": addr, "at": _ground(door), "radius": 5.0, "wait": 1.0, "in_vehicle": false,
				"wrong_way": "Out of the car. Nobody tips a bumper",
				"hint": "Park and walk it to the door", "on_reach": _dropped},
		],
		"on_finish": _finished,
		"on_cancel": func(_job: Dictionary) -> void: _carry(null),
		"data": data,
	}


func take(offer: Dictionary, mode: String) -> String:
	var why := jobs.start(make_job(offer, mode))
	if why == "":
		offers.erase(offer)
	return why


# --- the run -----------------------------------------------------------------------------------

func _picked_up(_s: Dictionary, job: Dictionary) -> void:
	job["data"]["picked"] = true
	job["data"]["food"] = 1.0
	_carry(player.get("vehicle") as Node3D if player != null else null)


## At the door: note the paint on the car it came in, for the tip.
func _dropped(_s: Dictionary, job: Dictionary) -> void:
	var car: Variant = job["data"]["car"]
	if car is Node3D and is_instance_valid(car):
		var pc := (car as Node3D).get_node_or_null("PaintCoverage") as PaintCoverage
		if pc != null:
			job["data"]["coverage"] = pc.coverage
			job["data"]["colour"] = _paint_colour(pc)
	_carry(null)


static func _paint_colour(pc: PaintCoverage) -> Color:
	if pc.hits.is_empty():
		return Color.WHITE
	var sum := Color(0, 0, 0, 0)
	for h: Dictionary in pc.hits:
		sum += h["colour"] as Color
	return sum / float(pc.hits.size())


## The customer's mood (the tip, 0 to MAX_TIP of the pay) from the food
## (0..1) and the paint on the car (coverage 0..1).
static func mood(food: float, coverage: float) -> float:
	return MAX_TIP * food_part(food) * paint_part(coverage)


static func food_part(food: float) -> float:
	return clampf((food - 0.35) / 0.6, 0.0, 1.0)


static func paint_part(coverage: float) -> float:
	return clampf(1.0 - coverage / PAINT_NO_TIP, 0.0, 1.0)


## The rating: {stars 1-5, tip, line}.
static func rate(pay: int, food: float, coverage: float, colour: Color, slow: bool, rng: RandomNumberGenerator) -> Dictionary:
	var m := mood(food, coverage)
	var stars := clampi(roundi(1.0 + 4.0 * m / MAX_TIP), 1, 5)
	var line := ""
	if coverage >= 0.03 and paint_part(coverage) <= food_part(food):
		line = (SpudDashLines.PAINTED[rng.randi() % SpudDashLines.PAINTED.size()] as String) % SpudDashLines.colour_name(colour)
	elif food < 0.5:
		line = SpudDashLines.WRECKED[rng.randi() % SpudDashLines.WRECKED.size()]
	elif food < 0.85:
		line = SpudDashLines.BUMPY[rng.randi() % SpudDashLines.BUMPY.size()]
	elif slow:
		line = SpudDashLines.SLOW[rng.randi() % SpudDashLines.SLOW.size()]
	else:
		line = SpudDashLines.HAPPY[rng.randi() % SpudDashLines.HAPPY.size()]
	return {"stars": stars, "tip": roundi(float(pay) * m), "line": line}


func _finished(job: Dictionary, pay: int) -> void:
	_carry(null)
	var d: Dictionary = job["data"]
	var slow := jobs.elapsed() > float(job.get("estimate", 300.0)) * 1.2 if jobs != null else false
	var r := rate(pay, float(d["food"]), float(d["coverage"]), d["colour"], slow, _rng)
	r["client"] = str(job.get("client", ""))
	r["food"] = float(d["food"])
	last_rating = r
	if int(r["tip"]) > 0:
		get_tree().root.get_node("GameState").call("add_money", int(r["tip"]))
	# After Jobs' "Job done" title has had its moment.
	if hud != null and hud.has_method("show_title"):
		var h := hud
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			if is_instance_valid(h):
				h.call("show_title", "%d/5 from %s · tip %s" % [int(r["stars"]), r["client"], CarModels.dollars(int(r["tip"]))], "\"%s\"" % r["line"]))


# --- the food in the car -----------------------------------------------------------------------

## Watch `car` for knocks (null: stop watching).
func _carry(car: Node3D) -> void:
	if _car != null and is_instance_valid(_car):
		if _car.has_signal("crashed") and _car.is_connected("crashed", _on_crashed):
			_car.disconnect("crashed", _on_crashed)
		if _car.has_signal("bumped") and _car.is_connected("bumped", _on_bumped):
			_car.disconnect("bumped", _on_bumped)
	_car = car
	_rolled = false
	if car == null:
		return
	if car.has_signal("crashed"):
		car.connect("crashed", _on_crashed)
	if car.has_signal("bumped"):
		car.connect("bumped", _on_bumped)
	var job := _run()
	if not job.is_empty():
		job["data"]["car"] = car


## The SpudDash run under way with the food on board ({} for none).
func _run() -> Dictionary:
	if jobs == null or str(jobs.active.get("kind", "")) != KIND or not bool(jobs.active["data"]["picked"]):
		return {}
	return jobs.active


## Takes `amount` (before fragility) off the food.
func spill(amount: float) -> void:
	var job := _run()
	if job.is_empty():
		return
	var d: Dictionary = job["data"]
	d["food"] = clampf(float(d["food"]) - amount * float(d["fragile"]), 0.0, 1.0)


static func crash_loss(jolt: float) -> float:
	return clampf((jolt - CRASH_FROM) * CRASH_LOSS, 0.0, 0.6)


func _on_crashed(jolt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _crash_until:
		# The same knock over several frames: only what it adds.
		if jolt > _crash_peak:
			spill(crash_loss(jolt) - crash_loss(_crash_peak))
			_crash_peak = jolt
		return
	_crash_until = now + HIT_GAP
	_crash_peak = jolt
	spill(crash_loss(jolt))


func _on_bumped(punch: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if punch < BUMP_FROM or now < _bump_until:
		return
	_bump_until = now + HIT_GAP
	spill(clampf((punch - BUMP_FROM) * BUMP_LOSS, 0.0, 0.4))


func _process(_delta: float) -> void:
	var job := _run()
	if job.is_empty():
		if _car != null:
			_carry(null)
		return
	# The order rides in whatever you're driving; on foot you carry it.
	var v: Variant = player.get("vehicle") if player != null and is_instance_valid(player) else null
	var car := v as Node3D if v is Node3D else null
	if car != null and car != _car:
		_carry(car)
	if _car != null and is_instance_valid(_car):
		var up := _car.global_transform.basis.y.normalized().dot(Vector3.UP)
		if up < 0.2 and not _rolled:
			_rolled = true
			spill(ROLL_LOSS)
		elif up > 0.7:
			_rolled = false


# --- the phone ---------------------------------------------------------------------------------

func _build_tab(box: VBoxContainer) -> void:
	var phone := Phone.find(get_tree())
	var tag := HudStyle.label(14, false, HudStyle.DIM, false)
	tag.text = "Island food, eventually."
	box.add_child(tag)
	if _say != "":
		box.add_child(_wrapped(_say, 15, HudStyle.WARN))
		_say = ""
	if str(jobs.active.get("kind", "")) == KIND:
		var j := jobs.active
		box.add_child(_wrapped("On a run: %s. Food %d%%." % [j.get("title", ""), roundi(float(j["data"]["food"]) * 100.0)], 15, Color.WHITE))
	var here := Vector2.ZERO
	if player != null and is_instance_valid(player):
		here = Vector2(player.global_position.x, player.global_position.z)
	var list := current_offers(here)
	if list.is_empty():
		box.add_child(_wrapped("No orders near you. Everyone's cooking at home, for once.", 15, HudStyle.DIM))
	for o in list:
		box.add_child(_gap())
		var place: Dictionary = o["place"]
		box.add_child(_wrapped("%s, for %s" % [place["name"], Addresses.text(o["address"])], 18, Color.WHITE, true))
		var est := int(o["estimate"])
		box.add_child(_wrapped("%s  ·  %s  ·  about %d:%02d" % [o["order"], HudStyle.distance_text(float(o["distance"])), est / 60, est % 60], 14, HudStyle.DIM))
		box.add_child(_wrapped("\"%s\" (%s)" % [o["line"], o["client"]], 14, HudStyle.TEXT))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 4)
		box.add_child(row)
		for mode: String in ["route", "directions", "address"]:
			var offer: Dictionary = o
			var m := mode
			row.add_child(phone.make_button("%s %s" % [mode.capitalize(), CarModels.dollars(pay_for(o, mode))], func() -> void:
				var why := take(offer, m)
				if why == "":
					phone.close()
				else:
					_say = why
					phone.refresh()))
	box.add_child(_gap())
	var left := maxi(0, int(REFRESH - (Time.get_ticks_msec() / 1000.0 - _offers_time)))
	var foot := "Route draws the way, Directions calls the turns, Address is just the address: less help pays more. New orders in about %d:%02d." % [left / 60, left % 60]
	box.add_child(_wrapped(foot, 13, HudStyle.DIM))
	var done := int(get_tree().root.get_node("GameState").call("jobs_done_count", KIND))
	var tally := "Runs done: %d" % done
	if not last_rating.is_empty():
		tally += ". Last: %d/5 from %s, \"%s\"" % [int(last_rating["stars"]), last_rating["client"], last_rating["line"]]
	box.add_child(_wrapped(tally, 13, HudStyle.DIM))


func _wrapped(text: String, size: int, colour: Color, heading := false) -> Label:
	var l := HudStyle.label(size, heading, colour, false)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 6
	return c

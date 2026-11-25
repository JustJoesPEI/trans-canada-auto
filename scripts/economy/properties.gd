class_name Properties
extends Node
## Where your vehicles live (docs/design.md section 6½, "Property"): a
## module of Economy. How many vehicles you can keep is GameState's
## storage_spaces(): one on the street, plus each place you own:
##
##   a pass at a parkade (Queen, Pownal, Fitzroy): a pay machine on the
##     ground floor sells it; marked stalls on level 2
##   a suite at the Gamma Prince Edward (the hotel at the bottom of Queen
##     Street): the front desk on Queen Street sells it; stalls in the
##     parking under the hotel (UndergroundGarage); change clothes there
##
## Any of them can be made home: you start the game there, in the aisle by
## your first stall (home_spawn, asked by WorldBuilder.get_spawn).
##
## A stored car (OwnedCars.put_away) waits in one of your stalls: it's
## shown there while you're near, and getting in takes it out again. Drive
## into your stalls and press the interact key to store the car you're in.
## The Garage tab on the map (the phone) lists every vehicle you own and
## where it is, with a waypoint to it, "Bring it round" (a valet drives it
## to the curb near you, for VALET_FEE) and "Store it" when you're at one
## of your places.

## Everything you can own, by id (what GameState.properties holds):
##   building  the OSM id of its building (a parkade, or the hotel)
##   level, side, first  parkades: the stalls are on `level`, `side` of the
##             ramp, from stall `first` (Parkade.stall_xform)
##   first     the hotel: the first of its stalls in the garage's far row
const PLACES := {
	"queen_parkade": {"name": "Queen Parkade", "short": "Queen Parkade", "kind": "parkade", "building": "28326012",
		"spaces": 3, "price": 5000, "level": 1, "side": -1, "first": 4},
	"pownal_parkade": {"name": "Pownal Parkade", "short": "Pownal Parkade", "kind": "parkade", "building": "28326014",
		"spaces": 2, "price": 4000, "level": 1, "side": -1, "first": 4},
	"fitzroy_parkade": {"name": "Fitzroy Parkade", "short": "Fitzroy Parkade", "kind": "parkade", "building": "28331937",
		"spaces": 3, "price": 5500, "level": 1, "side": -1, "first": 4},
	"gamma_suite": {"name": "Suite at the Gamma Prince Edward", "short": "the Gamma Prince Edward", "kind": "hotel",
		"building": "28326186", "spaces": 4, "price": 40000, "first": 2},
}

const VALET_FEE := 150
## m: stored cars are shown in their stalls while you're this close, and
## put away again past HIDE_DIST.
const SHOW_DIST := 120.0
const HIDE_DIST := 170.0

var economy: Economy
var world: WorldBuilder
var player: Node3D
var _shown := {} ## vehicle id -> property id, for stored cars shown in their stalls
var _marks := {} ## property id -> Node3D (the paint and signs on its stalls)
var _wardrobe: CanvasLayer


static func find(tree: SceneTree) -> Properties:
	return tree.get_first_node_in_group("properties") as Properties if tree != null else null


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


## Tells GameState how many spaces each place gives.
static func register_spaces() -> void:
	for id: String in PLACES:
		GameState.property_spaces[id] = int(PLACES[id]["spaces"])


func _ready() -> void:
	add_to_group("properties")


func setup(e: Economy) -> void:
	economy = e
	world = e.world
	player = e.player
	register_spaces()
	for id: String in PLACES:
		_add_counters(id)
	_gs().connect("properties_changed", _refresh_marks)
	_refresh_marks()
	var map := WorldMap.find(get_tree())
	if map != null:
		map.add_tab("garage", "Garage", _build_tab)


# --- where things are ---------------------------------------------------------------------

## The parkade's or garage's layout for property `id` ({} if not found).
static func layout_of(w: WorldBuilder, id: String) -> Dictionary:
	var p: Dictionary = PLACES.get(id, {})
	if p.is_empty() or w == null or w.data == null:
		return {}
	if str(p["kind"]) == "parkade":
		return Parkade.find(w.data, w.network, w.terrain, str(p["building"]))
	return UndergroundGarage.find(w.data, w.terrain, str(p["building"]))


## Where a car stored in stall `i` of property `id` stands.
static func stall_xform(w: WorldBuilder, id: String, i: int) -> Transform3D:
	var p: Dictionary = PLACES[id]
	var lay := layout_of(w, id)
	if lay.is_empty():
		return Transform3D.IDENTITY
	if str(p["kind"]) == "parkade":
		return Parkade.stall_xform(lay, int(p["level"]), int(p["side"]), int(p["first"]) + i)
	return UndergroundGarage.stall_xform(lay, int(p["first"]) + i)


## Standing in the aisle in front of stall `i`.
static func aisle_xform(w: WorldBuilder, id: String, i: int) -> Transform3D:
	var p: Dictionary = PLACES[id]
	var lay := layout_of(w, id)
	if lay.is_empty():
		return Transform3D.IDENTITY
	if str(p["kind"]) == "parkade":
		return Parkade.aisle_xform(lay, int(p["level"]), int(p["side"]), int(p["first"]) + i)
	return UndergroundGarage.aisle_xform(lay, int(p["first"]) + i)


## Where you start if you've made a place you own home: {"xform"}, or {}.
static func home_spawn(w: WorldBuilder) -> Dictionary:
	var home := str(GameState.home)
	if home == "" or not PLACES.has(home) or not GameState.owns_property(home):
		return {}
	if layout_of(w, home).is_empty():
		return {}
	return {"xform": aisle_xform(w, home, 0)}


## The pay machine (a parkade's, on the ground floor by the way in) or the
## front desk (the hotel's, on the street by the garage's way in).
static func desk_point(w: WorldBuilder, id: String) -> Vector3:
	var lay := layout_of(w, id)
	if lay.is_empty():
		return Vector3.INF
	if str(PLACES[id]["kind"]) == "parkade":
		return Parkade.world_point(lay, float(lay["hu"]) - 1.2, 0.0, 0, 0.0)
	var p := UndergroundGarage.world_point(lay, -2.0, -UndergroundGarage.OPENING * 0.5 - 6.0)
	return Vector3(p.x, w.terrain.h2(Vector2(p.x, p.z)), p.z)


## The vehicles stored at property `id`, in stall order.
static func stored_at(id: String) -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in GameState.vehicles:
		if str(v.get("stored", "")) == id:
			out.append(str(v["id"]))
	return out


## Is `p` in property `id`'s building (on its stall level for the hotel)?
func is_at(id: String, p: Vector3) -> bool:
	var lay := layout_of(world, id)
	if lay.is_empty():
		return false
	if str(PLACES[id]["kind"]) == "parkade":
		var d := Vector2(p.x, p.z) - (lay["c"] as Vector2)
		return absf(d.dot(lay["u"])) < float(lay["hu"]) + 2.0 and absf(d.dot(lay["v"])) < float(lay["hv"]) + 2.0 \
			and p.y > float(lay["floor_y"]) - 2.0 and p.y < float(lay["floor_y"]) + int(lay["levels"]) * Parkade.STOREY
	return UndergroundGarage.contains(lay, p, 1.0)


## The place you own that `p` is in ("" for none).
func owned_place_at(p: Vector3) -> String:
	for id: String in PLACES:
		if GameState.owns_property(id) and is_at(id, p):
			return id
	return ""


# --- the counters -------------------------------------------------------------------------

func _add_counters(id: String) -> void:
	var p: Dictionary = PLACES[id]
	var at := desk_point(world, id)
	if at == Vector3.INF:
		return
	var hotel := str(p["kind"]) == "hotel"
	economy.counters.add({"id": "property_" + id, "title": "Gamma Prince Edward" if hotel else str(p["name"]),
		"subtitle": "Front desk" if hotel else "Pay machine: monthly passes", "at": at, "reach": 2.5,
		"kind": "hotel" if hotel else "parkade", "map_name": "Gamma Prince Edward" if hotel else str(p["name"]),
		"prompt": "Front desk" if hotel else "Pay machine", "items": func() -> Array: return _desk_items(id)})
	# At your stalls, in a car: store it.
	var mid := stall_xform(world, id, int(p["spaces"]) / 2)
	economy.counters.add({"id": "stalls_" + id, "title": "Your spaces", "subtitle": str(p["name"]),
		"at": mid.origin, "reach": 9.0, "on_foot": false, "in_car": true, "kind": "",
		"prompt": "Store this car", "items": func() -> Array: return _stall_items(id)})


func _desk_items(id: String) -> Array:
	var p: Dictionary = PLACES[id]
	var owned: bool = GameState.owns_property(id)
	var hotel := str(p["kind"]) == "hotel"
	var items: Array = []
	if owned:
		var n := stored_at(id).size()
		items.append({"id": "have", "name": "Yours: %d space%s" % [int(p["spaces"]), "" if int(p["spaces"]) == 1 else "s"],
			"note": "%d car%s stored here" % [n, "" if n == 1 else "s"], "price": 0, "enabled": false,
			"why": "Drive into your stalls to store a car."})
	else:
		items.append({"id": "buy", "name": "A suite" if hotel else "Monthly pass", "price": int(p["price"]),
			"note": "%d spaces in the parking under the hotel; you can live here" % int(p["spaces"]) if hotel \
				else "%d marked spaces on level 2" % int(p["spaces"]),
			"action": func(_it: Dictionary) -> String: return _buy(id)})
	if owned:
		if str(GameState.home) == id:
			items.append({"id": "home", "name": "This is home", "note": "You start the game here", "price": 0,
				"enabled": false, "why": "It's already home."})
		else:
			items.append({"id": "home", "name": "Make it home", "note": "Start the game here", "price": 0,
				"action": func(_it: Dictionary) -> String:
					GameState.set_home(id)
					return "Home is %s now." % str(p["short"])})
		if hotel:
			items.append({"id": "clothes", "name": "Change clothes", "note": "Up in your suite", "price": 0,
				"action": func(_it: Dictionary) -> String:
					economy.counters.menu.close()
					_open_wardrobe.call_deferred()
					return ""})
	return items


func _buy(id: String) -> String:
	GameState.add_property(id)
	var p: Dictionary = PLACES[id]
	if str(GameState.home) == "" and str(p["kind"]) == "hotel":
		GameState.set_home(id)
		return "It's yours, and home now: you'll start here. %d spaces downstairs." % int(p["spaces"])
	return "It's yours: %d more spaces (%d in all)." % [int(p["spaces"]), int(GameState.storage_spaces())]


func _stall_items(id: String) -> Array:
	if not GameState.owns_property(id):
		return [{"id": "none", "name": "Reserved", "note": "Pass holders only", "price": 0, "enabled": false,
			"why": "Buy a pass to park here." if str(PLACES[id]["kind"]) == "parkade" else "These are for guests in the suites."}]
	var car: Car = player.get("vehicle") as Car
	var why := _why_not_store(id, car)
	return [{"id": "store", "name": "Store this car", "note": "%d of %d spaces used" % [stored_at(id).size(), int(PLACES[id]["spaces"])],
		"price": 0, "enabled": why == "", "why": why,
		"action": func(_it: Dictionary) -> String:
			economy.counters.menu.close()
			store(car.garage_id, id)
			return ""}]


func _why_not_store(id: String, car: Car) -> String:
	if car == null or car.garage_id == "" or GameState.vehicle(car.garage_id).is_empty():
		return "Only a car you own."
	if stored_at(id).has(car.garage_id):
		return "It's already stored here."
	if stored_at(id).size() >= int(PLACES[id]["spaces"]):
		return "Your spaces here are full."
	return ""


# --- storing and bringing round -------------------------------------------------------------

## Puts owned vehicle `vid` away in a free stall of property `id` (getting
## you out first if you're in it) and shows it parked there. False if
## there's no room or it isn't yours.
func store(vid: String, id: String) -> bool:
	if GameState.vehicle(vid).is_empty() or not GameState.owns_property(id):
		return false
	var here := stored_at(id)
	if not here.has(vid) and here.size() >= int(PLACES[id]["spaces"]):
		return false
	var owned := economy.owned_cars
	var car := owned.car_for(vid)
	if car != null and player.get("vehicle") == car:
		_get_out()
	owned.put_away(vid, id)
	_shown.erase(vid)
	_show_stored(id)
	_say("Stored", "Your %s is in %s." % [_model_name(vid), str(PLACES[id]["short"])])
	return true


## A valet brings owned vehicle `vid` to the curb near you, for VALET_FEE
## (nothing if it's already near). The Car, or null if it couldn't.
func bring_round(vid: String) -> Car:
	var v: Dictionary = GameState.vehicle(vid)
	if v.is_empty():
		return null
	var owned := economy.owned_cars
	var car := owned.car_for(vid)
	if car != null and player.get("vehicle") == car:
		return car
	if Wanted.level > 0:
		_say("Not now", "No valet will come out while the police are after you.")
		return null
	if not GameState.spend_money(VALET_FEE):
		_say("Not enough money", "The valet is %s; you have %s." % [CarModels.dollars(VALET_FEE), CarModels.dollars(GameState.money)])
		return null
	var stored_in := str(v.get("stored", ""))
	_shown.erase(vid)
	car = owned.spawn(vid, curb_spot(player.global_position))
	if car != null:
		_say("On its way", "Your %s is at the curb%s." % [_model_name(vid), " from " + str(PLACES[stored_in]["short"]) if PLACES.has(stored_in) else ""])
		if is_inside_tree():
			_refresh_tab()
	return car


## A spot against the curb on the street nearest `at`, facing along it.
func curb_spot(at: Vector3) -> Transform3D:
	var p := Vector2(at.x, at.z)
	var hit := world.network.nearest_on_streets(p, 300.0)
	if hit.is_empty():
		return Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.5)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var sp: Array = RoadNetwork.sample(e.points, clampf(float(hit["along"]), minf(8.0, e.length * 0.5), maxf(e.length * 0.5, e.length - 8.0)))
	var q: Vector2 = sp[0]
	var dir: Vector2 = sp[1]
	q += Vector2(-dir.y, dir.x) * maxf(0.0, e.half_width - 1.4)
	var y := world.terrain.h2(q)
	if player != null and player.is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, y + 6.0, q.y), Vector3(q.x, y - 4.0, q.y), Layers.GROUND)
		var h := player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not h.is_empty():
			y = float(h["position"].y)
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(q.x, y + 0.4, q.y))


func _get_out() -> void:
	var main := economy.main
	if main == null:
		return
	player.get("model").visible = true
	player.call("exit_vehicle", main)
	var rig: Variant = main.get("camera_rig")
	if rig != null:
		rig.set("target", player)
		rig.call("set_vehicle_mode", false)


## Stored cars at property `id` as cars in their stalls.
func _show_stored(id: String) -> void:
	var owned := economy.owned_cars
	var list := stored_at(id)
	for i in list.size():
		var vid := list[i]
		if _shown.has(vid) and owned.car_for(vid) != null:
			continue
		var car := owned.spawn(vid, stall_xform(world, id, i))
		# Still stored: spawn takes it out, so put the mark back.
		GameState.set_vehicle(vid, {"stored": id}, false)
		if car != null:
			_shown[vid] = id


func _process(_delta: float) -> void:
	if player == null or economy == null:
		return
	var owned := economy.owned_cars
	var in_car: Variant = player.get("vehicle")
	# Got into a stored car: it's out.
	for vid: String in _shown.keys():
		var car := owned.car_for(vid)
		if car == null:
			_shown.erase(vid)
		elif in_car == car:
			_shown.erase(vid)
			GameState.set_vehicle(vid, {"stored": ""})
	var p := player.global_position
	for id: String in GameState.properties:
		if not PLACES.has(id):
			continue
		var at := stall_xform(world, id, 0).origin
		var d := p.distance_to(at)
		if d < SHOW_DIST:
			for vid in stored_at(id):
				if not _shown.has(vid):
					_show_stored(id)
					break
		elif d > HIDE_DIST:
			for vid: String in _shown.keys():
				if str(_shown[vid]) == id and owned.car_for(vid) != in_car:
					owned.put_away(vid, id)
					_shown.erase(vid)


# --- the stalls' marks ---------------------------------------------------------------------

## Yellow paint and a sign at each stall of the places you own.
func _refresh_marks() -> void:
	for id: String in PLACES:
		var want: bool = GameState.owns_property(id)
		if want and not _marks.has(id):
			var m := _make_marks(id)
			if m != null:
				_marks[id] = m
				add_child(m)
		elif not want and _marks.has(id):
			(_marks[id] as Node).queue_free()
			_marks.erase(id)


func _make_marks(id: String) -> Node3D:
	if layout_of(world, id).is_empty():
		return null
	var root := Node3D.new()
	root.name = "Marks_" + id
	var kit := MeshKit.new()
	var hotel := str(PLACES[id]["kind"]) == "hotel"
	var depth := UndergroundGarage.STALL_DEPTH if hotel else Parkade.STALL_DEPTH
	var width := UndergroundGarage.STALL_WIDTH if hotel else Parkade.STALL_WIDTH
	for i in int(PLACES[id]["spaces"]):
		var x := stall_xform(world, id, i)
		var o := x.origin - x.basis.y * 0.33 + Vector3.UP * 0.02
		var fwd := -x.basis.z # nose, toward the aisle
		var side := x.basis.x
		# A yellow bar across the stall's mouth, and one down each side.
		var mouth := o + fwd * (depth * 0.5 - 0.15)
		kit.quad(mouth - side * width * 0.5 - fwd * 0.1, mouth + side * width * 0.5 - fwd * 0.1,
			mouth + side * width * 0.5 + fwd * 0.1, mouth - side * width * 0.5 + fwd * 0.1, Vector3.UP)
		var label := Label3D.new()
		label.text = "%s\n%d" % ["SUITE" if hotel else "PASS", i + 1]
		label.font_size = 64
		label.pixel_size = 0.007
		label.outline_size = 0
		label.modulate = Color(1.0, 0.84, 0.2)
		label.double_sided = false
		var back := o - fwd * (depth * 0.5 - 0.02)
		label.position = back + Vector3.UP * 1.7
		label.rotation.y = StreetProps.yaw_facing(Vector2(fwd.x, fwd.z))
		root.add_child(label)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit_indexed(null, Materials.get_shared().paint_yellow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


# --- changing clothes ----------------------------------------------------------------------

func _open_wardrobe() -> void:
	if _wardrobe != null:
		return
	_wardrobe = CanvasLayer.new()
	_wardrobe.layer = 80
	_wardrobe.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_wardrobe)
	var creator := CharacterCreator.new()
	_wardrobe.add_child(creator)
	var model: HumanoidModel = player.get("model")
	var look: Dictionary = PlayerLook.load_look()
	if model != null:
		look = {"skin": model.skin, "hair": model.hair, "hair_style": model.hair_style, "height": model.height,
			"build": model.build, "outfit": Outfit.complete(model.outfit)}
	look["paint"] = player.get("paint_colour")
	creator.closed.connect(func(saved: bool) -> void:
		if saved and model != null:
			model.set_look(PlayerLook.copy(creator.look))
			player.set("paint_colour", creator.look.get("paint", player.get("paint_colour")))
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_wardrobe.queue_free()
		_wardrobe = null)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	creator.open(look)


# --- the Garage tab --------------------------------------------------------------------------

func _refresh_tab() -> void:
	var map := WorldMap.find(get_tree())
	if map != null and map.visible:
		map.refresh_tab()


func _build_tab(box: VBoxContainer) -> void:
	var map := WorldMap.find(get_tree())
	var head := HudStyle.label(22, true, Color.WHITE, false)
	head.text = "Garage: %d of %d spaces" % [GameState.vehicles.size(), GameState.storage_spaces()]
	box.add_child(head)
	if GameState.vehicles.is_empty():
		box.add_child(_line("You don't own a car yet. Buy one at a dealer: it's yours to keep."))
	var at_place := owned_place_at(player.global_position)
	for v: Dictionary in GameState.vehicles:
		var vid := str(v["id"])
		var name := HudStyle.label(17, true, HudStyle.ACCENT, false)
		name.text = _model_name(vid)
		box.add_child(name)
		box.add_child(_line(where_text(vid)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var pos := vehicle_position(vid)
		var driving: bool = economy.owned_cars.car_for(vid) != null and player.get("vehicle") == economy.owned_cars.car_for(vid)
		if pos != Vector3.INF and not driving:
			row.add_child(map.make_button("Waypoint", func() -> void:
				var gps := Gps.find(get_tree())
				if gps != null:
					gps.set_waypoint(pos, _model_name(vid), "route")
				map.refresh_tab()))
		if not driving:
			row.add_child(map.make_button("Bring it round (%s)" % CarModels.dollars(VALET_FEE), func() -> void:
				bring_round(vid)
				map.refresh_tab()))
		if at_place != "" and str(v.get("stored", "")) != at_place and _why_not_store(at_place, economy.owned_cars.car_for(vid)) == "" \
				and economy.owned_cars.car_for(vid) != null and is_at(at_place, economy.owned_cars.car_for(vid).global_position):
			row.add_child(map.make_button("Store it", func() -> void:
				store(vid, at_place)
				map.refresh_tab()))
	var places := HudStyle.label(20, true, Color.WHITE, false)
	places.text = "Places"
	box.add_child(places)
	var any := false
	for id: String in PLACES:
		if not GameState.owns_property(id):
			continue
		any = true
		var p: Dictionary = PLACES[id]
		var n := stored_at(id).size()
		box.add_child(_line("%s%s: %d of %d spaces used" % [str(p["name"]), " (home)" if str(GameState.home) == id else "", n, int(p["spaces"])]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var spot := stall_xform(world, id, 0).origin
		row.add_child(map.make_button("Waypoint", func() -> void:
			var gps := Gps.find(get_tree())
			if gps != null:
				gps.set_waypoint(spot, str(p["name"]), "route")
			map.refresh_tab()))
		if str(GameState.home) != id:
			row.add_child(map.make_button("Make it home", func() -> void:
				GameState.set_home(id)
				map.refresh_tab()))
	if not any:
		box.add_child(_line("One car fits on the street. For more, buy a pass at a parkade's pay machine (Queen, Pownal, Fitzroy) or a suite at the Gamma Prince Edward's front desk."))


func _line(text: String) -> Label:
	var l := HudStyle.label(15, false, HudStyle.DIM, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	return l


## Where owned vehicle `vid` is, in words.
func where_text(vid: String) -> String:
	var v: Dictionary = GameState.vehicle(vid)
	var stored := str(v.get("stored", ""))
	if PLACES.has(stored):
		return "Stored at %s" % str(PLACES[stored]["name"])
	var car := economy.owned_cars.car_for(vid)
	if car != null and player.get("vehicle") == car:
		return "You're driving it"
	var pos := vehicle_position(vid)
	if pos == Vector3.INF:
		return "Not parked anywhere yet"
	for id: String in PLACES:
		if is_at(id, pos):
			return "Parked in %s" % str(PLACES[id]["short"])
	var hit := world.network.nearest_on_streets(Vector2(pos.x, pos.z), 80.0)
	if not hit.is_empty() and str((hit["edge"] as RoadNetwork.RoadEdge).name) != "":
		return "On %s" % str((hit["edge"] as RoadNetwork.RoadEdge).name)
	return "Parked off the street"


## Where owned vehicle `vid` is now (Vector3.INF if nowhere: stored, or
## never parked).
func vehicle_position(vid: String) -> Vector3:
	var car := economy.owned_cars.car_for(vid)
	var v: Dictionary = GameState.vehicle(vid)
	var stored := str(v.get("stored", ""))
	if PLACES.has(stored):
		var i := stored_at(stored).find(vid)
		return stall_xform(world, stored, maxi(i, 0)).origin
	if car != null:
		return car.global_position
	var at: Dictionary = v.get("parked", {})
	if at.is_empty():
		return Vector3.INF
	return Vector3(float(at["x"]), float(at["y"]), float(at["z"]))


func _model_name(vid: String) -> String:
	var v: Dictionary = GameState.vehicle(vid)
	return CarModels.full_name(str(v.get("model", "civique"))) if not v.is_empty() else "car"


func _say(title: String, sub: String) -> void:
	var hud := economy.hud
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", title, sub)

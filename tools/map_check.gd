extends SceneTree
## Checks the town map (scripts/ui/world_map.gd) and the waypoint
## (scripts/ui/gps.gd), headless:
##
##   godot --headless --path . --script res://tools/map_check.gd
##
## Loads the real streets and terrain (as the world does), then: the named
## places load from data/city/locations.json; a route between two far
## places runs along the streets, is not much longer than the straight line
## and keeps to one-way streets when driving; setting the waypoint routes to
## it, trims it as you go, reroutes when you leave it, and clears on
## arrival; M opens the map (pausing the game) and closes it; a click on a
## place sets the waypoint there, on the waypoint clears it; the HUD shows
## the waypoint and its marker; the list leaves the scenery (churches,
## banks...) off until points of interest are turned on. One "MAP" line per check; exits non-zero
## with "MAP FAIL" lines if any fail.

## Stands in for WorldBuilder: what the map, the GPS and the HUD read.
class FakeWorld extends Node:
	signal built
	var data: StreetData
	var network: RoadNetwork
	var terrain: Terrain
	var boundary := PackedVector2Array()
	var is_built := true

	func is_in_play_area(_p: Vector2) -> bool:
		return true

	func street_name_at(p: Vector2, max_dist := 25.0) -> String:
		var hit := network.nearest_on_streets(p, max_dist)
		return (hit["edge"] as RoadNetwork.RoadEdge).name if not hit.is_empty() else ""

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("MAP ok   %s" % what)
	else:
		_failures += 1
		print("MAP FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	# The title screen and the loading screen would keep the map shut.
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		menu.set("_open", false)
		if menu.get("_loading") is Control:
			(menu.get("_loading") as Control).visible = false
	root.size = Vector2i(1600, 900)
	var data := StreetData.load_from("res://data/map_config.json")
	var world := FakeWorld.new()
	world.data = data
	world.network = RoadNetwork.new(data)
	world.terrain = Terrain.load_from(str(data.config.get("elevation")))
	root.add_child(world)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var player := Node3D.new()
	root.add_child(player)
	var hud := Hud.new()
	root.add_child(hud)
	await _frames(2)
	# (Not Hud.setup: that wants a real WorldBuilder, for the street line.)
	hud.minimap.setup(world, player)
	hud.gps.setup(world, player)
	hud.world_map.setup(world, player, hud.gps, hud.minimap)
	var map := hud.world_map
	var gps := hud.gps
	_check(map != null and WorldMap.find(self) == map and Gps.find(self) == gps, "the HUD has a map and a GPS, and other code can find them")

	# The places.
	var by_name := {}
	for p in map.places:
		by_name[p["name"]] = p
	var kinds := {}
	for p in map.places:
		kinds[p["kind"]] = true
	_check(map.places.size() > 80 and by_name.has("Victoria Park") and by_name.has("Province House"), "the named places load (%d, %d kinds)" % [map.places.size(), kinds.size()])
	var unknown: Array[String] = []
	for k: String in kinds:
		if not WorldMap.KINDS.has(k):
			unknown.append(k)
	_check(unknown.is_empty(), "every kind of place has an icon %s" % str(unknown))
	_check(not by_name.has("Tim Hortons") and not by_name.has("Atlantic Superstore") and by_name.has("Tim Hardly's"), "businesses go by their world brand, never the real chain")

	# A route across town.
	var a: Vector2 = by_name["Province House"]["at"]
	var b: Vector2 = by_name["Maritime Megastore"]["at"] if by_name.has("Maritime Megastore") else by_name["Victoria Park"]["at"]
	var t0 := Time.get_ticks_usec()
	var route := Gps.find_route(world.network, a, b, true)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var length := RoadNetwork.polyline_length(route)
	var straight := a.distance_to(b)
	_check(route.size() > 2 and length > straight * 0.95 and length < straight * 2.0, "a route across town follows the streets (%.0f m for %.0f m straight, %d points)" % [length, straight, route.size()])
	_check(ms < 120.0, "and is quick to work out (%.1f ms)" % ms)
	var on_streets := true
	for i in range(0, route.size(), 5):
		if world.network.nearest_on_streets(route[i], 3.0).is_empty() and route[i].distance_to(b) > 20.0:
			on_streets = false
	_check(on_streets, "every point of it is on a street")
	# One-way streets: driving keeps to them, so the way back differs.
	var one_ways := 0
	for e in world.network.edges:
		if e.oneway != 0:
			one_ways += 1
	var back := Gps.find_route(world.network, b, a, true)
	_check(one_ways == 0 or not back.is_empty(), "the way back is found too (%d one-way streets in town)" % one_ways)

	# Setting the waypoint.
	player.global_position = Vector3(a.x, 0, a.y)
	var changes := [0]
	gps.changed.connect(func() -> void: changes[0] += 1)
	gps.set_waypoint(Vector3(b.x, 0, b.y), "Somewhere")
	_check(gps.active and gps.route.size() > 2 and gps.remaining > straight * 0.9, "setting a waypoint routes to it (%s along the streets)" % HudStyle.distance_text(gps.remaining))
	await _frames(3)
	_check(hud._waypoint.visible and hud._marker.visible, "the HUD shows it, and marks it on the screen")
	# Turn by turn: the first turn along a route across town is at a
	# junction, left or right, onto a named street.
	var turn := Gps.find_turn(gps.route, world.network, gps.remaining)
	_check(str(turn.get("turn", "")) in ["left", "right", "sharp left", "sharp right", "roundabout"] and float(turn["dist"]) > 0.0 and str(turn["onto"]) != "",
		"the next turn is worked out: %s in %s onto %s" % [Gps.turn_text(turn), HudStyle.distance_text(float(turn.get("dist", 0.0))), turn.get("onto", "")])
	_check(Gps._at_junction(world.network, RoadNetwork.sample(gps.route, float(turn["dist"]))[0]), "at a junction, not a bend in the road")
	_check(not gps.next_turn.is_empty(), "and kept up to date for the HUD (%s)" % Gps.turn_text(gps.next_turn))
	# A straight street with a curve but no junction isn't a turn.
	var bend := PackedVector2Array()
	for i in 40:
		var t := i / 39.0
		bend.append(Vector2(-90000.0 + 300.0 * t, -90000.0 + 120.0 * t * t))
	_check(str(Gps.find_turn(bend, world.network, 300.0)["turn"]) == "arrive", "a bend with no junction isn't called a turn")
	# The route is drawn on the minimap only, never on the road.
	_check(hud.find_child("RouteRibbon", true, false) == null, "the route isn't drawn on the road")
	var before := gps.remaining
	# Walk a third of the way along the route.
	var mid: Vector2 = RoadNetwork.sample(gps.route, RoadNetwork.polyline_length(gps.route) * 0.33)[0]
	for i in 5:
		var q: Vector2 = RoadNetwork.sample(gps.route, RoadNetwork.polyline_length(gps.route) * 0.066 * (i + 1))[0]
		player.global_position = Vector3(q.x, 0, q.y)
		await create_timer(0.3).timeout
	player.global_position = Vector3(mid.x, 0, mid.y)
	await create_timer(0.3).timeout
	_check(gps.remaining < before - 300.0 and gps.route_ahead().size() < gps.route.size() + 1, "going along it, what's left shrinks (%s -> %s)" % [HudStyle.distance_text(before), HudStyle.distance_text(gps.remaining)])
	# Off the route: worked out again.
	var off := mid + Vector2(250, 250)
	var hit := world.network.nearest_on_streets(off, 400.0)
	if not hit.is_empty():
		off = hit["pos"]
	var old_route := gps.route
	player.global_position = Vector3(off.x, 0, off.y)
	await create_timer(Gps.REROUTE_GAP + 0.6).timeout
	_check(gps.route != old_route and gps.route.size() > 1 and gps.route[0].distance_to(off) < 40.0, "leaving the route works it out again from where you are")
	var arrived := [""]
	gps.arrived.connect(func(place: String) -> void: arrived[0] = place)
	player.global_position = Vector3(b.x + 3.0, 0, b.y)
	await create_timer(0.4).timeout
	_check(not gps.active and arrived[0] == "Somewhere", "getting there clears it (\"%s\")" % arrived[0])
	await _frames(2)
	_check(not hud._waypoint.visible and not hud._marker.visible, "and it's off the HUD")

	# The GPS modes for delivery jobs: less help, less shown.
	player.global_position = Vector3(a.x, 0, a.y)
	gps.set_waypoint(Vector3(b.x, 0, b.y), "Somewhere", "directions")
	await create_timer(0.3).timeout
	_check(not gps.shows_route() and gps.shows_turns() and gps.shows_pin() and hud._marker.visible, "Directions: the turns and the pin, no route drawn")
	gps.set_waypoint(Vector3(b.x, 0, b.y), "Somewhere", "address")
	await create_timer(0.3).timeout
	_check(not gps.shows_route() and not gps.shows_turns() and not gps.shows_pin() and not hud._marker.visible and hud._waypoint.visible, "Address: only the place's name")
	gps.set_waypoint(Vector3(b.x, 0, b.y), "Somewhere")
	_check(gps.mode == "route" and gps.shows_route(), "your own waypoints get the full route")
	gps.clear()

	# The map.
	player.global_position = Vector3(a.x, 0, a.y)
	await _key(KEY_M)
	_check(map.is_open and map.visible and paused, "M opens the map and pauses the game")
	var rows := map._list.get_root().get_child_count()
	var useful := 0
	var churches := 0
	for p in map.places:
		if not WorldMap.is_poi(p):
			useful += 1
		if str(p["kind"]) == "church":
			churches += 1
	_check(rows == useful and rows < map.places.size() and rows > 40, "the list has the places you can use or find your way by (%d of %d)" % [rows, map.places.size()])
	var listed_church := false
	for p in map._list_places:
		if str(p["kind"]) in ["church", "bank", "school"]:
			listed_church = true
	_check(churches > 0 and not listed_church and map._list_places.any(func(p: Dictionary) -> bool: return str(p["kind"]) == "park"),
		"churches, banks and schools are left off by default; parks stay")
	map.set_show_poi(true)
	_check(map._list.get_root().get_child_count() == map.places.size(), "points of interest on: every place (%d)" % map.places.size())
	map.set_show_poi(false)
	_check(map._list_places.size() > 1 and (map._list_places[0]["at"] as Vector2).distance_to(a) <= (map._list_places[map._list_places.size() - 1]["at"] as Vector2).distance_to(a), "nearest first")
	map._set_group("food")
	var all_food := map._list_places.size() > 0
	for p in map._list_places:
		if WorldMap._group_of(str(p["kind"])) != "food":
			all_food = false
	_check(all_food, "a kind narrows it (%d food places)" % map._list_places.size())
	map._set_group("all")
	# A click on Victoria Park sets the waypoint there.
	var vp: Dictionary = by_name["Victoria Park"]
	map.centre = vp["at"]
	map.zoom = 1.0
	await _frames(2)
	map._click(map._to_view(vp["at"]))
	_check(gps.active and gps.place == "Victoria Park", "clicking a place sets the waypoint there (%s)" % gps.title())
	map._click(map._to_view(Vector2(gps.target.x, gps.target.z)))
	_check(not gps.active, "clicking the waypoint clears it")
	# A click on bare ground: the nearest street.
	map._click(map._to_view(a + Vector2(40, 40)))
	_check(gps.active and gps.place != "", "clicking near a street sets it on the street (%s)" % gps.title())
	map._zoom_at(map._view.size * 0.5, 100.0)
	_check(is_equal_approx(map.zoom, WorldMap.ZOOM_MAX), "zoom stops at its closest")
	# All the way out and off to a corner: the view stays on the mapped ground.
	map._zoom_at(map._view.size * 0.5, 0.0001)
	map.centre = Vector2(-1e5, 1e5)
	await _frames(2)
	var ext := map._extent()
	var seen := Rect2(map._to_world(Vector2.ZERO), map._view.size / map.zoom)
	_check(ext.size.x > 0.0 and ext.grow(1.0).encloses(seen), "zoomed out and moved off the edge, the view stays inside the mapped ground (%s in %s)" % [str(seen), str(ext)])
	await _frames(2)
	await _key(KEY_ESCAPE)
	_check(not map.is_open and not paused, "Esc closes it, and the game goes on")
	await _key(KEY_M)
	_check(map.is_open, "M opens it again")
	await _key(KEY_M)
	_check(not map.is_open, "and M closes it")
	gps.clear()

	print("MAP %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)

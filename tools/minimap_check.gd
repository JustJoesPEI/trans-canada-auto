extends SceneTree
## Checks the minimap (scripts/ui/minimap.gd), headless:
##
##   godot --headless --path . --script res://tools/minimap_check.gd
##
## Loads the real street network and terrain (as the world does), then:
## the streets are drawn once into tiles and the water mask is made off the
## main thread; the player is in the middle and the camera's way is up;
## markers, tracked units, the search circle
## and the caption go on through its API; the wanted level's search circle
## and the red rim come from WantedHud; the HUD makes one, bottom left.
## One "MINIMAP" line per check; exits non-zero with "MINIMAP FAIL" lines
## if any fail.

## Stands in for WorldBuilder: what the minimap reads from it.
class FakeWorld extends Node:
	var network: RoadNetwork
	var terrain: Terrain
	var is_built := true

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("MINIMAP ok   %s" % what)
	else:
		_failures += 1
		print("MINIMAP FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var data := StreetData.load_from("res://data/map_config.json")
	var world := FakeWorld.new()
	world.network = RoadNetwork.new(data)
	world.terrain = Terrain.load_from(str(data.config.get("elevation")))
	root.add_child(world)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3(100, 0, 50)

	var hud := Hud.new()
	root.add_child(hud)
	var mm := hud.minimap
	_check(mm != null and Minimap.find(self) == mm, "the HUD has one, and other code can find it")
	await _frames(2)
	var vp := root.get_visible_rect().size
	_check(mm.position.x < vp.x * 0.1 and mm.position.y + mm.size.y > vp.y * 0.85 and is_equal_approx(mm.size.x, mm.size.y), "bottom left, round (%s at %s)" % [str(mm.size), str(mm.position)])

	var t0 := Time.get_ticks_msec()
	mm.setup(world, player)
	var setup_ms := Time.get_ticks_msec() - t0
	var tiles := mm.find_children("Streets_*", "Node2D", true, false)
	var edges := 0
	var keys := {}
	for e in world.network.edges:
		var c := e.bounds.get_center()
		keys[Vector2i(floori(c.x / Minimap.TILE), floori(c.y / Minimap.TILE))] = true
		edges += 1
	_check(tiles.size() == keys.size() and tiles.size() > 4, "the %d streets are drawn once, in %d tiles (%d ms)" % [edges, tiles.size(), setup_ms])
	_check(setup_ms < 1000, "without holding up the game (%d ms on the main thread)" % setup_ms)
	for i in 600:
		await process_frame
		if mm.find_child("Water", true, false) != null:
			break
	_check(mm.find_child("Water", true, false) != null, "the water is made off the main thread and drawn under the streets")

	# The player in the middle, the camera's way up.
	cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), player.global_position + Vector3(0, 2, 6).rotated(Vector3.UP, deg_to_rad(30.0)))
	await _frames(3)
	var mid := mm.size * 0.5
	var here := mm.to_map(player.global_position)
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var ahead := mm.to_map(player.global_position + fwd.normalized() * 100.0)
	_check(here.distance_to(mid) < 0.5, "you're in the middle (%s)" % str(here))
	_check(absf(ahead.x - mid.x) < 0.5 and ahead.y < mid.y, "it turns with the camera: ahead is up (%s)" % str(ahead))
	var r := mm.size.x * 0.5
	_check(absf(mid.distance_to(mm.to_map(player.global_position + Vector3(Minimap.RANGE_FOOT, 0, 0))) - r) < 2.0, "on foot the rim is %d m off" % int(Minimap.RANGE_FOOT))

	# The API.
	mm.set_marker("wash", "car_wash", player.global_position + Vector3(50, 0, 0))
	mm.set_marker("station", "police_station", player.global_position + Vector3(5000, 0, 0))
	var unit := Node3D.new()
	root.add_child(unit)
	unit.global_position = player.global_position + Vector3(0, 0, 30)
	mm.track(unit, "police")
	mm.set_search_circle(player.global_position + Vector3(40, 0, 0), 120.0)
	mm.set_caption("Search area")
	await _frames(2)
	_check(mm.markers.size() == 2 and mm.tracked.size() == 1 and mm.search_radius == 120.0 and mm._caption.visible, "markers, units, the search circle and a caption go on")
	unit.queue_free()
	await _frames(3)
	_check(mm.tracked.is_empty(), "a unit that's gone comes off")
	mm.remove_marker("wash")
	mm.clear_search_circle()
	mm.set_caption("")
	_check(mm.markers.size() == 1 and mm.search_radius == 0.0 and not mm._caption.visible, "and come off again")

	# Wanted: the search circle from WantedHud, and the rim goes red.
	var wanted: Node = root.get_node("Wanted")
	wanted.set("auto_tick", false)
	wanted.set("target", player)
	wanted.call("debug_set_level", 2)
	wanted.set("last_known_position", player.global_position + Vector3(300, 0, 0))
	wanted.set("search_radius", 150.0)
	wanted.set("_last_seen", -1000.0)
	await _frames(3)
	_check(mm.alarm, "wanted, the rim is red")
	_check(mm.search_radius == 150.0 and mm.search_centre.is_equal_approx(player.global_position + Vector3(300, 0, 0)), "out of sight, the search circle is on the minimap")
	_check(mm._caption.visible and mm._caption.text.contains("150 m outside"), "with how far outside it you are (%s)" % mm._caption.text)
	wanted.call("debug_set_level", 0)
	await _frames(3)
	_check(not mm.alarm and mm.search_radius == 0.0 and not mm._caption.visible, "not wanted, it's gone and the rim's white")

	if _failures > 0:
		print("MINIMAP %d check(s) failed" % _failures)
		quit(1)
	else:
		print("MINIMAP all checks passed")
		quit(0)

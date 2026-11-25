extends SceneTree
## Shapes the ground the way the game does at startup and saves it
## (GroundCache), so the shipped game loads it instead of working it out:
##
##   godot --headless --path . --script res://tools/bake_ground.gd
##
## The build workflow runs it before exporting. It then loads what it saved
## into a fresh copy and checks it matches the ground worked out here,
## height for height; "GROUND FAIL" and a non-zero exit if not.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var path := str(data.config.get("elevation", "res://data/elevation.json"))
	var terrain := Terrain.load_from(path)
	if terrain.is_flat():
		print("GROUND no elevation data; nothing to bake")
		quit(0)
		return
	RoadMesher.seat_bridges(net, terrain)
	RoadMesher.smooth_streets(net, terrain)
	var shaped_ms := Time.get_ticks_msec() - t0
	var k := GroundCache.key(data)
	var err := GroundCache.save(terrain, net, k)
	if err != OK:
		print("GROUND FAIL could not write %s (error %d)" % [GroundCache.PATH, err])
		quit(1)
		return
	# Check: load it back the way the game does and compare.
	t0 = Time.get_ticks_msec()
	var net2 := RoadNetwork.new(data)
	RoadMesher.prepare(net2, data)
	var t2 := Terrain.load_from(path, false)
	var ok := GroundCache.apply(t2, net2, k)
	var load_ms := Time.get_ticks_msec() - t0
	if not ok or t2.heights_bytes() != terrain.heights_bytes() or net2.bridge_end_h != net.bridge_end_h:
		print("GROUND FAIL the saved ground doesn't load back the same")
		quit(1)
		return
	print("GROUND saved %s (%.1f MB): shaping took %d ms, loading the saved ground (with the map) %d ms" % [
		GroundCache.PATH, FileAccess.get_file_as_bytes(GroundCache.PATH).size() / 1048576.0, shaped_ms, load_ms])
	quit(0)

extends SceneTree
## Times how long chunks take to build, without drawing anything:
##
##   godot --headless --path . --script res://tools/profile_chunks.gd -- --at=0,0 --radius=400
##
## Builds every chunk within the radius of the point (x,z metres) once in
## full detail and once in low detail, on this thread, and prints the
## average and worst time for each, plus how many buildings went in.


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var at := (str(args.get("at", "0,0"))).split_floats(",")
	var radius := float(args.get("radius", "400"))
	var t0 := Time.get_ticks_msec()
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var terrain := Terrain.load_from(str(data.config.get("elevation")))
	RoadMesher.seat_bridges(net, terrain)
	RoadMesher.smooth_streets(net, terrain)
	Materials.get_shared()
	StreetProps.prepare()
	ChunkBuilder.coarse_mask = load(str(data.config.get("ground_mask"))) as Texture2D
	print("PROFILE setup_ms=%d" % (Time.get_ticks_msec() - t0))
	var size := data.chunk_size
	for lod: bool in [false, true]:
		var total := 0
		var worst := 0
		var n := 0
		var buildings := 0
		var cx0 := floori((at[0] - radius) / size)
		var cx1 := floori((at[0] + radius) / size)
		var cz0 := floori((at[1] - radius) / size)
		var cz1 := floori((at[1] + radius) / size)
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var t := Time.get_ticks_usec()
				var node := ChunkBuilder.build(data, net, terrain, cx, cz, lod)
				var ms := (Time.get_ticks_usec() - t) / 1000
				buildings += int(node.get_meta("buildings", 0))
				node.free()
				total += ms
				worst = maxi(worst, ms)
				n += 1
		print("PROFILE %s chunks=%d avg_ms=%d worst_ms=%d buildings=%d" % ["far" if lod else "near", n, total / maxi(n, 1), worst, buildings])
	quit()

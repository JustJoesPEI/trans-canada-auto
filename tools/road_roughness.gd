extends SceneTree
## Measures how rough the street surfaces are, the way a car feels them:
## for every street (bridges aside) it samples the surface height along both
## wheel paths every metre, then reports
##   * bump: how far the surface strays from a straight line between points
##     3 m either side (a pitch kick over one wheelbase), in cm;
##   * twist: how much the left and right wheel paths differ in height,
##     change over 3 m (what rocks the car side to side), in cm;
##   * curb: how much the sidewalk top strays the same way (lumpy curbs).
## Each as the mean, the 95th and 99th percentile and the worst.
##
##   godot --headless --path . --script res://tools/road_roughness.gd
##
## --raw measures the bare lidar ground instead (no street smoothing).

const STEP := 1.0
const SPAN := 3.0


func _initialize() -> void:
	var raw := OS.get_cmdline_user_args().has("--raw")
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var terrain := Terrain.load_from(str(data.config.get("elevation")))
	RoadMesher.seat_bridges(net, terrain)
	if not raw:
		var t0 := Time.get_ticks_msec()
		RoadMesher.smooth_streets(net, terrain)
		print("ROUGH smoothing took %d ms" % (Time.get_ticks_msec() - t0))
	var bump: Array[float] = []
	var twist: Array[float] = []
	var curb: Array[float] = []
	var hw_bump: Array[float] = []
	for e in net.edges:
		if e.bridge or e.length < 2.0 * SPAN + 2.0:
			continue
		var track := minf(0.8, e.half_width * 0.4)
		var n := int((e.length - 2.0 * SPAN) / STEP)
		for k in n:
			var d := SPAN + k * STEP
			var s0 := RoadNetwork.sample(e.points, d - SPAN)
			var s1 := RoadNetwork.sample(e.points, d)
			var s2 := RoadNetwork.sample(e.points, d + SPAN)
			for side: float in [1.0, -1.0]:
				var hs: Array[float] = []
				for s: Array in [s0, s1, s2]:
					var dir: Vector2 = s[1]
					hs.append(terrain.h2((s[0] as Vector2) + Vector2(-dir.y, dir.x) * track * side))
				var b := absf(hs[1] - (hs[0] + hs[2]) * 0.5) * 100.0
				bump.append(b)
				if e.is_highway():
					hw_bump.append(b)
			var tw: Array[float] = []
			for s: Array in [s0, s2]:
				var dir: Vector2 = s[1]
				var perp := Vector2(-dir.y, dir.x)
				tw.append(terrain.h2((s[0] as Vector2) + perp * track) - terrain.h2((s[0] as Vector2) - perp * track))
			twist.append(absf(tw[1] - tw[0]) * 100.0)
			if e.walk(1) > 0.0:
				var off := e.half_width + e.walk(1) * 0.5
				var hc: Array[float] = []
				for s: Array in [s0, s1, s2]:
					var dir: Vector2 = s[1]
					hc.append(terrain.h2((s[0] as Vector2) + Vector2(-dir.y, dir.x) * off))
				curb.append(absf(hc[1] - (hc[0] + hc[2]) * 0.5) * 100.0)
	_report("bump (cm)", bump)
	_report("highway bump (cm)", hw_bump)
	_report("twist (cm)", twist)
	_report("sidewalk (cm)", curb)
	quit()


func _report(label: String, v: Array[float]) -> void:
	if v.is_empty():
		return
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	print("ROUGH %-18s n=%d mean %.2f  p95 %.2f  p99 %.2f  max %.2f" % [label, v.size(), sum / v.size(),
		v[int(v.size() * 0.95)], v[int(v.size() * 0.99)], v[v.size() - 1]])

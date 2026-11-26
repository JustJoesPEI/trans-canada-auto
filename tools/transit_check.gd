extends SceneTree
## Checks the bus routes and stops (data/transit.json, TransitStops) against
## the streets: every junction found, every leg drivable by a bus (planned
## the way TrafficBuses plans them, out and back), every stop on a leg each
## way and on a sidewalk on at least one side, no long gaps between stops.
## Lists the streets each route runs along and, for a gap, the cross
## streets in it (where a stop could go).
##
##     godot --headless --path . --script res://tools/transit_check.gd
##
## Exits 1 if anything's wrong.

## A stretch this long without a stop is listed (m).
const GAP := 650.0


func _initialize() -> void:
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var ts := TransitStops.current
	var bad := 0
	print("TRANSIT %d routes, %d stops (%d named as T3 lists them)" % [ts.routes.size(), ts.stops.size(),
		ts.stops.filter(func(s: Dictionary) -> bool: return bool(s["t3"])).size()])
	for ri in ts.routes.size():
		var r: Dictionary = ts.routes[ri]
		var via: Array[Vector2] = r["via"]
		var loop: Array[Vector2] = via.duplicate()
		for i in range(via.size() - 2, -1, -1):
			loop.append(via[i])
		var used := {} # stop -> [out, back]
		var length := [0.0, 0.0]
		var streets: Array[String] = []
		var stops_along: Array = [[], []] # [metres from the route's start, stop]
		var gone := [0.0, 0.0]
		var crossings: Array = [] # [metres along (out), "street & street"]
		for k in range(loop.size() - 1):
			var back := 1 if k >= via.size() - 1 else 0
			var leg := StreetRoute.plan(net, loop[k], loop[k + 1], TrafficManager.plan_options((loop[k + 1] - loop[k]).normalized()))
			if leg.is_empty() or leg.partial:
				print("  route %s: NO WAY from %s to %s" % [r["number"], _where(net, loop[k]), _where(net, loop[k + 1])])
				bad += 1
				continue
			if back == 0:
				# The junctions passed (for listing where a stop could go).
				var seen_j := {}
				for i in range(0, leg.points.size(), 2):
					for e in net.edges_near(Rect2(leg.points[i] - Vector2(12, 12), Vector2(24, 24))):
						for nid: String in [e.a, e.b]:
							if seen_j.has(nid) or net.degree(nid) < 3 or (net.nodes[nid] as Vector2).distance_to(leg.points[i]) > 12.0:
								continue
							seen_j[nid] = true
							var names: Array[String] = []
							for inc: RoadNetwork.Incident in net.incidents[nid]:
								if inc.edge.name != "" and not inc.edge.minor and not names.has(inc.edge.name):
									names.append(inc.edge.name)
							if names.size() >= 2:
								crossings.append([float(gone[0]) + i * StreetRoute.STEP, " & ".join(names)])
				for i in range(0, leg.points.size(), 6):
					var hit := net.nearest_on_streets(leg.points[i], 15.0)
					if not hit.is_empty():
						var nm := (hit["edge"] as RoadNetwork.RoadEdge).name
						if nm != "" and (streets.is_empty() or streets[streets.size() - 1] != nm):
							streets.append(nm)
			for st: Array in TrafficBuses.stops_on(leg, ri):
				var si: int = st[1]
				if not used.has(si):
					used[si] = [false, false]
				used[si][back] = true
				(stops_along[back] as Array).append([float(gone[back]) + float(st[0]), si])
			gone[back] = float(gone[back]) + leg.length
		print("ROUTE %s %s: %.1f km each way; %s" % [r["number"], r["name"], float(gone[0]) / 1000.0, " > ".join(streets)])
		for si: int in r["stops"]:
			var st: Dictionary = ts.stops[si]
			var u: Array = used.get(si, [false, false])
			var ok := bool(u[0]) and bool(u[1]) and not (st["sides"] as Array).is_empty()
			if not ok:
				bad += 1
			print("  %s %-48s %-18s out %s back %s sides %s at %.0f,%.0f" % ["  " if ok else "!!", st["name"], (st["edge"] as RoadNetwork.RoadEdge).name,
				"yes" if u[0] else "NO", "yes" if u[1] else "NO", st["sides"], (st["p"] as Vector2).x, (st["p"] as Vector2).y])
		# Long stretches with no stop (out), and the cross streets in them.
		var list: Array = stops_along[0]
		var marks: Array[float] = [0.0]
		for x: Array in list:
			marks.append(float(x[0]))
		marks.append(float(gone[0]))
		for i in range(marks.size() - 1):
			if marks[i + 1] - marks[i] > GAP:
				var at: Array[String] = []
				for c: Array in crossings:
					if float(c[0]) > marks[i] + 150.0 and float(c[0]) < marks[i + 1] - 150.0:
						at.append("%s (%.0f)" % [c[1], c[0]])
				print("  gap of %.0f m after %.0f m along; junctions in it: %s" % [marks[i + 1] - marks[i], marks[i], "; ".join(at)])
	print("TRANSIT %s (%d problems)" % ["OK" if bad == 0 else "FAILED", bad])
	quit(0 if bad == 0 else 1)


func _where(net: RoadNetwork, p: Vector2) -> String:
	var names: Array[String] = []
	var hit := net.nearest_on_streets(p, 10.0)
	if not hit.is_empty():
		names.append((hit["edge"] as RoadNetwork.RoadEdge).name)
	return "%s (%.0f,%.0f)" % [", ".join(names), p.x, p.y]

extends SceneTree
## Checks every junction in the city for geometry that will draw badly:
##
##   godot --headless --path . --script res://tools/audit_junctions.gd
##
## * "too close": two junctions joined by a stretch of street too short to
##   fit both junction boxes (the curbs would cross);
## * "overlapping": two junction boxes that overlap each other;
## * "spiky": a junction box reaching far out from its junction (very
##   shallow angles between streets).
## Prints the counts and the worst places, with their street names.


func _initialize() -> void:
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	var too_close: Array = []
	var overlapping: Array = []
	var spiky: Array = []
	for e in net.edges:
		if net.degree(e.a) < 3 or net.degree(e.b) < 3:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var need := net.mouth_distance(e.a, ka) + net.mouth_distance(e.b, kb)
		if need > e.length + 0.5:
			too_close.append([need - e.length, _where(net, e.a)])
		if net.junction_polys.has(e.a) and net.junction_polys.has(e.b):
			var common := Geometry2D.intersect_polygons(net.junction_polys[e.a], net.junction_polys[e.b])
			if not common.is_empty():
				overlapping.append([0.0, _where(net, e.a)])
	for nid: String in net.junction_polys:
		var c: Vector2 = net.nodes[nid]
		var widest := 0.0
		for inc: RoadNetwork.Incident in net.incidents[nid]:
			widest = maxf(widest, inc.edge.half_width)
		var reach := 0.0
		for q in net.junction_polys[nid]:
			reach = maxf(reach, q.distance_to(c))
		if reach > widest * 3.5 + 4.0:
			spiky.append([reach, _where(net, nid)])
	print("AUDIT %d junctions: %d too close to a neighbour, %d overlapping a neighbour, %d spiky" % [net.junction_polys.size(), too_close.size(), overlapping.size(), spiky.size()])
	for list: Array in [too_close, overlapping, spiky]:
		list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for row: Array in too_close.slice(0, 12):
		print("AUDIT too close by %.1f m: %s" % [row[0], row[1]])
	for row: Array in spiky.slice(0, 12):
		print("AUDIT spiky, reaches %.0f m: %s" % [row[0], row[1]])
	quit()


func _where(net: RoadNetwork, nid: String) -> String:
	var names := {}
	for inc: RoadNetwork.Incident in net.incidents[nid]:
		names[inc.edge.name if inc.edge.name != "" else "(unnamed)"] = true
	var p: Vector2 = net.nodes[nid]
	return "%s at (%.0f, %.0f)" % [" / ".join(names.keys()), p.x, p.y]

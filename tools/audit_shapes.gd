extends SceneTree
## Looks over the shape of every street as the game builds it, for the
## kinds of trouble that come from the map data:
##
##   godot --headless --path . --script res://tools/audit_shapes.gd [-- --all]
##
## * "folded": a curb or back-of-sidewalk line crossing itself (a bow tie
##   of curb standing out of a bend). RoadNetwork._unfold pinches these shut,
##   so anything listed is new trouble.
## * "sharp": a bend of more than 30 degrees still drawn as a corner, where
##   RoadNetwork.round_bends couldn't round it (the straights beside it too
##   short for the street's width).
## * "stub": a dead end under 15 m sticking out of a junction (scraps of
##   lot aisles; under RoadNetwork.STUB they're left out already).
## * "split": where a divided road begins (RoadNetwork._find_splits), and
##   "fork": a one-way pair leaving a node side by side that wasn't treated
##   as one though it carries on from a two-way street (more than three
##   streets meet there): these still meet in a junction box.
## * "underpass": streets passing under a bridge (each gets abutments).
## Prints counts and the worst places with game coordinates (x, z), for
## tools/shot.sh or tools/draw_roads.gd. --all lists every one.


func _initialize() -> void:
	var show_all := OS.get_cmdline_user_args().has("--all")
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	var folded := []
	var sharp := []
	var stubs := []
	var forks := []
	var under := []
	for e in net.edges:
		for side: int in [1, -1]:
			for level: int in [RoadNetwork.Level.CURB, RoadNetwork.Level.BACK]:
				var at: Variant = _crossing(net.side_line(e, side, level))
				if at != null:
					folded.append([0.0, "%s (%s)" % [_name(e), e.highway], at])
		var p := e.points
		for i in range(1, p.size() - 1):
			var turn := rad_to_deg(absf((p[i] - p[i - 1]).angle_to(p[i + 1] - p[i])))
			if turn > 30.0:
				sharp.append([turn, "%s (%s), %.0f degrees" % [_name(e), e.highway, turn], p[i]])
		for end: String in [e.a, e.b]:
			var other := e.b if end == e.a else e.a
			if net.degree(end) == 1 and net.degree(other) >= 3 and e.length < 15.0:
				stubs.append([15.0 - e.length, "%s (%s), %.1f m" % [_name(e), e.highway, e.length], net.nodes[end]])
		if e.bridge:
			for u in RoadMesher._under(net, e):
				under.append([0.0, "%s under %s" % [_name(u), _name(e)], e.bounds.get_center()])
	for nid: String in net.incidents:
		if net.splits.has(nid):
			continue
		var list: Array = net.incidents[nid]
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: RoadNetwork.Incident = list[i]
				var b: RoadNetwork.Incident = list[j]
				if a.edge.oneway == 0 or b.edge.oneway == 0 or a.dir.dot(b.dir) < 0.5:
					continue
				if ((a.edge.oneway == 1) == a.at_start) == ((b.edge.oneway == 1) == b.at_start):
					continue
				# Only where they carry on from one two-way street (not the two
				# halves of a divided road at a crossroads).
				var from_one := false
				for t: RoadNetwork.Incident in list:
					from_one = from_one or (t.edge.oneway == 0 and t.dir.dot((a.dir + b.dir).normalized()) < -0.85)
				if not from_one:
					continue
				forks.append([float(list.size()), "%s / %s, %d streets" % [_name(a.edge), _name(b.edge), list.size()], net.nodes[nid]])
	print("SHAPES %d streets, %d junctions, %d divided-road splits" % [net.edges.size(), net.junction_polys.size(), net.splits.size()])
	_report("folded", folded, show_all)
	_report("sharp", sharp, show_all)
	_report("stub", stubs, show_all)
	_report("fork", forks, show_all)
	_report("underpass", under, show_all)
	quit()


## Where a polyline crosses itself (not just touching where a loop was
## pinched shut), or null.
static func _crossing(l: PackedVector2Array) -> Variant:
	for i in l.size() - 1:
		if l[i].distance_to(l[i + 1]) < 0.01:
			continue
		for j in range(i + 2, l.size() - 1):
			if l[j].distance_to(l[j + 1]) < 0.01:
				continue
			var x: Variant = Geometry2D.segment_intersects_segment(l[i], l[i + 1], l[j], l[j + 1])
			if x == null:
				continue
			var q: Vector2 = x
			if minf(minf(q.distance_to(l[i]), q.distance_to(l[i + 1])), minf(q.distance_to(l[j]), q.distance_to(l[j + 1]))) > 0.02:
				return q
	return null


static func _name(e: RoadNetwork.RoadEdge) -> String:
	return e.name if e.name != "" else "(unnamed)"


static func _report(what: String, rows: Array, show_all: bool) -> void:
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	print("SHAPES %s: %d" % [what, rows.size()])
	for k in (rows.size() if show_all else mini(rows.size(), 15)):
		var at: Vector2 = rows[k][2]
		print("SHAPES   %s at (%.0f, %.0f)" % [rows[k][1], at.x, at.y])

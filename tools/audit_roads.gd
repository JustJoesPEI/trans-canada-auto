extends SceneTree
## Checks the built streets against the rest of the map:
##
##   godot --headless --path . --script res://tools/audit_roads.gd [-- --all]
##
## * "through a building": a stretch of roadway (curb to curb) running into
##   a building footprint, the street cutting into a house;
## * "sidewalk in a building": the same for the sidewalk beyond the curb;
## * "missing": OSM streets with a name, or service roads longer than 60 m
##   that aren't driveways or parking aisles, that the game doesn't build
##   (see map_config.json "minor_roads").
## Buildings are the ones tools/fit_streets.gd fits the streets to (open
## roofs like gas station canopies left out). What's still listed after
## running it is mostly where the OSM centreline itself runs into a
## building: move the street or the building in tools/map_editor.html.
## Prints counts and the worst places with their street names and game
## coordinates (x, z), so they can be found in tools/map_editor.html.
## --all lists every one instead of the worst 25.

const SAMPLE := 2.0 ## metres between checks along a street


func _initialize() -> void:
	var show_all := OS.get_cmdline_user_args().has("--all")
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	var grid: Dictionary = preload("res://tools/fit_streets.gd").load_buildings(data)
	var nb := 0
	for k: Vector2i in grid:
		nb += (grid[k] as Array).size()
	var road_hits := {} # "edge:building" -> [metres, where]
	var walk_hits := {}
	for e in net.edges:
		if e.bridge:
			continue
		for i in e.points.size() - 1:
			var a := e.points[i]
			var seg := e.points[i + 1] - a
			var sl := seg.length()
			if sl < 0.01:
				continue
			var t := seg / sl
			var n := Vector2(-t.y, t.x)
			var d := 0.0
			while d < sl:
				var p := a + t * d
				for side: int in [1, -1]:
					for f: float in [0.0, 0.5, 0.95]:
						_check(grid, e, p + n * side * e.half_width * f, road_hits)
					var w := e.walk(side)
					if w > 0.3:
						_check(grid, e, p + n * side * (e.half_width + w * 0.6), walk_hits)
				d += SAMPLE
	print("ROADS %d streets, %d buildings (counted once per 50 m square they touch)" % [net.edges.size(), nb])
	_report("through a building", road_hits, show_all)
	_report("sidewalk in a building", walk_hits, show_all)
	# Streets in OSM the game leaves out.
	var missing := {}
	for r in data.roads:
		if RoadNetwork.builds(data, r):
			continue
		var len := RoadNetwork.polyline_length(r.points)
		var svc := str(r.tags.get("service", ""))
		var named := r.name != "" and r.highway in ["service", "track", "living_street", "road"]
		var lane := r.highway == "service" and svc in ["", "alley", "drive-through"] and len > 60.0
		if not (named or lane):
			continue
		var k := "%s|%s" % [r.highway + ("/" + svc if svc != "" else ""), r.name]
		if not missing.has(k):
			missing[k] = [0.0, 0, r.points[r.points.size() / 2]]
		missing[k][0] += len
		missing[k][1] += 1
	var rows := []
	var total := 0.0
	for k: String in missing:
		rows.append([missing[k][0], k, missing[k][1], missing[k][2]])
		total += float(missing[k][0])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	print("ROADS missing: %d kinds of street not built, %.1f km" % [rows.size(), total / 1000.0])
	for row: Array in (rows if show_all else rows.slice(0, 25)):
		var p: Vector2 = row[3]
		print("ROADS   missing %4.0f m in %d piece(s): %s at (%.0f, %.0f)" % [row[0], row[2], row[1], p.x, p.y])
	quit()


func _check(grid: Dictionary, e: RoadNetwork.RoadEdge, p: Vector2, hits: Dictionary) -> void:
	for b: StreetData.Building in grid.get(Vector2i(floori(p.x / 50.0), floori(p.y / 50.0)), []):
		if Geometry2D.is_point_in_polygon(p, b.ring):
			var k := "%d:%s" % [e.index, b.id]
			if not hits.has(k):
				hits[k] = [0.0, e, b, p]
			hits[k][0] += SAMPLE / 3.0
			return


func _report(what: String, hits: Dictionary, show_all: bool) -> void:
	var rows := hits.values()
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	print("ROADS %s: %d places" % [what, rows.size()])
	for row: Array in (rows if show_all else rows.slice(0, 25)):
		var e: RoadNetwork.RoadEdge = row[1]
		var b: StreetData.Building = row[2]
		var p: Vector2 = row[3]
		var bname := str(b.tags.get("name", b.tags.get("building", "")))
		print("ROADS   %s (%s) into building %s [%s], about %.0f m, at (%.0f, %.0f)" % [
			e.name if e.name != "" else "(unnamed)", e.highway, b.id, bname, row[0], p.x, p.y])

extends SceneTree
## Draws the streets exactly as the game builds them, seen from straight
## above, as an SVG: for checking road geometry (gaps, overlaps, curbs that
## don't meet, paint in the wrong place) without rendering anything.
##
##   godot --headless --path . --script res://tools/draw_roads.gd -- \
##       --rect=-300,-300,0,0 --out=/tmp/roads.svg
##
## --rect=x0,z0,x1,z1 is the area in metres (keep it to a few hundred metres
## across: every triangle is written out). Asphalt, sidewalks, verges, medians
## and paint are each their own colour; a roadway hidden under another one
## (see RoadMesher.SUNK) is drawn darker. Thin red lines are the street
## centrelines, blue dots the junctions and magenta dots the dead ends.

const COLOURS := {
	"Verges": "#9a9468", "Asphalt": "#4d5052", "BrickStreets": "#8c4b38", "Sidewalks": "#d8d4c4",
	"Islands": "#5f9a4a", "CentreLines": "#f2c200", "LaneLines": "#ffffff", "Parapets": "#8890c0",
}


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var r := str(args.get("rect", "-300,-300,0,0")).split_floats(",")
	var rect := Rect2(Vector2(r[0], r[1]), Vector2(r[2] - r[0], r[3] - r[1]))
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var terrain := Terrain.load_from(str(data.config.get("elevation")))
	RoadMesher.seat_bridges(net, terrain)
	var paths := {}
	var size := data.chunk_size
	for cx in range(floori(rect.position.x / size), floori(rect.end.x / size) + 1):
		for cz in range(floori(rect.position.y / size), floori(rect.end.y / size) + 1):
			var root := RoadMesher.new(net, data, terrain, ChunkBuilder.chunk_rect(data, cx, cz), false).build()
			for c in root.get_children():
				if c is MeshInstance3D:
					_add(paths, str(c.name), (c as MeshInstance3D).mesh.get_faces(), terrain, rect)
			root.free()
	var svg := PackedStringArray()
	svg.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%f %f %f %f" width="1600" height="%d">' % [
		rect.position.x, rect.position.y, rect.size.x, rect.size.y, int(1600.0 * rect.size.y / rect.size.x)])
	svg.append('<rect x="%f" y="%f" width="%f" height="%f" fill="#8db37e"/>' % [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	for key: String in ["Verges", "Asphalt_sunk", "Asphalt", "BrickStreets", "Sidewalks", "Islands", "CentreLines", "LaneLines", "Parapets"]:
		if paths.has(key):
			var col: String = COLOURS.get(key, "#2c2e30") if key != "Asphalt_sunk" else "#2c2e30"
			svg.append('<path fill="%s" d="%s"/>' % [col, "".join(PackedStringArray(paths[key]))])
	for e in net.edges_near(rect):
		var d := "M"
		for q in e.points:
			d += " %.2f %.2f" % [q.x, q.y]
		svg.append('<path d="%s" fill="none" stroke="#e02020" stroke-width="0.15"/>' % d)
		for nid: String in [e.a, e.b]:
			var deg := net.degree(nid)
			if deg != 2:
				var p: Vector2 = net.nodes[nid]
				svg.append('<circle cx="%.2f" cy="%.2f" r="0.5" fill="%s"/>' % [p.x, p.y, "#2040e0" if deg >= 3 else "#d020d0"])
	svg.append("</svg>")
	var out := str(args.get("out", "/tmp/roads.svg"))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(svg))
	f.close()
	print("DRAW wrote %s" % out)
	quit()


## Top faces only (walls and curb faces are left out), as path segments.
func _add(paths: Dictionary, mesh_name: String, faces: PackedVector3Array, terrain: Terrain, rect: Rect2) -> void:
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var n := (b - a).cross(c - a)
		if absf(n.y) < 0.5 * n.length():
			continue
		var mid := (a + b + c) / 3.0
		if not rect.grow(5.0).has_point(Vector2(mid.x, mid.z)):
			continue
		var key := mesh_name
		if mesh_name == "Asphalt" and _sunk(a, terrain) and _sunk(b, terrain) and _sunk(c, terrain):
			key = "Asphalt_sunk"
		if not paths.has(key):
			paths[key] = []
		(paths[key] as Array).append("M%.2f %.2fL%.2f %.2fL%.2f %.2fZ" % [a.x, a.z, b.x, b.z, c.x, c.z])


## Every street vertex sits at the ground height plus its lift, so a hidden
## roadway is one whose corners are all RoadMesher.SUNK down.
func _sunk(p: Vector3, terrain: Terrain) -> bool:
	return absf(p.y - terrain.height_at(p.x, p.z) - RoadMesher.SUNK) < 0.002

extends SceneTree
## Fits every street between the buildings along it, so no roadway or
## sidewalk runs into a house:
##
##   godot --headless --path . --script res://tools/fit_streets.gd
##
## Street widths come from the road type (map_config.json "road_defaults"),
## which is too wide for the narrow lanes and old streets where houses stand
## close (Williams Lane, Elm Lane, Alley Street). Along each stretch of
## street between junctions this measures, every metre on each side, how far
## it is from the centreline to the first building wall, and where the
## street doesn't fit it narrows, in this order: the sidewalk on that side
## down to 1.2 m, then the roadway (to no less than 5.5 m two-way, 3.5 m
## one-way; lanes and service roads to 3 m), then the sidewalk away
## altogether. The widths are written to
## data/city/street_fit.json, which the game reads as it builds the streets
## (RoadNetwork._apply_fit).
##
## Streets whose width was set by hand (tca:width or tca:sidewalk in the map
## editor), highways, bridges and roundabouts are left as they are, and so
## is a building the centreline itself runs into: that's the map data
## being wrong there, not the width (tools/audit_roads.gd lists them).
##
## Run it again after changing street widths, adding or moving streets or
## buildings in the map editor, or refreshing the OSM data. A fit made for
## an older width is ignored, so a stale file never narrows a street wrongly,
## it just stops fitting the streets that changed.

const OUT := "res://data/city/street_fit.json"
const STEP := 1.0 ## metres between measurements along a street
const MIN_WALK := 1.2 ## narrowest sidewalk kept before dropping it
const SLACK := 0.15 ## a wall this far into the sidewalk is let be
## A wall closer than this to the centreline is the map being wrong there.
const ON_LINE := 1.0
## Roofs with nothing under them (gas station canopies, carports): streets
## can run under them.
const OPEN_BUILDINGS := ["roof", "carport", "canopy", "no", "construction"]


func _initialize() -> void:
	var data := StreetData.load_from("res://data/map_config.json")
	var grid := load_buildings(data)
	var fit := {}
	var keys := ""
	var net: RoadNetwork
	# Narrower streets can mean fewer junctions merged (RoadNetwork merges
	# ones whose curbs would cross), which changes the stretches of street,
	# so fit again on the network the fit makes until that stops changing.
	for attempt in 4:
		net = RoadNetwork.new(data, fit)
		var now := _edge_keys(net)
		if now == keys:
			break
		keys = now
		fit = _fit_all(net, grid)
	var fitted := 0
	var narrowed := 0
	var walks := 0
	for k: String in fit:
		var f: Dictionary = fit[k]
		fitted += 1
		if float(f["fit"][0]) < float(f["base"][0]) - 0.01:
			narrowed += 1
		if float(f["fit"][1]) < 0.01 and float(f["base"][1]) > 0.0 or float(f["fit"][2]) < 0.01 and float(f["base"][2]) > 0.0:
			walks += 1
	var sorted := {}
	var ks := fit.keys()
	ks.sort()
	for k: String in ks:
		sorted[k] = fit[k]
	var out := {
		"_comment": "Street widths fitted between the buildings along them, by tools/fit_streets.gd: edge 'from node>to node' -> base (half width, sidewalk right, sidewalk left, metres, as the street is set up) and fit (as built). Made by a tool: run it again rather than editing this.",
		"edges": sorted,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false) + "\n")
	f.close()
	print("FIT %d of %d stretches of street fitted between buildings: %d with a narrower roadway, %d with a sidewalk taken away" % [fitted, net.edges.size(), narrowed, walks])
	print("FIT wrote %s" % OUT)
	quit()


func _edge_keys(net: RoadNetwork) -> String:
	var ks: Array = []
	for e in net.edges:
		ks.append(RoadNetwork.edge_key(e.a, e.b))
	ks.sort()
	return ",".join(PackedStringArray(ks))


## Every closed building's outline by 50 m grid cell.
static func load_buildings(data: StreetData) -> Dictionary:
	var grid := {}
	for key: String in data.chunk_keys:
		var xz := key.split("_")
		var c := data.load_chunk(int(xz[0]), int(xz[1]))
		for b in c.buildings:
			if str(b.tags.get("building", "yes")) in OPEN_BUILDINGS:
				continue
			var box := Rect2(b.ring[0], Vector2.ZERO)
			for q in b.ring:
				box = box.expand(q)
			for gx in range(floori(box.position.x / 50.0), floori(box.end.x / 50.0) + 1):
				for gz in range(floori(box.position.y / 50.0), floori(box.end.y / 50.0) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					if not (grid[k] as Array).has(b):
						grid[k].append(b)
	return grid


## Distance from p along unit direction dir to the first building wall, up
## to reach (INF if none). -1 if p itself is inside a building.
static func clearance(grid: Dictionary, p: Vector2, dir: Vector2, reach: float) -> float:
	var q := p + dir * reach
	var best := INF
	var seen := {}
	for gx in range(floori(minf(p.x, q.x) / 50.0), floori(maxf(p.x, q.x) / 50.0) + 1):
		for gz in range(floori(minf(p.y, q.y) / 50.0), floori(maxf(p.y, q.y) / 50.0) + 1):
			for b: StreetData.Building in grid.get(Vector2i(gx, gz), []):
				if seen.has(b):
					continue
				seen[b] = true
				if Geometry2D.is_point_in_polygon(p, b.ring):
					return -1.0
				var n := b.ring.size()
				for i in n:
					var hit: Variant = Geometry2D.segment_intersects_segment(p, q, b.ring[i], b.ring[(i + 1) % n])
					if hit != null:
						best = minf(best, p.distance_to(hit))
	return best


func _fit_all(net: RoadNetwork, grid: Dictionary) -> Dictionary:
	var fit := {}
	for e in net.edges:
		if e.hand_set or e.is_highway() or e.bridge or e.roundabout:
			continue
		var f := _fit_edge(net, e, grid)
		if not f.is_empty():
			fit[RoadNetwork.edge_key(e.a, e.b)] = f
	return fit


## The narrowest room on each side of e between its junctions, and the
## widths that fit in it. Empty if e fits as it is.
func _fit_edge(net: RoadNetwork, e: RoadNetwork.RoadEdge, grid: Dictionary) -> Dictionary:
	var hw := e.base.x
	var walk := [e.base.y, e.base.z] # right, left
	var min_hw := (1.4 if e.oneway != 0 else 1.5) if e.minor else (1.75 if e.oneway != 0 else 2.75)
	min_hw = minf(min_hw, hw)
	var reach := hw + maxf(walk[0], walk[1]) + 0.5
	# Right up to the junctions: a house on the corner is beside this street
	# too. (Across the junction a ray only runs down the cross street.)
	var start := 1.0
	var stop := e.length - 1.0
	var room := [INF, INF]
	var along := 0.0
	for i in e.points.size() - 1:
		var a := e.points[i]
		var seg := e.points[i + 1] - a
		var sl := seg.length()
		if sl < 0.01:
			continue
		var t := seg / sl
		var n := Vector2(-t.y, t.x)
		var d := fposmod(-along, STEP)
		while d < sl:
			var s := along + d
			if s >= start and s <= stop:
				for k in 2:
					var c := clearance(grid, a + t * d, n * (1.0 if k == 0 else -1.0), reach)
					# A building the centreline (nearly) runs into is the map
					# being wrong, not the street too wide: leave it. Closer
					# than the narrowest street, the street goes down to that.
					if c >= ON_LINE:
						room[k] = minf(room[k], c)
			d += STEP
		along += sl
	# Roadway: as wide as it can be with at least MIN_WALK of sidewalk left
	# (or none, where there's none to begin with) on both sides.
	var new_hw := hw
	for k in 2:
		var c: float = room[k] + SLACK
		if c >= hw + float(walk[k]):
			continue
		var keep := minf(float(walk[k]), MIN_WALK)
		if c >= hw + keep:
			continue
		if c - keep >= min_hw:
			new_hw = minf(new_hw, c - keep)
		else:
			new_hw = minf(new_hw, maxf(min_hw, c))
	new_hw = floorf(new_hw * 20.0) / 20.0
	var new_walk := [float(walk[0]), float(walk[1])]
	for k in 2:
		var left: float = room[k] + SLACK - new_hw
		if left < float(walk[k]):
			new_walk[k] = floorf(left * 20.0) / 20.0 if left >= MIN_WALK * 0.75 else 0.0
	if new_hw >= hw - 0.01 and new_walk[0] >= float(walk[0]) - 0.01 and new_walk[1] >= float(walk[1]) - 0.01:
		return {}
	return {"base": [hw, walk[0], walk[1]], "fit": [new_hw, new_walk[0], new_walk[1]]}

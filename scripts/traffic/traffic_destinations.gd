class_name TrafficDestinations
extends RefCounted
## Where traffic goes: real places off the streets, from the map. Every
## driveway, parking-lot entrance, alley and drive-through (OSM service
## roads) that meets a street is a destination: the car drives to it by
## road and turns in a few metres, then it's taken away once nobody can
## see it (and another is placed somewhere else).
##
## Each is {"street": Vector2 (the mouth, on the street), "inside": Vector2
## (a few metres in), "kind": the OSM service value ("driveway",
## "parking_aisle", ... or "" for a plain service road)}.

## How far in to drive (m).
const IN_BY := 6.5
const GRID := 200.0

static var _cache := {}

var places: Array[Dictionary] = []
var _grid := {} ## Vector2i -> Array[int]


static func of(net: RoadNetwork, data: StreetData) -> TrafficDestinations:
	var key := net.get_instance_id()
	if not _cache.has(key):
		var d := TrafficDestinations.new()
		d._build(net, data)
		_cache[key] = d
	return _cache[key]


func _build(net: RoadNetwork, data: StreetData) -> void:
	var seen := {}
	for r in data.roads:
		if r.highway != "service" or r.points.size() < 2:
			continue
		var kind := str(r.tags.get("service", ""))
		if kind == "emergency_access":
			continue
		var n := r.points.size()
		for end: int in [0, n - 1]:
			var p := r.points[end]
			var hit := net.nearest_on_streets(p, 30.0)
			if hit.is_empty():
				continue
			var e: RoadNetwork.RoadEdge = hit["edge"]
			if e.bridge or e.is_highway() or e.roundabout or float(hit["dist"]) > e.half_width + 5.0:
				continue
			var cell := Vector2i(floori(p.x / 15.0), floori(p.y / 15.0))
			if seen.has(cell):
				continue
			seen[cell] = true
			# A few metres in along the service road from this end.
			var inside := p
			var run := 0.0
			var i := end
			var step := 1 if end == 0 else -1
			while run < IN_BY and i + step >= 0 and i + step < n:
				var q := r.points[i + step]
				var seg := r.points[i].distance_to(q)
				if run + seg >= IN_BY:
					inside = r.points[i].lerp(q, (IN_BY - run) / maxf(seg, 0.01))
					run = IN_BY
					break
				run += seg
				inside = q
				i += step
			if inside.distance_to(hit["pos"]) < e.half_width + 1.5:
				continue
			var idx := places.size()
			places.append({"street": hit["pos"], "inside": inside, "kind": kind})
			var g := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
			if not _grid.has(g):
				_grid[g] = []
			(_grid[g] as Array).append(idx)


## A destination between lo and hi metres (straight) from p, chosen with
## rng; empty if none. With `behind` (a unit vector), only ones that way.
func pick(rng: RandomNumberGenerator, p: Vector2, lo: float, hi: float, behind := Vector2.ZERO) -> Dictionary:
	var cands: Array[int] = []
	var c0 := Vector2i(floori((p.x - hi) / GRID), floori((p.y - hi) / GRID))
	var c1 := Vector2i(floori((p.x + hi) / GRID), floori((p.y + hi) / GRID))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for idx: int in _grid.get(Vector2i(cx, cz), []):
				var q: Vector2 = places[idx]["street"]
				var d := q.distance_to(p)
				if d < lo or d > hi:
					continue
				if behind != Vector2.ZERO and (q - p).dot(behind) < d * 0.3:
					continue
				cands.append(idx)
	if cands.is_empty():
		return {}
	return places[cands[rng.randi() % cands.size()]]

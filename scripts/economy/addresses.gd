class_name Addresses
extends RefCounted
## Real street addresses for jobs (data/city/addresses.json, made by
## tools/make_addresses.py from OSM): about 1,700 buildings with a house
## number, each with the point of the building nearest its street ("door")
## and the nearest point on the street ("road"). A delivery's drop zone
## lies between them: the lawn, the driveway, the curb.
##
##   Addresses.load_for(world)          the list, once (cached), inside the
##                                      play area only
##   pick(near, min_m, max_m, kinds)    a random one that distance from
##                                      `near` (Vector2 x, z); {} if none
##   nearest(p, kinds)
##   text(a)                            "45 Kent Street"
##   lawn(a, t)                         a point t of the way from the road
##                                      (0) to the door (1), Vector2
##
## An address: {n, street, kind ("home", "apartments", "business"), x, z,
## door: Vector2, road: Vector2}.

static var _cached: Addresses

var all: Array[Dictionary] = []


static func load_for(world: Node) -> Addresses:
	if _cached != null:
		return _cached
	var a := Addresses.new()
	var dir := "res://data/city"
	var data: Variant = world.get("data") if world != null else null
	if data is StreetData and (data as StreetData).city_dir != "":
		dir = (data as StreetData).city_dir
	var f := FileAccess.open(dir.path_join("addresses.json"), FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			for e: Dictionary in (j as Dictionary).get("addresses", []):
				var at := Vector2(float(e["x"]), float(e["z"]))
				if world != null and world.has_method("is_in_play_area") and not bool(world.call("is_in_play_area", at)):
					continue
				var d: Array = e["door"]
				var r: Array = e["road"]
				a.all.append({"n": str(e["n"]), "street": str(e["street"]), "kind": str(e["kind"]), "x": at.x, "z": at.y,
					"door": Vector2(float(d[0]), float(d[1])), "road": Vector2(float(r[0]), float(r[1]))})
	_cached = a
	return a


## A random address between min_m and max_m from `near`, of one of `kinds`
## (all kinds if empty). {} if there's none.
func pick(near: Vector2, min_m: float, max_m: float, kinds: Array = []) -> Dictionary:
	var fits: Array[Dictionary] = []
	for a in all:
		if not kinds.is_empty() and not kinds.has(a["kind"]):
			continue
		var d := near.distance_to(Vector2(a["x"], a["z"]))
		if d >= min_m and d <= max_m:
			fits.append(a)
	return fits.pick_random() if not fits.is_empty() else {}


func nearest(p: Vector2, kinds: Array = []) -> Dictionary:
	var best := {}
	var best_d := INF
	for a in all:
		if not kinds.is_empty() and not kinds.has(a["kind"]):
			continue
		var d := p.distance_squared_to(Vector2(a["x"], a["z"]))
		if d < best_d:
			best_d = d
			best = a
	return best


static func text(a: Dictionary) -> String:
	return "%s %s" % [a.get("n", ""), a.get("street", "")] if not a.is_empty() else ""


## A point on the way in: 0 the street's middle, 1 the building's front.
static func lawn(a: Dictionary, t: float) -> Vector2:
	return (a["road"] as Vector2).lerp(a["door"], t)

class_name StreetData
extends RefCounted
## Loads map_config.json and the OSM map data it points to (data/city/),
## projected into world metres. Nothing here builds geometry; it is just clean
## data that the road network, building generator and (later) minimap and AI
## all share.
##
## The streets (and their signals, stop signs and crossings) are loaded for
## the whole city at startup. Buildings, ground areas, trees and the like are
## split into square chunks (data/city/chunks/X_Z.geojson) and loaded one
## chunk at a time with load_chunk(), as the player comes near.


class Road:
	var id: String
	var name: String
	var highway: String
	var oneway: int = 0 ## 0 two-way, 1 one-way in drawing order, -1 one-way against it
	var nodes: PackedStringArray
	var points: PackedVector2Array ## ground positions Vector2(x, z)
	var tags: Dictionary


class Building:
	var id: String
	var tags: Dictionary
	var ring: PackedVector2Array ## outer ring, no repeated closing point


class GroundArea:
	var id: String
	var type: String ## e.g. "amenity=parking", "leisure=park"
	var tags: Dictionary
	var ring: PackedVector2Array


class MapPoint:
	var id: String
	var type: String ## e.g. "highway=traffic_signals", "natural=tree"
	var pos: Vector2
	var tags: Dictionary


## What one chunk of the map holds (see load_chunk).
class Chunk:
	var buildings: Array[Building] = []
	var areas: Array[GroundArea] = []
	var points: Array[MapPoint] = []
	## Trees seen by the lidar survey: five numbers each, x, z, height,
	## crown radius (metres) and 1 for a conifer.
	var trees := PackedFloat32Array()

	func points_of_type(type: String) -> Array[MapPoint]:
		var out: Array[MapPoint] = []
		for p in points:
			if p.type == type:
				out.append(p)
		return out


var config: Dictionary = {}
var projection: GeoProjection
var metadata: Dictionary = {}
var roads: Array[Road] = []
## Street points for the whole city: signals, stops, give-ways, crossings.
var points: Array[MapPoint] = []
## The folder holding roads.geojson, index.json and chunks/.
var city_dir := ""
## Chunk size in metres, and which chunks have data ("X_Z" -> true).
var chunk_size := 200.0
var chunk_keys: Dictionary = {}
## True when the chunks carry the lidar's building heights and trees.
var has_lidar := false
## Parking lot aisles (OSM service=parking_aisle), by 100 m grid cell, for
## painting the stalls either side of them.
var aisles: Dictionary = {} ## Vector2i -> Array[Road]


static func load_from(config_path: String) -> StreetData:
	var sd := StreetData.new()
	var cfg: Variant = _read_json(config_path)
	if not (cfg is Dictionary):
		push_error("StreetData: could not read config %s" % config_path)
		return sd
	sd.config = cfg
	var origin: Dictionary = sd.config.get("origin", {})
	sd.projection = GeoProjection.new(float(origin.get("lat", 0.0)), float(origin.get("lon", 0.0)))
	sd.city_dir = str(sd.config.get("city", "res://data/city"))
	var index: Variant = _read_json(sd.city_dir.path_join("index.json"))
	if index is Dictionary:
		sd.chunk_size = float(index.get("chunk_size", 200.0))
		sd.has_lidar = index.has("lidar")
		for k: Variant in index.get("chunks", []):
			sd.chunk_keys[str(k)] = true
	var gj: Variant = _read_json(sd.city_dir.path_join("roads.geojson"))
	if not (gj is Dictionary):
		push_error("StreetData: could not read %s/roads.geojson" % sd.city_dir)
		return sd
	sd._parse(gj, null)
	for r in sd.roads:
		if r.highway == "service" and str(r.tags.get("service", "")) == "parking_aisle":
			var box := Rect2(r.points[0], Vector2.ZERO)
			for q in r.points:
				box = box.expand(q)
			for cx in range(floori(box.position.x / 100.0), floori(box.end.x / 100.0) + 1):
				for cz in range(floori(box.position.y / 100.0), floori(box.end.y / 100.0) + 1):
					var key := Vector2i(cx, cz)
					if not sd.aisles.has(key):
						sd.aisles[key] = []
					if not (sd.aisles[key] as Array).has(r):
						sd.aisles[key].append(r)
	return sd


## Parking aisles that come within `area`.
func aisles_near(area: Rect2) -> Array:
	var out := []
	for cx in range(floori(area.position.x / 100.0), floori(area.end.x / 100.0) + 1):
		for cz in range(floori(area.position.y / 100.0), floori(area.end.y / 100.0) + 1):
			for r: Variant in aisles.get(Vector2i(cx, cz), []):
				if not out.has(r):
					out.append(r)
	return out


static func chunk_key(cx: int, cz: int) -> String:
	return "%d_%d" % [cx, cz]


func has_chunk(cx: int, cz: int) -> bool:
	return chunk_keys.has(chunk_key(cx, cz))


## The buildings, ground areas and points of one chunk. Safe to call from a
## worker thread: it only reads files and the projection.
func load_chunk(cx: int, cz: int) -> Chunk:
	var c := Chunk.new()
	if not has_chunk(cx, cz):
		return c
	var gj: Variant = _read_json(city_dir.path_join("chunks/%s.geojson" % chunk_key(cx, cz)))
	if gj is Dictionary:
		_parse(gj, c)
	return c


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _parse(gj: Dictionary, into: Chunk) -> void:
	if into == null:
		metadata = gj.get("metadata", {})
	for f: Dictionary in gj.get("features", []):
		var props: Dictionary = f.get("properties", {})
		var geom: Dictionary = f.get("geometry", {}) if f.get("geometry") is Dictionary else {}
		var kind := str(props.get("kind", ""))
		if kind == "trees" and into != null:
			into.trees = PackedFloat32Array(props.get("t", []))
		elif kind == "road" and geom.get("type") == "LineString":
			_add_road(props, geom.get("coordinates", []))
		elif kind == "building" and geom.get("type") == "Polygon" and into != null:
			_add_building(into, props, geom.get("coordinates", []))
		elif kind == "area" and geom.get("type") == "Polygon" and into != null:
			var a := GroundArea.new()
			a.id = str(props.get("osm_id", ""))
			a.type = str(props.get("type", ""))
			a.tags = props
			a.ring = _ring(geom.get("coordinates", []))
			if a.ring.size() >= 3:
				into.areas.append(a)
		elif kind == "point" and geom.get("type") == "Point":
			var c: Array = geom.get("coordinates", [0.0, 0.0])
			var p := MapPoint.new()
			p.id = str(props.get("osm_id", ""))
			p.type = str(props.get("type", ""))
			p.pos = projection.to_ground(float(c[0]), float(c[1]))
			p.tags = props
			if into != null:
				into.points.append(p)
			else:
				points.append(p)


func _add_road(props: Dictionary, coords: Array) -> void:
	var r := Road.new()
	r.id = str(props.get("id", ""))
	r.name = str(props.get("name", ""))
	r.highway = str(props.get("highway", ""))
	r.tags = props
	var ow := str(props.get("oneway", "no"))
	# Roundabouts are one way round, whether or not OSM says so.
	if (ow == "no" or ow == "") and str(props.get("junction", "")) in ["roundabout", "circular"] and not props.has("oneway"):
		ow = "yes"
	if ow == "yes" or ow == "1" or ow == "true":
		r.oneway = 1
	elif ow == "-1" or ow == "reverse":
		r.oneway = -1
	for n: Variant in props.get("nodes", []):
		r.nodes.append(str(n))
	for c: Array in coords:
		r.points.append(projection.to_ground(float(c[0]), float(c[1])))
	if r.nodes.size() != r.points.size() or r.points.size() < 2:
		push_warning("StreetData: skipping malformed road %s" % r.id)
		return
	roads.append(r)


func _add_building(into: Chunk, props: Dictionary, rings: Array) -> void:
	if rings.is_empty():
		return
	var b := Building.new()
	b.id = str(props.get("osm_id", ""))
	b.tags = props
	b.ring = _ring(rings)
	if b.ring.size() >= 3:
		into.buildings.append(b)


## Outer ring of GeoJSON polygon coordinates, projected, without the
## repeated closing point.
func _ring(rings: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if rings.is_empty():
		return out
	var outer: Array = rings[0]
	for i in range(outer.size() - 1):
		var c: Array = outer[i]
		out.append(projection.to_ground(float(c[0]), float(c[1])))
	return out


## Curb-to-curb width and sidewalk width (metres) for a street: a
## per-street override if map_config.json has one, otherwise worked out
## from the road class (and its lane count, when OSM gives one).
## Returns Vector3(width, sidewalk, shoulder): shoulder is the paved strip
## outside the edge line on highway-style roads (0 on town streets).
func road_style(street_name: String, highway: String, tags: Dictionary = {}) -> Vector3:
	var overrides: Dictionary = config.get("street_overrides", {})
	var defaults: Dictionary = config.get("road_defaults", {})
	var d: Dictionary = defaults.get(highway, {})
	var oneway := str(tags.get("oneway", "")) in ["yes", "1", "-1", "true"] or str(tags.get("junction", "")) in ["roundabout", "circular"]
	var shoulder := float(d.get("shoulder", 0.0))
	var sidewalk := float(d.get("sidewalk", 2.0))
	var width := float(d.get("oneway_width" if oneway and d.has("oneway_width") else "width", 8.0))
	var lanes := str(tags.get("lanes", "")).to_int()
	if lanes > 0 and d.has("lane"):
		# Both directions' lanes on a two-way road; one direction's on a one-way.
		width = lanes * float(d["lane"]) + shoulder * 2.0
	match str(tags.get("sidewalk", "")):
		"no", "none":
			sidewalk = minf(sidewalk, 0.0)
	if overrides.has(street_name):
		var s: Dictionary = overrides[street_name]
		# Overrides are for town streets; a highway stretch of the same name keeps its class style.
		if shoulder <= 0.0:
			width = float(s.get("width", width))
			sidewalk = float(s.get("sidewalk", sidewalk))
	return Vector3(width, sidewalk, shoulder)


## Street points of one type (e.g. "highway=crossing"), city-wide.
func points_of_type(type: String) -> Array[MapPoint]:
	var out: Array[MapPoint] = []
	for p in points:
		if p.type == type:
			out.append(p)
	return out

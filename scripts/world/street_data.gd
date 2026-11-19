class_name StreetData
extends RefCounted
## Loads map_config.json and the OSM GeoJSON it points to, projected into
## world metres. Nothing here builds geometry; it is just clean data that the
## road network, building generator and (later) minimap and AI all share.


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


class MapPoint:
	var id: String
	var type: String ## e.g. "highway=traffic_signals", "natural=tree"
	var pos: Vector2
	var tags: Dictionary


var config: Dictionary = {}
var projection: GeoProjection
var metadata: Dictionary = {}
var roads: Array[Road] = []
var buildings: Array[Building] = []
var points: Array[MapPoint] = []


static func load_from(config_path: String) -> StreetData:
	var sd := StreetData.new()
	var cfg: Variant = _read_json(config_path)
	if not (cfg is Dictionary):
		push_error("StreetData: could not read config %s" % config_path)
		return sd
	sd.config = cfg
	var origin: Dictionary = sd.config.get("origin", {})
	sd.projection = GeoProjection.new(float(origin.get("lat", 0.0)), float(origin.get("lon", 0.0)))
	var gj: Variant = _read_json(str(sd.config.get("geojson", "")))
	if not (gj is Dictionary):
		push_error("StreetData: could not read GeoJSON named in %s" % config_path)
		return sd
	sd._parse(gj)
	return sd


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _parse(gj: Dictionary) -> void:
	metadata = gj.get("metadata", {})
	for f: Dictionary in gj.get("features", []):
		var props: Dictionary = f.get("properties", {})
		var geom: Dictionary = f.get("geometry", {})
		var kind := str(props.get("kind", ""))
		if kind == "road" and geom.get("type") == "LineString":
			_add_road(props, geom.get("coordinates", []))
		elif kind == "building" and geom.get("type") == "Polygon":
			_add_building(props, geom.get("coordinates", []))
		elif kind == "point" and geom.get("type") == "Point":
			var c: Array = geom.get("coordinates", [0.0, 0.0])
			var p := MapPoint.new()
			p.id = str(props.get("osm_id", ""))
			p.type = str(props.get("type", ""))
			p.pos = projection.to_ground(float(c[0]), float(c[1]))
			p.tags = props
			points.append(p)


func _add_road(props: Dictionary, coords: Array) -> void:
	var r := Road.new()
	r.id = str(props.get("id", ""))
	r.name = str(props.get("name", ""))
	r.highway = str(props.get("highway", ""))
	r.tags = props
	var ow := str(props.get("oneway", "no"))
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


func _add_building(props: Dictionary, rings: Array) -> void:
	if rings.is_empty():
		return
	var b := Building.new()
	b.id = str(props.get("osm_id", ""))
	b.tags = props
	var outer: Array = rings[0]
	for i in range(outer.size() - 1): # GeoJSON rings repeat the first point at the end
		var c: Array = outer[i]
		b.ring.append(projection.to_ground(float(c[0]), float(c[1])))
	if b.ring.size() >= 3:
		buildings.append(b)


## Curb-to-curb width and sidewalk width (metres) for a street.
func road_style(street_name: String, highway: String) -> Vector2:
	var overrides: Dictionary = config.get("street_overrides", {})
	var defaults: Dictionary = config.get("road_defaults", {})
	var s: Dictionary = {}
	if overrides.has(street_name):
		s = overrides[street_name]
	elif defaults.has(highway):
		s = defaults[highway]
	return Vector2(float(s.get("width", 8.0)), float(s.get("sidewalk", 2.0)))


func points_of_type(type: String) -> Array[MapPoint]:
	var out: Array[MapPoint] = []
	for p in points:
		if p.type == type:
			out.append(p)
	return out

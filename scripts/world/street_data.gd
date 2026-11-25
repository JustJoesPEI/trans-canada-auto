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
## Places along the curbs to leave empty of parked cars (where the player's
## cars start), filled in by WorldBuilder before any chunk is built.
var keep_clear: Array[Vector2] = []
## Hand edits from the map editor (map_config.json "edits", made with
## tools/map_editor.html), laid over the OSM data as it loads. See
## data/README.md, "Hand edits".
var edits: Dictionary = {}
## Feature edits by "kind:osm_id" (tag changes, a new outline, deletion).
var _feature_edits: Dictionary = {}
## New buildings, areas and points by chunk key: Array of GeoJSON features.
var _new_by_chunk: Dictionary = {}
## Lidar trees taken out, by chunk key: Array of Vector2.
var _removed_trees: Dictionary = {}
## Spots where the game's own street furniture (hydrants, lamps, parked
## cars) is erased: Vector3(x, z, radius), by 100 m grid cell.
var _erased: Dictionary = {}
## Fences, walls, hedges and guardrails drawn in the map editor: each
## {"kind", "pts": PackedVector2Array, "height"} (see EditLines).
var lines: Array[Dictionary] = []
## Which chunks each loaded building, area and point came from
## ("kind:osm_id" -> Array of chunk keys), so a live reload of the edits
## knows which chunks a changed feature is in. Filled as chunks load.
var feature_chunks: Dictionary = {}
var _fc_mutex := Mutex.new()
## Street widths fitted to the buildings beside them (map_config.json
## "street_fit", written by tools/fit_streets.gd); see RoadNetwork._apply_fit.
var street_fit: Dictionary = {}
## Driveways, alleys and other service roads (not built as streets), by
## 100 m grid cell, so street furniture isn't put across them.
var _service: Dictionary = {}


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
	var edits_path := str(sd.config.get("edits", ""))
	if edits_path != "":
		var ed: Variant = _read_json(edits_path)
		if ed is Dictionary:
			sd.edits = ed
	var fit_path := str(sd.config.get("street_fit", ""))
	if fit_path != "" and FileAccess.file_exists(fit_path):
		var fit: Variant = _read_json(fit_path)
		if fit is Dictionary:
			sd.street_fit = fit.get("edges", {})
	sd._prepare_edits()
	sd._parse(gj, null)
	sd._edit_roads(gj)
	for r in sd.roads:
		if r.highway == "service":
			sd._grid_add(sd._service, r)
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


func _grid_add(grid: Dictionary, r: Road) -> void:
	var box := Rect2(r.points[0], Vector2.ZERO)
	for q in r.points:
		box = box.expand(q)
	box = box.grow(5.0)
	for cx in range(floori(box.position.x / 100.0), floori(box.end.x / 100.0) + 1):
		for cz in range(floori(box.position.y / 100.0), floori(box.end.y / 100.0) + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(r)


## True if p is on (within `reach` metres of the middle of) a driveway,
## alley or other service road.
func on_service_road(p: Vector2, reach := 2.6) -> bool:
	for r: Road in _service.get(Vector2i(floori(p.x / 100.0), floori(p.y / 100.0)), []):
		for i in r.points.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, r.points[i], r.points[i + 1])) < reach:
				return true
	return false


## True if the map editor erased the game's own street furniture at p.
func erased(p: Vector2) -> bool:
	for e: Vector3 in _erased.get(Vector2i(floori(p.x / 100.0), floori(p.y / 100.0)), []):
		if Vector2(e.x, e.y).distance_to(p) < e.z:
			return true
	return false


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
	var key := chunk_key(cx, cz)
	var gj: Variant = _read_json(city_dir.path_join("chunks/%s.geojson" % key))
	if gj is Dictionary:
		_parse(gj, c)
	_fc_mutex.lock()
	for b in c.buildings:
		_note_feature("building:" + b.id, key)
	for a in c.areas:
		_note_feature("area:" + a.id, key)
	for p in c.points:
		_note_feature("point:" + p.id, key)
	_fc_mutex.unlock()
	var added: Array = _new_by_chunk.get(key, [])
	if not added.is_empty():
		_parse({"features": added}, c)
	var gone: Array = _removed_trees.get(key, [])
	if not gone.is_empty() and not c.trees.is_empty():
		var kept := PackedFloat32Array()
		var t := c.trees
		for i in range(0, t.size() - 4, 5):
			var p := Vector2(t[i], t[i + 1])
			var hit := false
			for q: Vector2 in gone:
				if q.distance_squared_to(p) < 2.25:
					hit = true
					break
			if not hit:
				kept.append_array(t.slice(i, i + 5))
		c.trees = kept
	return c


func _note_feature(fkey: String, ckey: String) -> void:
	var list: Array = feature_chunks.get(fkey, [])
	if not list.has(ckey):
		list.append(ckey)
		feature_chunks[fkey] = list


## A copy of feature_chunks, safe to take while chunks are loading.
func feature_chunks_copy() -> Dictionary:
	_fc_mutex.lock()
	var out := feature_chunks.duplicate(true)
	_fc_mutex.unlock()
	return out


# --- hand edits ----------------------------------------------------------------------------

## Sorts the edits for loading: feature edits by key, new features and
## removed lidar trees by the chunk they fall in.
func _prepare_edits() -> void:
	_feature_edits = edits.get("features", {})
	for f: Variant in edits.get("new_features", []):
		if not (f is Dictionary):
			continue
		var feat := _edit_to_geojson(f)
		if feat.is_empty():
			continue
		var props: Dictionary = feat["properties"]
		if str(props.get("kind", "")) == "point" and str(props.get("type", "")).begins_with("highway="):
			continue # street points go with the streets: added in _edit_roads
		for key: String in _chunks_of(feat):
			if not _new_by_chunk.has(key):
				_new_by_chunk[key] = []
			_new_by_chunk[key].append(feat)
			chunk_keys[key] = true
	for l: Variant in edits.get("lines", []):
		if not (l is Dictionary) or not EditLines.KINDS.has(str(l.get("kind", ""))):
			continue
		var pts := PackedVector2Array()
		for c: Variant in l.get("pts", []):
			pts.append(projection.to_ground(float(c[0]), float(c[1])))
		if pts.size() >= 2:
			var kind := str(l["kind"])
			lines.append({"kind": kind, "pts": pts, "height": float(l.get("height", EditLines.KINDS[kind]))})
	for t: Variant in edits.get("erased_props", []):
		if t is Array and (t as Array).size() >= 2:
			var e := Vector3(float(t[0]), float(t[1]), float(t[2]) if (t as Array).size() > 2 else 2.0)
			for cx in range(floori((e.x - e.z) / 100.0), floori((e.x + e.z) / 100.0) + 1):
				for cz in range(floori((e.y - e.z) / 100.0), floori((e.y + e.z) / 100.0) + 1):
					var key := Vector2i(cx, cz)
					if not _erased.has(key):
						_erased[key] = []
					_erased[key].append(e)
	for t: Variant in edits.get("removed_trees", []):
		if t is Array and (t as Array).size() >= 2:
			var p := Vector2(float(t[0]), float(t[1]))
			var key := chunk_key(floori(p.x / chunk_size), floori(p.y / chunk_size))
			if not _removed_trees.has(key):
				_removed_trees[key] = []
			_removed_trees[key].append(p)


## An edit-file feature ({id, kind, tags, ring | pos}) as the GeoJSON the
## map files hold.
static func _edit_to_geojson(f: Dictionary) -> Dictionary:
	var props: Dictionary = (f.get("tags", {}) as Dictionary).duplicate()
	props["kind"] = str(f.get("kind", ""))
	props["osm_id"] = str(f.get("id", ""))
	if f.has("ring"):
		var ring: Array = (f["ring"] as Array).duplicate()
		if ring.size() < 3:
			return {}
		if ring[0] != ring[ring.size() - 1]:
			ring.append(ring[0])
		return {"type": "Feature", "properties": props, "geometry": {"type": "Polygon", "coordinates": [ring]}}
	if f.has("pos"):
		return {"type": "Feature", "properties": props, "geometry": {"type": "Point", "coordinates": f["pos"]}}
	return {}


## The chunk keys a feature belongs in: a building or point in the chunk
## its middle is in, a ground area in every chunk it overlaps.
func _chunks_of(feat: Dictionary) -> Array[String]:
	var geom: Dictionary = feat["geometry"]
	var pts: Array[Vector2] = []
	if geom["type"] == "Point":
		var c: Array = geom["coordinates"]
		pts.append(projection.to_ground(float(c[0]), float(c[1])))
	else:
		for c: Array in geom["coordinates"][0]:
			pts.append(projection.to_ground(float(c[0]), float(c[1])))
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var out: Array[String] = []
	if str(feat["properties"].get("kind", "")) == "area":
		for cx in range(floori(box.position.x / chunk_size), floori(box.end.x / chunk_size) + 1):
			for cz in range(floori(box.position.y / chunk_size), floori(box.end.y / chunk_size) + 1):
				out.append(chunk_key(cx, cz))
	else:
		var mid := box.get_center()
		out.append(chunk_key(floori(mid.x / chunk_size), floori(mid.y / chunk_size)))
	return out


## Applies a feature edit to a loaded feature's properties and geometry.
## Returns false when the edit deletes it.
func _apply_feature_edit(kind: String, props: Dictionary, geom: Dictionary) -> bool:
	var e: Variant = _feature_edits.get("%s:%s" % [kind, str(props.get("osm_id", ""))])
	if not (e is Dictionary):
		return true
	if bool(e.get("delete", false)):
		return false
	var tags: Dictionary = e.get("tags", {})
	for k: String in tags:
		if tags[k] == null:
			props.erase(k)
		else:
			props[k] = tags[k]
	if e.has("ring") and geom.get("type") == "Polygon":
		var ring: Array = (e["ring"] as Array).duplicate()
		if ring.size() >= 3:
			if ring[0] != ring[ring.size() - 1]:
				ring.append(ring[0])
			geom["coordinates"] = [ring]
	elif e.has("pos") and geom.get("type") == "Point":
		geom["coordinates"] = e["pos"]
	return true


## Applies the road edits after roads.geojson is loaded: moved and new
## junction points, changed and deleted streets, new streets, and new
## street points (stop signs, signals, crossings).
func _edit_roads(gj: Dictionary) -> void:
	var moved: Dictionary = edits.get("nodes", {})
	var road_edits: Dictionary = edits.get("roads", {})
	var new_roads: Array = edits.get("new_roads", [])
	if moved.is_empty() and road_edits.is_empty() and new_roads.is_empty() and edits.get("new_features", []).is_empty():
		return
	# Where every OSM node is, so an edited street can be rebuilt from node ids.
	var node_pos: Dictionary = {}
	for r in roads:
		for i in r.nodes.size():
			node_pos[r.nodes[i]] = r.points[i]
	for nid: String in moved:
		var c: Array = moved[nid]
		node_pos[nid] = projection.to_ground(float(c[0]), float(c[1]))
	var kept: Array[Road] = []
	for r in roads:
		var e: Variant = road_edits.get(r.id)
		if e is Dictionary:
			if bool(e.get("delete", false)):
				continue
			var tags: Dictionary = e.get("tags", {})
			for k: String in tags:
				if tags[k] == null:
					r.tags.erase(k)
				else:
					r.tags[k] = tags[k]
			r.name = str(r.tags.get("name", ""))
			r.highway = str(r.tags.get("highway", r.highway))
			r.oneway = _oneway_of(r.tags)
			if e.has("nodes"):
				r.nodes = PackedStringArray()
				for n: Variant in e["nodes"]:
					r.nodes.append(str(n))
		if not moved.is_empty() or (e is Dictionary and (e as Dictionary).has("nodes")):
			if not _place_nodes(r, node_pos):
				continue
		kept.append(r)
	for f: Variant in new_roads:
		if not (f is Dictionary):
			continue
		var r := Road.new()
		r.id = str(f.get("id", ""))
		r.tags = (f.get("tags", {}) as Dictionary).duplicate()
		r.tags["kind"] = "road"
		r.tags["id"] = r.id
		r.name = str(r.tags.get("name", ""))
		r.highway = str(r.tags.get("highway", "residential"))
		r.oneway = _oneway_of(r.tags)
		for n: Variant in f.get("nodes", []):
			r.nodes.append(str(n))
		if _place_nodes(r, node_pos):
			kept.append(r)
	roads = kept
	for f: Variant in edits.get("new_features", []):
		if f is Dictionary and str(f.get("kind", "")) == "point" and str((f.get("tags", {}) as Dictionary).get("type", "")).begins_with("highway="):
			var feat := _edit_to_geojson(f)
			if not feat.is_empty():
				_parse({"features": [feat]}, null)


## Sets a road's points from its node ids; false if a node is unknown or
## the road is left with fewer than two points.
func _place_nodes(r: Road, node_pos: Dictionary) -> bool:
	var pts := PackedVector2Array()
	for n in r.nodes:
		if not node_pos.has(n):
			push_warning("StreetData: edited road %s uses unknown node %s" % [r.id, n])
			return false
		pts.append(node_pos[n])
	r.points = pts
	return pts.size() >= 2


static func _oneway_of(props: Dictionary) -> int:
	var ow := str(props.get("oneway", "no"))
	# Roundabouts are one way round, whether or not OSM says so.
	if (ow == "no" or ow == "") and str(props.get("junction", "")) in ["roundabout", "circular"] and not props.has("oneway"):
		ow = "yes"
	if ow == "yes" or ow == "1" or ow == "true":
		return 1
	if ow == "-1" or ow == "reverse":
		return -1
	return 0


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _parse(gj: Dictionary, into: Chunk) -> void:
	if into == null:
		metadata = gj.get("metadata", metadata)
	for f: Dictionary in gj.get("features", []):
		var props: Dictionary = f.get("properties", {})
		var geom: Dictionary = f.get("geometry", {}) if f.get("geometry") is Dictionary else {}
		var kind := str(props.get("kind", ""))
		if not _feature_edits.is_empty() and kind in ["building", "area", "point"]:
			props = props.duplicate()
			geom = geom.duplicate()
			if not _apply_feature_edit(kind, props, geom):
				continue
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
	r.oneway = _oneway_of(props)
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
## from the road class (and its lane count, when OSM gives one), unless the
## map editor set tca:width / tca:sidewalk / tca:shoulder on the street.
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
	# Hand-tuned widths from the map editor win over everything else.
	if tags.has("tca:width"):
		width = str(tags["tca:width"]).to_float()
	if tags.has("tca:sidewalk"):
		sidewalk = str(tags["tca:sidewalk"]).to_float()
	if tags.has("tca:shoulder"):
		shoulder = str(tags["tca:shoulder"]).to_float()
	return Vector3(width, sidewalk, shoulder)


## Street points of one type (e.g. "highway=crossing"), city-wide.
func points_of_type(type: String) -> Array[MapPoint]:
	var out: Array[MapPoint] = []
	for p in points:
		if p.type == type:
			out.append(p)
	return out

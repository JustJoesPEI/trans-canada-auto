class_name BuildingGenerator
extends RefCounted
## Extrudes OSM building footprints into buildings that look like downtown
## Charlottetown: two- to four-storey Victorian brick blocks with cornices and
## shopfronts, clapboard and cedar-shingle houses with steep gables and white
## trim, and sandstone public buildings and churches.
##
## The footprint is always the real OSM outline. Height comes from the OSM
## `height` / `building:levels` tags when mapped, otherwise from the building
## type plus a little variety. Well-known buildings get extra detail from
## "landmarks" in map_config.json, matched by OSM id: their real material and
## colour, church towers and spires, Province House's portico.
## Every random choice is seeded by the OSM id, so the town is the same every run.
##
## Buildings are built a chunk at a time and merged: one mesh for the chunk's
## walls and roofs (two draw calls however many buildings), with each
## building's number in its vertices so the camera can still fade one at a
## time (see BuildingFade). Each building keeps its own collision body. The
## low-detail version for distant chunks leaves out cornices, awnings,
## parapet backs and collision; the walls still draw their windows.

const FLOOR_H := 3.2
const SHOP_FLOOR_H := 4.0 # matches shop_floor_height in building_wall.gdshader
const OVERHANG := 0.3

## Real geometry on the walls (window openings, sills, heads, casings,
## foundations, chimneys, porches) matching the windows the wall shader
## draws, so the facade casts shadows instead of being one flat slab.
## Off for the whole game with `--flat-facades`. It's only built for the
## chunks closest to the player (see ChunkStreamer and `detail`).
static var facade_relief := not OS.get_cmdline_user_args().has("--flat-facades")

## True while building the close-up version of a chunk's buildings.
var detail := false

enum Style { BRICK, CLAPBOARD, SANDSTONE, PAINTED, MODERN, SHINGLE, PLAIN, CHURCH }
## Wall-shader style for rough foundation stone (plinths and footings).
const STONE_STYLE := 8.0
## Wall-shader style for ribbed sandstone with slot windows (the
## Confederation Centre, landmark key "ribbed").
const RIBBED_STYLE := 9.0
enum Trim { WHITE, CREAM, GREEN, BLACK }

## Window bay width per style (metres); must match bay_metres() in the shader.
const BAY_W := {Style.BRICK: 2.0, Style.CLAPBOARD: 2.6, Style.SANDSTONE: 2.6, Style.PAINTED: 2.6,
	Style.MODERN: 3.0, Style.SHINGLE: 2.6, Style.PLAIN: 2.6, Style.CHURCH: 3.4}

const SKIP_TYPES := ["construction", "ruins", "no"]
## Roofs on posts: gas station canopies, carports, shelters.
const CANOPY_TYPES := ["roof", "canopy", "carport"]
const HOUSE_TYPES := ["house", "detached", "semidetached_house", "terrace", "bungalow", "cabin", "residential"]
const SMALL_TYPES := ["shed", "garage", "garages", "hut", "kiosk"]
const SHOP_TYPES := ["commercial", "retail", "kiosk", "supermarket"]
const CIVIC_TYPES := ["public", "civic", "government", "school", "college", "university", "train_station", "hall"]
const CHURCH_TYPES := ["church", "cathedral", "chapel"]

const BRICK := [Color(0.55, 0.25, 0.18), Color(0.6, 0.31, 0.21), Color(0.47, 0.22, 0.17), Color(0.63, 0.37, 0.26), Color(0.52, 0.31, 0.25), Color(0.42, 0.24, 0.2)]
const PAINTED := [Color(0.9, 0.85, 0.7), Color(0.92, 0.83, 0.55), Color(0.6, 0.67, 0.55), Color(0.5, 0.58, 0.67), Color(0.5, 0.2, 0.17), Color(0.9, 0.9, 0.86), Color(0.7, 0.7, 0.68), Color(0.33, 0.43, 0.38)]
const CLAPBOARD := [Color(0.93, 0.92, 0.88), Color(0.93, 0.87, 0.7), Color(0.93, 0.84, 0.56), Color(0.58, 0.7, 0.58), Color(0.6, 0.7, 0.78), Color(0.62, 0.22, 0.18), Color(0.74, 0.74, 0.71), Color(0.47, 0.6, 0.58), Color(0.86, 0.9, 0.93), Color(0.8, 0.55, 0.4)]
const SHINGLE := [Color(0.56, 0.53, 0.48), Color(0.52, 0.39, 0.28), Color(0.62, 0.58, 0.52), Color(0.45, 0.33, 0.25)]
const SANDSTONE := [Color(0.66, 0.44, 0.34), Color(0.7, 0.5, 0.39), Color(0.72, 0.68, 0.6)]
## Plain modern buildings out of downtown: concrete, beige and grey cladding.
const MODERN := [Color(0.72, 0.71, 0.67), Color(0.62, 0.62, 0.6), Color(0.78, 0.74, 0.64), Color(0.55, 0.57, 0.58), Color(0.7, 0.66, 0.58)]
const FLAT_ROOF := [Color(0.24, 0.24, 0.25), Color(0.3, 0.3, 0.3), Color(0.35, 0.34, 0.32)]
const PITCHED_ROOF := [Color(0.22, 0.22, 0.24), Color(0.3, 0.25, 0.21), Color(0.21, 0.29, 0.25), Color(0.35, 0.2, 0.16), Color(0.16, 0.16, 0.17), Color(0.32, 0.33, 0.36)]
const AWNINGS := [Color(0.12, 0.3, 0.2), Color(0.45, 0.1, 0.12), Color(0.12, 0.17, 0.32), Color(0.1, 0.1, 0.1), Color(0.55, 0.15, 0.1)]

var data: StreetData
var net: RoadNetwork
var terrain: Terrain
## Local height the current building's walls reach down to (below its floor
## on sloping ground, so the downhill side shows a foundation).
var _base := -0.1
var _landmarks: Dictionary
## Chains spoofed with made-up names (map_config.json "brands"), by the
## real name or brand OSM gives the building.
var _brands: Dictionary
## Buildings within this distance of the origin get the downtown look.
var _heritage_r := 900.0


func _init(street_data: StreetData, network: RoadNetwork, ground: Terrain) -> void:
	terrain = ground
	data = street_data
	net = network
	_landmarks = data.config.get("landmarks", {})
	_brands = data.config.get("brands", {})
	_index_brands()
	_heritage_r = float(data.config.get("heritage_district_m", 900.0))


var lod := false

## Full-detail buildings are merged by tile, this many metres square, rather
## than one mesh for the whole chunk: the graphics card only draws (and only
## draws into each shadow cascade) the tiles actually in view, instead of a
## whole 200 m block whenever any corner of it is. A building goes in the
## tile its centre is in. Distant chunks stay one mesh (few, cheap triangles,
## no shadows, and fewer draw calls).
const TILE := 50.0


## Which tile a building goes in ("Buildings_x_z", by its centre).
func _tile_name(b: StreetData.Building) -> String:
	if lod or b.ring.is_empty():
		return "Buildings"
	var c := Vector2.ZERO
	for p in b.ring:
		c += p
	c /= b.ring.size()
	return "Buildings_%d_%d" % [floori(c.x / TILE), floori(c.y / TILE)]


## Builds a chunk's buildings into `parent`: merged meshes, one per tile
## (MeshInstance3D "Buildings_x_z", or one "Buildings" for a distant chunk),
## and, in full detail, one collision body per building. Returns how many.
func build_chunk(buildings: Array[StreetData.Building], parent: Node3D, low_detail := false, areas: Array[StreetData.GroundArea] = [], cell := Vector2i.ZERO, mesh_only := false) -> int:
	lod = low_detail
	parking.clear()
	_yards.clear()
	dealers.clear()
	var area_styles: Dictionary = data.config.get("area_styles", {})
	for a in areas:
		var st: Variant = area_styles.get(str(a.tags.get("name", "")), null)
		if st is Dictionary and not (st as Dictionary).get("buildings", {}).is_empty():
			_yards.append([a.ring, st["buildings"]])
	var seen := {}
	for a in areas:
		if a.type == "amenity=parking":
			parking.append(a.ring)
			seen[a.id] = true
	# A big store's car park can be over the edge of its chunk: if any
	# building here faces its lot, bring in the lots next door too.
	var wants_lot := false
	for b in buildings:
		var lm_b: Dictionary = _landmarks.get(b.id, {})
		var br_b := _brand_of_building(b)
		if str(br_b.get("front", "")) == "parking" or str(lm_b.get("front", "")) == "parking" or br_b.get("showroom", false) or lm_b.get("showroom", false):
			wants_lot = true
			break
	if wants_lot:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				for a in data.load_chunk(cell.x + dx, cell.y + dz).areas:
					if a.type == "amenity=parking" and not seen.has(a.id):
						seen[a.id] = true
						parking.append(a.ring)
	_find_gas_stores(buildings, cell)
	var tiles := {} # tile name -> [walls kit, roofs kit]
	var tile_order: Array[String] = []
	var bodies: Array[StaticBody3D] = []
	var ground_bodies: Array[StaticBody3D] = []
	var signs_out: Array[Label3D] = []
	var posters_out: Array[MeshInstance3D] = []
	var count := 0
	for b in buildings:
		var part := _make(b, float(count + 1))
		if part.is_empty():
			continue
		count += 1
		var lift: float = part["floor_y"]
		var tile := _tile_name(b)
		if not tiles.has(tile):
			tiles[tile] = [_kit(), _kit()]
			tile_order.append(tile)
		(tiles[tile][0] as MeshKit).append_kit(part["walls"], lift)
		(tiles[tile][1] as MeshKit).append_kit(part["roof"], lift)
		for sg: Dictionary in part["signs"]:
			var label := Label3D.new()
			label.text = sg["text"]
			label.font_size = 64
			label.pixel_size = sg["pixel"]
			label.outline_size = 0
			label.modulate = sg["colour"]
			label.double_sided = false
			label.position = (sg["pos"] as Vector3) + Vector3(0, lift, 0)
			label.rotation.y = sg["yaw"]
			signs_out.append(label)
		for pg: Dictionary in part.get("posters", []):
			var poster := Ads.panel(str(pg["ad"]), pg["size"])
			poster.position = (pg["pos"] as Vector3) + Vector3(0, lift, 0)
			poster.rotation.y = pg["yaw"]
			posters_out.append(poster)
		if not lod and not mesh_only:
			var body := StaticBody3D.new()
			body.name = "Building_%s" % b.id
			body.position.y = lift
			body.collision_layer = Layers.SOLID
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(part["collision"])
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			body.set_meta("fade_id", float(count))
			body.set_meta("tile", tile)
			body.set_meta("osm_id", b.id)
			if b.tags.has("name"):
				var brand := _brand_of_building(b)
				body.set_meta("name", str(brand.get("name", b.tags["name"])))
			bodies.append(body)
			if part.has("ground"):
				# Decks and ramps: what wheels and feet stand on.
				var floors := StaticBody3D.new()
				floors.name = "Decks_%s" % b.id
				floors.position.y = lift
				floors.collision_layer = Layers.GROUND
				floors.collision_mask = 0
				var gs := ConcavePolygonShape3D.new()
				gs.backface_collision = true
				gs.set_faces(part["ground"])
				var gcs := CollisionShape3D.new()
				gcs.shape = gs
				floors.add_child(gcs)
				ground_bodies.append(floors)
				# The camera doesn't fade a parkade it's following someone round inside.
				var lay: Dictionary = part["parkade"]
				body.set_meta("inside", {"c": lay["c"], "u": lay["u"], "v": lay["v"], "hu": float(lay["hu"]) + 0.5,
					"hv": float(lay["hv"]) + 0.5, "y0": lift - 1.0, "y1": lift + (int(lay["levels"]) - 1) * Parkade.STOREY + 0.5})
	if count == 0:
		return 0
	var meshes := {} # tile name -> MeshInstance3D
	for tile in tile_order:
		# Indexed, with automatic LODs: a tile a little way off (and its
		# shadow) draws a simplified version once the difference is under
		# a pixel (docs/world_art.md).
		var mesh := ModelLod.finish_kits([[tiles[tile][0], Materials.get_shared().building_walls],
			[tiles[tile][1], Materials.get_shared().building_roofs]])
		var mi := MeshInstance3D.new()
		mi.name = tile
		mi.mesh = mesh
		parent.add_child(mi)
		meshes[tile] = mi
	for body in bodies:
		body.set_meta("fade_mesh", BuildingFade.new(meshes[body.get_meta("tile")], body.get_meta("fade_id")))
		parent.add_child(body)
	for body in ground_bodies:
		parent.add_child(body)
	for label in signs_out:
		if mesh_only:
			label.free()
		else:
			parent.add_child(label)
	for poster in posters_out:
		if mesh_only:
			poster.free()
		else:
			parent.add_child(poster)
	return count


## The close-up version of a chunk's buildings: the same merged tile meshes
## (same tiles and building numbers, so camera fading still works) with real
## window openings, trim, foundations, chimneys and porches, as
## {tile name: ArrayMesh}. The streamer swaps them in for the plain ones
## while the player is close. Safe on a worker thread.
func build_detail_mesh(buildings: Array[StreetData.Building], areas: Array[StreetData.GroundArea], cell: Vector2i) -> Dictionary:
	detail = true
	var holder := Node3D.new()
	build_chunk(buildings, holder, false, areas, cell, true)
	var out := {}
	for c in holder.get_children():
		if c is MeshInstance3D:
			out[str(c.name)] = (c as MeshInstance3D).mesh
	holder.free()
	return out


static func _kit() -> MeshKit:
	var k := MeshKit.new()
	k.use_color = true
	k.use_uv2 = true
	k.use_id = true
	return k


## The world brand standing in for a building of a real chain, or {}: the
## brand's own settings on top of its kind's (see map_config.json "brands").
func brand_of(b: StreetData.Building) -> Dictionary:
	for key: String in [str(b.tags.get("brand", "")), str(b.tags.get("name", ""))]:
		if key != "" and _brand_for.has(key):
			return _brand_for[key]
	return {}


## The world brand a building is built as: the one its landmark entry
## names ("brand", e.g. a dealer OSM names after the business, or one whose
## make differs from its OSM brand), else the one replacing its OSM brand
## or name.
func _brand_of_building(b: StreetData.Building) -> Dictionary:
	var lm: Dictionary = _landmarks.get(b.id, {})
	if lm.has("brand") and _brand_named.has(str(lm["brand"])):
		return _brand_named[str(lm["brand"])]
	return brand_of(b)


## Real chain name -> the full settings of the world brand replacing it.
var _brand_for: Dictionary = {}
## World brand name -> its full settings (for landmarks that name a brand).
var _brand_named: Dictionary = {}
## Car dealers built in this chunk, for StreetProps to fill their lots:
## {ring, showroom (its footprint), front: [p0, p1], stock: [model ids],
## used: the landmark's "used_lot" ({} for none)}.
var dealers: Array = []
## Parking lots in the chunk being built (big stores face their lot).
var parking: Array[PackedVector2Array] = []
## [ring, landmark settings] for the named areas in map_config.json
## "area_styles" with a "buildings" look: every building inside gets it.
var _yards: Array = []


## Gas stations where OSM puts the brand on the store but not on the
## canopy over the pumps (a plain building=roof): [store centre, brand] for
## every gas brand's store in or next to this chunk, so the canopy beside it
## can take the brand and be built with its pumps and colours.
var _gas_stores: Array = []
const GAS_CANOPY_REACH := 45.0


func _find_gas_stores(buildings: Array[StreetData.Building], cell: Vector2i) -> void:
	_gas_stores.clear()
	var loose := false
	for b in buildings:
		if CANOPY_TYPES.has(str(b.tags.get("building", ""))) and brand_of(b).is_empty() and not _landmarks.has(b.id):
			loose = true
			break
	if not loose:
		return
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var list: Array[StreetData.Building] = buildings if dx == 0 and dz == 0 else data.load_chunk(cell.x + dx, cell.y + dz).buildings
			for b in list:
				var br := brand_of(b)
				if str(br.get("kind", "")) == "gas" and not CANOPY_TYPES.has(str(b.tags.get("building", ""))):
					_gas_stores.append([_centre(b.ring), br])


## The gas brand of the nearest store within reach of a canopy, or {}.
func _gas_brand_near(ring: PackedVector2Array) -> Dictionary:
	var c := _centre(ring)
	var best := {}
	var best_d := GAS_CANOPY_REACH
	for s: Array in _gas_stores:
		var d := c.distance_to(s[0])
		if d < best_d:
			best_d = d
			best = s[1]
	return best


static func _centre(ring: PackedVector2Array) -> Vector2:
	var m := Vector2.ZERO
	for q in ring:
		m += q
	return m / float(maxi(1, ring.size()))


func _index_brands() -> void:
	var kinds: Dictionary = data.config.get("brand_kinds", {})
	for brand_name: String in _brands:
		var entry: Variant = _brands[brand_name]
		if brand_name.begins_with("_") or not (entry is Dictionary):
			continue
		var full: Dictionary = (kinds.get(str(entry.get("kind", "")), {}) as Dictionary).duplicate()
		full.merge(entry, true)
		full["name"] = brand_name
		if not full.has("sign"):
			full["sign"] = brand_name
		_brand_named[brand_name] = full
		for real: Variant in entry.get("replaces", []):
			_brand_for[str(real)] = full


## One building's meshes (local heights, floor at 0) and collision faces.
## Returns {} for footprints that aren't built.
func _make(b: StreetData.Building, id: float) -> Dictionary:
	var btype := str(b.tags.get("building", "yes"))
	var landmark: Dictionary = _landmarks.get(b.id, {})
	var brand := _brand_of_building(b)
	if brand.is_empty() and landmark.is_empty() and CANOPY_TYPES.has(btype) and not _gas_stores.is_empty():
		brand = _gas_brand_near(b.ring)
	if landmark.is_empty() and brand.is_empty() and not _yards.is_empty():
		var mid := Vector2.ZERO
		for q in b.ring:
			mid += q
		mid /= float(maxi(1, b.ring.size()))
		for y: Array in _yards:
			if Geometry2D.is_point_in_polygon(mid, y[0]):
				landmark = y[1]
	if landmark.is_empty():
		landmark = brand
	elif not brand.is_empty():
		# A chain's store with its own landmark entry: the brand's look and
		# sign underneath, the landmark's settings on top.
		var merged := brand.duplicate()
		merged.merge(landmark, true)
		landmark = merged
	if SKIP_TYPES.has(btype) and landmark.is_empty():
		return {}
	var ring := _clean_ring(b.ring)
	if ring.size() < 3:
		return {}
	var area := _signed_area(ring)
	if absf(area) < 6.0:
		return {}
	if area < 0.0:
		ring.reverse()
		area = -area
	if Parkade.is_parkade(landmark):
		return _parkade(ring, landmark, id)
	if CANOPY_TYPES.has(btype) or landmark.get("canopy", false):
		return _canopy(b, ring, landmark, id)
	if str(b.tags.get("man_made", "")) == "storage_tank" or str(landmark.get("style", "")) == "tank":
		return _tank(b, ring, landmark, id)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.id)
	var spec := _spec(b, btype, area, rng)
	if not landmark.is_empty():
		_apply_landmark(spec, landmark, area)
	var wall_h: float = spec["wall_h"]
	var style: int = spec["style"]
	var shop: bool = spec["shop"]

	var walls := _kit()
	walls.id = id
	var roof := _kit()
	roof.id = id

	var ground_floor := SHOP_FLOOR_H if shop and style != Style.CLAPBOARD and style != Style.SHINGLE else FLOOR_H
	var floors := 0.0
	if wall_h > ground_floor:
		floors = 1.0 + floorf((wall_h - 0.4 - ground_floor) / FLOOR_H)
	if style == Style.CHURCH:
		floors = floorf(wall_h / FLOOR_H)
	if not landmark.get("windows", true):
		floors = 0.0
	var wall_color: Color = spec["wall_color"]
	if facade_relief:
		# Calmer, weathered colours: less saturated and a touch darker.
		wall_color = _weathered(wall_color, 0.3, 0.94)
		spec["roof_color"] = _weathered(spec["roof_color"], 0.35, 0.92)
	var trim_color: Color = _trim_srgb(spec["trim"])
	var uv2 := Vector2(style, (1.0 if shop else 0.0) + 0.1 * float(spec["trim"]))
	var ribbed := facade_relief and bool(landmark.get("ribbed", false))
	if ribbed:
		uv2 = Vector2(RIBBED_STYLE, 0.1 * float(spec["trim"]))
		floors = wall_h / FLOOR_H
		spec["cornice"] = false
	walls.uv2 = uv2
	walls.color = _vertex_color(wall_color, floors)
	var flat: bool = not spec["gable"]
	var mansard: bool = spec.get("mansard", false)
	var parapet := 0.5 if flat and not mansard and style != Style.CLAPBOARD and style != Style.SHINGLE else 0.0
	var top := wall_h + parapet
	var bay_w: float = BAY_W[style]

	# On a slope the building stands at its uphill ground level (within 2 m of
	# its lowest corner) and its walls run down to the lowest corner, so the
	# downhill side shows a foundation below the ground floor.
	var low := INF
	var high := -INF
	for p in ring:
		var gh := terrain.h2(p)
		low = minf(low, gh)
		high = maxf(high, gh)
	var floor_y := minf(high, low + 2.0)
	_base = minf(-0.1, low - floor_y - 0.25)

	# A landmark with its own entrances (or a mansard roof) knows its front
	# before the walls go up: only the front wall gets shop glass when
	# "shopfront" is "front", so the loading docks round the back don't.
	var front: Array = []
	if not landmark.is_empty():
		front = _front_line(ring, landmark, spec["obb"])
	var front_only := str(landmark.get("shopfront", "")) == "front" and not front.is_empty()
	var front_out := Vector2.ZERO
	var front_mid := Vector2.ZERO
	if front_only:
		var ft: Vector2 = ((front[1] as Vector2) - (front[0] as Vector2)).normalized()
		front_out = Vector2(ft.y, -ft.x)
		front_mid = ((front[0] as Vector2) + (front[1] as Vector2)) * 0.5

	var collision := PackedVector3Array()
	var porch_done := false
	var awning_color: Color = spec["awning"]
	for i in ring.size():
		var p0 := ring[i]
		var p1 := ring[(i + 1) % ring.size()]
		var seg := p0.distance_to(p1)
		if seg < 0.05:
			continue
		var t := (p1 - p0) / seg
		var out2 := Vector2(t.y, -t.x)
		var out := Vector3(out2.x, 0.0, out2.y)
		var w_shop := shop
		var w_floors := floors
		if front_only:
			# Shop glass on walls looking the same way as the front and
			# standing within a few metres of its line; blank walls elsewhere.
			# ("front_depth" widens that for a plaza whose front steps back.)
			var on_front := out2.dot(front_out) > 0.9 and absf(((p0 + p1) * 0.5 - front_mid).dot(front_out)) < float(landmark.get("front_depth", 6.0))
			w_shop = on_front
			w_floors = 1.0 if on_front else 0.0
			walls.uv2 = Vector2(style, (1.0 if on_front else 0.0) + 0.1 * float(spec["trim"]))
			walls.color = _vertex_color(wall_color, w_floors)
		if ribbed:
			_wall(walls, p0, p1, _base, top, out, seg, bay_w)
			if detail:
				_ribbed_relief(walls, p0, p1, out2, seg, wall_h, wall_color)
		elif detail:
			var holes := _window_rects(seg, bay_w, style, w_shop, w_floors)
			_wall_open(walls, p0, p1, _base, top, out2, seg, bay_w, holes, style, wall_color, trim_color)
			_facade_relief(walls, p0, p1, out2, seg, bay_w, style, w_shop, w_floors, trim_color, wall_color, holes)
			if not porch_done and (style == Style.CLAPBOARD or style == Style.SHINGLE) and seg > bay_w * 2.5 and floors >= 1.0 and _faces_street(p0, p1, out2):
				porch_done = true
				if rng.randf() < 0.75:
					_porch(walls, roof, p0, p1, out2, seg, bay_w, trim_color, spec["roof_color"])
		else:
			_wall(walls, p0, p1, _base, top, out, seg, bay_w)
		if (landmark.has("base_colour") or landmark.has("cap_colour")) and seg > 0.3:
			# A brick base course round the bottom of the walls, and a band of
			# colour along the top edge (a chain's stripe on its parapet).
			var save_bc := walls.color
			var save_bu := walls.uv2
			var oa := p0 + out2 * 0.04
			var ob := p1 + out2 * 0.04
			if landmark.has("base_colour"):
				walls.uv2 = Vector2(Style.BRICK, 0.0)
				walls.color = _vertex_color(Color.from_string(str(landmark["base_colour"]), Color(0.45, 0.33, 0.28)), 0.0)
				walls.wall(oa, ob, _base, float(landmark.get("base_height", 1.2)), out)
			if landmark.has("cap_colour"):
				walls.uv2 = Vector2(Style.PLAIN, 0.0)
				walls.color = _vertex_color(Color.from_string(str(landmark["cap_colour"]), Color(0.8, 0.1, 0.1)), 0.0)
				walls.wall(oa, ob, top - float(landmark.get("cap_height", 0.3)), top + 0.02, out)
			walls.color = save_bc
			walls.uv2 = save_bu
		if lod:
			if parapet > 0.0 and seg > 0.5:
				_coping(walls, p0, p1, out2, top)
			continue
		if parapet > 0.0:
			# Inside face of the parapet: plain, no windows.
			var save := walls.color
			walls.color = _vertex_color(wall_color, 0.0)
			walls.wall(p0, p1, wall_h, top, -out)
			walls.color = save
		if spec["cornice"] and seg > 1.0:
			_cornice(walls, p0, p1, out2, top, trim_color, bay_w)
		elif parapet > 0.0 and seg > 0.5:
			_coping(walls, p0, p1, out2, top)
		if shop and awning_color.a > 0.0 and seg > 3.0 and _faces_street(p0, p1, out2):
			_awnings(roof, p0, p1, out2, seg, bay_w, ground_floor, awning_color, rng.randf() < 0.35)
		collision.append_array(_quad_faces(p0, p1, _base, wall_h))

	roof.color = _vertex_color(spec["roof_color"], 1.0)
	if spec["gable"] and style == Style.CHURCH and float((spec["obb"] as Dictionary)["half_v"]) > 9.0:
		# A big church: flat aisle roofs over the whole footprint and a steep
		# nave roof down the middle, rather than one roof the size of a field.
		roof.uv2 = Vector2.ZERO
		_flat_roof(roof, ring, wall_h + 0.02)
		var nave := spec.duplicate()
		var nave_obb: Dictionary = (spec["obb"] as Dictionary).duplicate()
		nave_obb["half_v"] = minf(float(nave_obb["half_v"]) * 0.45, 9.0)
		nave["obb"] = nave_obb
		_gable_roof(walls, roof, nave, rng)
	elif spec["gable"]:
		_gable_roof(walls, roof, spec, rng)
	else:
		roof.uv2 = Vector2.ZERO
		_flat_roof(roof, ring, wall_h + 0.02)
		if mansard:
			_mansard_roof(walls, roof, ring, spec)

	var signs: Array = []
	if not landmark.is_empty():
		if not front.is_empty():
			collision.append_array(_landmark_extras(walls, roof, landmark, spec, front[0], front[1], trim_color))
			var entrances: Array = landmark.get("entrances", [])
			if landmark.has("units"):
				collision.append_array(_units(walls, ring, front[0], front[1], landmark, spec, signs))
			if not entrances.is_empty():
				# Each entrance carries its own sign; no board in the middle.
				collision.append_array(_entrances(walls, roof, front[0], front[1], landmark, spec, signs))
			elif landmark.has("barrel"):
				collision.append_array(_quick_lube(walls, roof, ring, front[0], front[1], landmark, spec, wall_h, signs))
			elif landmark.get("showroom", false):
				collision.append_array(_showroom(walls, roof, ring, front[0], front[1], landmark, spec, wall_h, signs))
			elif landmark.has("sign") and not landmark.has("units"):
				var board_h := float(landmark.get("sign_height", 0.75))
				if board_h > 1.2:
					# Big signs grow with the store: about 4 m on a 100 m front.
					board_h = clampf(front[0].distance_to(front[1]) / 25.0, board_h, 4.2)
				# A big sign sits high on the wall; a small board just over the door.
				var board_y := wall_h - board_h - 0.6 if board_h > 1.2 else ground_floor + 0.35
				var board := _name_board(walls, str(landmark["sign"]), front[0], front[1], maxf(board_y, 0.5), board_h, Color.from_string(str(landmark.get("sign_colour", "#1a1f1f")), Color(0.1, 0.12, 0.12)))
				board["colour"] = Color.from_string(str(landmark.get("sign_text", "#f2f2ec")), Color(0.95, 0.95, 0.92))
				signs.append(board)
				if str(landmark.get("front", "")) == "parking" and not lod:
					collision.append_array(_storefront(walls, roof, front[0], front[1], landmark, spec, wall_h))
				if board_h > 1.2 and str(landmark.get("front", "")) == "parking":
					# Big stores: a second sign facing the street, if that's another side.
					var street_lm := landmark.duplicate()
					street_lm.erase("front")
					var street_front := _front_line(ring, street_lm, spec["obb"])
					if not street_front.is_empty() and ((street_front[0] + street_front[1]) * 0.5).distance_to((front[0] + front[1]) * 0.5) > 5.0:
						var b2 := _name_board(walls, str(landmark["sign"]), street_front[0], street_front[1], maxf(board_y, 0.5), board_h, Color.from_string(str(landmark.get("sign_colour", "#1a1f1f")), Color(0.1, 0.12, 0.12)))
						b2["colour"] = board["colour"]
						signs.append(b2)

	for ws: Dictionary in landmark.get("wall_signs", []):
		_wall_sign(walls, ring, spec, landmark, ws, wall_color, signs)

	var posters: Array = []
	if not front.is_empty() and not lod and landmark.has("posters"):
		posters = _window_posters(landmark["posters"], front[0], front[1], b.id)
	return {"walls": walls, "roof": roof, "collision": collision, "floor_y": floor_y, "signs": signs, "posters": posters}


## Posters in a chain's shop windows along its front (p0 to p1): up to one
## per 3 m of front, clear of the door in the middle, each location starting
## at a different poster of the brand's list. Returns
## [{"ad", "pos", "yaw", "size"}] for build_chunk to put up.
func _window_posters(ads: Array, p0: Vector2, p1: Vector2, building_id: String) -> Array:
	var out: Array = []
	var usable: Array[String] = []
	for ad: Variant in ads:
		if Ads.has(str(ad)):
			usable.append(str(ad))
	var length := p0.distance_to(p1)
	if usable.is_empty() or length < 5.0:
		return out
	var t := (p1 - p0) / length
	var normal := Vector2(t.y, -t.x)
	var size := Vector2(0.8, 1.2)
	# Spots along the front, from the middle outward, skipping the door.
	var spots: Array[float] = []
	var step := 1.6
	var d := 2.0
	while d < length * 0.5 - 0.7 and spots.size() < 6:
		spots.append(length * 0.5 - d)
		spots.append(length * 0.5 + d)
		d += step
	var count := mini(spots.size(), maxi(1, int(length / 3.0)))
	var start := absi(hash(building_id)) % usable.size()
	for i in count:
		var at := p0 + t * spots[i]
		out.append({"ad": usable[(start + i) % usable.size()], "pos": MeshKit.v3(at + normal * 0.1, 1.55),
			"yaw": StreetProps.yaw_facing(normal), "size": size})
	return out


# --- what kind of building is this? -------------------------------------------------------

func _spec(b: StreetData.Building, btype: String, area: float, rng: RandomNumberGenerator) -> Dictionary:
	var tags := b.tags
	var is_house := HOUSE_TYPES.has(btype)
	var is_small := SMALL_TYPES.has(btype)
	var is_church := CHURCH_TYPES.has(btype) or str(tags.get("amenity", "")) == "place_of_worship"
	var is_civic := CIVIC_TYPES.has(btype)
	var is_shop := SHOP_TYPES.has(btype) or tags.has("shop") or tags.has("office") \
		or str(tags.get("amenity", "")) in ["restaurant", "cafe", "bar", "pub", "bank", "fast_food", "pharmacy"]
	# Downtown (the heritage district) is Victorian brick blocks and shops.
	# Out in the rest of the city an untagged building of house size is a
	# house, and anything big that isn't a church or a landmark is a plain
	# modern box: a mall, school, plant or warehouse, without shopfronts.
	var centre := Vector2.ZERO
	for q in b.ring:
		centre += q
	centre /= float(b.ring.size())
	var downtown := centre.length() < _heritage_r
	var big_box := false
	if btype == "yes" and not is_shop and not is_civic and not is_church:
		if downtown:
			is_house = area < 170.0 and rng.randf() < 0.65
			is_shop = not is_house and rng.randf() < 0.65
		else:
			# A footprint of house size is a house, unless the lidar shows
			# it standing well over two storeys (an apartment block).
			is_house = area < 260.0 and float(tags.get("lidar_top", 0.0)) < 10.5
	if not downtown and not is_house and not is_small and not is_church and not _landmarks.has(b.id) \
			and (area > 450.0 or btype in ["industrial", "warehouse", "retail", "commercial", "supermarket", "hospital", "office"]):
		big_box = true

	var style := Style.BRICK
	var levels := 2.0
	var trim := Trim.WHITE
	if is_small:
		style = Style.SHINGLE if rng.randf() < 0.5 else Style.CLAPBOARD
		levels = 1.0
	elif is_house:
		style = Style.SHINGLE if rng.randf() < 0.3 else Style.CLAPBOARD
		levels = 2.0 if rng.randf() < 0.7 else 1.5
	elif is_church:
		style = Style.CHURCH
		levels = 4.0
	elif big_box:
		style = Style.MODERN if rng.randf() < 0.25 else Style.PAINTED
		levels = float(rng.randi_range(1, 3))
		trim = Trim.WHITE
	elif is_civic:
		style = Style.SANDSTONE if rng.randf() < 0.6 else Style.BRICK
		levels = float(rng.randi_range(2, 4))
	elif btype == "apartments":
		style = Style.BRICK if rng.randf() < 0.55 else Style.PAINTED
		levels = float(rng.randi_range(3, 4))
	else:
		style = Style.BRICK if rng.randf() < 0.65 else Style.PAINTED
		levels = float(rng.randi_range(2, 3))
	if style == Style.BRICK:
		trim = Trim.CREAM if rng.randf() < 0.5 else (Trim.WHITE if rng.randf() < 0.6 else Trim.GREEN)
	elif style == Style.PAINTED:
		trim = Trim.WHITE if rng.randf() < 0.6 else Trim.BLACK

	match str(tags.get("building:material", "")):
		"brick":
			if style != Style.CHURCH:
				style = Style.BRICK
		"wood":
			if style != Style.SHINGLE:
				style = Style.CLAPBOARD
		"stone", "sandstone":
			style = Style.CHURCH if style == Style.CHURCH else Style.SANDSTONE
		"plaster", "concrete":
			style = Style.PAINTED
		"glass":
			style = Style.MODERN

	var tagged_levels := str(tags.get("building:levels", "")).to_float()
	if tagged_levels > 0.0:
		levels = tagged_levels
	var ground := SHOP_FLOOR_H if is_shop and not is_house else FLOOR_H
	var wall_h := ground + (levels - 1.0) * FLOOR_H + 0.4
	var tagged_h := str(tags.get("height", "")).to_float()

	var roof_shape := str(tags.get("roof:shape", ""))
	var gable := false
	if roof_shape in ["gabled", "hipped", "gambrel", "mansard"]:
		gable = true
	elif roof_shape == "" and (is_house or is_small or is_church):
		gable = true
	var obb := _obb(b.ring)
	if gable and not is_church:
		# Only put a simple gable on footprints close to a rectangle, and not
		# over very deep buildings, where the roof would tower over the walls.
		var fill := area / maxf(obb["area"], 0.01)
		var span: float = obb["half_v"] * 2.0
		gable = fill > 0.8 and span < 12.0
	if tagged_h > 0.0:
		wall_h = tagged_h
		if gable:
			wall_h = maxf(2.5, tagged_h - float(obb["half_v"]) * tan(deg_to_rad(38.0)))

	# The lidar survey's measurements, where it saw the building: real wall
	# height, flat or pitched, which way the ridge runs, and how steep.
	var pitch := rng.randf_range(36.0, 45.0) if is_house or is_small else rng.randf_range(28.0, 35.0)
	var hip := false
	# A landmark entry that sets its own height or roof wins over the lidar;
	# one that only sets colours or materials keeps the measured shape.
	var lm_shape: Dictionary = _landmarks.get(b.id, {})
	if tags.has("lidar_top") and not (lm_shape.has("wall_height") or lm_shape.has("roof")):
		var top := float(tags["lidar_top"])
		var eave := float(tags.get("lidar_eave", top))
		var kind := str(tags.get("lidar_roof", "flat"))
		var fill := area / maxf(obb["area"], 0.01)
		if kind != "flat" and fill > 0.65 and not is_church:
			gable = true
			hip = kind == "hipped"
			if str(tags.get("lidar_ridge", "long")) == "short":
				# The ridge runs across the footprint: swap the box's axes.
				obb = obb.duplicate()
				var hu: float = obb["half_u"]
				obb["half_u"] = obb["half_v"]
				obb["half_v"] = hu
				var u2: Vector2 = obb["u"]
				obb["u"] = obb["v"]
				obb["v"] = u2
			wall_h = maxf(2.4, eave)
			pitch = clampf(rad_to_deg(atan2(maxf(top - eave, 0.5), maxf(float(obb["half_v"]), 1.0))), 15.0, 55.0)
		elif not is_church:
			gable = false
			wall_h = maxf(2.6, top - 0.4)

	var palette: Array = BRICK
	match style:
		Style.CLAPBOARD:
			palette = CLAPBOARD
		Style.SHINGLE:
			palette = SHINGLE
		Style.SANDSTONE, Style.CHURCH:
			palette = SANDSTONE
		Style.PAINTED:
			palette = MODERN if big_box else PAINTED
		Style.MODERN:
			palette = MODERN
	var wall_color: Color = palette[rng.randi() % palette.size()]
	wall_color = Color.from_string(str(tags.get("building:colour", "")), wall_color)
	var roof_palette: Array = PITCHED_ROOF if gable else FLAT_ROOF
	var roof_color: Color = roof_palette[rng.randi() % roof_palette.size()]
	roof_color = Color.from_string(str(tags.get("roof:colour", "")), roof_color)
	var awning := Color(0, 0, 0, 0)
	var shop := is_shop and not is_house and not big_box
	if shop and rng.randf() < 0.55:
		awning = AWNINGS[rng.randi() % AWNINGS.size()]

	return {
		"style": style, "wall_h": wall_h, "shop": shop, "trim": trim,
		"gable": gable, "hip": hip, "pitch": pitch,
		"obb": obb, "wall_color": wall_color, "roof_color": roof_color, "awning": awning,
		"cornice": not gable and not big_box and style in [Style.BRICK, Style.SANDSTONE, Style.PAINTED],
	}


## Overrides from map_config.json "landmarks" (see the comment there).
func _apply_landmark(spec: Dictionary, lm: Dictionary, _area: float) -> void:
	var styles := {"brick": Style.BRICK, "clapboard": Style.CLAPBOARD, "sandstone": Style.SANDSTONE,
		"painted": Style.PAINTED, "modern": Style.MODERN, "shingle": Style.SHINGLE, "church": Style.CHURCH,
		"plain": Style.PLAIN}
	if lm.has("style"):
		spec["style"] = styles.get(str(lm["style"]), spec["style"])
	if lm.has("colour"):
		spec["wall_color"] = Color.from_string(str(lm["colour"]), spec["wall_color"])
	if lm.has("roof_colour"):
		spec["roof_color"] = Color.from_string(str(lm["roof_colour"]), spec["roof_color"])
	if lm.has("wall_height"):
		spec["wall_h"] = float(lm["wall_height"])
	if lm.has("roof"):
		spec["gable"] = str(lm["roof"]) in ["gabled", "hipped"]
		spec["hip"] = str(lm["roof"]) == "hipped"
	if lm.has("chimneys"):
		spec["chimneys"] = int(lm["chimneys"])
	if lm.has("pitch"):
		spec["pitch"] = float(lm["pitch"])
	if str(lm.get("roof", "")) == "mansard":
		# Low walls under a deep sloping skirt of shingles round a flat top.
		# The skirt's lower edge is eave_height up, roof_overhang out from the
		# walls (a covered walk along the front); the walls stop where the
		# skirt crosses them.
		var pitch := float(lm.get("pitch", 30.0))
		var eave := float(lm.get("eave_height", 3.8))
		var overhang := float(lm.get("roof_overhang", 0.6))
		spec["mansard"] = true
		spec["pitch"] = pitch
		spec["eave"] = eave
		spec["overhang"] = overhang
		spec["roof_top"] = float(lm.get("roof_top", eave + 4.5))
		spec["wall_h"] = eave + overhang * tan(deg_to_rad(pitch))
	if lm.has("shop"):
		spec["shop"] = bool(lm["shop"])
	if lm.has("trim"):
		spec["trim"] = {"white": Trim.WHITE, "cream": Trim.CREAM, "green": Trim.GREEN, "black": Trim.BLACK}.get(str(lm["trim"]), spec["trim"])
	if lm.has("awning"):
		spec["awning"] = Color.from_string(str(lm["awning"]), Color(0, 0, 0, 0)) if str(lm["awning"]) != "none" else Color(0, 0, 0, 0)
	elif lm.has("style") or lm.has("towers") or lm.has("portico"):
		spec["awning"] = Color(0, 0, 0, 0)
	var style: int = spec["style"]
	spec["cornice"] = not spec["gable"] and style in [Style.BRICK, Style.SANDSTONE, Style.PAINTED]
	if lm.has("cornice"):
		spec["cornice"] = bool(lm["cornice"])


static func _vertex_color(c: Color, floors: float) -> Color:
	var lin := c.srgb_to_linear()
	return Color(lin.r, lin.g, lin.b, clampf(floors, 0.0, 16.0) / 16.0)


## A colour pulled toward its own grey by `desat` and darkened by `dim`, the
## way paint and brick look after years outdoors.
static func _weathered(c: Color, desat: float, dim: float) -> Color:
	var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	var g := Color(l, l, l)
	var w := c.lerp(g, desat) * dim
	w.a = c.a
	return w


static func _trim_srgb(trim: int) -> Color:
	match trim:
		Trim.CREAM:
			return Color(0.88, 0.82, 0.68)
		Trim.GREEN:
			return Color(0.17, 0.3, 0.21)
		Trim.BLACK:
			return Color(0.15, 0.14, 0.13)
	return Color(0.92, 0.92, 0.89)


# --- walls and their trimmings -------------------------------------------------------------

## Raised pieces on one wall, laid out exactly like the windows in
## building_wall.gdshader (same bays, storeys and proportions), so each painted
## window gets a real sill and head, and houses a real casing, that stand out
## from the wall and throw a shadow.
func _facade_relief(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, seg: float, bay_w: float, style: int, shop: bool, floors: float, trim: Color, wall_color: Color, holes: Array) -> void:
	if style == Style.CHURCH:
		_church_relief(kit, p0, p1, out, seg, bay_w, floors, wall_color, holes)
		return
	if style == Style.PLAIN:
		return
	var save_c := kit.color
	var save_uv := kit.uv2
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	var t := (p1 - p0) / seg
	var masonry := style == Style.BRICK or style == Style.SANDSTONE or style == Style.PAINTED or style == Style.MODERN
	var is_house := style == Style.CLAPBOARD or style == Style.SHINGLE
	var stone := Color(0.64, 0.6, 0.53)
	var tall_ground := shop and (style == Style.BRICK or style == Style.SANDSTONE or style == Style.PAINTED or style == Style.MODERN)
	# Base course: a dark, weathered stone plinth (just a low granite step
	# under a shopfront), or a skirt board on wooden houses.
	var plinth := 0.15 if tall_ground else (0.55 if masonry else 0.3)
	# Fieldstone under everything; on wooden houses a skirt board sits on it.
	kit.uv2 = Vector2(STONE_STYLE, 0.0)
	kit.color = _vertex_color(Color(0.92, 0.9, 0.88), 0.0)
	_slab(kit, p0, t, out, -0.04, seg + 0.04, _base, plinth if masonry else 0.12, 0.05)
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	if not masonry:
		kit.color = _vertex_color(trim, 0.0)
		_slab(kit, p0, t, out, -0.04, seg + 0.04, 0.12, 0.3, 0.035)
	if not tall_ground:
		kit.color = _vertex_color(Color(0.52, 0.5, 0.46) if masonry else trim, 0.0)
		_slab(kit, p0, t, out, -0.06, seg + 0.06, plinth - 0.06, plinth + 0.04, 0.07)
	# Corner boards on wooden houses.
	var top_y := 0.0
	var gf := SHOP_FLOOR_H if tall_ground else FLOOR_H
	top_y = gf + maxf(0.0, floors - 1.0) * FLOOR_H
	if is_house and seg > 1.0:
		kit.color = _vertex_color(trim, 0.0)
		for along in [0.0, seg - 0.14]:
			_slab(kit, p0, t, out, along, along + 0.14, 0.3, top_y, 0.035)
	# A downspout at one end of most walls, from the eave to the ground.
	if seg > 6.0 and (is_house or style == Style.BRICK) and int(absf(p0.x * 3.1 + p0.y * 1.7)) % 2 == 0:
		kit.color = _vertex_color(trim if is_house else Color(0.2, 0.22, 0.2), 0.0)
		_slab(kit, p0, t, out, 0.2, 0.28, _base, top_y - 0.05, 0.09)
	# Sills and heads (or casings) round each opening.
	for h: Dictionary in holes:
		var x0: float = h["x0"]
		var x1: float = h["x1"]
		var y_bot: float = h["y0"]
		var y_top: float = h["y1"]
		match str(h["kind"]):
			"door":
				# Two stone steps up to the door.
				kit.uv2 = Vector2(STONE_STYLE, 0.0)
				kit.color = _vertex_color(Color(0.95, 0.93, 0.9), 0.0)
				_slab(kit, p0, t, out, x0 - 0.06, x1 + 0.06, _base, 0.18, 0.55)
				_slab(kit, p0, t, out, x0 - 0.06, x1 + 0.06, _base, 0.36, 0.28)
				kit.uv2 = Vector2(Style.PLAIN, 0.0)
				kit.color = _vertex_color(trim, 0.0)
				var fw := 0.11
				_slab(kit, p0, t, out, x0 - fw, x0, 0.36, y_top, 0.04)
				_slab(kit, p0, t, out, x1, x1 + fw, 0.36, y_top, 0.04)
				_slab(kit, p0, t, out, x0 - fw - 0.08, x1 + fw + 0.08, y_top, y_top + 0.12, 0.1)
				_slab(kit, p0, t, out, x0 - fw - 0.12, x1 + fw + 0.12, y_top + 0.12, y_top + 0.18, 0.5)
			"shop":
				pass
			_:
				if is_house:
					var fw := 0.12
					kit.color = _vertex_color(trim, 0.0)
					_slab(kit, p0, t, out, x0 - fw, x0, y_bot, y_top, 0.035)
					_slab(kit, p0, t, out, x1, x1 + fw, y_bot, y_top, 0.035)
					_slab(kit, p0, t, out, x0 - fw - 0.03, x1 + fw + 0.03, y_top, y_top + fw * 1.3, 0.06)
					_slab(kit, p0, t, out, x0 - fw - 0.05, x1 + fw + 0.05, y_bot - 0.06, y_bot, 0.08)
				else:
					kit.color = _vertex_color(stone if style == Style.BRICK else trim, 0.0)
					_slab(kit, p0, t, out, x0 - 0.08, x1 + 0.08, y_bot - 0.1, y_bot, 0.1)
					var rise := _arch_of(h)
					if rise > 0.0:
						# An arched head of stone voussoirs following the curve,
						# with a taller keystone in the middle.
						var pts := _arch_points(h, x0 - 0.08, x1 + 0.08, y_top)
						for k in pts.size() - 1:
							var pa: Vector2 = pts[k]
							var pb: Vector2 = pts[k + 1]
							var yb := minf(pa.y, pb.y)
							_slab(kit, p0, t, out, pa.x, pb.x, yb, maxf(pa.y, pb.y) + 0.17, 0.05)
						var ac := float(h["ac"])
						_slab(kit, p0, t, out, ac - 0.09, ac + 0.09, y_top + rise - 0.05, y_top + rise + 0.26, 0.08)
					else:
						_slab(kit, p0, t, out, x0 - 0.06, x1 + 0.06, y_top, y_top + 0.18, 0.06)
						_slab(kit, p0, t, out, x0 - 0.09, x1 + 0.09, y_top + 0.18, y_top + 0.22, 0.09)
	kit.color = save_c
	kit.uv2 = save_uv


## Where the openings are on one wall, in metres along it and up it: the
## same windows, doors and shopfronts building_wall.gdshader paints, so the
## wall can be built with real holes in those places. Each is a Dictionary
## with x0, x1, y0, y1, depth (how far back the glass sits) and kind.
func _window_rects(seg: float, bay_w: float, style: int, shop: bool, floors: float) -> Array:
	var holes := []
	if style == Style.CHURCH:
		return _church_windows(seg, bay_w, floors)
	if style == Style.PLAIN or style == Style.MODERN:
		return holes
	var bays := roundf(seg / bay_w)
	if seg < bay_w * 0.7 or bays < 1.0 or floors < 0.5:
		return holes
	var is_house := style == Style.CLAPBOARD or style == Style.SHINGLE
	var tall_ground := shop and (style == Style.BRICK or style == Style.SANDSTONE or style == Style.PAINTED)
	var gf := SHOP_FLOOR_H if tall_ground else FLOOR_H
	var bay_len := seg / bays
	var lo := Vector2(0.36, 0.28) if is_house else Vector2(0.33, 0.22)
	var hi := Vector2(0.64, 0.8) if is_house else Vector2(0.67, 0.8)
	var sash := 0.012 if is_house else 0.03
	for fi in int(floors):
		var fh := gf if fi == 0 else FLOOR_H
		var fy0 := 0.0 if fi == 0 else gf + (fi - 1) * FLOOR_H
		var shopfront := fi == 0 and (tall_ground or (shop and not is_house))
		for b in int(bays):
			if shopfront:
				# Glass between the pilasters, above the kick plate, under the sign band.
				holes.append({"x0": (b + 0.07) * bay_len, "x1": (b + 0.93) * bay_len, "y0": 0.1 * fh, "y1": 0.8 * fh, "depth": 0.25, "kind": "shop"})
			elif is_house and fi == 0 and b == 1:
				holes.append({"x0": (b + 0.36) * bay_len, "x1": (b + 0.64) * bay_len, "y0": 0.36, "y1": 0.72 * fh, "depth": 0.12, "kind": "door"})
			else:
				var h := {"x0": (b + lo.x - sash) * bay_len, "x1": (b + hi.x + sash) * bay_len,
					"y0": fy0 + (lo.y - sash) * fh, "y1": fy0 + (hi.y + sash) * fh,
					"depth": 0.08 if is_house else 0.16, "kind": "win", "arch": 0.0}
				if not is_house:
					# A shallow segmental arch over the window, the same curve
					# the wall shader paints: centre, half span and rise.
					h["arch"] = 0.05 * fh
					h["ac"] = (b + 0.5) * bay_len
					h["aw"] = (hi.x - lo.x) * 0.5 * bay_len
				holes.append(h)
	return holes


## Tall pointed windows down a church wall, one per bay, where the wall
## shader paints them: glass from 2.2 m up to 1.1 m under the top, with a
## pointed head, set 30 cm into the thick masonry.
func _church_windows(seg: float, bay_w: float, floors: float) -> Array:
	var holes := []
	var bays := roundf(seg / bay_w)
	var top := floors * FLOOR_H - 1.2
	if seg < bay_w * 0.7 or bays < 1.0 or top < 4.0:
		return holes
	var bay_len := seg / bays
	for b in int(bays):
		holes.append({"x0": (b + 0.33) * bay_len, "x1": (b + 0.67) * bay_len, "y0": 2.2, "y1": top - 1.1,
			"depth": 0.3, "kind": "church", "arch": 1.1, "ac": (b + 0.5) * bay_len, "aw": 0.17 * bay_len})
	return holes


## A wall built with real holes where `holes` says, a reveal round the inside
## of each hole, and the glass (or door) set back in it. The faces keep the
## same UVs as a plain wall, so the shader paints brick round the holes and
## the window, curtains or door on the set-back pane. Their building id is
## marked (+0.5) so the shader knows the depth is real and draws no fake one.
func _wall_open(kit: MeshKit, p0: Vector2, p1: Vector2, y0: float, y1: float, out: Vector2, seg: float, bay_w: float, holes: Array, style: int, wall_color: Color, trim: Color) -> void:
	var o3 := Vector3(out.x, 0.0, out.y)
	if holes.is_empty():
		_wall(kit, p0, p1, y0, y1, o3, seg, bay_w)
		return
	var t := (p1 - p0) / seg
	var t3 := Vector3(t.x, 0.0, t.y)
	var bays := roundf(seg / bay_w)
	var u_per_m := bays / seg
	var save_id := kit.id
	kit.id = save_id + 0.5
	# The face: horizontal bands between every hole edge; in each band, the
	# pieces between the holes that cross it.
	var cuts := PackedFloat32Array([y0, y1])
	for h: Dictionary in holes:
		cuts.append(h["y0"])
		cuts.append(h["y1"])
		if _arch_of(h) > 0.0:
			cuts.append(float(h["y1"]) + _arch_of(h))
	cuts.sort()
	for k in cuts.size() - 1:
		var ya := cuts[k]
		var yb := cuts[k + 1]
		if yb - ya < 0.001 or ya < y0 - 0.001 or yb > y1 + 0.001:
			continue
		var mid := (ya + yb) * 0.5
		var spans := []
		for h: Dictionary in holes:
			if float(h["y0"]) < mid and float(h["y1"]) + _arch_of(h) > mid:
				spans.append(Vector2(h["x0"], h["x1"]))
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var x := 0.0
		for sp: Vector2 in spans:
			_face(kit, p0, t, o3, x, sp.x, ya, yb, 0.0, u_per_m)
			x = sp.y
		_face(kit, p0, t, o3, x, seg, ya, yb, 0.0, u_per_m)
	# Reveals and the set-back pane.
	var reveal := _vertex_color(trim if style == Style.CLAPBOARD or style == Style.SHINGLE else wall_color.darkened(0.12), 0.0)
	for h: Dictionary in holes:
		var x0: float = h["x0"]
		var x1: float = h["x1"]
		var hy0: float = h["y0"]
		var hy1: float = h["y1"]
		var d: float = h["depth"]
		var save_c := kit.color
		var save_uv := kit.uv2
		kit.color = reveal
		kit.uv2 = Vector2(Style.PLAIN, 0.0)
		var a0 := p0 + t * x0
		var a1 := p0 + t * x1
		var b0 := a0 - out * d
		var b1 := a1 - out * d
		kit.quad(MeshKit.v3(a0, hy0), MeshKit.v3(b0, hy0), MeshKit.v3(b0, hy1), MeshKit.v3(a0, hy1), t3)
		kit.quad(MeshKit.v3(a1, hy0), MeshKit.v3(b1, hy0), MeshKit.v3(b1, hy1), MeshKit.v3(a1, hy1), -t3)
		kit.quad(MeshKit.v3(a0, hy0), MeshKit.v3(a1, hy0), MeshKit.v3(b1, hy0), MeshKit.v3(b0, hy0), Vector3.UP)
		var rise := _arch_of(h)
		if rise <= 0.0:
			kit.quad(MeshKit.v3(a0, hy1), MeshKit.v3(a1, hy1), MeshKit.v3(b1, hy1), MeshKit.v3(b0, hy1), Vector3.DOWN)
			kit.color = save_c
			kit.uv2 = save_uv
			_face(kit, p0, t, o3, x0, x1, hy0, hy1, d, u_per_m)
			continue
		# Arched head: the soffit follows the curve back into the wall; the
		# wall face fills the spandrels above the curve and the glass fills
		# the arch below it.
		var top := hy1 + rise
		var pts := _arch_points(h, x0, x1, hy1)
		for k in pts.size() - 1:
			var pa: Vector2 = pts[k]
			var pb: Vector2 = pts[k + 1]
			var fa := p0 + t * pa.x
			var fb := p0 + t * pb.x
			kit.quad(MeshKit.v3(fa, pa.y), MeshKit.v3(fb, pb.y), MeshKit.v3(fb - out * d, pb.y), MeshKit.v3(fa - out * d, pa.y), Vector3.DOWN)
		kit.color = save_c
		kit.uv2 = save_uv
		_face(kit, p0, t, o3, x0, x1, hy0, hy1, d, u_per_m)
		for k in pts.size() - 1:
			var pa: Vector2 = pts[k]
			var pb: Vector2 = pts[k + 1]
			_face_quad(kit, p0, t, o3, pa.x, pb.x, hy1, hy1, pb.y, pa.y, d, u_per_m)
			_face_quad(kit, p0, t, o3, pa.x, pb.x, pa.y, pb.y, top, top, 0.0, u_per_m)
	kit.id = save_id


## How high a hole's arch rises above its spring line (0: square head).
static func _arch_of(h: Dictionary) -> float:
	return float(h.get("arch", 0.0))


## Points along a hole's arched head from x0 to x1: (metres along, height).
static func _arch_points(h: Dictionary, x0: float, x1: float, spring: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rise := _arch_of(h)
	var ac := float(h["ac"])
	var aw := float(h["aw"])
	var n := 8
	for k in n + 1:
		var x := lerpf(x0, x1, float(k) / n)
		var u := (x - ac) / aw
		out.append(Vector2(x, spring + rise * sqrt(maxf(0.0, 1.0 - u * u))))
	return out


## A four-sided piece of wall face with straight sides: from x0 to x1
## along the wall, bottom edge from ya0 to ya1 and top edge from yb1 (at x1)
## to yb0 (at x0), set back by `back`, with the UVs a whole wall would have.
func _face_quad(kit: MeshKit, p0: Vector2, t: Vector2, o3: Vector3, x0: float, x1: float, ya0: float, ya1: float, yb1: float, yb0: float, back: float, u_per_m: float) -> void:
	if x1 - x0 < 0.001:
		return
	var a := p0 + t * x0 - Vector2(o3.x, o3.z) * back
	var b := p0 + t * x1 - Vector2(o3.x, o3.z) * back
	kit.quad(MeshKit.v3(a, ya0), MeshKit.v3(b, ya1), MeshKit.v3(b, yb1), MeshKit.v3(a, yb0), o3,
		Vector2(x0 * u_per_m, ya0), Vector2(x1 * u_per_m, ya1), Vector2(x1 * u_per_m, yb1), Vector2(x0 * u_per_m, yb0))


## One flat piece of wall face from x0 to x1 along it, set back by `back`,
## with the UVs a whole wall would have there.
func _face(kit: MeshKit, p0: Vector2, t: Vector2, o3: Vector3, x0: float, x1: float, y0: float, y1: float, back: float, u_per_m: float) -> void:
	if x1 - x0 < 0.001:
		return
	var a := p0 + t * x0 - Vector2(o3.x, o3.z) * back
	var b := p0 + t * x1 - Vector2(o3.x, o3.z) * back
	kit.quad(MeshKit.v3(a, y0), MeshKit.v3(b, y0), MeshKit.v3(b, y1), MeshKit.v3(a, y1), o3,
		Vector2(x0 * u_per_m, y0), Vector2(x1 * u_per_m, y0), Vector2(x1 * u_per_m, y1), Vector2(x0 * u_per_m, y1))


## A brick chimney through the roof near `at`, from inside the house to a
## metre above the ridge, with a projecting cap and a flue pot.
func _chimney(walls: MeshKit, at: Vector2, u: Vector2, v: Vector2, eave: float, ridge: float) -> void:
	var save_c := walls.color
	var save_uv := walls.uv2
	walls.uv2 = Vector2(Style.BRICK, 0.0)
	walls.color = _vertex_color(_weathered(BRICK[int(absf(at.x * 7.0)) % BRICK.size()], 0.3, 0.85), 0.0)
	var hw := 0.38
	var hd := 0.28
	var y0 := eave - 0.5
	var y1 := ridge + 1.0
	var corners := [at + u * hw + v * hd, at - u * hw + v * hd, at - u * hw - v * hd, at + u * hw - v * hd]
	var u_at := 0.0
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var mid := (a + b) * 0.5 - at
		var side_len := a.distance_to(b)
		# Negative bays: brick, no windows.
		var ua := -100.0 + u_at / 2.0
		var ub := -100.0 + (u_at + side_len) / 2.0
		walls.quad(MeshKit.v3(a, y0), MeshKit.v3(b, y0), MeshKit.v3(b, y1), MeshKit.v3(a, y1), Vector3(mid.x, 0, mid.y).normalized(),
			Vector2(ua, y0), Vector2(ub, y0), Vector2(ub, y1), Vector2(ua, y1))
		u_at += side_len
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.42, 0.4, 0.37), 0.0)
	var cap_c := at
	_box(walls, cap_c, u, v, hw + 0.06, hd + 0.06, y1, y1 + 0.12)
	walls.color = _vertex_color(Color(0.5, 0.33, 0.25), 0.0)
	_box(walls, cap_c, u, v, 0.11, 0.11, y1 + 0.12, y1 + 0.45)
	walls.color = save_c
	walls.uv2 = save_uv


## An open front porch across the first bays of a house's street wall: a
## painted deck on a skirt, turned posts, a railing and a shingled roof.
func _porch(walls: MeshKit, roof: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, seg: float, bay_w: float, trim: Color, roof_color: Color) -> void:
	var save_c := walls.color
	var save_uv := walls.uv2
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	var t := (p1 - p0) / seg
	var bays := roundf(seg / bay_w)
	var bay_len := seg / bays
	var a := 0.2
	var b := minf(seg - 0.2, bay_len * 2.9)
	var depth := 2.1
	var deck := 0.55
	var eave := 2.75
	# Fieldstone piers and skirt under the deck (tall where the lot slopes).
	walls.uv2 = Vector2(STONE_STYLE, 0.0)
	walls.color = _vertex_color(Color(0.92, 0.9, 0.88), 0.0)
	_slab(walls, p0, t, out, a, b, _base, deck - 0.06, depth - 0.05)
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.42, 0.43, 0.42), 0.0)
	_slab(walls, p0, t, out, a - 0.03, b + 0.03, deck - 0.06, deck, depth + 0.04)
	# Steps down to the walk in the middle.
	var sm := (a + b) * 0.5
	_slab(walls, p0, t, out + Vector2.ZERO, sm - 0.6, sm + 0.6, _base, deck * 0.66, depth + 0.3)
	_slab(walls, p0, t, out, sm - 0.6, sm + 0.6, _base, deck * 0.33, depth + 0.6)
	# Posts, a top rail and a bottom rail between them (gap for the steps).
	walls.color = _vertex_color(trim, 0.0)
	var posts := [a + 0.08, sm - 0.68, sm + 0.68, b - 0.08]
	for x: float in posts:
		var c := p0 + t * x + out * (depth - 0.12)
		_box(walls, c, t, out, 0.07, 0.07, deck, eave)
	for pair: Array in [[posts[0], posts[1]], [posts[2], posts[3]]]:
		var x0: float = pair[0]
		var x1: float = pair[1]
		for y: float in [deck + 0.12, deck + 0.9]:
			var ca := p0 + t * ((x0 + x1) * 0.5) + out * (depth - 0.12)
			_box(walls, ca, t, out, (x1 - x0) * 0.5, 0.03, y, y + 0.06)
		# Balusters.
		var n := int((x1 - x0) / 0.14)
		for k in range(1, n):
			var cb := p0 + t * (x0 + k * (x1 - x0) / n) + out * (depth - 0.12)
			_box(walls, cb, t, out, 0.018, 0.018, deck + 0.18, deck + 0.9)
	# Beam along the front.
	_slab(walls, p0, t, out, a, b, eave - 0.2, eave, depth)
	# Shingled roof, sloping down from the wall.
	walls.color = save_c
	walls.uv2 = save_uv
	var r_save := roof.color
	var r_uv := roof.uv2
	roof.color = _vertex_color(roof_color, 1.0)
	roof.uv2 = Vector2(1.0, 0.0)
	var wa := p0 + t * (a - 0.1)
	var wb := p0 + t * (b + 0.1)
	var fa := wa + out * (depth + 0.3)
	var fb := wb + out * (depth + 0.3)
	var top := eave + 0.75
	var low := eave - 0.02
	var n3 := Vector3(out.x * 0.75, depth, out.y * 0.75).normalized()
	var run := depth + 0.3
	roof.quad(MeshKit.v3(wa, top), MeshKit.v3(wb, top), MeshKit.v3(fb, low), MeshKit.v3(fa, low), n3,
		Vector2(0, run), Vector2(b - a, run), Vector2(b - a, 0), Vector2(0, 0))
	roof.color = r_save
	roof.uv2 = r_uv
	walls.color = _vertex_color(trim, 0.0)
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.quad(MeshKit.v3(fa, low - 0.18), MeshKit.v3(fb, low - 0.18), MeshKit.v3(fb, low), MeshKit.v3(fa, low), Vector3(out.x, 0, out.y))
	walls.color = save_c
	walls.uv2 = save_uv


## A church wall's stonework: a deep plinth, a stepped buttress between
## every pair of windows, and a hood moulding of stones following each
## pointed head.
func _church_relief(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, seg: float, bay_w: float, floors: float, wall_color: Color, holes: Array) -> void:
	var save_c := kit.color
	var save_uv := kit.uv2
	var t := (p1 - p0) / seg
	kit.uv2 = Vector2(STONE_STYLE, 0.0)
	kit.color = _vertex_color(Color(0.9, 0.88, 0.85), 0.0)
	_slab(kit, p0, t, out, -0.1, seg + 0.1, _base, 0.9, 0.12)
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	var stone := _weathered(wall_color, 0.2, 0.92)
	kit.color = _vertex_color(stone, 0.0)
	var wall_h := floors * FLOOR_H
	var bays := roundf(seg / bay_w)
	# Buttresses between windows only (not at the corners, which on a
	# rounded apse would put one every couple of metres).
	if bays >= 2.0 and wall_h > 5.0:
		var bay_len := seg / bays
		for b in range(1, int(bays)):
			var x := b * bay_len
			# Two steps, each with a sloped weathering top.
			_slab(kit, p0, t, out, x - 0.35, x + 0.35, _base, wall_h * 0.45, 0.75)
			_slab(kit, p0, t, out, x - 0.3, x + 0.3, wall_h * 0.45, wall_h * 0.8, 0.45)
			_slab(kit, p0, t, out, x - 0.25, x + 0.25, wall_h * 0.8, wall_h * 0.88, 0.25)
	kit.color = _vertex_color(Color(0.72, 0.7, 0.65), 0.0)
	for h: Dictionary in holes:
		var pts := _arch_points(h, float(h["x0"]) - 0.12, float(h["x1"]) + 0.12, float(h["y1"]))
		for k in pts.size() - 1:
			var pa: Vector2 = pts[k]
			var pb: Vector2 = pts[k + 1]
			_slab(kit, p0, t, out, pa.x, pb.x, minf(pa.y, pb.y) + 0.05, maxf(pa.y, pb.y) + 0.2, 0.08)
		# Label stops: the moulding returns down a little each side.
		_slab(kit, p0, t, out, float(h["x0"]) - 0.2, float(h["x0"]) - 0.05, float(h["y1"]) - 0.35, float(h["y1"]) + 0.1, 0.08)
		_slab(kit, p0, t, out, float(h["x1"]) + 0.05, float(h["x1"]) + 0.2, float(h["y1"]) - 0.35, float(h["y1"]) + 0.1, 0.08)
		# A sloped stone sill.
		_slab(kit, p0, t, out, float(h["x0"]) - 0.1, float(h["x1"]) + 0.1, float(h["y0"]) - 0.14, float(h["y0"]), 0.14)
	kit.color = save_c
	kit.uv2 = save_uv


## Close-up stonework on a ribbed sandstone wall: deep fins between the
## groups of slot windows, a dark granite base and a heavy fascia band
## along the top.
func _ribbed_relief(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, seg: float, wall_h: float, wall_color: Color) -> void:
	var save_c := kit.color
	var save_uv := kit.uv2
	var t := (p1 - p0) / seg
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	kit.color = _vertex_color(Color(0.28, 0.27, 0.26), 0.0)
	_slab(kit, p0, t, out, -0.05, seg + 0.05, _base, 0.6, 0.08)
	kit.uv2 = Vector2(RIBBED_STYLE, 0.0)
	kit.color = _vertex_color(wall_color, wall_h / FLOOR_H)
	# Shader positions are in metres along the wall, stretched to whole bays.
	var bays := maxf(1.0, roundf(seg / BAY_W[Style.SANDSTONE]))
	var k := seg / (bays * BAY_W[Style.SANDSTONE])
	var x := 2.4 * k
	while x < seg - 0.5:
		var m := fmod(x / k, 14.0)
		if m < 4.3 or m > 8.5:
			_slab(kit, p0, t, out, x - 0.18, x + 0.18, 0.6, wall_h - 1.0, 0.22)
		x += 2.4 * k
	kit.color = _vertex_color(_weathered(wall_color, 0.1, 1.06), 0.0)
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	_slab(kit, p0, t, out, -0.4, seg + 0.4, wall_h - 1.0, wall_h + 0.6, 0.4)
	kit.color = save_c
	kit.uv2 = save_uv


## The Confederation Centre's massing on top of its one big OSM footprint:
## the theatre's tall fly tower, Memorial Hall standing above the rest, a
## long gallery clerestory, and a glazed lobby with a canopy on the front.
## All in ribbed sandstone. Returns collision faces for the lobby.
func _confederation(walls: MeshKit, roof: MeshKit, spec: Dictionary, p0: Vector2, p1: Vector2) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var obb: Dictionary = spec["obb"]
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var hu: float = obb["half_u"]
	var hv: float = obb["half_v"]
	var wall_h: float = spec["wall_h"]
	var wall_color := _weathered(spec["wall_color"], 0.3, 0.94)
	var save_c := walls.color
	var save_uv := walls.uv2
	var save_r := roof.color
	var save_ruv := roof.uv2
	# [centre along u, along v (fractions of the half sizes), half sizes, height]
	var blocks := [
		[0.3, 0.25, 11.0, 9.0, wall_h + 11.0],
		[-0.35, 0.2, 13.0, 10.0, wall_h + 4.5],
		[0.0, -0.45, hu * 0.55, 3.0, wall_h + 2.5],
	]
	for bl: Array in blocks:
		var bc: Vector2 = c + u * hu * float(bl[0]) + v * hv * float(bl[1])
		var a: float = bl[2]
		var b: float = bl[3]
		var h: float = bl[4]
		var ring := PackedVector2Array([bc + u * a + v * b, bc - u * a + v * b, bc - u * a - v * b, bc + u * a - v * b])
		walls.uv2 = Vector2(RIBBED_STYLE, 0.0)
		walls.color = _vertex_color(wall_color, (h - wall_h) / FLOOR_H + 0.4)
		for i in 4:
			var q0: Vector2 = ring[i]
			var q1: Vector2 = ring[(i + 1) % 4]
			var mid := (q0 + q1) * 0.5 - bc
			var n3 := Vector3(mid.x, 0, mid.y).normalized()
			# The raised blocks start at the main roof; UV heights from there.
			var seg := q0.distance_to(q1)
			var bays := maxf(1.0, roundf(seg / 2.6))
			walls.quad(MeshKit.v3(q0, wall_h - 0.3), MeshKit.v3(q1, wall_h - 0.3), MeshKit.v3(q1, h), MeshKit.v3(q0, h), n3,
				Vector2(0, -0.3), Vector2(bays, -0.3), Vector2(bays, h - wall_h), Vector2(0, h - wall_h))
			if detail:
				walls.uv2 = Vector2(Style.PLAIN, 0.0)
				walls.color = _vertex_color(_weathered(wall_color, 0.1, 1.06), 0.0)
				_slab(walls, q0, (q1 - q0) / seg, Vector2(n3.x, n3.z), -0.3, seg + 0.3, h - 0.9, h + 0.4, 0.3)
				walls.uv2 = Vector2(RIBBED_STYLE, 0.0)
				walls.color = _vertex_color(wall_color, (h - wall_h) / FLOOR_H + 0.4)
		roof.uv2 = Vector2.ZERO
		roof.color = _vertex_color(spec["roof_color"], 1.0)
		_flat_roof(roof, ring, h + (0.42 if detail else 0.02))
	# Glazed lobby on the front: a glass curtain wall standing a little
	# forward of the stone, and a thin concrete canopy over the doors.
	var seg_f := p0.distance_to(p1)
	var t := (p1 - p0) / seg_f
	var out := Vector2(t.y, -t.x)
	var w := minf(seg_f * 0.35, 28.0)
	var a0 := seg_f * 0.5 - w * 0.5
	var lobby_h := minf(wall_h - 1.5, 8.0)
	walls.uv2 = Vector2(RIBBED_STYLE, 1.0)
	walls.color = _vertex_color(wall_color, 3.0)
	var g0 := p0 + t * a0 + out * 0.8
	var g1 := p0 + t * (a0 + w) + out * 0.8
	var o3 := Vector3(out.x, 0, out.y)
	var gb := maxf(1.0, roundf(w / 2.6))
	walls.quad(MeshKit.v3(g0, _base), MeshKit.v3(g1, _base), MeshKit.v3(g1, lobby_h), MeshKit.v3(g0, lobby_h), o3,
		Vector2(0, _base), Vector2(gb, _base), Vector2(gb, lobby_h), Vector2(0, lobby_h))
	faces.append_array(_quad_faces(g0, g1, _base, lobby_h))
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.62, 0.6, 0.56), 0.0)
	_slab(walls, p0, t, out, a0 - 0.2, a0 + w + 0.2, lobby_h, lobby_h + 0.5, 1.0)
	_slab(walls, p0, t, out, a0 + w * 0.3, a0 + w * 0.7, 3.6, 3.85, 4.0)
	walls.color = save_c
	walls.uv2 = save_uv
	roof.color = save_r
	roof.uv2 = save_ruv
	return faces


## A box standing out from the wall: from `a` to `b` metres along it, `y0` to
## `y1` up, `depth` out from the face (with its back a little inside).
func _slab(kit: MeshKit, p0: Vector2, t: Vector2, out: Vector2, a: float, b: float, y0: float, y1: float, depth: float) -> void:
	var la := p0 + t * a - out * 0.01
	var lb := p0 + t * b - out * 0.01
	var fa := p0 + t * a + out * depth
	var fb := p0 + t * b + out * depth
	var o3 := Vector3(out.x, 0.0, out.y)
	var t3 := Vector3(t.x, 0.0, t.y)
	# UVs as on a wall (bays of 3.4 m, metres up) for the stone plinths.
	var ua := a / 3.4
	var ub := b / 3.4
	kit.quad(MeshKit.v3(fa, y0), MeshKit.v3(fb, y0), MeshKit.v3(fb, y1), MeshKit.v3(fa, y1), o3,
		Vector2(ua, y0), Vector2(ub, y0), Vector2(ub, y1), Vector2(ua, y1))
	kit.quad(MeshKit.v3(la, y1), MeshKit.v3(fa, y1), MeshKit.v3(fb, y1), MeshKit.v3(lb, y1), Vector3.UP)
	kit.quad(MeshKit.v3(lb, y0), MeshKit.v3(fb, y0), MeshKit.v3(fa, y0), MeshKit.v3(la, y0), Vector3.DOWN)
	kit.quad(MeshKit.v3(la, y0), MeshKit.v3(fa, y0), MeshKit.v3(fa, y1), MeshKit.v3(la, y1), -t3)
	kit.quad(MeshKit.v3(fb, y0), MeshKit.v3(lb, y0), MeshKit.v3(lb, y1), MeshKit.v3(fb, y1), t3)

## A wall with whole window bays stretched to fit its length.
func _wall(kit: MeshKit, p0: Vector2, p1: Vector2, y0: float, y1: float, n: Vector3, seg: float, bay_w: float) -> void:
	var bays := roundf(seg / bay_w)
	var u0 := 0.0
	var u1 := bays
	if seg < bay_w * 0.7 or bays < 1.0:
		u0 = -100.0 # too narrow for a window
		u1 = -100.0 + seg / bay_w
	kit.quad(MeshKit.v3(p0, y0), MeshKit.v3(p1, y0), MeshKit.v3(p1, y1), MeshKit.v3(p0, y1), n,
		Vector2(u0, y0), Vector2(u1, y0), Vector2(u1, y1), Vector2(u0, y1))


## The cornice along the top of a flat-roofed commercial block: a stepped
## profile (crown, a sloped bed moulding, frieze and fillet) so it throws a
## real shadow, with a bracket under the crown between every window bay when
## `bay_w` is given.
const CORNICE_PROFILE := [
	# [bottom below top, top below top, depth at bottom, depth at top]
	[0.12, -0.08, 0.42, 0.42], # crown
	[0.42, 0.12, 0.1, 0.3], # bed moulding, sloping out to the crown
	[0.82, 0.42, 0.07, 0.07], # frieze
	[0.92, 0.82, 0.13, 0.13], # fillet
]


func _cornice(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, top: float, trim: Color, bay_w := 0.0) -> void:
	var save_c := kit.color
	var save_uv := kit.uv2
	kit.color = _vertex_color(trim, 0.0)
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	var t := (p1 - p0).normalized()
	var o3 := Vector3(out.x, 0.0, out.y)
	for el: Array in CORNICE_PROFILE:
		var y0: float = top - float(el[0])
		var y1: float = top - float(el[1])
		var d0: float = el[2]
		var d1: float = el[3]
		# Run past the ends by the depth so neighbouring walls meet at corners.
		var a0 := p0 - t * d0 + out * d0
		var b0 := p1 + t * d0 + out * d0
		var a1 := p0 - t * d1 + out * d1
		var b1 := p1 + t * d1 + out * d1
		var n := (o3 * (y1 - y0) + Vector3.UP * (d1 - d0)).normalized()
		kit.quad(MeshKit.v3(a0, y0), MeshKit.v3(b0, y0), MeshKit.v3(b1, y1), MeshKit.v3(a1, y1), n)
		# Underside, back to the wall.
		kit.quad(MeshKit.v3(p0, y0), MeshKit.v3(p1, y0), MeshKit.v3(b0, y0), MeshKit.v3(a0, y0), Vector3.DOWN)
		# Ends, so the profile reads at a corner or where the block stops.
		for e: Array in [[p0, a0, a1, -t], [p1, b0, b1, t]]:
			var w: Vector2 = e[0]
			var n_end := Vector3(e[3].x, 0.0, e[3].y)
			kit.quad(MeshKit.v3(w, y0), MeshKit.v3(e[1], y0), MeshKit.v3(e[2], y1), MeshKit.v3(w, y1), n_end)
	# Top of the crown.
	var top_y := top + 0.08
	var ca := p0 - t * 0.42 + out * 0.42
	var cb := p1 + t * 0.42 + out * 0.42
	kit.quad(MeshKit.v3(p0, top_y), MeshKit.v3(p1, top_y), MeshKit.v3(cb, top_y), MeshKit.v3(ca, top_y), Vector3.UP)
	# Brackets between the bays, tucked under the crown.
	var seg := p0.distance_to(p1)
	if bay_w > 0.0 and seg > bay_w:
		var bays := maxf(1.0, roundf(seg / bay_w))
		var step := seg / bays
		for k in range(int(bays) + 1):
			var along := clampf(k * step, 0.2, seg - 0.2)
			var c := p0 + t * along
			_bracket(kit, c, t, out, top - 0.12, 0.5)
	kit.color = save_c
	kit.uv2 = save_uv


## A small tapered bracket under a cornice: deep at the top, shallow below.
func _bracket(kit: MeshKit, c: Vector2, t: Vector2, out: Vector2, y_top: float, h: float) -> void:
	var hw := 0.07
	var y_bot := y_top - h
	var o3 := Vector3(out.x, 0.0, out.y)
	var l0 := c - t * hw
	var r0 := c + t * hw
	var lt := l0 + out * 0.4
	var rt := r0 + out * 0.4
	var lb := l0 + out * 0.08
	var rb := r0 + out * 0.08
	var front_n := (o3 * h + Vector3.UP * 0.32).normalized()
	kit.quad(MeshKit.v3(lb, y_bot), MeshKit.v3(rb, y_bot), MeshKit.v3(rt, y_top), MeshKit.v3(lt, y_top), front_n)
	var tn := Vector3(t.x, 0.0, t.y)
	kit.quad(MeshKit.v3(r0, y_bot), MeshKit.v3(rb, y_bot), MeshKit.v3(rt, y_top), MeshKit.v3(r0, y_top), tn)
	kit.quad(MeshKit.v3(l0, y_bot), MeshKit.v3(lb, y_bot), MeshKit.v3(lt, y_top), MeshKit.v3(l0, y_top), -tn)
	kit.quad(MeshKit.v3(l0, y_bot), MeshKit.v3(r0, y_bot), MeshKit.v3(rb, y_bot), MeshKit.v3(lb, y_bot), Vector3.DOWN)


## A stone coping along the top of a parapet that has no cornice, so the
## wall has some thickness against the sky.
func _coping(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, top: float) -> void:
	var save_c := kit.color
	var save_uv := kit.uv2
	kit.color = _vertex_color(Color(0.6, 0.58, 0.54), 0.0)
	kit.uv2 = Vector2(Style.PLAIN, 0.0)
	var t := (p1 - p0).normalized()
	var a_out := p0 + out * 0.05 - t * 0.05
	var b_out := p1 + out * 0.05 + t * 0.05
	var a_in := p0 - out * 0.3
	var b_in := p1 - out * 0.3
	var o3 := Vector3(out.x, 0.0, out.y)
	kit.quad(MeshKit.v3(a_out, top), MeshKit.v3(b_out, top), MeshKit.v3(b_out, top + 0.08), MeshKit.v3(a_out, top + 0.08), o3)
	kit.quad(MeshKit.v3(a_in, top + 0.08), MeshKit.v3(b_in, top + 0.08), MeshKit.v3(b_out, top + 0.08), MeshKit.v3(a_out, top + 0.08), Vector3.UP)
	kit.quad(MeshKit.v3(a_in, top), MeshKit.v3(b_in, top), MeshKit.v3(b_in, top + 0.08), MeshKit.v3(a_in, top + 0.08), -o3)
	kit.color = save_c
	kit.uv2 = save_uv


## True when the wall looks onto a street across a sidewalk.
func _faces_street(p0: Vector2, p1: Vector2, out: Vector2) -> bool:
	var mid := (p0 + p1) * 0.5
	var hit := net.nearest_on_streets(mid + out * 3.0, 14.0)
	if hit.is_empty():
		return false
	var to_street: Vector2 = (hit["pos"] as Vector2) - mid
	return to_street.normalized().dot(out) > 0.75


## Canvas awnings over each shop bay of a street-facing wall.
func _awnings(kit: MeshKit, p0: Vector2, p1: Vector2, out: Vector2, seg: float, bay_w: float, ground_floor: float, c: Color, striped: bool) -> void:
	var save_c := kit.color
	var save_uv := kit.uv2
	kit.color = _vertex_color(c, 0.0)
	kit.uv2 = Vector2(2.0 if striped else 3.0, 0.0)
	var t := (p1 - p0) / seg
	var bays := maxf(1.0, roundf(seg / bay_w))
	var bay_len := seg / bays
	var y_top := ground_floor - 0.75
	var y_low := y_top - 0.75
	var depth := 1.3
	for k in int(bays):
		var a := p0 + t * (k * bay_len + 0.08)
		var b := p0 + t * ((k + 1) * bay_len - 0.08)
		var fa := a + out * depth
		var fb := b + out * depth
		var slope := Vector3(out.x * 0.75, depth, out.y * 0.75).normalized()
		kit.quad(MeshKit.v3(a, y_top), MeshKit.v3(b, y_top), MeshKit.v3(fb, y_low), MeshKit.v3(fa, y_low), slope,
			Vector2(0, 0), Vector2(bay_len, 0), Vector2(bay_len, 1.5), Vector2(0, 1.5))
		# Valance hanging from the front edge.
		kit.quad(MeshKit.v3(fa, y_low), MeshKit.v3(fb, y_low), MeshKit.v3(fb, y_low - 0.25), MeshKit.v3(fa, y_low - 0.25),
			Vector3(out.x, 0.0, out.y), Vector2(0, 0), Vector2(bay_len, 0), Vector2(bay_len, 0.25), Vector2(0, 0.25))
	kit.color = save_c
	kit.uv2 = save_uv


static func _quad_faces(p0: Vector2, p1: Vector2, y0: float, y1: float) -> PackedVector3Array:
	var a := MeshKit.v3(p0, y0)
	var b := MeshKit.v3(p1, y0)
	var c := MeshKit.v3(p1, y1)
	var d := MeshKit.v3(p0, y1)
	return PackedVector3Array([a, b, c, a, c, d])


# --- roofs -------------------------------------------------------------------------------------

func _flat_roof(kit: MeshKit, ring: PackedVector2Array, h: float) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty():
		var hull := Geometry2D.convex_hull(ring)
		for i in range(1, hull.size() - 2):
			kit.ground_tri(MeshKit.v3(hull[0], h), MeshKit.v3(hull[i], h), MeshKit.v3(hull[i + 1], h))
		return
	for i in range(0, idx.size(), 3):
		kit.ground_tri(MeshKit.v3(ring[idx[i]], h), MeshKit.v3(ring[idx[i + 1]], h), MeshKit.v3(ring[idx[i + 2]], h))


## Gable roof over the footprint's oriented bounding box, ridge along the long side.
func _gable_roof(walls: MeshKit, roof: MeshKit, spec: Dictionary, _rng: RandomNumberGenerator) -> void:
	var obb: Dictionary = spec["obb"]
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var hu: float = obb["half_u"]
	var hv: float = obb["half_v"]
	var eave: float = spec["wall_h"]
	var slope := tan(deg_to_rad(float(spec["pitch"])))
	var ridge := eave + hv * slope
	var low := eave - OVERHANG * slope
	roof.uv2 = Vector2(1.0, 0.0)
	var run := (hv + OVERHANG) * sqrt(1.0 + slope * slope)
	if detail and spec.has("chimneys"):
		# A landmark's own count: in pairs either side of the ridge, spread
		# along it (an odd one goes in the middle).
		var n_ch: int = spec["chimneys"]
		for k in n_ch:
			var pair := k / 2
			var pairs := maxi(1, (n_ch + 1) / 2)
			var along := 0.0 if pairs == 1 else hu * lerpf(-0.6, 0.6, float(pair) / float(pairs - 1))
			var side := 0.3 * hv * (1.0 if k % 2 == 0 else -1.0)
			if n_ch % 2 == 1 and k == n_ch - 1:
				side = 0.0
			_chimney(walls, c + u * along + v * side, u, v, eave, ridge)
	elif detail and spec["style"] != Style.CHURCH and _rng.randf() < 0.75:
		var along := hu * _rng.randf_range(0.35, 0.7) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_chimney(walls, c + u * along + v * _rng.randf_range(-0.3, 0.3) * hv, u, v, eave, ridge)
	if spec.get("hip", false):
		_hip_roof(walls, roof, spec, c, u, v, hu, hv, low, ridge, run)
		return
	for s: float in [1.0, -1.0]:
		var a := MeshKit.v3(c + u * (hu + OVERHANG) + v * (hv + OVERHANG) * s, low)
		var b := MeshKit.v3(c - u * (hu + OVERHANG) + v * (hv + OVERHANG) * s, low)
		var top_b := MeshKit.v3(c - u * (hu + OVERHANG), ridge)
		var top_a := MeshKit.v3(c + u * (hu + OVERHANG), ridge)
		var n := (b - a).cross(top_a - a).normalized()
		if n.y < 0.0:
			n = -n
		roof.quad(a, b, top_b, top_a, n, Vector2(0, 0), Vector2(hu * 2.0, 0), Vector2(hu * 2.0, run), Vector2(0, run))
	# Trim boards: a fascia along each eave and a barge board up each rake,
	# so the roof has an edge instead of a paper-thin plane.
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(_trim_srgb(spec["trim"]), 0.0)
	var board := 0.2
	for s: float in [1.0, -1.0]:
		var e0 := c + u * (hu + OVERHANG) + v * (hv + OVERHANG) * s
		var e1 := c - u * (hu + OVERHANG) + v * (hv + OVERHANG) * s
		var vn := Vector3(v.x * s, 0.0, v.y * s)
		walls.quad(MeshKit.v3(e0, low - board), MeshKit.v3(e1, low - board), MeshKit.v3(e1, low + 0.02), MeshKit.v3(e0, low + 0.02), vn)
		walls.quad(MeshKit.v3(e0, low - board), MeshKit.v3(e1, low - board), MeshKit.v3(e1 - v * s * 0.3, low - board), MeshKit.v3(e0 - v * s * 0.3, low - board), Vector3.DOWN)
		for r: float in [1.0, -1.0]:
			var end_c := c + u * (hu + OVERHANG) * r
			var un := Vector3(u.x * r, 0.0, u.y * r)
			var eave_p := end_c + v * (hv + OVERHANG) * s
			walls.quad(MeshKit.v3(eave_p, low - board), MeshKit.v3(end_c, ridge - board), MeshKit.v3(end_c, ridge + 0.02), MeshKit.v3(eave_p, low + 0.02), un)
	walls.color = save_c
	walls.uv2 = save_uv
	# Gable ends: triangles of wall up to the ridge, no windows.
	var save := walls.color
	walls.color = Color(save.r, save.g, save.b, 0.0)
	for s: float in [1.0, -1.0]:
		var end_c: Vector2 = c + u * hu * s
		var p_l := MeshKit.v3(end_c + v * hv, eave)
		var p_r := MeshKit.v3(end_c - v * hv, eave)
		var p_t := MeshKit.v3(end_c, ridge)
		var n := Vector3(u.x * s, 0.0, u.y * s)
		walls.tri(p_l, p_r, p_t, n, Vector2(-100.0, eave), Vector2(-99.0, eave), Vector2(-99.5, ridge))
	walls.color = save


## A hipped roof: sloping on all four sides up to a short ridge (or a point
## on a square house), with a fascia board round every eave.
func _hip_roof(walls: MeshKit, roof: MeshKit, spec: Dictionary, c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float, low: float, ridge: float, run: float) -> void:
	var half_ridge := maxf(hu - hv, 0.0)
	var eu := hu + OVERHANG
	var ev := hv + OVERHANG
	var ra := MeshKit.v3(c + u * half_ridge, ridge)
	var rb := MeshKit.v3(c - u * half_ridge, ridge)
	for s: float in [1.0, -1.0]:
		var a := MeshKit.v3(c + u * eu + v * ev * s, low)
		var b := MeshKit.v3(c - u * eu + v * ev * s, low)
		var n := (b - a).cross(ra - a).normalized()
		if n.y < 0.0:
			n = -n
		roof.quad(a, b, rb, ra, n, Vector2(0, 0), Vector2(eu * 2.0, 0), Vector2(eu + half_ridge, run), Vector2(eu - half_ridge, run))
		var end_l := MeshKit.v3(c + u * eu * s + v * ev, low)
		var end_r := MeshKit.v3(c + u * eu * s - v * ev, low)
		var apex := ra if s > 0.0 else rb
		var n2 := (end_r - end_l).cross(apex - end_l).normalized()
		if n2.y < 0.0:
			n2 = -n2
		roof.tri(end_l, end_r, apex, n2, Vector2(0, 0), Vector2(ev * 2.0, 0), Vector2(ev, run))
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(_trim_srgb(spec["trim"]), 0.0)
	var corners := [c + u * eu + v * ev, c - u * eu + v * ev, c - u * eu - v * ev, c + u * eu - v * ev]
	for k in 4:
		var e0: Vector2 = corners[k]
		var e1: Vector2 = corners[(k + 1) % 4]
		var mid := (e0 + e1) * 0.5 - c
		var out := Vector3(mid.x, 0.0, mid.y).normalized()
		walls.quad(MeshKit.v3(e0, low - 0.2), MeshKit.v3(e1, low - 0.2), MeshKit.v3(e1, low + 0.02), MeshKit.v3(e0, low + 0.02), out)
	walls.color = save_c
	walls.uv2 = save_uv


## A name board over the middle of the front wall, `h` metres tall with its
## foot at height `y`: a coloured panel in the wall mesh, and the text as a Label3D (returned
## as {text, pos, yaw, pixel} for build_chunk to add).
func _name_board(walls: MeshKit, text: String, p0: Vector2, p1: Vector2, y: float, h: float, board: Color) -> Dictionary:
	var t := (p1 - p0).normalized()
	var out := Vector2(t.y, -t.x)
	var mid := (p0 + p1) * 0.5
	var front_len := p0.distance_to(p1)
	var width := minf(front_len * 0.8, maxf(4.0, text.length() * h * 0.56))
	var a := mid - t * width * 0.5 + out * 0.06
	var b := mid + t * width * 0.5 + out * 0.06
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(board, 0.0)
	var n3 := Vector3(out.x, 0.0, out.y)
	walls.quad(MeshKit.v3(a, y), MeshKit.v3(b, y), MeshKit.v3(b, y + h), MeshKit.v3(a, y + h), n3)
	walls.uv2 = save_uv
	walls.color = save_c
	# Letters sized to fill most of the board.
	var pixel := clampf(width * 0.85 / maxf(1.0, text.length() * 64.0 * 0.55), 0.004, 0.012)
	return {"text": text, "pos": MeshKit.v3(mid + out * 0.09, y + h * 0.5), "yaw": StreetProps.yaw_facing(out), "pixel": pixel}


## A big store's entrance, under its sign: a glass vestibule standing out
## from the front wall with a band of the brand's colour across its top, and
## a dark base along the whole front. Returns collision faces.
func _storefront(walls: MeshKit, roof: MeshKit, p0: Vector2, p1: Vector2, lm: Dictionary, spec: Dictionary, wall_h: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var t := (p1 - p0).normalized()
	var out := Vector2(t.y, -t.x)
	var o3 := Vector3(out.x, 0.0, out.y)
	var front_len := p0.distance_to(p1)
	var brand := Color.from_string(str(lm.get("sign_colour", "#333333")), Color(0.2, 0.2, 0.2))
	var save_uv := walls.uv2
	var save_c := walls.color
	# Dark base along the front.
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.22, 0.22, 0.23), 0.0)
	var a := p0 + out * 0.04
	var b := p1 + out * 0.04
	walls.quad(MeshKit.v3(a, _base), MeshKit.v3(b, _base), MeshKit.v3(b, 1.0), MeshKit.v3(a, 1.0), o3)
	# A stripe of the brand's colour along the top of the front.
	walls.color = _vertex_color(brand, 0.0)
	walls.quad(MeshKit.v3(a, wall_h - 0.5), MeshKit.v3(b, wall_h - 0.5), MeshKit.v3(b, wall_h + 0.5), MeshKit.v3(a, wall_h + 0.5), o3)
	# The vestibule: glass shopfront walls (the wall shader draws the glazing
	# and doors on a shop's ground floor), flat roof, brand band on top.
	var w := clampf(front_len * 0.28, 6.0, 16.0)
	var depth := 3.0
	var h := minf(4.8, wall_h - 0.5)
	var mid := (p0 + p1) * 0.5
	var c0 := mid - t * w * 0.5
	var c1 := mid + t * w * 0.5
	var c2 := c1 + out * depth
	var c3 := c0 + out * depth
	walls.uv2 = Vector2(Style.PAINTED, 1.0 + 0.1 * float(spec["trim"]))
	walls.color = _vertex_color(Color(0.85, 0.85, 0.83), 1.0)
	var band := 0.9
	for side: Array in [[c3, c2, o3, w], [c0, c3, -Vector3(t.x, 0.0, t.y), depth], [c2, c1, Vector3(t.x, 0.0, t.y), depth]]:
		var q0: Vector2 = side[0]
		var q1: Vector2 = side[1]
		_wall(walls, q0, q1, _base, h - band, side[2], float(side[3]), BAY_W[Style.PAINTED])
		faces.append_array(_quad_faces(q0, q1, _base, h))
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(brand, 0.0)
	for side: Array in [[c3, c2, o3], [c0, c3, -Vector3(t.x, 0.0, t.y)], [c2, c1, Vector3(t.x, 0.0, t.y)]]:
		walls.wall(side[0], side[1], h - band, h, side[2])
	walls.uv2 = save_uv
	walls.color = save_c
	roof.uv2 = Vector2.ZERO
	_flat_roof(roof, PackedVector2Array([c0, c1, c2, c3]), h + 0.02)
	return faces


## A car dealer's front, the way the makes have them built now: a tall glass
## showroom standing out from the plain service building, a portal in the
## brand's colour with the make's name over the showroom door, service bay
## doors down the
## rest of the front, and the make's sign on a tall pylon out by the road.
## The lot gets its cars for sale from StreetProps (see `dealers`).
## Returns collision faces.
func _showroom(walls: MeshKit, roof: MeshKit, ring: PackedVector2Array, p0: Vector2, p1: Vector2, lm: Dictionary, spec: Dictionary, wall_h: float, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var t := (p1 - p0).normalized()
	var out := Vector2(t.y, -t.x)
	var o3 := Vector3(out.x, 0.0, out.y)
	var t3 := Vector3(t.x, 0.0, t.y)
	var front_len := p0.distance_to(p1)
	var brand := Color.from_string(str(lm.get("sign_colour", "#1f3f7a")), Color(0.12, 0.25, 0.48))
	var letters := Color.from_string(str(lm.get("sign_text", "#ffffff")), Color.WHITE)
	var silver := Color(0.78, 0.79, 0.8)
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	# The showroom box, toward one end of the front so the service doors
	# get the rest.
	var w := clampf(front_len * 0.5, 9.0, 30.0)
	var depth := 6.0
	var h := clampf(wall_h + 1.2, 5.5, 8.0)
	var shift := clampf((front_len - w) * 0.5 - 1.0, 0.0, front_len * 0.18)
	var mid := (p0 + p1) * 0.5 - t * shift
	var c0 := mid - t * w * 0.5
	var c1 := mid + t * w * 0.5
	var c2 := c1 + out * depth
	var c3 := c0 + out * depth
	var sides := [[c3, c2, o3], [c0, c3, -t3], [c2, c1, t3]]
	var glass := Color(0.3, 0.39, 0.44)
	var fascia := 1.1
	for sd: Array in sides:
		var q0: Vector2 = sd[0]
		var q1: Vector2 = sd[1]
		var n3: Vector3 = sd[2]
		var seg_l := q0.distance_to(q1)
		var dir := (q1 - q0) / seg_l
		var n2 := Vector2(n3.x, n3.z)
		walls.color = _vertex_color(Color(0.2, 0.2, 0.21), 0.0)
		walls.wall(q0, q1, _base, 0.35, n3)
		walls.color = _vertex_color(glass, 0.0)
		walls.wall(q0, q1, 0.35, h - fascia, n3)
		walls.color = _vertex_color(Color(0.93, 0.93, 0.92), 0.0)
		walls.wall(q0, q1, h - fascia, h, n3)
		faces.append_array(_quad_faces(q0, q1, _base, h))
		# Silver mullions every 2 m and a transom over the doors.
		walls.color = _vertex_color(silver, 0.0)
		var cols := maxi(1, int(round(seg_l / 2.0)))
		for k in range(cols + 1):
			var m := q0 + dir * seg_l * float(k) / float(cols) + n2 * 0.03
			walls.quad(MeshKit.v3(m - dir * 0.06, 0.35), MeshKit.v3(m + dir * 0.06, 0.35), MeshKit.v3(m + dir * 0.06, h - fascia), MeshKit.v3(m - dir * 0.06, h - fascia), n3)
		var a := q0 + n2 * 0.03
		var b := q1 + n2 * 0.03
		walls.quad(MeshKit.v3(a, 2.7), MeshKit.v3(b, 2.7), MeshKit.v3(b, 2.82), MeshKit.v3(a, 2.82), n3)
	roof.uv2 = Vector2.ZERO
	_flat_roof(roof, PackedVector2Array([c0, c1, c2, c3]), h + 0.02)
	# The portal: the make's colour framing the showroom door, standing
	# taller than the showroom with the make's name across the top.
	var pw := 5.6
	var pc := c3 + t * minf(pw * 0.5 + 1.5, w * 0.5) + out * 0.35
	var top := h + 2.2
	walls.color = _vertex_color(brand, 0.0)
	for sg: float in [-1.0, 1.0]:
		faces.append_array(_box(walls, pc + t * sg * (pw * 0.5 - 0.35), t, out, 0.35, 0.7, 0.0, top))
	faces.append_array(_box(walls, pc, t, out, pw * 0.5, 0.7, h - 1.0, top))
	var text := str(lm.get("sign", ""))
	if text != "" and not lod:
		signs.append({"text": text, "pos": MeshKit.v3(pc + out * 0.73, (h - 1.0 + top) * 0.5), "yaw": StreetProps.yaw_facing(out),
			"pixel": clampf((pw - 1.0) / maxf(1.0, text.length() * 64.0 * 0.55), 0.004, 0.016), "colour": letters})
	# Service bay doors down the rest of the front, under a SERVICE board.
	var left := (p0 + p1) * 0.5 + t * front_len * 0.5 # p1's end
	var from := c1 + t * 2.0
	var room := from.distance_to(left) - 1.5
	var doors := mini(4, int(floor(room / 4.6)))
	if doors > 0:
		var door_h := minf(3.9, wall_h - 1.0)
		for k in doors:
			var dc := from + t * (2.0 + 4.6 * float(k)) + out * 0.06
			walls.color = _vertex_color(Color(0.62, 0.64, 0.66), 0.0)
			walls.quad(MeshKit.v3(dc - t * 1.8, 0.0), MeshKit.v3(dc + t * 1.8, 0.0), MeshKit.v3(dc + t * 1.8, door_h), MeshKit.v3(dc - t * 1.8, door_h), o3)
			walls.color = _vertex_color(Color(0.48, 0.5, 0.52), 0.0)
			var y := 0.5
			while y < door_h - 0.2:
				var q := dc + out * 0.02
				walls.quad(MeshKit.v3(q - t * 1.8, y), MeshKit.v3(q + t * 1.8, y), MeshKit.v3(q + t * 1.8, y + 0.05), MeshKit.v3(q - t * 1.8, y + 0.05), o3)
				y += 0.55
		var span_a := from + t * 0.2
		var span_b := from + t * (4.6 * float(doors) - 0.2)
		var board := _name_board(walls, "SERVICE", span_a, span_b, door_h + 0.35, 0.75, brand)
		board["colour"] = letters
		if not lod:
			signs.append(board)
	# A brand band along the top of the rest of the front.
	walls.color = _vertex_color(brand, 0.0)
	var ba := p0 + out * 0.04
	var bb := p1 + out * 0.04
	walls.quad(MeshKit.v3(ba, wall_h - 0.45), MeshKit.v3(bb, wall_h - 0.45), MeshKit.v3(bb, wall_h + 0.15), MeshKit.v3(ba, wall_h + 0.15), o3)
	# The pylon out by the road.
	var pylon: Dictionary = lm.get("pylon", {})
	if not pylon.is_empty():
		var obb: Dictionary = spec["obb"]
		faces.append_array(_price_pylon(walls, lm, pylon, (c3 + c2) * 0.5, obb["half_u"], obb["half_v"], obb["u"], obb["v"], signs))
	walls.uv2 = save_uv
	walls.color = save_c
	dealers.append({"ring": ring, "showroom": PackedVector2Array([c0, c1, c2, c3]), "front": [p0, p1],
		"stock": lm.get("stock", ["civique", "halfton", "pony_gt"]), "used": lm.get("used_lot", {})})
	return faces


## A mansard: a skirt of shingles sloping up from a low eave all round the
## building to a flat top, the way the big 1970s and 80s plazas and
## supermarkets were roofed. The skirt follows the footprint with its small
## jogs smoothed out; its lower edge stands spec.overhang out from the walls
## with a soffit under it. Falls back to the plain flat roof already built if
## the footprint is too ragged for an even skirt.
func _mansard_roof(walls: MeshKit, roof: MeshKit, ring: PackedVector2Array, spec: Dictionary) -> void:
	var slope := tan(deg_to_rad(float(spec["pitch"])))
	var eave: float = spec["eave"]
	var overhang: float = spec["overhang"]
	var top: float = spec["roof_top"]
	var run_in := (top - eave) / slope - overhang
	# Smooth out jogs first; if a wing is too narrow for the skirt to slope
	# up from both its sides, smooth harder so it stands as a flat-roofed
	# annex under the main roof (a loading bay out the back, say).
	var simple := PackedVector2Array()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for tol: float in [5.0, 10.0, 20.0]:
		simple = _simplify_ring(ring, tol)
		outer = _offset_ring(simple, overhang)
		inner = _offset_ring(simple, -run_in)
		if not outer.is_empty() and not inner.is_empty():
			break
	if outer.is_empty() or inner.is_empty():
		return
	var n := simple.size()
	var run := (overhang + run_in) * sqrt(1.0 + slope * slope)
	roof.uv2 = Vector2(1.0, 0.0)
	for i in n:
		var j := (i + 1) % n
		var a := MeshKit.v3(outer[i], eave)
		var b := MeshKit.v3(outer[j], eave)
		var c := MeshKit.v3(inner[j], top)
		var d := MeshKit.v3(inner[i], top)
		var nrm := (b - a).cross(d - a).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var len_o := outer[i].distance_to(outer[j])
		var len_i := inner[i].distance_to(inner[j])
		var shift := (len_o - len_i) * 0.5
		roof.quad(a, b, c, d, nrm, Vector2(0, 0), Vector2(len_o, 0), Vector2(shift + len_i, run), Vector2(shift, run))
	roof.uv2 = Vector2.ZERO
	_flat_roof(roof, inner, top)
	# Fascia along the eave and a soffit back to the walls.
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	for i in n:
		var j := (i + 1) % n
		var t := (outer[j] - outer[i]).normalized()
		var o3 := Vector3(t.y, 0.0, -t.x)
		walls.color = _vertex_color(_trim_srgb(spec["trim"]), 0.0)
		walls.quad(MeshKit.v3(outer[i], eave - 0.35), MeshKit.v3(outer[j], eave - 0.35), MeshKit.v3(outer[j], eave + 0.02), MeshKit.v3(outer[i], eave + 0.02), o3)
		walls.color = _vertex_color(Color(0.78, 0.76, 0.72), 0.0)
		walls.quad(MeshKit.v3(simple[i], eave - 0.35), MeshKit.v3(simple[j], eave - 0.35), MeshKit.v3(outer[j], eave - 0.35), MeshKit.v3(outer[i], eave - 0.35), Vector3.DOWN)
	walls.uv2 = save_uv
	walls.color = save_c


## Douglas-Peucker on a closed ring: drops jogs smaller than `tol` metres
## (a door bay, a downpipe chase) and keeps the corners that shape it.
static func _simplify_ring(ring: PackedVector2Array, tol: float) -> PackedVector2Array:
	var n := ring.size()
	if n <= 4:
		return ring
	# Split at the two points furthest apart and simplify each half.
	var a := 0
	var b := 0
	var best := -1.0
	for i in n:
		var d := ring[0].distance_squared_to(ring[i])
		if d > best:
			best = d
			a = i
	best = -1.0
	for i in n:
		var d := ring[a].distance_squared_to(ring[i])
		if d > best:
			best = d
			b = i
	var keep := {}
	keep[a] = true
	keep[b] = true
	_dp(ring, a, b, tol, keep)
	_dp(ring, b, a, tol, keep)
	var out := PackedVector2Array()
	for i in n:
		if keep.has(i):
			out.append(ring[i])
	return out if out.size() >= 3 else ring


static func _dp(ring: PackedVector2Array, i0: int, i1: int, tol: float, keep: Dictionary) -> void:
	var n := ring.size()
	var count := (i1 - i0 + n) % n
	if count < 2:
		return
	var worst := -1.0
	var worst_i := -1
	for k in range(1, count):
		var i := (i0 + k) % n
		var q := Geometry2D.get_closest_point_to_segment(ring[i], ring[i0], ring[i1])
		var d := ring[i].distance_to(q)
		if d > worst:
			worst = d
			worst_i = i
	if worst > tol:
		keep[worst_i] = true
		_dp(ring, i0, worst_i, tol, keep)
		_dp(ring, worst_i, i1, tol, keep)


## The ring moved `d` metres outward (negative: inward) with mitred corners,
## vertex for vertex. Empty when that turns an edge round or folds the ring
## over itself (an inset deeper than a wing is wide).
static func _offset_ring(ring: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := ring.size()
	var out := PackedVector2Array()
	for i in n:
		var p0 := ring[(i - 1 + n) % n]
		var p1 := ring[i]
		var p2 := ring[(i + 1) % n]
		var t0 := (p1 - p0).normalized()
		var t1 := (p2 - p1).normalized()
		var n0 := Vector2(t0.y, -t0.x)
		var n1 := Vector2(t1.y, -t1.x)
		var den := 1.0 + n0.dot(n1)
		if den < 0.3:
			return PackedVector2Array() # a corner too sharp to mitre
		out.append(p1 + (n0 + n1) / den * d)
	for i in n:
		var j := (i + 1) % n
		var e0 := ring[j] - ring[i]
		var e1 := out[j] - out[i]
		if e1.dot(e0) <= 0.0 or e1.length() < 0.5:
			return PackedVector2Array()
	if _signed_area(out) <= 0.0 or Geometry2D.triangulate_polygon(out).is_empty():
		return PackedVector2Array()
	return out


## A quick oil change built the way Pro Oil Change built theirs: a low,
## flat-roofed box with drive-through service bays (an overhead door at each
## end of every bay, down both long sides) and, standing out of one end, a
## round tower about 6 m tall like a giant oil drum, which is the way in
## and carries the name. The drum stands where the footprint has a round
## part (OSM maps its curve); without one it goes on the front's right-hand
## corner. Landmark keys: "barrel" {height, radius} and "bay_doors" (bays per
## side). Returns collision faces.
func _quick_lube(walls: MeshKit, roof: MeshKit, ring: PackedVector2Array, p0: Vector2, p1: Vector2, lm: Dictionary, spec: Dictionary, wall_h: float, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var brand := Color.from_string(str(lm.get("sign_colour", "#c8102e")), Color(0.78, 0.06, 0.18))
	var letters := Color.from_string(str(lm.get("sign_text", "#ffffff")), Color.WHITE)
	var opts: Dictionary = lm.get("barrel", {}) if lm.get("barrel", {}) is Dictionary else {}
	var ft := (p1 - p0).normalized()
	var fout := Vector2(ft.y, -ft.x)
	var save_uv := walls.uv2
	var save_c := walls.color
	walls.uv2 = Vector2(Style.PLAIN, 0.0)

	var round_part := _round_part(ring)
	var bc: Vector2
	var r: float
	if round_part.is_empty():
		r = float(opts.get("radius", 1.9))
		bc = p1 - ft * r * 0.6 + fout * r * 0.4
	else:
		bc = round_part[0]
		r = float(opts.get("radius", round_part[1]))
	var r_draw := r + 0.08
	var barrel_h := maxf(float(opts.get("height", 6.1)), wall_h + 1.0)

	# A band of the brand's colour round the top of every straight wall, and
	# the bay doors and office glass down the long ones.
	var obb: Dictionary = spec["obb"]
	var long_axis: Vector2 = obb["u"] if float(obb["half_u"]) >= float(obb["half_v"]) else obb["v"]
	var top := wall_h + 0.5
	var want := int(lm.get("bay_doors", 3))
	var door_h := minf(3.7, wall_h - 0.75)
	var front_run: Array = []
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var seg := a.distance_to(b)
		if seg < 1.5:
			continue
		var t := (b - a) / seg
		var out := Vector2(t.y, -t.x)
		var o3 := Vector3(out.x, 0.0, out.y)
		var ea := a + out * 0.05
		var eb := b + out * 0.05
		walls.color = _vertex_color(brand, 0.0)
		walls.quad(MeshKit.v3(ea, wall_h - 0.55), MeshKit.v3(eb, wall_h - 0.55), MeshKit.v3(eb, top), MeshKit.v3(ea, top), o3)
		if seg < 8.0 or absf(t.dot(long_axis)) < 0.9:
			continue
		# The bays take the wall from its far end up to the office by the drum.
		var s0 := 0.8
		var s1 := seg - 0.8
		var sb := (bc - a).dot(t)
		var office := [0.0, 0.0]
		if sb > seg * 0.5:
			s1 = minf(s1, sb - r - 2.6)
			office = [s1 + 0.7, minf(seg, sb - r) - 0.3]
		else:
			s0 = maxf(s0, sb + r + 2.6)
			office = [maxf(0.0, sb + r) + 0.3, s0 - 0.7]
		var n := mini(want, int(floor((s1 - s0 + 0.4) / 3.9)))
		if n > 0:
			var pitch := (s1 - s0) / float(n)
			var half := minf(3.3, pitch - 0.5) * 0.5
			for k in n:
				var dc := a + t * (s0 + pitch * (float(k) + 0.5)) + out * 0.06
				# A white frame, then a full-view door: rows of glass panes.
				walls.color = _vertex_color(Color(0.9, 0.9, 0.88), 0.0)
				walls.quad(MeshKit.v3(dc - t * (half + 0.18), 0.0), MeshKit.v3(dc + t * (half + 0.18), 0.0), MeshKit.v3(dc + t * (half + 0.18), door_h + 0.18), MeshKit.v3(dc - t * (half + 0.18), door_h + 0.18), o3)
				var q := dc + out * 0.02
				walls.color = _vertex_color(Color(0.74, 0.76, 0.78), 0.0)
				walls.quad(MeshKit.v3(q - t * half, 0.0), MeshKit.v3(q + t * half, 0.0), MeshKit.v3(q + t * half, door_h), MeshKit.v3(q - t * half, door_h), o3)
				walls.color = _vertex_color(Color(0.2, 0.25, 0.29), 0.0)
				var y := 0.75
				while y + 0.5 < door_h:
					for col in 4:
						var x0 := -half + 0.1 + (2.0 * half - 0.1) * float(col) / 4.0
						var x1 := x0 + (2.0 * half - 0.1) / 4.0 - 0.1
						var g := q + out * 0.02
						walls.quad(MeshKit.v3(g + t * x0, y), MeshKit.v3(g + t * x1, y), MeshKit.v3(g + t * x1, y + 0.48), MeshKit.v3(g + t * x0, y + 0.48), o3)
					y += 0.58
			if out.dot(fout) > 0.0 and not lod and front_run.is_empty():
				front_run = [a + t * s0, a + t * s1]
		if office[1] - office[0] > 1.0:
			# The office window between the bays and the drum.
			var wa: Vector2 = a + t * float(office[0]) + out * 0.06
			var wb: Vector2 = a + t * float(office[1]) + out * 0.06
			walls.color = _vertex_color(Color(0.9, 0.9, 0.88), 0.0)
			walls.quad(MeshKit.v3(wa, 0.85), MeshKit.v3(wb, 0.85), MeshKit.v3(wb, 2.65), MeshKit.v3(wa, 2.65), o3)
			walls.color = _vertex_color(Color(0.2, 0.25, 0.29), 0.0)
			wa += out * 0.02 + t * 0.1
			wb += out * 0.02 - t * 0.1
			walls.quad(MeshKit.v3(wa, 0.95), MeshKit.v3(wb, 0.95), MeshKit.v3(wb, 2.55), MeshKit.v3(wa, 2.55), o3)
	if not front_run.is_empty() and lm.has("sign"):
		# The name over the bays on the side facing the street.
		var board := _name_board(walls, str(lm["sign"]), front_run[0], front_run[1], wall_h - 0.5, 0.6, brand)
		board["colour"] = letters
		signs.append(board)

	# The drum: the brand's colour, with two rolling hoops round it and a lip
	# round its top, like the oil drum it is.
	var nseg := 32
	var radial: Array[Vector2] = []
	for k in nseg + 1:
		var ang := TAU * float(k) / float(nseg)
		radial.append(Vector2(cos(ang), sin(ang)))
	var hoop := Color(0.86, 0.87, 0.88)
	var bands: Array = [[_base, barrel_h, r_draw, brand]]
	for frac: float in [0.36, 0.68]:
		var hy := barrel_h * frac
		bands.append([hy - 0.09, hy + 0.09, r_draw + 0.06, hoop])
	bands.append([barrel_h - 0.02, barrel_h + 0.16, r_draw + 0.04, hoop])
	for band: Array in bands:
		walls.color = _vertex_color(band[3], 0.0)
		var rr: float = band[2]
		for k in nseg:
			var na := Vector3(radial[k].x, 0.0, radial[k].y)
			var nb := Vector3(radial[k + 1].x, 0.0, radial[k + 1].y)
			var pa := bc + radial[k] * rr
			var pb := bc + radial[k + 1] * rr
			walls.quad_smooth(MeshKit.v3(pa, band[0]), MeshKit.v3(pb, band[0]), MeshKit.v3(pb, band[1]), MeshKit.v3(pa, band[1]), na, nb, nb, na, (na + nb) * 0.5)
	for k in nseg:
		faces.append_array(_quad_faces(bc + radial[k] * r_draw, bc + radial[k + 1] * r_draw, _base, barrel_h))
	roof.uv2 = Vector2.ZERO
	roof.color = _vertex_color(Color(0.55, 0.56, 0.57), 1.0)
	for k in nseg:
		roof.tri(MeshKit.v3(bc, barrel_h + 0.02), MeshKit.v3(bc + radial[k + 1] * (r_draw + 0.04), barrel_h + 0.02), MeshKit.v3(bc + radial[k] * (r_draw + 0.04), barrel_h + 0.02), Vector3.UP)

	# The way in, facing the front: a glass door with a window each side.
	var face := fout
	if face.dot(bc - _centre(ring)) < -0.2:
		# The front faces away from the drum's end: use the drum's end.
		face = (bc - _centre(ring)).normalized()
	var side := Vector2(-face.y, face.x)
	var f3 := Vector3(face.x, 0.0, face.y)
	var dp := bc + face * (r_draw + 0.03)
	walls.color = _vertex_color(Color(0.88, 0.88, 0.87), 0.0)
	walls.quad(MeshKit.v3(dp - side * 1.05, 0.0), MeshKit.v3(dp + side * 1.05, 0.0), MeshKit.v3(dp + side * 1.05, 2.55), MeshKit.v3(dp - side * 1.05, 2.55), f3)
	walls.color = _vertex_color(Color(0.18, 0.22, 0.26), 0.0)
	dp += face * 0.02
	walls.quad(MeshKit.v3(dp - side * 0.95, 0.05), MeshKit.v3(dp + side * 0.95, 0.05), MeshKit.v3(dp + side * 0.95, 2.45), MeshKit.v3(dp - side * 0.95, 2.45), f3)
	walls.color = _vertex_color(Color(0.8, 0.8, 0.8), 0.0)
	walls.quad(MeshKit.v3(dp - side * 0.03, 0.05), MeshKit.v3(dp + side * 0.03, 0.05), MeshKit.v3(dp + side * 0.03, 2.45), MeshKit.v3(dp - side * 0.03, 2.45), f3)
	if lm.has("sign") and not lod:
		# The name round the drum's upper half, facing the front.
		var text := str(lm["sign"])
		var y_mid := (barrel_h * 0.68 + 0.09 + barrel_h - 0.02) * 0.5
		signs.append({"text": text, "pos": MeshKit.v3(bc + face * (r_draw + 0.05), y_mid), "yaw": StreetProps.yaw_facing(face),
			"pixel": clampf(r * 1.15 / maxf(1.0, text.length() * 64.0 * 0.55), 0.004, 0.016), "colour": letters})
		var tagline := str(lm.get("tagline", ""))
		if tagline != "":
			signs.append({"text": tagline.to_upper(), "pos": MeshKit.v3(bc + face * (r_draw + 0.05), (barrel_h * 0.36 + 0.09 + barrel_h * 0.68 - 0.09) * 0.5), "yaw": StreetProps.yaw_facing(face),
				"pixel": clampf(r * 1.2 / maxf(1.0, tagline.length() * 64.0 * 0.55), 0.003, 0.01), "colour": letters})
	walls.uv2 = save_uv
	walls.color = save_c
	return faces


## The round part of a footprint, where OSM maps a curved wall as a run of
## short straight pieces all turning the same way: [centre, radius] of the
## circle that fits them best, or [] if there's no such run.
static func _round_part(ring: PackedVector2Array) -> Array:
	var n := ring.size()
	if n < 6:
		return []
	var short := []
	for i in n:
		short.append(ring[i].distance_to(ring[(i + 1) % n]) < 1.3)
	# Start just after a long side so a run doesn't wrap round the start.
	var start := -1
	for i in n:
		if not short[i]:
			start = (i + 1) % n
			break
	if start < 0:
		return []
	var best: Array = []
	var run: Array = []
	for j in n + 1:
		var i := (start + j) % n
		if j < n and short[i]:
			run.append(ring[i])
		else:
			if j < n or not run.is_empty():
				run.append(ring[i])
			if run.size() > best.size():
				best = run
			run = []
	if best.size() < 6:
		return []
	# Least-squares circle through the points (Kasa's fit).
	var m := Vector2.ZERO
	for p: Vector2 in best:
		m += p
	m /= float(best.size())
	var suu := 0.0
	var suv := 0.0
	var svv := 0.0
	var suuu := 0.0
	var svvv := 0.0
	var suvv := 0.0
	var svuu := 0.0
	for p: Vector2 in best:
		var u := p.x - m.x
		var v := p.y - m.y
		suu += u * u
		suv += u * v
		svv += v * v
		suuu += u * u * u
		svvv += v * v * v
		suvv += u * v * v
		svuu += v * u * u
	var det := suu * svv - suv * suv
	if absf(det) < 1e-6:
		return []
	var bu := 0.5 * (suuu + suvv)
	var bv := 0.5 * (svvv + svuu)
	var uc := (bu * svv - bv * suv) / det
	var vc := (suu * bv - suv * bu) / det
	var c := m + Vector2(uc, vc)
	var r := 0.0
	for p: Vector2 in best:
		r += p.distance_to(c)
	r /= float(best.size())
	if r < 0.8 or r > 6.0:
		return []
	return [c, r]


## The entrances along a big store's front ("entrances" in its landmark
## entry), each a tall glass A-frame standing out through the roof with its
## own sign, and a row of posts holding up the covered walk between them.
## An entrance is {at: 0..1 along the front from its left end as you face
## it, width, sign, sign_colour, sign_text, and optionally depth (how far
## it stands out of the wall), ridge, eave, glass, sign_height, sign_y}. Returns collision faces;
## the signs are added to `signs`.
func _entrances(walls: MeshKit, roof: MeshKit, p0: Vector2, p1: Vector2, lm: Dictionary, spec: Dictionary, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var seg := p0.distance_to(p1)
	var t := (p1 - p0) / seg
	var out := Vector2(t.y, -t.x)
	var mansard: bool = spec.get("mansard", false)
	var eave: float = spec["eave"] if mansard else float(spec["wall_h"])
	var overhang: float = spec["overhang"] if mansard else 0.0
	var top: float = spec["roof_top"] if mansard else float(spec["wall_h"])
	var slope := tan(deg_to_rad(float(spec["pitch"])))
	var run_in := (top - eave) / slope - overhang if mansard else 2.0
	var spans: Array = []
	for e: Dictionary in lm.get("entrances", []):
		# p1 is the left end as you stand outside facing the wall.
		var c := p1 - t * seg * clampf(float(e.get("at", 0.5)), 0.0, 1.0)
		var w := float(e.get("width", 12.0))
		spans.append([seg * float(e.get("at", 0.5)), w])
		if str(e.get("shape", "")) == "tower":
			faces.append_array(_glass_tower(walls, roof, c, t, out, w, e, lm, spec, signs))
			continue
		faces.append_array(_glass_gable(walls, roof, c, t, out, w, float(e.get("depth", overhang + 0.6)), run_in, eave, top, e, lm, spec, signs))
	if lm.has("base_colour"):
		# A base course along the whole front (split-face block under metal
		# siding), the height of "base_height".
		var save_bc := walls.color
		var save_bu := walls.uv2
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(Color.from_string(str(lm["base_colour"]), Color(0.5, 0.5, 0.5)), 0.0)
		var bh := float(lm.get("base_height", 1.1))
		walls.quad(MeshKit.v3(p0 + out * 0.04, _base), MeshKit.v3(p1 + out * 0.04, _base), MeshKit.v3(p1 + out * 0.04, bh), MeshKit.v3(p0 + out * 0.04, bh), Vector3(out.x, 0.0, out.y))
		walls.color = save_bc
		walls.uv2 = save_bu
	if lm.get("walk_posts", mansard) and overhang > 1.0 and not lod:
		# Posts under the eave of the covered walk, about every 6 m.
		var save_c := walls.color
		var save_uv := walls.uv2
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(_trim_srgb(spec["trim"]), 0.0)
		var count := maxi(2, int(round(seg / 6.0)))
		for k in range(count + 1):
			var along := lerpf(1.0, seg - 1.0, float(k) / float(count))
			var clear := true
			for sp: Array in spans:
				if absf(along - float(sp[0])) < float(sp[1]) * 0.5 + 1.2:
					clear = false
			if not clear:
				continue
			var c := p1 - t * along + out * (overhang - 0.35)
			faces.append_array(_box(walls, c, t, out, 0.18, 0.18, 0.0, eave - 0.3))
		walls.color = save_c
		walls.uv2 = save_uv
	return faces


## The shops along a strip plaza's front ("units" in its landmark entry),
## left to right as you face it. Each is {from, to (0 to 1 along the front
## from its left end), colour (its facade above the shop glass), height (a
## raised parapet or tower standing over the roof, m), glass (false for a
## blank wall), band (a dark canopy fascia over the glass), sign,
## sign_colour (the board; the facade's colour if unset), sign_text,
## sign_height}. Each unit stands on the footprint's own front wall where it
## is, so a plaza whose front steps back keeps its shops on their walls.
## Returns collision faces; the signs are added to `signs`.
func _units(walls: MeshKit, ring: PackedVector2Array, p0: Vector2, p1: Vector2, lm: Dictionary, spec: Dictionary, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var seg := p0.distance_to(p1)
	if seg < 1.0:
		return faces
	var t := (p1 - p0) / seg
	var out := Vector2(t.y, -t.x)
	var o3 := Vector3(out.x, 0.0, out.y)
	var wall_h := float(spec["wall_h"])
	var top := wall_h + 0.5
	var save_c := walls.color
	var save_uv := walls.uv2
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	for u: Dictionary in lm.get("units", []):
		var f0 := clampf(float(u.get("from", 0.0)), 0.0, 1.0)
		var f1 := clampf(float(u.get("to", 1.0)), 0.0, 1.0)
		if f1 - f0 < 0.005:
			continue
		# p1 is the left end as you stand outside facing the wall.
		var a := p1 - t * seg * f0
		var b := p1 - t * seg * f1
		var mid := (a + b) * 0.5
		# The front wall under this unit: the frontmost wall facing out that
		# covers its middle.
		var depth := -INF
		for i in ring.size():
			var q0 := ring[i]
			var q1 := ring[(i + 1) % ring.size()]
			var e := q1 - q0
			if e.length() < 0.5 or Vector2(e.y, -e.x).normalized().dot(out) < 0.9:
				continue
			var s0 := (q0 - p1).dot(-t)
			var s1 := (q1 - p1).dot(-t)
			var sm := (mid - p1).dot(-t)
			if sm < minf(s0, s1) - 0.5 or sm > maxf(s0, s1) + 0.5:
				continue
			depth = maxf(depth, ((q0 + q1) * 0.5 - p0).dot(out))
		if depth == -INF:
			continue
		a += out * (depth + 0.08)
		b += out * (depth + 0.08)
		mid = (a + b) * 0.5
		var w := a.distance_to(b)
		var colour := Color.from_string(str(u.get("colour", "")), spec["wall_color"])
		var h := maxf(float(u.get("height", top)), 1.0)
		var glass := bool(u.get("glass", true))
		var y0 := SHOP_FLOOR_H - 0.6 if glass else _base
		if not glass and lm.has("base_colour"):
			y0 = float(lm.get("base_height", 1.2)) # over the brick base course
		# The facade above the shop glass (or the whole blank wall).
		walls.color = _vertex_color(colour, 0.0)
		walls.quad(MeshKit.v3(b, y0), MeshKit.v3(a, y0), MeshKit.v3(a, h), MeshKit.v3(b, h), o3)
		if h > top + 0.3:
			# A raised parapet: its sides, back and cap standing over the roof.
			var d := clampf(w * 0.25, 1.5, 4.0)
			var ba := a - out * d
			var bb := b - out * d
			var t3 := Vector3(t.x, 0.0, t.y)
			# (a is the end toward +t, b toward -t.)
			walls.quad(MeshKit.v3(a, top), MeshKit.v3(ba, top), MeshKit.v3(ba, h), MeshKit.v3(a, h), t3)
			walls.quad(MeshKit.v3(bb, top), MeshKit.v3(b, top), MeshKit.v3(b, h), MeshKit.v3(bb, h), -t3)
			walls.quad(MeshKit.v3(ba, top), MeshKit.v3(bb, top), MeshKit.v3(bb, h), MeshKit.v3(ba, h), -o3)
			walls.quad(MeshKit.v3(b, h), MeshKit.v3(a, h), MeshKit.v3(ba, h), MeshKit.v3(bb, h), Vector3.UP)
			faces.append_array(_quad_faces(b, a, top, h))
		if u.has("band") and glass:
			# A dark canopy fascia standing out over the shop glass.
			walls.color = _vertex_color(Color.from_string(str(u["band"]), Color(0.2, 0.18, 0.17)), 0.0)
			var fa := a + out * 1.2
			var fb := b + out * 1.2
			walls.quad(MeshKit.v3(fb, y0 - 0.1), MeshKit.v3(fa, y0 - 0.1), MeshKit.v3(fa, y0 + 0.8), MeshKit.v3(fb, y0 + 0.8), o3)
			walls.quad(MeshKit.v3(b, y0 - 0.1), MeshKit.v3(a, y0 - 0.1), MeshKit.v3(fa, y0 - 0.1), MeshKit.v3(fb, y0 - 0.1), Vector3.DOWN)
		var text := str(u.get("sign", "")).replace("|", "\n")
		if text != "":
			var board_h := float(u.get("sign_height", clampf((h - y0) * 0.35, 0.8, 2.2)))
			# Clear of the canopy fascia, which stands out over the glass.
			var floor_y := y0 + (1.0 if u.has("band") and glass else 0.3)
			var board_y := maxf(floor_y, h - board_h - maxf(0.3, (h - floor_y - board_h) * 0.4))
			var board_c := Color.from_string(str(u.get("sign_colour", "")), colour)
			var board := _name_board(walls, text, b, a, board_y, board_h, board_c)
			board["colour"] = Color.from_string(str(u.get("sign_text", "#f2f2ec")), Color(0.95, 0.95, 0.92))
			# Plaza letters fill their board, bigger than a shop's name board
			# allows: as wide as the board takes, as tall as half of it.
			# ("|" in the sign starts a second line.)
			var lines := text.split("\n")
			var longest := 1
			for line in lines:
				longest = maxi(longest, line.length())
			var bw := minf(w * 0.8, maxf(4.0, longest * board_h * 0.56 / float(lines.size())))
			board["pixel"] = minf(bw * 0.85 / (longest * 64.0 * 0.55), board_h * 0.7 / (64.0 * float(lines.size())))
			signs.append(board)
	walls.color = save_c
	walls.uv2 = save_uv
	return faces


## One glass A-frame entrance: a steep gable facing out, its whole end
## glazed in white-framed panes over the doors, a sign band across it, the
## roof running back into the building's own roof.
func _glass_gable(walls: MeshKit, roof: MeshKit, c: Vector2, t: Vector2, out: Vector2, w: float, depth: float, back: float, eave: float, top: float, e: Dictionary, lm: Dictionary, spec: Dictionary, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var hw := w * 0.5
	var ridge := float(e.get("ridge", top + 1.5))
	var foot := float(e.get("eave", eave + 0.4))
	var o3 := Vector3(out.x, 0.0, out.y)
	var t3 := Vector3(t.x, 0.0, t.y)
	var save_c := walls.color
	var save_uv := walls.uv2
	var trim := _trim_srgb(spec["trim"])
	var fl := c + out * depth - t * hw # front corners
	var fr := c + out * depth + t * hw
	var bl := c - t * hw
	var br := c + t * hw
	# Glass walls round the vestibule, the wall shader's shopfront glazing.
	walls.uv2 = Vector2(Style.PAINTED, 1.0 + 0.1 * float(spec["trim"]))
	walls.color = _vertex_color(Color(0.9, 0.9, 0.88), 1.0)
	for side: Array in [[fl, fr, o3, w], [bl, fl, -t3, depth], [fr, br, t3, depth]]:
		_wall(walls, side[0], side[1], _base, foot, side[2], float(side[3]), BAY_W[Style.PAINTED])
		faces.append_array(_quad_faces(side[0], side[1], _base, foot))
	# The glazed gable end: tinted glass with the lit store behind it.
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	var glass := Color.from_string(str(e.get("glass", "#8d9aa0")), Color(0.55, 0.6, 0.63))
	walls.color = _vertex_color(glass, 0.0)
	var apex := c + out * depth
	walls.tri(MeshKit.v3(fl, foot), MeshKit.v3(fr, foot), MeshKit.v3(apex, ridge), o3)
	# White mullions up the glass and a transom across it.
	walls.color = _vertex_color(trim, 0.0)
	var pane := 1.6
	var cols := int(floor(w / pane))
	for k in range(1, cols):
		var x := -hw + w * float(k) / float(cols)
		var h_top := foot + (hw - absf(x)) / hw * (ridge - foot)
		var m := apex + t * x + out * 0.03
		walls.quad(MeshKit.v3(m - t * 0.05, foot), MeshKit.v3(m + t * 0.05, foot), MeshKit.v3(m + t * 0.05, h_top), MeshKit.v3(m - t * 0.05, h_top), o3)
	for frac: float in [0.0, 0.45]:
		var y := lerpf(foot, ridge, frac)
		var half := hw * (1.0 - frac)
		var m := apex + out * 0.03
		walls.quad(MeshKit.v3(m - t * half, y), MeshKit.v3(m + t * half, y), MeshKit.v3(m + t * half, y + 0.12), MeshKit.v3(m - t * half, y + 0.12), o3)
	# Rake boards up both edges of the gable.
	for s: float in [-1.0, 1.0]:
		var foot_p := apex + t * (hw + 0.35) * s + out * 0.25
		var top_p := apex + out * 0.25
		walls.quad(MeshKit.v3(foot_p, foot - 0.35), MeshKit.v3(top_p, ridge - 0.35), MeshKit.v3(top_p, ridge + 0.05), MeshKit.v3(foot_p, foot + 0.05), o3)
	# The back of the gable, where its ridge stands above the main roof.
	walls.color = _vertex_color(spec["wall_color"], 0.0)
	var bc := c - out * back
	walls.tri(MeshKit.v3(bc - t * hw, foot), MeshKit.v3(bc + t * hw, foot), MeshKit.v3(bc, ridge), -o3)
	walls.color = save_c
	walls.uv2 = save_uv
	# Shingled roof slopes from the front of the gable back into the building.
	roof.uv2 = Vector2(1.0, 0.0)
	roof.color = _vertex_color(spec["roof_color"], 1.0)
	var run := Vector2(hw + 0.35, ridge - foot + 0.35).length()
	var length := depth + 0.25 + back
	for s: float in [-1.0, 1.0]:
		var ef := apex + out * 0.25 + t * (hw + 0.35) * s
		var eb := bc + t * (hw + 0.35) * s
		var rf := apex + out * 0.25
		var a := MeshKit.v3(ef, foot - 0.35)
		var b := MeshKit.v3(eb, foot - 0.35)
		var rb := MeshKit.v3(bc, ridge)
		var ra := MeshKit.v3(rf, ridge)
		var nrm := (b - a).cross(ra - a).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		roof.quad(a, b, rb, ra, nrm, Vector2(0, 0), Vector2(length, 0), Vector2(length, run), Vector2(0, run))
	roof.uv2 = Vector2.ZERO
	# The sign: a band of the store's colour across the glass.
	var text := str(e.get("sign", lm.get("sign", "")))
	if text != "":
		var board_h := float(e.get("sign_height", 1.3))
		var board_y := float(e.get("sign_y", foot + 0.9))
		var frac_up := (board_y + board_h - foot) / (ridge - foot)
		var bw := minf(w * 0.85, 2.0 * hw * (1.0 - frac_up) - 0.4)
		var q0 := apex + out * 0.08 - t * bw * 0.5
		var q1 := apex + out * 0.08 + t * bw * 0.5
		var board := _name_board(walls, text, q0, q1, board_y, board_h, Color.from_string(str(e.get("sign_colour", lm.get("sign_colour", "#1a1f1f"))), Color(0.1, 0.12, 0.12)))
		board["colour"] = Color.from_string(str(e.get("sign_text", lm.get("sign_text", "#f2f2ec"))), Color(0.95, 0.95, 0.92))
		signs.append(board)
	return faces


## A flat-topped glass entrance tower ("shape": "tower" in an entrance):
## a box standing out of the front and up past the roof, glass all round
## (shop doors at the bottom, tall panes in a frame above), a metal cap
## across the top, the brand's sign on the glass, and optionally a "band"
## {colour, text, text_colour}: a canopy over the doors with a line of text
## on its edge. "accent" {colour, width} paints a strip of the front wall
## beside the tower (to the right as you face it, or the left with
## "side": "left"). Entrance keys: at, width, depth, height, cap (m),
## cap_colour, glass, sign, sign_colour, sign_text, sign_height, sign_y.
func _glass_tower(walls: MeshKit, roof: MeshKit, c: Vector2, t: Vector2, out: Vector2, w: float, e: Dictionary, lm: Dictionary, spec: Dictionary, signs: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var hw := w * 0.5
	var depth := float(e.get("depth", 2.0))
	var wall_h := float(spec["wall_h"])
	var h := float(e.get("height", wall_h + 3.0))
	var cap := float(e.get("cap", 1.2))
	var doors := float(e.get("doors", 3.4))
	var o3 := Vector3(out.x, 0.0, out.y)
	var t3 := Vector3(t.x, 0.0, t.y)
	var save_c := walls.color
	var save_uv := walls.uv2
	var trim := _trim_srgb(spec["trim"])
	var cap_c := Color.from_string(str(e.get("cap_colour", "#c9ccce")), Color(0.8, 0.8, 0.8))
	var glass := Color.from_string(str(e.get("glass", "#7f949e")), Color(0.5, 0.58, 0.62))
	var fl := c + out * depth + t * hw # front corners
	var fr := c + out * depth - t * hw
	var bl := c + t * hw
	var br := c - t * hw
	# The accent strip on the wall beside the tower.
	var accent: Dictionary = e.get("accent", {})
	if not accent.is_empty():
		var aw := float(accent.get("width", 4.0))
		var s := 1.0 if str(accent.get("side", "right")) == "left" else -1.0
		var a0 := c + t * s * hw + out * 0.05
		var a1 := c + t * s * (hw + aw) + out * 0.05
		if s > 0.0:
			var sw := a0
			a0 = a1
			a1 = sw
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(Color.from_string(str(accent.get("colour", "#2f6fc0")), Color(0.2, 0.4, 0.75)), 0.0)
		walls.quad(MeshKit.v3(a1, _base), MeshKit.v3(a0, _base), MeshKit.v3(a0, wall_h + 0.5), MeshKit.v3(a1, wall_h + 0.5), o3)
	# Each wall runs so its outward side is on its right, like every wall.
	var sides := [[fr, fl, o3, w], [fl, bl, t3, depth], [br, fr, -t3, depth]]
	for side: Array in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var n3: Vector3 = side[2]
		# Shop doors and glazing at the bottom (the wall shader draws them).
		walls.uv2 = Vector2(Style.PAINTED, 1.0 + 0.1 * float(spec["trim"]))
		walls.color = _vertex_color(Color(0.9, 0.9, 0.88), 1.0)
		_wall(walls, a, b, _base, doors, n3, float(side[3]), BAY_W[Style.PAINTED])
		# Tall tinted glass above, then the metal cap.
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(glass, 0.0)
		walls.wall(a, b, doors, h - cap, n3)
		walls.color = _vertex_color(cap_c, 0.0)
		walls.wall(a, b, h - cap, h, n3)
		faces.append_array(_quad_faces(a, b, _base, h))
		if not lod:
			# Frame: mullions about every 1.8 m and a transom every 2.5 m.
			walls.color = _vertex_color(trim.lerp(cap_c, 0.5), 0.0)
			var len_s := a.distance_to(b)
			var dir := (b - a) / maxf(len_s, 0.01)
			var off := Vector2(n3.x, n3.z) * 0.04
			var cols := maxi(1, int(round(len_s / 1.8)))
			for k in range(cols + 1):
				var m := a + dir * len_s * float(k) / float(cols) + off
				walls.quad(MeshKit.v3(m - dir * 0.07, doors), MeshKit.v3(m + dir * 0.07, doors), MeshKit.v3(m + dir * 0.07, h - cap), MeshKit.v3(m - dir * 0.07, h - cap), n3)
			var y := doors
			while y < h - cap - 0.5:
				walls.quad(MeshKit.v3(a + off, y), MeshKit.v3(b + off, y), MeshKit.v3(b + off, y + 0.14), MeshKit.v3(a + off, y + 0.14), n3)
				y += 2.5
	# The back, where the tower stands above the main roof, and its own roof.
	walls.color = _vertex_color(cap_c, 0.0)
	walls.wall(bl, br, wall_h, h, -o3)
	walls.color = save_c
	walls.uv2 = save_uv
	roof.uv2 = Vector2.ZERO
	var top_ring := PackedVector2Array([fr, fl, bl, br])
	if _signed_area(top_ring) < 0.0:
		top_ring.reverse()
	_flat_roof(roof, top_ring, h + 0.02)
	# A canopy over the doors with a coloured edge carrying a line of text.
	var band: Dictionary = e.get("band", {})
	if not band.is_empty():
		var reach := float(band.get("reach", 1.2))
		var bh := float(band.get("height", 0.8))
		var y0 := doors + 0.1
		var band_c := Color.from_string(str(band.get("colour", "#f2e33a")), Color(0.95, 0.9, 0.2))
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(band_c, 0.0)
		var bw := w + float(band.get("extra", 1.0)) * 2.0
		faces.append_array(_box(walls, c + out * (depth + reach * 0.5), t, out, bw * 0.5, reach * 0.5, y0, y0 + bh))
		walls.uv2 = save_uv
		walls.color = save_c
		var text := str(band.get("text", ""))
		if text != "":
			var q0 := c + out * (depth + reach + 0.01) + t * bw * 0.5
			var q1 := c + out * (depth + reach + 0.01) - t * bw * 0.5
			var board := _name_board(walls, text, q1, q0, y0 + bh * 0.15, bh * 0.7, band_c)
			board["colour"] = Color.from_string(str(band.get("text_colour", "#1d3f86")), Color(0.1, 0.2, 0.5))
			signs.append(board)
	# The brand's sign on the glass.
	var sign_text := str(e.get("sign", lm.get("sign", "")))
	if sign_text != "":
		var sh := float(e.get("sign_height", 1.8))
		var sy := float(e.get("sign_y", lerpf(doors + 1.2, h - cap - sh - 0.4, 0.55)))
		var q0 := c + out * (depth + 0.08) + t * hw * 0.92
		var q1 := c + out * (depth + 0.08) - t * hw * 0.92
		var board := _name_board(walls, sign_text, q1, q0, sy, sh, Color.from_string(str(e.get("sign_colour", lm.get("sign_colour", "#1a1f1f"))), Color(0.1, 0.12, 0.12)))
		board["colour"] = Color.from_string(str(e.get("sign_text", lm.get("sign_text", "#f2f2ec"))), Color(0.95, 0.95, 0.92))
		signs.append(board)
	return faces


## A roof on posts. Gas station canopies (OSM amenity=fuel, or a gas
## brand) stand about 5 m up with a deep fascia in the brand's colours and
## name, posts down the middle and a pump island at each post. Carports and
## shelters get a thin roof on corner posts. Cars drive underneath; only
## the posts and pumps are solid.
func _canopy(b: StreetData.Building, ring: PackedVector2Array, brand: Dictionary, id: float) -> Dictionary:
	var walls := _kit()
	walls.id = id
	var roof := _kit()
	roof.id = id
	var fuel := str(b.tags.get("amenity", "")) == "fuel" or str(brand.get("kind", "")) == "gas"
	var clear := 4.8 if fuel else 2.5
	var tagged := str(b.tags.get("height", "")).to_float()
	if tagged > 1.8:
		clear = tagged - (0.9 if fuel else 0.25)
	var depth := 0.9 if fuel else 0.25
	var low := INF
	for p in ring:
		low = minf(low, terrain.h2(p))
	_base = -0.1
	var board := Color.from_string(str(brand.get("sign_colour", "#e8e8e6" if fuel else "#8a8d90")), Color(0.9, 0.9, 0.9))
	var letters := Color.from_string(str(brand.get("sign_text", "#ffffff")), Color.WHITE)
	# Deck: top, underside, and the fascia round the edge.
	roof.uv2 = Vector2.ZERO
	roof.color = _vertex_color(Color(0.55, 0.56, 0.57), 1.0)
	_flat_roof(roof, ring, clear + depth)
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.88, 0.88, 0.86), 0.0)
	var idx := Geometry2D.triangulate_polygon(ring)
	for k in range(0, idx.size(), 3):
		walls.tri(MeshKit.v3(ring[idx[k]], clear), MeshKit.v3(ring[idx[k + 1]], clear), MeshKit.v3(ring[idx[k + 2]], clear), Vector3.DOWN)
	walls.color = _vertex_color(board, 0.0)
	for i in ring.size():
		var p0 := ring[i]
		var p1 := ring[(i + 1) % ring.size()]
		if p0.distance_to(p1) < 0.05:
			continue
		var t := (p1 - p0).normalized()
		walls.wall(p0, p1, clear, clear + depth, Vector3(t.y, 0.0, -t.x))
	# Posts and pumps, laid out along the canopy's length.
	var obb := _obb(ring)
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var hu: float = obb["half_u"]
	var hv: float = obb["half_v"]
	var faces := PackedVector3Array()
	var posts: Array[Vector2] = []
	if fuel:
		var n := maxi(2, int(round(hu * 2.0 / 8.0)) + 1)
		for k in n:
			posts.append(c + u * lerpf(-hu + 2.5, hu - 2.5, float(k) / float(n - 1)))
	else:
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				posts.append(c + u * su * (hu - 0.3) + v * sv * (hv - 0.3))
	walls.color = _vertex_color(Color(0.92, 0.92, 0.9) if fuel else Color(0.45, 0.45, 0.46), 0.0)
	for p in posts:
		faces.append_array(_box(walls, p, u, v, 0.2, 0.2, 0.0, clear))
	if fuel:
		for p in posts:
			# A concrete island across the post, a pump each side of it.
			walls.color = _vertex_color(Color(0.7, 0.69, 0.66), 0.0)
			faces.append_array(_box(walls, p, v, u, 2.4, 0.7, 0.0, 0.18))
			for sd: float in [-1.0, 1.0]:
				var q := p + v * sd * 1.3
				walls.color = _vertex_color(Color(0.93, 0.93, 0.91), 0.0)
				faces.append_array(_box(walls, q, u, v, 0.35, 0.25, 0.18, 1.6))
				walls.color = _vertex_color(board, 0.0)
				_box(walls, q, u, v, 0.37, 0.27, 1.6, 1.85)
	walls.uv2 = Vector2.ZERO
	# The brand's name on both long sides of the fascia.
	var signs: Array = []
	var pylon: Dictionary = brand.get("pylon", {})
	if fuel and not pylon.is_empty():
		faces.append_array(_price_pylon(walls, brand, pylon, c, hu, hv, u, v, signs))
	var text := str(brand.get("sign", ""))
	if fuel and text != "" and not lod:
		for sd: float in [-1.0, 1.0]:
			var n2 := v * sd
			var at := c + n2 * (hv + 0.03)
			signs.append({"text": text, "pos": MeshKit.v3(at, clear + depth * 0.5), "yaw": StreetProps.yaw_facing(n2),
				"pixel": clampf(depth * 0.6 / 45.0, 0.004, 0.02), "colour": letters})
	return {"walls": walls, "roof": roof, "collision": faces, "floor_y": low, "signs": signs}


## A multi-storey car park you can drive up through (see Parkade).
func _parkade(ring: PackedVector2Array, lm: Dictionary, id: float) -> Dictionary:
	var walls := _kit()
	walls.id = id
	var roof := _kit()
	roof.id = id
	var lay := Parkade.layout(ring, lm, terrain, net)
	var faces := Parkade.build(lay, walls, roof, lod)
	_base = -0.1
	return {"walls": walls, "roof": roof, "collision": faces["collision"], "ground": faces["ground"],
		"floor_y": lay["floor_y"], "signs": [], "parkade": lay}


## A storage tank: a white steel cylinder of welded courses on a concrete
## ring, a shallow cone or a dome on top with a railing round the rim, and a
## stair that spirals up the side. The footprint gives the centre and
## radius; height and dome from the lidar (or the landmark entry). A sign
## ("sign" in its entry) is painted on the side facing front_toward_spot,
## between two chevrons when "logo" is set, the way the oil companies do it.
func _tank(b: StreetData.Building, ring: PackedVector2Array, lm: Dictionary, id: float) -> Dictionary:
	var walls := _kit()
	walls.id = id
	var roof := _kit()
	roof.id = id
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	var r := 0.0
	for p in ring:
		r += p.distance_to(c)
	r /= float(ring.size())
	var tags := b.tags
	var top := float(tags.get("lidar_top", lm.get("wall_height", 12.0)))
	var eave := float(tags.get("lidar_eave", top))
	var dome := str(lm.get("roof", "dome" if str(tags.get("lidar_roof", "flat")) != "flat" else "cone")) == "dome"
	var h := top - maxf(0.4, r * 0.08)
	if dome and eave > 3.0:
		h = eave
	if lm.has("wall_height"):
		h = float(lm["wall_height"])
	h = maxf(h, 3.0)
	var low := INF
	var high := -INF
	for p in ring:
		var gh := terrain.h2(p)
		low = minf(low, gh)
		high = maxf(high, gh)
	var floor_y := minf(high, low + 1.0)
	_base = minf(-0.1, low - floor_y - 0.3)

	var body := Color.from_string(str(lm.get("colour", "#ecebe6")), Color(0.92, 0.92, 0.9))
	var cap := Color.from_string(str(lm.get("roof_colour", "#dcdcd7")), Color(0.86, 0.86, 0.84))
	var n := clampi(int(r * 1.6), 24, 56)
	var rim: Array[Vector2] = []
	var radial: Array[Vector2] = []
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		radial.append(Vector2(cos(a), sin(a)))
		rim.append(c + radial[k] * r)
	var faces := PackedVector3Array()
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	# The shell, a concrete ring at its foot, and a seam line at every course.
	var bands: Array = [[_base, h, r, body]]
	bands.append([_base, 0.35, r + 0.08, Color(0.6, 0.59, 0.56)])
	if not lod:
		var y := 2.44
		while y < h - 0.3:
			bands.append([y, y + 0.06, r + 0.015, body * 0.86])
			y += 2.44
	for band: Array in bands:
		walls.color = _vertex_color(band[3], 0.0)
		var rr: float = band[2]
		for k in n:
			var na := Vector3(radial[k].x, 0.0, radial[k].y)
			var nb := Vector3(radial[k + 1].x, 0.0, radial[k + 1].y)
			var pa := c + radial[k] * rr
			var pb := c + radial[k + 1] * rr
			walls.quad_smooth(MeshKit.v3(pa, band[0]), MeshKit.v3(pb, band[0]), MeshKit.v3(pb, band[1]), MeshKit.v3(pa, band[1]), na, nb, nb, na, (na + nb) * 0.5)
	for k in n:
		faces.append_array(_quad_faces(rim[k], rim[k + 1], _base, h))
	# The top: a dome (a cap of a sphere) or a shallow cone.
	roof.uv2 = Vector2(3.0, 0.0)
	roof.color = _vertex_color(cap, 1.0)
	if dome:
		# The dome can be narrower than the tank ("dome_width", a fraction of
		# its width), standing on a flat ring of roof.
		var rd := r * clampf(float(lm.get("dome_width", 1.0)), 0.2, 1.0)
		if rd < r - 0.1:
			for k in n:
				var o0 := MeshKit.v3(rim[k], h)
				var o1 := MeshKit.v3(rim[k + 1], h)
				var i0 := MeshKit.v3(c + radial[k] * rd, h)
				var i1 := MeshKit.v3(c + radial[k + 1] * rd, h)
				roof.quad(o0, o1, i1, i0, Vector3.UP)
		var d := clampf(top - h, 1.5, rd * 0.95)
		var big_r := (rd * rd + d * d) / (2.0 * d)
		var cy := h + d - big_r
		var theta0 := asin(clampf(rd / big_r, 0.0, 1.0))
		if d > big_r:
			theta0 = PI - theta0
		var rings := 8
		for j in rings:
			var t0 := theta0 * (1.0 - float(j) / rings)
			var t1 := theta0 * (1.0 - float(j + 1) / rings)
			for k in n:
				var corners: Array[Vector3] = []
				var normals: Array[Vector3] = []
				for q: Array in [[k, t0], [k + 1, t0], [k + 1, t1], [k, t1]]:
					var dir: Vector2 = radial[q[0]]
					var th: float = q[1]
					var nrm := Vector3(dir.x * sin(th), cos(th), dir.y * sin(th))
					corners.append(Vector3(c.x, cy, c.y) + nrm * big_r)
					normals.append(nrm)
				roof.quad_smooth(corners[0], corners[1], corners[2], corners[3], normals[0], normals[1], normals[2], normals[3], normals[0] + normals[2])
	else:
		var rise := maxf(0.4, r * 0.08)
		var apex := MeshKit.v3(c, h + rise)
		for k in n:
			var a := MeshKit.v3(rim[k], h)
			var bb := MeshKit.v3(rim[k + 1], h)
			var nrm := (bb - a).cross(apex - a).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			roof.tri(a, bb, apex, nrm)
	roof.uv2 = Vector2.ZERO

	var front := Vector2(0, 1)
	var spot: Array = lm.get("front_toward_spot", [])
	if spot.size() >= 2:
		front = (data.projection.to_ground(float(spot[1]), float(spot[0])) - c).normalized()
	if not lod:
		var rail := Color.from_string(str(lm.get("rail_colour", "#f2f2ee")), Color(0.95, 0.95, 0.93))
		walls.color = _vertex_color(rail, 0.0)
		# Railing round the rim: two rails and a post every few panels.
		for y: float in [h + 0.55, h + 1.05]:
			for k in n:
				var pa := c + radial[k] * (r - 0.12)
				var pb := c + radial[k + 1] * (r - 0.12)
				var o3 := Vector3(radial[k].x + radial[k + 1].x, 0.0, radial[k].y + radial[k + 1].y).normalized()
				walls.quad(MeshKit.v3(pa, y), MeshKit.v3(pb, y), MeshKit.v3(pb, y + 0.07), MeshKit.v3(pa, y + 0.07), o3)
				walls.quad(MeshKit.v3(pa, y), MeshKit.v3(pb, y), MeshKit.v3(pb, y + 0.07), MeshKit.v3(pa, y + 0.07), -o3)
		for k in range(0, n, 3):
			_box(walls, c + radial[k] * (r - 0.12), radial[k], Vector2(-radial[k].y, radial[k].x), 0.04, 0.04, h, h + 1.1)
		# The stair, climbing a third of the way round, ending at the top
		# beside the front so it shows from there.
		var span := float(lm.get("stair_turn", 120.0))
		var a_end := atan2(front.y, front.x) + deg_to_rad(float(lm.get("stair_angle", 40.0)))
		var a_start := a_end - deg_to_rad(span)
		var steps := maxi(12, int(span / 6.0))
		var tread := Color(0.62, 0.62, 0.6)
		for i in steps:
			var aa0 := lerpf(a_start, a_end, float(i) / steps)
			var aa1 := lerpf(a_start, a_end, float(i + 1) / steps)
			var y0 := h * float(i) / steps
			var y1 := h * float(i + 1) / steps
			var d0 := Vector2(cos(aa0), sin(aa0))
			var d1 := Vector2(cos(aa1), sin(aa1))
			var in0 := c + d0 * (r + 0.05)
			var in1 := c + d1 * (r + 0.05)
			var out0 := c + d0 * (r + 1.0)
			var out1 := c + d1 * (r + 1.0)
			walls.color = _vertex_color(tread, 0.0)
			var up := (MeshKit.v3(in1, y1) - MeshKit.v3(in0, y0)).cross(MeshKit.v3(out0, y0) - MeshKit.v3(in0, y0)).normalized()
			if up.y < 0.0:
				up = -up
			walls.quad(MeshKit.v3(in0, y0), MeshKit.v3(in1, y1), MeshKit.v3(out1, y1), MeshKit.v3(out0, y0), up)
			walls.quad(MeshKit.v3(in0, y0 - 0.08), MeshKit.v3(in1, y1 - 0.08), MeshKit.v3(out1, y1 - 0.08), MeshKit.v3(out0, y0 - 0.08), -up)
			walls.color = _vertex_color(rail, 0.0)
			var o3 := Vector3(d0.x + d1.x, 0.0, d0.y + d1.y).normalized()
			for band: Array in [[-0.3, 0.0], [0.5, 0.56], [1.0, 1.07]]:
				walls.quad(MeshKit.v3(out0, y0 + band[0]), MeshKit.v3(out1, y1 + band[0]), MeshKit.v3(out1, y1 + band[1]), MeshKit.v3(out0, y0 + band[1]), o3)
				walls.quad(MeshKit.v3(out0, y0 + band[0]), MeshKit.v3(out1, y1 + band[0]), MeshKit.v3(out1, y1 + band[1]), MeshKit.v3(out0, y0 + band[1]), -o3)
			if i % 2 == 0:
				_box(walls, out0, d0, Vector2(-d0.y, d0.x), 0.04, 0.04, y0, y0 + 1.05)
		# A landing round to the rim at the top.
		walls.color = _vertex_color(tread, 0.0)
		var de := Vector2(cos(a_end), sin(a_end))
		_box(walls, c + de * (r + 0.55), de, Vector2(-de.y, de.x), 0.5, 0.8, h - 0.1, h)
	walls.uv2 = Vector2.ZERO

	var signs: Array = []
	var text := str(lm.get("sign", ""))
	if text != "" and not lod:
		var letters := Color.from_string(str(lm.get("sign_text", "#1d2a5c")), Color(0.1, 0.15, 0.35))
		var w := minf(r * 1.0, 14.0)
		var y_mid := h * float(lm.get("sign_at", 0.55))
		var at := c + front * (r + 0.45)
		signs.append({"text": text, "pos": MeshKit.v3(at, y_mid), "yaw": StreetProps.yaw_facing(front),
			"pixel": clampf(w * 0.8 / maxf(1.0, text.length() * 64.0 * 0.55), 0.004, 0.06), "colour": letters})
		if lm.get("logo", false):
			# A chevron pointing up above the name, one pointing down below.
			var tn := Vector2(-front.y, front.x)
			var f3 := Vector3(front.x, 0.0, front.y)
			var hw := w * 0.45
			var rise := w * 0.22
			var thick := w * 0.07
			for part: Array in [[1.0, str(lm.get("logo_top", "#d22630"))], [-1.0, str(lm.get("logo_bottom", "#003da5"))]]:
				var sgn: float = part[0]
				walls.uv2 = Vector2(Style.PLAIN, 0.0)
				walls.color = _vertex_color(Color.from_string(part[1], Color.RED), 0.0)
				var base_y := y_mid + sgn * w * 0.1
				for side: float in [-1.0, 1.0]:
					var o := c + front * (r + 0.4)
					var e0 := o + tn * hw * side
					var e1 := o
					walls.quad(MeshKit.v3(e0, base_y), MeshKit.v3(e1, base_y + sgn * rise), MeshKit.v3(e1, base_y + sgn * (rise + thick)), MeshKit.v3(e0, base_y + sgn * thick), f3)
				walls.uv2 = Vector2.ZERO
	return {"walls": walls, "roof": roof, "collision": faces, "floor_y": floor_y, "signs": signs}


## The tall price sign out by the road in front of a gas station: the
## brand's panel on top, the store's below it, then the prices, on a pair of
## legs. Placed toward the nearest street, beside the canopy.
func _price_pylon(walls: MeshKit, brand: Dictionary, pylon: Dictionary, c: Vector2, hu: float, hv: float, u: Vector2, v: Vector2, signs: Array) -> PackedVector3Array:
	var hit := net.nearest_on_streets(c, 120.0)
	if hit.is_empty():
		return PackedVector3Array()
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var to_road := ((hit["pos"] as Vector2) - c).normalized()
	var along: Vector2 = hit["dir"]
	var at := (hit["pos"] as Vector2) - to_road * (e.half_width + e.shoulder + float(pylon.get("setback_m", 4.0)))
	at += along * float(pylon.get("shift_m", 0.0))
	var faces := PackedVector3Array()
	var w := float(pylon.get("width", 1.7))
	var h := float(pylon.get("height", 7.0))
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	walls.color = _vertex_color(Color(0.3, 0.32, 0.34), 0.0)
	for s: float in [-1.0, 1.0]:
		# Down into the ground: the road may be lower than the building.
		faces.append_array(_box(walls, at + along * s * w * 0.35, along, to_road, 0.1, 0.1, -2.5, h * 0.4))
	# Panels from the top down: [colour, text, text colour, height].
	var panels: Array = [
		[brand.get("sign_colour", "#003da5"), str(brand.get("sign", "")), brand.get("sign_text", "#ffffff"), 1.3],
	]
	for extra: Variant in pylon.get("panels", []):
		var d: Dictionary = extra
		panels.append([d.get("colour", "#ffffff"), str(d.get("text", "")), d.get("text_colour", "#000000"), float(d.get("height", 0.9))])
	var y := h
	for pnl: Array in panels:
		var ph: float = pnl[3]
		walls.color = _vertex_color(Color.from_string(str(pnl[0]), Color.WHITE), 0.0)
		faces.append_array(_box(walls, at, along, to_road, w * 0.5, 0.2, y - ph, y))
		for side: float in [-1.0, 1.0]:
			var n := to_road * side
			var txt: String = pnl[1]
			if txt != "":
				signs.append({"text": txt, "pos": MeshKit.v3(at + n * 0.22, y - ph * 0.5), "yaw": StreetProps.yaw_facing(n),
					"pixel": clampf(w * 0.8 / maxf(1.0, _longest_line(txt) * 64.0 * 0.55), 0.003, 0.012), "colour": Color.from_string(str(pnl[2]), Color.BLACK)})
		y -= ph
	walls.uv2 = Vector2.ZERO
	return faces


static func _longest_line(text: String) -> float:
	var n := 1
	for line in text.split("\n"):
		n = maxi(n, line.length())
	return float(n)


## A box centred on ground point c, half sizes a along `ua` and b along `ub`,
## from height y0 to y1. Added to `kit`; returns its side faces for collision.
func _box(kit: MeshKit, c: Vector2, ua: Vector2, ub: Vector2, a: float, b: float, y0: float, y1: float) -> PackedVector3Array:
	var corners := [c + ua * a + ub * b, c - ua * a + ub * b, c - ua * a - ub * b, c + ua * a - ub * b]
	var faces := PackedVector3Array()
	for k in 4:
		var p0: Vector2 = corners[k]
		var p1: Vector2 = corners[(k + 1) % 4]
		var mid := (p0 + p1) * 0.5 - c
		kit.quad(MeshKit.v3(p0, y0), MeshKit.v3(p1, y0), MeshKit.v3(p1, y1), MeshKit.v3(p0, y1), Vector3(mid.x, 0.0, mid.y).normalized())
		faces.append_array(_quad_faces(p0, p1, y0, y1))
	kit.quad(MeshKit.v3(corners[0], y1), MeshKit.v3(corners[1], y1), MeshKit.v3(corners[2], y1), MeshKit.v3(corners[3], y1), Vector3.UP)
	return faces


# --- landmarks ---------------------------------------------------------------------------

## The landmark's front facade as [p0, p1], ordered so its outward side is
## Vector2(t.y, -t.x), the same convention as every wall.
## The front is whichever side of the footprint's bounding box faces the
## junction named in "front_toward", or the street in "front_street"; the
## facade line is the frontmost part of the real footprint on that side, so a
## portico lands on Province House's centre bay and spires flank a nave.
func _front_line(ring: PackedVector2Array, lm: Dictionary, obb: Dictionary) -> Array:
	var target := Vector2.INF
	var toward: Array = lm.get("front_toward", [])
	if toward.size() >= 2:
		var nid := net.find_junction(str(toward[0]), str(toward[1]))
		if nid != "":
			target = net.nodes[nid]
	if str(lm.get("front", "")) == "parking" and not parking.is_empty():
		# The side looking onto the biggest stretch of parking lot.
		var best_lot := 0
		var c0: Vector2 = obb["center"]
		for n: Vector2 in [obb["u"], -(obb["u"] as Vector2), obb["v"], -(obb["v"] as Vector2)]:
			var reach := absf(n.dot(obb["u"])) * float(obb["half_u"]) + absf(n.dot(obb["v"])) * float(obb["half_v"])
			var side := Vector2(-n.y, n.x)
			var span := absf(side.dot(obb["u"])) * float(obb["half_u"]) + absf(side.dot(obb["v"])) * float(obb["half_v"])
			var hits := 0
			for k in 5:
				for d: float in [8.0, 20.0, 35.0]:
					var q := c0 + n * (reach + d) + side * span * (float(k) / 2.0 - 1.0) * 0.8
					for lot in parking:
						if Geometry2D.is_point_in_polygon(q, lot):
							hits += 1
							break
			if hits > best_lot:
				best_lot = hits
				target = c0 + n * (reach + 30.0)
	var spot: Array = lm.get("front_toward_spot", [])
	if spot.size() >= 2:
		# Where someone stood looking at the front (from a field note), as
		# [latitude, longitude].
		target = data.projection.to_ground(float(spot[1]), float(spot[0]))
	var street := str(lm.get("front_street", ""))
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var sides := [[u, float(obb["half_u"])], [-u, float(obb["half_u"])], [v, float(obb["half_v"])], [-v, float(obb["half_v"])]]
	var best_n := Vector2.ZERO
	var best_score := -INF
	for sd: Array in sides:
		var n: Vector2 = sd[0]
		var mid := c + n * float(sd[1])
		var score := 0.0
		if target != Vector2.INF:
			score = n.dot((target - mid).normalized())
		elif street != "":
			score = _facing_street(mid, n, street) - _distance_to_street(mid + n * 2.0, street) * 0.01
		else:
			var hit := net.nearest_on_streets(mid + n * 4.0, 60.0)
			score = -float(hit.get("dist", 99.0))
		if score > best_score:
			best_score = score
			best_n = n
	if best_n == Vector2.ZERO:
		return []
	# Frontmost footprint points on that side (within 2 m of the furthest).
	var max_d := -INF
	for p in ring:
		max_d = maxf(max_d, (p - c).dot(best_n))
	var t := Vector2(-best_n.y, best_n.x)
	var lo := INF
	var hi := -INF
	for p in ring:
		if (p - c).dot(best_n) > max_d - 2.0:
			lo = minf(lo, (p - c).dot(t))
			hi = maxf(hi, (p - c).dot(t))
	var base := c + best_n * max_d
	if str(lm.get("front_line", "")) == "main":
		# A long front with vestibules standing out of it: the line of the
		# main wall (the depth with the most wall along it), the whole width
		# of the building.
		# Walls are grouped by depth to the nearest half metre, and the line
		# goes at the winning group's real (length-weighted) depth, so things
		# set on it (an entrance tower, a base course) sit on the wall rather
		# than up to 25 cm inside it.
		var by_depth := {}
		var depth_sum := {}
		for i in ring.size():
			var q0 := ring[i]
			var q1 := ring[(i + 1) % ring.size()]
			var e := q1 - q0
			if e.length() < 0.5 or Vector2(e.y, -e.x).normalized().dot(best_n) < 0.95:
				continue
			var d := ((q0 + q1) * 0.5 - c).dot(best_n)
			var key := int(round(d * 2.0))
			by_depth[key] = float(by_depth.get(key, 0.0)) + e.length()
			depth_sum[key] = float(depth_sum.get(key, 0.0)) + d * e.length()
		var best_len := 0.0
		for key: int in by_depth:
			if float(by_depth[key]) > best_len:
				best_len = by_depth[key]
				max_d = float(depth_sum[key]) / best_len
		lo = INF
		hi = -INF
		for p in ring:
			lo = minf(lo, (p - c).dot(t))
			hi = maxf(hi, (p - c).dot(t))
		return [c + best_n * max_d + t * lo, c + best_n * max_d + t * hi]
	if hi - lo < 2.0:
		# An irregular footprint (wings, notches): use the whole side of its box.
		var half := absf(t.dot(u)) * float(obb["half_u"]) + absf(t.dot(v)) * float(obb["half_v"])
		lo = (c - c).dot(t) - half
		hi = half
		base = c + best_n * (absf(best_n.dot(u)) * float(obb["half_u"]) + absf(best_n.dot(v)) * float(obb["half_v"]))
	return [base + t * lo, base + t * hi]


## A logo or name on a wall other than the front ("wall_signs" in a
## landmark entry), the way chains put one on the side or back that faces
## the road or the next lot. Each is {facing (compass degrees the wall looks
## toward: 0 north, 90 east), at (0 to 1 along that wall from its left end
## as you face it, default 0.5), sign (default the brand's name),
## sign_colour ("wall" for letters straight on the wall), sign_text,
## sign_height, sign_y (default near the top of the wall)}.
func _wall_sign(walls: MeshKit, ring: PackedVector2Array, spec: Dictionary, lm: Dictionary, ws: Dictionary, wall_color: Color, signs: Array) -> void:
	var text := str(ws.get("sign", lm.get("sign", lm.get("name", ""))))
	if text == "":
		return
	var bearing := deg_to_rad(float(ws.get("facing", 0.0)))
	var want := Vector2(sin(bearing), -cos(bearing)) # game x east, z south
	var line := _side_line(ring, want)
	if line.is_empty():
		return
	var p0: Vector2 = line[0]
	var p1: Vector2 = line[1]
	var seg := p0.distance_to(p1)
	var t := (p1 - p0) / maxf(seg, 0.01)
	var wall_h := float(spec["wall_h"])
	var h := float(ws.get("sign_height", 1.6))
	var y := float(ws.get("sign_y", wall_h - h - 0.8))
	# A stretch of wall centred on "at" (p1 is the left end facing it), as
	# wide as the board can be, so _name_board centres the sign there.
	var c := p1 - t * seg * clampf(float(ws.get("at", 0.5)), 0.0, 1.0)
	var half := maxf(4.0, text.length() * h * 0.56) / 0.8 * 0.5
	var colour_s := str(ws.get("sign_colour", lm.get("sign_colour", "#1a1f1f")))
	var board_c := wall_color if colour_s == "wall" else Color.from_string(colour_s, Color(0.1, 0.12, 0.12))
	var board := _name_board(walls, text, c - t * half, c + t * half, y, h, board_c)
	board["colour"] = Color.from_string(str(ws.get("sign_text", lm.get("sign_text", "#f2f2ec"))), Color(0.95, 0.95, 0.92))
	# Letters as big as the board allows (a name board's usual cap keeps
	# them door-sized), so the logo reads from across the lot.
	var board_w := minf(seg * 0.8, maxf(4.0, text.length() * h * 0.56))
	board["pixel"] = minf(board_w * 0.85 / maxf(1.0, text.length() * 64.0 * 0.55), h * 0.7 / 64.0)
	signs.append(board)


## The longest wall of the footprint looking within about 25 degrees of
## `want`, as [p0, p1] (in ring order, so its outward side is
## Vector2(t.y, -t.x)), or [] if none does.
func _side_line(ring: PackedVector2Array, want: Vector2) -> Array:
	var best: Array = []
	var best_len := 0.0
	for i in ring.size():
		var q0 := ring[i]
		var q1 := ring[(i + 1) % ring.size()]
		var e := q1 - q0
		if e.length() > best_len and Vector2(e.y, -e.x).normalized().dot(want) > 0.9:
			best_len = e.length()
			best = [q0, q1]
	return best


func _distance_to_street(p: Vector2, street: String) -> float:
	var best := INF
	for e in net.edges:
		if e.name != street:
			continue
		for i in range(e.points.size() - 1):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, e.points[i], e.points[i + 1])))
	return best


func _facing_street(mid: Vector2, out: Vector2, street: String) -> float:
	var best_d := INF
	var best_q := mid
	for e in net.edges:
		if e.name != street:
			continue
		for i in range(e.points.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(mid, e.points[i], e.points[i + 1])
			if mid.distance_to(q) < best_d:
				best_d = mid.distance_to(q)
				best_q = q
	return out.dot((best_q - mid).normalized())


## Towers, spires and porticos on the front wall. Returns extra collision faces.
func _landmark_extras(walls: MeshKit, roof: MeshKit, lm: Dictionary, spec: Dictionary, p0: Vector2, p1: Vector2, trim: Color) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var seg := p0.distance_to(p1)
	var t := (p1 - p0) / seg
	var out := Vector2(t.y, -t.x)
	var wall_color: Color = spec["wall_color"]
	var spire_color := Color.from_string(str(lm.get("spire_colour", "")), spec["roof_color"])
	var size := float(lm.get("tower_size", 6.0))
	var tower_h := float(lm.get("tower_height", 25.0))
	var spire_h := float(lm.get("spire_height", 0.0))
	var protrude := float(lm.get("tower_protrude", 1.0))
	match str(lm.get("towers", "")):
		"front_pair":
			for c: Vector2 in [p0 + t * size * 0.5, p1 - t * size * 0.5]:
				faces.append_array(_tower(walls, roof, c + out * (protrude - size * 0.5), t, out, size, tower_h, spire_h, wall_color, spire_color, trim))
		"front_center":
			var c := (p0 + p1) * 0.5
			faces.append_array(_tower(walls, roof, c + out * (protrude - size * 0.5), t, out, size, tower_h, spire_h, wall_color, spire_color, trim))
		"front_corner":
			var c := p1 - t * size * 0.5
			faces.append_array(_tower(walls, roof, c + out * (protrude - size * 0.5), t, out, size, tower_h, spire_h, wall_color, spire_color, trim))
	if str(lm.get("massing", "")) == "confederation" and facade_relief:
		faces.append_array(_confederation(walls, roof, spec, p0, p1))
	if lm.get("portico", false):
		faces.append_array(_portico(walls, roof, (p0 + p1) * 0.5, t, out, minf(seg * 0.45, float(lm.get("portico_width", 13.0))), float(spec["wall_h"]), trim, spec["roof_color"]))
	return faces


## A square tower with a cornice and an eight-sided spire (or a low pyramid cap).
func _tower(walls: MeshKit, roof: MeshKit, c: Vector2, t: Vector2, out: Vector2, size: float, h: float, spire_h: float, wall_color: Color, spire_color: Color, trim: Color) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var hs := size * 0.5
	var corners := [c + (t + out) * hs, c + (out - t) * hs, c - (t + out) * hs, c + (t - out) * hs]
	var save_c := walls.color
	var save_uv := walls.uv2
	walls.color = _vertex_color(wall_color, floorf(h / FLOOR_H) - 1.0)
	walls.uv2 = Vector2(Style.CHURCH, 0.1 * Trim.WHITE)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var n2 := (mid - c).normalized()
		_wall(walls, a, b, _base, h, Vector3(n2.x, 0.0, n2.y), a.distance_to(b), size)
		faces.append_array(_quad_faces(a, b, _base, h))
		_cornice(walls, a, b, n2, h, trim)
		if detail:
			_belfry(walls, a, b, n2, size, h, wall_color)
	if detail and spire_h > size:
		# A small pinnacle on each corner round the foot of the spire.
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(_weathered(wall_color, 0.2, 0.9), 0.0)
		for k in 4:
			var q: Vector2 = c + (corners[k] - c) * 0.88
			_box(walls, q, t, out, 0.3, 0.3, h, h + 0.9)
			var tip := MeshKit.v3(q, h + 2.6)
			var sq := [q + (t + out) * 0.3, q + (out - t) * 0.3, q - (t + out) * 0.3, q + (t - out) * 0.3]
			for e in 4:
				var v0 := MeshKit.v3(sq[e], h + 0.9)
				var v1 := MeshKit.v3(sq[(e + 1) % 4], h + 0.9)
				var mid2: Vector2 = (sq[e] + sq[(e + 1) % 4]) * 0.5 - q
				walls.tri(v0, v1, tip, (Vector3(mid2.x, 0.25, mid2.y)).normalized())
	walls.color = save_c
	walls.uv2 = save_uv
	# Cap: spire (8 sides) or a shallow pyramid.
	var save_r := roof.color
	roof.color = _vertex_color(spire_color, 0.0)
	roof.uv2 = Vector2(1.0, 0.0)
	var apex := MeshKit.v3(c, h + maxf(spire_h, size * 0.35))
	var sides := 8 if spire_h > size else 4
	var radius := hs * (0.92 if sides == 8 else 1.25)
	var base_y := h + 0.08
	for i in sides:
		var a0 := TAU * (float(i) + (0.5 if sides == 4 else 0.0)) / float(sides)
		var a1 := TAU * (float(i + 1) + (0.5 if sides == 4 else 0.0)) / float(sides)
		var q0 := c + (t * cos(a0) + out * sin(a0)) * radius
		var q1 := c + (t * cos(a1) + out * sin(a1)) * radius
		var v0 := MeshKit.v3(q0, base_y)
		var v1 := MeshKit.v3(q1, base_y)
		var n := (v1 - v0).cross(apex - v0).normalized()
		if n.dot(MeshKit.v3((q0 + q1) * 0.5 - c, 0.0)) < 0.0:
			n = -n
		roof.tri(v0, v1, apex, n, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, spire_h))
	roof.color = save_r
	return faces


## The belfry opening near the top of one tower face: a tall pointed
## opening framed in stone, dark inside, with sloping louvre boards.
func _belfry(walls: MeshKit, a: Vector2, b: Vector2, n2: Vector2, size: float, h: float, wall_color: Color) -> void:
	var seg := a.distance_to(b)
	var t := (b - a) / seg
	var w := minf(seg * 0.45, 2.6)
	var x0 := seg * 0.5 - w * 0.5
	var x1 := seg * 0.5 + w * 0.5
	var y0 := h - 1.6 - w * 2.0
	var y1 := h - 1.6
	var save_uv := walls.uv2
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	# Frame (proud of the wall) and the dark opening inside it.
	walls.color = _vertex_color(_weathered(wall_color, 0.2, 0.88), 0.0)
	_slab(walls, a, t, n2, x0 - 0.25, x1 + 0.25, y0 - 0.3, y1, 0.12)
	walls.color = _vertex_color(Color(0.06, 0.06, 0.07), 0.0)
	_slab(walls, a, t, n2, x0, x1, y0, y1 - w * 0.3, 0.14)
	# Pointed head of the opening: stepped, darker.
	for k in 4:
		var f := float(k) / 4.0
		var inset := w * 0.5 * f * f
		_slab(walls, a, t, n2, x0 + inset, x1 - inset, y1 - w * 0.3 + f * w * 0.3 - 0.01, y1 - w * 0.3 + (f + 0.25) * w * 0.3, 0.14)
	# Louvres: boards sloping down and out.
	walls.color = _vertex_color(Color(0.36, 0.34, 0.3), 0.0)
	var count := int((y1 - w * 0.3 - y0) / 0.28)
	for k in count:
		var y := y0 + 0.12 + k * 0.28
		_slab(walls, a, t, n2, x0 + 0.04, x1 - 0.04, y, y + 0.06, 0.22)
	walls.uv2 = save_uv


## A classical portico: columns, entablature and a pediment.
func _portico(walls: MeshKit, roof: MeshKit, c: Vector2, t: Vector2, out: Vector2, width: float, wall_h: float, trim: Color, roof_color: Color) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var depth := 3.8
	var col_h := minf(wall_h * 0.78, 10.0)
	var ent_h := 1.1
	var save_c := walls.color
	var save_uv := walls.uv2
	walls.color = _vertex_color(trim, 0.0)
	walls.uv2 = Vector2(Style.PLAIN, 0.0)
	var count := 6 if width > 11.0 else 4
	for k in count:
		var along := -width * 0.5 + 0.6 + (width - 1.2) * float(k) / float(count - 1)
		var cc := c + t * along + out * (depth - 0.6)
		faces.append_array(_column(walls, cc, 0.42, col_h))
		if detail:
			# Square plinth and a rounded base under the shaft; an abacus
			# and a flared echinus on top.
			_box(walls, cc, t, out, 0.58, 0.58, _base, 0.32)
			_box(walls, cc, t, out, 0.5, 0.5, 0.32, 0.5)
			_box(walls, cc, t, out, 0.48, 0.48, col_h - 0.45, col_h - 0.25)
			_box(walls, cc, t, out, 0.6, 0.6, col_h - 0.25, col_h)
	if detail:
		# Three broad steps up to the portico floor, in stone.
		var save_uv2 := walls.uv2
		walls.uv2 = Vector2(Style.PLAIN, 0.0)
		walls.color = _vertex_color(Color(0.66, 0.62, 0.54), 0.0)
		for s in 3:
			var d2 := depth + 0.9 - s * 0.4
			_slab(walls, c - t * width * 0.5, t, out, -0.3, width + 0.3, _base, 0.15 * (s + 1), d2)
		walls.uv2 = save_uv2
		walls.color = _vertex_color(trim, 0.0)
	# Entablature: a box across the top of the columns.
	var l0 := c - t * width * 0.5
	var l1 := c + t * width * 0.5
	var f0 := l0 + out * depth
	var f1 := l1 + out * depth
	var y0 := col_h
	var y1 := col_h + ent_h
	var o3 := Vector3(out.x, 0.0, out.y)
	var t3 := Vector3(t.x, 0.0, t.y)
	walls.wall(f0, f1, y0, y1, o3)
	walls.wall(l0, f0, y0, y1, -t3)
	walls.wall(f1, l1, y0, y1, t3)
	walls.quad(MeshKit.v3(l0, y0), MeshKit.v3(l1, y0), MeshKit.v3(f1, y0), MeshKit.v3(f0, y0), Vector3.DOWN)
	# Pediment: the triangle on the front and two sloped roof faces.
	var peak := y1 + width * 0.2
	var fm := (f0 + f1) * 0.5
	var lm := (l0 + l1) * 0.5
	walls.tri(MeshKit.v3(f0, y1), MeshKit.v3(f1, y1), MeshKit.v3(fm, peak), o3)
	if detail:
		# A cornice along the top of the entablature, and raking cornices
		# up both slopes of the pediment, so it has deep edges and shadow.
		_cornice(walls, f0, f1, out, y1, trim)
		for side: float in [-1.0, 1.0]:
			var e: Vector2 = f0 if side < 0.0 else f1
			# A sloped beam from the eave corner up to the peak, standing
			# 0.45 m proud of the tympanum.
			var a_lo := MeshKit.v3(e + out * 0.45 - t * side * 0.25, y1 - 0.05)
			var a_hi := MeshKit.v3(fm + out * 0.45, peak + 0.05)
			var up := Vector3(0, 0.4, 0)
			var back := Vector3(out.x, 0, out.y) * -0.5
			var n_front := Vector3(out.x, 0, out.y)
			var n_top := (a_hi - a_lo).cross(Vector3(t.x, 0, t.y) * side).normalized()
			if n_top.y < 0.0:
				n_top = -n_top
			walls.quad(a_lo, a_hi, a_hi + up, a_lo + up, n_front)
			walls.quad(a_lo + up, a_hi + up, a_hi + up + back, a_lo + up + back, n_top)
			walls.quad(a_lo, a_hi, a_hi + back, a_lo + back, -n_top)
	walls.color = save_c
	walls.uv2 = save_uv
	var save_r := roof.color
	roof.color = _vertex_color(roof_color, 0.0)
	roof.uv2 = Vector2.ZERO
	for side: float in [-1.0, 1.0]:
		var e_front := f0 if side < 0.0 else f1
		var e_back := l0 if side < 0.0 else l1
		var a := MeshKit.v3(e_front, y1)
		var b := MeshKit.v3(e_back, y1)
		var cp := MeshKit.v3(lm, peak)
		var d := MeshKit.v3(fm, peak)
		var n := (b - a).cross(d - a).normalized()
		if n.y < 0.0:
			n = -n
		roof.quad(a, b, cp, d, n)
	roof.color = save_r
	return faces


## An eight-sided column, also returned as collision faces.
func _column(walls: MeshKit, c: Vector2, r: float, h: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var a1 := TAU * float(i + 1) / 8.0
		var q0 := c + Vector2(cos(a0), sin(a0)) * r
		var q1 := c + Vector2(cos(a1), sin(a1)) * r
		var mid := (q0 + q1) * 0.5 - c
		walls.wall(q0, q1, _base, h, Vector3(mid.x, 0.0, mid.y).normalized())
		faces.append_array(_quad_faces(q0, q1, _base, h))
	return faces


# --- footprint helpers ---------------------------------------------------------------------

static func _clean_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.05:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 0.05:
		out.remove_at(out.size() - 1)
	return out


static func _signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Smallest-area oriented rectangle around the footprint.
## Returns {center, u, v, half_u, half_v, area} with u along the longer side.
static func _obb(ring: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(ring)
	var best := {"area": INF}
	for i in range(hull.size() - 1):
		var edge := hull[i + 1] - hull[i]
		if edge.length() < 0.01:
			continue
		var u := edge.normalized()
		var v := Vector2(-u.y, u.x)
		var min_u := INF
		var max_u := -INF
		var min_v := INF
		var max_v := -INF
		for p in hull:
			min_u = minf(min_u, p.dot(u))
			max_u = maxf(max_u, p.dot(u))
			min_v = minf(min_v, p.dot(v))
			max_v = maxf(max_v, p.dot(v))
		var area := (max_u - min_u) * (max_v - min_v)
		if area < float(best["area"]):
			var center := u * (min_u + max_u) * 0.5 + v * (min_v + max_v) * 0.5
			best = {"area": area, "center": center, "u": u, "v": v,
				"half_u": (max_u - min_u) * 0.5, "half_v": (max_v - min_v) * 0.5}
	if not best.has("u"):
		return {"area": 1.0, "center": ring[0], "u": Vector2.RIGHT, "v": Vector2.DOWN, "half_u": 0.5, "half_v": 0.5}
	if float(best["half_v"]) > float(best["half_u"]):
		var hu: float = best["half_u"]
		best["half_u"] = best["half_v"]
		best["half_v"] = hu
		var u2: Vector2 = best["u"]
		best["u"] = best["v"]
		best["v"] = u2
	return best

class_name BuildingGenerator
extends RefCounted
## Extrudes OSM building footprints into simple buildings.
##
## The footprint is always the real OSM outline. Height comes from the OSM
## `height` or `building:levels` tags when mapped, otherwise from the building
## type plus a little variety. Style follows type: brick blocks with
## shopfronts for commercial buildings, clapboard and gable roofs for houses,
## sandstone for churches and public buildings, which is what downtown
## Charlottetown mostly looks like. Every choice is seeded by the OSM id, so
## the town looks the same every time it is built.

const FLOOR_H := 3.2
const BAY_W := 2.6
const OVERHANG := 0.35

enum Style { BRICK, CLAPBOARD, SANDSTONE, RENDER }

const SKIP_TYPES := ["roof", "carport", "construction", "ruins", "no"]
const HOUSE_TYPES := ["house", "detached", "semidetached_house", "terrace", "bungalow", "cabin", "residential"]
const SMALL_TYPES := ["shed", "garage", "garages", "hut", "kiosk"]
const SHOP_TYPES := ["commercial", "retail", "kiosk", "supermarket"]
const CIVIC_TYPES := ["church", "cathedral", "chapel", "public", "civic", "government", "school", "college", "university", "train_station", "hall"]

const BRICK := [Color(0.55, 0.25, 0.18), Color(0.6, 0.31, 0.21), Color(0.47, 0.22, 0.17), Color(0.63, 0.37, 0.26), Color(0.52, 0.31, 0.25), Color(0.42, 0.24, 0.2)]
const CLAPBOARD := [Color(0.92, 0.91, 0.86), Color(0.93, 0.87, 0.7), Color(0.93, 0.82, 0.5), Color(0.6, 0.68, 0.56), Color(0.5, 0.6, 0.68), Color(0.62, 0.24, 0.19), Color(0.72, 0.72, 0.69), Color(0.4, 0.58, 0.58), Color(0.86, 0.9, 0.93)]
const SANDSTONE := [Color(0.66, 0.44, 0.34), Color(0.7, 0.5, 0.39), Color(0.72, 0.68, 0.6)]
const RENDER := [Color(0.83, 0.79, 0.7), Color(0.71, 0.73, 0.74), Color(0.78, 0.72, 0.62)]
const FLAT_ROOF := [Color(0.24, 0.24, 0.25), Color(0.3, 0.3, 0.3), Color(0.35, 0.34, 0.32)]
const PITCHED_ROOF := [Color(0.22, 0.22, 0.24), Color(0.3, 0.25, 0.21), Color(0.21, 0.29, 0.25), Color(0.35, 0.2, 0.16), Color(0.16, 0.16, 0.17), Color(0.32, 0.33, 0.36)]

var data: StreetData


func _init(street_data: StreetData) -> void:
	data = street_data


## Adds one StaticBody3D per building under `parent`. Returns how many.
func build(parent: Node3D) -> int:
	var count := 0
	for b in data.buildings:
		var node := _make(b)
		if node != null:
			parent.add_child(node)
			count += 1
	return count


func _make(b: StreetData.Building) -> Node3D:
	var btype := str(b.tags.get("building", "yes"))
	if SKIP_TYPES.has(btype):
		return null
	var ring := _clean_ring(b.ring)
	if ring.size() < 3:
		return null
	var area := _signed_area(ring)
	if absf(area) < 6.0:
		return null
	if area < 0.0:
		ring.reverse()
		area = -area

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.id)
	var spec := _spec(b, btype, area, rng)
	var wall_h: float = spec["wall_h"]
	var style: int = spec["style"]

	var walls := MeshKit.new()
	walls.use_color = true
	walls.use_uv2 = true
	var roof := MeshKit.new()
	roof.use_color = true
	roof.use_uv2 = true

	var floors := floorf((wall_h - 0.3) / FLOOR_H)
	walls.color = _vertex_color(spec["wall_color"], floors)
	walls.uv2 = Vector2(style, 1.0 if spec["shop"] else 0.0)
	var flat: bool = not spec["gable"]
	var top := wall_h + (0.5 if flat and style != Style.CLAPBOARD else 0.0) # parapet on flat roofs

	var collision := PackedVector3Array()
	for i in ring.size():
		var p0 := ring[i]
		var p1 := ring[(i + 1) % ring.size()]
		var seg := p0.distance_to(p1)
		if seg < 0.05:
			continue
		var t := (p1 - p0) / seg
		var out := Vector3(t.y, 0.0, -t.x)
		_wall(walls, p0, p1, -0.1, top, out, seg)
		if top > wall_h:
			# Inside face of the parapet, no windows.
			var save := walls.color
			walls.color = _vertex_color(spec["wall_color"], 0.0)
			walls.wall(p0, p1, wall_h, top, -out)
			walls.color = save
		collision.append_array(_quad_faces(p0, p1, 0.0, wall_h))

	roof.color = _vertex_color(spec["roof_color"], 1.0)
	if spec["gable"]:
		_gable_roof(walls, roof, spec, rng)
	else:
		roof.uv2 = Vector2.ZERO
		_flat_roof(roof, ring, wall_h)

	var mesh := walls.commit(null, Materials.get_shared().building_walls)
	roof.commit(mesh, Materials.get_shared().building_roofs)

	var body := StaticBody3D.new()
	body.name = "Building_%s" % b.id
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(collision)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.set_meta("fade_mesh", mi)
	body.set_meta("osm_id", b.id)
	return body


# --- what kind of building is this? -------------------------------------------------------

func _spec(b: StreetData.Building, btype: String, area: float, rng: RandomNumberGenerator) -> Dictionary:
	var tags := b.tags
	var is_house := HOUSE_TYPES.has(btype)
	var is_small := SMALL_TYPES.has(btype)
	var is_civic := CIVIC_TYPES.has(btype) or tags.has("historic")
	var is_shop := SHOP_TYPES.has(btype) or tags.has("shop") or tags.has("amenity") or tags.has("office")
	if btype == "yes" and not is_shop and not is_civic:
		is_house = area < 170.0 and rng.randf() < 0.65
		is_shop = not is_house and rng.randf() < 0.6

	var style := Style.BRICK
	var levels := 2.0
	if is_small:
		style = Style.CLAPBOARD
		levels = 1.0
	elif is_house:
		style = Style.CLAPBOARD
		levels = 2.0 if rng.randf() < 0.75 else 1.5
	elif is_civic:
		style = Style.SANDSTONE
		levels = float(rng.randi_range(2, 4))
	elif btype == "apartments":
		style = Style.BRICK if rng.randf() < 0.6 else Style.RENDER
		levels = float(rng.randi_range(3, 5))
	else:
		style = Style.BRICK if rng.randf() < 0.8 else Style.RENDER
		levels = float(rng.randi_range(2, 3))

	var material := str(tags.get("building:material", ""))
	match material:
		"brick":
			style = Style.BRICK
		"wood":
			style = Style.CLAPBOARD
		"stone", "sandstone":
			style = Style.SANDSTONE
		"plaster", "concrete":
			style = Style.RENDER

	var tagged_levels := str(tags.get("building:levels", "")).to_float()
	if tagged_levels > 0.0:
		levels = tagged_levels
	var wall_h := levels * FLOOR_H + 0.3
	var tagged_h := str(tags.get("height", "")).to_float()

	var roof_shape := str(tags.get("roof:shape", ""))
	var gable := false
	if roof_shape == "gabled" or roof_shape == "hipped" or roof_shape == "gambrel":
		gable = true
	elif roof_shape == "" and (is_house or is_small):
		gable = true
	var obb := _obb(b.ring)
	if gable:
		# Only put a simple gable on footprints that are close to a rectangle.
		var fill := area / maxf(obb["area"], 0.01)
		var span: float = obb["half_v"] * 2.0
		gable = fill > 0.8 and span < 16.0
	if tagged_h > 0.0:
		wall_h = tagged_h
		if gable:
			wall_h = maxf(2.5, tagged_h - float(obb["half_v"]) * tan(deg_to_rad(35.0)))

	var palette: Array = BRICK
	match style:
		Style.CLAPBOARD:
			palette = CLAPBOARD
		Style.SANDSTONE:
			palette = SANDSTONE
		Style.RENDER:
			palette = RENDER
	var wall_color: Color = palette[rng.randi() % palette.size()]
	wall_color = Color.from_string(str(tags.get("building:colour", "")), wall_color)
	var roof_palette: Array = PITCHED_ROOF if gable else FLAT_ROOF
	var roof_color: Color = roof_palette[rng.randi() % roof_palette.size()]
	roof_color = Color.from_string(str(tags.get("roof:colour", "")), roof_color)

	return {
		"style": style, "wall_h": wall_h, "shop": is_shop and not is_house,
		"gable": gable, "obb": obb, "wall_color": wall_color, "roof_color": roof_color,
	}


static func _vertex_color(c: Color, floors: float) -> Color:
	var lin := c.srgb_to_linear()
	return Color(lin.r, lin.g, lin.b, clampf(floors, 0.0, 16.0) / 16.0)


# --- walls ------------------------------------------------------------------------------------

## A wall with whole window bays stretched to fit its length.
func _wall(kit: MeshKit, p0: Vector2, p1: Vector2, y0: float, y1: float, n: Vector3, seg: float) -> void:
	var bays := roundf(seg / BAY_W)
	var u0 := 0.0
	var u1 := bays
	if seg < 1.8 or bays < 1.0:
		u0 = -100.0 # too narrow for a window
		u1 = -100.0 + seg / BAY_W
	kit.quad(MeshKit.v3(p0, y0), MeshKit.v3(p1, y0), MeshKit.v3(p1, y1), MeshKit.v3(p0, y1), n,
		Vector2(u0, y0), Vector2(u1, y0), Vector2(u1, y1), Vector2(u0, y1))


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
		# Self-intersecting outline: fall back to its convex hull.
		var hull := Geometry2D.convex_hull(ring)
		for i in range(1, hull.size() - 2):
			kit.ground_tri(MeshKit.v3(hull[0], h), MeshKit.v3(hull[i], h), MeshKit.v3(hull[i + 1], h))
		return
	for i in range(0, idx.size(), 3):
		kit.ground_tri(MeshKit.v3(ring[idx[i]], h), MeshKit.v3(ring[idx[i + 1]], h), MeshKit.v3(ring[idx[i + 2]], h))


## Gable roof over the footprint's oriented bounding box, ridge along the long side.
func _gable_roof(walls: MeshKit, roof: MeshKit, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var obb: Dictionary = spec["obb"]
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var v: Vector2 = obb["v"]
	var hu: float = obb["half_u"]
	var hv: float = obb["half_v"]
	var eave: float = spec["wall_h"]
	var slope := tan(deg_to_rad(rng.randf_range(30.0, 42.0)))
	var ridge := eave + hv * slope
	var low := eave - OVERHANG * slope
	roof.uv2 = Vector2(1.0, 0.0)
	var run := (hv + OVERHANG) * sqrt(1.0 + slope * slope)
	for s: float in [1.0, -1.0]:
		var a := MeshKit.v3(c + u * (hu + OVERHANG) + v * (hv + OVERHANG) * s, low)
		var b := MeshKit.v3(c - u * (hu + OVERHANG) + v * (hv + OVERHANG) * s, low)
		var top_b := MeshKit.v3(c - u * (hu + OVERHANG), ridge)
		var top_a := MeshKit.v3(c + u * (hu + OVERHANG), ridge)
		var n := (b - a).cross(top_a - a).normalized()
		if n.y < 0.0:
			n = -n
		roof.quad(a, b, top_b, top_a, n, Vector2(0, 0), Vector2(hu * 2.0, 0), Vector2(hu * 2.0, run), Vector2(0, run))
	# Gable ends: triangles of wall up to the ridge, no windows.
	var save := walls.color
	walls.color = Color(save.r, save.g, save.b, 0.0)
	for s: float in [1.0, -1.0]:
		var end_c: Vector2 = c + u * hu * s
		var p_l := MeshKit.v3(end_c + v * hv, eave)
		var p_r := MeshKit.v3(end_c - v * hv, eave)
		var p_t := MeshKit.v3(end_c, ridge)
		var n := Vector3(u.x * s, 0.0, u.y * s)
		walls.tri(p_l, p_r, p_t, n, Vector2(-100.0, eave), Vector2(-100.0 + hv * 2.0 / BAY_W, eave), Vector2(-100.0 + hv / BAY_W, ridge))
	walls.color = save


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

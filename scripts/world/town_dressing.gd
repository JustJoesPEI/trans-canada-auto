class_name TownDressing
extends RefCounted
## The things the map doesn't place one by one but every street has: what
## stands in people's yards, and the furniture of the places OSM only
## outlines. Worked out per full-detail chunk by StreetProps, seeded by the
## building or area, so the same yard has the same shed every time; drawn
## by PlacedProps (props) and EditLines (fences and hedges), so nothing here
## makes a mesh or a material of its own.
##
## * Yards: every ordinary house gets what its neighbourhood's houses have
##   (map_config.json "yards": a profile per neighbourhood, "downtown" and
##   "default"): a front fence or hedge on the lot line with gaps for the
##   walk and the driveway, a back fence round the back yard, a shed, a
##   trampoline, chairs round a fire pit, the Waste Watch cart (and its blue
##   bags) out by the driveway, a mailbox on a post at the road.
## * OSM points the map has but nothing drew: benches, post boxes, litter
##   bins (amenity=bench, post_box, waste_basket), turned to the nearest
##   street, unless a placed prop of the kind is already there.
## * OSM areas: playgrounds get a play structure, swings and a bench;
##   pitches their goals, hoops, net and fence or backstop by sport;
##   outdoor seating (patios) tables and umbrellas; cemeteries rows of
##   headstones.

## OSM points drawn as props: type -> prop kind.
const OSM_POINTS := {"amenity=bench": "bench", "amenity=post_box": "post_box", "amenity=waste_basket": "waste_basket"}
## A placed prop this close (m) to an OSM point of its kind is the same one.
const SAME_SPOT := 4.0
## Front fence heights by kind (m); EditLines' own default for the rest.
const FRONT_HEIGHT := {"hedge": 1.1, "picket_fence": 0.95, "chain_link": 1.2, "split_rail": 1.0, "stone_wall": 0.6, "wood_fence": 1.2}
## Kinds generated in numbers too great to give each a collision shape
## (a cemetery's headstones), or too small to stop a car (a lawn chair).
const GHOSTS := ["headstone", "headstone_dark", "marble_tablet", "lawn_chair", "flowers"]

var props: StreetProps
## Prop kind -> Array of [Transform3D, solid].
var placed: Dictionary = {}
## Lines for EditLines, in its own form: {kind, pts (ground), height, own}.
var lines: Array[Dictionary] = []
## Paint on the ground, coloured per vertex: court surfaces and their
## lines, a ball diamond's red clay (StreetProps draws it as one mesh).
var paint := MeshKit.new()
## Floating docks in the marinas (vertex-coloured), and their decks for
## collision (you can walk out on them).
var docks := MeshKit.new()
var dock_faces := PackedVector3Array()

static var _hoods: Array = [] ## [centre (ground), radius, yards profile]
static var _hoods_ready := false
static var _hoods_lock := Mutex.new()


func _init(owner: StreetProps) -> void:
	props = owner
	paint.use_color = true
	docks.use_color = true


func build() -> void:
	_osm_points()
	_areas()
	_yards()
	_sidewalk_boards()
	_schools()
	_store_lots()
	_mailbox_banks()
	if not ChunkBuilder.server_build():
		_lot_curbs()
		_minor_ways()


# --- helpers -----------------------------------------------------------------------------

func _put(kind: String, p: Vector2, facing: Vector2, scale := Vector3.ONE, lift := 0.0) -> void:
	if kind in GHOSTS and ChunkBuilder.server_build():
		return # nothing to collide with, and a server draws nothing
	var at := props.terrain.at(p, 0.0) + Vector3.UP * lift
	var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y)).scaled(scale)
	if not placed.has(kind):
		placed[kind] = []
	placed[kind].append([Transform3D(basis, at), kind not in GHOSTS])


func _line(kind: String, pts: PackedVector2Array, height := -1.0) -> void:
	if pts.size() < 2:
		return
	var h := height if height > 0.0 else float(EditLines.KINDS.get(kind, 1.0))
	lines.append({"kind": kind, "pts": pts, "height": h, "own": true})


## The way from p to the nearest street (unit), or ZERO with none in reach.
func _to_street(p: Vector2, reach := 60.0) -> Vector2:
	var hit := props.net.nearest_on_streets(p, reach)
	if hit.is_empty():
		return Vector2.ZERO
	var d: Vector2 = (hit["pos"] as Vector2) - p
	return d.normalized() if d.length() > 0.01 else Vector2.ZERO


func _clear(p: Vector2, pad: float) -> bool:
	return not props._on_road(p, pad) and not _near_building(p, pad)


## Within pad of a footprint, by its outline (StreetProps._in_building
## tests the box round it, which on a street at 45 degrees covers the street).
## Near the chunk's edge the next chunk's buildings count too: a headstone
## or a fence mustn't run into a building whose middle is over the line.
## The footprints are filed in a grid of CELL-metre squares as they're
## first needed, so a test looks at the few buildings round it.
func _near_building(p: Vector2, pad: float) -> bool:
	if _grid.is_empty():
		_file(props.chunk.buildings)
	var r := props.rect
	var edge := EDGE_REACH + pad
	if not (p.x - r.position.x > edge and r.end.x - p.x > edge and p.y - r.position.y > edge and r.end.y - p.y > edge):
		var size := props.data.chunk_size
		var c := Vector2i(floori(r.position.x / size), floori(r.position.y / size))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := Vector2i(c.x + dx, c.y + dz)
				if (dx != 0 or dz != 0) and not _filed.has(k) and Rect2(r.position + Vector2(dx, dz) * size, r.size).grow(edge).has_point(p):
					_filed[k] = true
					_file(_neighbour(k.x, k.y))
	var seen := {}
	var c0 := Vector2i(floori((p.x - pad) / CELL), floori((p.y - pad) / CELL))
	var c1 := Vector2i(floori((p.x + pad) / CELL), floori((p.y + pad) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for i: int in _grid.get(Vector2i(cx, cz), []):
				if seen.has(i):
					continue
				seen[i] = true
				var box: Rect2 = _boxes[i]
				if not box.grow(pad).has_point(p):
					continue
				var ring: PackedVector2Array = _rings[i]
				if Geometry2D.is_point_in_polygon(p, ring):
					return true
				if pad > 0.0:
					for j in ring.size():
						var q := Geometry2D.get_closest_point_to_segment(p, ring[j], ring[(j + 1) % ring.size()])
						if q.distance_squared_to(p) < pad * pad:
							return true
	return false


const CELL := 16.0
## How far from its own chunk a building can reach (m).
const EDGE_REACH := 35.0
const NEIGHBOUR_CACHE := 48
static var _neighbours: Dictionary = {} ## Vector2i -> Array of StreetData.Building
static var _neighbour_order: Array = []
static var _neighbour_lock := Mutex.new()
var _grid: Dictionary = {} ## cell -> Array of indices into _rings
var _rings: Array[PackedVector2Array] = []
var _boxes: Array[Rect2] = []
var _filed: Dictionary = {} ## neighbouring chunks already filed


func _file(buildings: Array) -> void:
	for b: StreetData.Building in buildings:
		if b.ring.size() < 3:
			continue
		var box := Rect2(b.ring[0], Vector2.ZERO)
		for q in b.ring:
			box = box.expand(q)
		var i := _rings.size()
		_rings.append(b.ring)
		_boxes.append(box)
		for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not _grid.has(k):
					_grid[k] = []
				_grid[k].append(i)
	if _grid.is_empty():
		_grid[Vector2i(1 << 20, 0)] = [] # filed, even if there was nothing to file


func _neighbour(cx: int, cz: int) -> Array:
	var key := Vector2i(cx, cz)
	_neighbour_lock.lock()
	var got: Variant = _neighbours.get(key)
	_neighbour_lock.unlock()
	if got != null:
		return got
	var list: Array = props.data.load_chunk(cx, cz).buildings
	_neighbour_lock.lock()
	_neighbours[key] = list
	_neighbour_order.append(key)
	if _neighbour_order.size() > NEIGHBOUR_CACHE:
		_neighbours.erase(_neighbour_order.pop_front())
	_neighbour_lock.unlock()
	return list


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	if total <= 0.0:
		return "none"
	var r := rng.randf() * total
	for k: String in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return "none"


# --- OSM points --------------------------------------------------------------------------

func _osm_points() -> void:
	var placed_spots: Dictionary = {} ## kind -> Array of positions placed by hand
	for p in props.chunk.points:
		if p.type.begins_with("prop="):
			var k := p.type.substr(5)
			if not placed_spots.has(k):
				placed_spots[k] = []
			placed_spots[k].append(p.pos)
	for p in props.chunk.points:
		var kind: String = OSM_POINTS.get(p.type, "")
		if kind == "" or not props._inside(p.pos) or props.data.erased(p.pos):
			continue
		var dup := false
		for q: Vector2 in placed_spots.get(kind, []):
			if q.distance_to(p.pos) < SAME_SPOT:
				dup = true
				break
		if dup or props._on_road(p.pos, 0.0):
			continue
		var f := _to_street(p.pos)
		if f == Vector2.ZERO:
			f = Vector2(0, -1)
		# A bench looks out at the street; a post box's slot faces it.
		_put(kind, p.pos, f)


# --- areas -------------------------------------------------------------------------------

func _areas() -> void:
	for a in props.chunk.areas:
		match a.type:
			"leisure=playground":
				_playground(a)
			"leisure=pitch":
				_pitch(a)
			"leisure=outdoor_seating":
				_patio(a)
			"landuse=cemetery":
				_cemetery(a)
			"landuse=flowerbed", "leisure=garden":
				_flower_bed(a)
			"leisure=marina":
				_marina(a)


## The area's box: {center, u, v, half_u, half_v}, u the long way.
static func _box_of(ring: PackedVector2Array) -> Dictionary:
	var obb := BuildingGenerator._obb(ring)
	if obb.is_empty():
		return {}
	if float(obb["half_v"]) > float(obb["half_u"]):
		return {"center": obb["center"], "u": obb["v"], "v": obb["u"], "half_u": obb["half_v"], "half_v": obb["half_u"]}
	return obb


func _playground(a: StreetData.GroundArea) -> void:
	var box := _box_of(a.ring)
	if box.is_empty():
		return
	var c: Vector2 = box["center"]
	var u: Vector2 = box["u"]
	var v: Vector2 = box["v"]
	var hu: float = box["half_u"]
	var hv: float = box["half_v"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a.id)
	var spots: Array = [] ## [kind, position, facing]
	if hu < 3.0:
		spots.append(["playground", c, v])
	else:
		# The structure at one end, the swings at the other, a bench on the
		# long side looking in.
		spots.append(["playground", c - u * minf(hu * 0.45, 5.0), v])
		spots.append(["swing_set", c + u * minf(hu * 0.5, 6.0), v])
		if hv > 3.5:
			spots.append(["bench", c + v * (hv - 1.0), -v])
		if hu > 12.0:
			spots.append(["waste_basket", c + v * (hv - 1.0) + u * 2.0, -v])
	for s: Array in spots:
		var p: Vector2 = s[1]
		if props._inside(p) and Geometry2D.is_point_in_polygon(p, a.ring) and _clear(p, 0.5):
			_put(s[0], p, s[2])


func _pitch(a: StreetData.GroundArea) -> void:
	var box := _box_of(a.ring)
	if box.is_empty():
		return
	var c: Vector2 = box["center"]
	var u: Vector2 = box["u"]
	var v: Vector2 = box["v"]
	var hu: float = box["half_u"]
	var hv: float = box["half_v"]
	var sport := str(a.tags.get("sport", ""))
	if sport.begins_with("soccer") or sport == "rugby_union" or sport == "multi" and hu > 25.0:
		if hu < 12.0:
			return
		_soccer_paint(c, u, v, hu, hv)
		for s: float in [-1.0, 1.0]:
			var p := c + u * s * (hu - 0.6)
			if props._inside(p) and not props._on_road(p, 0.5):
				# The goal's mouth faces up the pitch.
				_put("soccer_goal", p, -u * s, Vector3.ONE * (1.0 if hu > 40.0 else 0.75))
	elif sport == "basketball":
		if hu < 5.0:
			return
		var ends: Array = [-1.0, 1.0] if hu > 10.0 else [1.0]
		_basketball_paint(c, u, v, hu, hv, ends, str(a.tags.get("surface", "asphalt")) in ["asphalt", "concrete", "paved", ""])
		for s: float in ends:
			var p := c + u * s * (hu - 0.4)
			if props._inside(p) and not props._on_road(p, 0.5):
				_put("basketball_hoop", p, -u * s)
	elif sport == "tennis":
		if hu < 8.0:
			return
		# A court or a row of them side by side, a net across each, and
		# the tall chain link round the lot.
		var courts := maxi(1, int(round(hv * 2.0 / 18.0)))
		_tennis_paint(c, u, v, hu, hv, courts)
		for k in courts:
			var off := (-hv + hv * 2.0 * (k + 0.5) / courts)
			var p := c + v * off
			if props._inside(p):
				_put("tennis_net", p, u)
		if props._inside(c):
			var ring := BuildingGenerator._offset_ring(_ccw(a.ring), -0.3)
			if not ring.is_empty():
				var pts := ring.duplicate()
				pts.append(ring[0])
				_line("chain_link", pts, 3.0)
	elif sport in ["baseball", "softball"]:
		_diamond(a, c, hu)


## A ball diamond's backstop: chain link in a curve behind home plate, the
## sharpest corner of the outline (a diamond is drawn as a fan from it),
## with a players' bench down each line.
func _diamond(a: StreetData.GroundArea, c: Vector2, hu: float) -> void:
	if hu < 15.0:
		return
	var ring := a.ring
	var best := -1
	var best_cos := -2.0
	for i in ring.size():
		var p := ring[i]
		var d0 := (ring[(i - 1 + ring.size()) % ring.size()] - p).normalized()
		var d1 := (ring[(i + 1) % ring.size()] - p).normalized()
		var cs := d0.dot(d1)
		if cs > best_cos:
			best_cos = cs
			best = i
	var home := ring[best]
	if not props._inside(home):
		return
	var out := (home - c).normalized()
	var side := Vector2(-out.y, out.x)
	_diamond_paint(home, -out, hu * 2.0)
	var pts := PackedVector2Array()
	var behind := home + out * 4.0
	for k in 7:
		var ang := lerpf(-1.1, 1.1, k / 6.0)
		pts.append(behind - out * 4.0 + (out * cos(ang) + side * sin(ang)) * 6.0)
	_line("chain_link", pts, 3.6)
	for s: float in [-1.0, 1.0]:
		var p := home - out * 6.0 + side * s * 9.0
		if _clear(p, 0.5):
			_put("bench", p, side * -s)


func _patio(a: StreetData.GroundArea) -> void:
	var box := _box_of(a.ring)
	if box.is_empty():
		return
	var c: Vector2 = box["center"]
	var u: Vector2 = box["u"]
	var v: Vector2 = box["v"]
	var hu: float = box["half_u"]
	var hv: float = box["half_v"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a.id)
	# A patio built out over the street (Victoria Row's) stands on the road.
	var on_street := str(a.tags.get("on_street", "")) == "yes"
	if on_street:
		_patio_rail(a)
	var step := 2.8
	var nu := maxi(1, int(hu * 2.0 / step))
	var nv := maxi(1, int(hv * 2.0 / step))
	var count := 0
	for i in nu:
		for j in nv:
			if count >= 24:
				return
			var p := c + u * (-hu + (i + 0.5) * hu * 2.0 / nu) + v * (-hv + (j + 0.5) * hv * 2.0 / nv)
			if not props._inside(p) or not Geometry2D.is_point_in_polygon(p, a.ring):
				continue
			if _near_building(p, 0.6) or (not on_street and props._on_road(p, 0.6)):
				continue
			var kind := "patio_set" if rng.randf() < 0.6 else "patio_table"
			_put(kind, p, u.rotated(rng.randf_range(-0.3, 0.3)))
			count += 1


## Rows of headstones on the cemetery's long axis, each facing the way
## the row does, with the gaps and odd ones out a real one has.
func _cemetery(a: StreetData.GroundArea) -> void:
	var box := _box_of(a.ring)
	if box.is_empty():
		return
	var c: Vector2 = box["center"]
	var u: Vector2 = box["u"]
	var v: Vector2 = box["v"]
	var hu: float = box["half_u"]
	var hv: float = box["half_v"]
	var old := str(a.tags.get("name", "")).contains("Old") or str(a.tags.get("name", "")).contains("Burying")
	var along := 1.9 # metres between stones in a row
	var across := 3.4 # between rows
	# Only the part of the box in this chunk.
	var r := props.rect.grow(1.0)
	var rng := RandomNumberGenerator.new()
	var j := -hv + across * 0.5
	while j < hv:
		var i := -hu + along * 0.5
		while i < hu:
			var p := c + u * i + v * j
			if r.has_point(p):
				rng.seed = hash(Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0)))
				var gap := rng.randf() < (0.35 if old else 0.2)
				# A path every eighth row and every 25 stones.
				var path := posmod(int(round((j + hv) / across)), 8) == 7 or posmod(int(round((i + hu) / along)), 25) == 24
				if not gap and not path and props._inside(p) and Geometry2D.is_point_in_polygon(p, a.ring) and _clear(p, 1.2):
					var q := p + u * rng.randf_range(-0.15, 0.15) + v * rng.randf_range(-0.2, 0.2)
					var pick := rng.randf()
					var kind := "headstone"
					if old:
						kind = "marble_tablet" if pick < 0.7 else "headstone"
					elif pick < 0.3:
						kind = "headstone_dark"
					var s := Vector3(rng.randf_range(0.8, 1.25), rng.randf_range(0.75, 1.3), 1.0)
					var face := v.rotated(rng.randf_range(-0.06, 0.06) + (rng.randf_range(-0.12, 0.12) if old else 0.0))
					_put(kind, q, face, s)
			i += along
		j += across


static func _ccw(ring: PackedVector2Array) -> PackedVector2Array:
	if BuildingGenerator._signed_area(ring) < 0.0:
		var r := ring.duplicate()
		r.reverse()
		return r
	return ring


# --- yards -------------------------------------------------------------------------------

static func _load_hoods(data: StreetData) -> void:
	_hoods_lock.lock()
	if not _hoods_ready:
		var proj := GeoProjection.new(float(data.config["origin"]["lat"]), float(data.config["origin"]["lon"]))
		var hoods: Dictionary = data.config.get("neighbourhoods", {})
		for k: String in hoods:
			var h: Variant = hoods[k]
			if not (h is Dictionary) or not (h as Dictionary).has("yards"):
				continue
			var at: Array = h["centre"]
			_hoods.append([proj.to_ground(float(at[1]), float(at[0])), float(h.get("radius_m", 500.0)), h["yards"]])
		_hoods_ready = true
	_hoods_lock.unlock()


## The yard profile for a house at p: its neighbourhood's (the nearest
## centre in reach), downtown's, or the town's default.
func _profile_at(p: Vector2) -> Dictionary:
	_load_hoods(props.data)
	var cfg: Dictionary = props.data.config.get("yards", {})
	if p.length() < float(props.data.config.get("heritage_district_m", 900.0)) and cfg.has("downtown"):
		return cfg["downtown"]
	var best: Dictionary = cfg.get("default", {})
	var best_d := INF
	for h: Array in _hoods:
		var d := p.distance_to(h[0])
		if d < float(h[1]) and d < best_d:
			best_d = d
			best = h[2]
	return best


## A house the way BuildingGenerator tells one: tagged as one, or an
## untagged footprint of house size that the lidar doesn't show standing
## over two storeys, with no shop or office in it.
func _is_house(b: StreetData.Building) -> bool:
	# A researched building is what its entry says, not a house to guess at.
	if (props.data.config.get("landmarks", {}) as Dictionary).has(b.id):
		return false
	var t := str(b.tags.get("building", ""))
	var area := absf(BuildingGenerator._signed_area(b.ring))
	if t in BuildingGenerator.HOUSE_TYPES:
		return area < 320.0
	if t != "yes" or b.tags.has("shop") or b.tags.has("office") or b.tags.has("amenity") or b.tags.has("name"):
		return false
	return area > 45.0 and area < 260.0 and float(b.tags.get("lidar_top", 0.0)) < 10.5


func _yards() -> void:
	if props.data.config.get("yards", {}).is_empty():
		return
	for b in props.chunk.buildings:
		if b.ring.size() < 3 or not _is_house(b):
			continue
		var c := BuildingGenerator._centre(b.ring)
		if not props._inside(c):
			continue
		var prof := _profile_at(c)
		if prof.is_empty():
			continue
		_yard(b, c, prof)


func _yard(b: StreetData.Building, c: Vector2, prof: Dictionary) -> void:
	var hit := props.net.nearest_on_streets(c, 45.0)
	if hit.is_empty():
		return
	var e: RoadNetwork.RoadEdge = hit["edge"]
	if e.is_highway() or e.highway in ["service", "track", "footway", "path", "cycleway", "pedestrian"]:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.id)
	var pos: Vector2 = hit["pos"]
	var t: Vector2 = hit["dir"]
	var right := Vector2(-t.y, t.x)
	var side := 1 if (c - pos).dot(right) > 0.0 else -1
	var n := right * float(side) # from the street to the house
	# The house in the street's frame: along it (t) and back from it (n).
	var t0 := INF
	var t1 := -INF
	var s0 := INF
	var s1 := -INF
	for q in b.ring:
		var d := q - pos
		t0 = minf(t0, d.dot(t))
		t1 = maxf(t1, d.dot(t))
		s0 = minf(s0, d.dot(n))
		s1 = maxf(s1, d.dot(n))
	if t1 - t0 > 30.0 or s1 - s0 > 30.0:
		return
	# The lot line: behind the sidewalk, or past the ditch where there's none
	# (the wider side's, as _on_road measures it).
	var walk := maxf(e.walk(1), e.walk(-1))
	var lot := e.half_width + (walk + 0.4 if walk > 0.0 else 2.4)
	var at := func(tt: float, ss: float) -> Vector2: return pos + t * tt + n * ss
	# Which side the driveway is on: the side with room, else either.
	var drive := 1.0 if rng.randf() < 0.5 else -1.0
	if not _clear(at.call(t1 + 2.0 if drive > 0.0 else t0 - 2.0, (s0 + lot) * 0.5), 0.3):
		drive = -drive
	var mid := (t0 + t1) * 0.5

	# The front: a fence or hedge on the lot line.
	var front_depth := s0 - lot
	if front_depth >= 3.0:
		var kind := _pick(rng, prof.get("front", {}))
		if kind != "none" and EditLines.KINDS.has(kind):
			var a := t0 - 1.5
			var z := t1 + 1.5
			if drive > 0.0:
				z = t1 + 0.2
			else:
				a = t0 - 0.2
			var y := lot + rng.randf_range(0.0, 0.3)
			var h := float(FRONT_HEIGHT.get(kind, -1.0))
			var gap := 0.65 if kind != "hedge" else 0.8
			var runs: Array = [[a, mid - gap], [mid + gap, z]]
			for run: Array in runs:
				_clear_runs(kind, [at.call(run[0], y), at.call(run[1], y)], h)
			# Picket and chain link come back to the house's front corners.
			if kind in ["picket_fence", "chain_link"]:
				var back := s0 + 0.6
				if drive > 0.0:
					_clear_runs(kind, [at.call(a, y), at.call(a, back)], h)
				else:
					_clear_runs(kind, [at.call(z, y), at.call(z, back)], h)

	# The carts out at the end of the driveway, and a mailbox on a post.
	var drive_t := (t1 + 1.9) if drive > 0.0 else (t0 - 1.9)
	if rng.randf() < float(prof.get("carts", 0.0)):
		var p: Vector2 = at.call(drive_t + drive * 1.4, lot + 0.5)
		if _clear(p, 0.4):
			# A whole street is on the same week: black cart and blue bags,
			# or the green cart.
			_put("compost_cart" if hash(e.name + str(e.highway)) % 2 == 0 else "waste_carts", p, -n)
	if walk <= 0.0 and front_depth >= 1.5 and rng.randf() < float(prof.get("mailbox_post", 0.0)):
		var p: Vector2 = at.call(drive_t - drive * 1.6, lot - 0.4)
		if not props._on_road(p, 0.3) and not _near_building(p, 0.5):
			_put("mailbox", p, -n)

	# The back yard: how deep it is before the next house, lane or street.
	var depth := 0.0
	while depth < 16.0:
		if not _clear(at.call(mid, s1 + depth + 1.5), 0.8):
			break
		depth += 2.0
	if depth < 6.0:
		return
	var yard_end := s1 + minf(depth - 0.5, rng.randf_range(8.0, 12.0))
	var back := _pick(rng, prof.get("back", {}))
	if back != "none" and EditLines.KINDS.has(back):
		var a := t0 - 1.0
		var z := t1 + 1.0
		_clear_runs(back, [at.call(a, s1 - 0.5), at.call(a, yard_end), at.call(z, yard_end), at.call(z, s1 - 0.5)],
			float(prof.get("back_height", -1.0)))
	var inner := yard_end - s1
	if rng.randf() < float(prof.get("shed", 0.0)):
		var st := (t0 + 1.7) if rng.randf() < 0.5 else (t1 - 1.7)
		var p: Vector2 = at.call(st, yard_end - 1.6)
		if _clear(p, 1.7):
			_put("shed", p, -n)
	if inner > 7.0 and rng.randf() < float(prof.get("trampoline", 0.0)):
		var p: Vector2 = at.call(mid + rng.randf_range(-1.5, 1.5), s1 + inner * 0.55)
		if _clear(p, 2.1):
			_put("trampoline", p, t)
	if rng.randf() < float(prof.get("fire_pit", 0.0)):
		var p: Vector2 = at.call(mid + (t1 - t0) * 0.25 * (1.0 if rng.randf() < 0.5 else -1.0), s1 + inner * 0.45)
		if _clear(p, 1.6):
			_put("fire_pit", p, t)
			for k in 2:
				var ang := (k - 0.5) * 1.6 + rng.randf_range(-0.2, 0.2)
				var off := (-n).rotated(ang) * 1.3
				_put("lawn_chair", p + off, -off)
	elif rng.randf() < float(prof.get("picnic_table", 0.0)):
		var p: Vector2 = at.call(mid, s1 + 2.5)
		if _clear(p, 1.2):
			_put("picnic_table", p, t)


## A line from point to point, split where it would run through a
## building, each clear run of a metre or more kept.
func _clear_runs(kind: String, pts: Array, height: float) -> void:
	var run := PackedVector2Array()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var steps := maxi(1, int(ceil(p0.distance_to(p1) / 1.5)))
		for k in steps + 1:
			if k == 0 and i > 0:
				continue
			var p := p0.lerp(p1, float(k) / steps)
			if _near_building(p, 0.25) or props._on_road(p, 0.1):
				_flush(kind, run, height)
				run = PackedVector2Array()
			else:
				run.append(p)
	_flush(kind, run, height)


func _flush(kind: String, run: PackedVector2Array, height: float) -> void:
	if run.size() < 2:
		return
	var length := 0.0
	for i in run.size() - 1:
		length += run[i].distance_to(run[i + 1])
	if length < 1.0:
		return
	# Straight stretches as one segment each (EditLines cuts them in 3 m pieces).
	var simple := PackedVector2Array([run[0]])
	for i in range(1, run.size() - 1):
		var d0 := (run[i] - simple[simple.size() - 1]).normalized()
		var d1 := (run[i + 1] - run[i]).normalized()
		if d0.dot(d1) < 0.999:
			simple.append(run[i])
	simple.append(run[run.size() - 1])
	_line(kind, simple, height)


# --- paint on the ground -----------------------------------------------------------------

## Heights above the ground: a court's surface, then its lines on top.
const SURFACE_Y := 0.06
const COURT_Y := 0.09 ## a court laid on its surround
const LINE_Y := 0.115
const LINE_W := 0.06
## Cells of at most this size (m), so paint follows the ground.
const PAINT_CELL := 4.0


## A rectangle in a frame (centre c, axes u and v): u from a0 to a1, v from
## b0 to b1, cut in cells that follow the ground, clipped to this chunk.
func _paint_rect(c: Vector2, u: Vector2, v: Vector2, a0: float, a1: float, b0: float, b1: float, col: Color, y: float) -> void:
	if ChunkBuilder.server_build():
		return
	var na := maxi(1, int(ceil((a1 - a0) / PAINT_CELL)))
	var nb := maxi(1, int(ceil((b1 - b0) / PAINT_CELL)))
	paint.color = col.srgb_to_linear()
	for i in na:
		for j in nb:
			var aa := lerpf(a0, a1, float(i) / na)
			var ab := lerpf(a0, a1, float(i + 1) / na)
			var ba := lerpf(b0, b1, float(j) / nb)
			var bb := lerpf(b0, b1, float(j + 1) / nb)
			var mid := c + u * (aa + ab) * 0.5 + v * (ba + bb) * 0.5
			if not props._inside(mid):
				continue
			var q := [c + u * aa + v * ba, c + u * ab + v * ba, c + u * ab + v * bb, c + u * aa + v * bb]
			var p3: Array[Vector3] = []
			for g: Vector2 in q:
				p3.append(props.terrain.at(g, y))
			paint.quad(p3[0], p3[1], p3[2], p3[3], Vector3.UP)


## A painted line from a to b (frame coordinates), LINE_W wide.
func _paint_line(c: Vector2, u: Vector2, v: Vector2, a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var du := d / length
	# The line's own frame: along it and across it, in the ground plane.
	var lu := u * du.x + v * du.y
	var lv := Vector2(-lu.y, lu.x)
	var start := c + u * a.x + v * a.y
	_paint_rect(start, lu, lv, 0.0, length, -LINE_W * 0.5, LINE_W * 0.5, col, LINE_Y)


func _paint_box_lines(c: Vector2, u: Vector2, v: Vector2, a0: float, a1: float, b0: float, b1: float, col: Color) -> void:
	_paint_line(c, u, v, Vector2(a0, b0), Vector2(a1, b0), col)
	_paint_line(c, u, v, Vector2(a1, b0), Vector2(a1, b1), col)
	_paint_line(c, u, v, Vector2(a1, b1), Vector2(a0, b1), col)
	_paint_line(c, u, v, Vector2(a0, b1), Vector2(a0, b0), col)


## An arc of painted line round centre o (frame coordinates), from angle
## t0 to t1 (radians, 0 along u).
func _paint_arc(c: Vector2, u: Vector2, v: Vector2, o: Vector2, r: float, t0: float, t1: float, col: Color) -> void:
	var n := maxi(4, int(absf(t1 - t0) * r / 1.2))
	for k in n:
		var a := lerpf(t0, t1, float(k) / n)
		var b := lerpf(t0, t1, float(k + 1) / n)
		_paint_line(c, u, v, o + Vector2(cos(a), sin(a)) * r, o + Vector2(cos(b), sin(b)) * r, col)


const COURT_GREEN := Color(0.24, 0.45, 0.32)
const COURT_BLUE := Color(0.2, 0.36, 0.55)
const ASPHALT := Color(0.27, 0.28, 0.29)
const PAINT_WHITE := Color(0.93, 0.93, 0.9)
const CLAY := Color(0.6, 0.3, 0.2) ## PEI's red, in the infield
const MULCH := Color(0.3, 0.19, 0.13)


## A polygon of paint (a flower bed's mulch), its triangles' corners set
## on the ground. Only for small areas: big ones would cut through bumps.
func _paint_polygon(ring: PackedVector2Array, col: Color, y: float) -> void:
	if ChunkBuilder.server_build() or not props._inside(BuildingGenerator._centre(ring)):
		return
	var idx := Geometry2D.triangulate_polygon(ring)
	paint.color = col.srgb_to_linear()
	for i in range(0, idx.size(), 3):
		var a := props.terrain.at(ring[idx[i]], y)
		var b := props.terrain.at(ring[idx[i + 1]], y)
		var c := props.terrain.at(ring[idx[i + 2]], y)
		paint.tri(a, b, c, Vector3.UP)


## A tennis court (or a row of them): blue courts on a green surround, the
## lines of a doubles court, scaled down if the pitch is short.
func _tennis_paint(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float, courts: int) -> void:
	_paint_rect(c, u, v, -hu, hu, -hv, hv, COURT_GREEN, SURFACE_Y)
	var s := minf(1.0, (hu * 2.0 - 2.0) / 23.77)
	var hl := 23.77 * 0.5 * s
	var hw := 10.97 * 0.5 * s
	var hs := 8.23 * 0.5 * s
	var sv := 6.4 * s
	for k in courts:
		var off := -hv + hv * 2.0 * (k + 0.5) / courts
		if hw * 2.0 > hv * 2.0 / courts:
			continue
		var cc := c + v * off
		_paint_rect(cc, u, v, -hl - 1.5 * s, hl + 1.5 * s, -hw - 1.0 * s, hw + 1.0 * s, COURT_BLUE, COURT_Y)
		_paint_box_lines(cc, u, v, -hl, hl, -hw, hw, PAINT_WHITE)
		for b: float in [-hs, hs]:
			_paint_line(cc, u, v, Vector2(-hl, b), Vector2(hl, b), PAINT_WHITE)
		for a: float in [-sv, sv]:
			_paint_line(cc, u, v, Vector2(a, -hs), Vector2(a, hs), PAINT_WHITE)
		_paint_line(cc, u, v, Vector2(-sv, 0), Vector2(sv, 0), PAINT_WHITE)


## A park basketball court: asphalt, the boundary, the half-court line and
## circle, a key and a three-point arc at each hoop (one hoop: half court).
func _basketball_paint(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float, ends: Array, paved: bool) -> void:
	if paved:
		_paint_rect(c, u, v, -hu, hu, -hv, hv, ASPHALT, SURFACE_Y)
	var col := PAINT_WHITE
	var a := hu - 0.6
	var b := hv - 0.6
	_paint_box_lines(c, u, v, -a, a, -b, b, col)
	if ends.size() == 2:
		_paint_line(c, u, v, Vector2(0, -b), Vector2(0, b), col)
		_paint_arc(c, u, v, Vector2.ZERO, minf(1.8, b * 0.4), 0.0, TAU, col)
	var key_w := minf(2.45, b * 0.45)
	var key_l := minf(5.8, a * 0.4)
	var three := minf(6.75, minf(b - 0.3, a * 0.6))
	for e: float in ends:
		var base := a * e
		var ft := base - e * key_l
		_paint_line(c, u, v, Vector2(base, -key_w), Vector2(ft, -key_w), col)
		_paint_line(c, u, v, Vector2(base, key_w), Vector2(ft, key_w), col)
		_paint_line(c, u, v, Vector2(ft, -key_w), Vector2(ft, key_w), col)
		var bulge := -PI * 0.5 if e < 0.0 else PI * 0.5
		_paint_arc(c, u, v, Vector2(ft, 0), key_w * 0.75, bulge, bulge + PI, col)
		var hoop := Vector2(base - e * 1.6, 0)
		var t0 := -PI * 0.5 if e < 0.0 else PI * 0.5
		_paint_arc(c, u, v, hoop, three, t0, t0 + PI, col)


## A soccer pitch's lines in white on the grass: touchlines, halfway line
## and circle, the penalty and goal areas, scaled to the pitch.
func _soccer_paint(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float) -> void:
	var a := hu - 1.0
	var b := hv - 1.0
	var s := minf(1.0, a * 2.0 / 105.0)
	_paint_box_lines(c, u, v, -a, a, -b, b, PAINT_WHITE)
	_paint_line(c, u, v, Vector2(0, -b), Vector2(0, b), PAINT_WHITE)
	_paint_arc(c, u, v, Vector2.ZERO, 9.15 * s, 0.0, TAU, PAINT_WHITE)
	for e: float in [-1.0, 1.0]:
		var pb := minf(20.15 * s, b - 1.0)
		var gb := minf(9.16 * s, b - 2.0)
		_paint_box_lines(c, u, v, minf(e * a, e * (a - 16.5 * s)), maxf(e * a, e * (a - 16.5 * s)), -pb, pb, PAINT_WHITE)
		_paint_box_lines(c, u, v, minf(e * a, e * (a - 5.5 * s)), maxf(e * a, e * (a - 5.5 * s)), -gb, gb, PAINT_WHITE)


## A ball diamond's infield: red clay in a fan out from home plate past the
## bases, white foul lines down each side, the bases and the rubber.
func _diamond_paint(home: Vector2, out: Vector2, reach: float) -> void:
	var side := Vector2(-out.y, out.x)
	var base := minf(27.4, reach * 0.35)
	var r := base * 1.06
	# The fan as thin wedges from home, each a quad cut to follow the ground.
	var n := 12
	for k in n:
		var t0 := lerpf(-PI * 0.25, PI * 0.25, float(k) / n)
		var t1 := lerpf(-PI * 0.25, PI * 0.25, float(k + 1) / n)
		var d0 := out.rotated(t0)
		var d1 := out.rotated(t1)
		for j in 4:
			var ra := r * j / 4.0
			var rb := r * (j + 1) / 4.0
			var q := [home + d0 * ra, home + d0 * rb, home + d1 * rb, home + d1 * ra]
			if not props._inside((q[0] + q[2]) * 0.5) or ChunkBuilder.server_build():
				continue
			paint.color = CLAY.srgb_to_linear()
			paint.quad(props.terrain.at(q[0], SURFACE_Y), props.terrain.at(q[1], SURFACE_Y), props.terrain.at(q[2], SURFACE_Y), props.terrain.at(q[3], SURFACE_Y), Vector3.UP)
	for t: float in [-PI * 0.25, PI * 0.25]:
		_paint_line(home, out, side, Vector2.ZERO, Vector2(cos(t), sin(t)) * reach * 0.95, PAINT_WHITE)
	# Bases at the diamond's corners, and the pitcher's rubber.
	for p: Vector2 in [Vector2(base, 0).rotated(-PI * 0.25), Vector2(base * sqrt(2.0), 0), Vector2(base, 0).rotated(PI * 0.25), Vector2(base * 0.67, 0)]:
		_paint_rect(home, out, side, p.x - 0.23, p.x + 0.23, p.y - 0.23, p.y + 0.23, PAINT_WHITE, LINE_Y)


## A patio built out over the street gets its black iron railing on the
## sides that don't meet a building, with a gap to walk in at one end.
func _patio_rail(a: StreetData.GroundArea) -> void:
	var ring := a.ring
	var c := BuildingGenerator._centre(ring)
	if not props._inside(c):
		return
	for i in ring.size():
		var p0 := ring[i]
		var p1 := ring[(i + 1) % ring.size()]
		if _near_building((p0 + p1) * 0.5, 1.2):
			continue
		if i == 0:
			p0 = p0.move_toward(p1, 1.1) # the way in
		_line("patio_rail", PackedVector2Array([p0, p1]), 1.0)


## How likely a downtown shop, café or bar puts its sandwich board out.
const BOARD_ODDS := 0.55


## Sandwich boards on the sidewalk outside downtown's cafés, restaurants,
## bars and shops: a metre out from the front wall, by the door.
func _sidewalk_boards() -> void:
	var heritage := float(props.data.config.get("heritage_district_m", 900.0))
	for b in props.chunk.buildings:
		var c := BuildingGenerator._centre(b.ring)
		if not props._inside(c) or c.length() > heritage:
			continue
		var amen := str(b.tags.get("amenity", ""))
		if not (b.tags.has("shop") or amen in ["restaurant", "cafe", "bar", "pub", "fast_food", "ice_cream"]):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(b.id) + 7
		if rng.randf() > BOARD_ODDS:
			continue
		var hit := props.net.nearest_on_streets(c, 40.0)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var pos: Vector2 = hit["pos"]
		var n: Vector2 = (c - pos).normalized()
		# The front wall: the nearest point of the footprint to the street.
		var front := INF
		for q in b.ring:
			front = minf(front, (q - pos).dot(n))
		var p := pos + n * (front - 1.0) + (hit["dir"] as Vector2) * rng.randf_range(-2.0, 2.0)
		if e.walk(1) <= 0.0 and e.walk(-1) <= 0.0:
			continue
		if props.net.clear_of_roads(p, 0.6) and not _near_building(p, 0.3):
			_put("sandwich_board", p, -n)


## A flower bed: OSM's flower beds, and its small gardens (the beds in
## Queen Square and Rochford Square), filled with clumps of bedding plants.
func _flower_bed(a: StreetData.GroundArea) -> void:
	var area := absf(BuildingGenerator._signed_area(a.ring))
	if area < 2.0 or area > 400.0:
		return
	var box := Rect2(a.ring[0], Vector2.ZERO)
	for q in a.ring:
		box = box.expand(q)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a.id)
	_paint_polygon(a.ring, MULCH, SURFACE_Y)
	var step := 1.0
	var count := 0
	var y := box.position.y + step * 0.5
	while y < box.end.y and count < 80:
		var x := box.position.x + step * 0.5
		while x < box.end.x and count < 80:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			if props._inside(p) and Geometry2D.is_point_in_polygon(p, a.ring) and not props._on_road(p, 0.2):
				var s := rng.randf_range(0.8, 1.25)
				_put("flowers", p, Vector2.from_angle(rng.randf() * TAU), Vector3(s, rng.randf_range(0.8, 1.2), s))
				count += 1
			x += step
		y += step


# --- hardscape: lot curbs, drive-through islands, footpaths -------------------------------

const CONCRETE := Color(0.66, 0.65, 0.62)
const LANE_YELLOW := Color(0.88, 0.7, 0.12)
const PATH_CONCRETE := Color(0.6, 0.6, 0.57)
const PATH_ASPHALT := Color(0.3, 0.31, 0.32)
const CURB_H := 0.14
const CURB_W := 0.16
## Paths as painted on the ground (tools/make_ground_mask.py PATHS): width.
const PATH_W := {"footway": 2.2, "path": 2.0, "cycleway": 3.0, "pedestrian": 4.0}
const SERVICE_W := {"driveway": 3.2, "parking_aisle": 6.0, "alley": 4.0, "drive-through": 3.5, "": 5.0}

var _ground_map: GroundMap


## True if the open ground at p is paved (the ground map: a lot, a
## plaza, a painted path), as a tyre would find it.
func _paved(p: Vector2) -> bool:
	if _ground_map == null:
		var size := props.data.chunk_size
		_ground_map = GroundMap.load_chunk(props.data.city_dir, StreetData.chunk_key(floori(props.rect.position.x / size), floori(props.rect.position.y / size)), props.rect)
	return _ground_map.kind_at(p.x, p.y) == GroundMap.PAVED


static var _minor_grid: Dictionary = {} ## 100 m cell -> Array of StreetData.Road (service and paths)
static var _minor_ready := false
static var _minor_lock := Mutex.new()


static func _index_minor(data: StreetData) -> void:
	_minor_lock.lock()
	if not _minor_ready:
		for r: StreetData.Road in data.roads:
			if r.highway != "service" and not PATH_W.has(r.highway):
				continue
			var box := Rect2(r.points[0], Vector2.ZERO)
			for q in r.points:
				box = box.expand(q)
			box = box.grow(4.0)
			for cx in range(floori(box.position.x / 100.0), floori(box.end.x / 100.0) + 1):
				for cz in range(floori(box.position.y / 100.0), floori(box.end.y / 100.0) + 1):
					var k := Vector2i(cx, cz)
					if not _minor_grid.has(k):
						_minor_grid[k] = []
					if not (_minor_grid[k] as Array).has(r):
						_minor_grid[k].append(r)
		_minor_ready = true
	_minor_lock.unlock()


func _minor_near(rect: Rect2) -> Array:
	_index_minor(props.data)
	var out: Array = []
	var seen := {}
	for cx in range(floori(rect.position.x / 100.0), floori(rect.end.x / 100.0) + 1):
		for cz in range(floori(rect.position.y / 100.0), floori(rect.end.y / 100.0) + 1):
			for r: StreetData.Road in _minor_grid.get(Vector2i(cx, cz), []):
				if not seen.has(r):
					seen[r] = true
					out.append(r)
	return out


## The lanes whose box reaches `box` (boxes cached per road).
static var _lane_boxes: Dictionary = {}
static var _lane_lock := Mutex.new()


func _lanes_in(lanes: Array, box: Rect2) -> Array:
	var out: Array = []
	for r: StreetData.Road in lanes:
		_lane_lock.lock()
		var b: Variant = _lane_boxes.get(r)
		_lane_lock.unlock()
		if b == null:
			var bb := Rect2(r.points[0], Vector2.ZERO)
			for q in r.points:
				bb = bb.expand(q)
			b = bb.grow(4.0)
			_lane_lock.lock()
			_lane_boxes[r] = b
			_lane_lock.unlock()
		if (b as Rect2).intersects(box):
			out.append(r)
	return out


## True if p is on a service lane (a lot's entrance, an aisle, a
## driveway), within its painted half-width and `pad` more.
func _on_lane(p: Vector2, pad: float, lanes: Array) -> bool:
	for r: StreetData.Road in lanes:
		if r.highway != "service":
			continue
		var half := float(SERVICE_W.get(str(r.tags.get("service", "")), 5.0)) * 0.5 + pad
		for i in r.points.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, r.points[i], r.points[i + 1]).distance_squared_to(p) < half * half:
				return true
	return false


## A strip along q0 -> q1, from `off0` to `off1` metres to its left, its top
## `top` above the ground and its sides down to `bottom` (a curb, a path).
func _strip(q0: Vector2, q1: Vector2, off0: float, off1: float, top: float, bottom: float, col: Color) -> void:
	var d := (q1 - q0).normalized()
	var n := Vector2(-d.y, d.x)
	var a0 := q0 + n * off0
	var a1 := q1 + n * off0
	var b0 := q0 + n * off1
	var b1 := q1 + n * off1
	var t := props.terrain
	paint.color = col.srgb_to_linear()
	var ta0 := t.at(a0, top)
	var ta1 := t.at(a1, top)
	var tb0 := t.at(b0, top)
	var tb1 := t.at(b1, top)
	paint.quad(ta0, ta1, tb1, tb0, Vector3.UP)
	paint.color = (col * 0.82).srgb_to_linear()
	var n3 := Vector3(n.x, 0, n.y)
	paint.quad(t.at(a0, bottom), t.at(a1, bottom), ta1, ta0, -n3 if off0 < off1 else n3)
	paint.quad(t.at(b1, bottom), t.at(b0, bottom), tb0, tb1, n3 if off0 < off1 else -n3)


## Concrete curbs round every parking lot, on the inside of its outline,
## with gaps where a lane comes in, where the lot meets a building or the
## street, and none on a parkade's deck.
func _lot_curbs() -> void:
	var lanes := _minor_near(props.rect.grow(10.0))
	for a in props.chunk.areas:
		if a.type != "amenity=parking":
			continue
		if str(a.tags.get("parking", "surface")) not in ["surface", ""]:
			continue
		var ring := _ccw(a.ring)
		if absf(BuildingGenerator._signed_area(ring)) < 60.0:
			continue
		var lot_box := Rect2(ring[0], Vector2.ZERO)
		for q in ring:
			lot_box = lot_box.expand(q)
		lot_box = lot_box.grow(6.0)
		if not lot_box.intersects(props.rect):
			continue
		var near_lanes := _lanes_in(lanes, lot_box)
		for i in ring.size():
			var p0 := ring[i]
			var p1 := ring[(i + 1) % ring.size()]
			var length := p0.distance_to(p1)
			if length < 0.5:
				continue
			var pieces := maxi(1, int(ceil(length / 2.0)))
			for k in pieces:
				var q0 := p0.lerp(p1, float(k) / pieces)
				var q1 := p0.lerp(p1, float(k + 1) / pieces)
				var mid := (q0 + q1) * 0.5
				if not props._inside(mid) or _on_lane(mid, 0.6, near_lanes) or props._on_road(mid, 0.3) or _near_building(mid, 0.8):
					continue
				# Where the pavement carries on past the outline (the next
				# lot, a store's apron) there's no curb.
				var d := (q1 - q0).normalized()
				if _paved(mid - Vector2(-d.y, d.x) * 1.2):
					continue
				# Inside a counter-clockwise outline is to the left.
				_strip(q0, q1, 0.0, CURB_W, CURB_H, -0.05, CONCRETE)


## Drive-through lanes get painted edge lines and arrows, and footpaths
## and park paths a paved strip a few centimetres proud of the grass with
## an edge, so they read as built (the colour under them is the ground
## map's). Brick and gravel paths keep the ground map's look.
func _minor_ways() -> void:
	var heritage := float(props.data.config.get("heritage_district_m", 900.0))
	var lanes := _minor_near(props.rect.grow(10.0))
	for r: StreetData.Road in lanes:
		var service := str(r.tags.get("service", "")) if r.highway == "service" else ""
		var is_drive := r.highway == "service" and service == "drive-through"
		var is_path := PATH_W.has(r.highway)
		if not is_drive and not is_path:
			continue
		if str(r.tags.get("bridge", "")) not in ["", "no"] or str(r.tags.get("tunnel", "")) not in ["", "no"] \
				or str(r.tags.get("layer", "0")).to_int() != 0 or str(r.tags.get("area", "")) == "yes":
			continue
		var col := PATH_CONCRETE
		if is_path:
			if str(r.tags.get("footway", "")) in ["sidewalk", "crossing"]:
				continue
			var surface := str(r.tags.get("surface", ""))
			if surface in ["gravel", "fine_gravel", "compacted", "dirt", "ground", "grass", "wood", "unpaved", "paving_stones", "bricks", "sett"]:
				continue
			if surface == "" and r.highway == "path" and _in_woods(r.points[r.points.size() / 2]):
				continue # an unmarked path in the woods: a trail
			col = PATH_ASPHALT if surface == "asphalt" or (surface == "" and r.highway in ["cycleway", "path"]) else PATH_CONCRETE
		var half := float(PATH_W.get(r.highway, 2.0)) * 0.5 if is_path else 1.75
		for i in r.points.size() - 1:
			var p0 := r.points[i]
			var p1 := r.points[i + 1]
			var length := p0.distance_to(p1)
			if length < 0.3:
				continue
			var pieces := maxi(1, int(ceil(length / 2.0)))
			for k in pieces:
				# A little overlap so bends don't open.
				var q0 := p0.lerp(p1, maxf(0.0, (k - 0.05) / pieces))
				var q1 := p0.lerp(p1, minf(1.0, (k + 1.05) / pieces))
				var mid := (q0 + q1) * 0.5
				if not props._inside(mid) or props._on_road(mid, 0.2) or _near_building(mid, 0.2):
					continue
				var across := Vector2(-(p1 - p0).normalized().y, (p1 - p0).normalized().x) * (half + 1.0)
				if is_path and (_paved(mid + across) or _paved(mid - across) or mid.length() < heritage):
					continue # across a paved square or a lot, or downtown's brick
				if is_path:
					_strip(q0, q1, -half, half, 0.045, -0.03, col)
				else:
					# A drive-through lane is paint, not curbs: a yellow line down
					# each edge, and an arrow every so often showing the way round.
					var dd := (q1 - q0).normalized()
					var nn := Vector2(-dd.y, dd.x)
					for sgn: float in [-1.0, 1.0]:
						_paint_line(q0, dd, nn, Vector2(0, sgn * half), Vector2(q0.distance_to(q1), sgn * half), LANE_YELLOW)
					if k % 6 == 3:
						var tip := Vector2(q0.distance_to(q1) * 0.5 + 0.6, 0)
						_paint_line(q0, dd, nn, tip - Vector2(1.6, 0), tip, PAINT_WHITE)
						_paint_line(q0, dd, nn, tip, tip + Vector2(-0.6, 0.45), PAINT_WHITE)
						_paint_line(q0, dd, nn, tip, tip + Vector2(-0.6, -0.45), PAINT_WHITE)

func _in_woods(p: Vector2) -> bool:
	for a in props.chunk.areas:
		if a.type in ["natural=wood", "landuse=forest", "natural=wetland", "natural=scrub"] and Geometry2D.is_point_in_polygon(p, a.ring):
			return true
	return false


# --- schools, store lots, mailbox banks ----------------------------------------------------

## A school's message board out front, the summer's (seeded by the school).
const SCHOOL_BOARD := [
	"HAVE A GREAT SUMMER|SEE YOU SEPTEMBER",
	"SUMMER CAMP|REGISTRATION OPEN|WAITLIST ALSO OPEN",
	"CONGRATULATIONS GRADS|THE PORTABLES|ARE STAYING",
	"BUS ROUTES POSTED|IN AUGUST|PROBABLY",
	"NEW GYM FLOOR|ANNOUNCED 2019|STAY TUNED",
	"LOST AND FOUND|DONATED JULY 1|YES, THAT JACKET TOO",
]


## A sign to be built with the placed ones (PlacedSigns reads the chunk's
## points after this).
func _sign_point(kind: String, p: Vector2, facing: Vector2, tags: Dictionary) -> void:
	var m := StreetData.MapPoint.new()
	m.id = "gen:%s:%d:%d" % [kind, roundi(p.x * 10.0), roundi(p.y * 10.0)]
	m.type = "sign=" + kind
	m.pos = p
	var t := tags.duplicate()
	t["direction"] = str(fposmod(rad_to_deg(atan2(facing.x, -facing.y)), 360.0))
	m.tags = t
	props.chunk.points.append(m)


## A school's grounds: the flagpole and bike racks by the main building's
## street side, the sign with its message board at the road, a play
## structure and swings out back where OSM maps none, and school-zone signs
## either way along the street out front.
func _schools() -> void:
	for a in props.chunk.areas:
		if a.type != "amenity=school":
			continue
		# The main building: the biggest footprint inside the grounds.
		var main: StreetData.Building = null
		var best := 0.0
		for b in props.chunk.buildings:
			var c := BuildingGenerator._centre(b.ring)
			if Geometry2D.is_point_in_polygon(c, a.ring):
				var ar := absf(BuildingGenerator._signed_area(b.ring))
				if ar > best:
					best = ar
					main = b
		if main == null or best < 300.0:
			continue
		var c := BuildingGenerator._centre(main.ring)
		var hit := props.net.nearest_on_streets(c, 150.0)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var pos: Vector2 = hit["pos"]
		var dir: Vector2 = hit["dir"]
		var out: Vector2 = (pos - c).normalized() # from the school to the street
		var front := -INF
		for q in main.ring:
			front = maxf(front, (q - c).dot(out))
		var door := c + out * (front + 5.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(a.id)
		var side := Vector2(-out.y, out.x)
		if props._inside(door) and _clear(door, 0.5):
			_put("flagpole", door, side)
			for k in 2:
				var br := door + side * (4.0 + k * 2.6)
				if _clear(br, 0.4):
					_put("bike_rack", br, out)
		# The sign at the road, facing the street.
		var lot := e.half_width + maxf(e.walk(1), e.walk(-1)) + 2.0
		var sp := pos - out * lot + dir * rng.randf_range(-6.0, 6.0)
		var name := str(a.tags.get("name", ""))
		if name != "" and props._inside(sp) and _clear(sp, 0.8):
			_sign_point("monument", sp, out, {"text": name.to_upper() + "|" + str(SCHOOL_BOARD[rng.randi() % SCHOOL_BOARD.size()]),
				"colour": "#1f3b6e", "text_colour": "#ffffff", "width": "3.2", "height": "1.5"})
		# School zone, both ways along the street.
		var right := Vector2(-dir.y, dir.x)
		for sgn: float in [-1.0, 1.0]:
			var at := pos - dir * sgn * 55.0 + right * sgn * (e.half_width + maxf(e.walk(int(sgn)), 0.0) + 0.6)
			if props._inside(at) and _clear(at, 0.3) and not props._on_road(at, 0.0):
				_sign_point("school_zone", at, -dir * sgn, {"text": "SCHOOL|ZONE"})
		# Somewhere to play out back, if OSM has none in the grounds.
		var has_play := false
		for o in props.chunk.areas:
			if o.type == "leisure=playground" and Geometry2D.is_point_in_polygon(BuildingGenerator._centre(o.ring), a.ring):
				has_play = true
		if not has_play:
			var back := -INF
			for q in main.ring:
				back = maxf(back, (q - c).dot(-out))
			var yard := c - out * (back + 14.0)
			if props._inside(yard) and Geometry2D.is_point_in_polygon(yard, a.ring) and _clear(yard, 3.0):
				_put("playground", yard, out)
				var sw := yard + side * 8.0
				if _clear(sw, 2.5):
					_put("swing_set", sw, out)
				for k in 2:
					var h := yard - out * 14.0 + side * (k * 6.0 - 3.0)
					if Geometry2D.is_point_in_polygon(h, a.ring) and _clear(h, 1.5):
						_put("basketball_hoop", h, out)


## Big lots out of downtown (the stores on Capital Drive, North River Road,
## University Avenue): pole lights on a grid, and cart corrals in the
## ones by a grocery or big-box store; a hardware store's garden centre puts
## its pallets of soil and mulch out front for the summer.
func _store_lots() -> void:
	var heritage := float(props.data.config.get("heritage_district_m", 900.0))
	var lanes: Array = []
	var stores: Array[StreetData.Building] = []
	var hardware: Array[StreetData.Building] = []
	for b in props.chunk.buildings:
		var shop := str(b.tags.get("shop", ""))
		var ar := absf(BuildingGenerator._signed_area(b.ring))
		if shop in ["supermarket", "department_store", "doityourself", "hardware", "mall", "wholesale", "garden_centre"] \
				or (ar > 4000.0 and str(b.tags.get("building", "")) in ["retail", "commercial"]):
			stores.append(b)
		if shop in ["doityourself", "hardware", "garden_centre"]:
			hardware.append(b)
	var placed_lights: Array[Vector2] = []
	for p in props.chunk.points:
		if p.type == "prop=lot_light":
			placed_lights.append(p.pos)
	for a in props.chunk.areas:
		if a.type != "amenity=parking" or str(a.tags.get("parking", "surface")) not in ["surface", ""]:
			continue
		var c := BuildingGenerator._centre(a.ring)
		var ar := absf(BuildingGenerator._signed_area(a.ring))
		if ar < 2500.0 or c.length() < heritage:
			continue
		var lit := false
		for q in placed_lights:
			if Geometry2D.is_point_in_polygon(q, a.ring):
				lit = true
		var by_store := false
		for b in stores:
			if BuildingGenerator._centre(b.ring).distance_to(c) < 140.0:
				by_store = true
		if lanes.is_empty():
			lanes = _minor_near(props.rect.grow(10.0))
		var box := BuildingGenerator._obb(a.ring)
		var u: Vector2 = box["u"]
		var v: Vector2 = box["v"]
		var hu: float = box["half_u"]
		var hv: float = box["half_v"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(a.id)
		var step := 34.0
		var corral_every := 3 if by_store else 0
		var n := 0
		var i := -hu + step * 0.5
		while i < hu:
			var j := -hv + step * 0.5
			while j < hv:
				var p: Vector2 = box["center"] + u * i + v * j
				j += step
				if not props._inside(p) or not Geometry2D.is_point_in_polygon(p, a.ring) or not _clear(p, 5.0):
					continue
				if _on_lane(p, 0.8, lanes) or _near_lot_car(p, 3.0):
					continue
				n += 1
				if not lit:
					_put("lot_light", p, u)
				if corral_every > 0 and n % corral_every == 1:
					var q := p + u * 5.0
					if not _on_lane(q, 1.0, lanes) and not _near_lot_car(q, 3.5) and _clear(q, 2.5):
						_put("cart_corral", q, v)
			i += step
	# The garden centre's summer pallets, in two rows along the front.
	for b in hardware:
		var c := BuildingGenerator._centre(b.ring)
		if not props._inside(c) or c.length() < heritage:
			continue
		# The front is the side facing its car park (the biggest lot near it).
		var lot_c := Vector2.INF
		var lot_a := 0.0
		for o in props.chunk.areas:
			if o.type != "amenity=parking":
				continue
			var oc := BuildingGenerator._centre(o.ring)
			var oa := absf(BuildingGenerator._signed_area(o.ring))
			if oc.distance_to(c) < 200.0 and oa > lot_a:
				lot_a = oa
				lot_c = oc
		if lot_c == Vector2.INF:
			continue
		var out: Vector2 = (lot_c - c).normalized()
		var front := -INF
		for q in b.ring:
			front = maxf(front, (q - c).dot(out))
		var side := Vector2(-out.y, out.x)
		for row in 2:
			for k in 6:
				var p := c + out * (front + 2.5 + row * 1.6) + side * (6.0 + k * 1.5)
				if _clear(p, 0.4) and not _near_lot_car(p, 2.0):
					_put("pallet_stack", p, out)


func _near_lot_car(p: Vector2, reach: float) -> bool:
	for car: Array in props._lot_cars:
		var o: Vector3 = (car[0] as Transform3D).origin
		if Vector2(o.x, o.z).distance_squared_to(p) < reach * reach:
			return true
	return false


## How likely a residential corner has a Canada Post mailbox bank (every
## street's mail has gone to them since 2015).
const MAILBOX_ODDS := 0.3


## Community mailbox banks at residential corners out of downtown, on the
## verge a few metres along one of the streets, facing it.
func _mailbox_banks() -> void:
	var heritage := float(props.data.config.get("heritage_district_m", 900.0))
	for nid in props._junctions():
		var at: Vector2 = props.net.nodes[nid]
		if at.length() < heritage:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(nid)
		if rng.randf() > MAILBOX_ODDS:
			continue
		var incs: Array = props.net.incidents.get(nid, [])
		if incs.is_empty():
			continue
		var inc: RoadNetwork.Incident = incs[rng.randi() % incs.size()]
		var e := inc.edge
		if e.highway not in ["residential", "living_street", "unclassified"]:
			continue
		var d := inc.dir
		var right := Vector2(-d.y, d.x)
		var k := props.net.incident_index(nid, e, inc.at_start)
		var p := at + d * (props.net.mouth_distance(nid, k) + 7.0) + right * (e.half_width + maxf(e.walk(1), e.walk(-1)) + 1.2)
		if props._inside(p) and _clear(p, 1.3):
			_put("community_mailbox", p, right)


# --- marinas -----------------------------------------------------------------------------

const DOCK_TOP := 0.35 ## the deck above the water (m)
const DOCK_C := Color(0.82, 0.8, 0.72) ## weathered decking
const FINGER_EVERY := 8.0
const FINGER_LEN := 9.0
const PIER_EVERY := 24.0


func _put_at(kind: String, at: Vector3, facing: Vector2, solid := true) -> void:
	var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y))
	if not placed.has(kind):
		placed[kind] = []
	placed[kind].append([Transform3D(basis, at), solid])


func _wet(p: Vector2) -> bool:
	return props.terrain.h2(p) < Terrain.WATER_Y - 0.05


## A dock's deck from a to b, `half` wide: the top and its edges down into
## the water, and the top for walking on.
func _deck(a: Vector2, b: Vector2, half: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * half
	var y := Terrain.WATER_Y + DOCK_TOP
	var low := Terrain.WATER_Y - 0.15
	var q := [a + n, b + n, b - n, a - n]
	docks.color = DOCK_C.srgb_to_linear()
	var top := [MeshKit.v3(q[0], y), MeshKit.v3(q[1], y), MeshKit.v3(q[2], y), MeshKit.v3(q[3], y)]
	docks.quad(top[0], top[1], top[2], top[3], Vector3.UP)
	docks.color = (DOCK_C * 0.7).srgb_to_linear()
	for i in 4:
		var p0: Vector2 = q[i]
		var p1: Vector2 = q[(i + 1) % 4]
		var mid := (p0 + p1) * 0.5
		var out := (mid - (a + b) * 0.5).normalized()
		docks.quad(MeshKit.v3(p0, y), MeshKit.v3(p1, y), MeshKit.v3(p1, low), MeshKit.v3(p0, low), Vector3(out.x, 0, out.y))
	dock_faces.append_array(PackedVector3Array([top[0], top[1], top[2], top[0], top[2], top[3]]))


## A marina's floating docks and its boats: a main dock down the middle of
## its water, finger docks off both sides every FINGER_EVERY metres, and a
## boat moored bow-in in most slips (sailboats, motor cruisers, and the odd
## lobster boat in for the day). Laid out from the marina's outline, since
## OSM maps hardly any of Charlottetown's docks.
func _marina(a: StreetData.GroundArea) -> void:
	var box := BuildingGenerator._obb(a.ring)
	var c: Vector2 = box["center"]
	var u: Vector2 = box["u"]
	var v: Vector2 = box["v"]
	var hu: float = box["half_u"]
	var hv: float = box["half_v"]
	var rng := RandomNumberGenerator.new()
	# Piers across the water every PIER_EVERY metres along the marina, each
	# the stretch of its line that's over water inside the outline.
	var pu := -hu + PIER_EVERY * 0.5
	while pu < hu:
		var run_start := INF
		var t := -hv + 1.0
		while t <= hv:
			var p := c + u * pu + v * t
			var ok := Geometry2D.is_point_in_polygon(p, a.ring) and _wet(p) and _wet(p + u * 2.0) and _wet(p - u * 2.0)
			if ok and run_start == INF:
				run_start = t
			if (not ok or t + 1.0 > hv) and run_start != INF:
				var run_end := t - 1.0
				if run_end - run_start > 8.0:
					_dock_run(a, c + u * pu, v, u, run_start, run_end, rng)
				run_start = INF
			t += 1.0
		pu += PIER_EVERY


func _dock_run(a: StreetData.GroundArea, c: Vector2, u: Vector2, v: Vector2, t0: float, t1: float, rng: RandomNumberGenerator) -> void:
	# The pier, in 4 m pieces (each built by the chunk its middle is in).
	var k := t0
	while k < t1:
		var e := minf(k + 4.0, t1)
		if props._inside(c + u * (k + e) * 0.5):
			_deck(c + u * k, c + u * e, 1.2)
		k = e
	# Fingers off both sides, and a boat in most slips between them.
	var reach := minf(FINGER_LEN, PIER_EVERY * 0.5 - 2.0)
	var f := t0 + 1.0
	while f <= t1 - 1.0:
		for side: float in [-1.0, 1.0]:
			var base := c + u * f + v * side * 1.2
			var tip := base + v * side * reach
			if not (_wet(tip) and Geometry2D.is_point_in_polygon(tip, a.ring)):
				continue
			if props._inside((base + tip) * 0.5):
				_deck(base, tip, 0.5)
			if f + FINGER_EVERY > t1 - 1.0:
				continue
			var slip := base + u * (FINGER_EVERY * 0.5) + v * side * (reach * 0.55)
			if not props._inside(slip) or not _wet(slip):
				continue
			rng.seed = hash(Vector2i(roundi(slip.x * 4.0), roundi(slip.y * 4.0)))
			if rng.randf() > 0.8:
				continue
			var pick := rng.randf()
			var kind := "sailboat" if pick < 0.5 else ("motorboat" if pick < 0.85 else "lobster_boat")
			# Bow in, toward the pier.
			_put_at(kind, Vector3(slip.x, Terrain.WATER_Y, slip.y), -v * side)
		f += FINGER_EVERY

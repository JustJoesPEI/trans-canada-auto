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
const GHOSTS := ["headstone", "headstone_dark", "marble_tablet", "lawn_chair"]

var props: StreetProps
## Prop kind -> Array of [Transform3D, solid].
var placed: Dictionary = {}
## Lines for EditLines, in its own form: {kind, pts (ground), height, own}.
var lines: Array[Dictionary] = []

static var _hoods: Array = [] ## [centre (ground), radius, yards profile]
static var _hoods_ready := false
static var _hoods_lock := Mutex.new()


func _init(owner: StreetProps) -> void:
	props = owner


func build() -> void:
	_osm_points()
	_areas()
	_yards()


# --- helpers -----------------------------------------------------------------------------

func _put(kind: String, p: Vector2, facing: Vector2, scale := Vector3.ONE, lift := 0.0) -> void:
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
func _near_building(p: Vector2, pad: float) -> bool:
	for b in props.chunk.buildings:
		if not props._building_box(b).grow(pad).has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, b.ring):
			return true
		if pad > 0.0:
			for i in b.ring.size():
				var q := Geometry2D.get_closest_point_to_segment(p, b.ring[i], b.ring[(i + 1) % b.ring.size()])
				if q.distance_squared_to(p) < pad * pad:
					return true
	return false


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
		for s: float in [-1.0, 1.0]:
			var p := c + u * s * (hu - 0.6)
			if props._inside(p) and not props._on_road(p, 0.5):
				# The goal's mouth faces up the pitch.
				_put("soccer_goal", p, -u * s, Vector3.ONE * (1.0 if hu > 40.0 else 0.75))
	elif sport == "basketball":
		if hu < 5.0:
			return
		var ends: Array = [-1.0, 1.0] if hu > 10.0 else [1.0]
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
		if not _clear(at.call(mid, s1 + depth + 1.0), 0.8):
			break
		depth += 1.0
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
		var steps := maxi(1, int(ceil(p0.distance_to(p1) / 0.75)))
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

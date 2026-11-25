class_name UndergroundGarage
extends RefCounted
## Parking under a building: a way in through its wall at street level, a
## ramp down, and a level of stalls under the ground floor. The Gamma Prince
## Edward's (docs/design.md section 6½) is one. A building whose landmark
## entry in map_config.json has "garage" gets one:
##
##   "garage": {
##     "entrance"  [latitude, longitude] by the wall the way in goes
##                 through (the nearest wall gets the opening)
##     "depth"     m from the street down to the garage floor (3.2)
##     "stalls"    stalls along the far wall (8)
##     "apron"     m of driveway out from the wall to the sidewalk (2)
##   }
##
## Laid out from the opening, u pointing into the building and v along the
## wall. The ramp comes straight down into an aisle running along v, with
## the long row of stalls across it and a short row each side of the ramp:
##
##                       | stalls (the far row, 0 at -v) |
##                       |             aisle             |
##                       | stalls |  ramp   | stalls     |
##                                 | ramp  |
##   street   apron  |landing|
##
## The building's walls are built as usual except over the opening, where
## the wall starts at the top of it (BuildingGenerator asks cut_ring and
## portal_top). Everything here goes in the building's walls mesh, built
## with Parkade's pieces (the same blocks, decks and slopes, the same
## concrete), so it costs no more draw calls than the building did. Decks
## and ramp are GROUND; walls, ceilings and the lintel SOLID, so the camera
## stays under the ceiling.
##
## The ground (a height map) can't have a hole in it, so flatten lowers it
## under the garage, inside the building where nobody sees it, keeping
## clear of the building's corners (which set its floor height).

const OPENING := 7.0 ## the way in, wall to wall
const HEAD := 3.0 ## clear height inside
const LANDING := 3.0 ## level, just inside the opening
const EASE := 3.5 ## gentler slope at the top and bottom of the ramp
const GRADE := 0.16 ## the ramp's middle
const STALL_WIDTH := 2.7
const STALL_DEPTH := 5.4
const AISLE := 7.0
const WALL := 0.25
const CEILING := 0.3

const LIGHT := Color(1.0, 0.97, 0.88)


static func has_garage(landmark: Dictionary) -> bool:
	return landmark.get("garage") is Dictionary


## The garage's layout from the building's (clean, counter-clockwise) ring:
## {c (the middle of the opening, on the wall line), u (into the building),
## v (along the wall), edge (ring index of the wall), floor_y (the
## building's ground floor, which BuildingGenerator lifts it to), grade
## (street level at the opening), profile (the floor: [u, y] corners,
## heights local to floor_y), hall [u0 (its back wall, behind the short
## rows), u1 (the foot of the ramp: the aisle starts), u2 (the far wall)],
## hv (half the hall's width), stalls (in the far row)}. {} if it has none.
static func layout(ring: PackedVector2Array, landmark: Dictionary, terrain: Terrain, proj: GeoProjection) -> Dictionary:
	var g: Variant = landmark.get("garage")
	if not (g is Dictionary) or ring.size() < 3:
		return {}
	var at: Array = (g as Dictionary).get("entrance", [])
	if at.size() < 2:
		return {}
	var spot := proj.to_ground(float(at[1]), float(at[0]))
	# The wall nearest the spot, and where along it.
	var best := INF
	var edge := -1
	var c := Vector2.ZERO
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < OPENING + 2.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(spot, a, b)
		if q.distance_to(spot) < best:
			best = q.distance_to(spot)
			edge = i
			c = q
	if edge < 0:
		return {}
	var a0 := ring[edge]
	var a1 := ring[(edge + 1) % ring.size()]
	var t := (a1 - a0).normalized()
	# Keep the opening clear of the wall's ends.
	var half := OPENING * 0.5 + WALL + 0.5
	var along := clampf((c - a0).dot(t), half, a0.distance_to(a1) - half)
	c = a0 + t * along
	var out := Vector2(t.y, -t.x) # BuildingGenerator's outward normal
	var u := -out
	var v := Vector2(-u.y, u.x)
	# The building's ground floor, as BuildingGenerator works it out.
	var low := INF
	var high := -INF
	for p in ring:
		low = minf(low, terrain.h2(p))
		high = maxf(high, terrain.h2(p))
	var floor_y := minf(high, low + 2.0)
	# Street level: the highest ground just outside the opening, so the
	# landing never sits under it.
	var grade := -INF
	for k: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		grade = maxf(grade, terrain.h2(c - u * 1.0 + v * k * OPENING * 0.5))
	var gl := grade - floor_y
	var depth := float(g.get("depth", 3.2))
	var ease_drop := EASE * GRADE * 0.5
	var mid := maxf(0.0, depth - ease_drop * 2.0) / GRADE
	# The driveway out to the sidewalk, from the ground there up to the landing.
	var apron := maxf(1.0, float(g.get("apron", 2.0)))
	var kerb := -INF
	for k: float in [-1.0, 0.0, 1.0]:
		kerb = maxf(kerb, terrain.h2(c - u * apron + v * k * OPENING * 0.5))
	var profile: Array = [[-apron, maxf(kerb + 0.03 - floor_y, gl - 0.6)], [0.0, gl], [LANDING, gl], [LANDING + EASE, gl - ease_drop],
		[LANDING + EASE + mid, gl - depth + ease_drop], [LANDING + EASE * 2.0 + mid, gl - depth]]
	var foot: float = profile[profile.size() - 1][0]
	var n := maxi(1, int(g.get("stalls", 8)))
	var hv := n * STALL_WIDTH * 0.5 + WALL + 0.3
	return {"c": c, "u": u, "v": v, "edge": edge, "floor_y": floor_y, "grade": gl, "depth": depth, "profile": profile,
		"hall": [foot - STALL_DEPTH - WALL, foot, foot + AISLE + STALL_DEPTH + WALL], "hv": hv, "stalls": n}


## The layout of the garage under the building with this OSM id ({} if
## there's none). Main thread only (it caches).
static func find(data: StreetData, terrain: Terrain, id: String) -> Dictionary:
	if _found.has(id):
		return _found[id]
	var lm: Dictionary = data.config.get("landmarks", {}).get(id, {})
	var out := {}
	var g: Variant = lm.get("garage")
	if g is Dictionary and ((g as Dictionary).get("entrance", []) as Array).size() >= 2:
		var at: Array = g["entrance"]
		var p := data.projection.to_ground(float(at[1]), float(at[0]))
		var cx := floori(p.x / data.chunk_size)
		var cz := floori(p.y / data.chunk_size)
		for dx in [0, -1, 1]:
			for dz in [0, -1, 1]:
				for b in data.load_chunk(cx + dx, cz + dz).buildings:
					if b.id == id and out.is_empty():
						out = layout(clean_ring(b.ring), lm, terrain, data.projection)
		if out.is_empty():
			push_warning("UndergroundGarage: couldn't find building %s (check its garage \"entrance\")" % id)
	_found[id] = out
	return out

static var _found := {}


## The ring as BuildingGenerator uses it: cleaned, counter-clockwise.
static func clean_ring(ring: PackedVector2Array) -> PackedVector2Array:
	var r := BuildingGenerator._clean_ring(ring)
	if BuildingGenerator._signed_area(r) < 0.0:
		r.reverse()
	return r


## Floor height (local) `lu` metres in from the opening.
static func floor_at(lay: Dictionary, lu: float) -> float:
	var pr: Array = lay["profile"]
	if lu <= float(pr[0][0]):
		return float(pr[0][1])
	for i in range(1, pr.size()):
		var a: Array = pr[i - 1]
		var b: Array = pr[i]
		if lu <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (lu - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])))
	return float(pr[pr.size() - 1][1])


## The top of the opening, local to the building's floor: where its wall
## starts there.
static func portal_top(lay: Dictionary) -> float:
	return float(lay["grade"]) + HEAD


## The ring with the opening's two sides added to its wall, so the opening
## is a wall of its own: [ring, index of the opening's wall].
static func cut_ring(ring: PackedVector2Array, lay: Dictionary) -> Array:
	var e: int = lay["edge"]
	var a := ring[e]
	var b := ring[(e + 1) % ring.size()]
	var t := (b - a).normalized()
	var c: Vector2 = lay["c"]
	var half := OPENING * 0.5 + WALL
	var out := ring.duplicate()
	out.insert(e + 1, c + t * half)
	out.insert(e + 1, c - t * half)
	return [out, e + 1]


## A point `lu` in, `lv` across, on the floor, in the world.
static func world_point(lay: Dictionary, lu: float, lv: float, lift := 0.0) -> Vector3:
	var p: Vector2 = (lay["c"] as Vector2) + (lay["u"] as Vector2) * lu + (lay["v"] as Vector2) * lv
	return Vector3(p.x, float(lay["floor_y"]) + floor_at(lay, lu) + lift, p.y)


## Where stall `i` of the far row is across the hall (lv of its middle).
static func _stall_v(lay: Dictionary, i: int) -> float:
	var n := int(lay["stalls"])
	return (clampi(i, 0, n - 1) - (n - 1) * 0.5) * STALL_WIDTH


## A car backed into stall `i` of the far row, nose to the aisle.
static func stall_xform(lay: Dictionary, i: int, lift := 0.35) -> Transform3D:
	var lu := float(lay["hall"][2]) - WALL - STALL_DEPTH * 0.5
	var nose: Vector2 = -(lay["u"] as Vector2)
	return Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.y)), world_point(lay, lu, _stall_v(lay, i), lift))


## Standing in the aisle in front of stall `i`, looking at it.
static func aisle_xform(lay: Dictionary, i: int) -> Transform3D:
	var lu := float(lay["hall"][2]) - WALL - STALL_DEPTH - 1.6
	var look: Vector2 = lay["u"]
	return Transform3D(Basis(Vector3.UP, atan2(-look.x, -look.y)), world_point(lay, lu, _stall_v(lay, i), 0.1))


## Inside the garage (from the opening in, under the ceiling)?
static func contains(lay: Dictionary, p: Vector3, margin := 0.0) -> bool:
	var d := Vector2(p.x, p.z) - (lay["c"] as Vector2)
	var lu := d.dot(lay["u"])
	var lv := d.dot(lay["v"])
	var hall: Array = lay["hall"]
	var hw := float(lay["hv"]) if lu >= float(hall[0]) else OPENING * 0.5 + WALL
	if lu < -margin or lu > float(hall[2]) + margin or absf(lv) > hw + margin:
		return false
	var y := p.y - float(lay["floor_y"]) - floor_at(lay, lu)
	return y > -1.0 and y < HEAD + 0.5


## The box the camera follows people round in without fading the building
## (BuildingGenerator's meta "inside"; the same shape as a parkade's).
static func inside_box(lay: Dictionary, lift: float) -> Dictionary:
	var hall: Array = lay["hall"]
	var mid := float(hall[2]) * 0.5
	var c: Vector2 = (lay["c"] as Vector2) + (lay["u"] as Vector2) * mid
	return {"c": c, "u": lay["u"], "v": lay["v"], "hu": mid + 0.5, "hv": float(lay["hv"]) + 0.5,
		"y0": lift + float(lay["grade"]) - float(lay["depth"]) - 1.0, "y1": lift + float(lay["grade"]) + HEAD + 0.3}


# --- the ground ---------------------------------------------------------------------------

## Lowers the ground under every garage to below its floor. Run once at
## startup with Parkade.flatten, before any chunk is built. Only inside the
## building, never within a grid step of its corners (BuildingGenerator
## sets the building's floor from the ground there), and not under the way
## in from the street beyond a small dip the landing covers.
static func flatten(data: StreetData, terrain: Terrain) -> void:
	_found.clear()
	if terrain.is_flat():
		return
	var lms: Dictionary = data.config.get("landmarks", {})
	for id: String in lms:
		var lm: Variant = lms[id]
		if not (lm is Dictionary) or not has_garage(lm):
			continue
		var lay := find(data, terrain, id)
		if lay.is_empty():
			continue
		var ring := _ring_of(data, id, lm)
		var c: Vector2 = lay["c"]
		var u: Vector2 = lay["u"]
		var v: Vector2 = lay["v"]
		# No lamp post or tree across the way in, and no car parked there.
		var apron := -float((lay["profile"] as Array)[0][0])
		data.erase_props(c - u * (apron + 1.5), OPENING * 0.5 + 1.0)
		for k in 3:
			data.keep_clear.append(c - u * (apron + 3.0 + k * 5.0))
		var hall: Array = lay["hall"]
		# The ground's drawn on a coarser grid than the heights (the chunk
		# builder's step): lower far enough round that none of its
		# triangles reaches up inside.
		var pad := ChunkBuilder.FULL_GROUND_STEP * 1.45
		var reach := float(hall[2]) + float(lay["hv"]) + pad * 2.0
		var ix0 := floori((c.x - reach - terrain.origin.x) / terrain.spacing)
		var iz0 := floori((c.y - reach - terrain.origin.y) / terrain.spacing)
		var n := ceili(reach * 2.0 / terrain.spacing) + 1
		var fy: float = lay["floor_y"]
		for iz in range(iz0, iz0 + n):
			for ix in range(ix0, ix0 + n):
				var p := terrain.origin + Vector2(ix, iz) * terrain.spacing
				var d := p - c
				var lu := d.dot(u)
				var lv := absf(d.dot(v))
				var hw := float(lay["hv"]) if lu >= float(hall[0]) - pad else OPENING * 0.5 + WALL
				if lu < 0.5 or lu > float(hall[2]) + pad or lv > hw + pad:
					continue
				if not Geometry2D.is_point_in_polygon(p, ring) or _near_corner(p, ring, terrain.spacing):
					continue
				# Under the stall level (the short rows beside the ramp
				# included), down to its floor; under the ramp, below the ramp.
				var y := floor_at(lay, maxf(lu, 0.0))
				if lu >= float(hall[0]) - pad:
					y = minf(y, float(lay["grade"]) - float(lay["depth"]))
				terrain.lower_grid(ix, iz, fy + y - CEILING)
	# Built afresh from the lowered ground (the layout reads only the
	# corners and the street, which this leaves alone).
	_found.clear()


static func _ring_of(data: StreetData, id: String, lm: Dictionary) -> PackedVector2Array:
	var at: Array = lm["garage"]["entrance"]
	var p := data.projection.to_ground(float(at[1]), float(at[0]))
	var cx := floori(p.x / data.chunk_size)
	var cz := floori(p.y / data.chunk_size)
	for dx in [0, -1, 1]:
		for dz in [0, -1, 1]:
			for b in data.load_chunk(cx + dx, cz + dz).buildings:
				if b.id == id:
					return clean_ring(b.ring)
	return PackedVector2Array()


static func _near_corner(p: Vector2, ring: PackedVector2Array, step: float) -> bool:
	for q in ring:
		if absf(p.x - q.x) < step * 1.01 and absf(p.y - q.y) < step * 1.01:
			return true
	return false


# --- building it --------------------------------------------------------------------------

## Builds the garage into `walls` (heights local to the building's floor).
## Returns {"collision": SOLID faces, "ground": GROUND faces, "signs": the
## name over the way in, in BuildingGenerator's form}.
static func build(lay: Dictionary, walls: MeshKit) -> Dictionary:
	var b := Parkade._Builder.new()
	b.lay = lay
	b.kit = walls
	var save_uv2 := walls.uv2
	var save_colour := walls.color
	walls.uv2 = Vector2(Parkade.STYLE_CONCRETE, 0.0)
	var pr: Array = lay["profile"]
	var hall: Array = lay["hall"]
	var hu0 := float(hall[0])
	var hu1 := float(hall[1])
	var hu2 := float(hall[2])
	var hv := float(lay["hv"])
	var lane := OPENING * 0.5
	var gl := float(lay["grade"])
	var low := gl - float(lay["depth"])

	# The way in and down: deck, side walls and ceiling, piece by piece.
	for i in range(1, pr.size()):
		var a: Array = pr[i - 1]
		var e: Array = pr[i]
		var u0 := float(a[0])
		var u1 := float(e[0])
		var y0 := float(a[1])
		var y1 := float(e[1])
		b.slope(u0, u1, -lane, lane, y0, y1, false)
		if u1 <= 0.0:
			continue
		var w0 := maxf(u0, 0.0)
		var f0 := floor_at(lay, w0)
		for s: float in [-1.0, 1.0]:
			var v0 := s * lane
			var v1 := s * (lane + WALL)
			b.block(w0, u1, minf(v0, v1), maxf(v0, v1), f0 - CEILING, y1 - CEILING, f0 + HEAD, y1 + HEAD, Parkade.CONCRETE, f0, false)
		_ceiling(b, w0, u1, -lane - WALL, lane + WALL, f0 + HEAD, y1 + HEAD)
	# The opening: a lintel over it and a jamb each side, in the wall line.
	var top := gl + HEAD
	b.block(-0.35, 0.35, -lane - WALL, lane + WALL, top - 0.45, top - 0.45, top + 0.3, top + 0.3, Parkade.CONCRETE, gl)
	for s: float in [-1.0, 1.0]:
		var j0 := s * lane
		var j1 := s * (lane + WALL + 0.35)
		b.block(-0.35, 0.35, minf(j0, j1), maxf(j0, j1), gl - CEILING, gl - CEILING, top + 0.3, top + 0.3, Parkade.CONCRETE, gl)

	# The stall level: floor, walls, ceiling, round the foot of the ramp.
	var side := lane + WALL
	b.flat(hu1, hu2, -hv, hv, low, true, Parkade.DECK)
	var ch := low + HEAD
	for s: float in [-1.0, 1.0]:
		var o0 := s * side
		var o1 := s * hv
		b.flat(hu0, hu1, minf(o0, o1), maxf(o0, o1), low, true, Parkade.DECK)
		_ceiling(b, hu0, hu1, minf(o0, o1), maxf(o0, o1), ch, ch)
		# The side walls, and the back wall behind the short row.
		var w0 := s * (hv - WALL)
		b.block(hu0, hu2, minf(w0, o1), maxf(w0, o1), low - CEILING, low - CEILING, ch, ch, Parkade.CONCRETE, low, false)
		b.block(hu0, hu0 + WALL, minf(o0, w0), maxf(o0, w0), low - CEILING, low - CEILING, ch, ch, Parkade.CONCRETE, low)
	_ceiling(b, hu1, hu2, -hv, hv, ch, ch)
	b.block(hu2 - WALL, hu2, -hv + WALL, hv - WALL, low - CEILING, low - CEILING, ch, ch, Parkade.CONCRETE, low)
	# Columns between every second pair of stalls in the far row.
	var n := int(lay["stalls"])
	var far_u := hu2 - WALL
	for i in range(0, n + 1, 2):
		var lv := _stall_v(lay, 0) - STALL_WIDTH * 0.5 + i * STALL_WIDTH
		b.block(far_u - 0.5, far_u, lv - 0.2, lv + 0.2, low, low, ch, ch, Parkade.CONCRETE, low)

	# Paint: stall lines, and strip lights over the aisle.
	walls.uv2 = Vector2(Parkade.STYLE_PLAIN, 0.0)
	walls.color = BuildingGenerator._vertex_color(Parkade.LINES, 0.0)
	var ly := low + 0.012
	for i in n + 1:
		var lv := _stall_v(lay, 0) - STALL_WIDTH * 0.5 + i * STALL_WIDTH
		_line(b, far_u - STALL_DEPTH + 0.3, far_u - 0.3, lv, ly)
	for s: float in [-1.0, 1.0]:
		var lv := s * (side + 0.15)
		while absf(lv) < hv - WALL - 0.5:
			_line(b, hu0 + WALL + 0.3, hu1 - 0.3, lv, ly)
			lv += s * STALL_WIDTH
	walls.color = BuildingGenerator._vertex_color(LIGHT, 0.0)
	var ly2 := ch - 0.02
	var lu2 := hu1 + AISLE * 0.5
	for lv: float in [-hv * 0.6, 0.0, hv * 0.6]:
		walls.quad(b.q3(lu2 - 0.12, lv - 1.2, ly2), b.q3(lu2 + 0.12, lv - 1.2, ly2), b.q3(lu2 + 0.12, lv + 1.2, ly2), b.q3(lu2 - 0.12, lv + 1.2, ly2), Vector3.DOWN)
	walls.uv2 = save_uv2
	walls.color = save_colour
	var u: Vector2 = lay["u"]
	var over := b.q3(-0.4, 0.0, top + 0.6)
	return {"collision": b.solid, "ground": b.ground,
		"signs": [{"text": "PARKING", "pos": over, "yaw": StreetProps.yaw_facing(-u), "pixel": 0.012, "colour": Color(0.12, 0.17, 0.24)}]}


## A painted line on the floor, along u from u0 to u1 at `lv`.
static func _line(b: Parkade._Builder, u0: float, u1: float, lv: float, y: float) -> void:
	b.kit.quad(b.q3(u0, lv - 0.06, y), b.q3(u1, lv - 0.06, y), b.q3(u1, lv + 0.06, y), b.q3(u0, lv + 0.06, y), Vector3.UP)


## A ceiling's underside (SOLID, for the camera) from u0 (height y0) to
## u1 (y1), and its top so it doesn't vanish seen from above.
static func _ceiling(b: Parkade._Builder, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	b.kit.color = BuildingGenerator._vertex_color(Parkade.CONCRETE, 0.0)
	var a := b.q3(u0, v0, y0)
	var c := b.q3(u1, v0, y1)
	var d := b.q3(u1, v1, y1)
	var e := b.q3(u0, v1, y0)
	var n := (c - a).cross(e - a).normalized()
	if n.y > 0.0:
		n = -n
	b.kit.quad(a, c, d, e, n, Vector2(-1, 0), Vector2(-1, 1), Vector2(-2, 1), Vector2(-2, 0))
	b.solid.append_array(PackedVector3Array([a, c, d, a, d, e]))
	var s := Vector3(0, CEILING, 0)
	b.kit.quad(a + s, c + s, d + s, e + s, -n, Vector2(-1, 0), Vector2(-1, 1), Vector2(-2, 1), Vector2(-2, 0))

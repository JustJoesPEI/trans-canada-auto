class_name Parkade
extends RefCounted
## Multi-storey car parks you can drive through: Charlottetown's Queen,
## Pownal and Fitzroy parkades. A building whose landmark entry in
## map_config.json has "style": "parkade" is built here instead of as a
## solid block:
##
##   "levels"           decks, counting the ground floor and the open roof (4)
##   "entrance_street"  the end facing this street is where you drive in at
##                      grade (else the end nearest any street)
##   "at"               [latitude, longitude] somewhere on it, so the spawn
##                      and the cars parked in it (spawn / parked_cars
##                      "parkade") can find it before its chunk is built
##
## The deck is laid out on the footprint's bounding box, u along its length
## (pointing to the entrance end) and v across:
##
##     |stalls|  aisle  |#| ramp |#|  aisle  |stalls|
##
## One straight ramp runs up the middle, from the far end of each level to
## the entrance end of the next, so every ramp sits exactly one storey above
## the one below it. Flat turning bays at both ends join the ramps to the
## aisles. Drive in, down an aisle to the far end, up the ramp, and round
## again. Decks and ramps are GROUND (wheels and feet stand on them); walls,
## columns, barriers and the undersides of the decks are SOLID, so the
## camera stays below the ceiling.
##
## All of it goes in the building's walls mesh (one shared material, the
## smooth painted wall style for bare concrete), so a parkade costs no more
## draw calls than any other building (docs/world_art.md).

const STOREY := 3.0 ## deck to deck
const SLAB := 0.35 ## deck thickness (2.65 m clear under each deck)
const END_BAY := 11.0 ## flat turning bay at each end, room to swing round from the ramp to an aisle
const LANE := 3.7 ## half the ramp's width, walls included
const WALL := 0.25 ## ramp walls, barriers and the outer wall
const STALL_DEPTH := 5.2
const STALL_WIDTH := 2.6
const PARAPET := 1.1 ## outer wall above each deck
const BARRIER := 1.0 ## ramp walls and the barrier along the ramp's opening
## The ramp's walls stop this far short of its ends: there the ramp is
## within 0.2 m of the deck beside it, so a car can cut in from the aisle.
const MOUTH := 4.0
## The roof jump ("roof_jump": true, or {"corner": 1 or -1, "angle":
## degrees}): a stunt ramp knocked together on the roof out of timber and
## plywood, in the corner at the entrance end (the +v corner unless
## "corner" says -1), angled "angle" degrees off the length of the roof
## toward that side, its lip over the corner of the parapet. Come down the
## other aisle, cut across the end bay along the yellow line, and it throws
## you off the corner and away down the street.
const JUMP_ANGLE := 60.0
const JUMP_WIDTH := 3.6
const JUMP_LENGTH := 10.0
const JUMP_LIP := 2.2 ## the lip above the roof (the parapet is 1.1)
const JUMP_OVER := 0.6 ## how far the lip hangs out past the corner
const PLYWOOD := Color(0.74, 0.6, 0.4)
const TIMBER := Color(0.5, 0.38, 0.25)
const HAZARD := Color(0.95, 0.72, 0.08)
const HAZARD_DARK := Color(0.08, 0.08, 0.08)
const TOWER_STALLS := 2 ## the stair tower takes the first stalls on the +v side
const OPENING_IN := 4.45 ## entrance openings run from here across...
const OPENING_OUT := 1.0 ## ...to this far in from the side walls

const CONCRETE := Color(0.67, 0.66, 0.63)
const DECK := Color(0.46, 0.46, 0.45)
const LINES := Color(0.9, 0.9, 0.84)
const TOWER_COLOUR := Color(0.55, 0.33, 0.26)
## Wall-shader styles (building_wall.gdshader): smooth painted, plain colour.
const STYLE_CONCRETE := 3.0
const STYLE_PLAIN := 6.0


static func is_parkade(landmark: Dictionary) -> bool:
	return str(landmark.get("style", "")) == "parkade"


# --- layout ---------------------------------------------------------------------------------

## Where everything goes, from the footprint: {c, u, v, hu, hv, floor_y,
## levels, base}. u points to the entrance end. floor_y is the ground floor's
## height, the ground just outside the entrance; base (local) is how far the
## foundation reaches down.
static func layout(ring: PackedVector2Array, landmark: Dictionary, terrain: Terrain, net: RoadNetwork) -> Dictionary:
	var obb := BuildingGenerator._obb(ring)
	var c: Vector2 = obb["center"]
	var u: Vector2 = obb["u"]
	var hu: float = obb["half_u"]
	var hv: float = obb["half_v"]
	# The entrance end: the one nearer the named street (or any street).
	var want := str(landmark.get("entrance_street", ""))
	var best_s := 1.0
	var best_d := INF
	for s: float in [1.0, -1.0]:
		var p := c + u * s * (hu + 5.0)
		var d := _street_distance(net, p, want)
		if d < best_d:
			best_d = d
			best_s = s
	u *= best_s
	var v := Vector2(-u.y, u.x)
	# Sampled 5 m out, past the ground lowered under the parkade (flatten).
	var floor_y := terrain.h2(c + u * (hu + 5.0))
	var low := INF
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var n := maxi(1, ceili(a.distance_to(b) / 2.0))
		for k in n:
			low = minf(low, terrain.h2(a.lerp(b, float(k) / n)))
	return {"c": c, "u": u, "v": v, "hu": hu, "hv": hv, "floor_y": floor_y,
		"levels": maxi(2, int(landmark.get("levels", 4))), "base": minf(-0.4, low - floor_y - 0.25),
		"jump": _jump_settings(landmark.get("roof_jump", false))}


## {} for no roof jump, else {"corner": 1 or -1, "angle": degrees}.
static func _jump_settings(j: Variant) -> Dictionary:
	if j is Dictionary:
		return {"corner": signf(float(j.get("corner", 1.0))) if float(j.get("corner", 1.0)) != 0.0 else 1.0,
			"angle": float(j.get("angle", JUMP_ANGLE))}
	if j is bool and j:
		return {"corner": 1.0, "angle": JUMP_ANGLE}
	return {}


static func _street_distance(net: RoadNetwork, p: Vector2, want: String) -> float:
	var best := INF
	for e in net.edges_near(Rect2(p - Vector2(40, 40), Vector2(80, 80))):
		if want != "" and e.name != want:
			continue
		for i in range(e.points.size() - 1):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, e.points[i], e.points[i + 1])))
	return best


## The layout of the parkade with this OSM id, found from its landmark
## entry's "at" ({} if it can't be). Main thread only (it caches).
static func find(data: StreetData, net: RoadNetwork, terrain: Terrain, id: String) -> Dictionary:
	if _found.has(id):
		return _found[id]
	var lm: Dictionary = data.config.get("landmarks", {}).get(id, {})
	var at: Array = lm.get("at", [])
	var out := {}
	if at.size() >= 2:
		var g := data.projection.to_ground(float(at[1]), float(at[0]))
		var cx := floori(g.x / data.chunk_size)
		var cz := floori(g.y / data.chunk_size)
		for dx in [0, -1, 1]:
			for dz in [0, -1, 1]:
				for b in data.load_chunk(cx + dx, cz + dz).buildings:
					if b.id == id and out.is_empty():
						out = layout(BuildingGenerator._clean_ring(b.ring), lm, terrain, net)
	if out.is_empty():
		push_warning("Parkade: couldn't find building %s (check its landmark entry's \"at\")" % id)
	_found[id] = out
	return out

static var _found := {}


## A point on the deck: `lu` along, `lv` across, on `level`, as a world position.
static func world_point(lay: Dictionary, lu: float, lv: float, level: int, lift := 0.0) -> Vector3:
	var p: Vector2 = (lay["c"] as Vector2) + (lay["u"] as Vector2) * lu + (lay["v"] as Vector2) * lv
	return Vector3(p.x, float(lay["floor_y"]) + level * STOREY + lift, p.y)


## Stalls along one side: [first stall's centre (u), how many].
static func _stalls(lay: Dictionary) -> Array:
	var run := (float(lay["hu"]) - END_BAY) * 2.0
	var n := int(floorf(run / STALL_WIDTH))
	return [-run * 0.5 + (run - n * STALL_WIDTH) * 0.5 + STALL_WIDTH * 0.5, n]


## A car backed into a stall, nose to the aisle. side is 1 or -1 (which
## side of the ramp), stall counts from the far end. level 0 is the ground.
static func stall_xform(lay: Dictionary, level: int, side: int, stall: int, lift := 0.35) -> Transform3D:
	var st := _stalls(lay)
	var i := clampi(stall, 0, int(st[1]) - 1)
	var lu := float(st[0]) + i * STALL_WIDTH
	var lv := signf(side) * (float(lay["hv"]) - WALL - STALL_DEPTH * 0.5)
	var nose: Vector2 = (lay["v"] as Vector2) * -signf(side)
	return Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.y)), world_point(lay, lu, lv, clampi(level, 0, int(lay["levels"]) - 1), lift))


## Standing in the aisle in front of a stall, looking at it.
static func aisle_xform(lay: Dictionary, level: int, side: int, stall: int) -> Transform3D:
	var st := _stalls(lay)
	var i := clampi(stall, 0, int(st[1]) - 1)
	var lu := float(st[0]) + i * STALL_WIDTH
	var lv := signf(side) * (float(lay["hv"]) - WALL - STALL_DEPTH - 2.2)
	var look: Vector2 = (lay["v"] as Vector2) * signf(side)
	return Transform3D(Basis(Vector3.UP, atan2(-look.x, -look.y)), world_point(lay, lu, lv, clampi(level, 0, int(lay["levels"]) - 1), 0.1))


## Lowers the ground under every parkade to just below its ground floor, so
## a hillside never pokes up through the bottom deck, and keeps parked cars
## (StreetProps) from blocking its way in. Run once at startup,
## after the streets are smoothed and before any chunk is built.
static func flatten(data: StreetData, net: RoadNetwork, terrain: Terrain) -> void:
	if terrain.is_flat():
		return
	_found.clear()
	var lms: Dictionary = data.config.get("landmarks", {})
	for id: String in lms:
		var lm: Variant = lms[id]
		if not (lm is Dictionary) or not is_parkade(lm):
			continue
		var lay := find(data, net, terrain, id)
		if lay.is_empty():
			continue
		var c: Vector2 = lay["c"]
		var u: Vector2 = lay["u"]
		var v: Vector2 = lay["v"]
		var reach_u: float = float(lay["hu"]) + terrain.spacing + 0.5
		var reach_v: float = float(lay["hv"]) + terrain.spacing + 0.5
		var r := maxf(reach_u, reach_v) * 1.5
		# No cars parked across the way in, out to the street.
		for k in 4:
			for lv: float in [-9.0, 0.0, 9.0]:
				data.keep_clear.append(c + u * (float(lay["hu"]) + 3.0 + k * 5.0) + v * lv)
		var under := float(lay["floor_y"]) - 0.3
		var ix0 := floori((c.x - r - terrain.origin.x) / terrain.spacing)
		var iz0 := floori((c.y - r - terrain.origin.y) / terrain.spacing)
		var n := ceili(r * 2.0 / terrain.spacing) + 1
		for iz in range(iz0, iz0 + n):
			for ix in range(ix0, ix0 + n):
				var p := terrain.origin + Vector2(ix, iz) * terrain.spacing - c
				if absf(p.dot(u)) <= reach_u and absf(p.dot(v)) <= reach_v:
					terrain.lower_grid(ix, iz, under)
	# The layouts read the ground 5 m out, which this doesn't touch, but
	# start afresh anyway.
	_found.clear()


# --- building it ----------------------------------------------------------------------------

## The stair tower, [u0, u1, v0, v1]: in the first stalls on the +v side
## at the far end, clear of the turning bay (a pickup swinging round from
## the aisle into the ramp needs all of it).
static func tower_rect(lay: Dictionary) -> Array:
	var st := _stalls(lay)
	var u0 := float(st[0]) - STALL_WIDTH * 0.5
	var hv: float = lay["hv"]
	return [u0, u0 + STALL_WIDTH * TOWER_STALLS, hv - WALL - STALL_DEPTH, hv - WALL]


## Builds the parkade into `walls` (and the stair tower's roof into `roof`),
## heights local to the ground floor. Returns {"collision": SOLID faces,
## "ground": GROUND faces}. lod leaves out the paint.
static func build(lay: Dictionary, walls: MeshKit, roof: MeshKit, lod: bool) -> Dictionary:
	var b := _Builder.new()
	b.lay = lay
	b.kit = walls
	b.lod = lod
	b.build_all()
	# The stair tower's roof.
	var tr := tower_rect(lay)
	roof.uv2 = Vector2.ZERO
	roof.color = BuildingGenerator._vertex_color(Color(0.3, 0.3, 0.3), 1.0)
	var top := b.tower_top
	roof.ground_quad(MeshKit.v3(b.p(tr[0], tr[2]), top), MeshKit.v3(b.p(tr[1], tr[2]), top),
		MeshKit.v3(b.p(tr[1], tr[3]), top), MeshKit.v3(b.p(tr[0], tr[3]), top))
	return {"collision": b.solid, "ground": b.ground}


class _Builder:
	var lay: Dictionary
	var kit: MeshKit
	var lod := false
	var solid := PackedVector3Array()
	var ground := PackedVector3Array()
	var tower_top := 0.0

	func p(lu: float, lv: float) -> Vector2:
		return (lay["c"] as Vector2) + (lay["u"] as Vector2) * lu + (lay["v"] as Vector2) * lv

	func q3(lu: float, lv: float, y: float) -> Vector3:
		var g := p(lu, lv)
		return Vector3(g.x, y, g.y)

	func _uv(lu: float, y: float) -> Vector2:
		# Negative x: no windows (building_wall.gdshader).
		return Vector2(-(lu + 200.0) / 2.6, y)

	## A level rectangle, top (GROUND) or underside (SOLID, for the camera).
	func flat(u0: float, u1: float, v0: float, v1: float, y: float, up: bool, colour: Color) -> void:
		kit.color = BuildingGenerator._vertex_color(colour, 0.0)
		var a := q3(u0, v0, y)
		var b := q3(u1, v0, y)
		var c := q3(u1, v1, y)
		var d := q3(u0, v1, y)
		var n := Vector3.UP if up else Vector3.DOWN
		var hy := 20.0 + v0
		kit.quad(a, b, c, d, n, _uv(u0, hy), _uv(u1, hy), _uv(u1, hy + v1 - v0), _uv(u0, hy + v1 - v0))
		var faces := PackedVector3Array([a, b, c, a, c, d])
		if up:
			ground.append_array(faces)
		else:
			solid.append_array(faces)

	## A ramp's deck from u0 (height y0) to u1 (y1) across v0..v1: its top
	## (GROUND) and underside (SOLID).
	func slope(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, under: bool) -> void:
		kit.color = BuildingGenerator._vertex_color(DECK, 0.0)
		var a := q3(u0, v0, y0)
		var b := q3(u1, v0, y1)
		var c := q3(u1, v1, y1)
		var d := q3(u0, v1, y0)
		var n := (b - a).cross(d - a).normalized()
		if n.y < 0.0:
			n = -n
		var hy := 20.0 + v0
		kit.quad(a, b, c, d, n, _uv(u0, hy), _uv(u1, hy), _uv(u1, hy + v1 - v0), _uv(u0, hy + v1 - v0))
		ground.append_array(PackedVector3Array([a, b, c, a, c, d]))
		if under:
			kit.color = BuildingGenerator._vertex_color(CONCRETE, 0.0)
			var s := Vector3(0, -SLAB, 0)
			kit.quad(a + s, b + s, c + s, d + s, -n, _uv(u0, hy), _uv(u1, hy), _uv(u1, hy + v1 - v0), _uv(u0, hy + v1 - v0))
			solid.append_array(PackedVector3Array([a + s, b + s, c + s, a + s, c + s, d + s]))

	## A block from u0 to u1 and v0 to v1 whose bottom and top can slope
	## along u (bottom b0 -> b1, top t0 -> t1). All of it SOLID; `ref` is
	## the floor it stands on (for the shader's grime at the foot of a wall).
	func block(u0: float, u1: float, v0: float, v1: float, b0: float, b1: float, t0: float, t1: float, colour: Color, ref := 0.0, ends := true) -> void:
		kit.color = BuildingGenerator._vertex_color(colour, 0.0)
		var lo0 := q3(u0, v0, b0)
		var lo1 := q3(u1, v0, b1)
		var lo2 := q3(u1, v1, b1)
		var lo3 := q3(u0, v1, b0)
		var hi0 := q3(u0, v0, t0)
		var hi1 := q3(u1, v0, t1)
		var hi2 := q3(u1, v1, t1)
		var hi3 := q3(u0, v1, t0)
		var U: Vector2 = lay["u"]
		var V: Vector2 = lay["v"]
		var nu := Vector3(U.x, 0, U.y)
		var nv := Vector3(V.x, 0, V.y)
		# Long sides (-v and +v), then the ends (-u, +u), then the top.
		_side(lo0, lo1, hi1, hi0, -nv, u0, u1, b0 - ref, b1 - ref, t1 - ref, t0 - ref)
		_side(lo3, lo2, hi2, hi3, nv, u0, u1, b0 - ref, b1 - ref, t1 - ref, t0 - ref)
		if ends:
			_side(lo0, lo3, hi3, hi0, -nu, v0, v1, b0 - ref, b0 - ref, t0 - ref, t0 - ref)
			_side(lo1, lo2, hi2, hi1, nu, v0, v1, b1 - ref, b1 - ref, t1 - ref, t1 - ref)
		var top_n := (hi1 - hi0).cross(hi3 - hi0).normalized()
		if top_n.y < 0.0:
			top_n = -top_n
		kit.quad(hi0, hi1, hi2, hi3, top_n, _uv(u0, 30.0), _uv(u1, 30.0), _uv(u1, 30.0 + v1 - v0), _uv(u0, 30.0 + v1 - v0))
		solid.append_array(PackedVector3Array([hi0, hi1, hi2, hi0, hi2, hi3]))

	func _side(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, s0: float, s1: float, ya: float, yb: float, yc: float, yd: float) -> void:
		kit.quad(a, b, c, d, n, _uv(s0, ya), _uv(s1, yb), _uv(s1, yc), _uv(s0, yd))
		solid.append_array(PackedVector3Array([a, b, c, a, c, d]))

	func build_all() -> void:
		var hu: float = lay["hu"]
		var hv: float = lay["hv"]
		var levels: int = lay["levels"]
		var base: float = lay["base"]
		var top_y := (levels - 1) * STOREY
		var ramp_u0 := -hu + END_BAY ## the far end of each ramp (low)
		var ramp_u1 := hu - END_BAY ## the entrance end (high)
		var aisle_in := LANE + WALL
		kit.uv2 = Vector2(STYLE_CONCRETE, 0.0)

		# Ground floor and its foundation.
		flat(-hu, hu, -hv, hv, 0.0, true, DECK)
		# A level apron out of each way in, over the ground lowered round
		# the walls (flatten), to where the floor's height was taken.
		var outside := 0.0
		for s: float in [-1.0, 1.0]:
			var v0 := s * OPENING_IN
			var v1 := s * (hv - OPENING_OUT)
			var a := q3(hu, minf(v0, v1), 0.0)
			var b := q3(hu + 5.0, minf(v0, v1), outside)
			var c := q3(hu + 5.0, maxf(v0, v1), outside)
			var d := q3(hu, maxf(v0, v1), 0.0)
			kit.color = BuildingGenerator._vertex_color(DECK, 0.0)
			kit.quad(a, b, c, d, Vector3.UP, _uv(hu, 20.0), _uv(hu + 5.0, 20.0), _uv(hu + 5.0, 30.0), _uv(hu, 30.0))
			ground.append_array(PackedVector3Array([a, b, c, a, c, d]))

		for level in levels:
			var y := level * STOREY
			var below := y - SLAB if level > 0 else base
			# The deck (the ground floor's is above): both side strips, and
			# the turning bays across the ramp's lane at each end.
			if level > 0:
				for s: float in [-1.0, 1.0]:
					var v0 := LANE if s > 0.0 else -hv
					var v1 := hv if s > 0.0 else -LANE
					flat(-hu, hu, v0, v1, y, true, DECK)
					flat(-hu, hu, v0, v1, y - SLAB, false, CONCRETE)
				for e: Array in [[-hu, ramp_u0], [ramp_u1, hu]]:
					flat(e[0], e[1], -LANE, LANE, y, true, DECK)
					flat(e[0], e[1], -LANE, LANE, y - SLAB, false, CONCRETE)
			# The outer wall: a parapet round each deck (on the ground floor,
			# down to the foundation, with the two ways in at the entrance end).
			var top := y + PARAPET
			block(-hu, hu, hv - WALL, hv, below, below, top, top, CONCRETE, y)
			block(-hu, hu, -hv, -hv + WALL, below, below, top, top, CONCRETE, y)
			block(-hu, -hu + WALL, -hv + WALL, hv - WALL, below, below, top, top, CONCRETE, y)
			if level == 0:
				block(hu - WALL, hu, -hv + WALL, hv - WALL, base, base, 0.0, 0.0, CONCRETE, 0.0)
				for piece: Array in [[-hv + WALL, -hv + OPENING_OUT], [-OPENING_IN, OPENING_IN], [hv - OPENING_OUT, hv - WALL]]:
					block(hu - WALL, hu, piece[0], piece[1], 0.0, 0.0, top, top, CONCRETE, 0.0)
			else:
				block(hu - WALL, hu, -hv + WALL, hv - WALL, below, below, top, top, CONCRETE, y)
			# Paint: stall lines along both sides.
			if not lod:
				_stall_lines(y)
			if level == levels - 1:
				if not (lay.get("jump", {}) as Dictionary).is_empty():
					_jump(y)
				continue
			var up := y + STOREY
			# The ramp up to the next level, with a wall each side (from the
			# ground on the ground floor, closing the space under it).
			slope(ramp_u0, ramp_u1, -LANE, LANE, y, up, level > 0)
			for s: float in [-1.0, 1.0]:
				var w0 := s * (LANE - WALL)
				var w1 := s * LANE
				# (The ground floor's stays closed at the high end, over the
				# space under the ramp.)
				var wu0 := ramp_u0 + MOUTH
				var wu1 := ramp_u1 if level == 0 else ramp_u1 - MOUTH
				var f0 := (wu0 - ramp_u0) / (ramp_u1 - ramp_u0)
				var f1 := (wu1 - ramp_u0) / (ramp_u1 - ramp_u0)
				var lo0 := y if level == 0 else y + f0 * STOREY - SLAB
				var lo1 := y if level == 0 else y + f1 * STOREY - SLAB
				block(wu0, wu1, minf(w0, w1), maxf(w0, w1), lo0, lo1, y + f0 * STOREY + BARRIER, y + f1 * STOREY + BARRIER, CONCRETE, y)
			if level == 0:
				# The high end of the space under the first ramp.
				block(ramp_u1 - 0.3, ramp_u1, -LANE + WALL, LANE - WALL, 0.0, 0.0, up - 0.02, up - 0.02, CONCRETE, 0.0)
			# Columns: along the side walls, and along the ramp's edges.
			var st := _stalls_here()
			for i in range(0, int(st[1]) + 1, 3):
				var lu := float(st[0]) - STALL_WIDTH * 0.5 + i * STALL_WIDTH
				for s: float in [-1.0, 1.0]:
					var o0 := s * (hv - 0.45)
					var o1 := s * hv
					block(lu - 0.22, lu + 0.22, minf(o0, o1), maxf(o0, o1), top, top, up - SLAB, up - SLAB, CONCRETE, y)
					if lu < ramp_u0 + MOUTH + 0.5 or lu > ramp_u1 - MOUTH - 0.5:
						continue
					var c0 := s * (LANE + WALL * 0.5 - 0.2)
					var c1 := s * (LANE + WALL * 0.5 + 0.2)
					block(lu - 0.25, lu + 0.25, minf(c0, c1), maxf(c0, c1), y, y, up - SLAB, up - SLAB, CONCRETE, y)
			for s: float in [-1.0, 1.0]:
				for e: float in [-1.0, 1.0]:
					var o0 := s * (hv - 0.45)
					var o1 := s * hv
					var eu := e * (hu - 0.22)
					block(eu - 0.22, eu + 0.22, minf(o0, o1), maxf(o0, o1), top, top, up - SLAB, up - SLAB, CONCRETE, y)
			# Barriers along the ramp's opening on the deck above.
			for s: float in [-1.0, 1.0]:
				var b0 := s * LANE
				var b1 := s * aisle_in
				block(ramp_u0 + MOUTH, ramp_u1 - MOUTH, minf(b0, b1), maxf(b0, b1), up - SLAB, up - SLAB, up + BARRIER, up + BARRIER, CONCRETE, up)

		# The stair tower, up past the roof.
		tower_top = top_y + 3.2
		kit.uv2 = Vector2(0.0, 0.0) # brick
		var tr := Parkade.tower_rect(lay)
		block(tr[0], tr[1], tr[2], tr[3], base, base, tower_top, tower_top, TOWER_COLOUR, 0.0)
		kit.uv2 = Vector2(STYLE_CONCRETE, 0.0)

	## The roof jump: a plywood deck on cross-bearers, curving up to a lip
	## with a hazard-striped board across it, on timber posts braced
	## diagonally down both sides (see JUMP_*). Its top is GROUND; the posts
	## are SOLID; the bracing is only drawn.
	func _jump(y: float) -> void:
		var hu: float = lay["hu"]
		var hv: float = lay["hv"]
		var j: Dictionary = lay["jump"]
		var side: float = j["corner"]
		var ang := deg_to_rad(float(j["angle"]))
		var ax := Vector2(cos(ang), side * sin(ang)) # along the ramp, in (u, v)
		var across := Vector2(-ax.y, ax.x)
		var lip_mid := Vector2(hu, side * hv) + ax * JUMP_OVER
		var toe := lip_mid - ax * JUMP_LENGTH
		var hw := JUMP_WIDTH * 0.5
		var at := func(d: float, w: float, h: float) -> Vector3:
			var l := toe + ax * d + across * w
			return q3(l.x, l.y, y + h)
		var height := func(d: float) -> float:
			var t := clampf(d / JUMP_LENGTH, 0.0, 1.0)
			return JUMP_LIP * (0.35 * t + 0.65 * t * t)
		kit.uv2 = Vector2(STYLE_PLAIN, 0.0)
		# The deck, a sheet of plywood at a time (each a shade different).
		var steps := 10
		for k in steps:
			var d0 := JUMP_LENGTH * k / steps
			var d1 := JUMP_LENGTH * (k + 1) / steps
			var h0: float = height.call(d0)
			var h1: float = height.call(d1)
			var a: Vector3 = at.call(d0, -hw, h0)
			var b: Vector3 = at.call(d1, -hw, h1)
			var c: Vector3 = at.call(d1, hw, h1)
			var d: Vector3 = at.call(d0, hw, h0)
			var n := (b - a).cross(d - a).normalized()
			if n.y < 0.0:
				n = -n
			kit.color = BuildingGenerator._vertex_color(PLYWOOD.darkened(0.06 * float((k * 7) % 3)), 0.0)
			kit.quad(a, b, c, d, n)
			ground.append_array(PackedVector3Array([a, b, c, a, c, d]))
			var dn := Vector3(0, -0.06, 0)
			kit.color = BuildingGenerator._vertex_color(PLYWOOD.darkened(0.25), 0.0)
			kit.quad(a + dn, b + dn, c + dn, d + dn, -n)
			kit.quad(a, b, b + dn, a + dn, -wdir(across))
			kit.quad(d, c, c + dn, d + dn, wdir(across))
		# The lip board, striped.
		var lip_h: float = height.call(JUMP_LENGTH)
		var stripes := 6
		for k in stripes:
			var w0 := lerpf(-hw, hw, float(k) / stripes)
			var w1 := lerpf(-hw, hw, float(k + 1) / stripes)
			kit.color = BuildingGenerator._vertex_color(HAZARD if k % 2 == 0 else HAZARD_DARK, 0.0)
			var p0: Vector3 = at.call(JUMP_LENGTH, w0, lip_h - 0.3)
			var p1: Vector3 = at.call(JUMP_LENGTH, w1, lip_h - 0.3)
			kit.quad(p0, p1, p1 + Vector3(0, 0.3, 0), p0 + Vector3(0, 0.3, 0), wdir(ax))
		# Posts, cross-bearers under the deck, and braces down the sides. A
		# post stands on the roof, or on the parapet where it's over the
		# wall; past the wall there's nothing to stand on.
		kit.color = BuildingGenerator._vertex_color(TIMBER, 0.0)
		var stations := [0.6, 2.6, 4.6, 6.6, 8.4]
		var feet := {}
		for d: float in stations:
			var top_h: float = height.call(d) - 0.06
			if top_h < 0.25:
				continue
			_beam(at.call(d, -hw, top_h - 0.08), at.call(d, hw, top_h - 0.08), 0.1, 0.14, false)
			for w: float in [-hw + 0.1, hw - 0.1]:
				var l := toe + ax * d + across * w
				var foot := 0.0
				if l.x > hu - 0.05 or absf(l.y) > hv - 0.05:
					continue
				if l.x > hu - WALL - 0.05 or absf(l.y) > hv - WALL - 0.05:
					foot = PARAPET
				if top_h - foot < 0.2:
					continue
				var p0: Vector3 = at.call(d, w, foot)
				var p1: Vector3 = at.call(d, w, top_h - 0.16)
				_beam(p0, p1, 0.14, 0.14, true)
				feet["%.1f/%.2f" % [d, w]] = [p0, p1]
		# Braces: from each foot up to the next post's top, both sides.
		for w: float in [-hw + 0.1, hw - 0.1]:
			for i in stations.size() - 1:
				var a: Variant = feet.get("%.1f/%.2f" % [stations[i], w])
				var b: Variant = feet.get("%.1f/%.2f" % [stations[i + 1], w])
				if a == null or b == null:
					continue
				_beam((a as Array)[0], (b as Array)[1], 0.06, 0.12, false)
		# A runner along each side under the deck edge, post to post.
		for w: float in [-hw + 0.1, hw - 0.1]:
			for i in stations.size() - 1:
				var a: Variant = feet.get("%.1f/%.2f" % [stations[i], w])
				var b: Variant = feet.get("%.1f/%.2f" % [stations[i + 1], w])
				if a != null and b != null:
					_beam((a as Array)[1], (b as Array)[1], 0.08, 0.16, false)
		# A yellow line back across the end bay to line up on.
		if not lod:
			kit.color = BuildingGenerator._vertex_color(HAZARD, 0.0)
			var run := 0.0
			for k in 40:
				var l := toe - ax * (k * 0.5 + 0.5)
				if l.x < hu - END_BAY + 0.3 or absf(l.y) > hv - WALL - 0.5:
					break
				run = k * 0.5 + 0.5
			if run > 1.0:
				var l0 := toe - ax * run
				var a: Vector3 = q3(l0.x - across.x * 0.08, l0.y - across.y * 0.08, y + 0.012)
				var b: Vector3 = q3(toe.x - across.x * 0.08, toe.y - across.y * 0.08, y + 0.012)
				var c: Vector3 = q3(toe.x + across.x * 0.08, toe.y + across.y * 0.08, y + 0.012)
				var d: Vector3 = q3(l0.x + across.x * 0.08, l0.y + across.y * 0.08, y + 0.012)
				kit.quad(a, b, c, d, Vector3.UP)
		kit.uv2 = Vector2(STYLE_CONCRETE, 0.0)

	## A direction in the parkade's (u, v) frame, in the world.
	func wdir(l: Vector2) -> Vector3:
		var g := (lay["u"] as Vector2) * l.x + (lay["v"] as Vector2) * l.y
		return Vector3(g.x, 0.0, g.y)

	## A square-ish timber from a to b, w wide and h deep. Posts (solid)
	## also go in the collision.
	func _beam(a: Vector3, b: Vector3, w: float, h: float, solid_too: bool) -> void:
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3((lay["u"] as Vector2).x, 0, (lay["u"] as Vector2).y)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		var sw := side * (w * 0.5)
		var uh := up * (h * 0.5)
		var c := [a - sw - uh, a + sw - uh, a + sw + uh, a - sw + uh]
		var e := [b - sw - uh, b + sw - uh, b + sw + uh, b - sw + uh]
		for k in 4:
			var k2 := (k + 1) % 4
			var mid: Vector3 = ((c[k] + c[k2]) * 0.5) - a
			kit.quad(c[k], c[k2], e[k2], e[k], mid.normalized())
			if solid_too:
				solid.append_array(PackedVector3Array([c[k], c[k2], e[k2], c[k], e[k2], e[k]]))
		kit.quad(e[0], e[1], e[2], e[3], dir)

	func _stalls_here() -> Array:
		return Parkade._stalls(lay)

	func _stall_lines(y: float) -> void:
		var hv: float = lay["hv"]
		var st := _stalls_here()
		kit.uv2 = Vector2(STYLE_PLAIN, 0.0)
		kit.color = BuildingGenerator._vertex_color(LINES, 0.0)
		var ly := y + 0.012
		for s: float in [-1.0, 1.0]:
			var v0 := s * (hv - WALL - STALL_DEPTH)
			var v1 := s * (hv - WALL - 0.3)
			for i in int(st[1]) + 1:
				if s > 0.0 and i > 0 and i < TOWER_STALLS:
					continue
				var lu := float(st[0]) - STALL_WIDTH * 0.5 + i * STALL_WIDTH
				kit.quad(q3(lu - 0.06, v0, ly), q3(lu + 0.06, v0, ly), q3(lu + 0.06, v1, ly), q3(lu - 0.06, v1, ly), Vector3.UP)
		kit.uv2 = Vector2(STYLE_CONCRETE, 0.0)

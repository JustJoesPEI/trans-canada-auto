class_name EditLines
extends RefCounted
## Fences, walls, hedges, guardrails and banks of armour stone drawn as
## lines in the map editor (edits.json "lines", loaded by StreetData into
## `lines`). Built by StreetProps in full-detail chunks: each chunk builds
## the 3 m pieces whose middles are inside it, so a line crossing several
## chunks is built once. Fences and walls leave a gap where they cross a
## street; guardrails and stone don't. All solid.

## Every kind the editor offers, with its default height (metres).
const KINDS := {
	"chain_link": 1.8, "chain_link_barbed": 2.2, "wood_fence": 1.8, "picket_fence": 1.0,
	"split_rail": 1.1, "hedge": 1.3, "stone_wall": 1.0, "brick_wall": 1.8, "concrete_wall": 2.4,
	"guardrail": 0.75, "armour_stone": 0.9,
	"patio_rail": 1.0, "string_lights": 5.0,
}
const PIECE := 3.0

var props: StreetProps
var _solid := MeshKit.new() ## vertex-coloured: walls, boards, hedges, posts
var _wire := MeshKit.new() ## chain-link fabric
var _faces := PackedVector3Array()
var _rocks: Array[Transform3D] = []
var _bulbs := MeshKit.new() ## string lights' bulbs, lit


func _init(owner: StreetProps) -> void:
	props = owner
	_solid.use_color = true


## Builds the map editor's lines in this chunk, and `extra` (TownDressing's
## yard fences and hedges, in the same form, built whole: "own" lines
## belong to this chunk's houses even where they reach over its edge).
func build(root: Node3D, extra: Array[Dictionary] = []) -> void:
	if props.data.lines.is_empty() and extra.is_empty():
		return
	for line: Dictionary in props.data.lines:
		_build_line(line)
	for line: Dictionary in extra:
		_build_line(line)
	# A server draws nothing: only the collision is kept (ChunkBuilder strips
	# the meshes anyway, and simplifying them for LODs is the costly part).
	var drawn := not ChunkBuilder.server_build()
	if drawn and not _solid.verts.is_empty():
		var mat := Materials.get_shared().vertex_colour(0.85)
		var mi := MeshInstance3D.new()
		mi.name = "EditLines"
		# Indexed, with automatic LODs (docs/world_art.md W1): a long fence
		# round a yard is thousands of triangles of posts and rails.
		mi.mesh = ModelLod.finish_kits([[_solid, mat]])
		root.add_child(mi)
	if drawn and not _bulbs.verts.is_empty():
		var bi := MeshInstance3D.new()
		bi.name = "StringLights"
		bi.mesh = ModelLod.finish_kits([[_bulbs, Materials.get_shared().glow(Color(1.0, 0.86, 0.6), 1.6)]])
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		WorldLod.limit(bi, 2.0)
		root.add_child(bi)
	if drawn and not _wire.verts.is_empty():
		var wi := MeshInstance3D.new()
		wi.name = "EditChainLink"
		wi.mesh = _wire.commit(null, StreetProps._chain_link)
		root.add_child(wi)
	if drawn and not _rocks.is_empty():
		# Tiled, drawn as far as a stone reads, shadows from a plain prism
		# (docs/world_art.md W3, W4, W6), like the riprap.
		var xf: Array = []
		xf.assign(_rocks)
		ShadowProxy.add(root, "EditArmourStone", StreetProps._rock, xf, WorldLod.draw_distance(StreetProps._rock),
			ShadowProxy.for_mesh(StreetProps._rock, ShadowProxy.Shape.ROUND), 40.0)
	if not _faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "EditLineCollision"
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


func _build_line(line: Dictionary) -> void:
	var kind := str(line["kind"])
	var pts: PackedVector2Array = line["pts"]
	var h := float(line["height"])
	var gaps := kind not in ["guardrail", "armour_stone", "patio_rail"]
	var own: bool = line.get("own", false)
	if kind == "string_lights":
		_string_lights(pts, h, own)
		return
	var along := 0.0
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var length := p0.distance_to(p1)
		if length < 0.05:
			continue
		var pieces := maxi(1, int(ceil(length / PIECE)))
		for k in pieces:
			var q0 := p0.lerp(p1, float(k) / pieces)
			var q1 := p0.lerp(p1, float(k + 1) / pieces)
			var mid := (q0 + q1) * 0.5
			var u0 := along + p0.distance_to(q0)
			if not own and not props.inside_area(mid):
				continue
			if gaps and (props.net.road_at(mid) != null or props.net.in_junction(mid)):
				continue
			_piece(kind, q0, q1, h, u0, k == 0, k == pieces - 1 and i == pts.size() - 2)
		along += length


## One piece of a line, q0 to q1 on the ground.
func _piece(kind: String, q0: Vector2, q1: Vector2, h: float, u0: float, first: bool, last: bool) -> void:
	var t := props.terrain
	var g0 := t.h2(q0)
	var g1 := t.h2(q1)
	var d := (q1 - q0).normalized()
	var n3 := Vector3(d.y, 0.0, -d.x)
	match kind:
		"chain_link", "chain_link_barbed":
			var u1 := u0 + q0.distance_to(q1)
			_wire.quad(MeshKit.v3(q0, g0 + 0.05), MeshKit.v3(q1, g1 + 0.05), MeshKit.v3(q1, g1 + h), MeshKit.v3(q0, g0 + h), n3,
				Vector2(u0, 0.05), Vector2(u1, 0.05), Vector2(u1, h), Vector2(u0, h))
			_wall_faces(q0, q1, g0, g1, h)
			_colour(Color(0.46, 0.48, 0.48))
			var barbed := kind == "chain_link_barbed"
			var top := h + (0.45 if barbed else 0.05)
			for q: Array in [[q0, g0], [q1, g1]]:
				StreetProps._bar(_solid, MeshKit.v3(q[0], q[1] - 0.2), MeshKit.v3(q[0], q[1] + top), 0.03)
			StreetProps._bar(_solid, MeshKit.v3(q0, g0 + h), MeshKit.v3(q1, g1 + h), 0.02)
			if barbed:
				for y: float in [h + 0.15, h + 0.3, h + 0.45]:
					StreetProps._bar(_solid, MeshKit.v3(q0, g0 + y), MeshKit.v3(q1, g1 + y), 0.006)
		"wood_fence":
			# Weathered pressure-treated board, the Island's back-yard fence.
			_colour(Color(0.56, 0.53, 0.47))
			_slab(q0, q1, g0, g1, 0.0, h, 0.02)
			_colour(Color(0.48, 0.45, 0.4))
			_slab(q0, q1, g0, g1, h * 0.12, h * 0.12 + 0.09, 0.045)
			_slab(q0, q1, g0, g1, h * 0.85, h * 0.85 + 0.09, 0.045)
			_post(q0, g0, h + 0.05, 0.05)
			if last:
				_post(q1, g1, h + 0.05, 0.05)
			_wall_faces(q0, q1, g0, g1, h)
		"picket_fence":
			_colour(Color(0.93, 0.93, 0.9))
			var length := q0.distance_to(q1)
			var count := maxi(1, int(length / 0.14))
			for j in count:
				var a := q0.lerp(q1, (j + 0.2) / count)
				var b := q0.lerp(q1, (j + 0.75) / count)
				var ga := lerpf(g0, g1, (j + 0.5) / count)
				_slab(a, b, ga, ga, 0.0, h - 0.06, 0.012)
				_slab(a.lerp(b, 0.25), b.lerp(a, 0.25), ga, ga, h - 0.06, h, 0.012)
			_slab(q0, q1, g0, g1, h * 0.25, h * 0.25 + 0.07, 0.03)
			_slab(q0, q1, g0, g1, h * 0.7, h * 0.7 + 0.07, 0.03)
			_post(q0, g0, h + 0.05, 0.045)
			if last:
				_post(q1, g1, h + 0.05, 0.045)
			_wall_faces(q0, q1, g0, g1, h)
		"split_rail":
			_colour(Color(0.45, 0.38, 0.3))
			for y: float in [h * 0.35, h * 0.75]:
				StreetProps._bar(_solid, MeshKit.v3(q0, g0 + y), MeshKit.v3(q1, g1 + y), 0.05)
			_post(q0, g0, h, 0.07)
			if last:
				_post(q1, g1, h, 0.07)
			_wall_faces(q0, q1, g0, g1, h)
		"hedge":
			# Cedar, mostly.
			_colour(Color(0.23, 0.35, 0.17))
			_slab(q0, q1, g0, g1, -0.1, h - 0.15, 0.4)
			_colour(Color(0.27, 0.4, 0.19))
			_slab(q0, q1, g0, g1, h - 0.15, h, 0.32)
			_wall_faces(q0, q1, g0, g1, h)
		"stone_wall":
			_colour(Color(0.52, 0.5, 0.46))
			_slab(q0, q1, g0, g1, -0.2, h - 0.08, 0.25)
			_colour(Color(0.6, 0.58, 0.54))
			_slab(q0, q1, g0, g1, h - 0.08, h, 0.29)
			_wall_faces(q0, q1, g0, g1, h)
		"brick_wall":
			_colour(Color(0.55, 0.26, 0.2))
			_slab(q0, q1, g0, g1, -0.2, h - 0.08, 0.11)
			_colour(Color(0.7, 0.68, 0.63))
			_slab(q0, q1, g0, g1, h - 0.08, h, 0.15)
			if first:
				_post(q0, g0, h + 0.1, 0.2)
			if last:
				_post(q1, g1, h + 0.1, 0.2)
			_wall_faces(q0, q1, g0, g1, h)
		"patio_rail":
			# A black square-bar café railing: top and bottom rails, posts at
			# the ends, thin bars between (flat, two triangles a side each).
			_colour(Color(0.06, 0.06, 0.06))
			_slab(q0, q1, g0, g1, h - 0.05, h, 0.025)
			_slab(q0, q1, g0, g1, 0.08, 0.12, 0.015)
			var length := q0.distance_to(q1)
			var count := maxi(1, int(length / 0.13))
			for j in count:
				var a := q0.lerp(q1, (j + 0.4) / count)
				var b := q0.lerp(q1, (j + 0.6) / count)
				var ga := lerpf(g0, g1, (j + 0.5) / count)
				_slab(a, b, ga, ga, 0.12, h - 0.05, 0.006)
			_post(q0, g0, h + 0.04, 0.03)
			if last:
				_post(q1, g1, h + 0.04, 0.03)
			_wall_faces(q0, q1, g0, g1, h)
		"concrete_wall":
			_colour(Color(0.66, 0.65, 0.62))
			_slab(q0, q1, g0, g1, -0.2, h, 0.12)
			_wall_faces(q0, q1, g0, g1, h)
		"guardrail":
			_colour(Color(0.62, 0.64, 0.64))
			var top := maxf(h, 0.5)
			_slab(q0, q1, g0, g1, top - 0.32, top, 0.04)
			_colour(Color(0.35, 0.3, 0.25))
			var length := q0.distance_to(q1)
			for j in maxi(1, int(round(length / 1.9))):
				var a := q0.lerp(q1, float(j) / maxi(1, int(round(length / 1.9))))
				_post(a + Vector2(n3.x, n3.z) * 0.12, t.h2(a), top - 0.05, 0.075)
			_wall_faces(q0, q1, g0, g1, top)
		"armour_stone":
			var length := q0.distance_to(q1)
			var count := maxi(1, int(length / 1.1))
			for j in count:
				var a := q0.lerp(q1, (j + 0.5) / count)
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(Vector2i(roundi(a.x * 10.0), roundi(a.y * 10.0)))
				var s := rng.randf_range(0.8, 1.3) * h / 0.9
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(1.0, 1.4), s, s))
				_rocks.append(Transform3D(basis, MeshKit.v3(a, t.h2(a) + 0.1 * s)))
			_wall_faces(q0, q1, g0, g1, h * 0.8)


func _colour(c: Color) -> void:
	_solid.color = c.srgb_to_linear()


## A box along q0-q1, half_t thick, from y0 to y1 above the ground.
func _slab(q0: Vector2, q1: Vector2, g0: float, g1: float, y0: float, y1: float, half_t: float) -> void:
	var d := (q1 - q0).normalized()
	var off := Vector2(d.y, -d.x) * half_t
	var a := [q0 + off, q1 + off, q1 - off, q0 - off]
	var g := [g0, g1, g1, g0]
	var n := Vector3(off.x, 0.0, off.y).normalized()
	var nd := Vector3(d.x, 0.0, d.y)
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for k in 4:
		lo.append(MeshKit.v3(a[k], g[k] + y0))
		hi.append(MeshKit.v3(a[k], g[k] + y1))
	_solid.quad(lo[0], lo[1], hi[1], hi[0], n)
	_solid.quad(lo[2], lo[3], hi[3], hi[2], -n)
	_solid.quad(lo[1], lo[2], hi[2], hi[1], nd)
	_solid.quad(lo[3], lo[0], hi[0], hi[3], -nd)
	_solid.quad(hi[0], hi[1], hi[2], hi[3], Vector3.UP)


## A square post, half wide, standing at q.
func _post(q: Vector2, g: float, h: float, half: float) -> void:
	var d := Vector2(half, 0.0)
	_slab(q - d, q + d, g, g, -0.2, h, half)


## Collision for one piece: a thin wall the height of the fence.
func _wall_faces(q0: Vector2, q1: Vector2, g0: float, g1: float, h: float) -> void:
	_faces.append_array(PackedVector3Array([MeshKit.v3(q0, g0 - 0.2), MeshKit.v3(q1, g1 - 0.2), MeshKit.v3(q1, g1 + h),
		MeshKit.v3(q0, g0 - 0.2), MeshKit.v3(q1, g1 + h), MeshKit.v3(q0, g0 + h)]))


## Strings of bulbs hung from point to point at height h, sagging between,
## the way they cross Victoria Row and Sydney Street all summer: a thin
## dark wire and a warm bulb every 0.6 m. No collision, no gaps over the
## street (that's where they go).
func _string_lights(pts: PackedVector2Array, h: float, own: bool) -> void:
	_colour(Color(0.05, 0.05, 0.05))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		if length < 0.5:
			continue
		if not own and not props.inside_area((a + b) * 0.5):
			continue
		var ga := props.terrain.h2(a) + h
		var gb := props.terrain.h2(b) + h
		var sag := minf(0.9, length * 0.05)
		var steps := maxi(2, int(length / 0.6))
		var prev := MeshKit.v3(a, ga)
		for k in range(1, steps + 1):
			var t := float(k) / steps
			var p := MeshKit.v3(a.lerp(b, t), lerpf(ga, gb, t) - sag * 4.0 * t * (1.0 - t))
			StreetProps._bar(_solid, prev, p, 0.006)
			if k < steps:
				var c := p + Vector3.DOWN * 0.06
				for f: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
					_bulbs.quad(c - f * 0.04 - Vector3.UP * 0.04, c + f * 0.04 - Vector3.UP * 0.04, c + f * 0.04 + Vector3.UP * 0.04, c - f * 0.04 + Vector3.UP * 0.04, f.cross(Vector3.UP))
			prev = p

class_name BodyPaint
extends Node
## Paint on a person, and the hits that put them out (docs/design.md
## section 2, "Hits and outs", and section 3, "Players"). The player has
## one; officers (the Police piece) will. The person's own script forwards
## `take_paint_hit`, `is_out` and `went_out` to it.
##
## Hits: 3 and you're out; a head hit counts as 2 (PaintShots asks
## `is_head_point`). They wear off one at a time, the first after 6 s
## without a hit and each next one 6 s after that. Out: `out` is true, the
## hands go up (HumanoidModel.hands_up) and the owner's marker won't fire.
## What happens next (walk off, respawn, getting caught) isn't decided
## here: `went_out` tells whoever decides, and they call `revive()`.
##
## Splats: the last 16, drawn like a car's paint (PaintCoverage): a
## material overlay on the body's mesh with the hits as uniforms, made on
## the first hit. The body is skinned, but its mesh carries every point's
## position at rest (BodyBuilder puts it in UV and UV2.x), so each splat is
## moved back into the rest pose once, when it lands, by the bone nearest
## it, and stays on the clothes as they move with nothing updated per frame.

## Out (by is the shooter, or null).
signal went_out(by: Node)
## The hit count changed (for the HUD's pips).
signal hits_changed(hits: int)
## Back in: `revive()` was called.
signal revived

const OUT_HITS := 3 ## design
const WEAR_TIME := 6.0 ## s without a hit before one wears off (design)
const MAX_SPLATS := 16 ## design
## m: a paintball's splat on clothes (not in the design; smaller than on a
## car, so a few hits read as separate splats on a chest).
const SPLAT_SIZE := 0.085
## Where the head starts, as a share of the person's height (the neck joint
## is at 0.85 in BodyBuilder).
const HEAD_FROM := 0.855

## The model to paint (its mesh_instance gets the overlay).
var model: HumanoidModel
## False outside events: paint only, never out (design section 2, "The rule
## outside events"). The Wanted/event code sets it; true until then.
var can_go_out := true
var hits := 0
var out := false
## The splats: {point, normal (rest space), colour, size, shape, turn}.
var splats: Array[Dictionary] = []

var _since_hit := 0.0
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## A hit: `value` hits (2 for a head shot), from `shooter`, at a point in
## the world, in `colour`. Paints whatever happens; counts toward an out
## unless already out (or outs are off).
func take_hit(value: int, shooter: Node, point: Vector3, colour: Color) -> void:
	add_splat(point, colour)
	if out or not can_go_out or value <= 0:
		return
	hits = mini(OUT_HITS, hits + value)
	_since_hit = 0.0
	hits_changed.emit(hits)
	if hits >= OUT_HITS:
		out = true
		if model != null:
			model.hands_up = 1.0
		went_out.emit(shooter)


## True when `point` (world) is on the head.
func is_head_point(point: Vector3) -> bool:
	if model == null:
		return false
	var local := model.global_transform.affine_inverse() * point
	return local.y >= model.height * HEAD_FROM


## Back in the game: hits gone, hands down. The paint stays (it lasts until
## respawn: call clear() too for that).
func revive() -> void:
	out = false
	hits = 0
	_since_hit = 0.0
	if model != null:
		model.hands_up = 0.0
	hits_changed.emit(hits)
	revived.emit()


## All paint off (respawn, going home, the harbour, the car wash).
func clear() -> void:
	splats.clear()
	_draw()


func _process(delta: float) -> void:
	# A change of clothes rebuilds the body mesh: put the paint back on it.
	if _material != null and not splats.is_empty() and model != null and model.mesh_instance != null \
			and model.mesh_instance.material_overlay != _material:
		model.mesh_instance.material_overlay = _material
	if hits <= 0 or out:
		return
	_since_hit += delta
	if _since_hit >= WEAR_TIME:
		_since_hit = 0.0
		hits -= 1
		hits_changed.emit(hits)


## A splat on the body at a world point, moved back to the rest pose by
## the nearest bone.
func add_splat(point: Vector3, colour: Color, size := SPLAT_SIZE) -> void:
	if model == null or model.skeleton == null:
		return
	var sk := model.skeleton
	var p := sk.global_transform.affine_inverse() * point
	var best := -1
	var best_d := INF
	var best_on := Vector3.ZERO
	for b in sk.get_bone_count():
		var a := sk.get_bone_global_pose(b).origin
		var e := a
		var kids := sk.get_bone_children(b)
		if kids.size() > 0:
			e = sk.get_bone_global_pose(kids[0]).origin
		if b == BodyBuilder.HEAD:
			e = a + sk.get_bone_global_pose(b).basis.y * 0.12 * model.height / 1.75
		var on := Geometry3D.get_closest_point_to_segment(p, a, e)
		var d := on.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = b
			best_on = on
	if best < 0:
		return
	# The ball hit the collision capsule, which is fatter than the body: put
	# the splat on a body of about the right thickness round that bone.
	var out_dir := p - best_on
	if out_dir.length_squared() < 0.000001:
		out_dir = sk.get_bone_global_pose(best).basis.z
	out_dir = out_dir.normalized()
	var on_body := best_on + out_dir * _thickness(best) * model.height / 1.75
	var to_rest := sk.get_bone_global_rest(best) * sk.get_bone_global_pose(best).affine_inverse()
	splats.append({"point": to_rest * on_body, "normal": (to_rest.basis * out_dir).normalized(), "colour": colour, "size": size,
		"shape": _rng.randi() % PaintTexture.SHAPES, "turn": _rng.randf() * TAU})
	while splats.size() > MAX_SPLATS:
		splats.pop_front()
	_draw()


## m: about how far the body's surface is from each bone (a 1.75 m person).
static func _thickness(bone: int) -> float:
	match bone:
		BodyBuilder.HIPS, BodyBuilder.SPINE, BodyBuilder.CHEST:
			return 0.13
		BodyBuilder.NECK:
			return 0.06
		BodyBuilder.HEAD:
			return 0.1
		BodyBuilder.UPPER_LEG_L, BodyBuilder.UPPER_LEG_R:
			return 0.075
		BodyBuilder.UPPER_ARM_L, BodyBuilder.UPPER_ARM_R:
			return 0.05
	return 0.045


func _draw() -> void:
	if model == null or model.mesh_instance == null:
		return
	var mi := model.mesh_instance
	if splats.is_empty():
		mi.material_overlay = null
		return
	if _material == null:
		_material = PaintCoverage.new_overlay_material(true)
		_material.set_shader_parameter("reach", SPLAT_SIZE)
	var pos := PackedVector4Array()
	var nrm := PackedVector4Array()
	var col := PackedVector4Array()
	pos.resize(PaintCoverage.MAX_HITS)
	nrm.resize(PaintCoverage.MAX_HITS)
	col.resize(PaintCoverage.MAX_HITS)
	for i in splats.size():
		var s := splats[i]
		var p: Vector3 = s["point"]
		var n: Vector3 = s["normal"]
		var c: Color = s["colour"]
		pos[i] = Vector4(p.x, p.y, p.z, float(s["size"]))
		nrm[i] = Vector4(n.x, n.y, n.z, float(s["shape"]))
		col[i] = Vector4(c.r, c.g, c.b, float(s["turn"]))
	_material.set_shader_parameter("hit_pos", pos)
	_material.set_shader_parameter("hit_nrm", nrm)
	_material.set_shader_parameter("hit_col", col)
	_material.set_shader_parameter("hit_count", splats.size())
	mi.material_overlay = _material

class_name BodyPaint
extends Node
## Paint on a person, and the hits that put them out (docs/design.md
## section 2, "Hits and outs", and section 3, "Players"). The player has
## one; officers (the Police piece) will. The person's own script forwards
## `take_paint_hit`, `is_out` and `went_out` to it.
##
## Hits: 8 and you're out; a head hit counts as 2 (PaintShots asks
## `is_head_point`). It's a paint meter, not three strikes: a fight lasts
## long enough to move, answer back and win it, the way the shooters people
## love play (a Halo shield, a Splatoon ink meter). Get out of the line of
## fire for REGEN_DELAY and the meter drains, a hit every REGEN_STEP, so
## breaking off and coming back is a real move. Out: `out` is true, the
## hands go up (HumanoidModel.hands_up) and the owner's marker won't fire.
## What happens next (walk off, respawn, getting caught) isn't decided
## here: `went_out` tells whoever decides, and they call `revive()`.
##
## Armour (docs/design.md section 6½): plates worn take the hits first,
## PLATE_HITS each, before any count toward an out; a hit worth more than
## the plate has left breaks it and the rest goes to the next plate (or
## counts). Plates don't come back on their own. Only hits that would count use
## plates (none outside events). The player's come from Ervin's and are
## kept in GameState.items["armour"] (Armour); officers have none.
##
## Police against the player (`soft_police`, on for the player): it's
## paintball, so a rampage should be fun. A hit from the police counts 1
## even on the head, and the meter starts draining POLICE_REGEN_DELAY after
## one, not REGEN_DELAY. Officers themselves go out sooner (`out_hits`, set
## by Officer).
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
## Plates worn changed (bought, or broken by a hit).
signal armour_changed(plates: int)
## A hit broke `n` plates.
signal plates_broke(n: int)
## Hit by `shooter` (or null), whether it counted or not: for the HUD's
## arrow to where it came from, and the flinch.
signal took_hit(shooter: Node, value: int)

const OUT_HITS := 8 ## design
## Most plates worn at once, and the hits each one takes (not in the
## design: three plates are most of an out's worth).
const ARMOUR_MAX := 3
const PLATE_HITS := 2
## s without a hit before the meter starts draining, then s for each hit
## to go (all 8 gone in under 2 s). Not in the design's old 6 s a hit:
## quick enough that cover is worth taking, slow enough that you can't
## stand in the open and outlast a fight.
const REGEN_DELAY := 2.5
const REGEN_STEP := 0.22
## s: the delay when the last hit was from the police and soft_police is on.
const POLICE_REGEN_DELAY := 2.0
const MAX_SPLATS := 16 ## design
## m: a paintball's splat on clothes (not in the design; smaller than on a
## car, so a few hits read as separate splats on a chest).
const SPLAT_SIZE := 0.085
## m: the overlay is drawn only within this of the camera (an 8 cm splat is
## a pixel or two past it), like a car's (PaintCoverage.OVERLAY_RANGE).
const OVERLAY_RANGE := 60.0
## Where the head starts, as a share of the person's height (the neck joint
## is at 0.85 in BodyBuilder).
const HEAD_FROM := 0.855

## The model to paint (its mesh_instance gets the overlay).
var model: HumanoidModel
## False outside events: paint only, never out (design section 2, "The rule
## outside events"). The Wanted/event code sets it; true until then.
var can_go_out := true
## Hits to go out (OUT_HITS; officers set fewer).
var out_hits := OUT_HITS
## The player's: police hits count 1 and wear off faster (above).
var soft_police := false
var hits := 0
var out := false
## Hits the outer plate has taken (0..PLATE_HITS - 1).
var plate_wear := 0
## Plates worn, 0..ARMOUR_MAX: set with set_armour.
var armour := 0
## The splats: {point, normal (rest space), colour, size, shape, turn,
## born (on PaintSplats.clock, for the drips)}.
var splats: Array[Dictionary] = []

var _since_hit := 0.0
var _police_hit := false
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _range_check := 0.0


func _ready() -> void:
	_rng.randomize()


## A hit: `value` hits (2 for a head shot), from `shooter`, at a point in
## the world, in `colour`. Paints whatever happens; counts toward an out
## unless already out (or outs are off).
func take_hit(value: int, shooter: Node, point: Vector3, colour: Color) -> void:
	add_splat(point, colour)
	if out or not can_go_out or value <= 0:
		took_hit.emit(shooter, 0)
		return
	_police_hit = soft_police and shooter != null and is_instance_valid(shooter) and shooter.is_in_group("police")
	if _police_hit:
		value = 1
	took_hit.emit(shooter, value)
	if armour > 0:
		var broke := 0
		while value > 0 and armour > 0:
			var take := mini(value, PLATE_HITS - plate_wear)
			plate_wear += take
			value -= take
			if plate_wear >= PLATE_HITS:
				plate_wear = 0
				armour -= 1
				broke += 1
		_since_hit = 0.0
		if broke > 0:
			_wear_armour()
			armour_changed.emit(armour)
			plates_broke.emit(broke)
		if value <= 0:
			return
	hits = mini(out_hits, hits + value)
	_since_hit = 0.0
	hits_changed.emit(hits)
	if hits >= out_hits:
		out = true
		if model != null:
			model.hands_up = 1.0
		went_out.emit(shooter)


## Plates worn now (clamped to 0..ARMOUR_MAX).
func set_armour(plates: int) -> void:
	plates = clampi(plates, 0, ARMOUR_MAX)
	if plates == armour:
		return
	if plates > armour:
		plate_wear = 0
	armour = plates
	_wear_armour()
	armour_changed.emit(armour)


## The model shows the plates worn.
func _wear_armour() -> void:
	if model != null:
		model.set_armour_plates(armour)


## True when `point` (world) is on the head.
func is_head_point(point: Vector3) -> bool:
	if model == null:
		return false
	var local := model.global_transform.affine_inverse() * point
	return local.y >= model.height * HEAD_FROM - model.crouch_drop()


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
	# A change of clothes rebuilds the body mesh: put the paint back on it
	# (within its draw range).
	_range_check -= delta
	if _material != null and not splats.is_empty() and model != null and model.mesh_instance != null and _range_check <= 0.0:
		_range_check = 0.25
		_apply_overlay()
	if hits <= 0 or out:
		return
	_since_hit += delta
	var wait := POLICE_REGEN_DELAY if _police_hit else REGEN_DELAY
	if _since_hit >= wait + REGEN_STEP:
		_since_hit = wait
		hits -= 1
		hits_changed.emit(hits)


## 0..1: how close to out (the HUD's meter).
func fraction() -> float:
	return float(hits) / float(maxi(out_hits, 1))


## True while the meter is draining (no hit for long enough).
func is_regenerating() -> bool:
	return hits > 0 and not out and _since_hit >= (POLICE_REGEN_DELAY if _police_hit else REGEN_DELAY)


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
		"shape": _rng.randi() % PaintTexture.SHAPES, "turn": _rng.randf() * TAU, "born": PaintSplats.clock})
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
	var born := PackedFloat32Array()
	born.resize(PaintCoverage.MAX_HITS)
	born.fill(-1000.0)
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
		born[i] = float(s.get("born", -1000.0))
	_material.set_shader_parameter("hit_pos", pos)
	_material.set_shader_parameter("hit_nrm", nrm)
	_material.set_shader_parameter("hit_col", col)
	_material.set_shader_parameter("hit_born", born)
	_material.set_shader_parameter("hit_count", splats.size())
	_apply_overlay()


## The overlay on the body within OVERLAY_RANGE of the camera, off past it.
func _apply_overlay() -> void:
	var mi := model.mesh_instance
	mi.set_meta("paint_range", OVERLAY_RANGE)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var far := cam != null and cam.global_position.distance_squared_to(mi.global_position) > OVERLAY_RANGE * OVERLAY_RANGE
	var want: Material = null if far else _material
	if mi.material_overlay != want:
		mi.material_overlay = want

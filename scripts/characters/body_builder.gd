class_name BodyBuilder
extends RefCounted
## Builds a person as ONE skinned mesh on a small skeleton.
##
## The body is lofted: rings (ellipses) are placed along each body part and
## joined into a smooth skin, so there are no seams or floating pieces, and
## each person costs a single draw call (plus its shadow) however much
## detail the shape has. Clothes, skin, hair and shoe soles are vertex
## colours on one shared material. Each vertex is weighted to one or two
## bones, so joints bend smoothly when HumanoidModel poses the skeleton.
##
## Measurements are for a 1.75 m adult in a relaxed A-pose, facing -Z, feet
## at y = 0; `k` scales the whole person and `build` widens the shoulders.

enum { HIPS, SPINE, CHEST, NECK, HEAD,
	UPPER_LEG_L, LOWER_LEG_L, FOOT_L, UPPER_LEG_R, LOWER_LEG_R, FOOT_R,
	UPPER_ARM_L, LOWER_ARM_L, HAND_L, UPPER_ARM_R, LOWER_ARM_R, HAND_R }

## name, parent, joint position (model space, 1.75 m person)
const BONES := [
	["hips", -1, Vector3(0.0, 0.93, 0.0)],
	["spine", HIPS, Vector3(0.0, 1.05, 0.0)],
	["chest", SPINE, Vector3(0.0, 1.27, 0.0)],
	["neck", CHEST, Vector3(0.0, 1.48, 0.0)],
	["head", NECK, Vector3(0.0, 1.57, 0.0)],
	["upper_leg.L", HIPS, Vector3(-0.095, 0.91, 0.0)],
	["lower_leg.L", UPPER_LEG_L, Vector3(-0.097, 0.49, 0.0)],
	["foot.L", LOWER_LEG_L, Vector3(-0.098, 0.085, 0.0)],
	["upper_leg.R", HIPS, Vector3(0.095, 0.91, 0.0)],
	["lower_leg.R", UPPER_LEG_R, Vector3(0.097, 0.49, 0.0)],
	["foot.R", LOWER_LEG_R, Vector3(0.098, 0.085, 0.0)],
	["upper_arm.L", CHEST, Vector3(-0.19, 1.43, 0.0)],
	["lower_arm.L", UPPER_ARM_L, Vector3(-0.215, 1.155, 0.0)],
	["hand.L", LOWER_ARM_L, Vector3(-0.228, 0.915, 0.0)],
	["upper_arm.R", CHEST, Vector3(0.19, 1.43, 0.0)],
	["lower_arm.R", UPPER_ARM_R, Vector3(0.215, 1.155, 0.0)],
	["hand.R", LOWER_ARM_R, Vector3(0.228, 0.915, 0.0)],
]

const SEGS := 18 # points around each ring of the body
const LIMB_SEGS := 12

static var _material: ShaderMaterial

var k := 1.0
var build := 1.0
var look: Dictionary

var _st := SurfaceTool.new()
var _verts := PackedVector3Array() # positions, to check winding
var _count := 0


func _init(appearance: Dictionary, height: float, shoulder_build: float) -> void:
	look = appearance
	k = height / 1.75
	build = shoulder_build


## The one material every person shares: vertex colours with a cloth weave
## and soft rim light (shaders/person.gdshader).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/person.gdshader")
	return _material


## Joint position for this person (scaled; arms move out with the build).
func joint(i: int) -> Vector3:
	var p: Vector3 = BONES[i][2]
	var arm := i >= UPPER_ARM_L
	return Vector3(p.x * k * (build if arm else 1.0), p.y * k, p.z * k)


func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for i in BONES.size():
		sk.add_bone(BONES[i][0])
	for i in BONES.size():
		var parent: int = BONES[i][1]
		if parent >= 0:
			sk.set_bone_parent(i, parent)
		var parent_pos := joint(parent) if parent >= 0 else Vector3.ZERO
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, joint(i) - parent_pos))
	sk.reset_bone_poses()
	return sk


func make_mesh() -> ArrayMesh:
	_st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_torso()
	for side: float in [-1.0, 1.0]:
		_leg(side)
		_arm(side)
	_head()
	_st.generate_normals()
	var mesh := _st.commit()
	mesh.surface_set_material(0, material())
	return mesh


# --- the body, part by part -------------------------------------------------------------

func _c(key: String, fallback: Color) -> Color:
	return look.get(key, fallback)


func _torso() -> void:
	var jacket := _c("top", Color(0.66, 0.16, 0.13))
	var hem := jacket.darkened(0.18)
	var shirt := _c("under", Color(0.82, 0.8, 0.74))
	var pants := _c("bottom", Color(0.21, 0.25, 0.34))
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var b := build
	# Shoulders slope from the neck down to the arms (no square shelf), the
	# chest is deeper than the waist and the back is flatter than the front.
	# y, half width, half depth, z offset (+ is the back), bone a, bone b, weight on b, colour
	var rows := [
		[0.8, 0.1, 0.08, 0.0, HIPS, HIPS, 0.0, pants], # crotch, inside the legs
		[0.86, 0.165, 0.11, 0.008, HIPS, HIPS, 0.0, pants],
		[0.905, 0.178, 0.114, 0.008, HIPS, HIPS, 0.0, pants],
		[0.915, 0.184, 0.12, 0.008, HIPS, HIPS, 0.0, hem], # jacket hem, a fold over the trousers
		[0.94, 0.18, 0.118, 0.006, HIPS, SPINE, 0.2, hem],
		[0.955, 0.176, 0.116, 0.006, HIPS, SPINE, 0.25, jacket],
		[1.03, 0.158 * lerpf(1.0, b, 0.2), 0.106, 0.004, HIPS, SPINE, 0.6, jacket],
		[1.11, 0.152 * lerpf(1.0, b, 0.3), 0.106, 0.0, SPINE, SPINE, 0.0, jacket],
		[1.2, 0.16 * lerpf(1.0, b, 0.6), 0.114, -0.006, SPINE, CHEST, 0.5, jacket],
		[1.29, 0.172 * b, 0.124, -0.01, CHEST, CHEST, 0.0, jacket],
		[1.36, 0.176 * b, 0.122, -0.008, CHEST, CHEST, 0.0, jacket],
		[1.415, 0.172 * b, 0.112, -0.002, CHEST, CHEST, 0.0, jacket],
		[1.45, 0.162 * b, 0.1, 0.004, CHEST, CHEST, 0.0, jacket],
		[1.47, 0.13 * b, 0.088, 0.008, CHEST, CHEST, 0.0, jacket],
		[1.48, 0.1 * b, 0.078, 0.01, CHEST, CHEST, 0.0, jacket],
		[1.485, 0.08, 0.072, 0.01, CHEST, NECK, 0.3, jacket], # collar
		[1.488, 0.072, 0.066, 0.01, CHEST, NECK, 0.3, shirt],
		[1.5, 0.064, 0.062, 0.012, CHEST, NECK, 0.6, shirt],
		[1.5, 0.062, 0.06, 0.012, NECK, NECK, 0.0, skin],
		[1.55, 0.058, 0.058, 0.016, NECK, HEAD, 0.5, skin],
	]
	var rings := []
	for r: Array in rows:
		var ring := _ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
			float(r[1]) * k, float(r[2]) * k, r[4], r[5], r[6], r[7])
		ring["sq"] = 2.6 if float(r[0]) > 0.9 and float(r[0]) < 1.45 else 2.0 # torso: rounded box, not a tube
		rings.append(ring)
	_loft(rings, SEGS, true, false)


func _leg(side: float) -> void:
	var pants := _c("bottom", Color(0.21, 0.25, 0.34))
	var shoes := _c("shoes", Color(0.16, 0.12, 0.1))
	var sole := Color(0.86, 0.84, 0.8)
	var up := UPPER_LEG_L if side < 0.0 else UPPER_LEG_R
	var low := up + 1
	var foot := up + 2
	var x := 0.095 * side
	# Seat and thigh, a narrower knee, a little calf under the trousers,
	# then the trousers falling straight to the shoe.
	# y, radius x, radius z, z offset, bone a, bone b, weight, colour
	var rows := [
		[0.93, 0.07, 0.08, 0.008, HIPS, up, 0.5, pants],
		[0.85, 0.084, 0.092, 0.012, up, up, 0.0, pants], # seat
		[0.76, 0.08, 0.084, 0.0, up, up, 0.0, pants],
		[0.64, 0.07, 0.072, -0.006, up, up, 0.0, pants],
		[0.53, 0.059, 0.062, -0.006, up, low, 0.3, pants],
		[0.49, 0.057, 0.06, -0.004, up, low, 0.5, pants], # knee
		[0.43, 0.058, 0.064, 0.004, low, low, 0.0, pants],
		[0.34, 0.056, 0.061, 0.008, low, low, 0.0, pants],
		[0.22, 0.052, 0.055, 0.004, low, low, 0.0, pants],
		[0.14, 0.053, 0.056, 0.004, low, foot, 0.25, pants],
		[0.115, 0.054, 0.058, 0.006, low, foot, 0.35, pants.darkened(0.2)], # hem
		[0.115, 0.046, 0.05, 0.006, low, foot, 0.35, shoes],
		[0.1, 0.048, 0.056, 0.004, low, foot, 0.6, shoes],
	]
	var rings := []
	for r: Array in rows:
		rings.append(_ring(Vector3(x * (1.0 - 0.02 * (1.0 - float(r[0]))), r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
			float(r[1]) * k, float(r[2]) * k, r[4], r[5], r[6], r[7]))
	_loft(rings, LIMB_SEGS, false, true)
	# Shoe: rings from heel to toe; the bottom is painted as a pale sole.
	var fx := 0.098 * side
	var shoe_rows := [
		# z, center y, half width, half height
		[0.07, 0.045, 0.036, 0.036],
		[0.045, 0.052, 0.048, 0.05],
		[-0.02, 0.052, 0.05, 0.05],
		[-0.1, 0.042, 0.052, 0.04],
		[-0.16, 0.034, 0.047, 0.032],
		[-0.19, 0.028, 0.034, 0.024],
	]
	var shoe := []
	for r: Array in shoe_rows:
		var ring := _ring(Vector3(fx, r[1], r[0]) * k, Vector3.RIGHT, Vector3.UP,
			float(r[2]) * k, float(r[3]) * k, foot, foot, 0.0, shoes)
		ring["sq"] = 2.6
		shoe.append(ring)
	_loft(shoe, LIMB_SEGS, true, true, func(p: Vector3, c: Color) -> Color: return sole if p.y < 0.016 * k else c)


func _arm(side: float) -> void:
	var jacket := _c("top", Color(0.66, 0.16, 0.13))
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var up := UPPER_ARM_L if side < 0.0 else UPPER_ARM_R
	var low := up + 1
	var hand := up + 2
	var shoulder := joint(up)
	var elbow := joint(low)
	var wrist := joint(hand)
	# The round of the shoulder: the sleeve curves in over the top of the arm
	# toward the neck, starting inside the torso, so the arm grows out of the
	# body instead of being a tube stuck on with a flat end.
	# offset (in, up), axis angle from straight down, radius across, radius front-back
	var rounds := [
		[0.055, 0.004, 1.45, 0.026, 0.044],
		[0.03, 0.006, 1.05, 0.04, 0.054],
		[0.008, -0.006, 0.55, 0.052, 0.06],
	]
	var arm_axis := (elbow - shoulder).normalized()
	var rings := []
	for r: Array in rounds:
		var p := shoulder + Vector3(-side * float(r[0]), float(r[1]), 0.0) * k
		var ang: float = r[2]
		var axis := Vector3(side * sin(ang), -cos(ang), 0.0).lerp(arm_axis, 1.0 - clampf(ang / 0.6, 0.0, 1.0)).normalized()
		var u := Vector3.BACK.cross(axis).normalized()
		var v := axis.cross(u).normalized()
		rings.append(_ring(p, u, v, float(r[3]) * k, float(r[4]) * k, CHEST, up, 0.35, jacket))
	# Then along the arm (0 shoulder .. 1 elbow .. 2 wrist).
	# t, radius across (x), radius front-back (z), bone a, bone b, weight, colour
	var rows := [
		[0.06, 0.057, 0.062, CHEST, up, 0.6, jacket], # deltoid
		[0.22, 0.056, 0.058, up, up, 0.0, jacket],
		[0.5, 0.053, 0.056, up, up, 0.0, jacket], # biceps
		[0.85, 0.049, 0.052, up, low, 0.25, jacket],
		[1.0, 0.047, 0.05, up, low, 0.5, jacket], # elbow
		[1.2, 0.05, 0.052, low, low, 0.0, jacket], # forearm
		[1.6, 0.043, 0.043, low, low, 0.0, jacket],
		[1.82, 0.045, 0.046, low, hand, 0.1, jacket.darkened(0.15)], # cuff
		[1.84, 0.044, 0.045, low, hand, 0.1, jacket.darkened(0.2)],
		[1.84, 0.024, 0.031, low, hand, 0.1, skin],
		[1.96, 0.023, 0.03, low, hand, 0.5, skin], # wrist
	]
	for r: Array in rows:
		var t: float = r[0]
		var p: Vector3
		var axis: Vector3
		if t <= 1.0:
			p = shoulder.lerp(elbow, t)
			axis = arm_axis
		else:
			p = elbow.lerp(wrist, t - 1.0)
			axis = (wrist - elbow).normalized()
		var u := Vector3.BACK.cross(axis).normalized()
		var v := axis.cross(u).normalized()
		rings.append(_ring(p, u, v, float(r[1]) * k, float(r[2]) * k, r[3], r[4], r[5], r[6]))
	_loft(rings, LIMB_SEGS, true, false)
	_hand(side, wrist, (wrist - elbow).normalized(), hand, skin)


## A relaxed hand: palm toward the thigh, fingers together and a little
## curled, the thumb in front.
func _hand(side: float, wrist: Vector3, axis: Vector3, bone: int, skin: Color) -> void:
	var inward := Vector3(-side, 0.0, 0.0)
	# along the hand, thickness (across, x), width (front-back, z), curl in, z shift
	var rows := [
		[-0.025, 0.022, 0.029, 0.0, 0.0],
		[0.02, 0.024, 0.036, 0.0, -0.002],
		[0.06, 0.023, 0.043, 0.002, -0.004], # palm
		[0.095, 0.021, 0.044, 0.006, -0.004], # knuckles
		[0.13, 0.017, 0.04, 0.014, -0.002],
		[0.165, 0.014, 0.034, 0.026, 0.0],
		[0.185, 0.01, 0.024, 0.036, 0.002], # finger tips
	]
	var rings := []
	for r: Array in rows:
		var p := wrist + axis * float(r[0]) * k + inward * float(r[3]) * k + Vector3(0.0, 0.0, float(r[4])) * k
		var u := Vector3.BACK.cross(axis).normalized()
		var v := axis.cross(u).normalized()
		rings.append(_ring(p, u, v, float(r[1]) * k, float(r[2]) * k, bone, bone, 0.0, skin))
	_loft(rings, LIMB_SEGS, true, true)
	# Thumb: from the heel of the hand, down and forward along the front.
	var base := wrist + axis * 0.03 * k + Vector3(0.0, 0.0, -0.03) * k + inward * 0.008 * k
	var tip := base + (axis * 0.07 + Vector3(0.0, 0.0, -0.012) + inward * 0.012) * k
	var tax := (tip - base).normalized()
	var tu := Vector3.BACK.cross(tax).normalized()
	var tv := tax.cross(tu).normalized()
	var thumb := []
	for r: Array in [[0.0, 0.014], [0.4, 0.013], [0.8, 0.011], [1.0, 0.008]]:
		thumb.append(_ring(base.lerp(tip, float(r[0])), tu, tv, float(r[1]) * k, float(r[1]) * k, bone, bone, 0.0, skin))
	_loft(thumb, 8, true, true)


func _head() -> void:
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var hair := _c("hair", Color(0.23, 0.16, 0.11))
	var hat: Color = look.get("hat", Color(0, 0, 0, 0))
	var style: int = look.get("hair_style", 0)
	# A head a touch larger than life, as most games draw them, with a jaw,
	# a chin and a skull rounder at the back than the front.
	# y, half width, half depth, z offset (interpolated to more rings below)
	var rows := [
		[1.535, 0.05, 0.05, 0.02],
		[1.55, 0.062, 0.07, 0.0], # under the jaw
		[1.568, 0.07, 0.086, -0.012], # chin and jaw
		[1.595, 0.08, 0.096, -0.012], # jaw line
		[1.63, 0.087, 0.101, -0.008], # cheeks
		[1.665, 0.091, 0.104, -0.002],
		[1.7, 0.093, 0.106, 0.002],
		[1.735, 0.088, 0.101, 0.006],
		[1.765, 0.07, 0.084, 0.01],
		[1.783, 0.04, 0.05, 0.012],
	]
	var rings := []
	for i in rows.size():
		var r: Array = rows[i]
		rings.append(_ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
			float(r[1]) * k, float(r[2]) * k, HEAD, HEAD, 0.0, skin))
		if i >= 2 and i < rows.size() - 1:
			# A ring halfway to the next, so the hairline and skull are smooth.
			var n: Array = rows[i + 1]
			var m := 0.5
			rings.append(_ring(Vector3(0.0, lerpf(r[0], n[0], m), lerpf(r[3], n[3], m)) * k, Vector3.RIGHT, Vector3.BACK,
				lerpf(r[1], n[1], m) * 1.012 * k, lerpf(r[2], n[2], m) * 1.012 * k, HEAD, HEAD, 0.0, skin))
	var kk := k
	var hairline := func(p: Vector3) -> float:
		# Up at the forehead, down at the temples and over the ears, low at the nape.
		var around := atan2(absf(p.x), -p.z) # 0 at the face, PI at the back
		var line := 1.712
		if around > 0.55:
			line = lerpf(1.712, 1.672, smoothstep(0.55, 1.15, around))
		if around > 1.15:
			line = lerpf(1.672, 1.6, smoothstep(1.15, 2.3, around))
		if style == 2:
			line += 0.012
		return line
	var paint := func(p: Vector3, c: Color) -> Color:
		var y := p.y / kk
		var z := p.z / kk
		if hat.a > 0.0 and y > 1.7 - maxf(0.0, z) * 0.3:
			return Color(hat.r, hat.g, hat.b)
		return hair if y > hairline.call(p) else c
	# Hair (and a knit hat) stand off the skull a little, so they have some
	# volume instead of looking painted on; the short style is fuller on top.
	var centre := Vector3(0.0, 1.66, 0.004) * k
	var shape := func(p: Vector3) -> Vector3:
		var y := p.y / kk
		var z := p.z / kk
		var covered := hat.a > 0.0 and y > 1.7 - maxf(0.0, z) * 0.3
		var line: float = hairline.call(p)
		if not covered and y <= line:
			return p
		var depth := 0.012 if covered else (0.004 if style == 2 else 0.009)
		if not covered and style == 0:
			depth += 0.006 * smoothstep(1.7, 1.77, y) # fuller on top
		depth *= smoothstep(0.0, 0.012, y - line) if not covered else 1.0
		return p + (p - centre).normalized() * depth * kk
	_loft(rings, 24, false, true, paint, shape)
	# Face details: nose, eyes, brows, mouth, ears.
	_blob(Vector3(0.0, 1.652, -0.101), Vector3(0.011, 0.02, 0.016), HEAD, skin.darkened(0.04))
	_blob(Vector3(0.0, 1.592, -0.087), Vector3(0.02, 0.012, 0.01), HEAD, skin) # chin
	_blob(Vector3(0.0, 1.615, -0.094), Vector3(0.016, 0.0035, 0.005), HEAD, skin.darkened(0.3)) # mouth
	for s: float in [-1.0, 1.0]:
		_blob(Vector3(0.032 * s, 1.67, -0.093), Vector3(0.012, 0.0085, 0.006), HEAD, Color(0.92, 0.9, 0.87)) # eye white
		_blob(Vector3(0.032 * s, 1.67, -0.097), Vector3(0.0065, 0.0075, 0.004), HEAD, Color(0.12, 0.09, 0.07)) # iris
		_blob(Vector3(0.034 * s, 1.688, -0.095), Vector3(0.018, 0.0045, 0.007), HEAD, hair.darkened(0.25)) # brow
		_blob(Vector3(0.092 * s, 1.655, 0.006), Vector3(0.012, 0.027, 0.018), HEAD, skin.darkened(0.06)) # ear
	if style == 1 and hat.a <= 0.0:
		# Long hair falling to the collar at the back.
		var back := []
		for r: Array in [[1.73, 0.092, 0.08, 0.03], [1.64, 0.1, 0.084, 0.04], [1.56, 0.094, 0.07, 0.05], [1.5, 0.078, 0.05, 0.055]]:
			back.append(_ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
				float(r[1]) * k, float(r[2]) * k, HEAD, HEAD, 0.0, hair))
		_loft(back, SEGS, true, true)
	if hat.a > 0.0:
		_blob(Vector3(0.0, 1.805, 0.012), Vector3(0.028, 0.026, 0.028), HEAD, Color(hat.r, hat.g, hat.b).lightened(0.15))


## A small ellipsoid (nose, eyes, ears, pompom) on one bone.
func _blob(center: Vector3, radii: Vector3, bone: int, c: Color) -> void:
	var rings := []
	for i in 5:
		var a := -PI * 0.5 + PI * float(i + 1) / 6.0
		var y := sin(a) * radii.y
		var s := cos(a)
		rings.append(_ring((center + Vector3(0.0, y, 0.0)) * k, Vector3.RIGHT, Vector3.BACK,
			radii.x * s * k, radii.z * s * k, bone, bone, 0.0, c))
	_loft(rings, 8, true, true)


# --- lofting -----------------------------------------------------------------------------

func _ring(c: Vector3, u: Vector3, v: Vector3, ru: float, rv: float, b0: int, b1: int, w: float, col: Color) -> Dictionary:
	return {"c": c, "u": u, "v": v, "ru": ru, "rv": rv, "b0": b0, "b1": b1, "w": w, "col": col}


## Joins rings into a closed skin, optionally capping the first and last ring.
## `paint` recolours a point, `shape` moves it (both see the point before moving).
func _loft(rings: Array, segs: int, cap_start: bool, cap_end: bool, paint: Callable = Callable(), shape: Callable = Callable()) -> void:
	var first := _count
	for r: Dictionary in rings:
		var e: float = 2.0 / float(r.get("sq", 2.0)) # 1 = ellipse, smaller = squarer
		for s in segs:
			var t := TAU * float(s) / float(segs)
			var cu := cos(t)
			var sv := sin(t)
			if e != 1.0:
				cu = signf(cu) * pow(absf(cu), e)
				sv = signf(sv) * pow(absf(sv), e)
			var p: Vector3 = r["c"] + (r["u"] as Vector3) * cu * float(r["ru"]) + (r["v"] as Vector3) * sv * float(r["rv"])
			var col: Color = r["col"]
			if paint.is_valid():
				col = paint.call(p, col)
			if shape.is_valid():
				p = shape.call(p)
			_add_vertex(p, col, r["b0"], r["b1"], r["w"])
	for i in range(rings.size() - 1):
		var ca: Vector3 = rings[i]["c"]
		var cb: Vector3 = rings[i + 1]["c"]
		for s in segs:
			var a0 := first + i * segs + s
			var a1 := first + i * segs + (s + 1) % segs
			var b0 := a0 + segs
			var b1 := a1 + segs
			var mid := (ca + cb) * 0.5
			_tri(a0, b0, a1, _verts[a0] - mid)
			_tri(a1, b0, b1, _verts[a1] - mid)
	if cap_start:
		_cap(rings[0], rings[1], first, segs)
	if cap_end:
		var n := rings.size()
		_cap(rings[n - 1], rings[n - 2], first + (n - 1) * segs, segs)


func _cap(r: Dictionary, inner: Dictionary, start: int, segs: int) -> void:
	var c: Vector3 = r["c"]
	var out := (c - (inner["c"] as Vector3)).normalized()
	var tip := c + out * minf(float(r["ru"]), float(r["rv"])) * 0.4
	var centre := _count
	_add_vertex(tip, _vertex_color_at(start), r["b0"], r["b1"], r["w"])
	for s in segs:
		_tri(start + s, start + (s + 1) % segs, centre, out)


var _colors := PackedColorArray()


func _vertex_color_at(i: int) -> Color:
	return _colors[i]


func _add_vertex(p: Vector3, col: Color, b0: int, b1: int, w: float) -> void:
	_st.set_color(col)
	# Rest position, so the cloth pattern in the shader sticks to the body.
	_st.set_uv(Vector2(p.x, p.y))
	_st.set_uv2(Vector2(p.z, 0.0))
	if b0 == b1 or w <= 0.0:
		_st.set_bones(PackedInt32Array([b0, 0, 0, 0]))
		_st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	else:
		_st.set_bones(PackedInt32Array([b0, b1, 0, 0]))
		_st.set_weights(PackedFloat32Array([1.0 - w, w, 0.0, 0.0]))
	_st.add_vertex(p)
	_verts.append(p)
	_colors.append(col)
	_count += 1


## Adds a triangle facing `outward` (Godot's front faces are clockwise).
func _tri(i0: int, i1: int, i2: int, outward: Vector3) -> void:
	var n := (_verts[i1] - _verts[i0]).cross(_verts[i2] - _verts[i0])
	if n.dot(outward) > 0.0:
		var t := i1
		i1 = i2
		i2 = t
	_st.add_index(i0)
	_st.add_index(i1)
	_st.add_index(i2)

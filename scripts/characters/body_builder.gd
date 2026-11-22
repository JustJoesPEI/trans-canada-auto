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
	["lower_arm.L", UPPER_ARM_L, Vector3(-0.225, 1.155, 0.0)],
	["hand.L", LOWER_ARM_L, Vector3(-0.245, 0.915, 0.0)],
	["upper_arm.R", CHEST, Vector3(0.19, 1.43, 0.0)],
	["lower_arm.R", UPPER_ARM_R, Vector3(0.225, 1.155, 0.0)],
	["hand.R", LOWER_ARM_R, Vector3(0.245, 0.915, 0.0)],
]

const SEGS := 12 # points around each ring of the body
const LIMB_SEGS := 10

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
	var hem := jacket.darkened(0.25)
	var shirt := _c("under", Color(0.82, 0.8, 0.74))
	var pants := _c("bottom", Color(0.21, 0.25, 0.34))
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var b := build
	# y, half width, half depth, z offset, bone a, bone b, weight on b, colour
	var rows := [
		[0.83, 0.12, 0.09, 0.0, HIPS, HIPS, 0.0, pants],
		[0.88, 0.155, 0.105, 0.005, HIPS, HIPS, 0.0, pants],
		[0.9, 0.165, 0.11, 0.005, HIPS, HIPS, 0.0, pants],
		[0.9, 0.172, 0.118, 0.005, HIPS, HIPS, 0.0, hem], # jacket hem
		[0.93, 0.168, 0.114, 0.005, HIPS, SPINE, 0.2, hem],
		[0.935, 0.166, 0.112, 0.005, HIPS, SPINE, 0.25, jacket],
		[1.02, 0.152, 0.104, 0.0, HIPS, SPINE, 0.6, jacket],
		[1.1, 0.148 * lerpf(1.0, b, 0.3), 0.104, -0.003, SPINE, SPINE, 0.0, jacket],
		[1.2, 0.162 * lerpf(1.0, b, 0.6), 0.115, -0.006, SPINE, CHEST, 0.5, jacket],
		[1.3, 0.176 * b, 0.122, -0.006, CHEST, CHEST, 0.0, jacket],
		[1.38, 0.184 * b, 0.116, -0.002, CHEST, CHEST, 0.0, jacket],
		[1.425, 0.186 * b, 0.105, 0.003, CHEST, CHEST, 0.0, jacket],
		[1.452, 0.165 * b, 0.092, 0.005, CHEST, CHEST, 0.0, jacket],
		[1.466, 0.115 * b, 0.08, 0.006, CHEST, CHEST, 0.0, jacket],
		[1.472, 0.075, 0.068, 0.006, CHEST, NECK, 0.3, jacket], # collar
		[1.472, 0.068, 0.062, 0.006, CHEST, NECK, 0.3, shirt],
		[1.49, 0.058, 0.056, 0.008, CHEST, NECK, 0.6, shirt],
		[1.49, 0.06, 0.058, 0.008, NECK, NECK, 0.0, skin],
		[1.56, 0.058, 0.056, 0.012, NECK, HEAD, 0.5, skin],
	]
	var rings := []
	for r: Array in rows:
		rings.append(_ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
			float(r[1]) * k, float(r[2]) * k, r[4], r[5], r[6], r[7]))
	_loft(rings, SEGS, true, false)


func _leg(side: float) -> void:
	var pants := _c("bottom", Color(0.21, 0.25, 0.34))
	var shoes := _c("shoes", Color(0.16, 0.12, 0.1))
	var sole := Color(0.86, 0.84, 0.8)
	var up := UPPER_LEG_L if side < 0.0 else UPPER_LEG_R
	var low := up + 1
	var foot := up + 2
	var x := 0.095 * side
	# y, radius x, radius z, z offset, bone a, bone b, weight, colour
	var rows := [
		[0.95, 0.075, 0.085, 0.0, HIPS, up, 0.5, pants],
		[0.86, 0.088, 0.09, 0.0, up, up, 0.0, pants],
		[0.72, 0.08, 0.084, -0.005, up, up, 0.0, pants],
		[0.58, 0.068, 0.07, -0.004, up, up, 0.0, pants],
		[0.49, 0.06, 0.062, -0.006, up, low, 0.5, pants],
		[0.4, 0.06, 0.064, 0.004, low, low, 0.0, pants],
		[0.28, 0.054, 0.056, 0.006, low, low, 0.0, pants],
		[0.15, 0.05, 0.05, 0.004, low, foot, 0.2, pants],
		[0.12, 0.052, 0.052, 0.004, low, foot, 0.35, pants.darkened(0.2)],
		[0.12, 0.046, 0.05, 0.004, low, foot, 0.35, shoes],
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
		[0.065, 0.05, 0.04, 0.042],
		[0.03, 0.055, 0.05, 0.055],
		[-0.04, 0.05, 0.054, 0.048],
		[-0.12, 0.04, 0.052, 0.038],
		[-0.18, 0.032, 0.042, 0.03],
	]
	var shoe := []
	for r: Array in shoe_rows:
		shoe.append(_ring(Vector3(fx, r[1], r[0]) * k, Vector3.RIGHT, Vector3.UP,
			float(r[2]) * k, float(r[3]) * k, foot, foot, 0.0, shoes))
	_loft(shoe, LIMB_SEGS, true, true, func(p: Vector3, c: Color) -> Color: return sole if p.y < 0.018 * k else c)


func _arm(side: float) -> void:
	var jacket := _c("top", Color(0.66, 0.16, 0.13))
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var up := UPPER_ARM_L if side < 0.0 else UPPER_ARM_R
	var low := up + 1
	var hand := up + 2
	var shoulder := joint(up)
	var elbow := joint(low)
	var wrist := joint(hand)
	# position along the arm (0 shoulder .. 1 elbow .. 2 wrist .. 3 fingertips)
	var rows := [
		[0.07, 0.056, 0.06, CHEST, up, 0.4, jacket],
		[0.16, 0.062, 0.063, up, up, 0.0, jacket],
		[0.55, 0.056, 0.056, up, up, 0.0, jacket],
		[1.0, 0.05, 0.052, up, low, 0.5, jacket],
		[1.45, 0.047, 0.048, low, low, 0.0, jacket],
		[1.86, 0.044, 0.045, low, hand, 0.15, jacket.darkened(0.2)], # cuff
		[1.86, 0.034, 0.036, low, hand, 0.15, skin],
		[1.98, 0.03, 0.034, low, hand, 0.5, skin],
		[2.2, 0.025, 0.046, hand, hand, 0.0, skin], # palm, flat side to the leg
		[2.45, 0.022, 0.04, hand, hand, 0.0, skin],
		[2.6, 0.014, 0.024, hand, hand, 0.0, skin],
	]
	var fingertip := wrist + (wrist - elbow).normalized() * 0.17 * k
	var rings := []
	for r: Array in rows:
		var t: float = r[0]
		var p: Vector3
		var axis: Vector3
		if t <= 1.0:
			p = shoulder.lerp(elbow, t)
			axis = (elbow - shoulder).normalized()
		elif t <= 2.0:
			p = elbow.lerp(wrist, t - 1.0)
			axis = (wrist - elbow).normalized()
		else:
			p = wrist.lerp(fingertip, (t - 2.0) / 0.6)
			axis = (fingertip - wrist).normalized()
		var u := Vector3.BACK.cross(axis).normalized()
		var v := axis.cross(u).normalized()
		rings.append(_ring(p, u, v, float(r[1]) * k, float(r[2]) * k, r[3], r[4], r[5], r[6]))
	_loft(rings, LIMB_SEGS, true, true)


func _head() -> void:
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var hair := _c("hair", Color(0.23, 0.16, 0.11))
	var hat: Color = look.get("hat", Color(0, 0, 0, 0))
	var style: int = look.get("hair_style", 0)
	# y, half width, half depth, z offset (interpolated to more rings below)
	var rows := [
		[1.55, 0.054, 0.054, 0.012],
		[1.568, 0.068, 0.076, -0.008], # under the jaw
		[1.592, 0.079, 0.09, -0.01], # jaw line
		[1.625, 0.085, 0.098, -0.008],
		[1.66, 0.09, 0.103, -0.002],
		[1.695, 0.091, 0.104, 0.0],
		[1.73, 0.084, 0.097, 0.003],
		[1.758, 0.066, 0.08, 0.006],
		[1.775, 0.036, 0.046, 0.008],
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
	var paint := func(p: Vector3, c: Color) -> Color:
		var y := p.y / kk
		var z := p.z / kk
		if hat.a > 0.0 and y > 1.7 - maxf(0.0, z) * 0.3:
			return Color(hat.r, hat.g, hat.b)
		# Hairline by angle around the head: up at the forehead, down at the
		# temples and over the ears, low at the nape.
		var around := atan2(absf(p.x), -p.z) # 0 at the face, PI at the back
		var line := 1.712
		if around > 0.55:
			line = lerpf(1.712, 1.672, smoothstep(0.55, 1.15, around))
		if around > 1.15:
			line = lerpf(1.672, 1.6, smoothstep(1.15, 2.3, around))
		if style == 2:
			line += 0.015
		return hair if y > line else c
	_loft(rings, 20, false, true, paint)
	# Face details: nose, eyes, ears.
	_blob(Vector3(0.0, 1.648, -0.099), Vector3(0.012, 0.02, 0.015), HEAD, skin.darkened(0.05))
	for side: float in [-1.0, 1.0]:
		_blob(Vector3(0.033 * side, 1.669, -0.089), Vector3(0.013, 0.011, 0.008), HEAD, Color(0.1, 0.08, 0.07)) # eye
		_blob(Vector3(0.034 * side, 1.689, -0.092), Vector3(0.017, 0.004, 0.006), HEAD, hair.darkened(0.2)) # brow
		_blob(Vector3(0.09 * side, 1.655, 0.002), Vector3(0.012, 0.026, 0.018), HEAD, skin.darkened(0.06))
	if style == 1 and hat.a <= 0.0:
		# Long hair falling to the collar at the back.
		var back := []
		for r: Array in [[1.73, 0.086, 0.07, 0.03], [1.64, 0.094, 0.075, 0.04], [1.55, 0.09, 0.06, 0.05], [1.48, 0.075, 0.045, 0.055]]:
			back.append(_ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
				float(r[1]) * k, float(r[2]) * k, HEAD, HEAD, 0.0, hair))
		_loft(back, SEGS, true, true)
	if hat.a > 0.0:
		_blob(Vector3(0.0, 1.79, 0.01), Vector3(0.028, 0.026, 0.028), HEAD, Color(hat.r, hat.g, hat.b).lightened(0.15))


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
func _loft(rings: Array, segs: int, cap_start: bool, cap_end: bool, paint: Callable = Callable()) -> void:
	var first := _count
	for r: Dictionary in rings:
		for s in segs:
			var t := TAU * float(s) / float(segs)
			var p: Vector3 = r["c"] + (r["u"] as Vector3) * cos(t) * float(r["ru"]) + (r["v"] as Vector3) * sin(t) * float(r["rv"])
			var col: Color = r["col"]
			if paint.is_valid():
				col = paint.call(p, col)
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

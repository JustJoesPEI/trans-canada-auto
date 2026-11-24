class_name BodyBuilder
extends RefCounted
## Builds a person as ONE skinned mesh on a small skeleton.
##
## The body is lofted: rings (ellipses) are placed along each body part and
## joined into a smooth skin, so there are no seams or floating pieces, and
## each person costs a single draw call (plus its shadow) however much
## detail the shape has. Clothes (see Outfit) are built into the same
## mesh, over the bare body; clothes, skin, hair and shoe soles are vertex
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
var outfit: Dictionary ## see Outfit

var _st := SurfaceTool.new()
var _verts := PackedVector3Array() # positions, to check winding
var _count := 0


func _init(appearance: Dictionary, height: float, shoulder_build: float) -> void:
	look = appearance
	var given: Dictionary = appearance.get("outfit", {})
	outfit = Outfit.complete(given) if not given.is_empty() else Outfit.from_colours(appearance)
	k = height / 1.75
	build = shoulder_build


## The one material every person shares: vertex colours with a cloth weave,
## fabric patterns, prints and soft rim light (shaders/person.gdshader).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/person.gdshader")
		_material.set_shader_parameter("prints", load("res://textures/clothing/prints.png"))
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
	_st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT) # print position and tile
	_st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT) # fabric pattern and its second colour
	_torso()
	for side: float in [-1.0, 1.0]:
		_leg(side)
		_shoe(side)
		_arm(side)
	_head()
	_st.generate_normals()
	var mesh := _st.commit()
	mesh.surface_set_material(0, material())
	return mesh


# --- clothes -----------------------------------------------------------------------------
#
# Each body part is a bare body (skin) described by rows along it, and the
# clothes are layers over stretches of it: from, to (along the part), colour,
# how much they add to the radius, and a smallest radius (so trousers fall
# straight past the calf instead of hugging it). Where a layer starts or
# stops the skin steps out or in, which makes the hems, cuffs and collars.

func _c(key: String, fallback: Color) -> Color:
	return look.get(key, fallback)


## The garment in a slot: {"kind", "color", "trim"}.
func _g(slot: String) -> Dictionary:
	return outfit[slot]


## A bare body row: position along the part, centre, ring axes, radii
## (unscaled metres), bones.
func _row(t: float, c: Vector3, u: Vector3, v: Vector3, ru: float, rv: float, b0: int, b1: int, w: float) -> Dictionary:
	return {"t": t, "c": c, "u": u, "v": v, "ru": ru, "rv": rv, "b0": b0, "b1": b1, "w": w}


func _layer(from: float, to: float, col: Color, add: float, min_r := 0.0) -> Dictionary:
	return {"from": minf(from, to), "to": maxf(from, to), "col": col, "add": add, "min": min_r}


## The layer showing at t (the first in the list that covers it), or {} for skin.
func _cover(layers: Array, t: float) -> Dictionary:
	for l: Dictionary in layers:
		if t >= float(l["from"]) and t <= float(l["to"]):
			return l
	return {}


## The bare body at t, between rows.
func _at(rows: Array, t: float) -> Dictionary:
	for i in range(rows.size() - 1):
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		var ta: float = a["t"]
		var tb: float = b["t"]
		if (t - ta) * (t - tb) <= 0.0:
			var f := 0.0 if is_equal_approx(ta, tb) else (t - ta) / (tb - ta)
			var near: Dictionary = a if f < 0.5 else b
			return {"t": t, "c": (a["c"] as Vector3).lerp(b["c"], f),
				"u": (a["u"] as Vector3).lerp(b["u"], f).normalized(), "v": (a["v"] as Vector3).lerp(b["v"], f).normalized(),
				"ru": lerpf(a["ru"], b["ru"], f), "rv": lerpf(a["rv"], b["rv"], f),
				"b0": near["b0"], "b1": near["b1"], "w": near["w"], "sq": lerpf(a.get("sq", 2.0), b.get("sq", 2.0), f)}
	return rows[0] if absf(t - float(rows[0]["t"])) < absf(t - float(rows[-1]["t"])) else rows[-1]


## Rings for a body part in its clothes.
func _dressed(rows: Array, layers: Array, skin: Color) -> Array:
	var t0: float = rows[0]["t"]
	var t1: float = rows[-1]["t"]
	var dir := 1.0 if t1 > t0 else -1.0
	var ts: Array[float] = []
	for r: Dictionary in rows:
		ts.append(float(r["t"]))
	var edges: Array[float] = []
	for l: Dictionary in layers:
		for e: float in [float(l["from"]), float(l["to"])]:
			if (e - t0) * dir > 0.0005 and (t1 - e) * dir > 0.0005:
				edges.append(e)
				ts.append(e)
	ts.sort()
	if dir < 0.0:
		ts.reverse()
	var rings := []
	var last := INF
	for t in ts:
		if is_equal_approx(t, last):
			continue
		last = t
		var base := _at(rows, t)
		var edge := false
		for e in edges:
			if is_equal_approx(e, t):
				edge = true
		if edge:
			var before := _cover(layers, t - 0.0005 * dir)
			var after := _cover(layers, t + 0.0005 * dir)
			if before != after:
				rings.append(_dress(base, before, skin))
				rings.append(_dress(base, after, skin))
				continue
		rings.append(_dress(base, _cover(layers, t), skin))
	return rings


func _dress(base: Dictionary, layer: Dictionary, skin: Color) -> Dictionary:
	var add: float = layer.get("add", 0.0)
	var mn: float = layer.get("min", 0.0)
	var ring := _ring(base["c"], base["u"], base["v"], maxf(float(base["ru"]) + add, mn) * k, maxf(float(base["rv"]) + add, mn) * k,
		base["b0"], base["b1"], base["w"], layer.get("col", skin))
	ring["sq"] = base.get("sq", 2.0)
	for key: String in ["pat", "matte", "print"]:
		if layer.has(key):
			ring[key] = layer[key]
	return ring


func _top_layers_torso() -> Array:
	var top := _g("top")
	var col: Color = top["color"]
	var trim: Color = top["trim"]
	var body := _fab(PAT_NONE, Color.BLACK, 1.0, true) # prints go on the main body of a top
	var rib := _fab(PAT_RIBBED, Color.BLACK, 1.0)
	match top["kind"]:
		"tshirt":
			return [_layer(1.462, 1.482, trim, 0.008).merged(rib), _layer(0.895, 1.462, col, 0.006).merged(body)]
		"longsleeve":
			return [_layer(1.466, 1.486, col.darkened(0.12), 0.008).merged(rib), _layer(0.9, 1.466, col, 0.006).merged(body)]
		"hoodie":
			return [_layer(0.86, 0.905, col.darkened(0.12), 0.011).merged(rib), _layer(0.905, 1.495, col, 0.016).merged(body)]
		"flannel": # untucked, a shirt collar
			var plaid := _fab(PAT_PLAID, trim, 1.0, true)
			return [_layer(0.88, 1.468, col, 0.009).merged(plaid), _layer(1.468, 1.5, col, 0.013).merged(plaid)]
		"bomber": # puffy satin, gathered into knit bands
			var knit := _fab(PAT_RIBBED, Color.BLACK, 1.0)
			return [_layer(0.895, 0.95, trim, 0.013).merged(knit), _layer(0.95, 1.465, col, 0.025).merged(_fab(PAT_NONE, Color.BLACK, 0.4, true)),
				_layer(1.465, 1.5, trim, 0.014).merged(knit)]
		"denim":
			var jean := _fab(PAT_DENIM, Color.BLACK, 1.0, true)
			return [_layer(0.885, 0.925, col, 0.02).merged(jean), _layer(0.925, 1.47, col, 0.016).merged(jean),
				_layer(1.47, 1.505, col, 0.022).merged(jean)]
		"varsity": # wool body, striped knit bands (leather sleeves on the arms)
			var bands := _fab(PAT_RIBBED_STRIPES, trim, 1.0)
			return [_layer(0.89, 0.94, col, 0.014).merged(bands), _layer(0.94, 1.465, col, 0.02).merged(body),
				_layer(1.465, 1.5, col, 0.014).merged(bands)]
		"puffer": # quilted nylon, a high collar
			var quilt := _fab(PAT_QUILTED, Color.BLACK, 0.5, true)
			return [_layer(0.875, 0.9, col.darkened(0.2), 0.026).merged(_fab(PAT_NONE, Color.BLACK, 0.5)),
				_layer(0.9, 1.47, col, 0.032).merged(quilt), _layer(1.47, 1.53, col, 0.026).merged(quilt)]
	# fall jacket: a hem band, a stand-up collar
	return [_layer(0.872, 0.902, col.darkened(0.18), 0.02), _layer(0.902, 1.47, col, 0.018).merged(body), _layer(1.47, 1.512, col, 0.017)]


## Where the top's prints go (see _spots).
func _top_spots() -> Array:
	var top := _g("top")
	var kind: String = top["kind"]
	var spots := []
	var front := Outfit.print_tile(top["print"])
	if front >= 0:
		if kind in Outfit.FRONT_BIG:
			spots.append({"tile": front, "plane": "front", "c": Vector3(0.0, 1.25, 0.0), "w": 0.27, "h": 0.27})
		elif kind == "varsity":
			spots.append({"tile": front, "plane": "front", "c": Vector3(-0.085, 1.3, 0.0), "w": 0.12, "h": 0.12})
		else: # a small logo on the left of the chest
			spots.append({"tile": front, "plane": "front", "c": Vector3(-0.085, 1.35, 0.0), "w": 0.09, "h": 0.09})
	var back := Outfit.print_tile(top["back"])
	if back >= 0:
		spots.append({"tile": back, "plane": "back", "c": Vector3(0.0, 1.25, 0.0), "w": 0.31, "h": 0.31})
	return spots


func _bottom_layers_torso() -> Array:
	var b := _g("bottom")
	var col: Color = b["color"]
	if b["kind"] == "joggers":
		return [_layer(0.97, 1.0, col, 0.009).merged(_fab(PAT_RIBBED)), _layer(0.7, 0.97, col, 0.008)]
	var cloth := _fab(PAT_DENIM) if b["kind"] == "jeans" else {}
	return [_layer(0.972, 1.0, col.darkened(0.3), 0.007).merged(_fab(PAT_NONE, Color.BLACK, 0.6)), _layer(0.7, 0.972, col, 0.005).merged(cloth)] # belt


func _torso() -> void:
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var b := build
	# The bare body. Shoulders slope from the neck down to the arms (no
	# square shelf), the chest is deeper than the waist and the back is
	# flatter than the front.
	# y, half width, half depth, z offset (+ is the back), bone a, bone b, weight on b
	var spec := [
		[0.8, 0.1, 0.08, 0.0, HIPS, HIPS, 0.0], # crotch, inside the legs
		[0.86, 0.16, 0.106, 0.008, HIPS, HIPS, 0.0],
		[0.905, 0.172, 0.11, 0.008, HIPS, HIPS, 0.0],
		[0.94, 0.166, 0.108, 0.006, HIPS, SPINE, 0.2],
		[1.03, 0.143 * lerpf(1.0, b, 0.2), 0.094, 0.004, HIPS, SPINE, 0.6],
		[1.11, 0.137 * lerpf(1.0, b, 0.3), 0.094, 0.0, SPINE, SPINE, 0.0],
		[1.2, 0.145 * lerpf(1.0, b, 0.6), 0.102, -0.006, SPINE, CHEST, 0.5],
		[1.29, 0.156 * b, 0.11, -0.01, CHEST, CHEST, 0.0],
		[1.36, 0.16 * b, 0.108, -0.008, CHEST, CHEST, 0.0],
		[1.415, 0.156 * b, 0.098, -0.002, CHEST, CHEST, 0.0],
		[1.45, 0.146 * b, 0.086, 0.004, CHEST, CHEST, 0.0],
		[1.47, 0.115 * b, 0.072, 0.008, CHEST, CHEST, 0.0],
		[1.482, 0.085 * b, 0.064, 0.01, CHEST, NECK, 0.3],
		[1.495, 0.063, 0.06, 0.012, CHEST, NECK, 0.6],
		[1.55, 0.058, 0.058, 0.016, NECK, HEAD, 0.5],
	]
	var rows := []
	for r: Array in spec:
		var row := _row(r[0], Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK, r[1], r[2], r[4], r[5], r[6])
		row["sq"] = 2.6 if float(r[0]) > 0.9 and float(r[0]) < 1.45 else 2.0 # torso: rounded box, not a tube
		rows.append(row)
	var layers := _top_layers_torso() + _bottom_layers_torso()
	_spots = _top_spots()
	_loft(_dressed(rows, layers, skin), SEGS, true, false)
	_spots = []
	# Details on the front, as thin pieces sitting on the cloth (painting
	# them on blurs: the body's points are too far apart for a sharp line).
	var top := _g("top")
	var col: Color = top["color"]
	var trim: Color = top["trim"]
	var kind: String = top["kind"]
	var front := func(y: float) -> float: # z of the front of the clothes at height y (unscaled)
		var r := _at(rows, y)
		var l := _cover(layers, y)
		return (r["c"] as Vector3).z / k - float(r["rv"]) - float(l.get("add", 0.0))
	var bone_at := func(y: float) -> int:
		return HIPS if y < 1.0 else (SPINE if y < 1.2 else CHEST)
	var metal := _fab(PAT_NONE, Color.BLACK, 0.25)
	match kind:
		"jacket", "bomber", "puffer":
			# The zip, up the front to the collar.
			var zip_col := col.darkened(0.4) if kind != "bomber" else Color(0.7, 0.7, 0.72)
			var zip := []
			for y: float in [0.885, 0.95, 1.05, 1.15, 1.25, 1.33, 1.42]:
				var ring := _ring(Vector3(0.0, y, front.call(y) - 0.0015) * k, Vector3.RIGHT, Vector3.BACK,
					0.0045 * k, 0.003 * k, bone_at.call(y), HIPS, 0.0, zip_col)
				ring.merge(metal)
				zip.append(ring)
			_loft(zip, 6, true, true)
			if kind == "bomber":
				# Slanted hand-warmer pockets.
				for side: float in [-1.0, 1.0]:
					_blob(Vector3(0.1 * side, 1.04, front.call(1.04) + 0.003), Vector3(0.012, 0.06, 0.006), SPINE, col.darkened(0.3))
		"hoodie":
			# The front pocket, the hood bunched behind the neck, the drawstrings.
			_blob(Vector3(0.0, 0.985, front.call(0.985) + 0.004), Vector3(0.1, 0.05, 0.01), SPINE, col.darkened(0.07), 5.0)
			_blob(Vector3(0.0, 1.488, 0.088), Vector3(0.11, 0.06, 0.06), CHEST, col.darkened(0.05))
			for side: float in [-1.0, 1.0]:
				_blob(Vector3(0.035 * side, 1.385, front.call(1.385) - 0.002), Vector3(0.0045, 0.05, 0.0045), CHEST, trim.lightened(0.5))
		"denim":
			# Copper buttons down the front, two flap pockets on the chest, a seam
			# across the yoke.
			var jean := _fab(PAT_DENIM)
			for y: float in [0.91, 1.0, 1.09, 1.18, 1.27, 1.36, 1.44]:
				_blob(Vector3(0.0, y, front.call(y) - 0.002), Vector3(0.008, 0.008, 0.004), bone_at.call(y), trim, 2.0, metal)
			for side: float in [-1.0, 1.0]:
				_blob(Vector3(0.08 * side, 1.335, front.call(1.335) + 0.002), Vector3(0.045, 0.024, 0.008), CHEST, col.darkened(0.12), 5.0, jean)
				_blob(Vector3(0.08 * side, 1.335, front.call(1.335) - 0.004), Vector3(0.006, 0.006, 0.004), CHEST, trim, 2.0, metal)
		"varsity":
			# Snaps down the front.
			for y: float in [0.95, 1.05, 1.15, 1.25, 1.35, 1.44]:
				_blob(Vector3(0.0, y, front.call(y) - 0.002), Vector3(0.007, 0.007, 0.004), bone_at.call(y), trim, 2.0, metal)
		"flannel":
			# Buttons, and the points of the collar.
			for y: float in [0.95, 1.06, 1.17, 1.28, 1.39]:
				_blob(Vector3(0.0, y, front.call(y) - 0.0015), Vector3(0.006, 0.006, 0.003), bone_at.call(y), Color(0.9, 0.88, 0.82))
			for side: float in [-1.0, 1.0]:
				_blob(Vector3(0.035 * side, 1.468, front.call(1.468) + 0.006), Vector3(0.028, 0.02, 0.006), CHEST, col, 2.0, _fab(PAT_PLAID, trim))
		"puffer":
			pass


func _leg(side: float) -> void:
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var up := UPPER_LEG_L if side < 0.0 else UPPER_LEG_R
	var low := up + 1
	var foot := up + 2
	var x := 0.095 * side
	# The bare leg: seat and thigh, knee, calf, ankle.
	# y, radius x, radius z, z offset, bone a, bone b, weight
	var spec := [
		[0.93, 0.066, 0.076, 0.008, HIPS, up, 0.5],
		[0.85, 0.08, 0.088, 0.012, up, up, 0.0], # seat
		[0.76, 0.076, 0.08, 0.0, up, up, 0.0],
		[0.64, 0.066, 0.068, -0.006, up, up, 0.0],
		[0.53, 0.052, 0.055, -0.006, up, low, 0.3],
		[0.49, 0.049, 0.052, -0.004, up, low, 0.5], # knee
		[0.43, 0.05, 0.056, 0.006, low, low, 0.0],
		[0.34, 0.048, 0.055, 0.01, low, low, 0.0], # calf
		[0.22, 0.037, 0.04, 0.004, low, low, 0.0],
		[0.14, 0.032, 0.035, 0.002, low, foot, 0.25], # ankle
		[0.1, 0.036, 0.045, 0.004, low, foot, 0.6],
	]
	var rows := []
	for r: Array in spec:
		rows.append(_row(r[0], Vector3(x * (1.0 - 0.02 * (1.0 - float(r[0]))), r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
			r[1], r[2], r[4], r[5], r[6]))
	var b := _g("bottom")
	var col: Color = b["color"]
	var layers := []
	match b["kind"]:
		"jeans":
			layers = [_layer(0.1, 0.135, col.darkened(0.15), 0.01, 0.058).merged(_fab(PAT_DENIM)), _layer(0.135, 1.0, col, 0.006, 0.055).merged(_fab(PAT_DENIM))]
		"trousers":
			layers = [_layer(0.1, 1.0, col, 0.005, 0.053)]
		"joggers":
			layers = [_layer(0.15, 0.2, col.darkened(0.12), 0.006).merged(_fab(PAT_RIBBED)), _layer(0.2, 1.0, col, 0.012, 0.058)]
		"shorts":
			layers = [_layer(0.5, 0.53, col.darkened(0.12), 0.016, 0.07), _layer(0.53, 1.0, col, 0.014, 0.072)]
	var shoes := _g("shoes")
	if shoes["kind"] == "boots":
		layers.append(_layer(0.0, 0.25, shoes["color"], 0.014, 0.052))
		layers.append(_layer(0.25, 0.27, (shoes["color"] as Color).darkened(0.2), 0.016, 0.054)) # the boot's top edge
	else:
		var sock := Color(0.9, 0.9, 0.88) if shoes["kind"] == "sneakers" else Color(0.12, 0.12, 0.13)
		layers.append(_layer(0.0, 0.17, sock, 0.003))
	_loft(_dressed(rows, layers, skin), LIMB_SEGS, false, true)


func _shoe(side: float) -> void:
	var shoes := _g("shoes")
	var col: Color = shoes["color"]
	var sole: Color = shoes["trim"]
	var foot := FOOT_L if side < 0.0 else FOOT_R
	var fx := 0.098 * side
	# Rings from heel to toe: z, centre y, half width, half height; and how
	# high the sole comes up.
	var rows: Array
	var sole_top := 0.018
	match shoes["kind"]:
		"boots": # chunky, a higher toe and a thick dark sole
			rows = [[0.076, 0.058, 0.042, 0.054], [0.048, 0.064, 0.054, 0.064], [-0.02, 0.058, 0.056, 0.058],
				[-0.1, 0.047, 0.056, 0.047], [-0.155, 0.04, 0.052, 0.038], [-0.188, 0.034, 0.04, 0.029]]
			sole_top = 0.022
		"dress": # slim and low, a long toe, a thin sole
			rows = [[0.066, 0.042, 0.034, 0.036], [0.04, 0.046, 0.044, 0.044], [-0.03, 0.042, 0.045, 0.04],
				[-0.11, 0.032, 0.043, 0.03], [-0.17, 0.025, 0.033, 0.022], [-0.2, 0.019, 0.018, 0.015]]
			sole_top = 0.01
		_: # sneakers: rounded, a thick pale sole
			rows = [[0.07, 0.045, 0.036, 0.036], [0.045, 0.052, 0.048, 0.05], [-0.02, 0.052, 0.05, 0.05],
				[-0.1, 0.042, 0.052, 0.04], [-0.16, 0.034, 0.047, 0.032], [-0.19, 0.028, 0.034, 0.024]]
	var rings := []
	for r: Array in rows:
		var ring := _ring(Vector3(fx, r[1], r[0]) * k, Vector3.RIGHT, Vector3.UP,
			float(r[2]) * k, float(r[3]) * k, foot, foot, 0.0, col)
		ring["sq"] = 2.6
		rings.append(ring)
	var top := sole_top * k
	_loft(rings, LIMB_SEGS, true, true, func(p: Vector3, c: Color) -> Color: return sole if p.y < top else c)


func _arm(side: float) -> void:
	var skin := _c("skin", Color(0.87, 0.69, 0.57))
	var up := UPPER_ARM_L if side < 0.0 else UPPER_ARM_R
	var low := up + 1
	var hand := up + 2
	var shoulder := joint(up)
	var elbow := joint(low)
	var wrist := joint(hand)
	var arm_axis := (elbow - shoulder).normalized()
	var fore_axis := (wrist - elbow).normalized()
	var rows := []
	# The round of the shoulder: the arm curves in over the top toward the
	# neck, starting inside the torso, so it grows out of the body instead of
	# being a tube stuck on with a flat end.
	# t, offset (in, up), axis angle from straight down, radius across, radius front-back
	for r: Array in [[-0.3, 0.055, 0.004, 1.45, 0.02, 0.036], [-0.2, 0.03, 0.006, 1.05, 0.032, 0.046], [-0.1, 0.008, -0.006, 0.55, 0.044, 0.052]]:
		var p := shoulder + Vector3(-side * float(r[1]), float(r[2]), 0.0) * k
		var ang: float = r[3]
		var axis := Vector3(side * sin(ang), -cos(ang), 0.0).lerp(arm_axis, 1.0 - clampf(ang / 0.6, 0.0, 1.0)).normalized()
		var u := Vector3.BACK.cross(axis).normalized()
		rows.append(_row(r[0], p, u, axis.cross(u).normalized(), r[4], r[5], CHEST, up, 0.35))
	# The bare arm (0 shoulder .. 1 elbow .. 2 wrist).
	# t, radius across, radius front-back, bone a, bone b, weight
	for r: Array in [
		[0.06, 0.05, 0.055, CHEST, up, 0.6], # deltoid
		[0.22, 0.049, 0.051, up, up, 0.0],
		[0.5, 0.046, 0.049, up, up, 0.0], # biceps
		[0.85, 0.04, 0.043, up, low, 0.25],
		[1.0, 0.038, 0.041, up, low, 0.5], # elbow
		[1.2, 0.042, 0.043, low, low, 0.0], # forearm
		[1.6, 0.034, 0.034, low, low, 0.0],
		[1.84, 0.025, 0.031, low, hand, 0.1],
		[1.96, 0.023, 0.03, low, hand, 0.5], # wrist
	]:
		var t: float = r[0]
		var p := shoulder.lerp(elbow, t) if t <= 1.0 else elbow.lerp(wrist, t - 1.0)
		var axis := arm_axis if t <= 1.0 else fore_axis
		var u := Vector3.BACK.cross(axis).normalized()
		rows.append(_row(t, p, u, axis.cross(u).normalized(), r[1], r[2], r[3], r[4], r[5]))
	var top := _g("top")
	var col: Color = top["color"]
	var layers := []
	var trim: Color = top["trim"]
	var rib := _fab(PAT_RIBBED)
	var sleeve := _fab(PAT_NONE, Color.BLACK, 1.0, true) # a patch can go on the sleeve
	match top["kind"]:
		"tshirt": # a loose short sleeve
			layers = [_layer(0.38, 0.42, col, 0.007, 0.054), _layer(-1.0, 0.38, col, 0.006, 0.052).merged(sleeve)]
		"longsleeve":
			layers = [_layer(1.8, 1.86, col.darkened(0.12), 0.007).merged(rib), _layer(-1.0, 1.8, col, 0.006).merged(sleeve)]
		"hoodie": # snug ribbed cuffs
			layers = [_layer(1.74, 1.86, trim, 0.007).merged(rib), _layer(-1.0, 1.74, col, 0.014, 0.052).merged(sleeve)]
		"flannel":
			var plaid := _fab(PAT_PLAID, trim)
			layers = [_layer(1.78, 1.86, col, 0.009).merged(plaid), _layer(-1.0, 1.78, col, 0.008).merged(plaid)]
		"bomber":
			layers = [_layer(1.72, 1.86, trim, 0.008).merged(rib), _layer(-1.0, 1.72, col, 0.022, 0.056).merged(_fab(PAT_NONE, Color.BLACK, 0.4, true))]
		"denim":
			var jean := _fab(PAT_DENIM, Color.BLACK, 1.0, true)
			layers = [_layer(1.78, 1.84, col, 0.017).merged(jean), _layer(-1.0, 1.78, col, 0.014).merged(jean)]
		"varsity": # leather sleeves, striped knit cuffs
			layers = [_layer(1.74, 1.86, col, 0.008).merged(_fab(PAT_RIBBED_STRIPES, trim)),
				_layer(-1.0, 1.74, trim, 0.016).merged(_fab(PAT_NONE, Color.BLACK, 0.45))]
		"puffer":
			layers = [_layer(1.78, 1.86, col.darkened(0.2), 0.012).merged(_fab(PAT_NONE, Color.BLACK, 0.5)),
				_layer(-1.0, 1.78, col, 0.026, 0.06).merged(_fab(PAT_QUILTED, Color.BLACK, 0.5, true))]
		_: # fall jacket
			layers = [_layer(1.8, 1.85, col.darkened(0.18), 0.018), _layer(-1.0, 1.8, col, 0.016).merged(sleeve)]
	var patch := Outfit.print_tile(top["patch"])
	if side < 0.0 and patch >= 0:
		_spots = [{"tile": patch, "plane": "left", "c": Vector3(0.0, 1.29, 0.0), "w": 0.09, "h": 0.09}]
	_loft(_dressed(rows, layers, skin), LIMB_SEGS, true, false)
	_spots = []
	_hand(side, wrist, fore_axis, hand, skin)


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
	var style: int = look.get("hair_style", 0)
	var hat := _g("hat")
	var hat_kind: String = hat["kind"]
	var hat_col: Color = hat["color"]
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
	# Where the hat sits: a toque pulled down over the tops of the ears, a
	# ball cap higher, round the crown.
	var hat_line := func(p: Vector3) -> float:
		var z := p.z / kk
		match hat_kind:
			"toque":
				return 1.69 - maxf(0.0, z) * 0.3
			"cap":
				return 1.712 - maxf(0.0, z) * 0.12
		return INF
	var paint := func(p: Vector3, c: Color) -> Color:
		var y := p.y / kk
		var hl: float = hat_line.call(p)
		if y > hl:
			# A toque's turned-up brim is a shade darker.
			return hat_col.darkened(0.12) if hat_kind == "toque" and y < hl + 0.025 else hat_col
		return hair if y > hairline.call(p) else c
	# Hair and hats stand off the skull a little, so they have some volume
	# instead of looking painted on; the short style is fuller on top.
	var centre := Vector3(0.0, 1.66, 0.004) * k
	var shape := func(p: Vector3) -> Vector3:
		var y := p.y / kk
		var hl: float = hat_line.call(p)
		if y > hl:
			var d := 0.013 if hat_kind == "toque" else 0.008
			if hat_kind == "toque" and y < hl + 0.025:
				d += 0.004 # the brim, folded double
			return p + (p - centre).normalized() * d * kk
		var line: float = hairline.call(p)
		if y <= line:
			return p
		var depth := 0.004 if style == 2 else 0.009
		if style == 0:
			depth += 0.006 * smoothstep(1.7, 1.77, y) # fuller on top
		if hat_kind != "none":
			depth = minf(depth, 0.006) # flattened under the hat
		depth *= smoothstep(0.0, 0.012, y - line)
		return p + (p - centre).normalized() * depth * kk
	# The hat: knit for a toque, and a print on the front of either.
	if hat_kind != "none":
		var knit := _fab(PAT_RIBBED if hat_kind == "toque" else PAT_NONE, Color.BLACK, 1.0, true)
		_style = func(p: Vector3) -> Dictionary:
			return knit if p.y / kk > float(hat_line.call(p)) else {}
		var tile := Outfit.print_tile(hat["print"])
		if tile >= 0:
			_spots = [{"tile": tile, "plane": "front", "c": Vector3(0.0, 1.745 if hat_kind == "cap" else 1.738, 0.0), "w": 0.09, "h": 0.065}]
	_loft(rings, 24, false, true, paint, shape)
	_style = Callable()
	_spots = []
	# Face details: nose, eyes, brows, mouth, ears.
	_blob(Vector3(0.0, 1.652, -0.101), Vector3(0.011, 0.02, 0.016), HEAD, skin.darkened(0.04))
	_blob(Vector3(0.0, 1.592, -0.087), Vector3(0.02, 0.012, 0.01), HEAD, skin) # chin
	_blob(Vector3(0.0, 1.615, -0.094), Vector3(0.016, 0.0035, 0.005), HEAD, skin.darkened(0.3)) # mouth
	for s: float in [-1.0, 1.0]:
		_blob(Vector3(0.032 * s, 1.67, -0.093), Vector3(0.012, 0.0085, 0.006), HEAD, Color(0.92, 0.9, 0.87)) # eye white
		_blob(Vector3(0.032 * s, 1.67, -0.097), Vector3(0.0065, 0.0075, 0.004), HEAD, Color(0.12, 0.09, 0.07)) # iris
		_blob(Vector3(0.034 * s, 1.688, -0.095), Vector3(0.018, 0.0045, 0.007), HEAD, hair.darkened(0.25)) # brow
		_blob(Vector3(0.092 * s, 1.655, 0.006), Vector3(0.012, 0.027, 0.018), HEAD, skin.darkened(0.06)) # ear
	if style == 1 and hat_kind != "toque":
		# Long hair falling to the collar at the back.
		var back := []
		for r: Array in [[1.73, 0.092, 0.08, 0.03], [1.64, 0.1, 0.084, 0.04], [1.56, 0.094, 0.07, 0.05], [1.5, 0.078, 0.05, 0.055]]:
			back.append(_ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK,
				float(r[1]) * k, float(r[2]) * k, HEAD, HEAD, 0.0, hair))
		_loft(back, SEGS, true, true)
	match hat_kind:
		"toque":
			_blob(Vector3(0.0, 1.808, 0.012), Vector3(0.028, 0.026, 0.028), HEAD, hat_col.lightened(0.15)) # pompom
		"cap":
			_blob(Vector3(0.0, 1.716, -0.122), Vector3(0.072, 0.006, 0.058), HEAD, hat_col.darkened(0.08)) # peak
			_blob(Vector3(0.0, 1.795, 0.008), Vector3(0.01, 0.006, 0.01), HEAD, hat_col) # button


## A small ellipsoid (nose, eyes, ears, pompom, button) on one bone;
## squareness above 2 makes it more of a rounded box (a pocket, a flap).
## `fabric` gives it a pattern and shine like a layer's (see _fab).
func _blob(center: Vector3, radii: Vector3, bone: int, c: Color, squareness := 2.0, fabric: Dictionary = {}) -> void:
	var e := 2.0 / squareness
	var rings := []
	for i in 5:
		var a := -PI * 0.5 + PI * float(i + 1) / 6.0
		var y := signf(sin(a)) * pow(absf(sin(a)), e) * radii.y
		var s := pow(cos(a), e)
		var ring := _ring((center + Vector3(0.0, y, 0.0)) * k, Vector3.RIGHT, Vector3.BACK,
			radii.x * s * k, radii.z * s * k, bone, bone, 0.0, c)
		ring["sq"] = squareness
		ring.merge(fabric)
		rings.append(ring)
	_loft(rings, 8 if squareness <= 2.0 else 16, true, true)


# --- fabric and prints -------------------------------------------------------------------

## Pattern numbers, as in shaders/person.gdshader.
enum { PAT_NONE, PAT_PLAID, PAT_DENIM, PAT_QUILTED, PAT_RIBBED, PAT_RIBBED_STRIPES }

## Fabric for a layer or blob: a pattern (with its second colour), how matte
## it is (1 cloth, lower for satin, nylon, leather) and whether prints can go
## on it.
func _fab(pattern: int, second := Color.BLACK, matte := 1.0, printable := false) -> Dictionary:
	return {"pat": Color(float(pattern), second.r, second.g, second.b), "matte": matte, "print": printable}


## Where prints go while the current part is built: Array of
## {"tile", "plane" ("front", "back", "left"), "c" (centre, unscaled), "w", "h"}.
var _spots: Array = []
## Optional fabric for points by position, for parts whose clothing isn't
## a layer (the hat on the head): Callable(point) -> Dictionary like _fab's, or {}.
var _style: Callable = Callable()


## The print coordinates for a point: Color(u, v, tile + 1, 1), or none.
## (The 1 marks a printed point: between a printed and a plain point the
## tile number blends through other tiles' numbers, and the shader only
## prints where all three corners are printed.)
func _print_at(p: Vector3, ring_c: Vector3) -> Color:
	var q := p / k
	var d := p - ring_c
	for spot: Dictionary in _spots:
		var c: Vector3 = spot["c"]
		var w: float = spot["w"]
		var h: float = spot["h"]
		var u := 0.0
		match spot["plane"]:
			"front": # seen from in front, the person's left is on the right
				if d.z >= 0.0:
					continue
				u = (c.x + w * 0.5 - q.x) / w
			"back":
				if d.z <= 0.0:
					continue
				u = (q.x - (c.x - w * 0.5)) / w
			"left": # the outside of the left arm
				if d.x >= 0.0:
					continue
				u = (q.z - (c.z - w * 0.5)) / w
		var v := (c.y + h * 0.5 - q.y) / h
		if u > -0.6 and u < 1.6 and v > -0.6 and v < 1.6:
			return Color(u, v, float(spot["tile"]) + 1.0, 1.0)
	return Color(0, 0, 0, 0)


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
			var fabric: Dictionary = r
			if _style.is_valid():
				var st: Dictionary = _style.call(p)
				if not st.is_empty():
					fabric = st
			var pr := Color(0, 0, 0, 0)
			if fabric.get("print", false) and not _spots.is_empty():
				pr = _print_at(p, r["c"])
			var pat: Color = fabric.get("pat", Color(0, 0, 0, 0))
			var matte: float = fabric.get("matte", 1.0)
			if shape.is_valid():
				p = shape.call(p)
			_add_vertex(p, col, r["b0"], r["b1"], r["w"], matte, pr, pat)
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
	# The tip takes on the look of the ring's first point (no print).
	_add_vertex(tip, _colors[start], r["b0"], r["b1"], r["w"], _matte[start], Color(0, 0, 0, 0), _pats[start])
	for s in segs:
		_tri(start + s, start + (s + 1) % segs, centre, out)


var _colors := PackedColorArray()
var _pats := PackedColorArray()
var _matte := PackedFloat32Array()


func _add_vertex(p: Vector3, col: Color, b0: int, b1: int, w: float, matte := 1.0, print_uv := Color(0, 0, 0, 0), pattern := Color(0, 0, 0, 0)) -> void:
	_st.set_color(Color(col.r, col.g, col.b, matte))
	# Rest position, so cloth patterns and prints stick to the body.
	_st.set_uv(Vector2(p.x, p.y))
	_st.set_uv2(Vector2(p.z, 0.0))
	_st.set_custom(0, print_uv)
	_st.set_custom(1, pattern)
	if b0 == b1 or w <= 0.0:
		_st.set_bones(PackedInt32Array([b0, 0, 0, 0]))
		_st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	else:
		_st.set_bones(PackedInt32Array([b0, b1, 0, 0]))
		_st.set_weights(PackedFloat32Array([1.0 - w, w, 0.0, 0.0]))
	_st.add_vertex(p)
	_verts.append(p)
	_colors.append(col)
	_pats.append(pattern)
	_matte.append(matte)
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

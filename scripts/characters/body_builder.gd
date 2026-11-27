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
		_material.set_shader_parameter("uniform_prints", load("res://textures/clothing/uniform_prints.png"))
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
	if top["kind"] == "duty": # a duty shirt tucked in, a shirt collar
		return [_layer(0.975, 1.468, col, 0.008), _layer(1.468, 1.5, col, 0.012)]
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
	if back >= 0 and kind != "duty": # a duty top's goes on its vest
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
		"duty":
			# The points of the collar, then the vest and the belt.
			for side: float in [-1.0, 1.0]:
				_blob(Vector3(0.035 * side, 1.468, front.call(1.468) + 0.006), Vector3(0.028, 0.02, 0.006), CHEST, col)
			_duty(rows, layers)
	_armour(rows, layers)


## Armour plates worn (BodyPaint.armour, look["armour"]): a plate carrier
## over the top, with a raised plate for each one worn: the first on the
## back (what the chase camera sees), the second on the front, the third
## split between the two sides. No plates, no carrier; a plate breaking
## takes its bulge away.
func _armour(rows: Array, layers: Array) -> void:
	var plates: int = clampi(int(look.get("armour", 0)), 0, 3)
	if plates <= 0:
		return
	var vest := Color(0.22, 0.25, 0.19) # olive drab nylon
	var plate := Color(0.29, 0.32, 0.24)
	var strap := vest.darkened(0.25)
	var nylon := _fab(PAT_NONE, Color.BLACK, 0.6)
	# The carrier: a band round the waist (the cummerbund), front and back
	# panels up to the collarbones, open under the arms (its sides sink
	# inside the jacket at chest height so the arms stay free).
	var ys := [0.99, 1.0, 1.11, 1.23, 1.29, 1.4, 1.435]
	var rings := []
	var front := {}
	var back := {}
	var side := {}
	for i in ys.size():
		var y: float = ys[i]
		var base := _at(rows, y)
		var add: float = _cover(layers, y).get("add", 0.0)
		var edge := i == 0 or i == ys.size() - 1 # the hems tuck in
		var thick := 0.006 if edge else 0.016
		var narrow := lerpf(1.0, 0.78, smoothstep(1.13, 1.26, y))
		var ru := (float(base["ru"]) + add) * narrow + thick
		var rv := float(base["rv"]) + add + thick
		var ring := _ring(base["c"], base["u"], base["v"], ru * k, rv * k, base["b0"], base["b1"], base["w"],
			strap if i <= 1 else vest)
		ring["sq"] = 3.0
		ring.merge(nylon)
		rings.append(ring)
		var cz := (base["c"] as Vector3).z / k
		front[y] = cz - rv
		back[y] = cz + rv
		side[y] = ru
	_loft(rings, 12, true, true)
	# Shoulder straps over to the back panel.
	for s: float in [-1.0, 1.0]:
		var r := _at(rows, 1.455)
		var cz := (r["c"] as Vector3).z / k
		_blob(Vector3(0.075 * build * s, 1.452, cz), Vector3(0.026, 0.012, float(r["rv"]) + 0.03), CHEST, strap, 4.0, nylon, 8, 3)
	# The plates, in their pockets.
	if plates >= 1:
		_blob(Vector3(0.0, 1.25, float(back[1.23]) + 0.008), Vector3(0.105 * build, 0.105, 0.014), CHEST, plate, 6.0, nylon, 8, 3)
	if plates >= 2:
		_blob(Vector3(0.0, 1.27, float(front[1.29]) - 0.008), Vector3(0.1 * build, 0.1, 0.014), CHEST, plate, 6.0, nylon, 8, 3)
	if plates >= 3:
		for s: float in [-1.0, 1.0]:
			_blob(Vector3(s * (float(side[1.11]) + 0.006), 1.09, (float(front[1.11]) + float(back[1.11])) * 0.5),
				Vector3(0.012, 0.055, 0.05), SPINE, plate, 6.0, nylon, 8, 3)


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
	if b.has("stripe") and b["kind"] == "trousers":
		_stripe(rows, side, b["stripe"])


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
		"duty": # long sleeves buttoned at the cuff
			layers = [_layer(1.8, 1.86, col.darkened(0.1), 0.01), _layer(-1.0, 1.8, col, 0.009, 0.052).merged(sleeve)]
		_: # fall jacket
			layers = [_layer(1.8, 1.85, col.darkened(0.18), 0.018), _layer(-1.0, 1.8, col, 0.016).merged(sleeve)]
	var patch := Outfit.print_tile(top["patch"])
	if side < 0.0 and patch >= 0:
		_spots = [{"tile": patch, "plane": "left", "c": Vector3(0.0, 1.29, 0.0), "w": 0.09, "h": 0.09}]
	elif top["kind"] == "duty" and patch >= 0:
		# A uniform's patch is on both shoulders.
		_spots = [{"tile": patch, "plane": "right", "c": Vector3(0.0, 1.29, 0.0), "w": 0.09, "h": 0.09}]
	_loft(_dressed(rows, layers, skin), LIMB_SEGS, true, false)
	_spots = []
	_hand(side, wrist, fore_axis, hand, skin)


## A relaxed hand: palm toward the thigh, fingers together and a little
## curled, the thumb in front. Life size (wrist to finger tips about a
## tenth of the height, a palm about 8 cm across and under 3 cm thick),
## thinning toward the finger tips so it reads as a hand, not a paddle.
func _hand(side: float, wrist: Vector3, axis: Vector3, bone: int, skin: Color) -> void:
	var inward := Vector3(-side, 0.0, 0.0)
	# along the hand, thickness (across, x), width (front-back, z), curl in, z shift
	var rows := [
		[-0.02, 0.02, 0.027, 0.0, 0.0],
		[0.015, 0.0165, 0.031, 0.001, -0.001],
		[0.05, 0.0145, 0.037, 0.002, -0.002], # palm
		[0.085, 0.013, 0.038, 0.005, -0.002], # knuckles
		[0.115, 0.0115, 0.034, 0.011, -0.001],
		[0.143, 0.0095, 0.029, 0.019, 0.0],
		[0.163, 0.007, 0.021, 0.027, 0.001], # finger tips
	]
	var rings := []
	for r: Array in rows:
		var p := wrist + axis * float(r[0]) * k + inward * float(r[3]) * k + Vector3(0.0, 0.0, float(r[4])) * k
		var u := Vector3.BACK.cross(axis).normalized()
		var v := axis.cross(u).normalized()
		var ring := _ring(p, u, v, float(r[1]) * k, float(r[2]) * k, bone, bone, 0.0, skin)
		ring["sq"] = 2.3 # a flattened oval, flatter on the back of the hand than a tube
		rings.append(ring)
	_loft(rings, LIMB_SEGS, true, true)
	# Thumb: rooted in the heel of the palm, angling down, forward and a
	# little in across the front of the fingers.
	var base := wrist + axis * 0.022 * k + Vector3(0.0, 0.0, -0.022) * k + inward * 0.004 * k
	var tip := base + (axis * 0.058 + Vector3(0.0, 0.0, -0.013) + inward * 0.011) * k
	var tax := (tip - base).normalized()
	var tu := Vector3.BACK.cross(tax).normalized()
	var tv := tax.cross(tu).normalized()
	var thumb := []
	for r: Array in [[0.0, 0.0115], [0.4, 0.0105], [0.75, 0.009], [1.0, 0.0065]]:
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
	# The front of the face at (x, y), unscaled z, for putting the features on it.
	var face_z := func(x: float, y: float) -> float:
		for i in rows.size() - 1:
			var a: Array = rows[i]
			var b: Array = rows[i + 1]
			if y >= float(a[0]) and y <= float(b[0]):
				var f := (y - float(a[0])) / (float(b[0]) - float(a[0]))
				var bulge: float = 1.0 + 0.048 * f * (1.0 - f) if i >= 2 else 1.0
				var hw: float = lerpf(a[1], b[1], f) * bulge
				var hd: float = lerpf(a[2], b[2], f) * bulge
				return lerpf(a[3], b[3], f) - hd * sqrt(maxf(0.0, 1.0 - pow(x / hw, 2.0)))
		return 0.0
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
			"forage_cap":
				return 1.7 - maxf(0.0, z) * 0.04
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
	# Face details: nose, eyes, lids, brows, lips, ears, each set on the
	# face (`face_z` + how far it sinks in). The small ones are cheap
	# blobs (6 points round, 3 rings): a person is drawn by the dozen.
	var on := func(x: float, y: float, sink: float) -> Vector3:
		return Vector3(x, y, float(face_z.call(x, y)) + sink)
	var lip := skin.lerp(Color(0.66, 0.34, 0.34), 0.2).darkened(0.08)
	_blob(on.call(0.0, 1.662, 0.004), Vector3(0.0085, 0.019, 0.0105), HEAD, skin, 2.0, {}, 8, 4) # bridge
	_blob(on.call(0.0, 1.6435, 0.0005), Vector3(0.0092, 0.0085, 0.0105), HEAD, skin.darkened(0.02), 2.0, {}, 8, 4) # tip
	_blob(on.call(0.0, 1.6345, 0.0), Vector3(0.0085, 0.003, 0.006), HEAD, skin.darkened(0.45), 2.0, {}, 6, 3) # nostrils
	# The lips: one soft shape mostly sunk into the face, a little darker
	# and redder than the skin, the lower lip a touch fuller and lighter,
	# a thin line where they meet. No more forward than a real mouth.
	_blob(on.call(0.0, 1.6125, 0.0036), Vector3(0.0165, 0.0072, 0.005), HEAD, lip, 2.0, {}, 8, 3)
	_blob(on.call(0.0, 1.6095, 0.0024), Vector3(0.0115, 0.0034, 0.004), HEAD, lip.lightened(0.05), 2.0, {}, 8, 3) # lower lip
	_blob(on.call(0.0, 1.6128, 0.0021), Vector3(0.0158, 0.0009, 0.0039), HEAD, lip.darkened(0.45), 2.0, {}, 6, 3) # where they meet
	for s: float in [-1.0, 1.0]:
		var ex := 0.032 * s
		_blob(on.call(ex, 1.669, 0.0035), Vector3(0.0125, 0.0075, 0.0065), HEAD, Color(0.93, 0.91, 0.88), 2.0, {}, 8, 3) # eye white
		_blob(on.call(ex, 1.6685, -0.0004), Vector3(0.0058, 0.0062, 0.0032), HEAD, look.get("eyes", Color(0.28, 0.2, 0.13)), 2.0, {}, 6, 3) # iris
		_blob(on.call(ex, 1.6685, -0.0019), Vector3(0.0026, 0.0028, 0.0013), HEAD, Color(0.03, 0.03, 0.03), 2.0, {}, 6, 3) # pupil
		_blob(on.call(ex, 1.6772, 0.0042), Vector3(0.0135, 0.0036, 0.0064), HEAD, skin.darkened(0.1), 2.0, {}, 6, 3) # upper lid
		_blob(on.call(0.034 * s, 1.688, 0.0015), Vector3(0.019, 0.0042, 0.0065), HEAD, hair.darkened(0.25), 2.0, {}, 6, 3) # brow
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
		"forage_cap":
			_forage_cap(hat)


## A small ellipsoid (nose, eyes, ears, pompom, button) on one bone;
## squareness above 2 makes it more of a rounded box (a pocket, a flap).
## `fabric` gives it a pattern and shine like a layer's (see _fab).
## `segs` and `n` (rings) make small ones cheaper: features a few
## millimetres across (pupils, lids, nostrils) read the same with fewer.
func _blob(center: Vector3, radii: Vector3, bone: int, c: Color, squareness := 2.0, fabric: Dictionary = {}, segs := 0, n := 5) -> void:
	var e := 2.0 / squareness
	var rings := []
	for i in n:
		var a := -PI * 0.5 + PI * float(i + 1) / float(n + 1)
		var y := signf(sin(a)) * pow(absf(sin(a)), e) * radii.y
		var s := pow(cos(a), e)
		var ring := _ring((center + Vector3(0.0, y, 0.0)) * k, Vector3.RIGHT, Vector3.BACK,
			radii.x * s * k, radii.z * s * k, bone, bone, 0.0, c)
		ring["sq"] = squareness
		ring.merge(fabric)
		rings.append(ring)
	if segs <= 0:
		segs = 8 if squareness <= 2.0 else 16
	_loft(rings, segs, true, true)


# --- fabric and prints -------------------------------------------------------------------

## Pattern numbers, as in shaders/person.gdshader.
enum { PAT_NONE, PAT_PLAID, PAT_DENIM, PAT_QUILTED, PAT_RIBBED, PAT_RIBBED_STRIPES, PAT_CHECK }

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
			"right": # the outside of the right arm
				if d.x <= 0.0:
					continue
				u = (c.z + w * 0.5 - q.z) / w
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


# --- uniforms ----------------------------------------------------------------------------
#
# The pieces only a uniform has (Outfit.UNIFORM_KINDS): an officer's vest
# carrier and duty belt over the duty shirt, the stripe down the trousers
# and the peaked forage cap. All of it is in the one mesh, like the rest.

## An officer's kit over the duty shirt: a vest carrier (its colour is the
## top's "trim") with the force's lettering across the back, a badge and a
## name tape on the chest, the radio and the shoulder mic, two pouches;
## and the duty belt with its buckle, holster, magazine and cuff pouches,
## baton and glove pouch.
func _duty(rows: Array, layers: Array) -> void:
	var top := _g("top")
	var vest: Color = top["trim"]
	var fip := str(top.get("force", "city")) == "fip"
	var metal_col := Color(0.86, 0.68, 0.24) if fip else Color(0.78, 0.8, 0.83)
	var nylon := _fab(PAT_NONE, Color.BLACK, 0.65, true)
	var gear := Color(0.045, 0.045, 0.05)
	var leather := _fab(PAT_NONE, Color.BLACK, 0.35)
	var shine := _fab(PAT_NONE, Color.BLACK, 0.22)
	# The carrier: front and back panels to the collarbones, a band round the
	# waist, open under the arms; the hems tuck in.
	var ys := [1.0, 1.01, 1.11, 1.23, 1.3, 1.4, 1.435]
	var rings := []
	var surface := func(y: float, thick: float) -> Array: # [half width, half depth, centre z], unscaled
		var base := _at(rows, y)
		var add: float = _cover(layers, y).get("add", 0.0)
		var narrow := lerpf(1.0, 0.8, smoothstep(1.13, 1.26, y))
		return [(float(base["ru"]) + add) * narrow + thick, float(base["rv"]) + add + thick, (base["c"] as Vector3).z / k]
	for i in ys.size():
		var y: float = ys[i]
		var base := _at(rows, y)
		var edge := i == 0 or i == ys.size() - 1
		var sv: Array = surface.call(y, 0.006 if edge else 0.015)
		var ring := _ring(base["c"], base["u"], base["v"], float(sv[0]) * k, float(sv[1]) * k, base["b0"], base["b1"], base["w"], vest)
		ring["sq"] = 3.0
		ring.merge(nylon)
		rings.append(ring)
	var back := Outfit.print_tile(top["back"])
	if back >= 0:
		_spots = [{"tile": back, "plane": "back", "c": Vector3(0.0, 1.26, 0.0), "w": 0.27, "h": 0.27}]
	_loft(rings, 14, true, true)
	_spots = []
	var vest_front := func(y: float) -> float:
		var sv: Array = surface.call(y, 0.015)
		return float(sv[2]) - float(sv[1])
	# Shoulder straps over to the back.
	for s: float in [-1.0, 1.0]:
		var r := _at(rows, 1.455)
		_blob(Vector3(0.075 * build * s, 1.452, (r["c"] as Vector3).z / k), Vector3(0.028, 0.012, float(r["rv"]) + 0.028), CHEST, vest, 4.0, nylon, 8, 3)
	# Badge on the left of the chest, name tape on the right.
	_blob(Vector3(-0.085, 1.355, vest_front.call(1.355) - 0.002), Vector3(0.016, 0.02, 0.004), CHEST, metal_col, 3.0, shine, 8, 3)
	_blob(Vector3(0.085, 1.37, vest_front.call(1.37) - 0.001), Vector3(0.042, 0.011, 0.003), CHEST,
		metal_col if fip else Color(0.82, 0.82, 0.8), 5.0, nylon, 8, 3)
	# The radio on the left, its stubby aerial, the mic on the right shoulder.
	_blob(Vector3(-0.1, 1.2, vest_front.call(1.2) - 0.012), Vector3(0.024, 0.05, 0.014), CHEST, gear, 5.0, leather, 8, 3)
	_blob(Vector3(-0.112, 1.27, vest_front.call(1.25) - 0.012), Vector3(0.006, 0.026, 0.006), CHEST, gear, 2.0, {}, 6, 3)
	_blob(Vector3(0.08 * build, 1.425, vest_front.call(1.4) - 0.01), Vector3(0.016, 0.022, 0.012), CHEST, gear, 4.0, leather, 8, 3)
	# Two pouches low on the front.
	for s: float in [-1.0, 1.0]:
		_blob(Vector3(0.065 * s, 1.075, vest_front.call(1.075) - 0.01), Vector3(0.03, 0.034, 0.011), SPINE, vest.darkened(0.2), 5.0, nylon, 8, 3)
	# The duty belt.
	var belt := []
	for e: Array in [[0.927, 0.004], [0.932, 0.014], [0.982, 0.014], [0.987, 0.004]]:
		var y: float = e[0]
		var base := _at(rows, y)
		var add: float = _cover(layers, y).get("add", 0.0)
		var ring := _ring(base["c"], base["u"], base["v"], (float(base["ru"]) + add + float(e[1])) * k,
			(float(base["rv"]) + add + float(e[1])) * k, HIPS, HIPS, 0.0, gear)
		ring["sq"] = 2.6
		ring.merge(leather)
		belt.append(ring)
	_loft(belt, SEGS, false, false)
	var bb := _at(rows, 0.957)
	var bru := float(bb["ru"]) + 0.02
	var brv := float(bb["rv"]) + 0.02
	var bcz := (bb["c"] as Vector3).z / k
	# A point on the belt at angle a (0 ahead, PI/2 the right hip), `out` beyond it.
	var at := func(a: float, y: float, out: float) -> Vector3:
		return Vector3(sin(a) * (bru + out), y, bcz - cos(a) * (brv + out))
	_blob(at.call(0.0, 0.957, -0.002), Vector3(0.024, 0.021, 0.004), HIPS, metal_col, 4.0, shine, 8, 3) # buckle
	# Holster on the right hip, the grip of the marker in it.
	_blob(at.call(1.75, 0.9, 0.02), Vector3(0.026, 0.08, 0.045), HIPS, gear, 4.0, leather)
	_blob(at.call(1.75, 0.985, 0.022), Vector3(0.018, 0.035, 0.028), HIPS, Color(0.12, 0.12, 0.13), 3.0, leather, 8, 3)
	# Magazine pouches ahead on the left, cuffs and gloves behind.
	_blob(at.call(-0.6, 0.952, 0.012), Vector3(0.034, 0.033, 0.016), HIPS, gear, 5.0, leather, 8, 3)
	_blob(at.call(2.65, 0.955, 0.012), Vector3(0.028, 0.03, 0.016), HIPS, gear, 5.0, leather, 8, 3)
	_blob(at.call(-2.6, 0.955, 0.012), Vector3(0.03, 0.028, 0.015), HIPS, gear, 5.0, leather, 8, 3)
	# The baton, hanging in its ring on the left.
	_blob(at.call(-1.7, 0.86, 0.016), Vector3(0.012, 0.13, 0.012), HIPS, Color(0.03, 0.03, 0.035), 2.0, shine, 8, 4)


## The stripe down the outside of a trouser leg (the FIP's gold, after the
## RCMP's), following the leg as it bends.
func _stripe(rows: Array, side: float, col: Color) -> void:
	var rings := []
	for y: float in [0.91, 0.85, 0.76, 0.64, 0.53, 0.49, 0.43, 0.34, 0.28]:
		var base := _at(rows, y)
		var r := maxf(float(base["ru"]) + 0.005, 0.053) + 0.0012
		var p: Vector3 = base["c"] + (base["u"] as Vector3) * side * r * k
		rings.append(_ring(p, Vector3.BACK, Vector3.RIGHT, 0.011 * k, 0.0022 * k, base["b0"], base["b1"], base["w"], col))
	_loft(rings, 6, true, true)


## A peaked forage cap: a band (the city's black and white chequers, the
## FIP's plain gold, after the RCMP's), a crown wider than the head with its
## front stiffened up, a glossy black peak and a badge.
func _forage_cap(hat: Dictionary) -> void:
	var col: Color = hat["color"]
	var band_col: Color = hat["trim"]
	var check := str(hat.get("band", "plain")) == "check"
	var band_fab := _fab(PAT_CHECK, Color(0.93, 0.93, 0.9)) if check else _fab(PAT_NONE, Color.BLACK, 0.7)
	var rings := []
	# y, half width, half depth, z offset; the first two are the band.
	for r: Array in [[1.697, 0.1, 0.113, 0.004], [1.736, 0.1, 0.113, 0.004], [1.737, 0.101, 0.114, 0.003],
			[1.765, 0.111, 0.125, -0.003], [1.788, 0.119, 0.133, -0.009], [1.797, 0.114, 0.128, -0.009],
			[1.8, 0.07, 0.08, -0.009], [1.801, 0.012, 0.014, -0.009]]: # the top, flat
		var ring := _ring(Vector3(0.0, r[0], r[3]) * k, Vector3.RIGHT, Vector3.BACK, float(r[1]) * k, float(r[2]) * k, HEAD, HEAD, 0.0,
			band_col if float(r[0]) < 1.7365 else col)
		ring.merge(band_fab if float(r[0]) < 1.7365 else _fab(PAT_NONE, Color.BLACK, 0.9))
		rings.append(ring)
	_loft(rings, 24, false, true)
	var gloss := _fab(PAT_NONE, Color.BLACK, 0.15)
	_blob(Vector3(0.0, 1.693, -0.128), Vector3(0.08, 0.0075, 0.052), HEAD, Color(0.03, 0.03, 0.035), 2.0, gloss) # peak
	var badge := Color(0.86, 0.68, 0.24) if not check else Color(0.8, 0.82, 0.85)
	_blob(Vector3(0.0, 1.758, -0.124), Vector3(0.014, 0.017, 0.004), HEAD, badge, 3.0, _fab(PAT_NONE, Color.BLACK, 0.22), 8, 3)

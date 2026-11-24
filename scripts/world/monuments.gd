class_name Monuments
extends Node3D
## One-off things placed by hand from map_config.json "monuments": a war
## memorial (bronze soldiers on a granite pedestal) and flagpoles. Each entry
## has "kind", "at" [latitude, longitude] and, for a memorial, "facing" (a
## compass bearing, 0 = north, 90 = east, as in field notes). A flagpole
## takes "flag" (a picture in textures/flags/) and "height" in metres.
##
## The city entrance at Riverside Drive and the Hillsborough Bridge adds:
##  * "flag_row": poles spaced evenly along "line" (a list of [latitude,
##    longitude]), flying "flags" (names from textures/flags/atlas.json, in
##    order), "height" in metres. One mesh for the poles and one for every
##    flag, drawn from the one atlas picture.
##  * "iron_fence": a black picket fence along "line", "height" in metres,
##    with brick piers at its ends.
##  * "welcome_sign": the city's welcome wall at "at", its face looking
##    toward "facing" (a picture in textures/signs/, "texture").
##  * "lane_sign": a sign on a post at "at" facing "facing": "texture" (in
##    textures/signs/), "width" and "height" in metres, and optionally
##    "marker" (another picture, a small square under it).
##  * "pylon_sign": a business's pole sign by the road at "at", its boards
##    across "facing" (they show both ways): "height" to the top, and
##    "panels", top first, each {texture, width, height} (pictures in
##    textures/signs/, transparent where the board's corners are rounded).
##
## There are only a few, so they're built once at startup, on the main
## thread, rather than with the chunks.

const BRONZE := Color(0.27, 0.26, 0.19)
const BRONZE_DARK := Color(0.2, 0.2, 0.15)
const GRANITE := Color(0.55, 0.55, 0.54)

var _data: StreetData
var _terrain: Terrain


func setup(data: StreetData, terrain: Terrain) -> void:
	_data = data
	_terrain = terrain
	for m: Dictionary in data.config.get("monuments", []):
		var at: Array = m.get("at", [])
		if at.is_empty() and m.has("line"):
			at = m["line"][0]
		if at.size() < 2:
			continue
		var p := data.projection.to_ground(float(at[1]), float(at[0]))
		data.keep_clear.append(p)
		match str(m.get("kind", "")):
			"war_memorial":
				_war_memorial(p, float(m.get("facing", 0.0)))
			"flagpole":
				_flagpole(p, str(m.get("flag", "canada")), float(m.get("height", 12.0)))
			"flag_row":
				_flag_row(_line(m), m.get("flags", []), float(m.get("height", 9.0)))
			"iron_fence":
				_iron_fence(_line(m), float(m.get("height", 1.8)))
			"welcome_sign":
				_welcome_sign(p, float(m.get("facing", 0.0)), str(m.get("texture", "")))
			"lane_sign":
				_lane_sign(p, float(m.get("facing", 0.0)), m)
			"pylon_sign":
				_pylon_sign(p, float(m.get("facing", 0.0)), m)


## Ground point to a world position standing on the ground there.
func _on_ground(p: Vector2, lift := 0.0) -> Vector3:
	return _terrain.at(p, lift)


## Yaw (rotation about y) that turns a model facing -Z toward a compass bearing.
static func _yaw_for_bearing(bearing: float) -> float:
	return -deg_to_rad(bearing)


func _war_memorial(p: Vector2, facing: float) -> void:
	var root := Node3D.new()
	root.name = "WarMemorial"
	root.position = _on_ground(p)
	root.rotation.y = _yaw_for_bearing(facing)
	add_child(root)
	var mats := Materials.get_shared()
	var granite := mats.plain(GRANITE, 0.75)
	var dark_granite := mats.plain(GRANITE.darkened(0.25), 0.7)
	# Two low steps, the inscribed die, and a moulded cap.
	var tiers := [
		[Vector3(7.0, 0.35, 5.2), 0.0, granite],
		[Vector3(6.0, 0.35, 4.4), 0.35, granite],
		[Vector3(4.6, 2.6, 3.0), 0.7, dark_granite],
		[Vector3(5.0, 0.35, 3.4), 3.3, granite],
	]
	for t: Array in tiers:
		var box := BoxMesh.new()
		box.size = t[0]
		box.material = t[2]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position.y = float(t[1]) + (t[0] as Vector3).y * 0.5
		root.add_child(mi)
	# A bronze plaque on the front of the die (the front faces -Z).
	var plaque := BoxMesh.new()
	plaque.size = Vector3(2.6, 1.4, 0.05)
	plaque.material = mats.plain(BRONZE_DARK, 0.5, 0.6)
	var pm := MeshInstance3D.new()
	pm.mesh = plaque
	pm.position = Vector3(0.0, 2.0, -1.52)
	root.add_child(pm)
	var top := 3.65
	# A low bronze rock under the figures' feet.
	var rock := BoxMesh.new()
	rock.size = Vector3(4.2, 0.3, 2.4)
	rock.material = mats.plain(BRONZE, 0.55, 0.5)
	var rm := MeshInstance3D.new()
	rm.mesh = rock
	rm.position.y = top + 0.15
	root.add_child(rm)
	# Three soldiers advancing in a staggered line, a little out of step,
	# rifles across their chests. Heroic scale: a head taller than life.
	var offsets := [Vector3(-1.35, 0.0, -0.2), Vector3(0.0, 0.0, 0.3), Vector3(1.35, 0.0, -0.1)]
	var steps := [3, 9, 14]
	for k in 3:
		var s := HumanoidModel.new()
		s.set_appearance({"skin": BRONZE, "hair": BRONZE_DARK, "height": 2.2, "build": 1.1, "outfit": {
			"hat": {"kind": "toque", "color": BRONZE_DARK},
			"top": {"kind": "jacket", "color": BRONZE, "trim": BRONZE},
			"bottom": {"kind": "trousers", "color": BRONZE},
			"shoes": {"kind": "boots", "color": BRONZE_DARK, "trim": BRONZE_DARK}}})
		s.position = offsets[k] + Vector3(0.0, top + 0.3, 0.0)
		# Advancing toward the front-left, as in Joe's photo.
		s.rotation.y = deg_to_rad(60.0) + [0.08, 0.0, -0.06][k]
		root.add_child(s)
		# Strike the pose: run the walk cycle into a stride, then hold it.
		s.set_motion(3.4, 1.5)
		for i in 40 + steps[k]:
			s._process(1.0 / 30.0)
		s.set_process(false)
		_rifle(s)
	_collider(root, Vector3(7.0, top + 2.6, 5.2))


## A rifle held diagonally across the chest, following the chest bone.
func _rifle(s: HumanoidModel) -> void:
	if s.skeleton == null:
		return
	var holder := BoneAttachment3D.new()
	holder.bone_idx = BodyBuilder.CHEST
	s.skeleton.add_child(holder)
	var mats := Materials.get_shared()
	var stock := BoxMesh.new()
	stock.size = Vector3(0.06, 0.08, 1.15)
	stock.material = mats.plain(BRONZE_DARK, 0.5, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = stock
	# In front of the chest, muzzle up and forward to the right.
	mi.position = Vector3(0.0, 0.05, -0.2)
	mi.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-30.0), 0.0)
	holder.add_child(mi)


func _flagpole(p: Vector2, flag: String, height: float) -> void:
	var root := Node3D.new()
	root.name = "Flagpole_%s" % flag
	root.position = _on_ground(p)
	add_child(root)
	var mats := Materials.get_shared()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.09
	pole.height = height
	pole.radial_segments = 10
	pole.material = mats.plain(Color(0.86, 0.86, 0.84), 0.4, 0.3)
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.position.y = height * 0.5
	root.add_child(pm)
	var ball := SphereMesh.new()
	ball.radius = 0.11
	ball.height = 0.22
	ball.material = mats.plain(Color(0.83, 0.68, 0.3), 0.35, 0.8)
	var bm := MeshInstance3D.new()
	bm.mesh = ball
	bm.position.y = height + 0.1
	root.add_child(bm)
	# The flag: a strip of quads from the pole outward (UV.x 0 at the pole),
	# rippled by the shader. It flies with the wind from the west.
	var tex := load("res://textures/flags/%s.png" % flag) as Texture2D
	var fw := clampf(height * 0.3, 2.0, 4.5)
	var fh := fw * 0.5
	var plane := PlaneMesh.new()
	plane.size = Vector2(fw, fh)
	plane.orientation = PlaneMesh.FACE_Z
	plane.subdivide_width = 16
	plane.subdivide_depth = 4
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	mat.set_shader_parameter("flag", tex)
	plane.material = mat
	var fm := MeshInstance3D.new()
	fm.mesh = plane
	fm.position = Vector3(fw * 0.5 + 0.08, height - fh * 0.5 - 0.15, 0.0)
	root.add_child(fm)
	_collider(root, Vector3(0.3, height, 0.3))


func _collider(root: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	root.add_child(body)



## A monument's "line" as ground points.
func _line(m: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for ll: Array in m.get("line", []):
		var q := _data.projection.to_ground(float(ll[1]), float(ll[0]))
		out.append(q)
		_data.keep_clear.append(q)
	return out


## Points spaced evenly along a polyline, ends included.
static func _spaced(line: PackedVector2Array, count: int) -> PackedVector2Array:
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var out := PackedVector2Array()
	for k in count:
		var want := total * (float(k) / maxf(1.0, count - 1.0))
		for i in line.size() - 1:
			var seg := line[i].distance_to(line[i + 1])
			if want <= seg + 0.001 or i == line.size() - 2:
				out.append(line[i].lerp(line[i + 1], clampf(want / maxf(seg, 0.001), 0.0, 1.0)))
				break
			want -= seg
	return out


## A tapered cylinder (no end caps: the bottom is in the ground, the top
## under a ball) from y0 to y1 at p.
static func _pole(kit: MeshKit, p: Vector3, y1: float, r0: float, r1: float, segments := 10) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var top := Vector3(p.x, y1, p.z)
		kit.quad_smooth(p + d0 * r0, p + d1 * r0, top + d1 * r1, top + d0 * r1, d0, d1, d1, d0, (d0 + d1) * 0.5)


## A small diamond-shaped knob (8 triangles) standing in for a ball.
static func _knob(kit: MeshKit, c: Vector3, r: float) -> void:
	var up := c + Vector3(0, r, 0)
	var dn := c - Vector3(0, r, 0)
	var ring := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	for i in 4:
		var a: Vector3 = c + ring[i]
		var b: Vector3 = c + ring[(i + 1) % 4]
		var out: Vector3 = (ring[i] + ring[(i + 1) % 4]).normalized()
		kit.tri(a, b, up, out + Vector3.UP)
		kit.tri(b, a, dn, out + Vector3.DOWN)


## A row of flagpoles flying the atlas's flags. Two meshes in all: white
## poles (with gilt knobs by vertex colour) and every flag in one strip mesh.
func _flag_row(line: PackedVector2Array, flags: Array, height: float) -> void:
	if line.size() < 2 or flags.is_empty():
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://textures/flags/atlas.json"))
	var names: Array = layout.get("flags", [])
	var cols := int(layout.get("cols", 4))
	var rows := int(layout.get("rows", 4))
	var root := Node3D.new()
	root.name = "FlagRow"
	add_child(root)
	var poles := MeshKit.new()
	poles.use_color = true
	var cloth := MeshKit.new()
	cloth.use_color = true
	cloth.use_uv2 = true
	var fw := clampf(height * 0.22, 1.5, 2.4)
	var fh := fw * 0.5
	var nx := 10
	var ny := 3
	var at := _spaced(line, flags.size())
	for k in flags.size():
		var g := _on_ground(at[k])
		poles.color = Color(0.9, 0.9, 0.88)
		_pole(poles, g - Vector3(0, 0.3, 0), g.y + height, 0.075, 0.045)
		poles.color = Color(0.83, 0.68, 0.3)
		_knob(poles, g + Vector3(0, height + 0.08, 0), 0.09)
		var cell := maxi(0, names.find(str(flags[k])))
		var cu := float(cell % cols)
		var cv := floorf(float(cell) / cols)
		cloth.color = Color(fmod(k * 0.37, 1.0), 0, 0)
		var x0 := g.x + 0.06
		var ytop := g.y + height - 0.12
		for i in nx:
			for j in ny:
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				var corners := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
				var pts: Array[Vector3] = []
				var uv: Array[Vector2] = []
				for c: Vector2 in corners:
					pts.append(Vector3(x0 + c.x * fw, ytop - c.y * fh, g.z))
					# Inset a hair so filtering never picks up the next cell.
					uv.append(Vector2((cu + 0.004 + c.x * 0.992) / cols, (cv + 0.004 + c.y * 0.992) / rows))
				cloth.quad_uv2(pts[0], pts[1], pts[2], pts[3], Vector3.BACK, uv[0], uv[1], uv[2], uv[3],
						corners[0], corners[1], corners[2], corners[3])
		_box_body(root, g, Vector3(0.25, height, 0.25), 0.0)
	var pm := MeshInstance3D.new()
	pm.name = "Poles"
	pm.mesh = ModelLod.finish_kits([[poles, _vertex_colour_material(0.4, 0.3)]])
	root.add_child(pm)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag_row.gdshader")
	mat.set_shader_parameter("flag", load("res://textures/flags/atlas.png"))
	var fm := MeshInstance3D.new()
	fm.name = "Flags"
	# No automatic LODs here: the ripple needs the strip's columns.
	fm.mesh = cloth.commit_indexed(null, mat)
	root.add_child(fm)


static var _vc_materials := {}


## A plain material coloured by the mesh's vertex colours.
static func _vertex_colour_material(roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "%.2f/%.2f" % [roughness, metallic]
	if not _vc_materials.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = roughness
		m.metallic = metallic
		_vc_materials[key] = m
	return _vc_materials[key]


## A black steel picket fence: posts every 2.4 m, top and bottom rails, and
## pickets as flat two-sided strips (2 quads each, rule 7) with spear tips,
## between red-brick piers at the ends.
func _iron_fence(line: PackedVector2Array, height: float) -> void:
	if line.size() < 2:
		return
	var root := Node3D.new()
	root.name = "IronFence"
	add_child(root)
	var steel := MeshKit.new()
	steel.use_color = true
	steel.color = Color(0.04, 0.04, 0.045)
	var brick := MeshKit.new()
	brick.use_color = true
	brick.color = Color(0.5, 0.24, 0.18)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.1:
			continue
		var t := (b - a) / seg
		var n3 := Vector3(-t.y, 0, t.x)
		var t3 := Vector3(t.x, 0, t.y)
		# Rails, following the ground in steps of a post bay.
		var bays := maxi(1, int(ceil(seg / 2.4)))
		for k in bays:
			var p0 := a + t * seg * k / bays
			var p1 := a + t * seg * (k + 1) / bays
			var g0 := _terrain.h2(p0)
			var g1 := _terrain.h2(p1)
			for y: float in [0.15, height - 0.25]:
				_bar(steel, MeshKit.v3(p0, g0 + y), MeshKit.v3(p1, g1 + y), n3, 0.03)
			_post_box(steel, MeshKit.v3(p0, g0 - 0.2), height + 0.25, 0.05, t3, n3)
			# Pickets every 13 cm, each a strip seen from both sides.
			var count := int(p0.distance_to(p1) / 0.13)
			for q in range(1, count):
				var f := float(q) / count
				var pq := p0.lerp(p1, f)
				var gq := lerpf(g0, g1, f)
				var lo := MeshKit.v3(pq, gq + 0.05)
				var hi := MeshKit.v3(pq, gq + height)
				var w := t3 * 0.011
				steel.quad(lo - w, lo + w, hi + w, hi - w, n3)
				steel.quad(lo + w, lo - w, hi - w, hi + w, -n3)
				# A spear tip: one triangle each side.
				var tip := hi + Vector3(0, 0.09, 0)
				steel.tri(hi - w * 2.2, hi + w * 2.2, tip, n3)
				steel.tri(hi + w * 2.2, hi - w * 2.2, tip, -n3)
		_box_body(root, MeshKit.v3((a + b) * 0.5, _terrain.h2((a + b) * 0.5)), Vector3(seg, height, 0.12), atan2(-t.y, t.x))
	# Brick piers with a stone cap at both ends.
	for e: Vector2 in [line[0], line[line.size() - 1]]:
		var t := (line[1] - line[0]).normalized()
		var g := _on_ground(e)
		_block(brick, g - Vector3(0, 0.2, 0), Vector3(0.6, height + 0.45, 0.6), t)
		brick.color = Color(0.72, 0.7, 0.66)
		_block(brick, g + Vector3(0, height + 0.25, 0), Vector3(0.72, 0.12, 0.72), t)
		brick.color = Color(0.5, 0.24, 0.18)
	var mi := MeshInstance3D.new()
	mi.name = "Fence"
	mi.mesh = ModelLod.finish_kits([[steel, _vertex_colour_material(0.5, 0.4)]])
	brick.commit_indexed(mi.mesh as ArrayMesh, _vertex_colour_material(0.85, 0.0))
	root.add_child(mi)


## A thin square rail from a to b.
static func _bar(kit: MeshKit, a: Vector3, b: Vector3, side: Vector3, r: float) -> void:
	var up := Vector3.UP * r
	var s := side * r
	kit.quad(a - s + up, b - s + up, b + s + up, a + s + up, Vector3.UP)
	kit.quad(a - s - up, b - s - up, b - s + up, a - s + up, -side)
	kit.quad(a + s - up, b + s - up, b + s + up, a + s + up, side)


## A square post standing at p (four sides and a top).
static func _post_box(kit: MeshKit, p: Vector3, h: float, r: float, t: Vector3, n: Vector3) -> void:
	_block(kit, p, Vector3(r * 2, h, r * 2), Vector2(t.x, t.z))


## A box standing on p, its width along t (a ground direction).
static func _block(kit: MeshKit, p: Vector3, size: Vector3, t: Vector2) -> void:
	var tx := Vector3(t.x, 0, t.y) * size.x * 0.5
	var nz := Vector3(-t.y, 0, t.x) * size.z * 0.5
	var top := Vector3(0, size.y, 0)
	var c := [p - tx - nz, p + tx - nz, p + tx + nz, p - tx + nz]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var out: Vector3 = ((a + b) * 0.5 - p).normalized()
		kit.quad(a, b, b + top, a + top, out)
	kit.quad(c[0] + top, c[1] + top, c[2] + top, c[3] + top, Vector3.UP)


## The city's welcome sign: a dark stone wall on a lighter plinth, with a cap,
## its lettering a picture on the face that looks toward `facing`.
func _welcome_sign(p: Vector2, facing: float, texture: String) -> void:
	var root := Node3D.new()
	root.name = "WelcomeSign"
	root.position = _on_ground(p)
	root.rotation.y = _yaw_for_bearing(facing)
	add_child(root)
	# Built facing -Z (the bearing), across X.
	var stone := MeshKit.new()
	stone.use_color = true
	var w := 7.6
	stone.color = Color(0.42, 0.4, 0.37)
	_block(stone, Vector3(0, -0.4, 0), Vector3(w + 0.5, 0.75, 1.0), Vector2.RIGHT)
	stone.color = Color(0.2, 0.17, 0.15)
	_block(stone, Vector3(0, 0.35, 0), Vector3(w, 2.15, 0.7), Vector2.RIGHT)
	stone.color = Color(0.45, 0.43, 0.4)
	_block(stone, Vector3(0, 2.5, 0), Vector3(w + 0.25, 0.18, 0.85), Vector2.RIGHT)
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = ModelLod.finish_kits([[stone, _vertex_colour_material(0.9, 0.0)]])
	root.add_child(mi)
	_face(root, texture, Vector3(0, 1.45, -0.356), w - 0.5, (w - 0.5) / 4.0)
	_box_body(root, Vector3(0, -0.4, 0), Vector3(w + 0.5, 3.1, 1.0), 0.0, true)


## A picture on a flat quad facing -Z of `root`, centred at c; with `back`
## set, the same picture (the right way round) on a quad facing +Z at c's
## mirror through the root, for a board that shows both ways.
func _face(root: Node3D, texture: String, c: Vector3, w: float, h: float, back := false) -> void:
	var tex := load("res://textures/signs/%s.png" % texture) as Texture2D
	if tex == null:
		return
	var kit := MeshKit.new()
	var x := Vector3(w * 0.5, 0, 0)
	var y := Vector3(0, h * 0.5, 0)
	# Seen from the -Z side the viewer's right is -X, so the picture's left
	# edge (u = 0) goes at +X.
	kit.quad(c + x - y, c - x - y, c - x + y, c + x + y, Vector3.FORWARD, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	if back:
		var b := Vector3(c.x, c.y, -c.z)
		kit.quad(b - x - y, b + x - y, b + x + y, b - x + y, Vector3.BACK, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.7
	m.alpha_scissor_threshold = 0.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit_indexed(null, m)
	root.add_child(mi)
	# docs/world_art.md W4: a draw distance from size, longer for a sign
	# drivers read coming up to it.
	WorldLod.limit(mi, maxf(w, h) * 3.0)


## A sign on a galvanised post, with an optional small marker below it.
func _lane_sign(p: Vector2, facing: float, m: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "LaneSign"
	root.position = _on_ground(p)
	root.rotation.y = _yaw_for_bearing(facing)
	add_child(root)
	var w := float(m.get("width", 1.2))
	var h := float(m.get("height", 1.6))
	var bottom := float(m.get("bottom", 2.0))
	var steel := MeshKit.new()
	steel.use_color = true
	steel.color = Color(0.6, 0.62, 0.62)
	_block(steel, Vector3(0, -0.3, 0.04), Vector3(0.08, bottom + h + 0.3, 0.08), Vector2.RIGHT)
	# The plates' grey backs.
	_block(steel, Vector3(0, bottom, -0.01), Vector3(w, h, 0.02), Vector2.RIGHT)
	var marker := str(m.get("marker", ""))
	if marker != "":
		_block(steel, Vector3(0, bottom - 0.75, -0.01), Vector3(0.6, 0.6, 0.02), Vector2.RIGHT)
	var mi := MeshInstance3D.new()
	mi.mesh = steel.commit_indexed(null, _vertex_colour_material(0.5, 0.5))
	root.add_child(mi)
	WorldLod.limit(mi, bottom + h + 2.0)
	_face(root, str(m.get("texture", "")), Vector3(0, bottom + h * 0.5, -0.022), w, h)
	if marker != "":
		_face(root, marker, Vector3(0, bottom - 0.45, -0.022), 0.6, 0.6)
	_box_body(root, Vector3.ZERO, Vector3(0.12, bottom + h, 0.12), 0.0, true)


## A solid box standing at p (in `root`'s space if local, else the world's),
## turned `yaw` about y.
func _box_body(root: Node3D, p: Vector3, size: Vector3, yaw: float, local := false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	body.rotation.y = yaw
	body.position = p if local else p - root.position
	root.add_child(body)


## A business's pole sign: a dark square pole with its boards stacked down
## from the top, each a slim box with its picture on both faces.
func _pylon_sign(p: Vector2, facing: float, m: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "PylonSign"
	root.position = _on_ground(p)
	root.rotation.y = _yaw_for_bearing(facing)
	add_child(root)
	var top := float(m.get("height", 7.0))
	var kit := MeshKit.new()
	kit.use_color = true
	kit.color = Color(0.16, 0.16, 0.17)
	var panels: Array = m.get("panels", [])
	var y := top
	var lowest := top
	for pd: Dictionary in panels:
		lowest = y - float(pd.get("height", 1.0))
		y = lowest - 0.15
	_block(kit, Vector3(0, -0.3, 0), Vector3(0.35, lowest + 0.4, 0.35), Vector2.RIGHT)
	y = top
	var depth := 0.36
	for pd: Dictionary in panels:
		var w := float(pd.get("width", 2.0))
		var h := float(pd.get("height", 1.0))
		# The board's edge (the faces go on its two sides), a little inset
		# so rounded corners don't show a square box behind them.
		_block(kit, Vector3(0, y - h + h * 0.08, 0), Vector3(w * 0.92, h * 0.84, depth - 0.02), Vector2.RIGHT)
		_face(root, str(pd.get("texture", "")), Vector3(0, y - h * 0.5, -depth * 0.5), w, h, true)
		y -= h + 0.15
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit_indexed(null, _vertex_colour_material(0.6, 0.3))
	root.add_child(mi)
	WorldLod.limit(mi)
	_box_body(root, Vector3.ZERO, Vector3(0.4, lowest, 0.4), 0.0, true)

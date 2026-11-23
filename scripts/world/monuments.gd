class_name Monuments
extends Node3D
## One-off things placed by hand from map_config.json "monuments": a war
## memorial (bronze soldiers on a granite pedestal) and flagpoles. Each entry
## has "kind", "at" [latitude, longitude] and, for a memorial, "facing" (a
## compass bearing, 0 = north, 90 = east, as in field notes). A flagpole
## takes "flag" (a picture in textures/flags/) and "height" in metres.
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
		if at.size() < 2:
			continue
		var p := data.projection.to_ground(float(at[1]), float(at[0]))
		data.keep_clear.append(p)
		match str(m.get("kind", "")):
			"war_memorial":
				_war_memorial(p, float(m.get("facing", 0.0)))
			"flagpole":
				_flagpole(p, str(m.get("flag", "canada")), float(m.get("height", 12.0)))


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

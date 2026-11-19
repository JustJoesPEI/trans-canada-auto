class_name HumanoidModel
extends Node3D
## A plain low-poly person built from primitives, with a procedural walk.
##
## Normal adult proportions (about 1.75 m, head about 1/7.5 of height), no
## rig or imported animation. Used for the player now and pedestrians later:
## give each one a different `appearance`, then call set_motion() every frame.
## Faces -Z, feet at y = 0.

## Meshes are shared by every person in the scene.
static var _mesh_cache := {}

@export var height := 1.75
@export var skin := Color(0.87, 0.69, 0.57)
@export var hair := Color(0.23, 0.16, 0.11)
@export var top := Color(0.22, 0.36, 0.52)
@export var bottom := Color(0.2, 0.21, 0.25)
@export var shoes := Color(0.12, 0.11, 0.1)

var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _body: Node3D
var _phase := 0.0
var _speed := 0.0
var _idle_t := 0.0


func _ready() -> void:
	_build()


## Pick colours before the model is added to the tree.
func set_appearance(appearance: Dictionary) -> void:
	skin = appearance.get("skin", skin)
	hair = appearance.get("hair", hair)
	top = appearance.get("top", top)
	bottom = appearance.get("bottom", bottom)
	shoes = appearance.get("shoes", shoes)


## A random everyday look, seeded so a pedestrian keeps theirs.
static func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var skins := [Color(0.95, 0.8, 0.69), Color(0.87, 0.69, 0.57), Color(0.76, 0.57, 0.43), Color(0.58, 0.4, 0.28), Color(0.4, 0.27, 0.19)]
	var hairs := [Color(0.1, 0.08, 0.07), Color(0.23, 0.16, 0.11), Color(0.45, 0.3, 0.18), Color(0.72, 0.58, 0.36), Color(0.6, 0.6, 0.6)]
	var tops := [Color(0.22, 0.36, 0.52), Color(0.6, 0.18, 0.16), Color(0.25, 0.42, 0.3), Color(0.85, 0.83, 0.78), Color(0.3, 0.3, 0.32), Color(0.75, 0.58, 0.2), Color(0.45, 0.3, 0.5)]
	var bottoms := [Color(0.2, 0.21, 0.25), Color(0.18, 0.25, 0.4), Color(0.4, 0.35, 0.28), Color(0.12, 0.12, 0.12)]
	return {
		"skin": skins[rng.randi() % skins.size()],
		"hair": hairs[rng.randi() % hairs.size()],
		"top": tops[rng.randi() % tops.size()],
		"bottom": bottoms[rng.randi() % bottoms.size()],
		"shoes": Color(0.1, 0.1, 0.1).lerp(Color(0.4, 0.3, 0.2), rng.randf()),
	}


## speed in m/s along the ground. The stride follows it, from a stroll to a run.
func set_motion(speed: float) -> void:
	_speed = speed


func _process(delta: float) -> void:
	if _hip_l == null:
		return
	var s := clampf(_speed, 0.0, 8.0)
	var running := clampf((s - 2.2) / 2.5, 0.0, 1.0)
	# Steps per second rise with speed; stride length does the rest.
	_phase += delta * s * lerpf(3.5, 1.6, running) # about 1.8 steps a second walking, 2.8 running
	var amount := clampf(s / 1.4, 0.0, 1.0)
	var swing := lerpf(0.45, 0.85, running) * amount
	var w := sin(_phase)
	_hip_l.rotation.x = w * swing
	_hip_r.rotation.x = -w * swing
	_knee_l.rotation.x = -maxf(0.0, -cos(_phase)) * swing * 1.4
	_knee_r.rotation.x = -maxf(0.0, cos(_phase)) * swing * 1.4
	_shoulder_l.rotation.x = -w * swing * 0.8
	_shoulder_r.rotation.x = w * swing * 0.8
	var elbow := 0.25 + running * 1.0 # forearm bends forward
	_elbow_l.rotation.x = elbow
	_elbow_r.rotation.x = elbow
	_idle_t += delta
	var bob := absf(cos(_phase)) * 0.035 * amount + sin(_idle_t * 1.6) * 0.004 * (1.0 - amount)
	_body.position.y = bob
	_body.rotation.x = -0.12 * running


# --- construction ----------------------------------------------------------------------------

func _build() -> void:
	var k := height / 1.75 # everything below is in metres for a 1.75 m person
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var m_skin := _mat(skin)
	var m_top := _mat(top)
	var m_bottom := _mat(bottom)
	var m_shoes := _mat(shoes)
	var m_hair := _mat(hair)

	var hip_y := 0.92 * k
	var shoulder_y := 1.43 * k
	# Pelvis and torso.
	_part(_body, _box(Vector3(0.34, 0.2, 0.2) * k), m_bottom, Vector3(0, hip_y + 0.02 * k, 0))
	_part(_body, _box(Vector3(0.38, 0.42, 0.22) * k), m_top, Vector3(0, hip_y + 0.31 * k, 0))
	_part(_body, _box(Vector3(0.44, 0.12, 0.24) * k), m_top, Vector3(0, shoulder_y - 0.04 * k, 0))
	# Neck and head.
	_part(_body, _cyl(0.055 * k, 0.1 * k), m_skin, Vector3(0, shoulder_y + 0.06 * k, 0))
	var head := _part(_body, _sphere(0.105 * k, 0.24 * k), m_skin, Vector3(0, 1.62 * k, 0))
	_part(head, _sphere(0.11 * k, 0.15 * k), m_hair, Vector3(0, 0.055 * k, 0.012 * k))
	# Nose, so you can tell which way someone faces from above.
	_part(head, _box(Vector3(0.03, 0.04, 0.04) * k), m_skin, Vector3(0, -0.01 * k, -0.105 * k))

	# Legs: hip pivot -> thigh, knee pivot -> shin, foot.
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side * k, hip_y, 0)
		_body.add_child(hip)
		_part(hip, _cyl(0.075 * k, 0.46 * k), m_bottom, Vector3(0, -0.23 * k, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.46 * k, 0)
		hip.add_child(knee)
		_part(knee, _cyl(0.06 * k, 0.42 * k), m_bottom, Vector3(0, -0.21 * k, 0))
		_part(knee, _box(Vector3(0.11, 0.07, 0.26) * k), m_shoes, Vector3(0, -0.42 * k, -0.05 * k))
		if side < 0.0:
			_hip_l = hip
			_knee_l = knee
		else:
			_hip_r = hip
			_knee_r = knee

	# Arms: shoulder pivot -> upper arm, elbow pivot -> forearm and hand.
	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.23 * side * k, shoulder_y - 0.04 * k, 0)
		_body.add_child(shoulder)
		_part(shoulder, _cyl(0.05 * k, 0.3 * k), m_top, Vector3(0, -0.15 * k, 0))
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.3 * k, 0)
		shoulder.add_child(elbow)
		_part(elbow, _cyl(0.042 * k, 0.26 * k), m_skin, Vector3(0, -0.13 * k, 0))
		_part(elbow, _sphere(0.05 * k, 0.1 * k), m_skin, Vector3(0, -0.29 * k, 0))
		if side < 0.0:
			_shoulder_l = shoulder
			_elbow_l = elbow
		else:
			_shoulder_r = shoulder
			_elbow_r = elbow


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> Mesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _cyl(radius: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [radius, h]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius * 0.9
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _sphere(radius: float, h: float) -> Mesh:
	var key := "s%.3f/%.3f" % [radius, h]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = h
		m.radial_segments = 10
		m.rings = 6
		if h < radius * 1.9:
			m.is_hemisphere = true
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _mat(c: Color) -> Material:
	return Materials.get_shared().plain(c, 0.85)

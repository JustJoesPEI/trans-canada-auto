class_name HumanoidModel
extends Node3D
## A low-poly person built from rounded primitives, with a procedural walk.
##
## Normal adult proportions (about 1.75 m, head about 1/7.5 of height), no
## rig or imported animation. Used for the player now and pedestrians later:
## give each one a different look with set_appearance(), then call
## set_motion() every physics frame. Faces -Z, feet at y = 0.
##
## The walk is driven by speed, not by a fixed clip: cadence and stride are
## worked out so the feet roughly keep pace with the ground, and it blends
## smoothly from standing, to a stroll, to a walk, to a run.

## Meshes are shared by every person in the scene.
static var _mesh_cache := {}

@export var height := 1.75
@export var skin := Color(0.87, 0.69, 0.57)
@export var hair := Color(0.23, 0.16, 0.11)
@export var top := Color(0.66, 0.16, 0.13) ## jacket: red, so the player reads against grey streets
@export var under := Color(0.82, 0.8, 0.74) ## shirt showing at the collar
@export var bottom := Color(0.21, 0.25, 0.34) ## trousers
@export var shoes := Color(0.16, 0.12, 0.1)

const LEG := 0.9 # hip to sole, metres, for a 1.75 m person

# Joints. Rotations are in radians; +x swings a limb forward (toward -Z).
var _hips: Node3D
var _spine: Node3D
var _neck: Node3D
var _hip := [null, null] # [left, right]
var _knee := [null, null]
var _ankle := [null, null]
var _shoulder := [null, null]
var _elbow := [null, null]

var _phase := 0.0
var _speed := 0.0 # smoothed
var _target_speed := 0.0
var _accel := 0.0 # smoothed, m/s per second along facing
var _turn := 0.0 # smoothed, radians per second
var _target_accel := 0.0
var _target_turn := 0.0
var _t := 0.0
var _k := 1.0 # scale factor for height


func _ready() -> void:
	_build()


## Pick colours before the model is added to the tree.
func set_appearance(appearance: Dictionary) -> void:
	skin = appearance.get("skin", skin)
	hair = appearance.get("hair", hair)
	top = appearance.get("top", top)
	under = appearance.get("under", under)
	bottom = appearance.get("bottom", bottom)
	shoes = appearance.get("shoes", shoes)
	height = appearance.get("height", height)


## A random everyday look, seeded so a pedestrian keeps theirs.
static func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var skins := [Color(0.95, 0.8, 0.69), Color(0.87, 0.69, 0.57), Color(0.76, 0.57, 0.43), Color(0.58, 0.4, 0.28), Color(0.4, 0.27, 0.19)]
	var hairs := [Color(0.1, 0.08, 0.07), Color(0.23, 0.16, 0.11), Color(0.45, 0.3, 0.18), Color(0.72, 0.58, 0.36), Color(0.62, 0.6, 0.58)]
	var tops := [Color(0.2, 0.33, 0.45), Color(0.55, 0.18, 0.16), Color(0.25, 0.38, 0.28), Color(0.78, 0.74, 0.66), Color(0.25, 0.25, 0.27), Color(0.7, 0.52, 0.22), Color(0.4, 0.28, 0.42)]
	var bottoms := [Color(0.21, 0.25, 0.34), Color(0.17, 0.2, 0.3), Color(0.4, 0.35, 0.28), Color(0.12, 0.12, 0.12), Color(0.33, 0.33, 0.3)]
	return {
		"skin": skins[rng.randi() % skins.size()],
		"hair": hairs[rng.randi() % hairs.size()],
		"top": tops[rng.randi() % tops.size()],
		"bottom": bottoms[rng.randi() % bottoms.size()],
		"shoes": Color(0.1, 0.1, 0.1).lerp(Color(0.45, 0.33, 0.22), rng.randf()),
		"height": rng.randf_range(1.6, 1.88),
	}


## Call every physics frame.
## speed: m/s over the ground. accel: m/s² along the way the person faces
## (positive when speeding up). turn: radians per second, positive to the left.
func set_motion(speed: float, accel := 0.0, turn := 0.0) -> void:
	_target_speed = speed
	_target_accel = accel
	_target_turn = turn


func _process(delta: float) -> void:
	if _hips == null:
		return
	_t += delta
	_speed = lerpf(_speed, _target_speed, 1.0 - exp(-12.0 * delta))
	_accel = lerpf(_accel, clampf(_target_accel, -8.0, 8.0), 1.0 - exp(-6.0 * delta))
	_turn = lerpf(_turn, clampf(_target_turn, -6.0, 6.0), 1.0 - exp(-8.0 * delta))
	var s := maxf(0.0, _speed) / _k

	var moving := clampf(s / 0.9, 0.0, 1.0) # 0 standing .. 1 walking
	var run := smoothstep(2.6, 4.4, s) # 0 walking .. 1 running
	# Cycles per second (two steps each): about 1.9 steps/s walking, 2.9 running.
	var cadence := clampf(0.55 + 0.22 * s, 0.6, 1.45)
	_phase = fmod(_phase + TAU * cadence * delta * moving, TAU)
	# Hip swing that roughly matches stride to speed.
	# (Scaled down a little: the knee and ankle bends add to the stride.)
	var swing := asin(clampf(s / (4.0 * LEG * cadence), 0.0, 0.72)) * moving * lerpf(0.78, 0.72, run)

	for side in 2:
		var p := _phase + (PI if side == 1 else 0.0)
		var forward := sin(p) # +1 leg fully forward
		var swinging := maxf(0.0, cos(p)) # leg travelling forward through the air
		var hip_x := forward * swing + run * 0.15
		var knee := -(0.06 + swinging * lerpf(0.75, 1.7, run) * swing * 1.6) * moving
		knee -= run * 0.25 * maxf(0.0, -forward)
		var ankle := -(hip_x + knee) * 0.85
		if forward < -0.4:
			ankle += (forward + 0.4) * -0.5 * moving # push off with the toe
		(_hip[side] as Node3D).rotation = Vector3(hip_x, 0.0, (-0.03 if side == 0 else 0.03))
		(_knee[side] as Node3D).rotation.x = knee
		(_ankle[side] as Node3D).rotation.x = ankle

		# Arms swing with the opposite leg; elbows bend more when running.
		var arm_swing := lerpf(0.32, 0.75, run) * moving * clampf(swing / 0.45, 0.4, 1.2)
		var other := sin(p + PI)
		(_shoulder[side] as Node3D).rotation = Vector3(other * arm_swing - run * 0.1, 0.0, (-0.07 if side == 0 else 0.07) * (1.0 + run))
		(_elbow[side] as Node3D).rotation.x = 0.15 + moving * 0.2 + run * 1.15 + maxf(0.0, other) * 0.25 * moving

	# Hips: bob (highest mid-stance walking, mid-flight running), sway, twist.
	var bob_amp := lerpf(0.022, -0.045, run) * moving
	var breathe := sin(_t * 1.7) * 0.006 * (1.0 - moving)
	var shift := sin(_t * 0.45) * 0.012 * (1.0 - moving)
	_hips.position = Vector3(shift, LEG * _k - 0.015 * moving - 0.07 * run + bob_amp * cos(2.0 * _phase), 0.0)
	_hips.rotation = Vector3(0.0, 0.11 * sin(_phase) * moving, 0.045 * sin(_phase) * moving * (1.0 - run * 0.5))
	# Spine: lean forward with speed and acceleration, counter-twist the shoulders.
	var lean := 0.04 * moving + 0.2 * run + clampf(_accel * 0.025, -0.12, 0.15)
	_spine.rotation = Vector3(-lean + breathe, -0.2 * sin(_phase) * moving, 0.0)
	_spine.scale = Vector3(1.0, 1.0 + breathe * 2.0, 1.0)
	# Keep the head steady and looking ahead.
	_neck.rotation = Vector3(lean * 0.7, 0.09 * sin(_phase) * moving, 0.0)
	# Lean into turns, more at speed.
	rotation.z = clampf(_turn * s * 0.035, -0.22, 0.22)


# --- construction ----------------------------------------------------------------------------

func _build() -> void:
	var k := height / 1.75 # everything below is in metres for a 1.75 m person
	_k = k
	var m_skin := _mat(skin)
	var m_top := _mat(top)
	var m_under := _mat(under)
	var m_bottom := _mat(bottom)
	var m_shoes := _mat(shoes)
	var m_hair := _mat(hair)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position.y = LEG * k
	add_child(_hips)
	# Pelvis, wider than deep.
	_part(_hips, _capsule(0.12, 0.34), m_bottom, Vector3(0, 0.02, 0) * k, Vector3(0, 0, PI * 0.5), Vector3(1.0, 1.0, 0.8) * k)
	# Belt line.
	_part(_hips, _capsule(0.125, 0.33), _mat(bottom.darkened(0.35)), Vector3(0, 0.09, 0) * k, Vector3(0, 0, PI * 0.5), Vector3(1.0, 0.25, 0.8) * k)

	_spine = Node3D.new()
	_spine.name = "Spine"
	_spine.position = Vector3(0, 0.1, 0) * k
	_hips.add_child(_spine)
	# Jacket: a waist and a broader chest, slightly flattened front to back.
	_part(_spine, _capsule(0.15, 0.42), m_top, Vector3(0, 0.16, 0) * k, Vector3.ZERO, Vector3(1.0, 1.0, 0.72) * k)
	_part(_spine, _capsule(0.19, 0.4), m_top, Vector3(0, 0.36, 0) * k, Vector3.ZERO, Vector3(1.05, 1.0, 0.68) * k)
	# Shoulders, rounded over the top.
	_part(_spine, _capsule(0.075, 0.46), m_top, Vector3(0, 0.49, 0) * k, Vector3(0, 0, PI * 0.5), Vector3(1.0, 1.0, 0.9) * k)
	# Zip line and collar.
	_part(_spine, _box(Vector3(0.012, 0.42, 0.01)), _mat(top.darkened(0.4)), Vector3(0, 0.3, -0.13) * k, Vector3(0.08, 0, 0), Vector3.ONE * k)
	_part(_spine, _capsule(0.06, 0.16), m_under, Vector3(0, 0.54, -0.02) * k, Vector3(0, 0, PI * 0.5), Vector3(1.0, 1.0, 1.0) * k)

	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0, 0.52, 0) * k
	_spine.add_child(_neck)
	_part(_neck, _capsule(0.05, 0.14), m_skin, Vector3(0, 0.04, 0) * k)
	var head := _part(_neck, _sphere(0.1), m_skin, Vector3(0, 0.12, -0.005) * k, Vector3.ZERO, Vector3(0.95, 1.15, 1.05) * k)
	# Hair: a cap over the top and back of the head.
	_part(head, _sphere(0.1), m_hair, Vector3(0, 0.025, 0.012), Vector3(-0.25, 0, 0), Vector3(1.06, 0.95, 1.06))
	_part(head, _sphere(0.022), m_skin, Vector3(0, -0.015, -0.1), Vector3.ZERO, Vector3(0.8, 1.0, 1.0)) # nose
	for side: float in [-1.0, 1.0]:
		_part(head, _sphere(0.024), m_skin, Vector3(0.095 * side, -0.005, 0.005), Vector3.ZERO, Vector3(0.5, 1.0, 0.8)) # ears
		_part(head, _sphere(0.012), _mat(Color(0.12, 0.1, 0.09)), Vector3(0.035 * side, 0.01, -0.095)) # eyes

	# Legs: hip -> thigh, knee -> shin, ankle -> shoe.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := Node3D.new()
		hip.position = Vector3(0.095 * side, 0.0, 0) * k
		_hips.add_child(hip)
		_part(hip, _capsule(0.085, 0.5), m_bottom, Vector3(0, -0.22, 0) * k, Vector3.ZERO, Vector3(1.0, 1.0, 1.05) * k)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.44, 0) * k
		hip.add_child(knee)
		_part(knee, _capsule(0.068, 0.46), m_bottom, Vector3(0, -0.2, 0) * k, Vector3.ZERO, Vector3.ONE * k)
		var ankle := Node3D.new()
		ankle.position = Vector3(0, -0.38, 0) * k
		knee.add_child(ankle)
		# Shoe: a rounded block, longer in front of the ankle than behind.
		_part(ankle, _capsule(0.055, 0.27), m_shoes, Vector3(0, -0.035, -0.055) * k, Vector3(PI * 0.5, 0, 0), Vector3(1.0, 1.0, 0.75) * k)
		_part(ankle, _box(Vector3(0.1, 0.022, 0.27)), _mat(Color(0.85, 0.83, 0.78)), Vector3(0, -0.075, -0.055) * k, Vector3.ZERO, Vector3.ONE * k) # sole
		_hip[i] = hip
		_knee[i] = knee
		_ankle[i] = ankle

	# Arms: shoulder -> sleeve, elbow -> forearm sleeve, cuff, hand.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.215 * side, 0.48, 0) * k
		_spine.add_child(shoulder)
		_part(shoulder, _capsule(0.062, 0.34), m_top, Vector3(0, -0.14, 0) * k, Vector3.ZERO, Vector3.ONE * k)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.28, 0) * k
		shoulder.add_child(elbow)
		_part(elbow, _capsule(0.052, 0.3), m_top, Vector3(0, -0.12, 0) * k, Vector3.ZERO, Vector3.ONE * k)
		_part(elbow, _capsule(0.04, 0.1), m_skin, Vector3(0, -0.27, 0) * k, Vector3.ZERO, Vector3.ONE * k) # wrist
		_part(elbow, _sphere(0.05), m_skin, Vector3(0, -0.33, -0.005) * k, Vector3.ZERO, Vector3(0.65, 1.0, 0.95) * k) # hand
		_shoulder[i] = shoulder
		_elbow[i] = elbow


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _capsule(radius: float, h: float) -> Mesh:
	var key := "c%.3f/%.3f" % [radius, h]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(h, radius * 2.0)
		m.radial_segments = 12
		m.rings = 4
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _sphere(radius: float) -> Mesh:
	var key := "s%.3f" % radius
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 14
		m.rings = 8
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _box(size: Vector3) -> Mesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func _mat(c: Color) -> Material:
	return Materials.get_shared().plain(c, 0.85)
